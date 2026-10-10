import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'coach_request.dart';

export 'coach_request.dart';

/// Today's Coach requests for this user. Every model call counts, retries
/// included.
class CoachQuota {
  final int used;
  final int limit;
  final DateTime? resetsAt;

  const CoachQuota({required this.used, required this.limit, this.resetsAt});

  int get remaining => (limit - used).clamp(0, limit);

  static CoachQuota? tryParse(Object? json) {
    if (json is! Map) return null;
    final used = json['used'];
    final limit = json['limit'];
    if (used is! num || limit is! num) return null;
    final resetsAt = json['resetsAt'];
    return CoachQuota(
      used: used.toInt(),
      limit: limit.toInt(),
      resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt) : null,
    );
  }
}

/// Why a request produced no model output. Each kind has one line of copy.
enum CoachFailureKind {
  /// The request never got a response.
  noConnection,

  /// 401: the session is missing or expired.
  unauthenticated,

  /// 413 / 422: the proxy refused the body.
  badRequest,

  /// 426: this build's contract version is no longer served.
  updateRequired,

  /// 429: this user's daily requests are used up.
  userQuota,

  /// 503 `busy`: the shared daily cap, or the model is rate limited.
  busy,

  /// 503 `unavailable`, or any status the table doesn't name.
  unavailable,

  /// 502, a timeout, or a 200 this build can't read.
  upstream;

  String get message => switch (this) {
    noConnection =>
      'The Coach needs a connection. Your plans still work offline.',
    unauthenticated => 'Sign in again to use the Coach.',
    badRequest => 'Something went wrong. Try a shorter message.',
    updateRequired => 'Update OpenGym to keep using the Coach.',
    userQuota => "You've used today's Coach requests. They reset tomorrow.",
    busy => 'The Coach is busy right now. Try again later.',
    unavailable => 'The Coach is unavailable right now.',
    upstream => "The Coach couldn't answer. Try again.",
  };
}

sealed class CoachClientResult {
  const CoachClientResult();
}

/// The model's raw output, still unvalidated.
class CoachAnswer extends CoachClientResult {
  final String output;
  final String? model;
  final CoachQuota? quota;

  const CoachAnswer({required this.output, this.model, this.quota});
}

class CoachFailure extends CoachClientResult {
  final CoachFailureKind kind;

  /// Sent with `user_quota`, so the chat can show the count.
  final CoachQuota? quota;

  const CoachFailure(this.kind, {this.quota});
}

/// The proxy call. Never throws: every outcome is a [CoachClientResult].
abstract interface class CoachClient {
  Future<CoachClientResult> send(CoachRequest request);
}

/// [CoachClient] over `supabase_flutter`, which attaches the user's token.
class SupabaseCoachClient implements CoachClient {
  /// Longer than the proxy's two 40-second model attempts.
  static const Duration timeout = Duration(seconds: 100);

  final FunctionsClient Function() _functions;

  SupabaseCoachClient({FunctionsClient Function()? functions})
    : _functions = functions ?? (() => SupabaseService.client.functions);

  @override
  Future<CoachClientResult> send(CoachRequest request) async {
    try {
      final response = await _functions()
          .invoke('coach', body: request.toJson())
          .timeout(timeout);
      return parseSuccess(response.data);
    } on FunctionException catch (error) {
      return parseError(error.status, error.details);
    } on TimeoutException {
      return const CoachFailure(CoachFailureKind.upstream);
    } on SocketException {
      return const CoachFailure(CoachFailureKind.noConnection);
    } on http.ClientException {
      return const CoachFailure(CoachFailureKind.noConnection);
    } on FormatException {
      // A 2xx labelled JSON that doesn't parse.
      return const CoachFailure(CoachFailureKind.upstream);
    } catch (error) {
      debugPrint('Coach request failed: ${error.runtimeType}');
      return const CoachFailure(CoachFailureKind.unavailable);
    }
  }

  /// A 2xx body. One stamped with any other contract version, or without
  /// an output string, is unreadable by this build.
  static CoachClientResult parseSuccess(Object? data) {
    final body = _decode(data);
    if (body == null ||
        body['contractVersion'] != kCoachContractVersion ||
        body['output'] is! String) {
      return const CoachFailure(CoachFailureKind.upstream);
    }
    final model = body['model'];
    return CoachAnswer(
      output: body['output'] as String,
      model: model is String ? model : null,
      quota: CoachQuota.tryParse(body['quota']),
    );
  }

  /// A non-2xx status. The status decides where the table is unambiguous,
  /// because the Supabase gateway answers some failures (an expired JWT, a
  /// cold-start error) without the proxy's `error` field.
  static CoachFailure parseError(int status, Object? details) {
    final body = _decode(details);
    final code = body?['error'];
    return switch (status) {
      // Newer clients report a request that never got a response as 0.
      0 => const CoachFailure(CoachFailureKind.noConnection),
      401 => const CoachFailure(CoachFailureKind.unauthenticated),
      413 || 422 => const CoachFailure(CoachFailureKind.badRequest),
      426 => const CoachFailure(CoachFailureKind.updateRequired),
      429 => CoachFailure(
        CoachFailureKind.userQuota,
        quota: CoachQuota.tryParse(body?['quota']),
      ),
      502 => const CoachFailure(CoachFailureKind.upstream),
      503 when code == 'busy' => const CoachFailure(CoachFailureKind.busy),
      _ => const CoachFailure(CoachFailureKind.unavailable),
    };
  }

  static Map<String, dynamic>? _decode(Object? data) {
    Object? value = data;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return value is Map<String, dynamic> ? value : null;
  }
}

/// Whether the Supabase host resolves, so the Coach can say up front that it
/// needs a connection. The web has no lookup; a failed request says it there.
Future<bool> probeCoachConnection() async {
  if (kIsWeb || !SupabaseService.isConfigured) return true;
  try {
    final host = Uri.parse(SupabaseService.supabaseUrl).host;
    final addresses = await InternetAddress.lookup(
      host,
    ).timeout(const Duration(seconds: 3));
    return addresses.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}
