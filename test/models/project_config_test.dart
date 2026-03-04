import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:fve/src/models/project_config.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fve_config_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ── ProjectConfig model ───────────────────────────────────────────────────

  group('ProjectConfig', () {
    test('fromJson parses flutter_version', () {
      final cfg = ProjectConfig.fromJson({'flutter_version': '3.22.2'});
      expect(cfg.flutterVersion, '3.22.2');
    });

    test('toJson round-trips cleanly', () {
      const cfg = ProjectConfig(flutterVersion: '3.19.0');
      expect(cfg.toJson(), {'flutter_version': '3.19.0'});
    });

    test('fromJson(toJson()) is idempotent', () {
      const cfg = ProjectConfig(flutterVersion: '3.24.0');
      final roundTripped = ProjectConfig.fromJson(cfg.toJson());
      expect(roundTripped.flutterVersion, cfg.flutterVersion);
    });
  });

  // ── saveToDirectory ───────────────────────────────────────────────────────

  group('ProjectConfig.saveToDirectory', () {
    test('creates a .fverc file in the target directory', () {
      const cfg = ProjectConfig(flutterVersion: '3.22.2');
      cfg.saveToDirectory(tempDir.path);

      expect(File(p.join(tempDir.path, '.fverc')).existsSync(), isTrue);
    });

    test('written file contains the correct flutter_version', () {
      const cfg = ProjectConfig(flutterVersion: '3.19.0');
      cfg.saveToDirectory(tempDir.path);

      final json = jsonDecode(
        File(p.join(tempDir.path, '.fverc')).readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(json['flutter_version'], '3.19.0');
    });

    test('written file is pretty-printed (indented) JSON', () {
      const cfg = ProjectConfig(flutterVersion: '3.22.2');
      cfg.saveToDirectory(tempDir.path);

      final contents =
          File(p.join(tempDir.path, '.fverc')).readAsStringSync();
      expect(contents, contains('\n'));
      expect(contents, contains('  '));
    });

    test('overwrites an existing .fverc', () {
      const cfg1 = ProjectConfig(flutterVersion: '3.19.0');
      cfg1.saveToDirectory(tempDir.path);

      const cfg2 = ProjectConfig(flutterVersion: '3.22.2');
      cfg2.saveToDirectory(tempDir.path);

      final json = jsonDecode(
        File(p.join(tempDir.path, '.fverc')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['flutter_version'], '3.22.2');
    });
  });

  // ── findForDirectory ──────────────────────────────────────────────────────

  group('ProjectConfig.findForDirectory', () {
    test('returns null when no .fverc exists anywhere in the tree', () {
      expect(ProjectConfig.findForDirectory(tempDir.path), isNull);
    });

    test('finds .fverc in the starting directory itself', () {
      const ProjectConfig(flutterVersion: '3.22.2')
          .saveToDirectory(tempDir.path);

      final found = ProjectConfig.findForDirectory(tempDir.path);
      expect(found, isNotNull);
      expect(found!.flutterVersion, '3.22.2');
    });

    test('walks up directories to find a parent .fverc', () {
      const ProjectConfig(flutterVersion: '3.22.2')
          .saveToDirectory(tempDir.path);

      final deep = Directory(p.join(tempDir.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      final found = ProjectConfig.findForDirectory(deep.path);
      expect(found!.flutterVersion, '3.22.2');
    });

    test('closer .fverc wins over a parent .fverc', () {
      // Parent pinned to an older version.
      const ProjectConfig(flutterVersion: '3.19.0')
          .saveToDirectory(tempDir.path);

      // Child package overrides with a newer version.
      final child = Directory(p.join(tempDir.path, 'packages', 'my_pkg'))
        ..createSync(recursive: true);
      const ProjectConfig(flutterVersion: '3.22.2').saveToDirectory(child.path);

      final found = ProjectConfig.findForDirectory(child.path);
      expect(found!.flutterVersion, '3.22.2');
    });

    test('returns null when .fverc contains invalid JSON', () {
      File(p.join(tempDir.path, '.fverc'))
          .writeAsStringSync('not { valid } json!!!');
      expect(ProjectConfig.findForDirectory(tempDir.path), isNull);
    });

    test('returns null when .fverc is valid JSON but missing the key', () {
      File(p.join(tempDir.path, '.fverc'))
          .writeAsStringSync('{"other_key": "value"}');
      // fromJson will throw a cast error caught by the outer try/catch.
      expect(ProjectConfig.findForDirectory(tempDir.path), isNull);
    });
  });

  // ── configPathForDirectory ────────────────────────────────────────────────

  group('ProjectConfig.configPathForDirectory', () {
    test('returns null when no .fverc exists', () {
      expect(ProjectConfig.configPathForDirectory(tempDir.path), isNull);
    });

    test('returns the path ending in ".fverc"', () {
      const ProjectConfig(flutterVersion: '3.22.2')
          .saveToDirectory(tempDir.path);

      final path = ProjectConfig.configPathForDirectory(tempDir.path);
      expect(path, isNotNull);
      expect(p.basename(path!), '.fverc');
    });

    test('returns the exact file path, not just the directory', () {
      const ProjectConfig(flutterVersion: '3.22.2')
          .saveToDirectory(tempDir.path);

      final path = ProjectConfig.configPathForDirectory(tempDir.path);
      expect(path, equals(p.join(tempDir.path, '.fverc')));
    });

    test('finds .fverc from a nested subdirectory', () {
      const ProjectConfig(flutterVersion: '3.22.2')
          .saveToDirectory(tempDir.path);

      final nested =
          Directory(p.join(tempDir.path, 'lib', 'src'))..createSync(recursive: true);

      final path = ProjectConfig.configPathForDirectory(nested.path);
      expect(path, equals(p.join(tempDir.path, '.fverc')));
    });
  });
}
