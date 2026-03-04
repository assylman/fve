import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Missing arguments ─────────────────────────────────────────────────────

  group('fve remove — missing arguments', () {
    test('exits 64 when no version and no --all', () async {
      final r = await env.run(['remove']);
      expect(r.exitCode, 64);
    });

    test('prints a usage hint', () async {
      final r = await env.run(['remove']);
      expect(r.output, contains('version'));
    });
  });

  // ── Version not installed ─────────────────────────────────────────────────

  group('fve remove — version not installed', () {
    test('exits 0 with a warning', () async {
      final r = await env.run(['remove', '3.22.2']);
      expect(r.exitCode, 0);
    });

    test('prints "not installed" warning', () async {
      final r = await env.run(['remove', '3.22.2']);
      expect(r.output.toLowerCase(), contains('not installed'));
    });
  });

  // ── Removing the active global version ───────────────────────────────────

  group('fve remove — target is the active global version', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('exits 1 and refuses to remove', () async {
      final r = await env.run(['remove', '3.22.2', '--force']);
      expect(r.exitCode, 1);
    });

    test('prints a warning about the active global version', () async {
      final r = await env.run(['remove', '3.22.2', '--force']);
      expect(r.output.toLowerCase(),
          anyOf(contains('global'), contains('current')));
    });

    test('leaves the version directory intact', () async {
      await env.run(['remove', '3.22.2', '--force']);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isTrue,
      );
    });
  });

  // ── Force remove ──────────────────────────────────────────────────────────

  group('fve remove --force', () {
    setUp(() => env.installVersion('3.22.2'));

    test('exits 0', () async {
      final r = await env.run(['remove', '3.22.2', '--force']);
      expect(r.exitCode, 0);
    });

    test('deletes the version directory', () async {
      await env.run(['remove', '3.22.2', '--force']);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isFalse,
      );
    });

    test('reports success', () async {
      final r = await env.run(['remove', '3.22.2', '--force']);
      expect(r.output.toLowerCase(), contains('removed'));
    });

    test('-f is an alias for --force', () async {
      final r = await env.run(['remove', '3.22.2', '-f']);
      expect(r.exitCode, 0);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isFalse,
      );
    });

    test('"uninstall" is an alias for remove', () async {
      final r = await env.run(['uninstall', '3.22.2', '--force']);
      expect(r.exitCode, 0);
    });

    test('"rm" is an alias for remove', () async {
      final r = await env.run(['rm', '3.22.2', '--force']);
      expect(r.exitCode, 0);
    });
  });

  // ── Interactive confirmation ───────────────────────────────────────────────

  group('fve remove — interactive confirmation', () {
    setUp(() => env.installVersion('3.22.2'));

    test('removes when user confirms with "y"', () async {
      final r = await env.run(['remove', '3.22.2'], stdin: 'y');
      expect(r.exitCode, 0);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isFalse,
      );
    });

    test('removes when user confirms with "yes"', () async {
      final r = await env.run(['remove', '3.22.2'], stdin: 'yes');
      expect(r.exitCode, 0);
    });

    test('aborts when user enters "n"', () async {
      final r = await env.run(['remove', '3.22.2'], stdin: 'n');
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isTrue,
      );
    });

    test('aborts when user presses Enter (empty input)', () async {
      final r = await env.run(['remove', '3.22.2'], stdin: '');
      expect(r.exitCode, 0);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isTrue,
      );
    });
  });

  // ── --all flag ────────────────────────────────────────────────────────────

  group('fve remove --all', () {
    test('warns when nothing is installed', () async {
      final r = await env.run(['remove', '--all']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('nothing'));
    });

    test('--all --force removes all installed versions', () async {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');

      final r = await env.run(['remove', '--all', '--force']);
      expect(r.exitCode, 0);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(env.versionsDir, '3.19.0')).existsSync(),
        isFalse,
      );
    });

    test('--all --force unlinks the global symlink if it was among the versions',
        () async {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');

      await env.run(['remove', '--all', '--force']);
      expect(env.hasGlobalSymlink, isFalse);
    });

    test('--all --force clears default_version in config.json', () async {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');

      await env.run(['remove', '--all', '--force']);
      expect(env.readConfig().containsKey('default_version'), isFalse);
    });

    test('--all with "y" confirmation removes all', () async {
      env.installVersion('3.22.2');
      final r = await env.run(['remove', '--all'], stdin: 'y');
      expect(r.exitCode, 0);
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isFalse,
      );
    });

    test('--all with "n" confirmation aborts', () async {
      env.installVersion('3.22.2');
      final r = await env.run(['remove', '--all'], stdin: 'n');
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(
        Directory(p.join(env.versionsDir, '3.22.2')).existsSync(),
        isTrue,
      );
    });

    test('-a is an alias for --all', () async {
      final r = await env.run(['remove', '-a', '--force']);
      expect(r.exitCode, 0);
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve remove --help', () {
    test('exits 0', () async {
      expect((await env.run(['remove', '--help'])).exitCode, 0);
    });
  });
}
