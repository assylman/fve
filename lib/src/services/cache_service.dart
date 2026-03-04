import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/platform_utils.dart';

/// Manages the `~/.fve/` directory layout.
class CacheService {
  /// Root directory for all fve data.
  static String get fveHome {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    return p.join(home, '.fve');
  }

  static String get versionsDir => p.join(fveHome, 'versions');

  /// Symlink pointing to the globally active SDK directory.
  static String get currentLink => p.join(fveHome, 'current');

  static String get globalConfigFile => p.join(fveHome, 'config.json');

  // ── Version directory paths ──────────────────────────────────────────────

  String versionDir(String version) => p.join(versionsDir, version);

  String flutterBin(String version) =>
      p.join(versionDir(version), 'bin', flutterBinaryName);

  String dartBin(String version) =>
      p.join(versionDir(version), 'bin', dartBinaryName);

  // ── Querying ─────────────────────────────────────────────────────────────

  /// Returns true when the version directory exists on disk, regardless of
  /// whether the installation is complete (e.g. an interrupted git clone).
  bool isVersionDirPresent(String version) =>
      Directory(versionDir(version)).existsSync();

  /// Returns true when the flutter binary exists inside the cached SDK.
  bool isInstalled(String version) =>
      File(flutterBin(version)).existsSync();

  /// Lists all versions that have a valid flutter binary cached.
  List<String> installedVersions() {
    final dir = Directory(versionsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .where(isInstalled)
        .toList()
      ..sort(_compareVersions);
  }

  /// Returns the currently active global version by reading the symlink.
  String? currentGlobalVersion() {
    final link = Link(currentLink);
    if (!link.existsSync()) return null;
    try {
      final target = link.targetSync();
      return p.basename(target);
    } catch (_) {
      return null;
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  void ensureDirectoriesExist() {
    Directory(versionsDir).createSync(recursive: true);
  }

  /// Sets the `~/.fve/current` symlink to the given version directory.
  void setCurrentSymlink(String version) {
    final target = versionDir(version);
    if (!Directory(target).existsSync()) {
      throw StateError('Version $version is not installed at $target');
    }

    final link = Link(currentLink);
    if (link.existsSync()) link.deleteSync();
    link.createSync(target);
  }

  /// Deletes the SDK directory for [version].
  void deleteVersion(String version) {
    final dir = Directory(versionDir(version));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Semver-aware comparator (falls back to lexicographic).
int _compareVersions(String a, String b) {
  final aParts = _parseParts(a);
  final bParts = _parseParts(b);
  for (var i = 0; i < 3; i++) {
    final cmp = aParts[i].compareTo(bParts[i]);
    if (cmp != 0) return cmp;
  }
  return 0;
}

List<int> _parseParts(String version) {
  final parts = version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}
