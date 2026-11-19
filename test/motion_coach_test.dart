import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Split;
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/coach_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/screens/coach_screen.dart';
import 'package:gymapp/services/coach/coach_client.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/motion/entrance.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/coach_fixtures.dart';
import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

// The Coach's motion: rows that arrive, the progress line handing over to
// the reply, the welcome giving way, and the regions and controls around the
// chat. `coach_ui_test.dart` covers what the Coach does; this covers how it
// moves.

const String _userId = 'coach-motion-user';
const String _thinking = 'Reading your plans';
const String _welcome = 'What should we work on?';
const String _offline =
    'The Coach needs a connection. Your plans still work offline.';

class _Client implements CoachClient {
  final List<FutureOr<CoachClientResult>> _queue = [];

  void answerRaw(String output) => _queue.add(CoachAnswer(output: output));

  void answer(String reply, {CoachQuota? quota}) => _queue.add(
    CoachAnswer(
      output: jsonEncode({'reply': reply, 'proposal': null}),
      quota: quota,
    ),
  );

  /// The next answer, held until the test completes it.
  Completer<CoachClientResult> hold() {
    final held = Completer<CoachClientResult>();
    _queue.add(held.future);
    return held;
  }

  @override
  Future<CoachClientResult> send(CoachRequest request) async {
    if (_queue.isEmpty) {
      return const CoachFailure(CoachFailureKind.unavailable);
    }
    return _queue.removeAt(0);
  }
}

/// Swaps Push's bench for incline dumbbells and adds a leg day.
String _proposal() => jsonEncode({
  'reply': 'Swapped bench for incline and added a leg day.',
  'proposal': {
    'target': 'active_split',
    'newSplitName': null,
    'plans': [
      {
        'ref': 'p1',
        'name': 'Push',
        'exercises': [
          {
            'name': 'Incline Dumbbell Press',
            'sets': [
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
  },
});

class _Fixture {
  final _Client client = _Client();
  late final SplitProvider splits;
  late final CoachProvider coach;
  bool online = true;

  _Fixture() {
    splits = SplitProvider(userIdProvider: () => _userId);
    coach = CoachProvider(
      splitProvider: splits,
      client: client,
      userIdProvider: () => _userId,
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

Future<void> _seed() async {
  final seeded = DateTime(2026, 9, 1);
  await HiveService.putSplitRaw(
    Split(
      id: kSplitId,
      name: 'Push Pull Legs',
      userId: _userId,
      createdAt: seeded,
      updatedAt: seeded,
      dirty: false,
    ),
  );
  await HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: _userId,
      activeSplitId: kSplitId,
      updatedAt: seeded,
      dirty: false,
    ),
  );
  await HiveService.putPlansRaw({
    'a': plan('a', 'Push', [
      template('Bench Press', [(8, 60)]),
    ], position: 0).copyWith(userId: _userId, dirty: false),
  });
}

void main() {
  final hive = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hive.open(includeSplits: true);
    await loadTestFonts();
  });

  setUp(() async {
    await HiveService.clearTrainingData();
    SharedPreferences.setMockInitialValues({});
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
    await _seed();
  });

  tearDownAll(() async {
    await hive.close();
  });

  Future<_Fixture> openCoach(
    WidgetTester tester, {
    bool reduceMotion = false,
    bool online = true,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final fixture = _Fixture()..online = online;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app(const CoachScreen()));
    await pumpWithStorage(tester);
    return fixture;
  }

  /// Types [text] and taps send, leaving the frame that sends it unpumped.
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('coach-input')), text);
    await tester.pump(AppMotion.quick);
    await tester.tap(find.byKey(const ValueKey('coach-send')));
  }

  /// A whole turn with an immediate answer, settled.
  Future<void> turn(
    WidgetTester tester,
    _Fixture fixture,
    String question,
    String reply,
  ) async {
    fixture.client.answer(reply);
    await send(tester, question);
    await pumpWithStorage(tester);
  }

  /// The arrival fade of [text]'s row: the one its [Entrance] owns.
  double arrival(WidgetTester tester, String text) =>
      tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of:
                      find
                          .ancestor(
                            of: find.text(text),
                            matching: find.byType(Entrance),
                          )
                          .first,
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;

  /// The cross fade of [text]'s row: the nearest one outside its [Entrance].
  double cross(WidgetTester tester, String text) =>
      tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of:
                      find
                          .ancestor(
                            of: find.text(text),
                            matching: find.byType(Entrance),
                          )
                          .first,
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;

  bool takesTaps(WidgetTester tester, Finder finder) =>
      !tester
          .widgetList<IgnorePointer>(
            find.ancestor(of: finder, matching: find.byType(IgnorePointer)),
          )
          .any((ignore) => ignore.ignoring);

  /// Every row arrival on screen, at rest.
  void expectAllAtRest(WidgetTester tester) {
    for (final entrance in find.byType(Entrance).evaluate()) {
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byWidget(entrance.widget),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    }
  }

  group('a turn', () {
    testWidgets('the question and progress line arrive, the reply crosses '
        'in where the progress line was', (tester) async {
      final fixture = await openCoach(tester);
      final held = fixture.client.hold();
      await send(tester, 'How should I deload?');
      await tester.pump();

      // Both new rows are there from the first frame, on their way in, the
      // progress line a beat behind the question.
      expect(find.text('How should I deload?'), findsOneWidget);
      expect(find.text(_thinking), findsOneWidget);
      final question = arrival(tester, 'How should I deload?');
      expect(question, lessThan(1));
      await tester.pump(AppMotion.stagger * 2);
      expect(
        arrival(tester, _thinking),
        lessThan(arrival(tester, 'How should I deload?')),
      );
      await tester.pump(AppMotion.enter + AppMotion.stagger);
      expect(arrival(tester, 'How should I deload?'), 1);
      expect(arrival(tester, _thinking), 1);

      held.complete(
        CoachAnswer(
          output: jsonEncode({'reply': 'Deload a week.', 'proposal': null}),
        ),
      );
      await tester.pump();
      await tester.pump();
      // The reply takes the progress line's place: both while they cross,
      // the reply by a cross alone (it doesn't also lift), and the progress
      // line no longer taking taps.
      expect(find.text('Deload a week.'), findsOneWidget);
      expect(find.text(_thinking), findsOneWidget);
      expect(takesTaps(tester, find.text(_thinking)), isFalse);
      expect(arrival(tester, 'Deload a week.'), 1);
      await tester.pump(AppMotion.quick ~/ 3);
      expect(cross(tester, 'Deload a week.'), lessThan(1));
      Offset row(String text) => tester.getTopLeft(
        find.ancestor(of: find.text(text), matching: find.byType(Entrance)),
      );
      expect(row('Deload a week.'), row(_thinking));

      await tester.pumpAndSettle();
      expect(find.text(_thinking), findsNothing);
      expect(cross(tester, 'Deload a week.'), 1);
      expectAllAtRest(tester);
    });

    testWidgets('a rebuild or a scroll back never replays an arrival', (
      tester,
    ) async {
      final fixture = await openCoach(tester, size: const Size(390, 600));
      for (var i = 0; i < 5; i++) {
        await turn(
          tester,
          fixture,
          'Question $i',
          'A reply long enough to take a few lines of the chat, number $i, '
              'so that the conversation scrolls well past one screen.',
        );
      }
      expectAllAtRest(tester);

      // Typing rebuilds the screen.
      await tester.enterText(find.byKey(const ValueKey('coach-input')), 'x');
      await tester.pump();
      expectAllAtRest(tester);

      // The first rows were dropped from the lazy list; back in view, they
      // are built afresh and simply there.
      final list = find.byType(Scrollable).first;
      expect(find.text('Question 0'), findsNothing);
      await tester.fling(list, const Offset(0, 3000), 3000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Question 0'), findsOneWidget);
      expectAllAtRest(tester);
      await tester.pumpAndSettle();
      await tester.fling(list, const Offset(0, -3000), 3000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expectAllAtRest(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('rows scrolled back into view while a reply is pending do '
        'not arrive again', (tester) async {
      final fixture = await openCoach(tester, size: const Size(390, 600));
      for (var i = 0; i < 12; i++) {
        await turn(
          tester,
          fixture,
          'Question $i',
          'A reply long enough to take a few lines of the chat, number $i, '
              'so that the conversation scrolls well past one screen.',
        );
      }
      final held = fixture.client.hold();
      await send(tester, 'One more question');
      await tester.pump();
      await tester.pump(AppMotion.enter + AppMotion.stagger * 2);
      expectAllAtRest(tester);

      // Nothing rebuilds the screen from here: no typing, only scrolling.
      // The newest rows leave the lazy list and are built again on the way
      // back, by then long settled.
      final list = find.byType(Scrollable).first;
      await tester.fling(list, const Offset(0, 3000), 3000);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('One more question'), findsNothing);
      await tester.fling(list, const Offset(0, -3000), 3000);
      for (
        var i = 0;
        i < 120 && find.text('One more question').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('One more question'), findsOneWidget);
      expectAllAtRest(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expectAllAtRest(tester);

      held.complete(
        CoachAnswer(output: jsonEncode({'reply': 'Done.', 'proposal': null})),
      );
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('history the Coach opens with is simply there', (tester) async {
      final fixture = await openCoach(tester);
      await turn(tester, fixture, 'First question', 'First answer.');

      // Open the Coach afresh over the same conversation.
      await tester.pumpWidget(fixture.app(const SizedBox.shrink()));
      await tester.pumpWidget(fixture.app(const CoachScreen()));
      expect(find.text('First question'), findsOneWidget);
      expect(find.text(_welcome), findsNothing);
      expectAllAtRest(tester);
      await pumpWithStorage(tester);
    });

    testWidgets('under reduced motion every row change is immediate', (
      tester,
    ) async {
      final fixture = await openCoach(tester, reduceMotion: true);
      final held = fixture.client.hold();
      await send(tester, 'Swap my bench');
      await tester.pump();
      expect(find.text(_welcome), findsNothing);
      expect(arrival(tester, 'Swap my bench'), 1);
      expect(arrival(tester, _thinking), 1);

      held.complete(
        CoachAnswer(
          output: jsonEncode({'reply': 'Try incline.', 'proposal': null}),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Try incline.'), findsOneWidget);
      expect(find.text(_thinking), findsNothing);
      expect(cross(tester, 'Try incline.'), 1);
      await pumpWithStorage(tester);
    });
  });

  group('around the chat', () {
    testWidgets('the welcome gives way to the conversation', (tester) async {
      final fixture = await openCoach(tester);
      fixture.client.answer('Sure.');
      await send(tester, 'Build a 4-day upper/lower');
      await tester.pump();
      // Leaving: still visible for a moment, no longer tappable.
      expect(find.text(_welcome), findsOneWidget);
      expect(takesTaps(tester, find.text(_welcome)), isFalse);
      expect(find.text('Build a 4-day upper/lower'), findsWidgets);
      await pumpWithStorage(tester);
      expect(find.text(_welcome), findsNothing);
    });

    testWidgets('a conversation started again while the last leaves scrolls '
        'on its own', (tester) async {
      final fixture = await openCoach(tester);
      await turn(tester, fixture, 'First question', 'First answer.');
      await tester.enterText(
        find.byKey(const ValueKey('coach-input')),
        'Start again',
      );
      await tester.pump(AppMotion.quick);
      // The conversation clears, and a question goes before the old chat
      // has finished leaving.
      fixture.coach.resetForAccount();
      await tester.pump();
      final held = fixture.client.hold();
      await tester.tap(find.byKey(const ValueKey('coach-send')));
      await tester.pump();
      final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
      expect(lists, hasLength(2));
      // Each chat owns its controller: one holding both positions throws
      // wherever its single position is read (the desktop scrollbar).
      expect(lists.map((list) => list.controller!.positions.length), [1, 1]);
      held.complete(
        CoachAnswer(output: jsonEncode({'reply': 'Again.', 'proposal': null})),
      );
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the connection notice folds open, and closed again', (
      tester,
    ) async {
      final fixture = _Fixture()..online = false;
      addTearDown(fixture.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(fixture.app(const CoachScreen()));
      final input = find.byKey(const ValueKey('coach-input'));
      final resting = tester.getTopLeft(find.text(_welcome)).dy;
      await tester.pump();
      await tester.pump();
      // The probe answered: the notice opens, easing the chat down.
      expect(find.text(_offline), findsOneWidget);
      await tester.pump(AppMotion.standard ~/ 2);
      final midway = tester.getTopLeft(find.text(_welcome)).dy;
      await tester.pumpAndSettle();
      final open = tester.getTopLeft(find.text(_welcome)).dy;
      expect(midway, greaterThan(resting));
      expect(midway, lessThan(open));
      expect(tester.getTopLeft(input).dy, greaterThan(0));

      // An answer clears it; it folds away and leaves the tree.
      fixture.client.answer('Back online.');
      await send(tester, 'Hello');
      await tester.pump();
      await tester.pump();
      expect(find.text(_offline), findsOneWidget);
      await pumpWithStorage(tester);
      expect(find.text(_offline), findsNothing);
    });

    testWidgets('the send button eases between quiet and ready', (
      tester,
    ) async {
      await openCoach(tester);
      final context = tester.element(find.byType(CoachScreen));
      Color ground() =>
          tester
              .widget<Material>(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('coach-send')),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color!;
      expect(ground(), controlFillColor(context));

      await tester.enterText(find.byKey(const ValueKey('coach-input')), 'Hi');
      await tester.pump();
      await tester.pump(AppMotion.quick ~/ 2);
      expect(ground(), isNot(controlFillColor(context)));
      expect(ground(), isNot(accentFillColor(context)));
      await tester.pumpAndSettle();
      expect(ground(), accentFillColor(context));

      // Typing more doesn't move it again.
      await tester.enterText(
        find.byKey(const ValueKey('coach-input')),
        'Hi there',
      );
      await tester.pump();
      expect(ground(), accentFillColor(context));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets("Apply's reason folds open and away over the buttons", (
      tester,
    ) async {
      const reason = 'Select at least one change to apply.';
      final fixture = await openCoach(tester);
      fixture.client.answerRaw(_proposal());
      await send(tester, 'Swap my bench');
      await pumpWithStorage(tester);
      await tester.tap(find.text('Review'));
      await pumpWithStorage(tester);
      final buttons = find.byKey(const ValueKey('coach-apply'));
      final resting = tester.getTopLeft(buttons).dy;

      await tester.tap(find.text('Clear all'));
      await tester.pump();
      expect(find.text(reason), findsOneWidget);
      await tester.pump(AppMotion.standard ~/ 2);
      // The bar grows as the line opens; the buttons stay at the bottom.
      expect(tester.getTopLeft(buttons).dy, resting);
      final midway = tester.getTopLeft(find.text(reason)).dy;
      await tester.pumpAndSettle();
      final open = tester.getTopLeft(find.text(reason)).dy;
      expect(midway, greaterThan(open));

      await tester.tap(find.text('Select all'));
      await tester.pump();
      // Folding away: still drawn for a moment, no longer read out.
      expect(find.text(reason), findsOneWidget);
      expect(
        tester
            .widgetList<ExcludeSemantics>(
              find.ancestor(
                of: find.text(reason),
                matching: find.byType(ExcludeSemantics),
              ),
            )
            .any((exclude) => exclude.excluding),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text(reason), findsNothing);
    });

    testWidgets('the usage meter settles to a spent request', (tester) async {
      final fixture = await openCoach(tester);
      await turn(tester, fixture, 'One', 'One.');
      fixture.client.answer('Two.', quota: const CoachQuota(used: 1, limit: 5));
      await send(tester, 'Two');
      await pumpWithStorage(tester);
      final segments = find.descendant(
        of: find.byKey(const ValueKey('coach-status')),
        matching: find.byType(AnimatedContainer),
      );
      expect(segments, findsNWidgets(5));
      expect(
        tester.widget<AnimatedContainer>(segments.first).duration,
        AppMotion.quick,
      );
    });
  });
}
