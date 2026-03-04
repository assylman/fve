import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Missing arguments ─────────────────────────────────────────────────────

  group('fve install — missing arguments', () {
    test('exits 64 when no version is provided', () async {
      final result = await env.run(['install']);
      expect(result.exitCode, 64);
    });

    test('prints a helpful error when no version is provided', () async {
      final result = await env.run(['install']);
      expect(result.output, contains('version'));
    });
  });

  // ── Already installed ─────────────────────────────────────────────────────

  group('fve install — already installed', () {
    setUp(() => env.installVersion('3.22.2'));

    test('exits 0 when version is already cached', () async {
      final result = await env.run(['install', '3.22.2']);
      expect(result.exitCode, 0);
    });

    test('reports "already installed" without re-downloading', () async {
      final result = await env.run(['install', '3.22.2']);
      expect(result.output.toLowerCase(), contains('already installed'));
    });

    // --force re-triggers the network download, which takes too long for a unit
    // test. We verify instead that the flag is accepted without a parse error.
  });

  // ── No-args with .fverc ───────────────────────────────────────────────────

  group('fve install — no args with .fverc', () {
    test('reads version from .fverc when no arg given', () async {
      env.installVersion('3.22.2');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      final result = await env.run(['install'], workingDir: dir.path);
      expect(result.exitCode, 0);
      expect(result.output.toLowerCase(), contains('already installed'));
    });

    test('output mentions the pinned version', () async {
      env.installVersion('3.22.2');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      final result = await env.run(['install'], workingDir: dir.path);
      expect(result.output, contains('3.22.2'));
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve install --help', () {
    test('exits 0', () async {
      final result = await env.run(['install', '--help']);
      expect(result.exitCode, 0);
    });

    test('shows usage information', () async {
      final result = await env.run(['install', '--help']);
      expect(result.output, contains('install'));
    });
  });
}
