import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/services/update_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/update_dialog.dart';

void main() {
  final release = ReleaseInfo(
    tagName: 'v1.0.0+2',
    displayVersion: 'OpenGym v1.0.0',
    changelog: '- Fixes',
    htmlUrl: 'https://example.invalid/release',
    apkUrl: 'https://example.invalid/app.apk',
    apkSize: 1024,
    version: AppVersion.tryParse('1.0.0+2')!,
  );

  Widget host(_FakeUpdates updates) =>
      ChangeNotifierProvider<UpdateProvider>.value(
        value: updates,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => showUpdateDialog(context),
                    child: const Text('[OPEN]'),
                  ),
            ),
          ),
        ),
      );

  testWidgets('available dialog invokes update and later callbacks', (
    tester,
  ) async {
    final updates = _FakeUpdates(UpdateStatus.available, release);
    await tester.pumpWidget(host(updates));
    await tester.tap(find.text('[OPEN]'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('[UPDATE]'));
    await tester.pump();
    expect(updates.startCount, 1);
    await tester.tap(find.text('[CANCEL]'));
    await tester.pump();
    expect(updates.cancelCount, 1);
    await tester.tap(find.text('[LATER]'));
    await tester.pumpAndSettle();
    expect(updates.dismissCount, 1);
  });

  testWidgets('failed dialog invokes retry and shows failure state', (
    tester,
  ) async {
    final updates = _FakeUpdates(UpdateStatus.failed, release)
      ..errorValue = 'Network unavailable';
    await tester.pumpWidget(host(updates));
    await tester.tap(find.text('[OPEN]'));
    await tester.pumpAndSettle();
    expect(find.text('Update failed'), findsOneWidget);
    expect(find.text('Network unavailable'), findsOneWidget);
    await tester.tap(find.text('[RETRY]'));
    await tester.pump();
    expect(updates.startCount, 1);
  });

  testWidgets('installing state renders progress without action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_FakeUpdates(UpdateStatus.installing, release)),
    );
    await tester.tap(find.text('[OPEN]'));
    await tester.pump();
    expect(find.text('Opening the installer...'), findsOneWidget);
    expect(find.text('[UPDATE]'), findsNothing);
    expect(find.text('[CANCEL]'), findsNothing);
  });

  testWidgets('update action failures are shown to the user', (tester) async {
    final updates = _FakeUpdates(UpdateStatus.available, release)
      ..throwOnStart = true;
    await tester.pumpWidget(host(updates));
    await tester.tap(find.text('[OPEN]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[UPDATE]'));
    await tester.pumpAndSettle();
    expect(find.textContaining('update failed'), findsOneWidget);
  });
}

class _FakeUpdates extends UpdateProvider {
  _FakeUpdates(this.status, this.release);

  @override
  UpdateStatus status;
  @override
  final ReleaseInfo release;
  String? errorValue;
  var startCount = 0;
  var cancelCount = 0;
  var dismissCount = 0;
  var throwOnStart = false;

  @override
  double get progress => 0.42;
  @override
  String? get error => errorValue;
  @override
  Future<void> startUpdate() async {
    startCount++;
    if (throwOnStart) throw StateError('update failed');
    status = UpdateStatus.downloading;
    notifyListeners();
  }

  @override
  Future<void> cancelUpdate() async {
    cancelCount++;
    status = UpdateStatus.available;
    notifyListeners();
  }

  @override
  void dismiss() {
    dismissCount++;
    status = UpdateStatus.idle;
    notifyListeners();
  }

  @override
  Future<void> loadInstalledVersion() async {}
}
