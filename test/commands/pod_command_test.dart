import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Help ───────────────────────────────────────────────────────────────────

  group('fve pod --help', () {
    test('exits 0', () async {
      final r = await env.run(['pod', '--help']);
      expect(r.exitCode, 0);
    });

    test('lists install, update, cache subcommands', () async {
      final r = await env.run(['pod', '--help']);
      expect(r.output, contains('install'));
      expect(r.output, contains('update'));
      expect(r.output, contains('cache'));
    });

    test('mentions CP_HOME_DIR', () async {
      final r = await env.run(['pod', '--help']);
      expect(r.output, contains('CP_HOME_DIR'));
    });
  });

  group('fve pod cache --help', () {
    test('exits 0', () async {
      final r = await env.run(['pod', 'cache', '--help']);
      expect(r.exitCode, 0);
    });

    test('lists list and clear subcommands', () async {
      final r = await env.run(['pod', 'cache', '--help']);
      expect(r.output, contains('list'));
      expect(r.output, contains('clear'));
    });
  });

  group('fve pod install --help', () {
    test('exits 0', () async {
      final r = await env.run(['pod', 'install', '--help']);
      expect(r.exitCode, 0);
    });
  });

  group('fve pod update --help', () {
    test('exits 0', () async {
      final r = await env.run(['pod', 'update', '--help']);
      expect(r.exitCode, 0);
    });
  });

  // ── pod install error cases ────────────────────────────────────────────────

  group('fve pod install — no .fverc', () {
    test('exits non-zero', () async {
      final dir = env.createProjectDir(); // no pinned version
      final r = await env.run(['pod', 'install'], workingDir: dir.path);
      expect(r.exitCode, isNot(0));
    });

    test('prints error mentioning .fverc', () async {
      final dir = env.createProjectDir();
      final r = await env.run(['pod', 'install'], workingDir: dir.path);
      expect(r.output.toLowerCase(), contains('.fverc'));
    });
  });

  group('fve pod install — no ios/Podfile', () {
    test('exits 1 when project has .fverc but no ios/Podfile', () async {
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      final r = await env.run(['pod', 'install'], workingDir: dir.path);
      expect(r.exitCode, 1);
    });

    test('prints error mentioning Podfile', () async {
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      final r = await env.run(['pod', 'install'], workingDir: dir.path);
      expect(r.output.toLowerCase(), contains('podfile'));
    });
  });

  // ── pod update error cases ─────────────────────────────────────────────────

  group('fve pod update — no .fverc', () {
    test('exits non-zero', () async {
      final dir = env.createProjectDir();
      final r = await env.run(['pod', 'update'], workingDir: dir.path);
      expect(r.exitCode, isNot(0));
    });

    test('prints error mentioning .fverc', () async {
      final dir = env.createProjectDir();
      final r = await env.run(['pod', 'update'], workingDir: dir.path);
      expect(r.output.toLowerCase(), contains('.fverc'));
    });
  });

  group('fve pod update — no ios/Podfile', () {
    test('exits 1', () async {
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      final r = await env.run(['pod', 'update'], workingDir: dir.path);
      expect(r.exitCode, 1);
    });
  });

  // ── pod cache list ─────────────────────────────────────────────────────────

  group('fve pod cache list', () {
    test('exits 0', () async {
      final r = await env.run(['pod', 'cache', 'list']);
      expect(r.exitCode, 0);
    });

    test('prints "No pod caches found" when empty', () async {
      final r = await env.run(['pod', 'cache', 'list']);
      expect(r.output.toLowerCase(), contains('no pod caches'));
    });

    test('shows cache entry after creating one', () async {
      // Create a fake pod cache directory under the test HOME.
      final version = '3.22.2';
      final cacheDir = Directory(
        p.join(env.fveHome, 'pods', version),
      )..createSync(recursive: true);
      // Write a dummy file so disk usage > 0.
      File(p.join(cacheDir.path, 'dummy.dat'))
          .writeAsStringSync('x' * 1024);

      final r = await env.run(['pod', 'cache', 'list']);
      expect(r.exitCode, 0);
      expect(r.output, contains(version));
    });
  });

  // ── pod cache clear ────────────────────────────────────────────────────────

  group('fve pod cache clear', () {
    test('exits 64 when no version and no --all flag', () async {
      final r = await env.run(['pod', 'cache', 'clear']);
      expect(r.exitCode, 64);
    });

    test('prints usage hint when no args given', () async {
      final r = await env.run(['pod', 'cache', 'clear']);
      expect(r.output, contains('--all'));
    });

    test('exits 0 with --all even when no caches exist', () async {
      final r = await env.run(['pod', 'cache', 'clear', '--all']);
      expect(r.exitCode, 0);
    });

    test('--all prints success message', () async {
      final r = await env.run(['pod', 'cache', 'clear', '--all']);
      expect(r.output.toLowerCase(), contains('cleared'));
    });

    test('exits 0 when clearing a non-existent version', () async {
      final r = await env.run(['pod', 'cache', 'clear', '9.99.99-fake']);
      expect(r.exitCode, 0);
    });

    test('clears existing cache directory', () async {
      final version = '3.22.2';
      final cacheDir = Directory(p.join(env.fveHome, 'pods', version))
        ..createSync(recursive: true);
      expect(cacheDir.existsSync(), isTrue);

      await env.run(['pod', 'cache', 'clear', version]);
      expect(cacheDir.existsSync(), isFalse);
    });
  });
}
