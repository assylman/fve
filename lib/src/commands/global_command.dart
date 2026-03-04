import 'dart:io';

import '../help.dart';
import '../services/cache_service.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class GlobalCommand extends FveCommand {
  @override
  String get name => 'global';

  @override
  String get description =>
      'Set the system-wide default Flutter version.';

  @override
  String get argSyntax => '<version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<version>', 'Installed Flutter version to set as the global default'),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('global 3.22.2', 'Set the system-wide default to 3.22.2'),
        HelpExample('global --unlink', 'Remove the global default (no system-wide version)'),
      ];

  GlobalCommand() {
    argParser.addFlag(
      'unlink',
      help: 'Remove the global default version symlink.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final unlink = argResults!['unlink'] as bool;
    final cache = CacheService();
    final config = ConfigService();

    if (unlink) {
      final link = Link(CacheService.currentLink);
      if (!link.existsSync()) {
        Logger.warning('No global version is set — nothing to unlink.');
        return;
      }
      link.deleteSync();
      config.clearDefaultVersion();
      Logger.success('Global Flutter version unlinked.');
      Logger.dim('Run fve global <version> to set a new global default.');
      return;
    }

    if (argResults!.rest.isEmpty) {
      usageException('Please provide a version number or --unlink.\n'
          'Example: fve global 3.22.2');
    }

    final version = argResults!.rest.first;

    if (!cache.isInstalled(version)) {
      Logger.error('Flutter $version is not installed.');
      Logger.dim('Install it first: fve install $version');
      exit(1);
    }

    cache.setCurrentSymlink(version);
    config.setDefaultVersion(version);

    Logger.success('Global Flutter version set to $version');
    print('');
    Logger.dim('Make sure your PATH includes:');
    Logger.dim('  export PATH="\$HOME/.fve/current/bin:\$PATH"');
  }
}
