import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';

/// What the updater is currently doing, and therefore what the UI may show.
enum UpdateStatus {
  /// Nothing to report. The only state in which the app stays silent.
  idle,

  /// A manual check is in flight.
  checking,

  /// A newer release is ready to offer.
  available,

  /// A manual check finished and found nothing newer.
  upToDate,

  /// The APK is coming down; [UpdateProvider.progress] is meaningful.
  downloading,

  /// The APK is on the phone and waiting for the user to install it.
  downloaded,

  /// The install is underway: Android is installing, or showing its confirm
  /// screen.
  installing,

  /// The last action failed; [UpdateProvider.error] says how.
  failed,
}

/// Owns the update check, when the prompt may appear, and the download.
///
/// Four rules shape this class:
///
/// 1. **A check must never be felt.** Nothing here is awaited before the first
///    frame, no automatic failure surfaces, and the network call is throttled.
///    Checks run at launch and whenever the app returns to the front, because
///    a gym app can sit in memory for days.
/// 2. **Offer once, then wait.** The prompt opens on its own at most once per
///    release every [snooze]; in between, the update stays visible as a badge
///    on Settings. "Later" still never means "never". The last release
///    payload is cached so the offer survives being offline.
/// 3. **Have the file ready before asking.** With auto-download on, a release
///    is fetched in the background over Wi-Fi only, so "Update now" can
///    install at once. A download the user started is theirs; one the app
///    started is never announced.
/// 4. **Leaving the app must not lose the download.** Android's DownloadManager
///    owns it (see [UpdateDownloader]), so this class only polls for progress
///    and picks a running or finished download back up after a restart.
class UpdateProvider with ChangeNotifier, WidgetsBindingObserver {
  UpdateProvider({
    UpdateDownloader downloader = const UpdateDownloader(),
    DateTime Function()? clock,
  }) : _downloader = downloader,
       _clock = clock ?? DateTime.now;

  final UpdateDownloader _downloader;
  final DateTime Function() _clock;

  static const String _lastCheckKey = 'update_last_check';
  static const String _cachedReleaseKey = 'update_cached_release';
  static const String _promptedTagKey = 'update_prompted_tag';
  static const String _promptedAtKey = 'update_prompted_at';
  static const String _autoDownloadKey = 'update_auto_download';
  static const String _lastSeenBuildKey = 'update_last_seen_build';
  static const String _corruptTagKey = 'update_corrupt_tag';
  static const bool _previewUpdate = bool.fromEnvironment(
    'OPENGYM_PREVIEW_UPDATE',
  );

  /// A local UI preview that never checks GitHub or installs an APK.
  bool get isPreview => kDebugMode && _previewUpdate;

  void _showPreview() {
    _installed = const AppVersion([0, 0, 0], 0);
    _release = const ReleaseInfo(
      tagName: 'preview',
      displayVersion: 'OpenGym preview',
      changelog: '''
- Faster workout startup
- Improved set logging
- Clearer progress charts
- More reliable offline sync
''',
      htmlUrl: kReleasesPageUrl,
      apkUrl: 'https://example.invalid/preview.apk',
      apkSize: 25 * 1024 * 1024,
      version: AppVersion([1, 0, 0], 999),
    );
    _error = null;
    _status = UpdateStatus.available;
    notifyListeners();
  }

  /// How long to wait between automatic network checks. Unauthenticated GitHub
  /// allows 60 requests/hour per IP; four a day leaves that untouched. The
  /// manual check in Settings deliberately ignores this.
  static const Duration throttle = Duration(hours: 6);

  /// How long an offer stays quiet after it was shown or put off.
  static const Duration snooze = Duration(days: 3);

  /// How often progress is read while the download runs.
  static const Duration pollInterval = Duration(milliseconds: 500);

  /// How long to wait for Android to answer an install before handing the
  /// button back.
  static const Duration installTimeout = Duration(minutes: 2);

  /// How long to wait after returning from the confirm screen for its answer.
  static const Duration installResultGrace = Duration(milliseconds: 1500);

  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _release;
  AppVersion? _installed;
  double _progress = 0;
  String? _error;

  Timer? _poll;
  Timer? _installTimer;
  bool _refreshing = false;
  bool _observing = false;
  bool _listening = false;
  bool _started = false;
  bool _waitingForNetwork = false;
  bool _autoDownload = true;
  bool _silentInstall = false;

  /// The user asked for this download, so it is theirs to be told about.
  bool _userStarted = false;

  /// Opened from the "Update ready" notification: show the prompt regardless
  /// of [snooze].
  bool _openRequested = false;

  /// The release that was just installed, shown once as "What's new".
  ReleaseInfo? _whatsNew;

  final StreamController<void> _openRequests =
      StreamController<void>.broadcast();

  /// The user tapped "Update now" (or tapped it before a restart), so a
  /// download that finishes while the app is in front goes straight to the
  /// installer.
  bool _installWhenReady = false;

  /// Android's confirm screen is showing for the current install.
  bool _confirming = false;

  /// Set once the app goes to the background behind the confirm screen, so
  /// the resume that follows is read as "the installer closed" rather than
  /// as a pulled-down notification shade.
  bool _leftForInstaller = false;

  /// A release whose download failed its checksum. It is not fetched in the
  /// background again: if the published digest is wrong, that would repeat a
  /// 60 MB download on every resume.
  String? _corruptTag;

  /// "Install unknown apps" was off and its settings screen was opened; the
  /// update continues by itself if the user switches it on and comes back.
  bool _awaitingPermission = false;

  /// Whether a finished download may be installed without another tap. Asked
  /// at that moment, not cached: the shell answers false during a workout, so
  /// an update can never close the app mid-session. The user can still tap
  /// Install themselves.
  Future<bool> Function() canInterrupt = _always;
  static Future<bool> _always() async => true;

  UpdateStatus get status => _status;
  ReleaseInfo? get release => _release;
  double get progress => _progress;
  String? get error => _error;

  /// Whether new releases download in the background over Wi-Fi.
  bool get autoDownload => _autoDownload;

  /// Android will probably install without a confirmation screen. A guess for
  /// the copy only.
  bool get installsSilently => _silentInstall;

  /// Fires when the user opened the app from the "Update ready" notification.
  Stream<void> get openRequests => _openRequests.stream;

  /// True while the prompt should be on screen: an offer, or a finished
  /// download waiting to be installed.
  bool get isUpdateAvailable =>
      _status == UpdateStatus.available || _status == UpdateStatus.downloaded;

  /// True while there is something to act on, for the Settings badge.
  bool get hasPendingUpdate => isUpdateAvailable || isBusy;

  /// True while a download is paused until the phone is back online.
  bool get isWaitingForNetwork =>
      _status == UpdateStatus.downloading && _waitingForNetwork;

  /// True while the download or install is underway, so the UI can keep the
  /// dialog open and refuse a second tap.
  bool get isBusy =>
      _status == UpdateStatus.downloading || _status == UpdateStatus.installing;

  /// The installed version formatted for Settings, e.g. `Version 11`.
  /// Falls back to an em dash rather than inventing a number.
  String get installedVersionLabel {
    final v = _installed;
    if (v == null) return '—';
    return v.displayLabel;
  }

  /// Reads the installed version so Settings can show it. Safe to call often.
  Future<void> loadInstalledVersion() async {
    if (_installed != null) return;
    _installed =
        isPreview
            ? const AppVersion([0, 0, 0], 0)
            : await UpdateService.installedVersion();
    if (_installed != null) notifyListeners();
  }

  /// The automatic check, called once after the first frame.
  ///
  /// Never throws, never blocks anything the user can see, and stays silent on
  /// every failure — an offline launch must be indistinguishable from a launch
  /// that found no update.
  Future<void> checkOnStartup() async {
    if (isPreview) {
      _showPreview();
      return;
    }
    if (!_downloader.isSupported || _started) return;
    await loadInstalledVersion();
    if (_installed == null) return;
    _started = true;
    _listen();
    _observeLifecycle();
    await _loadPreferences();
    await _noteInstalledBuild();
    _silentInstall = await _ask(_downloader.canUpdateSilently, false);
    _openRequested = await _ask(_downloader.takeOpenUpdateRequest, false);

    // A download the user started in an earlier run, still going or finished,
    // drives the prompt. This also deletes the APK once it has been installed.
    if (await _restoreDownload()) return;

    // Offer from the cache first. This is what re-offers without spending a
    // request, and it works with no network at all.
    final cached = await _readCachedRelease();
    if (cached != null) _offer(cached);

    await _checkNetwork();
  }

  /// The check when the app returns to the front. Same rules as at launch:
  /// throttled and silent.
  Future<void> checkOnResume() async {
    if (isPreview || !_started) return;
    if (_status == UpdateStatus.checking || isBusy) return;
    await _syncBackgroundDownload();
    await _checkNetwork();
  }

  /// Whether the shell should open the prompt by itself now. Call
  /// [markPrompted] when it does.
  Future<bool> shouldPromptAutomatically() async {
    if (isPreview) return isUpdateAvailable;
    if (_openRequested) {
      _openRequested = false;
      if (hasPendingUpdate) return true;
    }
    // A download the user started shows its progress or asks to install.
    if (isBusy || _status == UpdateStatus.downloaded) {
      if (_userStarted) return true;
    }
    final release = _release;
    if (!isUpdateAvailable || release == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tag = prefs.getString(_promptedTagKey);
      final at = prefs.getInt(_promptedAtKey);
      if (tag == release.tagName && at != null) {
        final elapsed = _clock().millisecondsSinceEpoch - at;
        if (elapsed >= 0 && elapsed < snooze.inMilliseconds) return false;
      }
    } catch (e) {
      debugPrint('UpdateProvider: could not read the prompt record: $e');
      return false; // Better quiet than nagging on every launch.
    }
    return true;
  }

  /// Records that the current offer was shown, which starts its [snooze].
  Future<void> markPrompted() async {
    final release = _release;
    if (release == null || isPreview) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_promptedTagKey, release.tagName);
      await prefs.setInt(_promptedAtKey, _clock().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('UpdateProvider: could not record the prompt: $e');
    }
  }

  /// The release that was just installed, once. Null on every other launch.
  ReleaseInfo? takeWhatsNew() {
    final release = _whatsNew;
    _whatsNew = null;
    return release;
  }

  /// Turns background downloads on or off. Turning them off stops one that
  /// has not finished; a finished file is kept because it costs nothing more.
  Future<void> setAutoDownload(bool value) async {
    if (_autoDownload == value) return;
    _autoDownload = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoDownloadKey, value);
    } catch (e) {
      debugPrint('UpdateProvider: could not save auto-download: $e');
    }
    if (!_downloader.isSupported || isPreview) return;
    if (value) {
      await _maybeDownloadInBackground();
      return;
    }
    final snapshot = await _readDownload();
    if (snapshot.background && snapshot.isActive) await _discardDownload();
  }

  /// The Settings check. Ignores the throttle and reports its outcome, because
  /// here the user asked and silence would read as a broken button.
  Future<void> checkManually() async {
    if (isBusy || _status == UpdateStatus.downloaded) return;
    if (isPreview) {
      _showPreview();
      return;
    }
    if (!_downloader.isSupported) {
      _error = 'Self-updating is only available on Android.';
      _status = UpdateStatus.failed;
      notifyListeners();
      return;
    }

    _status = UpdateStatus.checking;
    _error = null;
    notifyListeners();

    await loadInstalledVersion();
    if (_installed == null) {
      _fail('Could not read the installed version.');
      return;
    }

    await _markChecked();
    final fresh = await UpdateService.fetchLatestRelease();
    if (fresh == null) {
      _fail('Could not reach GitHub. Check your connection and try again.');
      return;
    }
    await _writeCachedRelease(fresh);

    if (UpdateService.isNewer(
      installed: _installed!,
      candidate: fresh.version,
    )) {
      _release = fresh;
      _status = UpdateStatus.available;
      notifyListeners();
      // A prefetched file for this build turns the offer into "install now".
      await _syncBackgroundDownload();
    } else {
      _status = UpdateStatus.upToDate;
      notifyListeners();
    }
  }

  /// "Later": closes the prompt and starts its [snooze]. The offer itself
  /// stays, so Settings and the tab badge still show it, and a finished
  /// download is kept so installing later needs no second download.
  void dismiss() {
    _installWhenReady = false;
    _awaitingPermission = false;
    _openRequested = false;
    if (_userStarted && _status == UpdateStatus.downloaded) {
      // Put off: the file is the app's now, and stops claiming every launch.
      unawaited(_quietly(() => _downloader.setBackground(true)));
    }
    _userStarted = false;
    if (_status == UpdateStatus.failed) {
      _error = null;
      final release = _release;
      final installed = _installed;
      _status =
          release != null &&
                  installed != null &&
                  UpdateService.isNewer(
                    installed: installed,
                    candidate: release.version,
                  )
              ? UpdateStatus.available
              : UpdateStatus.idle;
    }
    notifyListeners();
    unawaited(markPrompted());
  }

  /// Clears a terminal message so Settings stops showing it.
  void acknowledge() {
    if (_status == UpdateStatus.upToDate || _status == UpdateStatus.failed) {
      _status = UpdateStatus.idle;
      _error = null;
      notifyListeners();
    }
  }

  /// Downloads the offered APK, or reuses a download of the same build, and
  /// installs it.
  Future<void> startUpdate() async {
    if (isPreview) return;
    final release = _release;
    if (release == null || isBusy) return;
    if (!_downloader.isSupported) return;

    _error = null;
    _listen();
    _observeLifecycle();

    // Without this the download would succeed and the install would silently
    // do nothing, which looks exactly like a broken update.
    if (!await _downloader.ensureInstallPermission()) {
      _awaitingPermission = true;
      _fail(
        'OpenGym needs permission to install apps. Enable "Install unknown '
        'apps" for OpenGym in system settings, then come back.',
      );
      return;
    }
    _awaitingPermission = false;
    _installWhenReady = true;
    _userStarted = true;

    final existing = await _readDownload();
    if (existing.tag == release.tagName) {
      if (existing.background) {
        await _quietly(() => _downloader.setBackground(false));
      }
      // "Try again" after a cancelled install must not fetch 60 MB again, and
      // a download that is still running is picked up rather than restarted.
      if (existing.state == UpdateDownloadState.successful) {
        await _install();
        return;
      }
      // A background download held back for Wi-Fi is restarted below with
      // mobile data allowed: the user is asking now.
      if (existing.isActive && !existing.isWaitingForWifi) {
        _status = UpdateStatus.downloading;
        _applyProgress(existing);
        notifyListeners();
        _startPolling();
        return;
      }
    }

    _status = UpdateStatus.downloading;
    _progress = 0;
    _waitingForNetwork = false;
    notifyListeners();

    try {
      await _downloader.start(release);
    } catch (e) {
      debugPrint('UpdateProvider: could not start the download: $e');
      _fail(
        'Could not start the download. Try again, or get the update from '
        'GitHub.',
      );
      return;
    }
    _startPolling();
  }

  /// Abandons the download and deletes whatever had arrived.
  Future<void> cancelUpdate() async {
    _stopPolling();
    _installWhenReady = false;
    _userStarted = false;
    await _discardDownload();
    if (_status == UpdateStatus.downloading ||
        _status == UpdateStatus.downloaded) {
      _status = UpdateStatus.available;
      _progress = 0;
      _waitingForNetwork = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Only a real trip away counts. `inactive` is also a pulled-down shade,
      // and before the confirm screen is up the file is still being staged.
      final away =
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
      if (_status == UpdateStatus.installing && _confirming && away) {
        _leftForInstaller = true;
      }
      return;
    }
    unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    switch (_status) {
      case UpdateStatus.installing:
        if (!_leftForInstaller) return;
        _leftForInstaller = false;
        // Back from the confirm screen. Its answer is pushed, but may land
        // just after the resume; read anything that arrived unheard, then
        // give it a moment before handing the button back.
        final pending = await _ask(_downloader.takeInstallResult, null);
        if (pending != null) {
          _onInstallResult(pending);
          return;
        }
        await Future<void>.delayed(installResultGrace);
        if (_status != UpdateStatus.installing) return;
        _onInstallResult(await _ask(_downloader.takeInstallResult, null));
      case UpdateStatus.downloading:
        // Catch up at once instead of showing stale progress for a tick.
        await _refreshDownload();
      case UpdateStatus.downloaded:
        if (_installWhenReady && await canInterrupt()) {
          if (_status == UpdateStatus.downloaded) await _install();
        }
      case UpdateStatus.failed when _awaitingPermission:
        if (await _downloader.hasInstallPermission()) {
          _awaitingPermission = false;
          _status = UpdateStatus.available;
          _error = null;
          await startUpdate();
        }
      default:
        break;
    }
  }

  void _onPlatformEvent(UpdatePlatformEvent event) {
    switch (event) {
      case InstallResultEvent(:final result):
        _onInstallResult(result);
      case OpenUpdateEvent():
        if (hasPendingUpdate) _openRequests.add(null);
    }
  }

  /// A successful self-update replaces this process, so arriving here at all
  /// usually means the update is not installed yet.
  void _onInstallResult(InstallResult? result) {
    if (_status != UpdateStatus.installing) return;
    _installTimer?.cancel();
    _installTimer = null;
    if (result?.outcome == InstallOutcome.confirming) {
      // The user is reading Android's confirm screen; wait for them however
      // long it takes. Their answer, or the resume, settles it.
      _confirming = true;
      return;
    }
    _confirming = false;
    _leftForInstaller = false;
    switch (result?.outcome) {
      case InstallOutcome.installed:
        _status = UpdateStatus.idle;
        notifyListeners();
      case InstallOutcome.failed:
        _fail(installFailureMessage(result!.code));
      case InstallOutcome.corrupt:
        _userStarted = false;
        _corruptTag = _release?.tagName;
        unawaited(_rememberCorrupt(_corruptTag));
        unawaited(_discardDownload());
        _fail(kCorruptDownloadMessage);
      case InstallOutcome.confirming: // Handled above.
      case InstallOutcome.canceled:
      case null:
        // Backed out of the confirm screen, or it closed without saying. The
        // file is still here, so offer to install it again.
        _status = UpdateStatus.downloaded;
        _error = null;
        notifyListeners();
    }
  }

  Future<void> _install() async {
    final release = _release;
    if (release == null) return;
    _installWhenReady = false;
    _leftForInstaller = false;
    _confirming = false;
    _status = UpdateStatus.installing;
    _progress = 1;
    notifyListeners();

    var launched = false;
    try {
      launched = await _downloader.install(release);
    } catch (e) {
      debugPrint('UpdateProvider: could not start the install: $e');
    }
    if (!launched) {
      if (_status == UpdateStatus.installing) {
        _fail('Could not start the install. Try again.');
      }
      return;
    }
    // A silent install ends this process. If neither that, nor an answer,
    // nor the confirm screen arrives, do not leave the dialog spinning
    // forever. Showing the confirm screen stops this timer.
    _installTimer?.cancel();
    _installTimer = Timer(installTimeout, () => _onInstallResult(null));
  }

  /// Picks up a download left by an earlier run. Returns true when a download
  /// the user started now drives the prompt; false otherwise, including when
  /// a background download was found and adopted.
  Future<bool> _restoreDownload() async {
    final snapshot = await _readDownload();
    if (snapshot.state == UpdateDownloadState.none) return false;

    final version = AppVersion.tryParse(snapshot.tag);
    final cached = await _readCachedRelease();
    final wanted =
        version != null &&
        cached != null &&
        cached.tagName == snapshot.tag &&
        UpdateService.isNewer(installed: _installed!, candidate: version);
    final usable =
        snapshot.isActive || snapshot.state == UpdateDownloadState.successful;
    if (!wanted || !usable) {
      // Already installed, superseded, or failed: free the space.
      await _discardDownload();
      return false;
    }

    _release = cached;
    if (snapshot.background) {
      // Ours: a finished one becomes "ready to install"; a running one keeps
      // going quietly while the cached offer is made as usual.
      if (snapshot.state == UpdateDownloadState.successful) {
        _status = UpdateStatus.downloaded;
        _progress = 1;
        notifyListeners();
      }
      return false;
    }

    _userStarted = true;
    if (snapshot.state == UpdateDownloadState.successful) {
      _status = UpdateStatus.downloaded;
      _progress = 1;
    } else {
      // The user started this one, so finish the job when it lands.
      _installWhenReady = true;
      _status = UpdateStatus.downloading;
      _applyProgress(snapshot);
      _startPolling();
    }
    notifyListeners();
    return true;
  }

  /// Fetches the latest release when the throttle allows, then makes sure a
  /// background download is underway for whatever is on offer.
  Future<void> _checkNetwork() async {
    if (await _throttleElapsed()) {
      // The timestamp is written for any completed attempt, not just a
      // successful one: a 403 means we are already being rate-limited, and
      // retrying on every launch would make that worse. Settings always
      // offers an unthrottled check for anyone who wants to bypass this.
      await _markChecked();
      final fresh = await UpdateService.fetchLatestRelease();
      if (fresh != null) {
        await _writeCachedRelease(fresh);
        _offer(fresh);
      }
    }
    await _maybeDownloadInBackground();
  }

  /// Starts a Wi-Fi-only download of the offered release, or notices one that
  /// already finished.
  Future<void> _maybeDownloadInBackground() async {
    if (!_autoDownload || _status != UpdateStatus.available) return;
    final release = _release;
    if (release == null || release.tagName == _corruptTag) return;
    final snapshot = await _readDownload();
    if (snapshot.tag == release.tagName &&
        snapshot.state != UpdateDownloadState.failed) {
      _adoptFinished(snapshot, release);
      return; // Running or finished: nothing to start.
    }
    // Never replace a download the user is waiting on.
    if (snapshot.isActive && !snapshot.background) return;
    if (_status != UpdateStatus.available || _release != release) return;
    try {
      await _downloader.start(release, background: true);
    } catch (e) {
      debugPrint('UpdateProvider: could not start a background download: $e');
    }
  }

  /// Turns an offer into "ready to install" when its file has arrived.
  Future<void> _syncBackgroundDownload() async {
    final release = _release;
    if (_status != UpdateStatus.available || release == null) return;
    final snapshot = await _readDownload();
    if (snapshot.tag == release.tagName) _adoptFinished(snapshot, release);
  }

  void _adoptFinished(UpdateDownloadSnapshot snapshot, ReleaseInfo release) {
    if (snapshot.state != UpdateDownloadState.successful) return;
    if (_status != UpdateStatus.available || _release != release) return;
    _status = UpdateStatus.downloaded;
    _progress = 1;
    notifyListeners();
  }

  Future<UpdateDownloadSnapshot> _readDownload() async {
    try {
      return await _downloader.status();
    } catch (e) {
      debugPrint('UpdateProvider: could not read the download: $e');
      return UpdateDownloadSnapshot.none;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => _refreshDownload());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refreshDownload() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      _onDownloadSnapshot(await _readDownload());
    } finally {
      _refreshing = false;
    }
  }

  void _onDownloadSnapshot(UpdateDownloadSnapshot snapshot) {
    if (_status != UpdateStatus.downloading) {
      _stopPolling();
      return;
    }
    final ours = snapshot.tag != null && snapshot.tag == _release?.tagName;

    if (ours && snapshot.isActive) {
      _applyProgress(snapshot);
      notifyListeners();
      return;
    }

    _stopPolling();
    _waitingForNetwork = false;
    if (ours && snapshot.state == UpdateDownloadState.successful) {
      _progress = 1;
      _status = UpdateStatus.downloaded;
      notifyListeners();
      // In the background, the resume handler installs instead. During a
      // workout it waits for the user's own tap.
      if (_installWhenReady && _inForeground) {
        unawaited(_installIfAllowed());
      }
      return;
    }
    _installWhenReady = false;
    _userStarted = false;
    if (ours && snapshot.state == UpdateDownloadState.failed) {
      unawaited(_discardDownload());
      _fail(downloadFailureMessage(snapshot.reason));
      return;
    }
    // The system dropped the download, for example when its list was cleared.
    _fail('The download was removed before it finished. Try again.');
  }

  Future<void> _installIfAllowed() async {
    if (!await canInterrupt()) return;
    if (_status == UpdateStatus.downloaded && _installWhenReady) {
      await _install();
    }
  }

  Future<void> _discardDownload() =>
      _quietly(() => _downloader.cancel());

  void _applyProgress(UpdateDownloadSnapshot snapshot) {
    final fraction = snapshot.fraction;
    if (fraction != null) _progress = fraction;
    _waitingForNetwork = snapshot.isWaitingForNetwork;
  }

  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _observeLifecycle() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    try {
      _downloader.listen(_onPlatformEvent);
    } catch (e) {
      debugPrint('UpdateProvider: could not listen for installer events: $e');
    }
  }

  /// Records an offer, unless the release is not newer.
  void _offer(ReleaseInfo candidate) {
    final installed = _installed;
    if (installed == null) return;
    final newer = UpdateService.isNewer(
      installed: installed,
      candidate: candidate.version,
    );

    // Never interrupt a check, a download, or an install in flight. A file
    // the app fetched by itself may be replaced by a newer release, though;
    // the next background download then supersedes it.
    final current = _release;
    final supersedesPrefetch =
        _status == UpdateStatus.downloaded &&
        !_userStarted &&
        current != null &&
        newer &&
        UpdateService.isNewer(
          installed: current.version,
          candidate: candidate.version,
        );
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing ||
        (_status == UpdateStatus.downloaded && !supersedesPrefetch)) {
      return;
    }

    if (newer) {
      if (_status == UpdateStatus.available &&
          current?.tagName == candidate.tagName) {
        return;
      }
      _release = candidate;
      _status = UpdateStatus.available;
      notifyListeners();
      return;
    }

    // A cached offer that the server no longer backs (a yanked release) must
    // not keep prompting.
    if (_status == UpdateStatus.available) {
      _release = null;
      _status = UpdateStatus.idle;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _stopPolling();
    _installTimer?.cancel();
    _installTimer = null;
    _waitingForNetwork = false;
    _error = message;
    _status = UpdateStatus.failed;
    _progress = 0;
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoDownload = prefs.getBool(_autoDownloadKey) ?? true;
      _corruptTag = prefs.getString(_corruptTagKey);
    } catch (e) {
      debugPrint('UpdateProvider: could not read update settings: $e');
    }
  }

  /// Remembers the running build, and when it went up since the last launch,
  /// keeps its release notes for a one-time "What's new".
  Future<void> _noteInstalledBuild() async {
    final build = _installed?.build;
    if (build == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_lastSeenBuildKey);
      if (lastSeen != null && build > lastSeen) {
        final cached = await _readCachedRelease();
        if (cached != null && cached.version.build == build) {
          _whatsNew = cached;
        }
      }
      if (lastSeen != build) await prefs.setInt(_lastSeenBuildKey, build);
    } catch (e) {
      debugPrint('UpdateProvider: could not record the installed build: $e');
    }
  }

  Future<void> _rememberCorrupt(String? tag) async {
    if (tag == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_corruptTagKey, tag);
    } catch (e) {
      debugPrint('UpdateProvider: could not record the damaged download: $e');
    }
  }

  Future<bool> _throttleElapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey);
      if (last == null) return true;
      final elapsed = _clock().millisecondsSinceEpoch - last;
      // A negative gap means the clock moved backwards; treat it as due.
      return elapsed < 0 || elapsed >= throttle.inMilliseconds;
    } catch (e) {
      debugPrint('UpdateProvider: could not read the throttle: $e');
      return false; // Skip the check rather than risk hammering the API.
    }
  }

  Future<void> _markChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, _clock().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('UpdateProvider: could not record the check time: $e');
    }
  }

  Future<ReleaseInfo?> _readCachedRelease() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachedReleaseKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ReleaseInfo.fromJson(decoded);
    } catch (e) {
      debugPrint('UpdateProvider: could not read the cached release: $e');
      return null;
    }
  }

  Future<void> _writeCachedRelease(ReleaseInfo release) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedReleaseKey, jsonEncode(release.toCache()));
    } catch (e) {
      debugPrint('UpdateProvider: could not cache the release: $e');
    }
  }

  /// Runs a platform call whose failure only matters as a log line.
  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('UpdateProvider: $e');
    }
  }

  /// Runs a platform query, answering [fallback] if it fails.
  static Future<T> _ask<T>(Future<T> Function() query, T fallback) async {
    try {
      return await query();
    } catch (e) {
      debugPrint('UpdateProvider: $e');
      return fallback;
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _installTimer?.cancel();
    unawaited(_openRequests.close());
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
