import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/services/coach/coach_client.dart';

const CoachRequest _request = CoachRequest(
  context: {'today': '2026-10-09'},
  messages: [CoachMessage.user('Build me a 4-day upper/lower')],
);

/// A client whose proxy answers [status] with [body] as JSON, recording the
/// request it was sent.
(SupabaseCoachClient, List<http.Request>) _client(
  int status,
  Object? body, {
  String contentType = 'application/json',
}) {
  final sent = <http.Request>[];
  final mock = MockClient((request) async {
    sent.add(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': contentType},
    );
  });
  final functions = FunctionsClient(
    'https://example.supabase.co/functions/v1',
    const {},
    httpClient: mock,
  );
  return (SupabaseCoachClient(functions: () => functions), sent);
}

SupabaseCoachClient _throwing(Object error) {
  final functions = FunctionsClient(
    'https://example.supabase.co/functions/v1',
    const {},
    httpClient: MockClient((_) async => throw error),
  );
  return SupabaseCoachClient(functions: () => functions);
}

Future<CoachFailureKind> _failure(int status, Object? body) async {
  final (client, _) = _client(status, body);
  final result = await client.send(_request);
  expect(result, isA<CoachFailure>());
  return (result as CoachFailure).kind;
}

void main() {
  group('request', () {
    test('sends contract version, context, and messages', () async {
      final (client, sent) = _client(200, {
        'contractVersion': 1,
        'output': '{"reply":"Hi","proposal":null}',
      });
      await client.send(_request);

      final request = sent.single;
      expect(request.url.path, endsWith('/coach'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['contractVersion'], kCoachContractVersion);
      expect(body['context'], {'today': '2026-10-09'});
      expect(body['messages'], [
        {'role': 'user', 'content': 'Build me a 4-day upper/lower'},
      ]);
      expect(body.containsKey('retry'), isFalse);
    });

    test('a retry carries the previous output and the errors', () async {
      final (client, sent) = _client(200, {
        'contractVersion': 1,
        'output': '{}',
      });
      await client.send(
        const CoachRequest(
          context: {},
          messages: [CoachMessage.user('Hi')],
          retry: CoachRetry(previousOutput: 'bad', errors: ['reply: missing']),
        ),
      );

      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['retry'], {
        'previousOutput': 'bad',
        'errors': ['reply: missing'],
      });
    });
  });

  group('success', () {
    test('returns the output unparsed, with the quota', () async {
      final (client, _) = _client(200, {
        'contractVersion': 1,
        'output': '{"reply":"Hi","proposal":null}',
        'model': 'gemini-3.5-flash-lite',
        'quota': {'used': 4, 'limit': 20, 'resetsAt': '2026-10-10T07:00:00Z'},
      });
      final result = await client.send(_request);

      expect(result, isA<CoachAnswer>());
      final answer = result as CoachAnswer;
      expect(answer.output, '{"reply":"Hi","proposal":null}');
      expect(answer.model, 'gemini-3.5-flash-lite');
      expect(answer.quota!.used, 4);
      expect(answer.quota!.limit, 20);
      expect(answer.quota!.remaining, 16);
      expect(answer.quota!.resetsAt, DateTime.utc(2026, 10, 10, 7));
    });

    test('rejects a response stamped with another contract version', () async {
      final (client, _) = _client(200, {'contractVersion': 2, 'output': '{}'});
      final result = await client.send(_request);
      expect((result as CoachFailure).kind, CoachFailureKind.upstream);
    });

    test('rejects a response without a version or output', () async {
      expect(await _failure(200, {'output': '{}'}), CoachFailureKind.upstream);
      expect(
        await _failure(200, {'contractVersion': 1}),
        CoachFailureKind.upstream,
      );
    });

    test('a body that is not JSON is an upstream failure', () async {
      final (client, _) = _client(200, 'not json', contentType: 'text/plain');
      final result = await client.send(_request);
      expect((result as CoachFailure).kind, CoachFailureKind.upstream);
    });
  });

  group('errors map to the doc table', () {
    test('401 unauthenticated, with or without the proxy body', () async {
      expect(
        await _failure(401, {'error': 'unauthenticated'}),
        CoachFailureKind.unauthenticated,
      );
      // The gateway's own JWT rejection has no `error` field.
      expect(
        await _failure(401, {'code': 401, 'message': 'Invalid JWT'}),
        CoachFailureKind.unauthenticated,
      );
    });

    test('413 and 422 bad request', () async {
      expect(
        await _failure(413, {'error': 'bad_request'}),
        CoachFailureKind.badRequest,
      );
      expect(
        await _failure(422, {'error': 'bad_request'}),
        CoachFailureKind.badRequest,
      );
    });

    test('426 update required', () async {
      expect(
        await _failure(426, {'error': 'update_required'}),
        CoachFailureKind.updateRequired,
      );
    });

    test('429 user quota carries the quota', () async {
      final (client, _) = _client(429, {
        'error': 'user_quota',
        'quota': {'used': 20, 'limit': 20, 'resetsAt': '2026-10-10T07:00:00Z'},
      });
      final result = await client.send(_request) as CoachFailure;
      expect(result.kind, CoachFailureKind.userQuota);
      expect(result.quota!.remaining, 0);
    });

    test('503 busy and unavailable', () async {
      expect(await _failure(503, {'error': 'busy'}), CoachFailureKind.busy);
      expect(
        await _failure(503, {'error': 'unavailable'}),
        CoachFailureKind.unavailable,
      );
    });

    test('502 upstream', () async {
      expect(
        await _failure(502, {'error': 'upstream'}),
        CoachFailureKind.upstream,
      );
    });

    test('an unlisted status is unavailable', () async {
      expect(await _failure(500, 'boom'), CoachFailureKind.unavailable);
      expect(await _failure(404, {}), CoachFailureKind.unavailable);
    });

    test('no connection', () async {
      for (final error in [
        const SocketException('Failed host lookup'),
        http.ClientException('Connection closed'),
      ]) {
        final result = await _throwing(error).send(_request);
        expect((result as CoachFailure).kind, CoachFailureKind.noConnection);
      }
      expect(
        SupabaseCoachClient.parseError(0, null).kind,
        CoachFailureKind.noConnection,
      );
    });
  });

  test('every failure has sentence-case copy from the doc', () {
    expect(CoachFailureKind.values.map((kind) => kind.message), [
      'The Coach needs a connection. Your plans still work offline.',
      'Sign in again to use the Coach.',
      'Something went wrong. Try a shorter message.',
      'Update OpenGym to keep using the Coach.',
      "You've used today's Coach requests. They reset tomorrow.",
      'The Coach is busy right now. Try again later.',
      'The Coach is unavailable right now.',
      "The Coach couldn't answer. Try again.",
    ]);
  });
}
