import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import 'cache_service.dart';

/// Runs a `pod` invocation and reports its combined output.
///
/// [args] are the pod arguments (e.g. `['install']`), [cwd] is the working
/// directory (`<project>/ios`), [env] the environment (with `CP_HOME_DIR`
/// already set).  [onOutput] is called with each decoded chunk of the
/// process's stdout/stderr so the caller can accumulate it for analysis.
/// Returns the process exit code.
///
/// The default implementation ([PodService.defaultRunner]) tees the live
/// output to the real stdout/stderr while feeding [onOutput].  Tests inject a
/// fake that returns a canned output + exit code without spawning `pod`.
typedef PodProcessRunner = Future<int> Function(
  List<String> args,
  String cwd,
  Map<String, String> env,
  void Function(String) onOutput,
);

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

  /// How the service spawns `pod`.  Defaults to [defaultRunner]; overridden in
  /// tests with a fake that returns canned output + exit code.
  final PodProcessRunner _runner;

  PodService({PodProcessRunner? processRunner})
      : _runner = processRunner ?? defaultRunner;

  /// Substrings (matched case-insensitively) that indicate CocoaPods failed
  /// because its local spec index is out of date relative to the pinned
  /// versions in `Podfile.lock`.
  static const _staleSpecSignatures = <String>[
    'could not find compatible versions for pod',
    'specs repository is too out-of-date',
    'unable to find a specification for',
    'out-of-date source repos',
  ];

  /// Returns true when [output] looks like a stale-spec-index failure that a
  /// `--repo-update` retry can fix.
  ///
  /// This is intentionally heuristic and may yield false positives (e.g. a pod
  /// that genuinely does not exist at any version).  That is acceptable: the
  /// cost of a false positive is a single extra `--repo-update` attempt, which
  /// then fails again with the correct, real error.
  static bool isStaleSpecRepoError(String output) {
    final lower = output.toLowerCase();
    return _staleSpecSignatures.any(lower.contains);
  }

  /// Appends `--repo-update` unless it is already present (idempotent).
  static List<String> _withRepoUpdate(List<String> args) =>
      args.contains('--repo-update') ? args : [...args, '--repo-update'];

  /// Real runner: spawns `pod` with piped stdio, tees each decoded chunk to
  /// the live stdout/stderr (so the user still sees progress) while forwarding
  /// it to [onOutput] for analysis.  Decodes as UTF-8 tolerantly so binary or
  /// malformed bytes never crash the stream.
  static Future<int> defaultRunner(
    List<String> args,
    String cwd,
    Map<String, String> env,
    void Function(String) onOutput,
  ) async {
    final process = await Process.start(
      'pod',
      args,
      workingDirectory: cwd,
      environment: env,
      mode: ProcessStartMode.normal,
    );

    const decoder = Utf8Decoder(allowMalformed: true);

    final stdoutDone = process.stdout.transform(decoder).listen((chunk) {
      stdout.write(chunk);
      onOutput(chunk);
    }).asFuture<void>();

    final stderrDone = process.stderr.transform(decoder).listen((chunk) {
      stderr.write(chunk);
      onOutput(chunk);
    }).asFuture<void>();

    // Await the exit code AND both stream drains so no trailing output is lost
    // and we never deadlock on an unread pipe.
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return exitCode;
  }

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
  ///
  /// The spec index is refreshed (`--repo-update`) when [repoUpdate] is true
  /// (explicit `--repo-update` flag) or when this version's pod cache is being
  /// created for the first time — a fresh cache would otherwise start with an
  /// empty/missing spec index, the most common cause of resolution failures.
  /// On a warm cache the fast path (no `--repo-update`) is used, and the
  /// stale-index retry in [_runPod] heals it only if it actually fails.
  Future<int> podInstall(
    String projectDir,
    String version, {
    bool repoUpdate = false,
  }) {
    final firstTime = !Directory(podCacheDir(version)).existsSync();
    return _runPod(
      projectDir,
      version,
      ['install'],
      repoUpdate: repoUpdate || firstTime,
    );
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

  /// Runs a `pod` command with the version-isolated `CP_HOME_DIR`, teeing its
  /// output for analysis.
  ///
  /// When [repoUpdate] is true, `--repo-update` is added to the first attempt.
  /// Otherwise, if an install/update fails with a stale-spec-index signature
  /// and [allowRetry] is true, the command is re-run exactly once with
  /// `--repo-update` added.  `--repo-update` only refreshes the spec index and
  /// then fetches the missing/changed pods — pods already in this version's
  /// cache are reused, nothing is re-downloaded wholesale.
  Future<int> _runPod(
    String projectDir,
    String version,
    List<String> args, {
    bool repoUpdate = false,
    bool allowRetry = true,
  }) async {
    ensurePodCacheDir(version);

    final iosDir = Directory(p.join(projectDir, 'ios'));
    if (!iosDir.existsSync()) {
      throw StateError('ios/ directory not found in $projectDir');
    }

    final env = Map<String, String>.from(Platform.environment)
      ..['CP_HOME_DIR'] = podCacheDir(version);

    final effectiveArgs = repoUpdate ? _withRepoUpdate(args) : args;

    final buffer = StringBuffer();
    final exitCode = await _runner(
      effectiveArgs,
      iosDir.path,
      env,
      buffer.write,
    );

    final isInstallOrUpdate =
        args.isNotEmpty && (args.first == 'install' || args.first == 'update');

    if (exitCode != 0 &&
        allowRetry &&
        !repoUpdate &&
        isInstallOrUpdate &&
        isStaleSpecRepoError(buffer.toString())) {
      Logger.plain('');
      Logger.warning(
        'CocoaPods spec index is out of date — retrying with --repo-update…',
      );
      Logger.dim(
        '  Refreshing the spec index; only missing/changed pods are fetched, '
        'cached pods are reused.',
      );
      return _runPod(
        projectDir,
        version,
        args,
        repoUpdate: true,
        allowRetry: false,
      );
    }

    return exitCode;
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
