import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Runs an arbitrary command inside the Flutter version environment.
class ExecCommand extends FveCommand {
  @override
  String get name => 'exec';

  @override
  String get description =>
      'Run a command inside the Flutter version environment.';

  @override
  String get argSyntax => '-- <command> [arguments...]';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg(
          '-- <command>',
          'Command to run (everything after -- is forwarded verbatim)',
        ),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('exec -- pod install', 'Run pod install with the version environment set'),
        HelpExample('exec -- flutter --help', "Get flutter's native --help output"),
        HelpExample(
          'exec --version 3.19.0 -- flutter doctor',
          'Run with an explicit Flutter version override',
        ),
      ];

  ExecCommand() {
    argParser.addOption(
      'version',
      abbr: 'v',
      help: 'Override the Flutter version for this command.',
    );
  }

  @override
  Future<void> run() async {
    final args = argResults!.rest;
    if (args.isEmpty) {
      usageException('Please provide a command after --.\n'
          'Example: fve exec -- flutter run');
    }

    final version = _resolveVersion();
    if (version == null) return;

    final cache = CacheService();
    final versionBinDir = p.join(cache.versionDir(version), 'bin');

    // Prepend version's bin dir to PATH.
    final currentPath = Platform.environment['PATH'] ?? '';
    final newPath = '$versionBinDir${Platform.pathSeparator}$currentPath';

    final env = Map<String, String>.from(Platform.environment)
      ..['PATH'] = newPath
      ..['FVE_VERSION'] = version
      // Prevent Flutter from running `git fetch` to check for SDK updates.
      ..['FLUTTER_NO_VERSION_CHECK'] = '1';

    final command = args.first;
    final commandArgs = args.skip(1).toList();

    final process = await Process.start(
      command,
      commandArgs,
      environment: env,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    exit(exitCode);
  }

  String? _resolveVersion() {
    final explicit = argResults!['version'] as String?;
    if (explicit != null) {
      final cache = CacheService();
      if (!cache.isInstalled(explicit)) {
        Logger.error('Flutter $explicit is not installed.');
        Logger.dim('Install it: fve install $explicit');
        return null;
      }
      return explicit;
    }

    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final v = projectConfig.flutterVersion;
      final cache = CacheService();
      if (!cache.isInstalled(v)) {
        Logger.error('Flutter $v (from .fverc) is not installed.');
        Logger.dim('Install it: fve install $v');
        return null;
      }
      return v;
    }

    final globalVersion = CacheService().currentGlobalVersion();
    if (globalVersion != null) return globalVersion;

    Logger.error('No Flutter version set.');
    Logger.dim('Set a version: fve use <version>  or  fve global <version>');
    return null;
  }
}
