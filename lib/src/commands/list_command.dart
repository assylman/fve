import '../help.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Shows all locally installed Flutter SDK versions and marks which one is
/// active globally and/or pinned in the current project.
class ListCommand extends FveCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'Show locally installed Flutter SDK versions.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('list', 'Show all installed versions with global / project markers'),
        HelpExample('releases', 'Browse all versions available for download'),
      ];

  @override
  Future<void> run() async {
    final cache = CacheService();
    final versions = cache.installedVersions();

    if (versions.isEmpty) {
      Logger.warning('No Flutter versions installed.');
      Logger.dim('Install one  : fve install <version>');
      Logger.dim('Browse all   : fve releases');
      return;
    }

    final globalVersion = cache.currentGlobalVersion();
    final projectVersion = ProjectConfig.findForDirectory('.')?.flutterVersion;

    Logger.header('Installed Flutter versions');

    for (final v in versions) {
      final isGlobal = v == globalVersion;
      final isProject = v == projectVersion;

      final tags = [
        if (isGlobal) 'global',
        if (isProject) 'project',
      ].join(', ');

      final tagLabel = tags.isNotEmpty ? '  ← $tags' : '';
      final marker = (isProject || isGlobal) ? '●' : ' ';
      Logger.plain('  $marker $v$tagLabel');
    }

    print('');
    Logger.dim('${versions.length} version(s) installed.');
    Logger.dim('Browse available versions: fve releases');
  }
}
