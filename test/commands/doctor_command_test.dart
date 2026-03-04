import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Basic execution ───────────────────────────────────────────────────────

  group('fve doctor — basic execution', () {
    test('exits 1 when PATH not configured', () async {
      final r = await env.run(['doctor']);
      expect(r.exitCode, 1);
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

    test('exits 0 when PATH configured', () async {
      expect((await env.runWithPath(['doctor'])).exitCode, 0);
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

    test('exits 0 when PATH configured', () async {
      expect((await env.runWithPath(['doctor'], workingDir: projPath)).exitCode, 0);
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

    test('exits 1 and reports the problem', () async {
      final r = await env.run(['doctor'], workingDir: projPath);
      expect(r.exitCode, 1);
      // Should say the version isn't installed.
      expect(r.output, contains('9.9.9'));
    });
  });

  // ── iOS / CocoaPods section ───────────────────────────────────────────────

  group('fve doctor — no ios/Podfile', () {
    test('does not print iOS section when no Podfile', () async {
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      final r = await env.runWithPath(['doctor'], workingDir: dir.path);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), isNot(contains('cocoapods')));
    });
  });

  group('fve doctor — with ios/Podfile, no injection', () {
    late Directory projDir;

    setUp(() {
      projDir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      // Create ios/Podfile without fve injection.
      final iosDir = Directory(p.join(projDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile'))
          .writeAsStringSync("platform :ios, '12.0'\n");
    });

    test('shows iOS section when Podfile exists', () async {
      final r = await env.run(['doctor'], workingDir: projDir.path);
      expect(r.output.toLowerCase(), contains('cocoapods'));
    });

    test('reports missing fve injection', () async {
      final r = await env.run(['doctor'], workingDir: projDir.path);
      expect(r.output.toLowerCase(), contains('missing'));
    });
  });

  group('fve doctor — with ios/Podfile, correct injection', () {
    late Directory projDir;

    setUp(() async {
      projDir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      // Create ios/Podfile and inject via fve use.
      final iosDir = Directory(p.join(projDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile'))
          .writeAsStringSync("platform :ios, '12.0'\n");
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projDir.path,
      );
    });

    test('shows iOS section', () async {
      final r = await env.run(['doctor'], workingDir: projDir.path);
      expect(r.output.toLowerCase(), contains('cocoapods'));
    });

    test('reports correct injection', () async {
      final r = await env.run(['doctor'], workingDir: projDir.path);
      expect(r.output, contains('3.22.2'));
      expect(r.output.toLowerCase(), contains('cp_home_dir'));
    });
  });

  group('fve doctor — with ios/Podfile, wrong version injected', () {
    late Directory projDir;

    setUp(() async {
      projDir = env.createProjectDir(pinnedVersion: '3.22.2');
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      // Create ios/Podfile and inject for 3.19.0, then switch .fverc to 3.22.2.
      final iosDir = Directory(p.join(projDir.path, 'ios'))..createSync();
      File(p.join(iosDir.path, 'Podfile'))
          .writeAsStringSync("platform :ios, '12.0'\n");
      // Inject for old version.
      await env.run(
        ['use', '3.19.0', '--skip-pub-get', '--no-vscode'],
        workingDir: projDir.path,
      );
      // Update .fverc to 3.22.2 without re-injecting.
      File(p.join(projDir.path, '.fverc'))
          .writeAsStringSync('{\n  "flutter_version": "3.22.2"\n}\n');
    });

    test('reports version mismatch in Podfile injection', () async {
      final r = await env.run(['doctor'], workingDir: projDir.path);
      expect(r.output, contains('3.19.0'));
      expect(r.output.toLowerCase(), contains('fix'));
    });
  });
}
