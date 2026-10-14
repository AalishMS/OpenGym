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

  /// The system installer is open.
  installing,

  /// The last action failed; [UpdateProvider.error] says how.
  failed,
}

/// Owns the update check, the prompt's visibility, and the download.
///
/// Three rules shape this class:
///
/// 1. **A startup check must never be felt.** Nothing here is awaited before
///    the first frame, no failure surfaces, and the network call is throttled.
/// 2. **"Later" must not mean "never".** Dismissal lives in memory only, so it
///    clears when the process dies and the next launch prompts again. To make
///    that free, the last release payload is cached in shared_preferences and
///    the *network call* is what gets throttled — not the prompt.
/// 3. **Leaving the app must not lose the download.** Android's DownloadManager
///    owns it (see [UpdateDownloader]), so this class only polls for progress,
///    picks a running or finished download back up after a restart, and opens
///    the installer once the app is in front again — Android will not let a
///    background app open it.
class UpdateProvider with ChangeNotifier, WidgetsBindingObserver {
  UpdateProvider({UpdateDownloader downloader = const UpdateDownloader()})
    : _downloader = downloader;

  final UpdateDownloader _downloader;

  static const String _lastCheckKey = 'update_last_check';
  static const String _cachedReleaseKey = 'update_cached_release';
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

  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _release;
  AppVersion? _installed;
  double _progress = 0;
  String? _error;

  /// Tag the user said "Later" to. Not persisted — see the class doc.
  String? _dismissedTag;

  /// How often progress is read while the download runs.
  static const Duration pollInterval = Duration(milliseconds: 500);

  Timer? _poll;
  bool _refreshing = false;
  bool _observing = false;
  bool _waitingForNetwork = false;

  /// The user tapped "Update now" in this process, so a download that finishes
  /// while the app is in front goes straight to the installer.
  bool _installWhenReady = false;

  /// Set once the app loses focus to the installer, so the resume that follows
  /// is read as "the installer closed" rather than as a stray lifecycle event.
  bool _leftForInstaller = false;

  /// "Install unknown apps" was off and its settings screen was opened; the
  /// update continues by itself if the user switches it on and comes back.
  bool _awaitingPermission = false;

  UpdateStatus get status => _status;
  ReleaseInfo? get release => _release;
  double get progress => _progress;
  String? get error => _error;

  /// True while the prompt should be on screen: an offer, or a finished
  /// download waiting to be installed.
  bool get isUpdateAvailable =>
      _status == UpdateStatus.available || _status == UpdateStatus.downloaded;

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
    if (!_downloader.isSupported) return;
    await loadInstalledVersion();
    if (_installed == null) return;

    // A download from an earlier run, still going or finished, takes priority
    // over a fresh offer. This also deletes the APK once it has been installed.
    if (await _restoreDownload()) return;

    // Offer from the cache first. This is what re-prompts after "Later"
    // without spending a request, and it works with no network at all.
    final cached = await _readCachedRelease();
    if (cached != null) _offer(cached);

    if (!await _throttleElapsed()) return;

    // The timestamp is written for any completed attempt, not just a
    // successful one: a 403 means we are already being rate-limited, and
    // retrying on every launch would make that worse. Settings always offers
    // an unthrottled check for anyone who wants to bypass this.
    await _markChecked();

    final fresh = await UpdateService.fetchLatestRelease();
    if (fresh == null) return; // Cache-based offer, if any, still stands.
    await _writeCachedRelease(fresh);
    _offer(fresh);
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

    // An explicit check overrides an earlier "Later" for the same version:
    // asking again is a clear request to see the answer.
    if (_dismissedTag == fresh.tagName) _dismissedTag = null;

    if (UpdateService.isNewer(
      installed: _installed!,
      candidate: fresh.version,
    )) {
      _release = fresh;
      _status = UpdateStatus.available;
    } else {
      _status = UpdateStatus.upToDate;
    }
    notifyListeners();
  }

  /// "Later" — hides the prompt until the next launch. A finished download is
  /// kept, so the next launch offers to install it without fetching it again.
  void dismiss() {
    if (_release != null) _dismissedTag = _release!.tagName;
    _installWhenReady = false;
    _awaitingPermission = false;
    _status = UpdateStatus.idle;
    notifyListeners();
  }

  /// Clears a terminal message so Settings stops showing it.
  void acknowledge() {
    if (_status == UpdateStatus.upToDate || _status == UpdateStatus.failed) {
      _status = UpdateStatus.idle;
      _error = null;
      notifyListeners();
    }
  }

  /// Downloads the offered APK, or reuses a finished download of the same
  /// build, and hands it to the system installer.
  Future<void> startUpdate() async {
    if (isPreview) return;
    final release = _release;
    if (release == null || isBusy) return;
    if (!_downloader.isSupported) return;

    _error = null;
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

    final existing = await _readDownload();
    if (existing.tag == release.tagName) {
      // "Try again" after a cancelled install must not fetch 60 MB again, and
      // a download that is still running is picked up rather than restarted.
      if (existing.state == UpdateDownloadState.successful) {
        await _install();
        return;
      }
      if (existing.isActive) {
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
    try {
      await _downloader.cancel();
    } catch (e) {
      debugPrint('UpdateProvider: could not cancel the download: $e');
    }
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
      if (_status == UpdateStatus.installing) _leftForInstaller = true;
      return;
    }
    unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    switch (_status) {
      case UpdateStatus.installing:
        if (!_leftForInstaller) return;
        _leftForInstaller = false;
        InstallResult? result;
        try {
          result = await _downloader.takeInstallResult();
        } catch (e) {
          debugPrint('UpdateProvider: could not read the install result: $e');
        }
        _onInstallResult(result);
      case UpdateStatus.downloading:
        // Catch up at once instead of showing stale progress for a tick.
        await _refreshDownload();
      case UpdateStatus.downloaded:
        if (_installWhenReady) await _install();
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

  /// A successful self-update replaces this process, so arriving here at all
  /// usually means the update is not installed yet.
  void _onInstallResult(InstallResult? result) {
    if (_status != UpdateStatus.installing) return;
    switch (result?.outcome) {
      case InstallOutcome.installed:
        _status = UpdateStatus.idle;
        notifyListeners();
      case InstallOutcome.failed:
        _fail(installFailureMessage(result!.code));
      case InstallOutcome.canceled:
      case null:
        // Backed out of the installer, or it closed without saying. The file
        // is still here, so offer to install it again.
        _status = UpdateStatus.downloaded;
        _error = null;
        notifyListeners();
    }
  }

  Future<void> _install() async {
    _installWhenReady = false;
    _leftForInstaller = false;
    _status = UpdateStatus.installing;
    _progress = 1;
    notifyListeners();

    var launched = false;
    try {
      launched = await _downloader.install();
    } catch (e) {
      debugPrint('UpdateProvider: could not open the installer: $e');
    }
    if (!launched && _status == UpdateStatus.installing) {
      _fail('Could not open the Android installer. Try again.');
    }
  }

  /// Picks up a download left by an earlier run. Returns true when it now
  /// drives the prompt, false when there was nothing worth keeping.
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
      try {
        await _downloader.cancel();
      } catch (e) {
        debugPrint('UpdateProvider: could not clear an old download: $e');
      }
      return false;
    }

    _release = cached;
    _observeLifecycle();
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
      // In the background, the resume handler opens the installer instead.
      if (_installWhenReady && _inForeground) unawaited(_install());
      return;
    }
    _installWhenReady = false;
    if (ours && snapshot.state == UpdateDownloadState.failed) {
      unawaited(_discardDownload());
      _fail(downloadFailureMessage(snapshot.reason));
      return;
    }
    // The system dropped the download, for example when its list was cleared.
    _fail('The download was removed before it finished. Try again.');
  }

  Future<void> _discardDownload() async {
    try {
      await _downloader.cancel();
    } catch (e) {
      debugPrint('UpdateProvider: could not discard the download: $e');
    }
  }

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

  /// Records an offer, unless the release is not newer or was dismissed.
  void _offer(ReleaseInfo candidate) {
    // Never interrupt a check, a download, or an install in flight. A finished
    // check's result (upToDate/failed) is only a readout, so it may be replaced.
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.downloaded ||
        _status == UpdateStatus.installing) {
      return;
    }
    if (_installed == null) return;

    final newer = UpdateService.isNewer(
      installed: _installed!,
      candidate: candidate.version,
    );
    if (newer && _dismissedTag != candidate.tagName) {
      _release = candidate;
      _status = UpdateStatus.available;
      notifyListeners();
      return;
    }

    // A cached offer that the server no longer backs (a yanked release) must
    // not keep prompting.
    if (!newer && _status == UpdateStatus.available) {
      _release = null;
      _status = UpdateStatus.idle;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _stopPolling();
    _waitingForNetwork = false;
    _error = message;
    _status = UpdateStatus.failed;
    _progress = 0;
    notifyListeners();
  }

  Future<bool> _throttleElapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey);
      if (last == null) return true;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
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
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
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

  @override
  void dispose() {
    _stopPolling();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
