import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_service.dart';

/// Manages per-version snapshots of `pubspec.lock` so that switching Flutter
/// versions and then switching back restores the exact dependency resolution
/// that was used with that version.
///
/// Snapshots are stored at:
///   `~/.fve/snapshots/<project_id>/<flutter_version>/pubspec.lock`
///
/// where `<project_id>` is a stable hash of the project's canonical path.
class SnapshotService {
  static String get snapshotsDir => p.join(CacheService.fveHome, 'snapshots');

  // ── Paths ──────────────────────────────────────────────────────────────────

  String _projectId(String projectDir) {
    // Stable, filesystem-safe ID derived from the absolute project path.
    final canonical = Directory(projectDir).absolute.path;
    var hash = 0;
    for (final c in canonical.codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    final safeName = p.basename(canonical);
    return '${safeName}_${hash.toRadixString(16)}';
  }

  String _snapshotDir(String projectDir, String version) =>
      p.join(snapshotsDir, _projectId(projectDir), version);

  String _lockFilePath(String projectDir, String version) =>
      p.join(_snapshotDir(projectDir, version), 'pubspec.lock');

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Saves the current `pubspec.lock` from [projectDir] as a snapshot for
  /// [version]. Does nothing if there is no lock file.
  void save(String projectDir, String version) {
    final src = File(p.join(projectDir, 'pubspec.lock'));
    if (!src.existsSync()) return;

    final dest = File(_lockFilePath(projectDir, version));
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(src.readAsBytesSync());
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  /// Restores the snapshot for [version] into [projectDir] as `pubspec.lock`.
  /// Returns true if a snapshot existed and was restored, false otherwise.
  bool restore(String projectDir, String version) {
    final src = File(_lockFilePath(projectDir, version));
    if (!src.existsSync()) return false;

    final dest = File(p.join(projectDir, 'pubspec.lock'));
    dest.writeAsBytesSync(src.readAsBytesSync());
    return true;
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  /// Returns true when a snapshot exists for [projectDir] + [version].
  bool hasSnapshot(String projectDir, String version) =>
      File(_lockFilePath(projectDir, version)).existsSync();

  /// Lists all (version → snapshot path) pairs for [projectDir].
  List<({String version, String path})> listSnapshots(String projectDir) {
    final dir = Directory(p.join(snapshotsDir, _projectId(projectDir)));
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .where((d) => File(p.join(d.path, 'pubspec.lock')).existsSync())
        .map((d) => (version: p.basename(d.path), path: d.path))
        .toList()
      ..sort((a, b) => a.version.compareTo(b.version));
  }

  /// Lists all project-level snapshot directories.
  List<Map<String, dynamic>> listAllSnapshots() {
    final dir = Directory(snapshotsDir);
    if (!dir.existsSync()) return [];
    final result = <Map<String, dynamic>>[];
    for (final proj in dir.listSync().whereType<Directory>()) {
      for (final ver in proj.listSync().whereType<Directory>()) {
        if (File(p.join(ver.path, 'pubspec.lock')).existsSync()) {
          result.add({
            'project_id': p.basename(proj.path),
            'version': p.basename(ver.path),
            'path': ver.path,
          });
        }
      }
    }
    return result;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Removes all snapshots for [version] across all projects (called when a
  /// Flutter version is removed from the cache).
  void removeVersionSnapshots(String version) {
    final dir = Directory(snapshotsDir);
    if (!dir.existsSync()) return;
    for (final proj in dir.listSync().whereType<Directory>()) {
      final vDir = Directory(p.join(proj.path, version));
      if (vDir.existsSync()) vDir.deleteSync(recursive: true);
    }
  }
}
