import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;
  late Directory projectDir;

  setUp(() {
    env = FveTestEnv.create();
    projectDir = env.createProjectDir();
  });
  tearDown(() => env.dispose());

  // ── Missing arguments ─────────────────────────────────────────────────────

  group('fve use — missing arguments', () {
    test('exits 64 when no version is provided', () async {
      final r = await env.run(['use'], workingDir: projectDir.path);
      expect(r.exitCode, 64);
    });

    test('prints a usage hint when no version is provided', () async {
      final r = await env.run(['use'], workingDir: projectDir.path);
      expect(r.output, contains('version'));
    });
  });

  // ── Version not installed ─────────────────────────────────────────────────

  group('fve use — version not installed', () {
    test('exits 1 when the version is not cached', () async {
      final r = await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.exitCode, 1);
    });

    test('prints "not installed" error', () async {
      final r = await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.output.toLowerCase(), contains('not installed'));
    });

    test('does not create .fverc when version is missing', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(File(p.join(projectDir.path, '.fverc')).existsSync(), isFalse);
    });
  });

  // ── Happy path ────────────────────────────────────────────────────────────

  group('fve use — version installed', () {
    setUp(() => env.installVersion('3.22.2'));

    test('exits 0', () async {
      final r = await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.exitCode, 0);
    });

    test('creates .fverc in the working directory', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(File(p.join(projectDir.path, '.fverc')).existsSync(), isTrue);
    });

    test('.fverc contains the correct version', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      final json = jsonDecode(
        File(p.join(projectDir.path, '.fverc')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['flutter_version'], '3.22.2');
    });

    test('reports success in output', () async {
      final r = await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.output, contains('3.22.2'));
    });

    test('overwrites an existing .fverc when switching versions', () async {
      env.installVersion('3.19.0');

      // First pin.
      await env.run(
        ['use', '3.19.0', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );

      // Switch.
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );

      final json = jsonDecode(
        File(p.join(projectDir.path, '.fverc')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['flutter_version'], '3.22.2');
    });
  });

  // ── --skip-install ────────────────────────────────────────────────────────

  group('fve use --skip-install', () {
    test('creates .fverc even when the version is not cached', () async {
      final r = await env.run(
        ['use', '3.22.2', '--skip-install', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.exitCode, 0);
      expect(File(p.join(projectDir.path, '.fverc')).existsSync(), isTrue);
    });

    test('writes the correct version to .fverc', () async {
      await env.run(
        ['use', '3.22.2', '--skip-install', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      final json = jsonDecode(
        File(p.join(projectDir.path, '.fverc')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['flutter_version'], '3.22.2');
    });
  });

  // ── --global flag ─────────────────────────────────────────────────────────

  group('fve use --global', () {
    setUp(() => env.installVersion('3.22.2'));

    test('creates .fverc and sets the global symlink', () async {
      await env.run(
        ['use', '3.22.2', '--global', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(File(p.join(projectDir.path, '.fverc')).existsSync(), isTrue);
      expect(env.hasGlobalSymlink, isTrue);
      expect(env.globalVersion, '3.22.2');
    });

    test('updates config.json with default_version', () async {
      await env.run(
        ['use', '3.22.2', '--global', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(env.readConfig()['default_version'], '3.22.2');
    });

    test('-g is an alias for --global', () async {
      await env.run(
        ['use', '3.22.2', '-g', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(env.hasGlobalSymlink, isTrue);
    });
  });

  // ── VS Code integration ───────────────────────────────────────────────────

  group('fve use — VS Code settings', () {
    setUp(() => env.installVersion('3.22.2'));

    test('creates .vscode/settings.json when integration is enabled', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get'],
        workingDir: projectDir.path,
      );
      final settings =
          File(p.join(projectDir.path, '.vscode', 'settings.json'));
      expect(settings.existsSync(), isTrue);
    });

    test('settings.json contains dart.flutterSdkPath', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get'],
        workingDir: projectDir.path,
      );
      final json = jsonDecode(
        File(p.join(projectDir.path, '.vscode', 'settings.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['dart.flutterSdkPath'], isNotNull);
      expect(json['dart.flutterSdkPath'], contains('3.22.2'));
    });

    test('--no-vscode skips creating .vscode/settings.json', () async {
      await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      final settings =
          File(p.join(projectDir.path, '.vscode', 'settings.json'));
      expect(settings.existsSync(), isFalse);
    });

    test('preserves existing keys in settings.json', () async {
      // Pre-create .vscode/settings.json with an existing key.
      final vsDir = Directory(p.join(projectDir.path, '.vscode'))
        ..createSync();
      File(p.join(vsDir.path, 'settings.json')).writeAsStringSync(
        '{"editor.tabSize": 2}',
      );

      await env.run(
        ['use', '3.22.2', '--skip-pub-get'],
        workingDir: projectDir.path,
      );

      final json = jsonDecode(
        File(p.join(vsDir.path, 'settings.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['editor.tabSize'], 2);
      expect(json['dart.flutterSdkPath'], isNotNull);
    });
  });

  // ── --skip-pub-get ────────────────────────────────────────────────────────

  group('fve use --skip-pub-get', () {
    setUp(() => env.installVersion('3.22.2'));

    test('does not attempt pub get even when pubspec.yaml exists', () async {
      // Add a pubspec.yaml to the project dir.
      File(p.join(projectDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: test_app\n');

      // Without --skip-pub-get, fve would call the fake flutter binary's
      // "pub get". With --skip-pub-get, it should not.  The fake binary
      // exits 0 so success/failure doesn't differentiate — we just confirm
      // the command exits normally.
      final r = await env.run(
        ['use', '3.22.2', '--skip-pub-get', '--no-vscode'],
        workingDir: projectDir.path,
      );
      expect(r.exitCode, 0);
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve use --help', () {
    test('exits 0', () async {
      final r = await env.run(
        ['use', '--help'],
        workingDir: projectDir.path,
      );
      expect(r.exitCode, 0);
    });
  });
}
