import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/tui.dart';

/// Handles download, checksum verification, and SDK extraction.
///
/// Install strategy (in priority order):
///   1. git clone — shallow + blobless clone, ~200 MB, resume-aware.
///   2. aria2c    — 16 parallel connections, resume support (archive fallback).
///   3. HTTP      — single-connection streaming (last resort).
class DownloadService {
  final http.Client _client;

  DownloadService({http.Client? client}) : _client = client ?? http.Client();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Installs Flutter [version] into [destDir] via a shallow git clone.
  ///
  /// Downloads ~200 MB instead of the full 1 GB pre-built archive by using
  /// `git clone --depth 1 --filter=blob:none`. The Flutter engine (~400 MB)
  /// is not stored in the git repository; it is fetched automatically the
  /// first time `flutter` or `dart` is invoked.
  ///
  /// **Resume support**: if a previous clone was interrupted after git
  /// received all pack objects (but before checkout finished), this method
  /// detects the existing `.git` directory and calls `git checkout -f` to
  /// restore any missing working-tree files instead of re-downloading
  /// everything. If the pack data itself is incomplete the partial directory
  /// is removed and a fresh clone is started.
  ///
  /// Throws if git is unavailable — call [gitAvailable] first.
  Future<void> installViaGit(String version, String destDir) async {
    final gitDir = Directory(p.join(destDir, '.git'));
    final destDirectory = Directory(destDir);

    if (gitDir.existsSync()) {
      // A previous clone was started. Try to resume before giving up.
      if (await _tryResumeGitClone(version, destDir)) return;

      // Pack data is incomplete or corrupt — wipe and start fresh.
      Logger.dim('  Could not resume — starting a fresh clone…');
      _deleteDir(destDirectory);
    } else if (destDirectory.existsSync()) {
      // Directory present but no .git → corrupt state left by extraction or
      // another tool. Remove it so git clone can use the path.
      _deleteDir(destDirectory);
    }

    await _freshGitClone(version, destDir);
  }

  /// Downloads [url] to [destPath] using the fastest available HTTP backend.
  ///
  /// - aria2c (when installed) opens 16 parallel connections and resumes
  ///   interrupted downloads automatically with `-c`.
  /// - HTTP streaming is used as a fallback with a tip to install aria2c.
  Future<void> download(String url, String destPath) async {
    if (await _aria2Available()) {
      await _downloadWithAria2(url, destPath);
    } else {
      Logger.dim(
        '  Tip: install aria2c for 16× faster parallel downloads'
        ' (brew install aria2)',
      );
      await _downloadWithHttp(url, destPath);
    }
  }

  /// Verifies that [filePath] matches [expectedSha256].
  /// Throws if the checksum does not match.
  /// No-op when [expectedSha256] is empty (no checksum provided by the API).
  Future<void> verifySha256(String filePath, String expectedSha256) async {
    if (expectedSha256.isEmpty) return;

    final bytes = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();

    if (actual != expectedSha256) {
      throw Exception(
        'SHA-256 mismatch for ${p.basename(filePath)}\n'
        '  expected: $expectedSha256\n'
        '  actual:   $actual',
      );
    }
  }

  /// Extracts the Flutter SDK archive from [archivePath] into [destDir].
  ///
  /// The archive always contains a top-level `flutter/` directory. We extract
  /// into a temp dir and then rename that inner directory to [destDir] so the
  /// final layout is `destDir/bin/flutter` (not `destDir/flutter/bin/flutter`).
  Future<void> extractSdk(String archivePath, String destDir) async {
    final tempDir = Directory.systemTemp.createTempSync('fve_extract_');

    try {
      await _extract(archivePath, tempDir.path);

      final innerDir = Directory(p.join(tempDir.path, 'flutter'));
      if (!innerDir.existsSync()) {
        throw Exception(
          'Unexpected archive structure: missing top-level flutter/ directory.',
        );
      }

      final dest = Directory(destDir);
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      innerDir.renameSync(destDir);
    } finally {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  // ── Git backend ───────────────────────────────────────────────────────────

  // Cached results so availability and version are only checked once per
  // process, regardless of how many versions are installed.
  static bool? _gitCacheResult;
  static int? _gitMajorVersionCache;

  /// Returns `true` when `git` is installed and executable on PATH.
  ///
  /// The result is cached after the first call so subsequent invocations
  /// within the same process pay no subprocess overhead.
  static Future<bool> gitAvailable() async {
    if (_gitCacheResult != null) return _gitCacheResult!;
    try {
      final r = await Process.run('git', ['--version']);
      if (r.exitCode == 0) {
        _gitCacheResult = true;
        // Parse "git version 2.39.3 (Apple Git-145)" → major = 2.
        final m =
            RegExp(r'git version (\d+)').firstMatch(r.stdout.toString());
        _gitMajorVersionCache = int.tryParse(m?.group(1) ?? '0') ?? 0;
      } else {
        _gitCacheResult = false;
        _gitMajorVersionCache = 0;
      }
    } catch (_) {
      _gitCacheResult = false;
      _gitMajorVersionCache = 0;
    }
    return _gitCacheResult!;
  }

  /// Attempts to finish a previously interrupted clone by restoring any
  /// missing working-tree files from already-downloaded git objects.
  ///
  /// Returns `true` when the resume succeeds, `false` when the git object
  /// database is too incomplete to recover (caller should start fresh).
  Future<bool> _tryResumeGitClone(String version, String destDir) async {
    Logger.info('  Detected an interrupted clone — attempting to resume…');
    try {
      // `rev-parse --verify HEAD` succeeds only when HEAD points to a valid
      // commit, meaning all pack objects were received successfully.
      final head = await Process.run(
        'git',
        ['-C', destDir, 'rev-parse', '--verify', 'HEAD'],
      );
      if (head.exitCode != 0) {
        Logger.dim('  Pack data is incomplete; cannot resume.');
        return false;
      }

      // Objects are intact. Force-checkout restores any files that were not
      // written to disk before the process was killed.
      Logger.dim('  Pack objects OK — restoring working tree…');
      await _runProcess('git', ['-C', destDir, 'checkout', '-f', 'HEAD']);
      Logger.success('Resumed successfully.');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Performs a fresh shallow, blobless clone of the Flutter repository at
  /// the given [version] tag (or branch name such as `master`).
  Future<void> _freshGitClone(String version, String destDir) async {
    Logger.info(
      '  Cloning Flutter $version'
      ' (shallow · blobless · ~200 MB vs 1 GB archive)…',
    );
    Logger.dim(
      '  Engine binaries (~400 MB) download automatically'
      ' on first flutter / dart run.',
    );
    print('');

    // --filter=blob:none tells the server to skip binary file blobs until
    // they are actually accessed, reducing the initial transfer by ~40%.
    // Supported since git 2.17 (April 2018); virtually all modern systems
    // qualify, but we gate on the major version just to be safe.
    final supportsFilter = (_gitMajorVersionCache ?? 0) >= 2;

    final args = [
      'clone',
      '--depth', '1',       // single commit — no git history
      '--single-branch',    // fetch only the requested branch/tag refs
      '--branch', version,  // tag (e.g. 3.22.2) or branch (e.g. master)
      if (supportsFilter) '--filter=blob:none',
      'https://github.com/flutter/flutter.git',
      destDir,
    ];

    // Inherit stdio so git's native progress bar (objects received, speed,
    // ETA) renders directly in the user's terminal.
    final process = await Process.start(
      'git',
      args,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      // Remove any partial clone so the cache is never left in a broken state.
      _deleteDir(Directory(destDir));
      throw Exception(_gitCloneErrorMessage(version, exitCode));
    }
  }

  /// Builds a human-readable error message for a failed `git clone`.
  ///
  /// git already printed its own low-level error to stderr (via inherited
  /// stdio), so we only need to add higher-level context and remediation
  /// steps.
  static String _gitCloneErrorMessage(String version, int exitCode) =>
      'git clone exited with code $exitCode.\n\n'
      'Possible causes:\n'
      '  • "$version" has no git tag in the Flutter repository\n'
      '    → Run `fve releases` to see valid version strings\n'
      '    → Or force the archive download: fve install $version --no-git\n'
      '  • No internet connection or github.com is unreachable\n'
      '    → Behind a proxy? export HTTPS_PROXY=http://host:port\n'
      '  • Disk full → check free space: df -h ~/.fve\n'
      '  • git credential / firewall issue\n'
      '    → Try: git clone https://github.com/flutter/flutter.git --depth 1';

  // ── aria2c backend ────────────────────────────────────────────────────────

  // Cache the availability check so every download in the same process does
  // not pay the cost of spawning a subprocess.
  static bool? _aria2CacheResult;

  /// Returns true when `aria2c` is installed and executable on PATH.
  static Future<bool> _aria2Available() async {
    if (_aria2CacheResult != null) return _aria2CacheResult!;
    try {
      final r = await Process.run('aria2c', ['--version']);
      _aria2CacheResult = r.exitCode == 0;
    } catch (_) {
      _aria2CacheResult = false;
    }
    return _aria2CacheResult!;
  }

  Future<void> _downloadWithAria2(String url, String destPath) async {
    Logger.info(
      '  Downloading with aria2c'
      ' (16 parallel connections · resume-enabled)…',
    );

    final process = await Process.start(
      'aria2c',
      [
        // Parallelism — split the file into 16 segments, 16 connections max.
        '-x', '16',
        '-s', '16',
        // Do not split segments smaller than 10 MB (avoids unnecessary
        // overhead for the small files we might download in tests).
        '--min-split-size=10M',
        // Resume an interrupted download automatically.
        '-c',
        // Skip file pre-allocation: faster startup, especially on macOS.
        '--file-allocation=none',
        // Refresh the in-terminal progress summary every second.
        '--summary-interval=1',
        // Suppress the "Download Results:" table printed after completion.
        '--download-result=hide',
        // Output directory and filename.
        '-d', p.dirname(destPath),
        '-o', p.basename(destPath),
        url,
      ],
      // Inherit the parent's file descriptors so aria2c's native progress
      // bar (including speed and ETA) renders directly in the user's terminal.
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      // aria2c writes its own .aria2 control file for resuming; leave it in
      // place so the next invocation (with -c) can continue from where it
      // stopped. Only remove the partial data file itself on hard failure.
      //
      // Actually aria2c handles this internally — we only reach here on a
      // non-recoverable error (e.g. 404, bad URL). In that case remove both
      // the partial file and control file to avoid stale state.
      for (final ext in ['', '.aria2']) {
        final f = File('$destPath$ext');
        if (f.existsSync()) f.deleteSync();
      }
      throw Exception('aria2c failed (exit $exitCode): $url');
    }
  }

  // ── HTTP streaming fallback ───────────────────────────────────────────────

  Future<void> _downloadWithHttp(String url, String destPath) async {
    final request  = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed (HTTP ${response.statusCode}): $url');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink   = File(destPath).openWrite();
    final bar    = ProgressBar(total: total, label: p.basename(destPath));

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      bar.update(received);
    }

    await sink.close();
    bar.complete();
  }

  // ── Extraction helpers ────────────────────────────────────────────────────

  Future<void> _extract(String archivePath, String targetDir) async {
    final ext = archivePath.toLowerCase();

    if (ext.endsWith('.zip')) {
      await _runProcess('unzip', ['-q', archivePath, '-d', targetDir]);
    } else if (ext.endsWith('.tar.xz') || ext.endsWith('.tar.gz')) {
      await _runProcess('tar', ['-xf', archivePath, '-C', targetDir]);
    } else {
      throw UnsupportedError('Unknown archive format: $archivePath');
    }
  }

  Future<void> _runProcess(String cmd, List<String> args) async {
    final result = await Process.run(cmd, args);
    if (result.exitCode != 0) {
      throw Exception(
        '$cmd failed (exit ${result.exitCode}):\n${result.stderr}',
      );
    }
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  void _deleteDir(Directory dir) {
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort — if we cannot delete, the next install attempt will
        // hit the same guard and report a meaningful error.
      }
    }
  }

}
