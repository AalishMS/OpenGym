import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/data/workout_presets.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/split_repository.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/workout_preset_installer.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/history/history_journal_data.dart';
import 'package:gymapp/widgets/splits/preset_browser_dialog.dart';
import 'package:gymapp/widgets/splits/split_dialogs.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  final hive = HiveTestHarness();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
    );
    await hive.open(includeSplits: true);
  });
  tearDownAll(hive.close);
  setUp(() async {
    await Hive.box<gym.Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    for (final id in ['Current', 'Other']) {
      await HiveService.putSplitRaw(
        gym.Split(id: id, name: id, userId: 'user', createdAt: DateTime(2026)),
      );
    }
  });

  Widget host(
    _DelayedSplits splits, {
    Widget? child,
    _DelayedSessions? sessions,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SplitProvider>.value(value: splits),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      if (sessions != null)
        ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
    ],
    child: MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
      home:
          child ??
          Builder(
            builder:
                (context) => Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        onPressed: () => SplitDialogs.showCreate(context),
                        child: const Text('Create split'),
                      ),
                      TextButton(
                        onPressed: () => SplitDialogs.showManage(context),
                        child: const Text('Manage'),
                      ),
                      TextButton(
                        onPressed: () => PresetBrowserDialog.show(context),
                        child: const Text('Presets'),
                      ),
                    ],
                  ),
                ),
          ),
    ),
  );

  for (final action in ['create', 'rename', 'delete']) {
    testWidgets('$action split cannot dismiss a pending write', (tester) async {
      final splits = _DelayedSplits();
      addTearDown(splits.dispose);
      await tester.pumpWidget(host(splits));
      if (action == 'create') {
        await tester.tap(find.text('Create split'));
      } else {
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byTooltip('${action == 'rename' ? 'Rename' : 'Delete'} Other'),
        );
      }
      await tester.pumpAndSettle();
      final title =
          action == 'create'
              ? 'New split'
              : action == 'rename'
              ? 'Rename split'
              : 'Delete split?';
      if (action != 'delete') {
        await tester.enterText(
          find.byKey(const ValueKey('split-name-field')),
          'New name',
        );
      }
      final submit =
          action == 'create'
              ? 'Create'
              : action == 'rename'
              ? 'Save'
              : 'Delete';
      await tester.tap(find.text(submit));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(title), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text(title), findsOneWidget);
      splits.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('disk full'), findsOneWidget);
      splits.pending = Completer<void>();
      await tester.tap(find.text(submit));
      await tester.pump();
      await tester.runAsync(() async {
        splits.pending.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      if (action == 'delete') {
        expect(find.text('Manage splits'), findsOneWidget);
        expect(splits.splits.any((split) => split.id == 'Other'), isFalse);
      } else {
        expect(splits.splits.any((split) => split.name == 'New name'), isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'preset install blocks Back, close, Escape and outside dismissal',
    (tester) async {
      final splits = _DelayedSplits();
      addTearDown(splits.dispose);
      await tester.pumpWidget(host(splits));
      await tester.tap(find.text('Presets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full-body hypertrophy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('install-preset-action')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('preset-details-HYP-FB-3')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back to workout presets'));
      await tester.tap(find.byTooltip('Close workout presets'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('preset-details-HYP-FB-3')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('preset-details-HYP-FB-3')),
        findsOneWidget,
      );
      splits.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('disk full'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preset-catalog')), findsOneWidget);
      splits.pending = Completer<void>();
      await tester.tap(find.text('Full-body hypertrophy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('install-preset-action')));
      await tester.pump();
      splits.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Workout presets'), findsNothing);
      expect(find.text('Installed split added and selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workout deletion keeps its dialog until the write finishes', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'session',
      planName: 'Push',
      date: DateTime(2026),
      exercises: [],
    );
    await tester.runAsync(() => HiveService.putSessionRaw(session));
    final splits = _DelayedSplits();
    final sessions = _DelayedSessions();
    addTearDown(splits.dispose);
    addTearDown(sessions.dispose);
    await tester.pumpWidget(
      host(
        splits,
        sessions: sessions,
        child: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => WorkoutDetailsScreen(
                                sessionIdentity: historySessionIdentity(
                                  session,
                                ),
                              ),
                        ),
                      ),
                  child: const Text('Open workout'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete workout?'), findsOneWidget);
    await tester.runAsync(() async {
      sessions.pending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await pumpWithStorage(tester);
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsNothing);
    expect(find.text('Open workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedSplits extends SplitProvider {
  Completer<void> pending = Completer<void>();
  _DelayedSplits()
    : super(repository: _MemorySplits(), userIdProvider: () => 'user');

  @override
  Future<void> createSplit(String rawName) async {
    await pending.future;
    await super.createSplit(rawName);
  }

  @override
  Future<void> renameSplit(String id, String rawName) async {
    await pending.future;
    await super.renameSplit(id, rawName);
  }

  @override
  Future<void> deleteSplit(String id, String replacementId) async {
    await pending.future;
    await super.deleteSplit(id, replacementId);
  }

  @override
  Future<PresetInstallResult> installPreset(WorkoutPreset preset) async {
    await pending.future;
    return const PresetInstallResult(
      splitId: 'installed',
      splitName: 'Installed split',
      reusedDefaultSplit: false,
    );
  }
}

class _DelayedSessions extends WorkoutSessionProvider {
  final Completer<void> pending = Completer<void>();
  final List<WorkoutSession> _values = HiveService.getSessions();

  @override
  List<WorkoutSession> get sessions => _values;

  @override
  Future<void> deleteSession(String id) async {
    await pending.future;
    _values.removeWhere((session) => session.id == id);
    notifyListeners();
  }
}

class _MemorySplits extends SplitRepository {
  final List<gym.Split> values = HiveService.getSplits();
  SplitPreference preference = SplitPreference(
    userId: 'user',
    activeSplitId: 'Current',
  );

  @override
  List<gym.Split> getSplits() => List.of(values);
  @override
  SplitPreference? getPreference(String userId) => preference;
  @override
  Future<void> upsertSplit(gym.Split split) async {
    values.removeWhere((value) => value.id == split.id);
    values.add(split);
  }

  @override
  Future<void> setActive(String userId, String splitId) async {
    preference = SplitPreference(userId: userId, activeSplitId: splitId);
  }

  @override
  Future<void> deleteSplit({
    required String userId,
    required String splitId,
    required String replacementSplitId,
  }) async {
    values.removeWhere((value) => value.id == splitId);
  }
}
