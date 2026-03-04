import 'dart:io';

import '../help.dart';
import '../models/project_config.dart';
import '../services/pod_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

// ── Root pod command ───────────────────────────────────────────────────────────

class PodCommand extends FveCommand {
  @override
  String get name => 'pod';

  @override
  String get description =>
      'Manage CocoaPods with version-isolated cache (sets CP_HOME_DIR).';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('pod install', 'Run pod install with isolated cache'),
        HelpExample('pod update', 'Run pod update with isolated cache'),
        HelpExample('pod update FirebaseCore', 'Update a single pod'),
        HelpExample('pod cache list', 'Show disk usage per Flutter version'),
        HelpExample('pod cache clear 3.22.2', 'Delete cache for one version'),
        HelpExample('pod cache clear --all', 'Delete all pod caches'),
      ];

  PodCommand() {
    addSubcommand(_PodInstallCommand());
    addSubcommand(_PodUpdateCommand());
    addSubcommand(_PodCacheCommand());
  }
}

// ── Shared context resolver ────────────────────────────────────────────────────

/// Reads the active Flutter version from .fverc and returns (version, cwd).
/// Prints an error and exits if no .fverc is found.
({String version, String projectDir}) _resolveContext() {
  final projectDir = Directory.current.path;
  final config = ProjectConfig.findForDirectory(projectDir);

  if (config == null) {
    Logger.error('No .fverc found. Run fve use <version> first.');
    exit(1);
  }

  return (version: config.flutterVersion, projectDir: projectDir);
}

// ── pod install ────────────────────────────────────────────────────────────────

class _PodInstallCommand extends FveCommand {
  @override
  String get name => 'install';

  @override
  String get description =>
      "Run pod install using the project's version-isolated pod cache.";

  @override
  Future<void> run() async {
    final (:version, :projectDir) = _resolveContext();
    final pod = PodService();

    if (!pod.hasPodfile(projectDir)) {
      Logger.error('No ios/Podfile found in $projectDir');
      Logger.dim('Is this a Flutter project with iOS support?');
      exit(1);
    }

    Logger.info('Running pod install  [Flutter $version]');
    Logger.dim('  CP_HOME_DIR → ${pod.podCacheDir(version)}');
    print('');

    final exitCode = await pod.podInstall(projectDir, version);

    print('');
    if (exitCode != 0) {
      Logger.error('pod install failed (exit $exitCode).');
      exit(exitCode);
    }
    Logger.success('pod install complete.');
  }
}

// ── pod update ─────────────────────────────────────────────────────────────────

class _PodUpdateCommand extends FveCommand {
  @override
  String get name => 'update';

  @override
  String get description =>
      "Run pod update using the project's version-isolated pod cache.";

  @override
  String get argSyntax => '[pod-name]';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('[pod-name]', 'Update one pod only; omit to update all'),
      ];

  @override
  Future<void> run() async {
    final (:version, :projectDir) = _resolveContext();
    final pod = PodService();

    if (!pod.hasPodfile(projectDir)) {
      Logger.error('No ios/Podfile found in $projectDir');
      exit(1);
    }

    final podName = argResults!.rest.firstOrNull;
    final label = podName != null ? 'pod update $podName' : 'pod update';

    Logger.info('Running $label  [Flutter $version]');
    Logger.dim('  CP_HOME_DIR → ${pod.podCacheDir(version)}');
    print('');

    final exitCode = await pod.podUpdate(projectDir, version, podName: podName);

    print('');
    if (exitCode != 0) {
      Logger.error('$label failed (exit $exitCode).');
      exit(exitCode);
    }
    Logger.success('$label complete.');
  }
}

// ── pod cache ──────────────────────────────────────────────────────────────────

class _PodCacheCommand extends FveCommand {
  @override
  String get name => 'cache';

  @override
  String get description => 'Inspect and clear version-isolated pod caches.';

  _PodCacheCommand() {
    addSubcommand(_PodCacheListCommand());
    addSubcommand(_PodCacheClearCommand());
  }
}

// ── pod cache list ─────────────────────────────────────────────────────────────

class _PodCacheListCommand extends FveCommand {
  @override
  String get name => 'list';

  @override
  String get description =>
      'List all version-isolated pod caches with disk usage.';

  @override
  Future<void> run() async {
    final caches = PodService().listCaches();

    if (caches.isEmpty) {
      Logger.dim('No pod caches found.');
      Logger.dim('Run fve pod install inside a Flutter iOS project.');
      return;
    }

    Logger.header('Pod Caches');
    for (final entry in caches) {
      final size = _formatBytes(entry.sizeBytes).padLeft(8);
      Logger.plain('  ${entry.version.padRight(14)} $size');
      Logger.dim('    ${entry.path}');
    }
    print('');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ── pod cache clear ────────────────────────────────────────────────────────────

class _PodCacheClearCommand extends FveCommand {
  @override
  String get name => 'clear';

  @override
  String get description =>
      'Delete the pod cache for a Flutter version (or all versions).';

  @override
  String get argSyntax => '<version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<version>', 'Flutter version whose pod cache to delete'),
      ];

  _PodCacheClearCommand() {
    argParser.addFlag(
      'all',
      help: 'Clear every pod cache (all Flutter versions).',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final clearAll = argResults!['all'] as bool;
    final pod = PodService();

    if (clearAll) {
      pod.clearAllCaches();
      Logger.success('Cleared all pod caches.');
      return;
    }

    if (argResults!.rest.isEmpty) {
      Logger.error('Provide a version or pass --all.');
      Logger.dim('  fve pod cache clear 3.22.2');
      Logger.dim('  fve pod cache clear --all');
      exit(64);
    }

    final version = argResults!.rest.first;
    pod.clearCache(version);
    Logger.success('Cleared pod cache for Flutter $version.');
  }
}
