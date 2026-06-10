@Tags(['integration'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

/// End-to-end tests for the stale-spec-index auto-heal flow.
///
/// Unlike the unit tests in `test/services/pod_service_test.dart` (which inject
/// a fake [PodProcessRunner]), these run the *real* fve binary against a fake
/// `pod` executable placed on PATH. They therefore exercise the real tee runner
/// ([PodService.defaultRunner] — Process.start, dual-stream drain, UTF-8
/// decode), the command-layer flag wiring, the `CP_HOME_DIR` plumbing, and the
/// retry decision, all together.
///
/// The fake `pod` is a POSIX shell script, so these are skipped on Windows
/// (consistent with the rest of the suite, which already shells out to `sh`).
void main() {
  final skipReason =
      Platform.isWindows ? 'requires a POSIX shell fake `pod`' : null;

  late FveTestEnv env;
  late Directory fakeBin;
  late File callLog;

  setUp(() {
    env = FveTestEnv.create();
    fakeBin = Directory.systemTemp.createTempSync('fve_fakepod_');
    callLog = File(p.join(fakeBin.path, 'calls.log'));
  });

  tearDown(() {
    env.dispose();
    if (fakeBin.existsSync()) fakeBin.deleteSync(recursive: true);
  });

  // ── Fixtures ───────────────────────────────────────────────────────────────

  /// Shell snippet for one outcome the fake `pod` can produce.
  String outcome(String kind) {
    switch (kind) {
      case 'ok':
        return 'echo "Analyzing dependencies"; '
            'echo "Pod installation complete!"; exit 0';
      case 'stale':
        // Signature written to stderr to also prove stderr is captured for
        // detection (the runner feeds both streams to the analysis buffer).
        return 'echo "[!] could not find compatible versions for pod '
            'AppMetricaAnalytics" 1>&2; '
            'echo "specs repository is too out-of-date" 1>&2; exit 1';
      case 'other':
        return 'echo "Command CompileSwift failed with a nonzero exit code" '
            '1>&2; exit 1';
      default:
        throw ArgumentError('unknown outcome: $kind');
    }
  }

  /// Writes an executable fake `pod` that logs each invocation's args (one line
  /// per call) to [callLog] and picks its outcome by whether `--repo-update` is
  /// present: [withFlag] when it is, [withoutFlag] when it is not.
  void writeFakePod({required String withFlag, required String withoutFlag}) {
    final script = '#!/bin/sh\n'
        "printf '%s\\n' \"\$*\" >> '${callLog.path}'\n"
        'case "\$*" in\n'
        '  *--repo-update*) ${outcome(withFlag)} ;;\n'
        '  *) ${outcome(withoutFlag)} ;;\n'
        'esac\n';
    final f = File(p.join(fakeBin.path, 'pod'))..writeAsStringSync(script);
    Process.runSync('chmod', ['+x', f.path]);
  }

  /// PATH with the fake `pod` dir taking precedence over the real one.
  String pathWithFakePod() =>
      '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}';

  /// A project dir pinned to [version] with an `ios/Podfile`.
  Directory makeIosProject(String version) {
    final dir = env.createProjectDir(pinnedVersion: version);
    Directory(p.join(dir.path, 'ios')).createSync();
    File(p.join(dir.path, 'ios', 'Podfile'))
        .writeAsStringSync("platform :ios, '12.0'\n");
    return dir;
  }

  /// Pre-creates the version's pod cache so install takes the warm-cache path
  /// (no forced --repo-update from first-time detection).
  void warmPodCache(String version) {
    Directory(p.join(env.fveHome, 'pods', version)).createSync(recursive: true);
  }

  /// The recorded `pod` invocations, one entry per call.
  List<String> recordedCalls() => callLog.existsSync()
      ? callLog.readAsLinesSync().where((l) => l.isNotEmpty).toList()
      : const [];

  Future<FveResult> runInstall(Directory proj, {List<String> extra = const []}) =>
      env.run(
        ['pod', 'install', ...extra],
        workingDir: proj.path,
        extraEnv: {'PATH': pathWithFakePod()},
      );

  Future<FveResult> runUpdate(Directory proj, {List<String> extra = const []}) =>
      env.run(
        ['pod', 'update', ...extra],
        workingDir: proj.path,
        extraEnv: {'PATH': pathWithFakePod()},
      );

  Future<FveResult> runRestore(Directory proj) => env.run(
        ['pod', 'restore'],
        workingDir: proj.path,
        extraEnv: {'PATH': pathWithFakePod()},
      );

  Future<FveResult> runUse(Directory proj, String version) => env.run(
        ['use', version, '--skip-pub-get', '--no-vscode'],
        workingDir: proj.path,
        extraEnv: {'PATH': pathWithFakePod()},
      );

  // ── Auto-heal retry ──────────────────────────────────────────────────────

  group('pod install — stale spec index auto-heal', () {
    test('warm cache: stale failure is retried once with --repo-update and '
        'ultimately succeeds', () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'stale');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runInstall(proj);

      expect(r.exitCode, 0, reason: r.toString());
      final calls = recordedCalls();
      expect(calls.length, 2, reason: 'expected one retry: $calls');
      expect(calls[0], isNot(contains('--repo-update')));
      expect(calls[1], contains('--repo-update'));
      // User is warned before the retry.
      expect(r.output.toLowerCase(), contains('out of date'));
      expect(r.output, contains('--repo-update'));
    }, skip: skipReason);

    test('warm cache: a non-stale failure is NOT retried', () async {
      writeFakePod(withFlag: 'other', withoutFlag: 'other');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runInstall(proj);

      expect(r.exitCode, isNot(0));
      expect(recordedCalls().length, 1, reason: 'must not retry on non-stale');
    }, skip: skipReason);

    test('warm cache: a clean success runs once with no --repo-update',
        () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'ok');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runInstall(proj);

      expect(r.exitCode, 0, reason: r.toString());
      final calls = recordedCalls();
      expect(calls.length, 1);
      expect(calls.single, isNot(contains('--repo-update')));
    }, skip: skipReason);
  });

  // ── First-time cache (Variant B) ─────────────────────────────────────────

  group('pod install — first-time cache', () {
    test('forces --repo-update on the initial install for a fresh version',
        () async {
      // Fake pod fails WITHOUT the flag — proving the very first attempt
      // already carried --repo-update (otherwise it would fail/retry).
      writeFakePod(withFlag: 'ok', withoutFlag: 'stale');
      final proj = makeIosProject('3.99.0'); // no warmPodCache → first time

      final r = await runInstall(proj);

      expect(r.exitCode, 0, reason: r.toString());
      final calls = recordedCalls();
      expect(calls.length, 1, reason: 'no retry expected: $calls');
      expect(calls.single, contains('--repo-update'));
    }, skip: skipReason);
  });

  // ── Explicit flag ─────────────────────────────────────────────────────────

  group('pod install --repo-update', () {
    test('forces --repo-update on the first (only) attempt of a warm cache',
        () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'stale');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runInstall(proj, extra: ['--repo-update']);

      expect(r.exitCode, 0, reason: r.toString());
      final calls = recordedCalls();
      expect(calls.length, 1);
      expect(calls.single, contains('--repo-update'));
    }, skip: skipReason);
  });

  // ── pod update shares the same heal path ──────────────────────────────────

  group('pod update — stale spec index auto-heal', () {
    test('stale failure is retried once with --repo-update and succeeds',
        () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'stale');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runUpdate(proj);

      expect(r.exitCode, 0, reason: r.toString());
      final calls = recordedCalls();
      expect(calls.length, 2, reason: 'expected one retry: $calls');
      expect(calls[0], allOf(contains('update'), isNot(contains('--repo-update'))));
      expect(calls[1], allOf(contains('update'), contains('--repo-update')));
      expect(r.output.toLowerCase(), contains('out of date'));
    }, skip: skipReason);

    test('a non-stale failure is NOT retried', () async {
      writeFakePod(withFlag: 'other', withoutFlag: 'other');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runUpdate(proj);

      expect(r.exitCode, isNot(0));
      expect(recordedCalls().length, 1);
    }, skip: skipReason);
  });

  // ── pod restore ───────────────────────────────────────────────────────────

  group('pod restore', () {
    test('runs pod install and notes the missing snapshot when none exists',
        () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'ok');
      final proj = makeIosProject('3.22.2');
      warmPodCache('3.22.2');

      final r = await runRestore(proj);

      expect(r.exitCode, 0, reason: r.toString());
      expect(recordedCalls().length, 1); // a single pod install
      expect(r.output.toLowerCase(), contains('no podfile.lock snapshot'));
    }, skip: skipReason);

    test('errors when the project has no ios/Podfile', () async {
      writeFakePod(withFlag: 'ok', withoutFlag: 'ok');
      final proj = env.createProjectDir(pinnedVersion: '3.22.2'); // no Podfile

      final r = await runRestore(proj);

      expect(r.exitCode, isNot(0));
      expect(r.output.toLowerCase(), contains('podfile'));
      expect(recordedCalls(), isEmpty); // pod never invoked
    }, skip: skipReason);
  });

  // ── Auto pod install on `fve use` (config-gated) ────────────────────────────

  group('fve use — auto pod install', () {
    test('runs pod install when auto_pod_install is enabled', () async {
      env.writeConfig({'auto_pod_install': true});
      env.installVersion('3.22.2');
      writeFakePod(withFlag: 'ok', withoutFlag: 'ok');
      final proj = makeIosProject('3.22.2');

      final r = await runUse(proj, '3.22.2');

      expect(r.exitCode, 0, reason: r.toString());
      expect(recordedCalls().length, 1); // pod install ran once
    }, skip: skipReason);

    test('does NOT run pod install when disabled (default)', () async {
      env.installVersion('3.22.2');
      writeFakePod(withFlag: 'ok', withoutFlag: 'ok');
      final proj = makeIosProject('3.22.2');

      final r = await runUse(proj, '3.22.2');

      expect(r.exitCode, 0, reason: r.toString());
      expect(recordedCalls(), isEmpty);
    }, skip: skipReason);
  });
}
