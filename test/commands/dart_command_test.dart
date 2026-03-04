import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── No version configured ─────────────────────────────────────────────────

  group('fve dart — no version set', () {
    test('exits 0 (returns after printing error)', () async {
      expect((await env.run(['dart', 'pub', 'get'])).exitCode, 0);
    });

    test('prints "no Flutter version set" error', () async {
      final r = await env.run(['dart', 'pub', 'get']);
      expect(r.output.toLowerCase(), contains('no flutter version'));
    });
  });

  // ── Project version not installed ─────────────────────────────────────────

  group('fve dart — .fverc version not installed', () {
    late String projPath;

    setUp(() {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      projPath = dir.path;
    });

    test('exits 0 (returns after printing error)', () async {
      final r = await env.run(['dart', 'pub', 'get'], workingDir: projPath);
      expect(r.exitCode, 0);
    });

    test('prints "not installed" error', () async {
      final r = await env.run(['dart', 'pub', 'get'], workingDir: projPath);
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── Global version available ──────────────────────────────────────────────

  group('fve dart — global version installed', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('exits 0 when the global dart binary runs successfully', () async {
      final r = await env.run(['dart', '--version']);
      expect(r.exitCode, 0);
    });

    test('passes arguments to the dart binary', () async {
      final r = await env.run(['dart', '--version']);
      // Fake dart binary echoes "dart 3.22.2".
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Project version takes precedence ─────────────────────────────────────

  group('fve dart — project version overrides global', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('uses the project-pinned version', () async {
      final r = await env.run(['dart', '--version'], workingDir: projPath);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── --help intercept ──────────────────────────────────────────────────────

  group('fve dart --help', () {
    test('exits 0', () async {
      expect((await env.run(['dart', '--help'])).exitCode, 0);
    });

    test('-h exits 0', () async {
      expect((await env.run(['dart', '-h'])).exitCode, 0);
    });
  });
}
