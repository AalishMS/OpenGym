import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/services/update_service.dart';

/// A trimmed but structurally faithful copy of what
/// GET /repos/AalishMS/OpenGym/releases/latest returns.
const _releaseJson = '''
{
  "tag_name": "v1.2.0+7",
  "name": "OpenGym v1.2.0",
  "body": "- Added the in-app updater\\n- Fixed a crash",
  "html_url": "https://github.com/AalishMS/OpenGym/releases/tag/v1.2.0%2B7",
  "draft": false,
  "prerelease": false,
  "assets": [
    {
      "name": "OpenGym-v1.2.0+7.apk.sha256",
      "size": 64,
      "browser_download_url": "https://example.invalid/checksum"
    },
    {
      "name": "OpenGym-v1.2.0+7.apk",
      "size": 24117248,
      "browser_download_url": "https://example.invalid/OpenGym.apk"
    }
  ]
}
''';

void main() {
  group('AppVersion.tryParse', () {
    test('parses a tag with a leading v and a build number', () {
      final v = AppVersion.tryParse('v1.2.3+4')!;
      expect(v.parts, [1, 2, 3]);
      expect(v.build, 4);
    });

    test('parses a tag without a leading v', () {
      final v = AppVersion.tryParse('1.2.3+4')!;
      expect(v.parts, [1, 2, 3]);
      expect(v.build, 4);
    });

    test('parses a tag with no build number, leaving build null', () {
      final v = AppVersion.tryParse('v1.2.3')!;
      expect(v.parts, [1, 2, 3]);
      expect(v.build, isNull);
    });

    test('parses a short version name', () {
      expect(AppVersion.tryParse('v2.1')!.parts, [2, 1]);
    });

    test('tolerates surrounding whitespace', () {
      expect(AppVersion.tryParse('  v1.0.0+1  ')!.build, 1);
    });

    test('reads the build number package_info_plus reports separately', () {
      final v = AppVersion.of('1.0.0', '3')!;
      expect(v.parts, [1, 0, 0]);
      expect(v.build, 3);
    });

    test('treats an empty package_info_plus build number as absent', () {
      expect(AppVersion.of('1.0.0', '')!.build, isNull);
    });

    test('returns null for input it cannot parse', () {
      for (final bad in ['', '   ', 'v', 'latest', 'nightly-build', 'v+4']) {
        expect(AppVersion.tryParse(bad), isNull, reason: 'input was "$bad"');
      }
    });

    test('returns null rather than throwing on a non-numeric build', () {
      expect(AppVersion.tryParse('v1.2.3+abc'), isNull);
    });
  });

  group('UpdateService.isNewer — build number is authoritative', () {
    AppVersion v(String s) => AppVersion.tryParse(s)!;

    test('a higher build number is newer', () {
      expect(UpdateService.isNewer(installed: v('1.0.0+1'), candidate: v('1.0.1+2')), isTrue);
    });

    test('an equal build number is not newer', () {
      expect(UpdateService.isNewer(installed: v('1.0.0+2'), candidate: v('1.0.1+2')), isFalse);
    });

    test('a lower build number is not newer, even with a higher version name', () {
      // Guards the exact trap the build number exists to avoid: Android would
      // reject this APK as a downgrade, so we must not offer it.
      expect(UpdateService.isNewer(installed: v('1.0.0+9'), candidate: v('2.0.0+3')), isFalse);
    });

    test('build numbers win over version names that sort the other way', () {
      expect(UpdateService.isNewer(installed: v('1.9.0+4'), candidate: v('1.10.0+5')), isTrue);
    });
  });

  group('UpdateService.isNewer — numeric fallback when a build is absent', () {
    AppVersion v(String s) => AppVersion.tryParse(s)!;

    test('compares version names component-wise, not as strings', () {
      // String comparison would call "1.10.0" older than "1.9.0".
      expect(UpdateService.isNewer(installed: v('1.9.0'), candidate: v('1.10.0')), isTrue);
      expect(UpdateService.isNewer(installed: v('1.10.0'), candidate: v('1.9.0')), isFalse);
    });

    test('an identical version name is not newer', () {
      expect(UpdateService.isNewer(installed: v('1.2.3'), candidate: v('1.2.3')), isFalse);
    });

    test('pads missing components with zero', () {
      expect(UpdateService.isNewer(installed: v('1.2'), candidate: v('1.2.1')), isTrue);
      expect(UpdateService.isNewer(installed: v('1.2.0'), candidate: v('1.2')), isFalse);
    });

    test('falls back when only one side carries a build number', () {
      expect(UpdateService.isNewer(installed: v('1.0.0+1'), candidate: v('1.0.1')), isTrue);
      expect(UpdateService.isNewer(installed: v('1.0.0'), candidate: v('1.0.1+2')), isTrue);
    });
  });

  group('ReleaseInfo.fromJson', () {
    test('reads every field the update prompt needs', () {
      final r = ReleaseInfo.fromJson(jsonDecode(_releaseJson) as Map<String, dynamic>)!;
      expect(r.tagName, 'v1.2.0+7');
      expect(r.displayVersion, 'OpenGym v1.2.0');
      expect(r.changelog, contains('in-app updater'));
      expect(r.htmlUrl, contains('github.com'));
      expect(r.version.build, 7);
    });

    test('finds the .apk asset by extension, not by position or name', () {
      final r = ReleaseInfo.fromJson(jsonDecode(_releaseJson) as Map<String, dynamic>)!;
      expect(r.apkUrl, 'https://example.invalid/OpenGym.apk');
      expect(r.apkSize, 24117248);
    });

    test('is not fooled by an asset that merely contains .apk', () {
      final json = jsonDecode(_releaseJson) as Map<String, dynamic>;
      json['assets'] = [
        {'name': 'notes.apk.txt', 'size': 1, 'browser_download_url': 'https://x.invalid/a'},
      ];
      expect(ReleaseInfo.fromJson(json), isNull);
    });

    test('returns null when the release carries no APK', () {
      final json = jsonDecode(_releaseJson) as Map<String, dynamic>;
      json['assets'] = <dynamic>[];
      expect(ReleaseInfo.fromJson(json), isNull);
    });

    test('returns null when the tag cannot be parsed', () {
      final json = jsonDecode(_releaseJson) as Map<String, dynamic>;
      json['tag_name'] = 'nightly';
      expect(ReleaseInfo.fromJson(json), isNull);
    });

    test('returns null on missing or malformed fields instead of throwing', () {
      expect(ReleaseInfo.fromJson(<String, dynamic>{}), isNull);
      expect(ReleaseInfo.fromJson({'tag_name': 'v1.0.0+1'}), isNull);
      expect(ReleaseInfo.fromJson({'assets': 'not-a-list'}), isNull);
    });

    test('falls back to the tag when the release has no name', () {
      final json = jsonDecode(_releaseJson) as Map<String, dynamic>;
      json['name'] = null;
      expect(ReleaseInfo.fromJson(json)!.displayVersion, 'v1.2.0+7');
    });

    test('tolerates a null body, which GitHub sends for an empty changelog', () {
      final json = jsonDecode(_releaseJson) as Map<String, dynamic>;
      json['body'] = null;
      expect(ReleaseInfo.fromJson(json)!.changelog, isEmpty);
    });
  });

  group('formatBytes', () {
    test('renders a download size the way a person reads it', () {
      expect(formatBytes(24117248), '23.0 MB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(512), '512 B');
    });

    test('does not claim a size it was never given', () {
      expect(formatBytes(0), isEmpty);
      expect(formatBytes(-1), isEmpty);
    });
  });
}
