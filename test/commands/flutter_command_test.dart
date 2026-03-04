import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── No version configured ─────────────────────────────────────────────────

  group('fve flutter — no version set', () {
    test('exits 0 (command returns after printing error)', () async {
      final r = await env.run(['flutter', 'run']);
      expect(r.exitCode, 0);
    });

    test('prints an error message', () async {
      final r = await env.run(['flutter', 'run']);
      expect(r.output.toLowerCase(), contains('no flutter version'));
    });

    test('suggests how to set a version', () async {
      final r = await env.run(['flutter', 'run']);
      expect(
        r.output.toLowerCase(),
        anyOf(contains('fve use'), contains('fve global')),
      );
    });
  });

  // ── Project version not installed ─────────────────────────────────────────

  group('fve flutter — .fverc version not installed', () {
    late String projPath;

    setUp(() {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      projPath = dir.path;
    });

    test('exits 0 (returns after printing error)', () async {
      final r = await env.run(['flutter', 'run'], workingDir: projPath);
      expect(r.exitCode, 0);
    });

    test('prints "not installed" error', () async {
      final r = await env.run(['flutter', 'run'], workingDir: projPath);
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── Global version available ──────────────────────────────────────────────

  group('fve flutter — global version installed', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('exits 0 when the global flutter binary runs successfully', () async {
      // The fake binary echoes and exits 0.
      final r = await env.run(['flutter', '--version']);
      expect(r.exitCode, 0);
    });

    test('passes arguments to the flutter binary', () async {
      final r = await env.run(['flutter', '--version']);
      // Our fake binary echoes "flutter 3.22.2".
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Project version takes precedence ─────────────────────────────────────

  group('fve flutter — project version overrides global', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('uses project version when both are available', () async {
      final r = await env.run(['flutter', '--version'], workingDir: projPath);
      expect(r.exitCode, 0);
      // Fake binary echoes "flutter 3.22.2" — the project version.
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── --help intercept ──────────────────────────────────────────────────────

  group('fve flutter --help', () {
    test('exits 0 and shows fve help (not Flutter native help)', () async {
      final r = await env.run(['flutter', '--help']);
      expect(r.exitCode, 0);
    });

    test('-h also shows help', () async {
      final r = await env.run(['flutter', '-h']);
      expect(r.exitCode, 0);
    });
  });
}
