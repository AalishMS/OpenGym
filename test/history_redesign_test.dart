import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as google_fonts_base;
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/history/history_journal_data.dart';
import 'package:gymapp/widgets/history/history_journal_widgets.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final previewFetch =
        Platform.environment['OPENGYM_PREVIEW_ALLOW_FONT_FETCH'] == 'true';
    GoogleFonts.config.allowRuntimeFetching = previewFetch;
    if (previewFetch) {
      final fontDirectory = Platform.environment['OPENGYM_PREVIEW_FONTS']!;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => fontDirectory,
          );
      final responses = <String, List<int>>{};
      await for (final entity in Directory(fontDirectory).list()) {
        if (entity is File && entity.path.endsWith('.ttf')) {
          responses[entity.uri.pathSegments.last] = await entity.readAsBytes();
        }
      }
      google_fonts_base.httpClient = _LocalFontClient(responses);
    }
    SharedPreferences.setMockInitialValues({});
    final fontDirectory = Platform.environment['OPENGYM_PREVIEW_FONTS'];
    if (fontDirectory != null) {
      final icons = File('$fontDirectory/MaterialIcons-Regular.otf');
      if (await icons.exists()) {
        final bytes = await icons.readAsBytes();
        await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      for (final family in ['Manrope', 'JetBrainsMono']) {
        final bytes = await File('$fontDirectory/$family.ttf').readAsBytes();
        for (final weight in ['regular', '500', '600', '700']) {
          await (FontLoader('${family}_$weight')
            ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      }
    }
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_history_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  WorkoutSession session({
    required String id,
    required String name,
    required DateTime date,
    String splitId = 'a',
    bool completed = true,
    DateTime? deletedAt,
    int? durationSeconds,
    String exerciseName = 'Bench Press',
    double weight = 80,
    int reps = 5,
    String? exerciseNote,
    String? setNote,
    int? rpe,
  }) => WorkoutSession(
    id: id,
    planName: name,
    date: date,
    splitId: splitId,
    isCompleted: completed,
    deletedAt: deletedAt,
    durationSeconds: durationSeconds,
    weekNumber: 4,
    exercises: [
      Exercise(
        name: exerciseName,
        note: exerciseNote,
        sets: [Set(weight: weight, reps: reps, note: setNote, rpe: rpe)],
      ),
    ],
  );

  Widget host(
    WorkoutSessionProvider provider, {
    Widget screen = const HistoryScreen(),
    SettingsProvider? settings,
    Size size = const Size(390, 800),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    GlobalKey? repaintKey,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkoutSessionProvider>.value(value: provider),
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings ?? SettingsProvider(),
      ),
    ],
    child: RepaintBoundary(
      key: repaintKey,
      child: MaterialApp(
        key: ValueKey('history-host-${identityHashCode(provider)}'),
        theme: buildTheme(const Color(0xFF00A2FF), brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: screen,
          ),
        ),
      ),
    ),
  );

  test('groups by month and year newest first and keeps same-day workouts', () {
    final data = buildHistoryJournalData([
      session(id: 'aug', name: 'August', date: DateTime(2026, 8, 31, 18)),
      session(
        id: 'sep-old-year',
        name: 'Old September',
        date: DateTime(2025, 9, 1),
      ),
      session(
        id: 'same-late',
        name: 'Evening',
        date: DateTime(2026, 9, 11, 18),
      ),
      session(
        id: 'same-early',
        name: 'Morning',
        date: DateTime(2026, 9, 11, 7),
      ),
    ]);

    expect(
      data.groups.map((group) => historyMonthLabel(group.month, group.year)),
      ['September 2026', 'August 2026', 'September 2025'],
    );
    expect(
      data.groups.first.workouts.map((workout) => workout.session.planName),
      ['Evening', 'Morning'],
    );
  });

  test(
    'searches workout and exercise names and excludes ineligible sessions',
    () {
      final sessions = [
        session(id: 'push', name: 'Push Day', date: DateTime(2026, 9, 2)),
        session(
          id: 'pull',
          name: 'Back session',
          date: DateTime(2026, 9, 1),
          exerciseName: 'Lat Pulldown',
        ),
        session(
          id: 'draft',
          name: 'Draft match',
          date: DateTime(2026, 9, 3),
          completed: false,
        ),
        session(
          id: 'deleted',
          name: 'Deleted match',
          date: DateTime(2026, 9, 4),
          deletedAt: DateTime(2026, 9, 5),
        ),
        session(
          id: 'other-split',
          name: 'Other match',
          date: DateTime(2026, 9, 6),
          splitId: 'b',
        ),
      ];

      expect(
        buildHistoryJournalData(
          sessions,
          query: ' PUSH ',
          splitId: 'a',
        ).groups.single.workouts.single.session.id,
        'push',
      );
      expect(
        buildHistoryJournalData(
          sessions,
          query: 'pulldown',
          splitId: 'a',
        ).groups.single.workouts.single.session.id,
        'pull',
      );
      expect(
        buildHistoryJournalData(sessions, splitId: 'a').eligibleSessions,
        hasLength(2),
      );
    },
  );

  test(
    'summaries retain fractional volume and historical records before search',
    () {
      final first = session(
        id: 'first',
        name: 'Foundation',
        date: DateTime(2026, 8, 1),
        weight: 12.25,
        reps: 3,
      );
      final later = session(
        id: 'later',
        name: 'Later',
        date: DateTime(2026, 8, 8),
        weight: 20,
        reps: 3,
      );
      final data = buildHistoryJournalData([later, first], query: 'Foundation');
      final summary = data.groups.single.workouts.single;

      expect(summary.statistics.totalSets, 1);
      expect(summary.statistics.volumeLoad, 36.75);
      expect(summary.hasPersonalRecord, isTrue);
    },
  );

  testWidgets('journal search clears and split changes reset the query', (
    tester,
  ) async {
    final provider = _Sessions([
      session(id: 'a', name: 'Push Day', date: DateTime(2026, 9, 1)),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.text('No matching workouts'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pump();
    expect(find.text('Push Day'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'Push',
    );
    provider.replaceSplit('b', [
      session(
        id: 'b',
        name: 'Pull Day',
        date: DateTime(2026, 9, 2),
        splitId: 'b',
      ),
    ]);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-search-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('Pull Day'), findsOneWidget);
  });

  testWidgets('journal preserves scroll position after opening details', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    final provider = _Sessions([
      for (var index = 0; index < 18; index++)
        session(
          id: 'scroll-$index',
          name: 'Workout $index',
          date: DateTime(2026, 9, 20 - index),
        ),
    ]);
    await tester.pumpWidget(host(provider, size: const Size(390, 600)));
    await tester.pump();

    await tester.drag(
      find.byKey(const PageStorageKey('history-journal-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final listFinder = find.byKey(const PageStorageKey('history-journal-list'));
    final before = tester.widget<ListView>(listFinder).controller!.offset;
    expect(before, greaterThan(0));

    await tester.tap(find.byType(HistoryWorkoutRow).first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final after = tester.widget<ListView>(listFinder).controller!.offset;
    expect(after, moreOrLessEquals(before));
  });

  testWidgets(
    'details preserve notes, zero-rep sets, units, and return state',
    (tester) async {
      final provider = _Sessions([
        session(
          id: 'detail',
          name: 'Mixed Case Day',
          date: DateTime(2026, 9, 11),
          weight: 12.25,
          reps: 0,
          exerciseNote: 'Keep the tempo controlled across every repetition.',
          setNote: 'Warm-up only; stop if the shoulder feels tight.',
        ),
      ]);
      final settings = _Settings('lbs');
      await tester.pumpWidget(host(provider, settings: settings));
      await tester.enterText(
        find.byKey(const ValueKey('history-search-field')),
        'Mixed',
      );
      await tester.tap(find.text('Mixed Case Day'));
      await tester.pumpAndSettle();

      expect(find.text('Workout details'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workout-details-readout')),
        findsOneWidget,
      );
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('Performed sets'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('Weight (lbs)'), findsOneWidget);
      expect(find.text('27.0'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('tempo controlled'), findsOneWidget);
      expect(find.textContaining('Warm-up only'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('history-search-field')),
            )
            .controller
            ?.text,
        'Mixed',
      );
    },
  );

  testWidgets('PR attempt is a compact marker beside the set weight', (
    tester,
  ) async {
    final provider = _Sessions([
      session(
        id: 'pr-attempt',
        name: 'Strength day',
        date: DateTime(2026, 9, 11),
        setNote: 'PR attempt',
      ),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.tap(find.text('Strength day'));
    await tester.pumpAndSettle();

    expect(find.text('PR attempt'), findsNothing);
    expect(find.text('PR'), findsOneWidget);
    expect(
      tester.getCenter(find.text('PR')).dy,
      moreOrLessEquals(tester.getCenter(find.text('80')).dy, epsilon: 1),
    );
  });

  testWidgets('successful edit refreshes details and failed edit keeps draft', (
    tester,
  ) async {
    final provider = _Sessions([
      session(id: 'edit', name: 'Original', date: DateTime(2026, 9, 11)),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workout-name-field')),
      'Updated',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Workout updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    provider.failUpdate = true;
    await tester.enterText(
      find.byKey(const ValueKey('workout-name-field')),
      'Recoverable draft',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);
    expect(find.textContaining('Your edits are still here'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('workout-name-field')))
          .controller
          ?.text,
      'Recoverable draft',
    );
  });

  testWidgets('delete supports cancel, failure retry, and confirmed removal', (
    tester,
  ) async {
    final provider = _Sessions([
      session(id: 'delete', name: 'Delete Me', date: DateTime(2026, 9, 11)),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.tap(find.text('Delete Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete “Delete Me” from 11 Sep 2026?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);

    provider.failDelete = true;
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-workout-error')), findsOneWidget);
    expect(find.text('Delete workout?'), findsOneWidget);

    provider.failDelete = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No completed workouts'), findsOneWidget);
  });

  testWidgets('journal, details, editing, and empty states do not overflow', (
    tester,
  ) async {
    final output = Platform.environment['OPENGYM_PREVIEW_DIR'];
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final brightness in Brightness.values) {
      for (final scenario in [
        (const Size(320, 800), 1.0),
        (const Size(390, 800), 2.0),
        (const Size(1000, 800), 1.0),
      ]) {
        final provider = _Sessions([
          session(
            id: 'visual',
            name: 'Long lower-body training session',
            date: DateTime(2026, 9, 11),
            exerciseName: 'Single-leg Romanian deadlift',
            exerciseNote: 'Use a slow lowering phase and keep the hips level.',
            setNote: 'Left side first, then match repetitions on the right.',
          ),
        ]);
        tester.view.physicalSize = scenario.$1;
        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          host(
            provider,
            brightness: brightness,
            size: scenario.$1,
            textScale: scenario.$2,
            repaintKey: repaintKey,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (output != null) {
          await _writePreview(
            tester,
            repaintKey,
            output,
            'history-${brightness.name}-${scenario.$1.width}-${scenario.$2}x',
          );
        }
        await tester.tap(find.text('Long lower-body training session'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output != null && scenario.$1.width == 390) {
          await _writePreview(
            tester,
            repaintKey,
            output,
            'history-details-${brightness.name}-${scenario.$2}x',
          );
        }
        await tester.tap(find.byTooltip('Workout actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output != null && scenario.$1.width == 390) {
          await _writePreview(
            tester,
            repaintKey,
            output,
            'history-edit-${brightness.name}-${scenario.$2}x',
          );
        }
      }
    }

    final emptyKey = GlobalKey();
    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpWidget(
      host(_Sessions([]), size: const Size(320, 800), repaintKey: emptyKey),
    );
    await tester.pump();
    expect(find.text('No completed workouts'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (output != null) {
      await _writePreview(tester, emptyKey, output, 'history-empty-light-320');
    }
  });
}

Future<void> _writePreview(
  WidgetTester tester,
  GlobalKey key,
  String output,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pump();
}

class _Sessions extends WorkoutSessionProvider {
  _Sessions(List<WorkoutSession> sessions) : _sessions = List.of(sessions);

  List<WorkoutSession> _sessions;
  String _splitId = 'a';
  bool failUpdate = false;
  bool failDelete = false;

  @override
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  @override
  String? get activeSplitId => _splitId;

  void replaceSplit(String splitId, List<WorkoutSession> sessions) {
    _splitId = splitId;
    _sessions = List.of(sessions);
    notifyListeners();
  }

  @override
  Future<void> updateSession(WorkoutSession updated) async {
    if (failUpdate) throw StateError('update failed');
    final index = _sessions.indexWhere((session) => session.id == updated.id);
    _sessions[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteSession(String id) async {
    if (failDelete) throw StateError('delete failed');
    _sessions.removeWhere((session) => session.id == id);
    notifyListeners();
  }
}

class _Settings extends SettingsProvider {
  _Settings(this.unit);

  final String unit;

  @override
  String get weightUnit => unit;
}

class _LocalFontClient extends http.BaseClient {
  _LocalFontClient(this.responses);

  final Map<String, List<int>> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = responses[request.url.pathSegments.last];
    return http.StreamedResponse(
      Stream.value(bytes ?? const <int>[]),
      bytes == null ? 404 : 200,
    );
  }
}
