import 'dart:io';

import 'package:args/args.dart';

import '../help.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Runs `dart <args>` using the project-pinned or global version.
class DartCommand extends FveCommand {
  @override
  String get name => 'dart';

  @override
  String get description =>
      'Run dart using the project-pinned version (from .fverc).';

  @override
  String get argSyntax => '[dart-arguments...]';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('dart pub get', 'Fetch pub dependencies'),
        HelpExample('dart run bin/main.dart', 'Run a Dart script'),
        HelpExample('dart compile exe bin/main.dart', 'Compile to a native executable'),
        HelpExample('exec -- dart --help', "Show dart's own help text"),
      ];

  /// Use allowAnything so all dart arguments pass through unparsed.
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<void> run() async {
    final dartArgs = argResults!.rest;

    // Intercept --help / -h when it is the first argument.
    if (dartArgs.isNotEmpty &&
        (dartArgs.first == '--help' || dartArgs.first == '-h')) {
      printUsage();
      return;
    }

    final binary = _resolveDartBinary();
    if (binary == null) return;

    final process = await Process.start(
      binary,
      dartArgs,
      environment: {
        ...Platform.environment,
        // Prevent Flutter from running `git fetch` to check for SDK updates.
        'FLUTTER_NO_VERSION_CHECK': '1',
      },
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    exit(exitCode);
  }

  String? _resolveDartBinary() {
    final cache = CacheService();

    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final version = projectConfig.flutterVersion;
      if (!cache.isInstalled(version)) {
        Logger.error('Flutter $version (from .fverc) is not installed.');
        Logger.dim('Install it: fve install $version');
        return null;
      }
      return cache.dartBin(version);
    }

    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null) {
      return cache.dartBin(globalVersion);
    }

    Logger.error('No Flutter version set.');
    Logger.dim('Set a project version: fve use <version>');
    return null;
  }
}
