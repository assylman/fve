import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/version_validator.dart';

const _configFileName = '.fverc';

class ProjectConfig {
  final String flutterVersion;

  const ProjectConfig({required this.flutterVersion});

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    return ProjectConfig(
      flutterVersion: VersionValidator.check(json['flutter_version'] as String),
    );
  }

  Map<String, dynamic> toJson() => {'flutter_version': flutterVersion};

  void saveToDirectory(String dir) {
    final file = File(p.join(dir, _configFileName));
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  /// Walks up from [startDir] looking for a `.fverc` file.
  ///
  /// The `FVE_FLUTTER_VERSION` environment variable takes precedence over
  /// the config file, allowing CI pipelines to override the version without
  /// modifying project files (test case 5.9).
  ///
  /// Returns null if none is found.
  static ProjectConfig? findForDirectory(String startDir) {
    // 5.9 — environment variable override.
    final envVersion = Platform.environment['FVE_FLUTTER_VERSION'];
    if (envVersion != null && envVersion.isNotEmpty) {
      if (VersionValidator.isValid(envVersion)) {
        return ProjectConfig(flutterVersion: envVersion);
      }
      Logger.warning(
        'Ignoring FVE_FLUTTER_VERSION="$envVersion" — not a valid version '
        'or channel.',
      );
    }

    var current = Directory(startDir);
    while (true) {
      final file = File(p.join(current.path, _configFileName));
      if (file.existsSync()) {
        try {
          final json = jsonDecode(file.readAsStringSync());
          return ProjectConfig.fromJson(json as Map<String, dynamic>);
        } catch (_) {
          Logger.warning(
            '${file.path} is invalid — expected {"flutter_version": "x.y.z"}',
          );
          return null;
        }
      }
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  /// Returns the path to the nearest `.fverc` from [startDir].
  static String? configPathForDirectory(String startDir) {
    var current = Directory(startDir);
    while (true) {
      final file = File(p.join(current.path, _configFileName));
      if (file.existsSync()) return file.path;
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }
}
