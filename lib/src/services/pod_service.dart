import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_service.dart';

/// An entry in the pod cache — one per Flutter version.
class PodCacheEntry {
  final String version;
  final String path;
  final int sizeBytes;

  const PodCacheEntry({
    required this.version,
    required this.path,
    required this.sizeBytes,
  });
}

/// Manages version-isolated CocoaPods caches under `~/.fve/pods/<version>/`.
///
/// The isolation is achieved by setting the `CP_HOME_DIR` environment variable
/// before running `pod install` / `pod update`, and by injecting a small Ruby
/// snippet at the top of `ios/Podfile` so that CocoaPods picks up the right
/// cache regardless of how it is invoked (Xcode GUI, flutter run, Fastlane…).
///
/// The injected block is conditional on `~/.fve` existing, so CI machines
/// without fve installed fall back to `~/.cocoapods` automatically.
class PodService {
  static const _blockStart = '# fve managed — do not edit this block';
  static const _blockEnd = '# end fve managed';

  // ── Paths ──────────────────────────────────────────────────────────────────

  static String get podsDir => p.join(CacheService.fveHome, 'pods');

  String podCacheDir(String version) => p.join(podsDir, version);

  void ensurePodCacheDir(String version) {
    Directory(podCacheDir(version)).createSync(recursive: true);
  }

  // ── Podfile helpers ────────────────────────────────────────────────────────

  /// Returns the path to `ios/Podfile` under [projectDir], or null if absent.
  String? findPodfile(String projectDir) {
    final f = File(p.join(projectDir, 'ios', 'Podfile'));
    return f.existsSync() ? f.path : null;
  }

  /// Returns true when [projectDir] contains an `ios/Podfile`.
  bool hasPodfile(String projectDir) => findPodfile(projectDir) != null;

  /// Returns the Flutter version embedded in the fve block of the Podfile,
  /// or null if no fve block is present.
  String? podfileInjectionVersion(String projectDir) {
    final path = findPodfile(projectDir);
    if (path == null) return null;
    final content = File(path).readAsStringSync();
    if (!content.contains(_blockStart)) return null;
    // The block contains: _fve_pods = File.join(_fve_root, 'pods', '<version>')
    final match = RegExp("'pods', '([^']+)'").firstMatch(content);
    return match?.group(1);
  }

  // ── Podfile injection ──────────────────────────────────────────────────────

  /// Injects (or replaces) the fve `CP_HOME_DIR` block at the top of the
  /// `ios/Podfile`.  Safe to call multiple times — idempotent.
  ///
  /// The block is a conditional Ruby snippet:
  /// ```ruby
  /// # fve managed — do not edit this block
  /// _fve_root = File.join(ENV['HOME'], '.fve')
  /// _fve_pods = File.join(_fve_root, 'pods', '<version>')
  /// ENV['CP_HOME_DIR'] = _fve_pods if Dir.exist?(_fve_root)
  /// # end fve managed
  /// ```
  /// On machines without fve (`~/.fve` absent) the block is a no-op, so CI
  /// pipelines continue to use their own `~/.cocoapods` cache.
  void injectPodfile(String projectDir, String version) {
    final path = findPodfile(projectDir);
    if (path == null) return;

    final file = File(path);
    var content = file.readAsStringSync();

    content = _removeFveBlock(content);

    file.writeAsStringSync('${_buildBlock(version)}\n$content');
  }

  /// Removes the fve block from `ios/Podfile` if present.
  void removePodfileInjection(String projectDir) {
    final path = findPodfile(projectDir);
    if (path == null) return;

    final file = File(path);
    file.writeAsStringSync(_removeFveBlock(file.readAsStringSync()));
  }

  String _buildBlock(String version) {
    return '$_blockStart\n'
        "_fve_root = File.join(ENV['HOME'], '.fve')\n"
        "_fve_pods = File.join(_fve_root, 'pods', '$version')\n"
        "ENV['CP_HOME_DIR'] = _fve_pods if Dir.exist?(_fve_root)\n"
        '$_blockEnd';
  }

  String _removeFveBlock(String content) {
    // Matches the fve block (including optional trailing newline).
    final pattern = RegExp(
      '${RegExp.escape(_blockStart)}.*?${RegExp.escape(_blockEnd)}\n?',
      dotAll: true,
    );
    return content.replaceFirst(pattern, '');
  }

  // ── Pod operations ─────────────────────────────────────────────────────────

  /// Runs `pod install` in `<projectDir>/ios/` with `CP_HOME_DIR` set.
  Future<int> podInstall(String projectDir, String version) {
    return _runPod(projectDir, version, ['install']);
  }

  /// Runs `pod update [podName]` with `CP_HOME_DIR` set.
  Future<int> podUpdate(
    String projectDir,
    String version, {
    String? podName,
  }) {
    final args = podName != null ? ['update', podName] : ['update'];
    return _runPod(projectDir, version, args);
  }

  Future<int> _runPod(
    String projectDir,
    String version,
    List<String> args,
  ) async {
    ensurePodCacheDir(version);

    final iosDir = Directory(p.join(projectDir, 'ios'));
    if (!iosDir.existsSync()) {
      throw StateError('ios/ directory not found in $projectDir');
    }

    final env = Map<String, String>.from(Platform.environment)
      ..['CP_HOME_DIR'] = podCacheDir(version);

    final process = await Process.start(
      'pod',
      args,
      workingDirectory: iosDir.path,
      environment: env,
      mode: ProcessStartMode.inheritStdio,
    );

    return process.exitCode;
  }

  // ── Cache management ───────────────────────────────────────────────────────

  /// Lists all version-isolated pod caches, sorted by version.
  List<PodCacheEntry> listCaches() {
    final dir = Directory(podsDir);
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .whereType<Directory>()
        .map(
          (d) => PodCacheEntry(
            version: p.basename(d.path),
            path: d.path,
            sizeBytes: _dirSize(d),
          ),
        )
        .toList()
      ..sort((a, b) => a.version.compareTo(b.version));
  }

  /// Deletes the pod cache for [version].
  void clearCache(String version) {
    final dir = Directory(podCacheDir(version));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Deletes all pod caches.
  void clearAllCaches() {
    final dir = Directory(podsDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  int _dirSize(Directory dir) {
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {}
    return total;
  }
}
