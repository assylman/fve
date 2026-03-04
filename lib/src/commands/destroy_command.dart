import 'dart:io';

import '../help.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class DestroyCommand extends FveCommand {
  @override
  String get name => 'destroy';

  @override
  String get description =>
      'Remove the entire fve cache, deleting all installed Flutter SDK versions and configuration.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('destroy', 'Remove all cached SDKs and config (with confirmation)'),
        HelpExample('destroy --force', 'Skip the confirmation prompt'),
      ];

  DestroyCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Skip the confirmation prompt.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final force = argResults!['force'] as bool;
    final home = CacheService.fveHome;
    final dir = Directory(home);

    if (!dir.existsSync()) {
      Logger.warning('fve cache directory does not exist: $home');
      return;
    }

    final versions = CacheService().installedVersions();

    Logger.warning('This will permanently delete $home');
    if (versions.isNotEmpty) {
      Logger.dim('  Including ${versions.length} installed Flutter SDK version(s):');
      for (final v in versions) {
        Logger.dim('    • $v');
      }
    }

    if (!force) {
      stdout.write('\nType "yes" to confirm: ');
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input != 'yes') {
        Logger.plain('Aborted.');
        return;
      }
    }

    dir.deleteSync(recursive: true);
    Logger.success('fve cache destroyed.');
    Logger.dim('Run fve install <version> to start fresh.');
  }
}
