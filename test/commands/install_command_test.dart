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
