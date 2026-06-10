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
      expect(podfile.readAsStringSync(), contains('Dir.exist?'));
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

  // ── Stale-spec-index detection ───────────────────────────────────────────

  group('PodService.isStaleSpecRepoError', () {
    test('matches "could not find compatible versions for pod"', () {
      expect(
        PodService.isStaleSpecRepoError(
          '[!] CocoaPods could not find compatible versions for pod '
          '"AppMetricaAnalytics":',
        ),
        isTrue,
      );
    });

    test('matches "specs repository is too out-of-date"', () {
      expect(
        PodService.isStaleSpecRepoError(
          "Error: CocoaPods's specs repository is too out-of-date to "
          'satisfy dependencies.',
        ),
        isTrue,
      );
    });

    test('matches "unable to find a specification for"', () {
      expect(
        PodService.isStaleSpecRepoError(
          '[!] Unable to find a specification for `Firebase/Core (= 10.0.0)`',
        ),
        isTrue,
      );
    });

    test('matches "out-of-date source repos"', () {
      expect(
        PodService.isStaleSpecRepoError(
          'You have either:\n * out-of-date source repos.',
        ),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        PodService.isStaleSpecRepoError(
          'COULD NOT FIND COMPATIBLE VERSIONS FOR POD "X"',
        ),
        isTrue,
      );
    });

    test('does not match a normal successful run', () {
      expect(
        PodService.isStaleSpecRepoError(
          'Analyzing dependencies\nDownloading dependencies\n'
          'Pod installation complete!',
        ),
        isFalse,
      );
    });

    test('does not match an unrelated compilation error', () {
      expect(
        PodService.isStaleSpecRepoError(
          "error: cannot find 'foo' in scope\nCommand CompileSwift failed",
        ),
        isFalse,
      );
    });
  });

  // ── Tee-output + auto-retry with --repo-update ───────────────────────────

  group('PodService _runPod retry logic', () {
    late Directory projectDir;

    setUp(() {
      // Isolate the pod cache under the temp dir so first-time detection is
      // deterministic and nothing touches the real ~/.fve.
      CacheService.fveHomeOverride = p.join(tempDir.path, '.fve');
      projectDir = Directory(p.join(tempDir.path, 'proj'))..createSync();
      Directory(p.join(projectDir.path, 'ios')).createSync(recursive: true);
    });

    tearDown(() {
      CacheService.fveHomeOverride = null;
    });

    /// A fake runner that records each invocation's args and returns a canned
    /// output + exit code.
    ({PodService pod, List<List<String>> calls}) makePod({
      required String output,
      required int exitCode,
    }) {
      final calls = <List<String>>[];
      final pod = PodService(
        processRunner: (args, cwd, env, onOutput) async {
          calls.add(List.of(args));
          onOutput(output);
          return exitCode;
        },
      );
      return (pod: pod, calls: calls);
    }

    /// Pre-creates the version cache dir so install takes the warm-cache path
    /// (no forced --repo-update from first-time detection).
    void warmCache(PodService pod, String version) =>
        pod.ensurePodCacheDir(version);

    test('failure + stale output retries once with --repo-update', () async {
      final f = makePod(
        output: 'could not find compatible versions for pod "X"',
        exitCode: 1,
      );
      warmCache(f.pod, '3.22.2');

      await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(f.calls.length, 2);
      expect(f.calls[0], isNot(contains('--repo-update')));
      expect(f.calls[1], contains('--repo-update'));
    });

    test('failure + non-stale output does NOT retry', () async {
      final f = makePod(
        output: 'Command CompileSwift failed with a nonzero exit code',
        exitCode: 1,
      );
      warmCache(f.pod, '3.22.2');

      final code = await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(f.calls.length, 1);
      expect(f.calls[0], isNot(contains('--repo-update')));
      expect(code, 1);
    });

    test('success runs exactly once', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      warmCache(f.pod, '3.22.2');

      final code = await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(f.calls.length, 1);
      expect(code, 0);
    });

    test('retry does not loop — at most two attempts total', () async {
      // Stale output on BOTH attempts: the second must not trigger a third.
      final f = makePod(
        output: 'specs repository is too out-of-date',
        exitCode: 1,
      );
      warmCache(f.pod, '3.22.2');

      await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(f.calls.length, 2);
    });

    test('--repo-update flag forces it on the first (only) attempt', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      warmCache(f.pod, '3.22.2');

      await f.pod.podInstall(projectDir.path, '3.22.2', repoUpdate: true);

      expect(f.calls.length, 1);
      expect(f.calls[0], contains('--repo-update'));
    });

    test('does not duplicate --repo-update when flag set and retry path', () {
      // Sanity: _withRepoUpdate is idempotent via the public surface — the
      // forced first attempt already carries it, so no retry can double it.
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      warmCache(f.pod, '3.22.2');
      return f.pod.podInstall(projectDir.path, '3.22.2', repoUpdate: true).then(
            (_) => expect(
              f.calls[0].where((a) => a == '--repo-update').length,
              1,
            ),
          );
    });

    test('first-time cache forces --repo-update', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      // No warmCache: the version dir does not exist yet.

      await f.pod.podInstall(projectDir.path, '3.99.0');

      expect(f.calls.length, 1);
      expect(f.calls[0], contains('--repo-update'));
    });

    test('warm cache without errors does NOT add --repo-update', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      warmCache(f.pod, '3.22.2');

      await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(f.calls.length, 1);
      expect(f.calls[0], isNot(contains('--repo-update')));
    });

    // ── Per-version cache lock ──────────────────────────────────────────────

    String lockPathFor(String version) =>
        p.join(PodService.podsDir, '$version.lock');

    test('a held lock blocks the operation and pod is never run', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      f.pod.ensurePodCacheDir('3.22.2');
      // Simulate another live process holding this version's lock (our PID).
      File(lockPathFor('3.22.2'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$pid\n');

      final code = await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(code, isNot(0)); // EX_TEMPFAIL
      expect(f.calls, isEmpty); // pod was never invoked
    });

    test('a successful run releases the lock afterwards', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      warmCache(f.pod, '3.22.2');

      await f.pod.podInstall(projectDir.path, '3.22.2');

      expect(File(lockPathFor('3.22.2')).existsSync(), isFalse);
    });

    test('different versions lock independently', () async {
      final f = makePod(output: 'Pod installation complete!', exitCode: 0);
      f.pod.ensurePodCacheDir('3.22.2');
      // 3.22.2 is held, but installing 3.19.0 must still proceed.
      File(lockPathFor('3.22.2'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$pid\n');

      final code = await f.pod.podInstall(projectDir.path, '3.19.0');

      expect(code, 0);
      expect(f.calls.length, 1);
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
