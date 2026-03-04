import 'dart:io';

import 'package:fve/src/services/cache_service.dart';
import 'package:fve/src/services/pod_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late PodService pod;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fve_pod_svc_test_');
    pod = PodService();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ── Path structure ─────────────────────────────────────────────────────────

  group('PodService path structure', () {
    test('podsDir is inside fveHome', () {
      expect(PodService.podsDir, startsWith(CacheService.fveHome));
    });

    test('podsDir directory name is "pods"', () {
      expect(p.basename(PodService.podsDir), 'pods');
    });

    test('podCacheDir contains the version string', () {
      expect(pod.podCacheDir('3.22.2'), endsWith('3.22.2'));
    });

    test('podCacheDir is nested inside podsDir', () {
      expect(pod.podCacheDir('3.22.2'), startsWith(PodService.podsDir));
    });

    test('different versions have different podCacheDirs', () {
      expect(pod.podCacheDir('3.22.2'), isNot(pod.podCacheDir('3.38.0')));
    });
  });

  // ── Podfile detection ──────────────────────────────────────────────────────

  group('PodService.findPodfile', () {
    test('returns null when ios/ directory does not exist', () {
      expect(pod.findPodfile(tempDir.path), isNull);
    });

    test('returns null when ios/ exists but has no Podfile', () {
      Directory(p.join(tempDir.path, 'ios')).createSync();
      expect(pod.findPodfile(tempDir.path), isNull);
    });

    test('returns the Podfile path when ios/Podfile exists', () {
      final iosDir = Directory(p.join(tempDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile')).writeAsStringSync("platform :ios, '12.0'\n");
      expect(pod.findPodfile(tempDir.path), isNotNull);
    });

    test('returned path ends with "Podfile"', () {
      final iosDir = Directory(p.join(tempDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile')).writeAsStringSync("platform :ios, '12.0'\n");
      expect(p.basename(pod.findPodfile(tempDir.path)!), 'Podfile');
    });
  });

  group('PodService.hasPodfile', () {
    test('returns false when no ios/Podfile', () {
      expect(pod.hasPodfile(tempDir.path), isFalse);
    });

    test('returns true when ios/Podfile exists', () {
      final iosDir = Directory(p.join(tempDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile')).writeAsStringSync("platform :ios, '12.0'\n");
      expect(pod.hasPodfile(tempDir.path), isTrue);
    });
  });

  // ── Podfile injection ──────────────────────────────────────────────────────

  group('PodService.injectPodfile', () {
    late File podfile;
    const originalContent = "platform :ios, '12.0'\n";

    setUp(() {
      final iosDir = Directory(p.join(tempDir.path, 'ios'))..createSync();
      podfile = File(p.join(iosDir.path, 'Podfile'))
        ..writeAsStringSync(originalContent);
    });

    test('injects block at the top of the Podfile', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      expect(podfile.readAsStringSync(), startsWith('# fve managed'));
    });

    test('block contains the version string', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      expect(podfile.readAsStringSync(), contains('3.22.2'));
    });

    test('block sets CP_HOME_DIR', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      expect(podfile.readAsStringSync(), contains('CP_HOME_DIR'));
    });

    test('block is conditional on ~/.fve existence (Dir.exist? guard)', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      expect(podfile.readAsStringSync(), contains("Dir.exist?"));
    });

    test('original Podfile content is preserved after the block', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      expect(podfile.readAsStringSync(), contains(originalContent.trim()));
    });

    test('calling twice with the same version is idempotent (one block)', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      pod.injectPodfile(tempDir.path, '3.22.2');
      final content = podfile.readAsStringSync();
      expect('# fve managed'.allMatches(content).length, 1);
    });

    test('switching version replaces the block with the new version', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      pod.injectPodfile(tempDir.path, '3.38.0');
      final content = podfile.readAsStringSync();
      expect(content, contains('3.38.0'));
      expect(content, isNot(contains('3.22.2')));
    });

    test('only one block exists after version switch', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      pod.injectPodfile(tempDir.path, '3.38.0');
      final content = podfile.readAsStringSync();
      expect('# fve managed'.allMatches(content).length, 1);
    });

    test('is a no-op when ios/Podfile does not exist', () {
      final noIos = Directory.systemTemp.createTempSync('fve_no_ios_');
      try {
        expect(() => pod.injectPodfile(noIos.path, '3.22.2'), returnsNormally);
      } finally {
        noIos.deleteSync(recursive: true);
      }
    });
  });

  // ── Podfile removal ────────────────────────────────────────────────────────

  group('PodService.removePodfileInjection', () {
    late File podfile;
    const originalContent = "platform :ios, '12.0'\n";

    setUp(() {
      final iosDir = Directory(p.join(tempDir.path, 'ios'))..createSync();
      podfile = File(p.join(iosDir.path, 'Podfile'))
        ..writeAsStringSync(originalContent);
    });

    test('removes the fve block', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      pod.removePodfileInjection(tempDir.path);
      expect(podfile.readAsStringSync(), isNot(contains('# fve managed')));
    });

    test('original content is preserved after removal', () {
      pod.injectPodfile(tempDir.path, '3.22.2');
      pod.removePodfileInjection(tempDir.path);
      expect(podfile.readAsStringSync(), contains(originalContent.trim()));
    });

    test('is a no-op when there is no fve block in the Podfile', () {
      pod.removePodfileInjection(tempDir.path);
      expect(podfile.readAsStringSync(), originalContent);
    });

    test('is a no-op when ios/Podfile does not exist', () {
      final noIos = Directory.systemTemp.createTempSync('fve_no_ios_');
      try {
        expect(() => pod.removePodfileInjection(noIos.path), returnsNormally);
      } finally {
        noIos.deleteSync(recursive: true);
      }
    });
  });

  // ── Cache management ───────────────────────────────────────────────────────

  group('PodService cache management', () {
    test('listCaches returns empty list when pods dir does not exist', () {
      if (!Directory(PodService.podsDir).existsSync()) {
        expect(pod.listCaches(), isEmpty);
      }
    });

    test('listCaches returns a list without throwing', () {
      expect(() => pod.listCaches(), returnsNormally);
    });

    test('clearCache does not throw when version dir does not exist', () {
      expect(() => pod.clearCache('9.99.99-nonexistent'), returnsNormally);
    });

    test('clearAllCaches does not throw when pods dir does not exist', () {
      if (!Directory(PodService.podsDir).existsSync()) {
        expect(() => pod.clearAllCaches(), returnsNormally);
      }
    });

    test('ensurePodCacheDir creates the version directory', () {
      final testVersion = '0.0.0-test-${DateTime.now().millisecondsSinceEpoch}';
      final cacheDir = Directory(pod.podCacheDir(testVersion));
      try {
        expect(cacheDir.existsSync(), isFalse);
        pod.ensurePodCacheDir(testVersion);
        expect(cacheDir.existsSync(), isTrue);
      } finally {
        if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      }
    });

    test('clearCache removes the version directory', () {
      final testVersion = '0.0.0-clear-${DateTime.now().millisecondsSinceEpoch}';
      pod.ensurePodCacheDir(testVersion);
      final cacheDir = Directory(pod.podCacheDir(testVersion));
      expect(cacheDir.existsSync(), isTrue);
      pod.clearCache(testVersion);
      expect(cacheDir.existsSync(), isFalse);
    });
  });
}
