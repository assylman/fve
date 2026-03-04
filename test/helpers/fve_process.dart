import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// ── Project root discovery ────────────────────────────────────────────────────

/// Absolute path to the fve project root (contains bin/fve.dart).
final String fveProjectRoot = () {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'bin', 'fve.dart')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Cannot find fve project root. Run tests from the project directory.',
      );
    }
    dir = parent;
  }
}();

// ── Result type ───────────────────────────────────────────────────────────────

/// The captured output of a single fve subprocess invocation.
class FveResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const FveResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  bool get success => exitCode == 0;

  /// Combined stdout + stderr for assertions that don't care which stream.
  String get output => '$stdout\n$stderr';

  @override
  String toString() =>
      'FveResult(exit=$exitCode)\n  out: ${stdout.trim()}\n  err: ${stderr.trim()}';
}

// ── Subprocess runner ─────────────────────────────────────────────────────────

/// Runs `dart run bin/fve.dart [args]` in a subprocess.
///
/// [homeDir] is set as the HOME environment variable so that fve writes its
/// data into an isolated temp directory rather than the developer's real home.
///
/// [workingDir] is the working directory for the fve process (affects where
/// commands like `use` write .fverc). Defaults to the project root.
///
/// [stdin] is optional text written to the process's stdin before EOF.
Future<FveResult> runFve(
  List<String> args, {
  required String homeDir,
  String? workingDir,
  String? stdin,
  Map<String, String> extraEnv = const {},
}) async {
  final dartExe = Platform.resolvedExecutable;
  // Use an absolute path to bin/fve.dart so that dart run works regardless
  // of the working directory we pass (which may be a temp project dir).
  final script = p.join(fveProjectRoot, 'bin', 'fve.dart');

  final process = await Process.start(
    dartExe,
    ['run', script, ...args],
    workingDirectory: workingDir ?? fveProjectRoot,
    environment: {
      ...Platform.environment,
      'HOME': homeDir,
      // Disable ANSI codes so we can assert on plain text.
      'TERM': 'dumb',
      'NO_COLOR': '1',
      ...extraEnv,
    },
  );

  if (stdin != null) {
    process.stdin.writeln(stdin);
  }
  await process.stdin.close();

  // Read stdout and stderr concurrently to avoid deadlocks on full buffers.
  final results = await Future.wait([
    process.stdout.transform(const Utf8Decoder()).join(),
    process.stderr.transform(const Utf8Decoder()).join(),
  ]);
  final exitCode = await process.exitCode;

  return FveResult(stdout: results[0], stderr: results[1], exitCode: exitCode);
}

// ── Test environment ──────────────────────────────────────────────────────────

/// Manages an isolated temporary HOME directory for a single test.
///
/// Creates the fve directory structure, fake Flutter SDK installations,
/// project configs, and provides a convenient [run] shortcut.
class FveTestEnv {
  final Directory homeDir;
  final List<Directory> _temps = [];

  FveTestEnv._(this.homeDir);

  /// Creates a new test environment backed by a fresh temp directory.
  factory FveTestEnv.create() =>
      FveTestEnv._(Directory.systemTemp.createTempSync('fve_home_'));

  // ── Path accessors ──────────────────────────────────────────────────────

  String get homePath => homeDir.path;
  String get fveHome => p.join(homePath, '.fve');
  String get versionsDir => p.join(fveHome, 'versions');
  String get currentLink => p.join(fveHome, 'current');
  String get configFilePath => p.join(fveHome, 'config.json');

  // ── Fixture helpers ─────────────────────────────────────────────────────

  /// Installs a fake Flutter SDK for [version].
  ///
  /// Creates executable shell scripts for `flutter` and `dart` that simply
  /// echo their name and the version, then exit 0. This is enough to satisfy
  /// CacheService.isInstalled() and to let proxy commands (flutter, dart,
  /// spawn, exec) actually launch something without needing a real SDK.
  void installVersion(String version) {
    final binDir = Directory(p.join(versionsDir, version, 'bin'))
      ..createSync(recursive: true);

    for (final name in ['flutter', 'dart']) {
      final bin = File(p.join(binDir.path, name))
        ..writeAsStringSync('#!/bin/sh\necho "$name $version"\nexit 0\n');
      Process.runSync('chmod', ['+x', bin.path]);
    }
  }

  /// Sets the `~/.fve/current` symlink to [version] and writes config.json.
  ///
  /// [version] must already be installed via [installVersion].
  void setGlobal(String version) {
    final target = p.join(versionsDir, version);
    final link = Link(currentLink);
    if (link.existsSync()) link.deleteSync();
    link.createSync(target);
    writeConfig({'default_version': version});
  }

  /// Writes raw data to `~/.fve/config.json`.
  void writeConfig(Map<String, dynamic> data) {
    File(configFilePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Creates a temporary project directory, optionally with a `.fverc`.
  ///
  /// The directory is owned by this env and deleted in [dispose].
  Directory createProjectDir({String? pinnedVersion}) {
    final dir = Directory.systemTemp.createTempSync('fve_proj_');
    _temps.add(dir);
    if (pinnedVersion != null) {
      File(p.join(dir.path, '.fverc')).writeAsStringSync(
        '{\n  "flutter_version": "$pinnedVersion"\n}\n',
      );
    }
    return dir;
  }

  /// Creates a project dir with a pubspec.yaml (to trigger auto pub get logic).
  Directory createFlutterProjectDir({String? pinnedVersion}) {
    final dir = createProjectDir(pinnedVersion: pinnedVersion);
    File(p.join(dir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: test_app\nversion: 1.0.0\n');
    return dir;
  }

  // ── Convenience run ─────────────────────────────────────────────────────

  /// Runs fve with this environment's HOME.
  ///
  /// [workingDir] defaults to the project root (not the temp home).
  Future<FveResult> run(
    List<String> args, {
    String? workingDir,
    String? stdin,
  }) =>
      runFve(
        args,
        homeDir: homePath,
        workingDir: workingDir,
        stdin: stdin,
      );

  // ── Query helpers ───────────────────────────────────────────────────────

  /// Returns true if the `~/.fve/current` symlink exists.
  bool get hasGlobalSymlink => Link(currentLink).existsSync();

  /// Returns the version the `~/.fve/current` symlink points to, or null.
  String? get globalVersion {
    final link = Link(currentLink);
    if (!link.existsSync()) return null;
    return p.basename(link.targetSync());
  }

  /// Returns the contents of `~/.fve/config.json` as a Map, or {} if absent.
  Map<String, dynamic> readConfig() {
    final file = File(configFilePath);
    if (!file.existsSync()) return {};
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  void dispose() {
    for (final d in _temps) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    if (homeDir.existsSync()) homeDir.deleteSync(recursive: true);
  }
}
