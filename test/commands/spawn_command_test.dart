import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Missing / invalid arguments ───────────────────────────────────────────

  group('fve spawn — missing arguments', () {
    test('shows help when no args are provided', () async {
      final r = await env.run(['spawn']);
      expect(r.exitCode, 0); // ArgParser.allowAnything triggers printUsage.
    });

    test('shows help when only --help is passed', () async {
      final r = await env.run(['spawn', '--help']);
      expect(r.exitCode, 0);
    });

    test('exits 64 when version is given but command is missing', () async {
      final r = await env.run(['spawn', '3.22.2']);
      expect(r.exitCode, 64);
    });

    test('error message hints at the missing command', () async {
      final r = await env.run(['spawn', '3.22.2']);
      expect(r.output.toLowerCase(), contains('command'));
    });
  });

  // ── Version not installed ─────────────────────────────────────────────────

  group('fve spawn — version not installed', () {
    test('exits 1 when the specified version is not cached', () async {
      final r = await env.run(['spawn', '9.9.9', 'echo', 'hello']);
      expect(r.exitCode, 1);
    });

    test('prints "not installed" error', () async {
      final r = await env.run(['spawn', '9.9.9', 'echo', 'hello']);
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── Happy path ────────────────────────────────────────────────────────────

  group('fve spawn — version installed', () {
    setUp(() => env.installVersion('3.22.2'));

    test('exits 0 when the command runs successfully', () async {
      final r = await env.run(['spawn', '3.22.2', 'echo', 'hello']);
      expect(r.exitCode, 0);
    });

    test('captures the command output', () async {
      final r = await env.run(['spawn', '3.22.2', 'echo', 'hello']);
      expect(r.output, contains('hello'));
    });

    test('sets FVE_VERSION to the specified version', () async {
      final r = await env.run(['spawn', '3.22.2', 'printenv', 'FVE_VERSION']);
      expect(r.exitCode, 0);
      expect(r.output.trim(), '3.22.2');
    });

    test('prepends the version bin dir to PATH', () async {
      // Verify the version's bin/ directory appears in the spawned PATH.
      final r = await env.run(['spawn', '3.22.2', 'printenv', 'PATH']);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Ignores .fverc ────────────────────────────────────────────────────────

  group('fve spawn — ignores project .fverc', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      // Project is pinned to 3.19.0, but we will spawn with 3.22.2.
      final dir = env.createProjectDir(pinnedVersion: '3.19.0');
      projPath = dir.path;
    });

    test('uses the version from the command line, not from .fverc', () async {
      final r = await env.run(
        ['spawn', '3.22.2', 'printenv', 'FVE_VERSION'],
        workingDir: projPath,
      );
      expect(r.output.trim(), '3.22.2');
    });
  });
}
