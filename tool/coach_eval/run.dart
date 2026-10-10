// Coach eval runner. See docs/coach.md, "Eval".
//
// Builds each case's context with the real CoachContextBuilder, sends it
// through the proxy's own request parsing, prompt, and upstream call
// (model_call.ts, run under Deno), validates with the real ProposalValidator,
// and retries once with {previousOutput, errors} exactly as CoachProvider
// does. Never part of `flutter test` or CI: it spends real model requests.
//
// From the repo root:
//   dart run tool/coach_eval/run.dart --model gemini-3.5-flash-lite --repeat 2
//   dart run tool/coach_eval/run.dart --model gemini-3.5-flash \
//     --cases sore_shoulder,new_split_upper_lower --max-calls 2
//   dart run tool/coach_eval/run.dart --dry-run      # contexts only, no calls
//
// Options: --model, --cases (comma-separated ids), --repeat N, --max-calls N,
// --prompt FILE (a candidate system prompt, tested without deploying),
// --label NAME (also names the prompt in the report), --pace SECONDS between calls (default 5).
// Reads COACH_API_KEY from supabase/.env (git-ignored). Writes
// tool/coach_eval/results/<run>.json, then regenerates report.md.

// ignore_for_file: avoid_print, a command-line tool.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gymapp/services/coach/coach_context_builder.dart';
import 'package:gymapp/services/coach/coach_request.dart';
import 'package:gymapp/services/coach/proposal_diff.dart';
import 'package:gymapp/services/coach/proposal_validator.dart';

import 'cases.dart';
import 'diff_render.dart';
import 'report.dart' as report;

const String _envFile = 'supabase/.env';
const String _resultsDir = 'tool/coach_eval/results';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final cases =
      options.caseIds == null
          ? evalCases
          : [
            for (final id in options.caseIds!)
              evalCases.firstWhere(
                (item) => item.id == id,
                orElse: () => throw ArgumentError('Unknown case "$id"'),
              ),
          ];

  if (options.dryRun) {
    for (final item in cases) {
      final context = item.context();
      final request = fitRequest(
        context.json,
        item.encodedHistory(),
        item.message,
      );
      final bytes = utf8.encode(jsonEncode(request.toJson())).length;
      print(
        '${item.id}: ${context.snapshot.plans.length} plans, '
        '${(context.json['exercises'] as List).length} exercises, '
        'body $bytes bytes, ${request.messages.length} messages',
      );
    }
    return;
  }

  if (!File(_envFile).existsSync()) {
    stderr.writeln('Missing $_envFile with COACH_API_KEY.');
    exit(2);
  }
  final helper = await _ModelHelper.start();
  final runner = _Runner(helper, options);
  final started = DateTime.now();
  final turns = <Map<String, dynamic>>[];
  try {
    for (var rep = 1; rep <= options.repeat; rep++) {
      for (final item in cases) {
        if (runner.budgetLeft == 0) break;
        final turn = await runner.runTurn(item, rep);
        turns.add(turn);
        _printTurn(turn);
        if (runner.dailyLimitHit) break;
      }
      if (runner.dailyLimitHit || runner.budgetLeft == 0) break;
    }
  } finally {
    await helper.close();
  }

  final stamp = started
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .substring(0, 19);
  final label = options.label ?? options.model;
  final file = File('$_resultsDir/${stamp}_$label.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'run': '${stamp}_$label',
      'startedAt': started.toIso8601String(),
      'model': options.model,
      'prompt': options.label ?? (options.promptFile == null ? 'v1' : 'custom'),
      'promptFile': options.promptFile,
      'calls': runner.calls,
      'turns': turns,
    }),
  );
  print('\n${runner.calls} calls. Wrote ${file.path}');
  report.writeReport(_resultsDir);
  // The helper's pipes can keep the VM alive on Windows after it exits.
  exit(0);
}

/// `CoachProvider._fitRequest`: as much history as fits the size cap.
CoachRequest fitRequest(
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

class _Options {
  final String model;
  final List<String>? caseIds;
  final int repeat;
  final int? maxCalls;
  final String? promptFile;
  final String? label;
  final Duration pace;
  final bool dryRun;

  _Options({
    required this.model,
    required this.caseIds,
    required this.repeat,
    required this.maxCalls,
    required this.promptFile,
    required this.label,
    required this.pace,
    required this.dryRun,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    var dryRun = false;
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg.startsWith('--') && index + 1 < args.length) {
        values[arg.substring(2)] = args[++index];
      } else {
        throw ArgumentError('Unexpected argument "$arg"');
      }
    }
    return _Options(
      model: values['model'] ?? 'gemini-3.5-flash-lite',
      caseIds: values['cases']?.split(',').map((id) => id.trim()).toList(),
      repeat: int.parse(values['repeat'] ?? '1'),
      maxCalls:
          values['max-calls'] == null ? null : int.parse(values['max-calls']!),
      promptFile: values['prompt'],
      label: values['label'],
      pace: Duration(seconds: int.parse(values['pace'] ?? '5')),
      dryRun: dryRun,
    );
  }
}

class _Runner {
  final _ModelHelper helper;
  final _Options options;
  final ProposalValidator validator = const ProposalValidator();
  int calls = 0;
  bool dailyLimitHit = false;
  DateTime? _lastCall;

  _Runner(this.helper, this.options);

  int? get budgetLeft =>
      options.maxCalls == null ? null : options.maxCalls! - calls;

  Future<Map<String, dynamic>> runTurn(EvalCase item, int rep) async {
    final context = item.context();
    final request = fitRequest(
      context.json,
      item.encodedHistory(),
      item.message,
    );
    final attempts = <Map<String, dynamic>>[];
    final turn = <String, dynamic>{
      'case': item.id,
      'model': options.model,
      'rep': rep,
      'attempts': attempts,
    };

    final first = await _call(request);
    attempts.add(first);
    if (first['kind'] != 'ok') return _finish(turn, item, context, null);
    final checked = validator.validate(first['output'], context.snapshot);
    first['errors'] = checked.errors;
    if (checked.isValid) return _finish(turn, item, context, checked);

    if (budgetLeft == 0 || dailyLimitHit) {
      turn['retrySkipped'] = true;
      return _finish(turn, item, context, null);
    }
    final second = await _call(
      CoachRequest(
        context: request.context,
        messages: request.messages,
        retry: CoachRetry(
          previousOutput: first['output'],
          errors: checked.errors,
        ),
      ),
    );
    attempts.add(second);
    if (second['kind'] != 'ok') return _finish(turn, item, context, null);
    final rechecked = validator.validate(second['output'], context.snapshot);
    second['errors'] = rechecked.errors;
    return _finish(turn, item, context, rechecked.isValid ? rechecked : null);
  }

  Map<String, dynamic> _finish(
    Map<String, dynamic> turn,
    EvalCase item,
    CoachContext context,
    ProposalValidationResult? valid,
  ) {
    final attempts = turn['attempts'] as List<Map<String, dynamic>>;
    turn['passedFirst'] =
        attempts.first['kind'] == 'ok' &&
        (attempts.first['errors'] as List).isEmpty;
    turn['passedAfterRetry'] = valid != null;
    turn['infraFailure'] = attempts.any((attempt) => attempt['kind'] != 'ok');
    turn['latencyMs'] = attempts.fold<int>(
      0,
      (sum, attempt) => sum + ((attempt['latencyMs'] as int?) ?? 0),
    );
    final reply = valid?.reply;
    if (reply != null) {
      turn['reply'] = reply.reply;
      final proposal = reply.proposal;
      if (proposal != null) {
        final diff = ProposalDiff.compute(proposal);
        turn['proposal'] = {
          'target': proposal.target.name,
          'newSplitName': proposal.newSplitName,
          'summary': diffSummary(diff),
          'counts': diffCounts(diff),
          'diff': renderDiff(diff),
        };
      } else {
        turn['proposal'] = null;
      }
    } else {
      // What the chat would still show: the reply read leniently.
      final last = attempts.lastWhere(
        (attempt) => attempt['output'] != null,
        orElse: () => const {},
      );
      turn['reply'] = _lenientReply(last['output'] as String?);
      turn['planUnusable'] = last.isNotEmpty;
    }
    return turn;
  }

  Future<Map<String, dynamic>> _call(CoachRequest request) async {
    var waits = 0;
    while (true) {
      final last = _lastCall;
      if (last != null) {
        final wait = options.pace - DateTime.now().difference(last);
        if (!wait.isNegative) await Future<void>.delayed(wait);
      }
      _lastCall = DateTime.now();
      calls++;
      final result = await helper.call(
        model: options.model,
        body: jsonEncode(request.toJson()),
        promptFile: options.promptFile,
      );
      if (result['kind'] != 'rate_limited') {
        if (waits > 0) result['rateLimitWaits'] = waits;
        return result;
      }
      // A per-minute limit clears; a daily one doesn't. Two waits, then stop.
      if (waits == 2 || budgetLeft == 0) {
        dailyLimitHit = true;
        return result;
      }
      waits++;
      stderr.writeln('  429, waiting 65 s');
      await Future<void>.delayed(const Duration(seconds: 65));
    }
  }

  static String? _lenientReply(String? output) {
    if (output == null) return null;
    try {
      final decoded = jsonDecode(output);
      final reply = decoded is Map ? decoded['reply'] : null;
      return reply is String ? reply : null;
    } on FormatException {
      return null;
    }
  }
}

void _printTurn(Map<String, dynamic> turn) {
  final attempts = turn['attempts'] as List;
  final verdict =
      turn['passedFirst'] == true
          ? 'pass'
          : turn['passedAfterRetry'] == true
          ? 'pass after retry'
          : turn['infraFailure'] == true
          ? 'call failed (${attempts.last['kind']} ${attempts.last['status']})'
          : 'FAIL';
  final summary = (turn['proposal'] as Map?)?['summary'] ?? 'no proposal';
  print(
    '${turn['case']} #${turn['rep']}: $verdict, ${turn['latencyMs']} ms, '
    '$summary',
  );
  for (final attempt in attempts) {
    for (final error in (attempt['errors'] as List?) ?? const []) {
      print('    $error');
    }
  }
}

/// model_call.ts under Deno, one JSON line per call.
class _ModelHelper {
  final Process _process;
  final StreamIterator<String> _lines;

  _ModelHelper(this._process)
    : _lines = StreamIterator(
        _process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ) {
    _process.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  /// Deno through npx, as docs/coach.md runs it. npx resolves the binary
  /// once; the helper is started directly, because piping stdin through
  /// `npx` under cmd.exe on Windows hangs.
  static Future<_ModelHelper> start() async {
    final which = await Process.run('npx', [
      '--yes',
      'deno@2.9.6',
      'eval',
      'console.log(Deno.execPath())',
    ], runInShell: Platform.isWindows);
    if (which.exitCode != 0) {
      throw StateError('Deno not available through npx: ${which.stderr}');
    }
    return _ModelHelper(
      await Process.start((which.stdout as String).trim(), [
        'run',
        '--allow-net',
        '--allow-read',
        '--allow-env',
        '--env-file=$_envFile',
        'tool/coach_eval/model_call.ts',
      ]),
    );
  }

  Future<Map<String, dynamic>> call({
    required String model,
    required String body,
    String? promptFile,
  }) async {
    _process.stdin.writeln(
      jsonEncode({'model': model, 'body': body, 'promptFile': promptFile}),
    );
    await _process.stdin.flush();
    if (!await _lines.moveNext()) {
      throw StateError(
        'model_call.ts exited (exit ${await _process.exitCode})',
      );
    }
    return (jsonDecode(_lines.current) as Map).cast<String, dynamic>();
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _lines.cancel();
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }
}
