import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Missing arguments ─────────────────────────────────────────────────────

  group('fve global — missing arguments', () {
    test('exits 64 with no args and no --unlink', () async {
      final r = await env.run(['global']);
      expect(r.exitCode, 64);
    });

    test('prints a usage hint', () async {
      final r = await env.run(['global']);
      expect(r.output, contains('version'));
    });
  });

  // ── Version not installed ─────────────────────────────────────────────────

  group('fve global — version not installed', () {
    test('exits 1 when version is not cached', () async {
      final r = await env.run(['global', '3.22.2']);
      expect(r.exitCode, 1);
    });

    test('prints "not installed" message', () async {
      final r = await env.run(['global', '3.22.2']);
      expect(r.output.toLowerCase(), contains('not installed'));
    });

    test('does not create the global symlink', () async {
      await env.run(['global', '3.22.2']);
      expect(env.hasGlobalSymlink, isFalse);
    });
  });

  // ── Happy path ────────────────────────────────────────────────────────────

  group('fve global — version installed', () {
    setUp(() => env.installVersion('3.22.2'));

    test('exits 0', () async {
      final r = await env.run(['global', '3.22.2']);
      expect(r.exitCode, 0);
    });

    test('creates the ~/.fve/current symlink', () async {
      await env.run(['global', '3.22.2']);
      expect(env.hasGlobalSymlink, isTrue);
    });

    test('symlink points to the correct version directory', () async {
      await env.run(['global', '3.22.2']);
      expect(env.globalVersion, '3.22.2');
    });

    test('updates config.json with default_version', () async {
      await env.run(['global', '3.22.2']);
      expect(env.readConfig()['default_version'], '3.22.2');
    });

    test('reports success in output', () async {
      final r = await env.run(['global', '3.22.2']);
      expect(r.output, contains('3.22.2'));
    });

    test('switching global from one version to another updates the symlink',
        () async {
      env.installVersion('3.19.0');

      await env.run(['global', '3.22.2']);
      expect(env.globalVersion, '3.22.2');

      await env.run(['global', '3.19.0']);
      expect(env.globalVersion, '3.19.0');
    });
  });

  // ── --unlink ──────────────────────────────────────────────────────────────

  group('fve global --unlink', () {
    test('exits 0 and warns when no global version is set', () async {
      final r = await env.run(['global', '--unlink']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('no global'));
    });

    test('removes the symlink when one is set', () async {
      env.installVersion('3.22.2');
      await env.run(['global', '3.22.2']);
      expect(env.hasGlobalSymlink, isTrue);

      final r = await env.run(['global', '--unlink']);
      expect(r.exitCode, 0);
      expect(env.hasGlobalSymlink, isFalse);
    });

    test('clears default_version in config.json after unlink', () async {
      env.installVersion('3.22.2');
      await env.run(['global', '3.22.2']);
      await env.run(['global', '--unlink']);
      expect(env.readConfig().containsKey('default_version'), isFalse);
    });

    test('reports success after unlink', () async {
      env.installVersion('3.22.2');
      await env.run(['global', '3.22.2']);
      final r = await env.run(['global', '--unlink']);
      expect(r.output.toLowerCase(), contains('unlink'));
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve global --help', () {
    test('exits 0', () async {
      expect((await env.run(['global', '--help'])).exitCode, 0);
    });
  });
}
