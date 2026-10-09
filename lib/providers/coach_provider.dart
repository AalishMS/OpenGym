import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/coach_proposal.dart';
import '../models/split.dart';
import '../services/coach/coach_applier.dart';
import '../services/coach/coach_client.dart';
import '../services/coach/coach_context_builder.dart';
import '../services/coach/proposal_diff.dart';
import '../services/coach/proposal_validator.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import 'split_provider.dart';

enum CoachEntryRole { user, coach, failure }

enum CoachProposalStatus { pending, applied, discarded, stale }

/// A validated proposal in the chat, with the diff its card and review screen
/// show.
class CoachProposalItem {
  final ValidatedProposal proposal;
  final ProposalDiff diff;
  CoachProposalStatus status = CoachProposalStatus.pending;

  CoachProposalItem(this.proposal) : diff = ProposalDiff.compute(proposal);

  /// The split the plans land in.
  String get splitName => proposal.newSplitName ?? proposal.snapshot.splitName;

  /// "2 plans changed, 1 added".
  String get summary {
    final parts = [
      for (final (kind, verb) in const [
        (DiffKind.changed, 'changed'),
        (DiffKind.added, 'added'),
        (DiffKind.removed, 'removed'),
      ])
        if (diff.count(kind) > 0) (diff.count(kind), verb),
    ];
    return [
      for (var index = 0; index < parts.length; index++)
        index == 0
            ? '${parts[index].$1} ${parts[index].$1 == 1 ? 'plan' : 'plans'} '
                '${parts[index].$2}'
            : '${parts[index].$1} ${parts[index].$2}',
    ].join(', ');
  }
}

/// One line of the conversation.
class CoachEntry {
  final CoachEntryRole role;

  /// The user's message, the Coach's reply, or the failure copy.
  final String text;

  /// For Coach and failure entries: the user message that asked for it, so
  /// it can be sent again.
  final String? prompt;

  /// What the model said, as sent back in later turns. Coach entries only.
  final String? output;

  /// The model suggested a plan that failed validation twice.
  final bool planUnusable;
  final CoachFailureKind? failure;
  final CoachProposalItem? proposal;

  const CoachEntry._({
    required this.role,
    required this.text,
    this.prompt,
    this.output,
    this.planUnusable = false,
    this.failure,
    this.proposal,
  });
}

typedef CoachContextSource = CoachContext Function(Split split);

/// The Coach conversation for this app session. Never stored: not in Hive,
/// not synced, not in backups. It clears when the account changes and starts
/// over when the active split changes, because refs and proposals belong to
/// one split.
class CoachProvider with ChangeNotifier {
  /// History turns sent with each request. With the new message this stays
  /// under the proxy's twelve.
  static const int maxHistoryTurns = 5;

  /// The remaining count shows once fewer than this many requests are left.
  static const int lowQuotaThreshold = 5;

  final CoachClient _client;
  final SplitProvider _splits;
  final String? Function() _userIdProvider;
  final bool Function() _isConfigured;
  final CoachContextSource _contextSource;
  final ProposalValidator _validator;
  final Future<bool> Function() _probeConnection;

  final List<CoachEntry> _entries = [];
  CoachQuota? _quota;
  bool _sending = false;
  bool _applying = false;
  bool _connectionNotice = false;
  String? _splitId;
  String? _userId;

  /// Bumped on every reset, so a reply to an abandoned conversation is
  /// dropped.
  int _generation = 0;

  CoachProvider({
    required SplitProvider splitProvider,
    CoachClient? client,
    String? Function()? userIdProvider,
    bool Function()? isConfigured,
    CoachContextSource? contextSource,
    ProposalValidator validator = const ProposalValidator(),
    Future<bool> Function()? probeConnection,
  }) : _splits = splitProvider,
       _client = client ?? SupabaseCoachClient(),
       _userIdProvider =
           userIdProvider ?? (() => SupabaseService.currentUserId),
       _isConfigured = isConfigured ?? (() => SupabaseService.isConfigured),
       _contextSource = contextSource ?? _hiveContext(splitProvider),
       _validator = validator,
       _probeConnection = probeConnection ?? probeCoachConnection {
    _splitId = _splits.activeSplitId;
    _userId = _userIdProvider();
    _splits.addListener(_onSplitsChanged);
  }

  static CoachContextSource _hiveContext(SplitProvider splits) =>
      (split) => const CoachContextBuilder().build(
        split: split,
        splits: splits.splits,
        plans: HiveService.getPlans(splitId: split.id),
        sessions: HiveService.getCompletedSessions(splitId: split.id),
        maxSplits: SplitProvider.maxSplits,
      );

  List<CoachEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;
  bool get sending => _sending;
  bool get applying => _applying;
  CoachQuota? get quota => _quota;

  String? get userId => _userIdProvider();

  /// Hidden in offline-only builds and while signed out.
  bool get available => _isConfigured() && _userIdProvider() != null;

  /// "The Coach needs a connection" shows above the chat.
  bool get connectionNotice => _connectionNotice;

  /// Requests left today, once there are few enough to mention.
  int? get lowRemaining {
    final quota = _quota;
    if (quota == null || quota.remaining >= lowQuotaThreshold) return null;
    return quota.remaining;
  }

  /// Clears the conversation. Called when the signed-in account changes.
  void resetForAccount() {
    _userId = _userIdProvider();
    _quota = null;
    _reset();
  }

  Future<void> checkConnection() async {
    final online = await _probeConnection();
    if (online == !_connectionNotice) return;
    _connectionNotice = !online;
    notifyListeners();
  }

  /// One turn: context, request, validation, and at most one retry.
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    final split = _splits.activeSplit;
    if (text.isEmpty || _sending || split == null) return;
    if (_userIdProvider() != _userId) resetForAccount();
    if (split.id != _splitId) {
      _splitId = split.id;
      _reset();
    }

    final generation = _generation;
    final history = _history();
    _entries.add(CoachEntry._(role: CoachEntryRole.user, text: text));
    _sending = true;
    notifyListeners();

    try {
      final context = _contextSource(split);
      final request = _fitRequest(context.json, history, text);
      final first = await _client.send(request);
      if (generation != _generation) return;
      if (first is CoachFailure) return _fail(first, text);
      final answer = first as CoachAnswer;
      _takeQuota(answer.quota);

      final checked = _validator.validate(answer.output, context.snapshot);
      if (checked.isValid) return _answer(checked.reply!, answer.output, text);

      final second = await _client.send(
        CoachRequest(
          context: request.context,
          messages: request.messages,
          retry: CoachRetry(
            previousOutput: answer.output,
            errors: checked.errors,
          ),
        ),
      );
      if (generation != _generation) return;
      if (second is CoachAnswer) {
        _takeQuota(second.quota);
        final rechecked = _validator.validate(second.output, context.snapshot);
        if (rechecked.isValid) {
          return _answer(rechecked.reply!, second.output, text);
        }
        return _unusable(
          replyText(second.output) ?? replyText(answer.output),
          text,
        );
      }
      final failure = second as CoachFailure;
      _takeQuota(failure.quota);
      _unusable(replyText(answer.output), text);
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('Coach turn failed: ${error.runtimeType}');
      _fail(const CoachFailure(CoachFailureKind.unavailable), text);
    } finally {
      if (generation == _generation) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  /// Marks a proposal out of date and asks the same question again with the
  /// latest plans.
  Future<void> askAgain(CoachEntry entry) {
    entry.proposal?.status = CoachProposalStatus.stale;
    notifyListeners();
    return send(entry.prompt ?? '');
  }

  /// Marks pending proposals whose plans changed since they were made.
  /// Returns whether [entry], if given, is still current.
  bool refreshStale([CoachEntry? entry]) {
    final userId = _userIdProvider();
    if (userId == null) return false;
    var changed = false;
    for (final item in _entries) {
      final proposal = item.proposal;
      if (proposal == null || proposal.status != CoachProposalStatus.pending) {
        continue;
      }
      final reason = CoachApplier.staleReason(
        proposal.proposal.snapshot,
        userId: userId,
      );
      if (reason != null) {
        proposal.status = CoachProposalStatus.stale;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    return entry?.proposal?.status == CoachProposalStatus.pending;
  }

  /// Writes [entry]'s proposal. Throws when the write fails; a stale proposal
  /// writes nothing and is marked out of date.
  Future<CoachApplyOutcome> apply(CoachEntry entry) async {
    final item = entry.proposal!;
    _applying = true;
    notifyListeners();
    try {
      final outcome = await _splits.applyCoachProposal(item.proposal);
      item.status = switch (outcome) {
        CoachApplied() => CoachProposalStatus.applied,
        CoachApplyStale() => CoachProposalStatus.stale,
      };
      return outcome;
    } finally {
      _applying = false;
      notifyListeners();
    }
  }

  void discard(CoachEntry entry) {
    entry.proposal?.status = CoachProposalStatus.discarded;
    notifyListeners();
  }

  /// The model's `reply`, read leniently from output that failed validation.
  static String? replyText(String output) {
    var text = output.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(text);
    if (fence != null) text = fence.group(1)!;
    try {
      final decoded = jsonDecode(text);
      final reply = decoded is Map ? decoded['reply'] : null;
      if (reply is String && reply.trim().isNotEmpty) return reply.trim();
    } on FormatException {
      return null;
    }
    return null;
  }

  void _onSplitsChanged() {
    final active = _splits.activeSplitId;
    if (active != _splitId) {
      _splitId = active;
      _reset();
      return;
    }
    refreshStale();
  }

  void _reset() {
    _generation++;
    final hadState = _entries.isNotEmpty || _sending || _applying;
    _entries.clear();
    _sending = false;
    _applying = false;
    if (hadState) notifyListeners();
  }

  /// Completed turns, oldest first, as user/assistant pairs. Failed turns
  /// are left out so the roles keep alternating.
  List<(String, String)> _history() {
    final turns = <(String, String)>[];
    for (var index = 1; index < _entries.length; index++) {
      final answer = _entries[index];
      final question = _entries[index - 1];
      if (answer.role == CoachEntryRole.coach &&
          question.role == CoachEntryRole.user &&
          answer.output != null) {
        turns.add((question.text, answer.output!));
      }
    }
    return turns.length > maxHistoryTurns
        ? turns.sublist(turns.length - maxHistoryTurns)
        : turns;
  }

  /// The request with as much history as fits the proxy's size cap.
  CoachRequest _fitRequest(
    Map<String, dynamic> context,
    List<(String, String)> history,
    String text,
  ) {
    var turns = history;
    while (true) {
      final request = CoachRequest(
        context: context,
        messages: [
          for (final (question, answer) in turns) ...[
            CoachMessage.user(question),
            CoachMessage.assistant(answer),
          ],
          CoachMessage.user(text),
        ],
      );
      if (turns.isEmpty ||
          utf8.encode(jsonEncode(request.toJson())).length <=
              kCoachMaxBodyBytes) {
        return request;
      }
      turns = turns.sublist(1);
    }
  }

  void _takeQuota(CoachQuota? quota) {
    if (quota != null) _quota = quota;
  }

  void _answer(CoachReply reply, String output, String prompt) {
    _connectionNotice = false;
    final proposal = reply.proposal;
    _entries.add(
      CoachEntry._(
        role: CoachEntryRole.coach,
        text: reply.reply,
        prompt: prompt,
        output: output,
        proposal: proposal == null ? null : CoachProposalItem(proposal),
      ),
    );
  }

  /// The second answer failed too: show what the Coach said, without a plan.
  /// Later turns see the reply alone, not the plan that couldn't be used.
  void _unusable(String? reply, String prompt) {
    _connectionNotice = false;
    final text = reply ?? '';
    _entries.add(
      CoachEntry._(
        role: CoachEntryRole.coach,
        text: text,
        prompt: prompt,
        output:
            text.isEmpty ? null : jsonEncode({'reply': text, 'proposal': null}),
        planUnusable: true,
      ),
    );
  }

  void _fail(CoachFailure failure, String prompt) {
    _takeQuota(failure.quota);
    if (failure.kind == CoachFailureKind.noConnection) _connectionNotice = true;
    _entries.add(
      CoachEntry._(
        role: CoachEntryRole.failure,
        text: failure.kind.message,
        prompt: prompt,
        failure: failure.kind,
      ),
    );
  }

  @override
  void dispose() {
    _splits.removeListener(_onSplitsChanged);
    super.dispose();
  }
}
