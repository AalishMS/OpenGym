import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the "install unknown apps" toggle and opens its settings screen.
///
/// Implemented in MainActivity rather than pulled in as a package: this is two
/// platform calls, and permission_handler wanted 30+ permission handlers and a
/// compileSdk bump to provide them. Must match INSTALLER_CHANNEL there.
const MethodChannel _installerChannel =
    MethodChannel('com.aalishms.opengym/installer');

/// Where the app looks for new builds. The repo is public, so the GitHub REST
/// API needs no token; unauthenticated callers get 60 requests/hour per IP,
/// which the startup throttle keeps us far below.
const String kReleasesApiUrl =
    'https://api.github.com/repos/AalishMS/OpenGym/releases/latest';

/// Requests are abandoned after this, so a captive portal or a stalled socket
/// can never leave a check hanging.
const Duration kUpdateRequestTimeout = Duration(seconds: 10);

/// An app version split into its numeric parts plus the build number.
///
/// The build number is the Android `versionCode` (the `+N` in pubspec's
/// `version:`). It is the authoritative signal for "is newer": it must strictly
/// increase every release, and Android itself refuses to install an APK whose
/// versionCode is not greater than the installed one.
@immutable
class AppVersion {
  /// Numeric components of the version name, e.g. `1.2.3` -> `[1, 2, 3]`.
  final List<int> parts;

  /// The `+N` build number, or null when the source did not carry one.
  final int? build;

  const AppVersion(this.parts, this.build);

  /// Parses a git tag or version string: `v1.2.3+4`, `1.2.3+4`, `v1.2.3`, `2.1`.
  ///
  /// Returns null for anything it cannot read with confidence. Callers treat
  /// null as "no update information", never as version zero — guessing here
  /// would either offer every release forever or silence the updater entirely.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);

    final plus = s.indexOf('+');
    String namePart = s;
    int? build;
    if (plus >= 0) {
      namePart = s.substring(0, plus);
      final buildPart = s.substring(plus + 1).trim();
      build = int.tryParse(buildPart);
      // A `+` that is present but unreadable means the tag is not shaped the
      // way we publish. Refuse it rather than silently dropping the build.
      if (build == null) return null;
    }

    final segments = namePart.split('.');
    final parts = <int>[];
    for (final segment in segments) {
      final n = int.tryParse(segment.trim());
      if (n == null) return null;
      parts.add(n);
    }
    if (parts.isEmpty) return null;
    return AppVersion(parts, build);
  }

  /// Builds a version from the two strings package_info_plus reports, where the
  /// build number arrives separately from the version name.
  static AppVersion? of(String version, String buildNumber) {
    final parsed = tryParse(version);
    if (parsed == null) return null;
    final build = int.tryParse(buildNumber.trim());
    return AppVersion(parsed.parts, build);
  }

  /// Compares version names component-wise, padding the shorter side with
  /// zeroes. Never a string compare: `1.10.0` must outrank `1.9.0`.
  int compareName(AppVersion other) {
    final len = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < len; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  String get name => parts.join('.');

  @override
  String toString() => build == null ? name : '$name+$build';
}

/// A published release, reduced to what the update prompt needs.
@immutable
class ReleaseInfo {
  final String tagName;
  final String displayVersion;
  final String changelog;
  final String htmlUrl;
  final String apkUrl;
  final int apkSize;
  final AppVersion version;

  const ReleaseInfo({
    required this.tagName,
    required this.displayVersion,
    required this.changelog,
    required this.htmlUrl,
    required this.apkUrl,
    required this.apkSize,
    required this.version,
  });

  /// Reads a GitHub release payload, returning null if it is not something we
  /// can offer as an update. Every field is treated as untrusted.
  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'];
    if (tagName is! String) return null;
    final version = AppVersion.tryParse(tagName);
    if (version == null) return null;

    final assets = json['assets'];
    if (assets is! List) return null;

    // Located by extension so renaming the artifact never breaks the updater.
    Map<String, dynamic>? apk;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is String && name.toLowerCase().endsWith('.apk')) {
        apk = asset.cast<String, dynamic>();
        break;
      }
    }
    if (apk == null) return null;

    final url = apk['browser_download_url'];
    if (url is! String || url.isEmpty) return null;
    final size = apk['size'];

    final name = json['name'];
    final body = json['body'];
    final htmlUrl = json['html_url'];

    return ReleaseInfo(
      tagName: tagName,
      displayVersion: (name is String && name.trim().isNotEmpty) ? name : tagName,
      changelog: body is String ? body.trim() : '',
      htmlUrl: htmlUrl is String ? htmlUrl : '',
      apkUrl: url,
      apkSize: size is int ? size : 0,
      version: version,
    );
  }

  Map<String, dynamic> toCache() => {
        'tag_name': tagName,
        'name': displayVersion,
        'body': changelog,
        'html_url': htmlUrl,
        'assets': [
          {'name': 'cached.apk', 'size': apkSize, 'browser_download_url': apkUrl},
        ],
      };
}

/// Renders a byte count for display. Returns an empty string when the size is
/// unknown, so the UI can omit it rather than print a confident "0 B".
String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Reads the installed version, asks GitHub what the newest release is, and
/// hands a downloaded APK to the system installer.
///
/// Every method fails soft: callers get null or false, never an exception. The
/// app is offline-first, so a failed update check must be indistinguishable
/// from not having checked.
class UpdateService {
  const UpdateService._();

  /// Whether self-updating can work at all here. `ota_update` is Android-only,
  /// and this app also builds for web and desktop, where calling it would throw.
  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  /// True when [candidate] should be offered over [installed].
  ///
  /// The build number decides whenever both sides have one, because it is what
  /// Android enforces. Only when a build number is missing does this fall back
  /// to comparing version names numerically.
  static bool isNewer({required AppVersion installed, required AppVersion candidate}) {
    final a = installed.build;
    final b = candidate.build;
    if (a != null && b != null) return b > a;
    return candidate.compareName(installed) > 0;
  }

  /// The running app's version, or null if the platform will not report it.
  static Future<AppVersion?> installedVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion.of(info.version, info.buildNumber);
    } catch (e) {
      debugPrint('UpdateService: could not read installed version: $e');
      return null;
    }
  }

  /// Fetches the latest published release, or null on any failure.
  ///
  /// Note this hits `/releases/latest`, which by design skips drafts and
  /// prereleases — the publish workflow must mark releases as neither.
  static Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
    final owned = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.get(
        Uri.parse(kReleasesApiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(kUpdateRequestTimeout);

      if (response.statusCode != 200) {
        // 404 before the first release, 403 when rate-limited. Both are normal.
        debugPrint('UpdateService: GitHub returned ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return ReleaseInfo.fromJson(decoded);
    } catch (e) {
      // No network, DNS failure, timeout, TLS error, malformed JSON.
      debugPrint('UpdateService: update check failed: $e');
      return null;
    } finally {
      if (owned) c.close();
    }
  }

  /// Whether the user has allowed this app to install APKs.
  static Future<bool> hasInstallPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final granted =
          await _installerChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return granted ?? false;
    } catch (e) {
      debugPrint('UpdateService: permission check failed: $e');
      return false;
    }
  }

  /// Sends the user to the "install unknown apps" screen when the toggle is off.
  ///
  /// Returns whether the app may install right now. This cannot wait for the
  /// user's answer — Android gives no callback and the settings screen is a
  /// separate activity — so a false return means "ask them to try again", not
  /// "they refused".
  static Future<bool> ensureInstallPermission() async {
    if (!isSupportedPlatform) return false;
    if (await hasInstallPermission()) return true;
    try {
      await _installerChannel.invokeMethod<bool>('openInstallPermissionSettings');
    } catch (e) {
      debugPrint('UpdateService: could not open install settings: $e');
    }
    // Re-read rather than assuming: on a device where the toggle was already on
    // but the first read raced, this lets the update proceed immediately.
    return hasInstallPermission();
  }

  /// Downloads [release] and hands it to the system installer, reporting
  /// progress as a 0..1 fraction.
  ///
  /// Completes when the installer has been launched. The install itself is the
  /// user's decision, and Android gives us no callback for their answer.
  static Stream<OtaEvent> downloadAndInstall(ReleaseInfo release) {
    return OtaUpdate().execute(
      release.apkUrl,
      destinationFilename: 'OpenGym-${release.tagName}.apk'.replaceAll('+', '_'),
    );
  }
}
