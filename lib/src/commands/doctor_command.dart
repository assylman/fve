import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class DoctorCommand extends FveCommand {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check your fve environment for problems and print setup instructions.';

  @override
  Future<void> run() async {
    Logger.bold('\nfve doctor');
    print('');

    final cache = CacheService();

    // ── 1. fve home ──────────────────────────────────────────────────────
    _section('fve home');
    final home = CacheService.fveHome;
    _check('fve home exists', Directory(home).existsSync(), home);
    _check(
      'versions dir exists',
      Directory(CacheService.versionsDir).existsSync(),
      CacheService.versionsDir,
    );

    // ── 2. Installed versions ────────────────────────────────────────────
    _section('Installed versions');
    final versions = cache.installedVersions();
    if (versions.isEmpty) {
      Logger.warning('  No versions installed. Run: fve install <version>');
    } else {
      for (final v in versions) {
        Logger.success('  $v');
      }
    }

    // ── 3. Global version ────────────────────────────────────────────────
    _section('Global version');
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null) {
      _check('Global version set', true, globalVersion);
      _check(
        'Symlink target exists',
        Directory(cache.versionDir(globalVersion)).existsSync(),
        CacheService.currentLink,
      );
    } else {
      Logger.warning('  No global version. Run: fve global <version>');
    }

    // ── 4. PATH check ─────────────────────────────────────────────────────
    _section('PATH');
    final pathEnv = Platform.environment['PATH'] ?? '';
    final fveBinInPath =
        pathEnv.contains(p.join(home, 'current', 'bin'));
    _check(
      'fve current/bin is in PATH',
      fveBinInPath,
      fveBinInPath
          ? null
          : 'Add to your shell rc:\n'
              '    export PATH="\$HOME/.fve/current/bin:\$PATH"',
    );

    // ── 5. Project config ────────────────────────────────────────────────
    _section('Project (current directory)');
    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final v = projectConfig.flutterVersion;
      final installed = cache.isInstalled(v);
      _check('Project version set', true, v);
      _check(
        'Project version installed',
        installed,
        installed ? null : 'Run: fve install $v',
      );
      final configPath = ProjectConfig.configPathForDirectory('.');
      Logger.dim('  config: $configPath');
    } else {
      Logger.dim('  No .fverc found. Run: fve use <version>');
    }

    // ── 6. System tools ──────────────────────────────────────────────────
    _section('System tools');
    _checkTool('git', ['--version']);
    _checkTool('unzip', ['-v']);
    if (Platform.isMacOS) {
      _checkTool('pod', ['--version']);
      _checkTool('xcode-select', ['--print-path']);
    }

    print('');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _section(String title) {
    Logger.header(title);
  }

  void _check(String label, bool ok, String? detail) {
    if (ok) {
      Logger.success('  $label${detail != null ? ': $detail' : ''}');
    } else {
      Logger.error('  $label${detail != null ? '\n    $detail' : ''}');
    }
  }

  void _checkTool(String tool, List<String> args) {
    try {
      final result = Process.runSync(tool, args);
      final ok = result.exitCode == 0;
      final version = result.stdout.toString().trim().split('\n').first;
      _check(tool, ok, ok ? version : null);
    } catch (_) {
      Logger.error('  $tool: not found');
    }
  }
}
