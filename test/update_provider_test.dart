import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/services/update_service.dart';

void main() {
  final release = ReleaseInfo(
    tagName: 'v1.0.1+2',
    displayVersion: 'OpenGym v1.0.1',
    changelog: '- Faster workout startup',
    htmlUrl: 'https://github.com/AalishMS/OpenGym/releases/tag/v1.0.1%2B2',
    apkUrl: 'https://example.invalid/app.apk',
    apkSize: 100,
    version: AppVersion.tryParse('1.0.1+2')!,
  );

  /// Installs build [build] and caches [release] as already fetched, so the
  /// startup check offers it without touching the network.
  void seed({String build = '1'}) {
    PackageInfo.setMockInitialValues(
      appName: 'OpenGym',
      packageName: 'com.aalishms.opengym',
      version: '1.0.0',
      buildNumber: build,
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'update_cached_release': jsonEncode(release.toCache()),
      'update_last_check': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
  }

  UpdateDownloadSnapshot running(int downloaded, {int reason = 0}) =>
      UpdateDownloadSnapshot(
        state:
            reason == 0
                ? UpdateDownloadState.running
                : UpdateDownloadState.paused,
        tag: release.tagName,
        downloadedBytes: downloaded,
        totalBytes: 100,
        reason: reason,
      );

  final finished = UpdateDownloadSnapshot(
    state: UpdateDownloadState.successful,
    tag: release.tagName,
    downloadedBytes: 100,
    totalBytes: 100,
  );

  /// An offer on screen, ready for "Update now".
  Future<(UpdateProvider, _FakeDownloader)> offered(WidgetTester tester) async {
    seed();
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader();
    final updates = UpdateProvider(downloader: downloader);
    await updates.checkOnStartup();
    expect(updates.status, UpdateStatus.available);
    return (updates, downloader);
  }

  testWidgets('a download finished in the background installs on return', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);

    await updates.startUpdate();
    expect(downloader.starts, 1);
    expect(updates.status, UpdateStatus.downloading);

    // Screen off or another app: the system keeps downloading.
    await lifecycle(tester, AppLifecycleState.paused);
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    expect(updates.status, UpdateStatus.downloaded);
    expect(
      downloader.installs,
      0,
      reason: 'Android blocks this from the background',
    );

    await lifecycle(tester, AppLifecycleState.resumed);
    expect(downloader.installs, 1);
    expect(updates.status, UpdateStatus.installing);
    updates.dispose();
  });

  testWidgets('a download finished in front opens the installer at once', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);

    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();

    expect(downloader.installs, 1);
    expect(updates.status, UpdateStatus.installing);
    updates.dispose();
  });

  testWidgets('progress follows the system download, including network waits', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);

    await updates.startUpdate();
    downloader.snapshot = running(50);
    await tester.pump(UpdateProvider.pollInterval);
    expect(updates.progress, 0.5);
    expect(updates.isWaitingForNetwork, isFalse);

    // PAUSED_WAITING_FOR_NETWORK
    downloader.snapshot = running(60, reason: 2);
    await tester.pump(UpdateProvider.pollInterval);
    expect(updates.progress, 0.6);
    expect(updates.isWaitingForNetwork, isTrue);
    expect(updates.status, UpdateStatus.downloading);
    updates.dispose();
  });

  testWidgets(
    'backing out of the installer offers it again without a refetch',
    (tester) async {
      final (updates, downloader) = await offered(tester);
      await updates.startUpdate();
      downloader.snapshot = finished;
      await tester.pump(UpdateProvider.pollInterval);
      await tester.pump();
      expect(updates.status, UpdateStatus.installing);

      downloader.installResult = const InstallResult(InstallOutcome.canceled);
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(updates.status, UpdateStatus.downloaded);
      expect(updates.isUpdateAvailable, isTrue);
      expect(updates.isBusy, isFalse);

      await updates.startUpdate();
      expect(downloader.starts, 1, reason: 'the finished file is reused');
      expect(downloader.installs, 2);
      updates.dispose();
    },
  );

  testWidgets('an installer that closes without an answer does not hang', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();

    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(updates.status, UpdateStatus.downloaded);
    updates.dispose();
  });

  testWidgets('a signing mismatch is explained instead of retried blindly', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();

    downloader.installResult = const InstallResult(InstallOutcome.failed, -7);
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(updates.status, UpdateStatus.failed);
    expect(updates.error, contains('signed differently'));
    updates.dispose();
  });

  testWidgets('a failed download says why and frees the space', (tester) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();

    downloader.snapshot = UpdateDownloadSnapshot(
      state: UpdateDownloadState.failed,
      tag: release.tagName,
      reason: 1006,
    );
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();

    expect(updates.status, UpdateStatus.failed);
    expect(updates.error, contains('free storage'));
    expect(downloader.cancels, 1);
    updates.dispose();
  });

  testWidgets('cancel stops the system download', (tester) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();

    await updates.cancelUpdate();
    expect(downloader.cancels, 1);
    expect(updates.status, UpdateStatus.available);

    // Nothing left polling, and nothing will open the installer later.
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval * 2);
    expect(downloader.installs, 0);
    updates.dispose();
  });

  testWidgets('a restart picks up a finished download', (tester) async {
    seed();
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader()..snapshot = finished;
    final updates = UpdateProvider(downloader: downloader);

    await updates.checkOnStartup();
    expect(updates.status, UpdateStatus.downloaded);
    expect(updates.release?.tagName, release.tagName);
    expect(downloader.installs, 0, reason: 'the user decides after a restart');
    updates.dispose();
  });

  testWidgets('a restart picks up a running download and keeps polling', (
    tester,
  ) async {
    seed();
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader()..snapshot = running(30);
    final updates = UpdateProvider(downloader: downloader);

    await updates.checkOnStartup();
    expect(updates.status, UpdateStatus.downloading);
    expect(updates.progress, 0.3);

    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();
    expect(downloader.installs, 1);
    updates.dispose();
  });

  testWidgets('the first launch after updating deletes the old APK', (
    tester,
  ) async {
    seed(build: '2');
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader()..snapshot = finished;
    final updates = UpdateProvider(downloader: downloader);

    await updates.checkOnStartup();
    expect(downloader.cancels, 1);
    expect(updates.status, UpdateStatus.idle);
    updates.dispose();
  });

  testWidgets('allowing installs in settings continues the update on return', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    downloader.permission = false;

    await updates.startUpdate();
    expect(updates.status, UpdateStatus.failed);
    expect(downloader.starts, 0);

    downloader.permission = true;
    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(downloader.starts, 1);
    expect(updates.status, UpdateStatus.downloading);
    updates.dispose();
  });
}

class _FakeDownloader extends UpdateDownloader {
  UpdateDownloadSnapshot snapshot = UpdateDownloadSnapshot.none;
  InstallResult? installResult;
  bool permission = true;
  int starts = 0;
  int installs = 0;
  int cancels = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasInstallPermission() async => permission;

  @override
  Future<bool> ensureInstallPermission() async => permission;

  @override
  Future<void> start(ReleaseInfo release) async {
    starts++;
    snapshot = UpdateDownloadSnapshot(
      state: UpdateDownloadState.pending,
      tag: release.tagName,
    );
  }

  @override
  Future<UpdateDownloadSnapshot> status() async => snapshot;

  @override
  Future<void> cancel() async {
    cancels++;
    snapshot = UpdateDownloadSnapshot.none;
  }

  @override
  Future<bool> install() async {
    installs++;
    return true;
  }

  @override
  Future<InstallResult?> takeInstallResult() async {
    final result = installResult;
    installResult = null;
    return result;
  }
}
