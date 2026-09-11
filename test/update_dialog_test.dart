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
    changelog: '''
## What's changed
- Faster workout startup
- Fixed the set editor
- Clearer progress charts
- Improved offline sync
- This fifth note belongs on GitHub
''',
    htmlUrl: 'https://github.com/AalishMS/OpenGym/releases/tag/v1.0.0%2B2',
    apkUrl: 'https://example.invalid/app.apk',
    apkSize: 1024,
    version: AppVersion.tryParse('1.0.0+2')!,
  );

  Widget host(_FakeUpdates updates, {ReleasePageLauncher? openRelease}) =>
      ChangeNotifierProvider<UpdateProvider>.value(
        value: updates,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () =>
                            showUpdateDialog(context, openRelease: openRelease),
                    child: const Text('Open'),
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
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('A new build is ready'), findsOneWidget);
    expect(find.text("What's changed"), findsOneWidget);
    expect(find.text('Faster workout startup'), findsOneWidget);
    expect(find.text('This fifth note belongs on GitHub'), findsNothing);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(updates.startCount, 1);
    await tester.tap(find.text('Cancel download'));
    await tester.pump();
    expect(updates.cancelCount, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(updates.dismissCount, 1);
  });

  testWidgets('failed dialog invokes retry and shows failure state', (
    tester,
  ) async {
    final updates = _FakeUpdates(UpdateStatus.failed, release)
      ..errorValue = 'Network unavailable';
    await tester.pumpWidget(host(updates));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Update needs attention'), findsOneWidget);
    expect(find.text('Network unavailable'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(updates.startCount, 1);
  });

  testWidgets('installing state renders progress without action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_FakeUpdates(UpdateStatus.installing, release)),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Opening installer'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Cancel download'), findsNothing);
  });

  testWidgets('GitHub action opens the exact release page', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      host(
        _FakeUpdates(UpdateStatus.available, release),
        openRelease: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View release on GitHub'));
    await tester.pump();

    expect(openedUri, release.releasePageUri);
  });

  testWidgets('failed GitHub launch gives useful feedback', (tester) async {
    await tester.pumpWidget(
      host(
        _FakeUpdates(UpdateStatus.available, release),
        openRelease: (_) async => false,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View release on GitHub'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open GitHub'), findsOneWidget);
  });

  testWidgets('update action failures are shown to the user', (tester) async {
    final updates = _FakeUpdates(UpdateStatus.available, release)
      ..throwOnStart = true;
    await tester.pumpWidget(host(updates));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(find.text('The update action failed. Try again.'), findsOneWidget);
  });

  test('release notes are normalized and capped', () {
    expect(releaseHighlights(release.changelog), [
      'Faster workout startup',
      'Fixed the set editor',
      'Clearer progress charts',
      'Improved offline sync',
    ]);
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
