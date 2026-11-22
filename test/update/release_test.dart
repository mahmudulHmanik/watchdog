import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/update/release.dart';
import 'package:watchdog/features/update/update_prefs.dart';

Map<String, Object?> rel(
  String tag, {
  bool draft = false,
  bool pre = false,
  List<Map<String, Object?>>? assets,
  String body = 'notes',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': pre,
  'body': body,
  'html_url': 'https://github.com/x/y/releases/tag/$tag',
  'assets':
      assets ??
      [
        {
          'name': 'watchdog-$tag-arm64.apk',
          'browser_download_url': 'https://dl/$tag.apk',
          'size': 100,
          'digest': 'sha256:ABCDEF',
        },
      ],
};

void main() {
  group('versions', () {
    test('parse', () {
      expect(parseVersion('v0.2.0')?.minor, 2);
      expect(parseVersion('0.1.0+3')?.patch, 0);
      expect(parseVersion('1.2')?.patch, 0);
      expect(parseVersion('nightly'), isNull);
    });
    test('compare', () {
      expect(compareVersions('v0.2.0', '0.1.0+1'), greaterThan(0));
      expect(compareVersions('0.1.0', 'v0.1.0'), 0);
      expect(compareVersions('0.1.9', '0.2.0'), lessThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });
  });

  group('pickRelease', () {
    test('newest with an apk; drafts and apk-less releases skipped', () {
      final r = pickRelease([
        rel('v0.3.0', draft: true),
        rel('v0.2.5', assets: const []),
        rel('v0.2.0'),
        rel('v0.1.0'),
      ]);
      expect(r?.tag, 'v0.2.0');
      expect(r?.version, '0.2.0');
      expect(r?.apkUrl, 'https://dl/v0.2.0.apk');
      expect(r?.apkSize, 100);
      expect(r?.sha256, 'abcdef');
      expect(r?.notes, 'notes');
    });

    test('pre-releases only when allowed', () {
      final list = [rel('v0.2.0', pre: true), rel('v0.1.0')];
      expect(pickRelease(list)?.tag, 'v0.2.0');
      expect(pickRelease(list, prerelease: false)?.tag, 'v0.1.0');
    });

    test('prefers the arm64 apk', () {
      final r = pickRelease([
        rel(
          'v1.0.0',
          assets: [
            {'name': 'watchdog-x86_64.apk', 'browser_download_url': 'u1'},
            {'name': 'watchdog-arm64-v8a.apk', 'browser_download_url': 'u2'},
          ],
        ),
      ]);
      expect(r?.apkUrl, 'u2');
      expect(r?.sha256, isNull);
    });

    test('garbage in, null out', () {
      expect(pickRelease(null), isNull);
      expect(pickRelease({'message': 'Not Found'}), isNull);
      expect(pickRelease([1, 'x', <String, Object?>{}]), isNull);
    });

    test('isNewer', () {
      final r = pickRelease([rel('v0.2.0')])!;
      expect(isNewer(r, '0.1.0+1'), isTrue);
      expect(isNewer(r, '0.2.0+9'), isFalse);
      expect(isNewer(r, '0.3.0'), isFalse);
    });
  });

  group('UpdatePrefs', () {
    test('due honours switch and interval', () {
      final now = DateTime(2026, 11, 22, 12);
      expect(const UpdatePrefs().due(now), isTrue);
      expect(const UpdatePrefs(autoCheck: false).due(now), isFalse);
      final recent = UpdatePrefs(
        lastCheckMs: now
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      );
      expect(recent.due(now), isFalse);
      final old = UpdatePrefs(
        lastCheckMs: now
            .subtract(const Duration(hours: 30))
            .millisecondsSinceEpoch,
      );
      expect(old.due(now), isTrue);
    });

    test('json round trip, tolerant of junk', () {
      final p = UpdatePrefs.fromJson(
        const UpdatePrefs(autoCheck: false, lastCheckMs: 5).toJson(),
      );
      expect(p.autoCheck, isFalse);
      expect(p.lastCheckMs, 5);
      expect(UpdatePrefs.fromJson('nope').autoCheck, isTrue);
    });
  });
}
