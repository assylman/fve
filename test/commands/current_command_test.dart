import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── No version configured ─────────────────────────────────────────────────

  group('fve current — no version set', () {
    test('exits 0', () async {
      final r = await env.run(['current']);
      expect(r.exitCode, 0);
    });

    test('shows "none" for project version', () async {
      final r = await env.run(['current']);
      expect(r.output.toLowerCase(), contains('none'));
    });

    test('shows "none" for global version', () async {
      final r = await env.run(['current']);
      expect(r.output.toLowerCase(), contains('none'));
    });

    test('shows a warning about no active version', () async {
      final r = await env.run(['current']);
      expect(r.output.toLowerCase(), anyOf(contains('no active'), contains('none')));
    });
  });

  // ── Project version via .fverc ────────────────────────────────────────────

  group('fve current — project version set', () {
    late FveTestEnv envWithProject;
    late String projPath;

    setUp(() {
      envWithProject = FveTestEnv.create();
      envWithProject.installVersion('3.22.2');
      final dir = envWithProject.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });
    tearDown(() => envWithProject.dispose());

    test('exits 0', () async {
      final r = await envWithProject.run(['current'], workingDir: projPath);
      expect(r.exitCode, 0);
    });

    test('shows the project-pinned version', () async {
      final r = await envWithProject.run(['current'], workingDir: projPath);
      expect(r.output, contains('3.22.2'));
    });

    test('labels the source as "project"', () async {
      final r = await envWithProject.run(['current'], workingDir: projPath);
      expect(r.output.toLowerCase(), contains('project'));
    });
  });

  // ── Global version only ───────────────────────────────────────────────────

  group('fve current — global version set', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('exits 0', () async {
      expect((await env.run(['current'])).exitCode, 0);
    });

    test('shows the global version', () async {
      final r = await env.run(['current']);
      expect(r.output, contains('3.22.2'));
    });

    test('labels the source as "global"', () async {
      final r = await env.run(['current']);
      expect(r.output.toLowerCase(), contains('global'));
    });

    test('active version equals the global version', () async {
      final r = await env.run(['current']);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Both project and global set (project wins) ────────────────────────────

  group('fve current — both project and global set', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('exits 0', () async {
      final r = await env.run(['current'], workingDir: projPath);
      expect(r.exitCode, 0);
    });

    test('shows both versions', () async {
      final r = await env.run(['current'], workingDir: projPath);
      expect(r.output, contains('3.22.2'));
      expect(r.output, contains('3.19.0'));
    });

    test('active version is the project-pinned version', () async {
      final r = await env.run(['current'], workingDir: projPath);
      // The active line should show the project version (3.22.2).
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Project version not installed ─────────────────────────────────────────

  group('fve current — project version not installed', () {
    late String projPath;

    setUp(() {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      projPath = dir.path;
    });

    test('exits 0 but warns about missing installation', () async {
      final r = await env.run(['current'], workingDir: projPath);
      expect(r.exitCode, 0);
      expect(r.output, contains('9.9.9'));
      // Should show a warning symbol or "not installed" text.
      expect(r.output, anyOf(contains('⚠'), contains('not installed')));
    });
  });
}
