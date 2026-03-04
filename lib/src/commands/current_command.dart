import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class CurrentCommand extends FveCommand {
  @override
  String get name => 'current';

  @override
  String get description =>
      'Show the active Flutter version (project-pinned and global).';

  @override
  Future<void> run() async {
    final cache = CacheService();
    final globalVersion = cache.currentGlobalVersion();
    final projectConfig = ProjectConfig.findForDirectory('.');
    final projectVersion = projectConfig?.flutterVersion;
    final configPath = ProjectConfig.configPathForDirectory('.');

    Logger.header('Active Flutter versions');

    if (projectVersion != null) {
      final installed = cache.isInstalled(projectVersion);
      final status = installed ? '' : '  ⚠ not installed';
      Logger.plain('  project : $projectVersion$status');
      Logger.dim('            $configPath');
    } else {
      Logger.dim('  project : (none — no .fverc found in directory tree)');
    }

    print('');

    if (globalVersion != null) {
      Logger.plain('  global  : $globalVersion');
      Logger.dim('            ${CacheService.currentLink} → ${cache.versionDir(globalVersion)}');
    } else {
      Logger.dim('  global  : (none — run `fve global <version>` to set one)');
    }

    print('');

    // Show effective version.
    final effective = projectVersion ?? globalVersion;
    if (effective != null) {
      Logger.info('  active  : $effective');
    } else {
      Logger.warning('  No active Flutter version. Install one: fve install <version>');
    }
  }
}
