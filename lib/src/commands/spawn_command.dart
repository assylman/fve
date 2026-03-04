import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../help.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Runs a command with a specific installed Flutter version, bypassing the
/// current project's .fverc.
///
/// Unlike `fve exec --version`, the version is a positional argument rather
/// than a flag, making ad-hoc cross-version invocations more ergonomic.
class SpawnCommand extends FveCommand {
  @override
  String get name => 'spawn';

  @override
  String get description =>
      'Run a command with a specific Flutter version, ignoring the project .fverc.';

  @override
  String get argSyntax => '<version> <command> [arguments...]';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<version>', 'Installed Flutter version to use'),
        HelpArg('<command>', 'Command to run (flutter, dart, pod, or any binary)'),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('spawn 3.19.0 flutter doctor', 'Run flutter doctor with 3.19.0'),
        HelpExample('spawn stable flutter --version', 'Check the latest stable SDK version'),
        HelpExample('spawn 3.22.2 dart pub get', 'Run pub get with 3.22.2'),
        HelpExample('spawn 3.19.0 pod install', 'Run pod install with 3.19.0 environment'),
      ];

  /// Use allowAnything so that flags for the spawned command are not parsed
  /// by fve's own argument parser.
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<void> run() async {
    final rest = argResults!.rest;

    if (rest.isEmpty || rest.first == '--help' || rest.first == '-h') {
      printUsage();
      return;
    }

    final version = rest.first;
    final commandParts = rest.skip(1).toList();

    if (commandParts.isEmpty) {
      stderr.writeln(
        'Error: please provide a command to run after the version.\n'
        'Example: fve spawn $version flutter doctor',
      );
      exit(64);
    }

    final cache = CacheService();

    if (!cache.isInstalled(version)) {
      Logger.error('Flutter $version is not installed.');
      Logger.dim('Install it first: fve install $version');
      exit(1);
    }

    final versionBinDir = p.join(cache.versionDir(version), 'bin');
    final currentPath = Platform.environment['PATH'] ?? '';
    final newPath = '$versionBinDir${Platform.pathSeparator}$currentPath';

    final env = Map<String, String>.from(Platform.environment)
      ..['PATH'] = newPath
      ..['FVE_VERSION'] = version
      // Prevent Flutter from running `git fetch` to check for SDK updates.
      ..['FLUTTER_NO_VERSION_CHECK'] = '1';

    final process = await Process.start(
      commandParts.first,
      commandParts.skip(1).toList(),
      environment: env,
      mode: ProcessStartMode.inheritStdio,
    );

    exit(await process.exitCode);
  }
}
