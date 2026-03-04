import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Basic execution ───────────────────────────────────────────────────────

  group('fve doctor — basic execution', () {
    test('exits 0', () async {
      final r = await env.run(['doctor']);
      expect(r.exitCode, 0);
    });

    test('outputs section headers', () async {
      final r = await env.run(['doctor']);
      expect(r.output.toLowerCase(), contains('fve'));
    });

    test('checks for fve home directory', () async {
      final r = await env.run(['doctor']);
      expect(r.output.toLowerCase(), anyOf(contains('home'), contains('fve')));
    });

    test('checks installed versions', () async {
      final r = await env.run(['doctor']);
      expect(r.output.toLowerCase(),
          anyOf(contains('installed'), contains('version')));
    });

    test('checks PATH', () async {
      final r = await env.run(['doctor']);
      expect(r.output.toUpperCase(), contains('PATH'));
    });

    test('checks system tools', () async {
      final r = await env.run(['doctor']);
      expect(r.output.toLowerCase(),
          anyOf(contains('git'), contains('unzip'), contains('tool')));
    });
  });

  // ── With versions installed ───────────────────────────────────────────────

  group('fve doctor — with installed version', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('exits 0', () async {
      expect((await env.run(['doctor'])).exitCode, 0);
    });

    test('reports the installed version', () async {
      final r = await env.run(['doctor']);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── With project config ───────────────────────────────────────────────────

  group('fve doctor — with project .fverc', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('exits 0', () async {
      expect((await env.run(['doctor'], workingDir: projPath)).exitCode, 0);
    });

    test('shows project version in output', () async {
      final r = await env.run(['doctor'], workingDir: projPath);
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Uninstalled project version ───────────────────────────────────────────

  group('fve doctor — project version not installed', () {
    late String projPath;

    setUp(() {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      projPath = dir.path;
    });

    test('exits 0 but reports the problem', () async {
      final r = await env.run(['doctor'], workingDir: projPath);
      expect(r.exitCode, 0);
      // Should say the version isn't installed.
      expect(r.output, contains('9.9.9'));
    });
  });
}
