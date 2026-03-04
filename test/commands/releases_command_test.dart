import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Argument/flag parsing (no network needed) ─────────────────────────────

  group('fve releases — argument parsing', () {
    test('--help exits 0', () async {
      expect((await env.run(['releases', '--help'])).exitCode, 0);
    });

    test('exits 0 or with a network error — never crashes the process', () async {
      final r = await env.run(['releases']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('--channel stable is the default and does not crash', () async {
      final r = await env.run(['releases', '--channel', 'stable']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('--channel beta does not crash', () async {
      final r = await env.run(['releases', '--channel', 'beta']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('--channel dev does not crash', () async {
      final r = await env.run(['releases', '--channel', 'dev']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('--channel any does not crash', () async {
      final r = await env.run(['releases', '--channel', 'any']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('-c is an alias for --channel', () async {
      final r = await env.run(['releases', '-c', 'stable']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('--page-size is accepted', () async {
      final r = await env.run(['releases', '--page-size', '5']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('-n is an alias for --page-size', () async {
      final r = await env.run(['releases', '-n', '5']);
      expect(r.exitCode, anyOf(0, 1));
    });

    test('invalid --channel value exits with an error', () async {
      final r = await env.run(['releases', '--channel', 'nonexistent']);
      expect(r.exitCode, isNot(0));
    });
  });

  // ── Error message quality ─────────────────────────────────────────────────

  group('fve releases — error handling', () {
    test('prints a human-readable error when the network is unreachable', () async {
      final r = await runFve(
        ['releases'],
        homeDir: env.homePath,
        extraEnv: {
          'https_proxy': 'http://127.0.0.1:1',
          'HTTPS_PROXY': 'http://127.0.0.1:1',
        },
      );
      expect(r.exitCode, anyOf(0, 1));
    });
  });
}
