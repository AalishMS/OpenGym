import 'dart:async';
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
  void seed({
    String build = '1',
    bool autoDownload = false,
    Map<String, Object> extra = const {},
  }) {
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
      'update_auto_download': autoDownload,
      ...extra,
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

      downloader.onEvent!(
        const InstallResultEvent(InstallResult(InstallOutcome.confirming)),
      );
      downloader.installResult = const InstallResult(InstallOutcome.canceled);
      await lifecycle(tester, AppLifecycleState.paused);
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
    downloader.onEvent!(
      const InstallResultEvent(InstallResult(InstallOutcome.confirming)),
    );

    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    // The answer may trail the resume, so it is given a moment first.
    expect(updates.status, UpdateStatus.installing);
    await tester.pump(UpdateProvider.installResultGrace);
    await tester.pump();
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

    downloader.onEvent!(
      const InstallResultEvent(InstallResult(InstallOutcome.confirming)),
    );
    downloader.installResult = const InstallResult(InstallOutcome.failed, -7);
    await lifecycle(tester, AppLifecycleState.paused);
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

  UpdateDownloadSnapshot background(
    UpdateDownloadState state, {
    int reason = 0,
  }) => UpdateDownloadSnapshot(
    state: state,
    tag: release.tagName,
    downloadedBytes: state == UpdateDownloadState.successful ? 100 : 0,
    totalBytes: 100,
    reason: reason,
    background: true,
  );

  group('background downloads', () {
    testWidgets('an offer starts a Wi-Fi-only download when enabled', (
      tester,
    ) async {
      seed(autoDownload: true);
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader = _FakeDownloader();
      final updates = UpdateProvider(downloader: downloader);

      await updates.checkOnStartup();
      expect(updates.status, UpdateStatus.available);
      expect(downloader.starts, 1);
      expect(downloader.lastStartBackground, isTrue);
      updates.dispose();
    });

    testWidgets('nothing downloads by itself when turned off', (tester) async {
      final (updates, downloader) = await offered(tester);
      expect(downloader.starts, 0);
      updates.dispose();
    });

    testWidgets('turning it off stops an unfinished background download', (
      tester,
    ) async {
      seed(autoDownload: true);
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader = _FakeDownloader();
      final updates = UpdateProvider(downloader: downloader);
      await updates.checkOnStartup();

      await updates.setAutoDownload(false);
      expect(downloader.cancels, 1);
      expect(updates.autoDownload, isFalse);
      updates.dispose();
    });

    testWidgets('a finished background download installs without refetching', (
      tester,
    ) async {
      seed(autoDownload: true);
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader =
          _FakeDownloader()
            ..snapshot = background(UpdateDownloadState.successful);
      final updates = UpdateProvider(downloader: downloader);

      await updates.checkOnStartup();
      expect(updates.status, UpdateStatus.downloaded);
      expect(downloader.installs, 0, reason: 'the user has not asked yet');

      await updates.startUpdate();
      expect(downloader.starts, 0);
      expect(downloader.installs, 1);
      expect(downloader.backgroundMarks, [false]);
      updates.dispose();
    });

    testWidgets('a resume notices a background download that finished', (
      tester,
    ) async {
      seed(autoDownload: true);
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader = _FakeDownloader();
      final updates = UpdateProvider(downloader: downloader);
      await updates.checkOnStartup();
      expect(updates.status, UpdateStatus.available);

      downloader.snapshot = background(UpdateDownloadState.successful);
      await updates.checkOnResume();
      expect(updates.status, UpdateStatus.downloaded);
      updates.dispose();
    });

    testWidgets('Update now restarts a download held back for Wi-Fi', (
      tester,
    ) async {
      seed(autoDownload: true);
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader =
          _FakeDownloader()
            ..snapshot = background(UpdateDownloadState.paused, reason: 3);
      final updates = UpdateProvider(downloader: downloader);
      await updates.checkOnStartup();
      expect(downloader.starts, 0, reason: 'the queued download is kept');

      await updates.startUpdate();
      expect(downloader.starts, 1);
      expect(downloader.lastStartBackground, isFalse);
      expect(updates.status, UpdateStatus.downloading);
      updates.dispose();
    });
  });

  group('when the prompt opens by itself', () {
    testWidgets('once per release, then again after the snooze', (
      tester,
    ) async {
      var now = DateTime.now();
      seed();
      await lifecycle(tester, AppLifecycleState.resumed);
      final updates = UpdateProvider(
        downloader: _FakeDownloader(),
        clock: () => now,
      );
      await updates.checkOnStartup();

      expect(await updates.shouldPromptAutomatically(), isTrue);
      await updates.markPrompted();
      expect(await updates.shouldPromptAutomatically(), isFalse);

      now = now.add(UpdateProvider.snooze);
      expect(await updates.shouldPromptAutomatically(), isTrue);
      updates.dispose();
    });

    testWidgets('Later keeps the offer for the Settings badge', (tester) async {
      final (updates, _) = await offered(tester);
      updates.dismiss();
      await tester.pump(); // Lets the snooze record land.
      expect(updates.status, UpdateStatus.available);
      expect(updates.hasPendingUpdate, isTrue);
      expect(await updates.shouldPromptAutomatically(), isFalse);
      updates.dispose();
    });

    testWidgets('a download the user started asks until put off', (
      tester,
    ) async {
      seed();
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader = _FakeDownloader()..snapshot = finished;
      final updates = UpdateProvider(downloader: downloader);
      await updates.checkOnStartup();
      await updates.markPrompted();

      expect(await updates.shouldPromptAutomatically(), isTrue);
      updates.dismiss();
      await tester.pump();
      expect(downloader.backgroundMarks, [true]);
      expect(await updates.shouldPromptAutomatically(), isFalse);
      updates.dispose();
    });

    testWidgets('the "Update ready" notification overrides the snooze', (
      tester,
    ) async {
      seed(
        extra: {
          'update_prompted_tag': release.tagName,
          'update_prompted_at': DateTime.now().millisecondsSinceEpoch,
        },
      );
      await lifecycle(tester, AppLifecycleState.resumed);
      final downloader = _FakeDownloader()..openRequest = true;
      final updates = UpdateProvider(downloader: downloader);
      await updates.checkOnStartup();

      expect(await updates.shouldPromptAutomatically(), isTrue);
      expect(await updates.shouldPromptAutomatically(), isFalse);
      updates.dispose();
    });

    testWidgets('the notification while running asks the shell to open it', (
      tester,
    ) async {
      final (updates, downloader) = await offered(tester);
      var opened = 0;
      final sub = updates.openRequests.listen((_) => opened++);

      downloader.onEvent!(const OpenUpdateEvent());
      await tester.pump();
      expect(opened, 1);
      unawaited(sub.cancel());
      updates.dispose();
    });
  });

  testWidgets('a finished download waits out a workout', (tester) async {
    final (updates, downloader) = await offered(tester);
    var workoutLive = true;
    updates.canInterrupt = () async => !workoutLive;

    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();
    expect(updates.status, UpdateStatus.downloaded);
    expect(downloader.installs, 0);

    workoutLive = false;
    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(downloader.installs, 1);
    updates.dispose();
  });

  testWidgets('a pushed install answer is handled without a resume', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();
    expect(updates.status, UpdateStatus.installing);

    downloader.onEvent!(
      const InstallResultEvent(InstallResult(InstallOutcome.canceled)),
    );
    expect(updates.status, UpdateStatus.downloaded);
    updates.dispose();
  });

  testWidgets('a damaged download is discarded and explained', (tester) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();

    downloader.onEvent!(
      const InstallResultEvent(InstallResult(InstallOutcome.corrupt)),
    );
    await tester.pump();
    expect(updates.status, UpdateStatus.failed);
    expect(updates.error, kCorruptDownloadMessage);
    expect(downloader.cancels, 1);

    await updates.startUpdate();
    expect(downloader.starts, 2, reason: 'Try again downloads it afresh');
    updates.dispose();
  });

  testWidgets('the confirm screen is waited on, and a shade pull is ignored', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();
    expect(updates.status, UpdateStatus.installing);

    // Still staging: a notification shade pull is not the installer.
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(UpdateProvider.installResultGrace);
    expect(updates.status, UpdateStatus.installing);

    // The confirm screen is up; no timeout while the user reads it.
    downloader.onEvent!(
      const InstallResultEvent(InstallResult(InstallOutcome.confirming)),
    );
    await tester.pump(UpdateProvider.installTimeout * 2);
    expect(updates.status, UpdateStatus.installing);

    // Backing out of it without an answer hands the button back.
    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(UpdateProvider.installResultGrace);
    await tester.pump();
    expect(updates.status, UpdateStatus.downloaded);
    updates.dispose();
  });

  testWidgets('a damaged release is not fetched in the background again', (
    tester,
  ) async {
    seed(autoDownload: true, extra: {'update_corrupt_tag': 'v1.0.1+2'});
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader();
    final updates = UpdateProvider(downloader: downloader);
    await updates.checkOnStartup();
    expect(updates.status, UpdateStatus.available);
    expect(downloader.starts, 0);
    updates.dispose();
  });

  testWidgets('a failed background download is retried', (tester) async {
    seed(autoDownload: true);
    await lifecycle(tester, AppLifecycleState.resumed);
    final downloader = _FakeDownloader();
    final updates = UpdateProvider(downloader: downloader);
    await updates.checkOnStartup();
    expect(downloader.starts, 1);

    downloader.snapshot = background(UpdateDownloadState.failed);
    await updates.checkOnResume();
    expect(downloader.starts, 2);
    updates.dispose();
  });

  testWidgets('an install that never answers hands the button back', (
    tester,
  ) async {
    final (updates, downloader) = await offered(tester);
    await updates.startUpdate();
    downloader.snapshot = finished;
    await tester.pump(UpdateProvider.pollInterval);
    await tester.pump();
    expect(updates.status, UpdateStatus.installing);

    await tester.pump(UpdateProvider.installTimeout);
    expect(updates.status, UpdateStatus.downloaded);
    updates.dispose();
  });

  group("what's new", () {
    testWidgets('shows once on the first launch of a new build', (
      tester,
    ) async {
      seed(build: '2', extra: {'update_last_seen_build': 1});
      await lifecycle(tester, AppLifecycleState.resumed);
      final updates = UpdateProvider(downloader: _FakeDownloader());
      await updates.checkOnStartup();

      expect(updates.takeWhatsNew()?.tagName, release.tagName);
      expect(updates.takeWhatsNew(), isNull);
      updates.dispose();

      final relaunched = UpdateProvider(downloader: _FakeDownloader());
      await relaunched.checkOnStartup();
      expect(relaunched.takeWhatsNew(), isNull);
      relaunched.dispose();
    });

    testWidgets('stays quiet on a fresh install', (tester) async {
      seed(build: '2');
      await lifecycle(tester, AppLifecycleState.resumed);
      final updates = UpdateProvider(downloader: _FakeDownloader());
      await updates.checkOnStartup();
      expect(updates.takeWhatsNew(), isNull);
      updates.dispose();
    });
  });
}

class _FakeDownloader extends UpdateDownloader {
  UpdateDownloadSnapshot snapshot = UpdateDownloadSnapshot.none;
  InstallResult? installResult;
  bool permission = true;
  bool openRequest = false;
  int starts = 0;
  int installs = 0;
  int cancels = 0;
  bool? lastStartBackground;
  final List<bool> backgroundMarks = [];
  void Function(UpdatePlatformEvent event)? onEvent;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasInstallPermission() async => permission;

  @override
  Future<bool> ensureInstallPermission() async => permission;

  @override
  Future<void> start(ReleaseInfo release, {bool background = false}) async {
    starts++;
    lastStartBackground = background;
    snapshot = UpdateDownloadSnapshot(
      state: UpdateDownloadState.pending,
      tag: release.tagName,
      background: background,
    );
  }

  @override
  Future<void> setBackground(bool background) async {
    backgroundMarks.add(background);
  }

  @override
  Future<UpdateDownloadSnapshot> status() async => snapshot;

  @override
  Future<void> cancel() async {
    cancels++;
    snapshot = UpdateDownloadSnapshot.none;
  }

  @override
  Future<bool> install(ReleaseInfo release) async {
    installs++;
    return true;
  }

  @override
  Future<InstallResult?> takeInstallResult() async {
    final result = installResult;
    installResult = null;
    return result;
  }

  @override
  Future<bool> canUpdateSilently() async => false;

  @override
  Future<bool> takeOpenUpdateRequest() async {
    final requested = openRequest;
    openRequest = false;
    return requested;
  }

  @override
  void listen(void Function(UpdatePlatformEvent event) onEvent) {
    this.onEvent = onEvent;
  }
}
