import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Split;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/coach_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/screens/coach_screen.dart';
import 'package:gymapp/services/coach/coach_applier.dart';
import 'package:gymapp/services/coach/coach_client.dart';
import 'package:gymapp/services/coach/coach_disclosure.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/coach/coach_button.dart';

import 'support/coach_fixtures.dart';
import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

const String _userId = 'coach-ui-user';
final DateTime _seeded = DateTime(2026, 9, 1);

/// Answers from a queue and records every request.
class FakeCoachClient implements CoachClient {
  final List<CoachRequest> requests = [];
  final List<FutureOr<CoachClientResult>> _queue = [];

  void answer(String output, {CoachQuota? quota}) =>
      _queue.add(CoachAnswer(output: output, quota: quota));

  void fail(CoachFailureKind kind, {CoachQuota? quota}) =>
      _queue.add(CoachFailure(kind, quota: quota));

  void enqueue(Future<CoachClientResult> result) => _queue.add(result);

  @override
  Future<CoachClientResult> send(CoachRequest request) async {
    requests.add(request);
    if (_queue.isEmpty) fail(CoachFailureKind.unavailable);
    return _queue.removeAt(0);
  }
}

String _output(String reply, [Map<String, dynamic>? proposal]) =>
    jsonEncode({'reply': reply, 'proposal': proposal});

Map<String, dynamic> _editPush(String exercise) => {
  'target': 'active_split',
  'newSplitName': null,
  'plans': [
    {
      'ref': 'p1',
      'name': 'Push',
      'exercises': [
        {
          'name': exercise,
          'sets': [
            {'reps': 10, 'kg': 22.5},
            {'reps': 10, 'kg': 22.5},
          ],
          'note': null,
          'custom': false,
        },
      ],
    },
    {
      'ref': null,
      'name': 'Legs',
      'exercises': [
        {
          'name': 'Squat',
          'sets': [
            {'reps': 5, 'kg': 100},
          ],
          'note': null,
          'custom': false,
        },
      ],
    },
  ],
  'removePlanRefs': <String>[],
};

final String _validProposal = _output(
  'Swapped bench for incline and added a leg day.',
  _editPush('Incline Dumbbell Press'),
);

Future<void> _seed() async {
  await HiveService.putSplitRaw(
    Split(
      id: kSplitId,
      name: 'Push Pull Legs',
      userId: _userId,
      createdAt: _seeded,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  await HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: _userId,
      activeSplitId: kSplitId,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  await HiveService.putPlansRaw({
    'a': plan('a', 'Push', [
      template('Bench Press', [(8, 60), (8, 60)]),
    ], position: 0).copyWith(userId: _userId, dirty: false),
    'b': plan('b', 'Pull', [
      template('Barbell Row', [(10, 50)]),
    ], position: 1).copyWith(userId: _userId, dirty: false),
  });
}

/// Hands the write back to the test, which runs the real applier inside
/// `runAsync`: Hive file writes started in the widget test's fake-async zone
/// leave the box unable to close.
class _DeferredApplier extends CoachApplier {
  ValidatedProposal? proposal;
  Completer<CoachApplyOutcome> result = Completer();

  @override
  Future<CoachApplyOutcome> apply(
    ValidatedProposal proposal, {
    required String userId,
  }) {
    this.proposal = proposal;
    return result.future;
  }

  Future<void> complete(WidgetTester tester) async {
    final outcome = await tester.runAsync(
      () => const CoachApplier().apply(proposal!, userId: _userId),
    );
    result.complete(outcome);
  }
}

class _Fixture {
  final FakeCoachClient client = FakeCoachClient();
  final _DeferredApplier applier = _DeferredApplier();
  late final SplitProvider splits;
  late final CoachProvider coach;
  String? userId = _userId;
  bool online = true;

  _Fixture() {
    splits = SplitProvider(userIdProvider: () => userId, coachApplier: applier);
    coach = CoachProvider(
      splitProvider: splits,
      client: client,
      userIdProvider: () => userId,
      isConfigured: () => true,
      probeConnection: () async => online,
    );
  }

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: splits),
      ChangeNotifierProvider.value(value: coach),
    ],
    child: MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
      home: home,
    ),
  );

  void dispose() {
    coach.dispose();
    splits.dispose();
  }
}

/// A Home stand-in: the Coach button and nothing else.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CoachButton()));
}

Future<_Fixture> _openChat(WidgetTester tester) async {
  final fixture = _Fixture();
  addTearDown(fixture.dispose);
  await tester.pumpWidget(fixture.app(const _Home()));
  await pumpWithStorage(tester);
  await tester.runAsync(() => CoachDisclosure.accept(_userId));
  await tester.tap(find.byKey(const ValueKey('coach-button')));
  await pumpWithStorage(tester);
  expect(find.byType(CoachScreen), findsOneWidget);
  return fixture;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('coach-input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('coach-send')));
  await pumpWithStorage(tester);
}

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open(includeSplits: true);
    await loadTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
    await _seed();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  group('availability and disclosure', () {
    testWidgets('the button is hidden while signed out', (tester) async {
      final fixture = _Fixture()..userId = null;
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(const _Home()));
      await pumpWithStorage(tester);
      expect(find.byKey(const ValueKey('coach-button')), findsNothing);
    });

    testWidgets('the button is hidden in an offline-only build', (
      tester,
    ) async {
      final splits = SplitProvider(userIdProvider: () => _userId);
      final coach = CoachProvider(
        splitProvider: splits,
        client: FakeCoachClient(),
        userIdProvider: () => _userId,
        isConfigured: () => false,
      );
      addTearDown(() {
        coach.dispose();
        splits.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: splits),
            ChangeNotifierProvider.value(value: coach),
          ],
          child: const MaterialApp(home: _Home()),
        ),
      );
      await pumpWithStorage(tester);
      expect(find.byKey(const ValueKey('coach-button')), findsNothing);
    });

    testWidgets('Continue waits for the age box, then opens the Coach', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(const _Home()));
      await pumpWithStorage(tester);

      await tester.tap(find.byKey(const ValueKey('coach-button')));
      await pumpWithStorage(tester);
      expect(find.text('Before you use the Coach'), findsOneWidget);
      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('coach-age-checkbox')));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(continueButton).onPressed,
        isNotNull,
      );
      await tester.tap(continueButton);
      await pumpWithStorage(tester);

      expect(find.byType(CoachScreen), findsOneWidget);
      expect(
        await tester.runAsync(() => CoachDisclosure.isAccepted(_userId)),
        isTrue,
      );
      expect(
        await tester.runAsync(() => CoachDisclosure.isAccepted('someone-else')),
        isFalse,
      );

      // Accepted once: the next open goes straight to the chat.
      Navigator.of(tester.element(find.byType(CoachScreen))).pop();
      await pumpWithStorage(tester);
      await tester.tap(find.byKey(const ValueKey('coach-button')));
      await pumpWithStorage(tester);
      expect(find.text('Before you use the Coach'), findsNothing);
      expect(find.byType(CoachScreen), findsOneWidget);
    });

    testWidgets('Not now leaves the Coach closed and asks again later', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(const _Home()));
      await pumpWithStorage(tester);

      await tester.tap(find.byKey(const ValueKey('coach-button')));
      await pumpWithStorage(tester);
      await tester.tap(find.text('Not now'));
      await pumpWithStorage(tester);

      expect(find.byType(CoachScreen), findsNothing);
      expect(
        await tester.runAsync(() => CoachDisclosure.isAccepted(_userId)),
        isFalse,
      );
    });
  });

  group('chat', () {
    testWidgets('the empty state offers three suggestions that send', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      for (final suggestion in kCoachSuggestions) {
        expect(find.text(suggestion), findsOneWidget);
      }
      fixture.client.answer(_output('Sure.'));
      await tester.tap(find.text('My squat has stalled'));
      await pumpWithStorage(tester);

      final sent = fixture.client.requests.single;
      expect(sent.messages.single.content, 'My squat has stalled');
      expect(sent.context['split'], containsPair('name', 'Push Pull Legs'));
      expect(find.text('Sure.'), findsOneWidget);
    });

    testWidgets('the send button shows progress while a request is out', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      final pending = Completer<CoachClientResult>();
      fixture.client.enqueue(pending.future);

      await tester.enterText(find.byKey(const ValueKey('coach-input')), 'Hi');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('coach-send')));
      await tester.pump();

      expect(find.bySemanticsLabel('Sending'), findsOneWidget);
      expect(find.text('Thinking'), findsOneWidget);

      pending.complete(CoachAnswer(output: _output('Hello.')));
      await pumpWithStorage(tester);
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('Hello.'), findsOneWidget);
    });

    testWidgets('later turns send the earlier ones as history', (tester) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_output('First answer.'));
      fixture.client.answer(_output('Second answer.'));
      await _send(tester, 'First');
      await _send(tester, 'Second');

      final messages = fixture.client.requests.last.messages;
      expect([for (final m in messages) m.role], ['user', 'assistant', 'user']);
      expect(messages.first.content, 'First');
      expect(messages[1].content, _output('First answer.'));
      expect(messages.last.content, 'Second');
    });

    testWidgets('a failed proposal is retried once with the errors', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(
        _output('Here you go.', _editPush('Incline DB Press')),
      );
      fixture.client.answer(_validProposal);
      await _send(tester, 'Swap my bench');

      expect(fixture.client.requests, hasLength(2));
      final retry = fixture.client.requests.last.retry!;
      expect(retry.previousOutput, contains('Incline DB Press'));
      expect(
        retry.errors.single,
        contains('"Incline DB Press" is not in the library'),
      );
      expect(
        fixture.client.requests.last.messages.last.content,
        'Swap my bench',
      );
      expect(
        find.text('Swapped bench for incline and added a leg day.'),
        findsOneWidget,
      );
      expect(
        find.text('Push Pull Legs · 1 plan changed, 1 added'),
        findsOneWidget,
      );
    });

    testWidgets('a second failure shows the reply without a plan', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_output('Try this.', _editPush('Incline DB')));
      fixture.client.answer(_output('Try this one.', _editPush('Incline DB')));
      await _send(tester, 'Swap my bench');

      expect(fixture.client.requests, hasLength(2));
      expect(find.text('Try this one.'), findsOneWidget);
      expect(
        find.textContaining("suggested a plan that couldn't be used"),
        findsOneWidget,
      );
      expect(find.text('Review'), findsNothing);
    });
  });

  group('errors and quota', () {
    for (final kind in CoachFailureKind.values) {
      testWidgets('${kind.name} shows its copy', (tester) async {
        final fixture = await _openChat(tester);
        fixture.client.fail(kind);
        await _send(tester, 'Hi');

        // No connection also raises the notice above the chat.
        expect(
          find.text(kind.message),
          kind == CoachFailureKind.noConnection
              ? findsNWidgets(2)
              : findsOneWidget,
        );
        expect(
          find.text('Check for updates'),
          kind == CoachFailureKind.updateRequired
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('the screen opens with the notice when offline', (
      tester,
    ) async {
      final fixture = _Fixture()..online = false;
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(const CoachScreen()));
      await pumpWithStorage(tester);
      expect(
        find.text(
          'The Coach needs a connection. Your plans still work offline.',
        ),
        findsOneWidget,
      );
      // Plans still read normally underneath; the chat is still usable.
      expect(find.byKey(const ValueKey('coach-input')), findsOneWidget);
    });

    testWidgets('the remaining count appears only under five', (tester) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(
        _output('One.'),
        quota: const CoachQuota(used: 10, limit: 20),
      );
      await _send(tester, 'Hi');
      expect(find.textContaining('left today'), findsNothing);

      fixture.client.answer(
        _output('Two.'),
        quota: const CoachQuota(used: 16, limit: 20),
      );
      await _send(tester, 'Again');
      expect(find.text('4 Coach requests left today'), findsOneWidget);

      fixture.client.fail(
        CoachFailureKind.userQuota,
        quota: const CoachQuota(used: 20, limit: 20),
      );
      await _send(tester, 'More');
      expect(find.text('No Coach requests left today'), findsOneWidget);
    });
  });

  group('proposals', () {
    testWidgets('review shows the diff and apply writes it', (tester) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_validProposal);
      await _send(tester, 'Swap my bench and add legs');

      await tester.tap(find.text('Review'));
      await pumpWithStorage(tester);
      expect(find.text('Review changes'), findsOneWidget);
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Added: Incline Dumbbell Press, 2 × 10 · 22.5 kg',
        ),
        findsOne,
      );
      expect(
        find.bySemanticsLabel('Removed: Bench Press, 2 × 8 · 60 kg'),
        findsOne,
      );
      expect(find.text('New plan'), findsOneWidget);

      final removed = tester.widget<Text>(find.text('Bench Press'));
      expect(removed.style!.decoration, TextDecoration.lineThrough);
      final context = tester.element(find.text('Bench Press'));
      expect(removed.style!.color, errorColor(context));
      expect(
        tester.widget<Text>(find.text('Incline Dumbbell Press')).style!.color,
        accentColor(context),
      );

      await tester.tap(find.byKey(const ValueKey('coach-apply')));
      await tester.pump();
      expect(find.bySemanticsLabel('Applying'), findsOneWidget);
      await fixture.applier.complete(tester);
      await pumpWithStorage(tester);

      expect(find.byType(CoachScreen), findsNothing);
      expect(find.byType(_Home), findsOneWidget);
      expect(find.text('Plans updated'), findsOneWidget);
      final push = HiveService.getPlanById('a')!;
      expect(push.exercises.single.name, 'Incline Dumbbell Press');
      expect(
        HiveService.getPlans(splitId: kSplitId).map((plan) => plan.name),
        containsAll(['Push', 'Pull', 'Legs']),
      );
      final item = fixture.coach.entries.last.proposal!;
      expect(item.status, CoachProposalStatus.applied);
    });

    testWidgets('discard writes nothing', (tester) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_validProposal);
      await _send(tester, 'Swap my bench');

      await tester.tap(find.text('Review'));
      await pumpWithStorage(tester);
      await tester.tap(find.text('Discard'));
      await pumpWithStorage(tester);

      expect(find.byType(CoachScreen), findsOneWidget);
      expect(find.text('Discarded'), findsOneWidget);
      expect(
        HiveService.getPlanById('a')!.exercises.single.name,
        'Bench Press',
      );
    });

    testWidgets('a stale proposal offers Ask again with a fresh context', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_validProposal);
      await _send(tester, 'Swap my bench');

      // The user edits the plan after the Coach saw it.
      await tester.runAsync(() async {
        final push = HiveService.getPlanById('a')!;
        await HiveService.upsertPlan(push.copyWith(name: 'Push day'));
      });

      await tester.tap(find.text('Review'));
      await pumpWithStorage(tester);
      expect(find.text('Review changes'), findsNothing);
      expect(
        find.text('Plans changed. Ask again with the latest?'),
        findsOneWidget,
      );

      fixture.client.answer(_output('Updated for your latest plans.'));
      await tester.tap(find.text('Ask again'));
      await pumpWithStorage(tester);

      expect(fixture.client.requests, hasLength(2));
      final again = fixture.client.requests.last;
      expect(again.messages.last.content, 'Swap my bench');
      final plans = again.context['plans'] as List;
      expect((plans.first as Map)['name'], 'Push day');
      expect(find.text('Updated for your latest plans.'), findsOneWidget);
      expect(
        fixture.coach.entries
            .where((entry) => entry.role == CoachEntryRole.user)
            .map((entry) => entry.text),
        ['Swap my bench', 'Swap my bench'],
      );
      expect(
        HiveService.getPlanById('a')!.exercises.single.name,
        'Bench Press',
      );
    });

    testWidgets('apply refuses a proposal that went stale on screen', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_validProposal);
      await _send(tester, 'Swap my bench');
      await tester.tap(find.text('Review'));
      await pumpWithStorage(tester);

      await tester.runAsync(() async {
        final pull = HiveService.getPlanById('b')!;
        await HiveService.upsertPlan(pull.copyWith(name: 'Back'));
      });
      await tester.tap(find.byKey(const ValueKey('coach-apply')));
      await tester.pump();
      await fixture.applier.complete(tester);
      await pumpWithStorage(tester);

      expect(find.byType(CoachScreen), findsOneWidget);
      expect(
        find.text('Plans changed. Ask again with the latest?'),
        findsOneWidget,
      );
      expect(
        HiveService.getPlanById('a')!.exercises.single.name,
        'Bench Press',
      );
    });
  });

  group('conversation lifetime', () {
    testWidgets('changing the active split starts a new conversation', (
      tester,
    ) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(_output('Hello.'));
      await _send(tester, 'Hi');
      expect(find.text('Hello.'), findsOneWidget);

      await tester.runAsync(() => fixture.splits.createSplit('Upper lower'));
      await pumpWithStorage(tester);

      expect(fixture.coach.isEmpty, isTrue);
      expect(find.text('Hello.'), findsNothing);
      expect(find.text('Ask the Coach'), findsOneWidget);
      expect(find.text('Upper lower'), findsOneWidget);
    });

    testWidgets('a reply for an abandoned split is dropped', (tester) async {
      final fixture = await _openChat(tester);
      final pending = Completer<CoachClientResult>();
      fixture.client.enqueue(pending.future);
      await tester.enterText(find.byKey(const ValueKey('coach-input')), 'Hi');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('coach-send')));
      await tester.pump();

      await tester.runAsync(() => fixture.splits.createSplit('Upper lower'));
      pending.complete(CoachAnswer(output: _output('Too late.')));
      await pumpWithStorage(tester);

      expect(fixture.coach.isEmpty, isTrue);
      expect(fixture.coach.sending, isFalse);
      expect(find.text('Too late.'), findsNothing);
    });

    testWidgets('an account change clears the conversation', (tester) async {
      final fixture = await _openChat(tester);
      fixture.client.answer(
        _output('Hello.'),
        quota: const CoachQuota(used: 18, limit: 20),
      );
      await _send(tester, 'Hi');

      fixture.coach.resetForAccount();
      await pumpWithStorage(tester);

      expect(fixture.coach.isEmpty, isTrue);
      expect(fixture.coach.quota, isNull);
      expect(find.text('Hello.'), findsNothing);
    });
  });
}
