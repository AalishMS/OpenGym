import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
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

  /// The APK is handed off to the system installer.
  installing,

  /// The last action failed; [UpdateProvider.error] says how.
  failed,
}

/// Owns the update check, the prompt's visibility, and the download.
///
/// Two rules shape this class:
///
/// 1. **A startup check must never be felt.** Nothing here is awaited before
///    the first frame, no failure surfaces, and the network call is throttled.
/// 2. **"Later" must not mean "never".** Dismissal lives in memory only, so it
///    clears when the process dies and the next launch prompts again. To make
///    that free, the last release payload is cached in shared_preferences and
///    the *network call* is what gets throttled — not the prompt.
class UpdateProvider with ChangeNotifier {
  static const String _lastCheckKey = 'update_last_check';
  static const String _cachedReleaseKey = 'update_cached_release';

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

  StreamSubscription<OtaEvent>? _subscription;

  UpdateStatus get status => _status;
  ReleaseInfo? get release => _release;
  double get progress => _progress;
  String? get error => _error;

  /// True while the prompt should be on screen.
  bool get isUpdateAvailable => _status == UpdateStatus.available;

  /// True while the download or install is underway, so the UI can keep the
  /// dialog open and refuse a second tap.
  bool get isBusy =>
      _status == UpdateStatus.downloading || _status == UpdateStatus.installing;

  /// The installed version formatted for Settings, e.g. `1.0.0 (1)`.
  /// Falls back to an em dash rather than inventing a number.
  String get installedVersionLabel {
    final v = _installed;
    if (v == null) return '—';
    return v.build == null ? v.name : '${v.name} (${v.build})';
  }

  /// Reads the installed version so Settings can show it. Safe to call often.
  Future<void> loadInstalledVersion() async {
    if (_installed != null) return;
    _installed = await UpdateService.installedVersion();
    if (_installed != null) notifyListeners();
  }

  /// The automatic check, called once after the first frame.
  ///
  /// Never throws, never blocks anything the user can see, and stays silent on
  /// every failure — an offline launch must be indistinguishable from a launch
  /// that found no update.
  Future<void> checkOnStartup() async {
    if (!UpdateService.isSupportedPlatform) return;
    await loadInstalledVersion();
    if (_installed == null) return;

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
    if (isBusy) return;
    if (!UpdateService.isSupportedPlatform) {
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

    if (UpdateService.isNewer(installed: _installed!, candidate: fresh.version)) {
      _release = fresh;
      _status = UpdateStatus.available;
    } else {
      _status = UpdateStatus.upToDate;
    }
    notifyListeners();
  }

  /// "Later" — hides the prompt until the next launch.
  void dismiss() {
    if (_release != null) _dismissedTag = _release!.tagName;
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

  /// Downloads the offered APK and hands it to the system installer.
  Future<void> startUpdate() async {
    final release = _release;
    if (release == null || isBusy) return;
    if (!UpdateService.isSupportedPlatform) return;

    _error = null;

    // Without this the download would succeed and the install would silently
    // do nothing, which looks exactly like a broken update.
    if (!await UpdateService.ensureInstallPermission()) {
      _fail('OpenGym needs permission to install apps. Enable "Install unknown '
          'apps" for OpenGym in system settings, then try again.');
      return;
    }

    _status = UpdateStatus.downloading;
    _progress = 0;
    notifyListeners();

    try {
      _subscription = UpdateService.downloadAndInstall(release).listen(
        _onOtaEvent,
        onError: (Object e) => _fail('Download failed: $e'),
        cancelOnError: true,
      );
    } catch (e) {
      _fail('Could not start the download: $e');
    }
  }

  /// Abandons an in-flight download.
  Future<void> cancelUpdate() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_status == UpdateStatus.downloading) {
      _status = UpdateStatus.available;
      _progress = 0;
      notifyListeners();
    }
  }

  void _onOtaEvent(OtaEvent event) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final percent = double.tryParse(event.value ?? '');
        if (percent != null) _progress = (percent / 100).clamp(0.0, 1.0);
        _status = UpdateStatus.downloading;
      case OtaStatus.INSTALLING:
        _progress = 1;
        _status = UpdateStatus.installing;
      case OtaStatus.INSTALLATION_DONE:
        // Reached only when Android installs without a confirmation screen.
        // Usually the process is replaced before this arrives.
        _status = UpdateStatus.idle;
      case OtaStatus.CANCELED:
        _status = UpdateStatus.available;
        _progress = 0;
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _error = 'Permission to install apps was denied.';
        _status = UpdateStatus.failed;
      case OtaStatus.ALREADY_RUNNING_ERROR:
        // Another download is already in flight; leave it alone.
        _status = UpdateStatus.downloading;
      case OtaStatus.DOWNLOAD_ERROR:
      case OtaStatus.CHECKSUM_ERROR:
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.INTERNAL_ERROR:
        _error = event.value?.trim().isNotEmpty == true
            ? event.value!.trim()
            : 'The update could not be installed.';
        _status = UpdateStatus.failed;
    }
    notifyListeners();
  }

  /// Records an offer, unless the release is not newer or was dismissed.
  void _offer(ReleaseInfo candidate) {
    // Never interrupt a check, a download, or an install in flight. A finished
    // check's result (upToDate/failed) is only a readout, so it may be replaced.
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }
    if (_installed == null) return;

    final newer =
        UpdateService.isNewer(installed: _installed!, candidate: candidate.version);
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
    _subscription?.cancel();
    super.dispose();
  }
}
