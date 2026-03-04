import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Missing command ───────────────────────────────────────────────────────

  group('fve exec — missing command', () {
    test('exits 64 when no command is provided after --', () async {
      final r = await env.run(['exec']);
      expect(r.exitCode, 64);
    });

    test('prints a usage hint', () async {
      final r = await env.run(['exec']);
      expect(r.output, contains('command'));
    });
  });

  // ── No version configured ─────────────────────────────────────────────────

  group('fve exec — no version set', () {
    test('exits 0 (returns after printing error)', () async {
      final r = await env.run(['exec', '--', 'echo', 'hello']);
      expect(r.exitCode, 0);
    });

    test('prints "no Flutter version" error', () async {
      final r = await env.run(['exec', '--', 'echo', 'hello']);
      expect(r.output.toLowerCase(), contains('no flutter version'));
    });
  });

  // ── --version flag: version not installed ─────────────────────────────────

  group('fve exec --version — version not installed', () {
    test('exits 0 (returns after printing error)', () async {
      final r = await env.run(['exec', '--version', '9.9.9', '--', 'echo']);
      expect(r.exitCode, 0);
    });

    test('prints "not installed" error', () async {
      final r = await env.run(['exec', '--version', '9.9.9', '--', 'echo']);
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── .fverc version not installed ─────────────────────────────────────────

  group('fve exec — .fverc version not installed', () {
    late String projPath;

    setUp(() {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      projPath = dir.path;
    });

    test('exits 0 (returns after printing error)', () async {
      final r = await env.run(
        ['exec', '--', 'echo', 'hello'],
        workingDir: projPath,
      );
      expect(r.exitCode, 0);
    });

    test('prints "not installed" error referencing .fverc', () async {
      final r = await env.run(
        ['exec', '--', 'echo', 'hello'],
        workingDir: projPath,
      );
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── Happy path: run a command ─────────────────────────────────────────────

  group('fve exec — with version set', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('runs the given command and exits with its exit code', () async {
      // `echo hello` should exit 0.
      final r = await env.run(['exec', '--', 'echo', 'hello']);
      expect(r.exitCode, 0);
    });

    test('captures the command output', () async {
      final r = await env.run(['exec', '--', 'echo', 'hello']);
      expect(r.output, contains('hello'));
    });

    test('sets FVE_VERSION in the environment', () async {
      // Use printenv to verify the env var.
      final r = await env.run(['exec', '--', 'printenv', 'FVE_VERSION']);
      expect(r.exitCode, 0);
      expect(r.output.trim(), '3.22.2');
    });
  });

  // ── --version override ────────────────────────────────────────────────────

  group('fve exec --version override', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.22.2');
    });

    test('uses the overridden version instead of global', () async {
      final r = await env.run([
        'exec',
        '--version',
        '3.19.0',
        '--',
        'printenv',
        'FVE_VERSION',
      ]);
      expect(r.exitCode, 0);
      expect(r.output.trim(), '3.19.0');
    });

    test('-v is an alias for --version', () async {
      final r = await env.run([
        'exec',
        '-v',
        '3.19.0',
        '--',
        'printenv',
        'FVE_VERSION',
      ]);
      expect(r.output.trim(), '3.19.0');
    });
  });

  // ── Project version takes precedence ─────────────────────────────────────

  group('fve exec — project version via .fverc', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('uses the .fverc version, not the global', () async {
      final r = await env.run(
        ['exec', '--', 'printenv', 'FVE_VERSION'],
        workingDir: projPath,
      );
      expect(r.output.trim(), '3.22.2');
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve exec --help', () {
    test('exits 0', () async {
      expect((await env.run(['exec', '--help'])).exitCode, 0);
    });
  });
}
