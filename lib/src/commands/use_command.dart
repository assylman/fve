import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../services/config_service.dart';
import '../services/pod_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class UseCommand extends FveCommand {
  @override
  String get name => 'use';

  @override
  String get description =>
      'Pin a Flutter version for the current project by writing a .fverc file.';

  @override
  String get argSyntax => '<version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<version>', 'Installed Flutter version to pin for this project'),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('use 3.22.2', 'Pin version for the current project'),
        HelpExample('use 3.22.2 --global', 'Pin and also set as system-wide default'),
        HelpExample('use 3.22.2 --skip-pub-get', 'Pin without running flutter pub get'),
        HelpExample('use 3.22.2 --no-vscode', 'Pin without updating .vscode/settings.json'),
      ];

  UseCommand() {
    argParser
      ..addFlag(
        'global',
        abbr: 'g',
        help: 'Also set this version as the system-wide global default.',
        negatable: false,
      )
      ..addFlag(
        'skip-install',
        help: 'Write .fverc even if the version is not installed.',
        negatable: false,
      )
      ..addFlag(
        'skip-pub-get',
        help: 'Skip running flutter pub get after pinning.',
        negatable: false,
      )
      ..addFlag(
        'no-vscode',
        help: 'Skip updating .vscode/settings.json.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      _showCurrentVersion();
      return;
    }

    final version = argResults!.rest.first;
    final setGlobal = argResults!['global'] as bool;
    final skipInstall = argResults!['skip-install'] as bool;
    final skipPubGet = argResults!['skip-pub-get'] as bool;
    final noVsCode = argResults!['no-vscode'] as bool;

    final cache = CacheService();
    final config = ConfigService();
    final cwd = Directory.current.path;

    if (!skipInstall && !cache.isInstalled(version)) {
      Logger.error('Flutter $version is not installed.');
      Logger.dim('Install it first: fve install $version');
      exit(1);
    }

    // Write .fverc.
    ProjectConfig(flutterVersion: version).saveToDirectory(cwd);
    Logger.success('Pinned Flutter $version → $cwd/.fverc');

    // Inject CP_HOME_DIR block into ios/Podfile if the project has one.
    final pod = PodService();
    if (pod.hasPodfile(cwd)) {
      pod.injectPodfile(cwd, version);
      Logger.success('Updated ios/Podfile with pod cache isolation');
      Logger.dim('  CP_HOME_DIR → ${pod.podCacheDir(version)}');
    }

    // Update global symlink if requested.
    if (setGlobal) {
      cache.setCurrentSymlink(version);
      config.setDefaultVersion(version);
      Logger.success('Global default set to Flutter $version');
    }

    print('');

    // VS Code settings.json integration.
    final vsCodeEnabled = !noVsCode && config.getVsCodeIntegration();
    if (vsCodeEnabled && !skipInstall) {
      _updateVsCodeSettings(version, cwd);
    }

    // Auto pub get.
    final pubGetEnabled = !skipPubGet && config.getAutoPubGet();
    if (pubGetEnabled && !skipInstall) {
      await _runPubGet(version, cwd, cache);
    }
  }

  // ── No-arg: show current version ─────────────────────────────────────────

  void _showCurrentVersion() {
    final cache = CacheService();

    // Project version from .fverc (walks up directory tree).
    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final version = projectConfig.flutterVersion;
      final installed = cache.isInstalled(version);
      Logger.info('Project version : $version');
      if (!installed) {
        Logger.warning('  Not installed — run: fve install $version');
      }
      return;
    }

    // Fall back to global.
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null) {
      Logger.info('Global version  : $globalVersion');
      Logger.dim('No .fverc found in current directory.');
      Logger.dim('To pin a version here: fve use <version>');
      return;
    }

    Logger.warning('No Flutter version set.');
    Logger.dim('Pin a project version : fve use <version>');
    Logger.dim('Set a global default  : fve global <version>');
  }

  // ── VS Code integration ───────────────────────────────────────────────────

  void _updateVsCodeSettings(String version, String directory) {
    final vscodeDir = Directory(p.join(directory, '.vscode'));
    final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));

    Map<String, dynamic> settings = {};

    if (settingsFile.existsSync()) {
      try {
        final content = settingsFile.readAsStringSync();
        if (content.trim().isNotEmpty) {
          settings = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {
        // Couldn't parse existing file — overwrite with our key only.
      }
    } else {
      vscodeDir.createSync(recursive: true);
    }

    final sdkPath = CacheService().versionDir(version);
    settings['dart.flutterSdkPath'] = sdkPath;

    settingsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings),
    );

    Logger.success('Updated .vscode/settings.json');
    Logger.dim('  dart.flutterSdkPath → $sdkPath');
    Logger.dim('  Add .vscode/settings.json to .gitignore (path is machine-specific).');
  }

  // ── Auto pub get ──────────────────────────────────────────────────────────

  Future<void> _runPubGet(
    String version,
    String directory,
    CacheService cache,
  ) async {
    final pubspec = File(p.join(directory, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;

    Logger.info('Running flutter pub get…');

    final process = await Process.start(
      cache.flutterBin(version),
      ['pub', 'get'],
      workingDirectory: directory,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      Logger.warning('flutter pub get exited with code $exitCode.');
    }
  }
}
