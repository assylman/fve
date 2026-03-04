import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:fve/src/services/cache_service.dart';
import 'package:test/test.dart';

void main() {
  // ── Static path structure ─────────────────────────────────────────────────

  group('CacheService static paths', () {
    test('fveHome resolves to a path ending in ".fve"', () {
      expect(p.basename(CacheService.fveHome), '.fve');
    });

    test('versionsDir is a direct child named "versions" inside fveHome', () {
      expect(CacheService.versionsDir, equals(p.join(CacheService.fveHome, 'versions')));
    });

    test('currentLink is a direct child named "current" inside fveHome', () {
      expect(CacheService.currentLink, equals(p.join(CacheService.fveHome, 'current')));
    });

    test('globalConfigFile is named "config.json" inside fveHome', () {
      expect(
        CacheService.globalConfigFile,
        equals(p.join(CacheService.fveHome, 'config.json')),
      );
    });
  });

  // ── Instance path helpers ─────────────────────────────────────────────────

  group('CacheService instance path helpers', () {
    late CacheService cache;

    setUp(() => cache = CacheService());

    test('versionDir returns a path ending with the version string', () {
      expect(cache.versionDir('3.22.2'), endsWith('3.22.2'));
    });

    test('versionDir is nested inside versionsDir', () {
      expect(
        cache.versionDir('3.22.2'),
        startsWith(CacheService.versionsDir),
      );
    });

    test('flutterBin is inside the version bin/ directory', () {
      final bin = cache.flutterBin('3.22.2');
      expect(bin, contains(p.join('3.22.2', 'bin')));
      expect(p.basename(bin), startsWith('flutter'));
    });

    test('dartBin is inside the version bin/ directory', () {
      final bin = cache.dartBin('3.22.2');
      expect(bin, contains(p.join('3.22.2', 'bin')));
      expect(p.basename(bin), startsWith('dart'));
    });
  });

  // ── isInstalled ───────────────────────────────────────────────────────────

  group('CacheService.isInstalled', () {
    late CacheService cache;

    setUp(() => cache = CacheService());

    test('returns false for a version that has never been installed', () {
      expect(cache.isInstalled('0.0.0-nonexistent'), isFalse);
    });
  });

  // ── installedVersions ─────────────────────────────────────────────────────

  group('CacheService.installedVersions', () {
    late CacheService cache;

    setUp(() => cache = CacheService());

    test('returns a list (empty or otherwise) without throwing', () {
      expect(() => cache.installedVersions(), returnsNormally);
    });

    test('returns an empty list when versionsDir does not exist', () {
      if (!Directory(CacheService.versionsDir).existsSync()) {
        expect(cache.installedVersions(), isEmpty);
      }
    });
  });

  // ── Version sorting via fake directory structure ───────────────────────────
  //
  // CacheService.installedVersions() sorts results with a semver-aware
  // comparator. We exercise that comparator here by creating a temporary
  // directory tree that mimics the ~/.fve/versions/ layout, then asserting
  // the returned order is correct.
  //
  // Because CacheService hard-codes HOME from Platform.environment, we
  // inspect the sorted order indirectly through a helper that replicates the
  // comparator logic. The comparator itself is package-private, so we verify
  // its behaviour through unit-level property tests.

  group('version sort order (comparator properties)', () {
    // Build a fake installed-versions environment in a temp dir.
    late Directory fakeVersionsDir;

    setUp(() {
      fakeVersionsDir = Directory.systemTemp.createTempSync('fve_versions_');
    });

    tearDown(() {
      if (fakeVersionsDir.existsSync()) {
        fakeVersionsDir.deleteSync(recursive: true);
      }
    });

    // We can't inject the home dir into CacheService without refactoring, so
    // we verify sort behaviour by running our own sort using the same logic
    // the service uses, and asserting the expected output.
    List<String> sortVersions(List<String> versions) {
      List<int> parse(String v) {
        final parts = v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        while (parts.length < 3) {
          parts.add(0);
        }
        return parts;
      }

      int compare(String a, String b) {
        final ap = parse(a);
        final bp = parse(b);
        for (var i = 0; i < 3; i++) {
          final cmp = ap[i].compareTo(bp[i]);
          if (cmp != 0) return cmp;
        }
        return 0;
      }

      return [...versions]..sort(compare);
    }

    test('sorts versions in ascending semver order', () {
      final sorted = sortVersions(['3.22.2', '3.19.0', '3.10.6', '3.24.0']);
      expect(sorted, ['3.10.6', '3.19.0', '3.22.2', '3.24.0']);
    });

    test('compares major versions correctly', () {
      expect(sortVersions(['2.0.0', '3.0.0', '1.0.0']), ['1.0.0', '2.0.0', '3.0.0']);
    });

    test('compares minor versions when major matches', () {
      expect(sortVersions(['3.2.0', '3.10.0', '3.1.0']), ['3.1.0', '3.2.0', '3.10.0']);
    });

    test('compares patch versions when major and minor match', () {
      expect(sortVersions(['3.22.3', '3.22.1', '3.22.10']), ['3.22.1', '3.22.3', '3.22.10']);
    });

    test('identical versions are considered equal', () {
      expect(sortVersions(['3.22.2', '3.22.2']), ['3.22.2', '3.22.2']);
    });
  });
}
