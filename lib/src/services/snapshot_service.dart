import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_service.dart';

/// A kind of dependency lockfile that fve snapshots per Flutter version.
enum LockKind {
  /// Dart's `pubspec.lock` at the project root.
  pubspec('pubspec.lock', 'pubspec.lock'),

  /// CocoaPods' `ios/Podfile.lock`.
  podfile('ios/Podfile.lock', 'Podfile.lock');

  const LockKind(this._sourceRelPath, this.fileName);

  /// POSIX-style path of the lockfile relative to the project root.
  final String _sourceRelPath;

  /// The bare filename stored inside the snapshot directory.
  final String fileName;

  /// Absolute path of this lockfile inside [projectDir].
  String sourcePath(String projectDir) =>
      p.join(projectDir, p.joinAll(_sourceRelPath.split('/')));
}

/// Manages per-version snapshots of dependency lockfiles so that switching
/// Flutter versions and then switching back restores the exact dependency
/// resolution that was used with that version.
///
/// Two lockfiles are tracked (see [LockKind]):
///   * `pubspec.lock`      — Dart package resolution
///   * `ios/Podfile.lock`  — CocoaPods resolution (version-locked to the
///     Flutter engine; committing the wrong one breaks teammates on a
///     different Flutter version)
///
/// Snapshots are stored at:
///   `~/.fve/snapshots/<project_id>/<flutter_version>/<lockfile>`
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

  String _snapshotFilePath(String projectDir, String version, LockKind kind) =>
      p.join(_snapshotDir(projectDir, version), kind.fileName);

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Saves the current [kind] lockfile from [projectDir] as a snapshot for
  /// [version]. Does nothing if there is no lock file.
  void save(
    String projectDir,
    String version, {
    LockKind kind = LockKind.pubspec,
  }) {
    final src = File(kind.sourcePath(projectDir));
    if (!src.existsSync()) return;

    final dest = File(_snapshotFilePath(projectDir, version, kind));
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(src.readAsBytesSync());
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  /// Restores the [kind] snapshot for [version] into [projectDir].
  /// Returns true if a snapshot existed and was restored, false otherwise.
  bool restore(
    String projectDir,
    String version, {
    LockKind kind = LockKind.pubspec,
  }) {
    final src = File(_snapshotFilePath(projectDir, version, kind));
    if (!src.existsSync()) return false;

    final dest = File(kind.sourcePath(projectDir));
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(src.readAsBytesSync());
    return true;
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  /// Returns true when a [kind] snapshot exists for [projectDir] + [version].
  bool hasSnapshot(
    String projectDir,
    String version, {
    LockKind kind = LockKind.pubspec,
  }) =>
      File(_snapshotFilePath(projectDir, version, kind)).existsSync();

  /// The lockfile filenames snapshotted under [versionDir], in [LockKind] order.
  List<String> _locksIn(String versionDir) => LockKind.values
      .where((k) => File(p.join(versionDir, k.fileName)).existsSync())
      .map((k) => k.fileName)
      .toList();

  /// Lists all (version → path → locks) entries for [projectDir]. A version is
  /// included if it has a snapshot of any [LockKind].
  List<({String version, String path, List<String> locks})> listSnapshots(
    String projectDir,
  ) {
    final dir = Directory(p.join(snapshotsDir, _projectId(projectDir)));
    if (!dir.existsSync()) return [];
    final out = <({String version, String path, List<String> locks})>[];
    for (final d in dir.listSync().whereType<Directory>()) {
      final locks = _locksIn(d.path);
      if (locks.isEmpty) continue;
      out.add((version: p.basename(d.path), path: d.path, locks: locks));
    }
    out.sort((a, b) => a.version.compareTo(b.version));
    return out;
  }

  /// Lists all project-level snapshot entries across every project.
  List<Map<String, dynamic>> listAllSnapshots() {
    final dir = Directory(snapshotsDir);
    if (!dir.existsSync()) return [];
    final result = <Map<String, dynamic>>[];
    for (final proj in dir.listSync().whereType<Directory>()) {
      for (final ver in proj.listSync().whereType<Directory>()) {
        final locks = _locksIn(ver.path);
        if (locks.isEmpty) continue;
        result.add({
          'project_id': p.basename(proj.path),
          'version': p.basename(ver.path),
          'path': ver.path,
          'locks': locks,
        });
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
