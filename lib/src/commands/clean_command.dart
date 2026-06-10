import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// `fve clean` — a pod-preserving project clean.
///
/// Removes the cheap-to-regenerate Flutter/Dart build artifacts but never
/// touches the expensive CocoaPods state (`ios/Pods`, `ios/.symlinks`) unless
/// `--pods` is passed, so the next build doesn't trigger a full `pod install`.
class CleanCommand extends FveCommand {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'Clean build artifacts while preserving ios/Pods (no full pod reinstall).';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('clean', 'Remove build artifacts, keep ios/Pods'),
        HelpExample('clean --pods', 'Also remove ios/Pods and ios/.symlinks'),
      ];

  /// Always removed.
  static const _artifacts = [
    'build',
    '.dart_tool',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  ];

  /// Expensive CocoaPods state — removed only with `--pods`.
  static const _podState = ['ios/Pods', 'ios/.symlinks'];

  CleanCommand() {
    argParser.addFlag(
      'pods',
      help: 'Also remove ios/Pods and ios/.symlinks (forces a full pod install).',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final cwd = Directory.current.path;
    final alsoPods = argResults!['pods'] as bool;

    final removed = <String>[];
    for (final rel in [..._artifacts, if (alsoPods) ..._podState]) {
      if (_remove(cwd, rel)) removed.add(rel);
    }

    if (removed.isEmpty) {
      Logger.dim('Nothing to clean.');
    } else {
      Logger.success('Cleaned: ${removed.join(', ')}');
    }

    if (!alsoPods) {
      final kept = _podState.where((r) => _exists(cwd, r)).toList();
      if (kept.isNotEmpty) {
        Logger.dim('Preserved: ${kept.join(', ')}  (use --pods to remove)');
      }
    }
  }

  bool _exists(String cwd, String rel) {
    final path = p.join(cwd, p.joinAll(rel.split('/')));
    return Directory(path).existsSync() || File(path).existsSync();
  }

  bool _remove(String cwd, String rel) {
    final path = p.join(cwd, p.joinAll(rel.split('/')));
    final dir = Directory(path);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      return true;
    }
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }
}
