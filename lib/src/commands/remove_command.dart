import 'dart:io';

import '../help.dart';
import '../services/cache_service.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class RemoveCommand extends FveCommand {
  @override
  String get name => 'remove';

  @override
  List<String> get aliases => ['uninstall', 'rm'];

  @override
  String get description => 'Remove one or all cached Flutter SDK versions.';

  @override
  String get argSyntax => '<version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<version>', 'Installed Flutter version to remove (omit when using --all)'),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('remove 3.19.0', 'Remove a specific version with confirmation'),
        HelpExample('remove 3.19.0 --force', 'Skip the confirmation prompt'),
        HelpExample('remove --all', 'Remove every installed version'),
        HelpExample('remove --all --force', 'Remove every version without prompting'),
      ];

  RemoveCommand() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Skip confirmation prompt.',
        negatable: false,
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: 'Remove every installed Flutter SDK version.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    final force = argResults!['force'] as bool;
    final all = argResults!['all'] as bool;
    final cache = CacheService();

    if (all) {
      await _removeAll(cache, force);
      return;
    }

    if (argResults!.rest.isEmpty) {
      usageException('Please provide a version number or --all.\n'
          'Example: fve remove 3.19.0');
    }

    await _removeSingle(argResults!.rest.first, cache, force);
  }

  // ── Single version ────────────────────────────────────────────────────────

  Future<void> _removeSingle(
    String version,
    CacheService cache,
    bool force,
  ) async {
    if (!cache.isInstalled(version)) {
      Logger.warning('Flutter $version is not installed — nothing to remove.');
      return;
    }

    // Guard against removing the active global version.
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion == version) {
      Logger.warning(
        'Flutter $version is the current global version.\n'
        'Unset it first: fve global --unlink\n'
        'Or set another: fve global <other-version>',
      );
      exit(1);
    }

    if (!force) {
      stdout.write('Remove Flutter $version? [y/N] ');
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input != 'y' && input != 'yes') {
        Logger.plain('Aborted.');
        return;
      }
    }

    Logger.plain('Removing Flutter $version…');
    cache.deleteVersion(version);
    Logger.success('Flutter $version removed.');
  }

  // ── All versions ──────────────────────────────────────────────────────────

  Future<void> _removeAll(CacheService cache, bool force) async {
    final versions = cache.installedVersions();

    if (versions.isEmpty) {
      Logger.warning('No Flutter versions installed — nothing to remove.');
      return;
    }

    Logger.plain('Installed versions to remove:');
    for (final v in versions) {
      Logger.plain('  • $v');
    }

    if (!force) {
      stdout.write('\nRemove all ${versions.length} version(s)? [y/N] ');
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input != 'y' && input != 'yes') {
        Logger.plain('Aborted.');
        return;
      }
    }

    // If the global version is among them, unlink it first.
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null && versions.contains(globalVersion)) {
      final link = Link(CacheService.currentLink);
      if (link.existsSync()) link.deleteSync();
      ConfigService().clearDefaultVersion();
    }

    for (final v in versions) {
      Logger.plain('  Removing $v…');
      cache.deleteVersion(v);
    }

    Logger.success('Removed ${versions.length} version(s).');
  }
}
