import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Nothing installed ─────────────────────────────────────────────────────

  group('fve list — nothing installed', () {
    test('exits 0', () async {
      expect((await env.run(['list'])).exitCode, 0);
    });

    test('prints a warning that nothing is installed', () async {
      final r = await env.run(['list']);
      expect(r.output.toLowerCase(), contains('no flutter'));
    });

    test('suggests install command', () async {
      final r = await env.run(['list']);
      expect(r.output.toLowerCase(), contains('install'));
    });
  });

  // ── Versions present ──────────────────────────────────────────────────────

  group('fve list — versions present', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
    });

    test('exits 0', () async {
      expect((await env.run(['list'])).exitCode, 0);
    });

    test('lists all installed versions', () async {
      final r = await env.run(['list']);
      expect(r.output, contains('3.22.2'));
      expect(r.output, contains('3.19.0'));
    });

    test('shows the total count', () async {
      final r = await env.run(['list']);
      expect(r.output, contains('2'));
    });
  });

  // ── Global marker ─────────────────────────────────────────────────────────

  group('fve list — global marker', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('marks the global version', () async {
      final r = await env.run(['list']);
      expect(r.output.toLowerCase(), contains('global'));
    });

    test('shows the global version in the list', () async {
      final r = await env.run(['list']);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Project version marker ────────────────────────────────────────────────

  group('fve list — project version marker', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('marks the project-pinned version', () async {
      final r = await env.run(['list'], workingDir: projPath);
      expect(r.output.toLowerCase(), contains('project'));
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve list --help', () {
    test('exits 0', () async {
      expect((await env.run(['list', '--help'])).exitCode, 0);
    });
  });
}
