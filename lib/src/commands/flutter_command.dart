import 'dart:io';

import 'package:args/args.dart';

import '../help.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Runs `flutter <args>` using the project-pinned or global version.
class FlutterCommand extends FveCommand {
  @override
  String get name => 'flutter';

  @override
  String get description =>
      'Run flutter using the project-pinned version (from .fverc).';

  @override
  String get argSyntax => '[flutter-arguments...]';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('flutter run', 'Run the app on a connected device'),
        HelpExample('flutter build apk --release', 'Build a release APK'),
        HelpExample('flutter pub get', 'Fetch pub dependencies'),
        HelpExample('flutter --version', 'Print the pinned Flutter version'),
        HelpExample('exec -- flutter --help', "Show flutter's own help"),
      ];

  /// Use allowAnything so all flutter arguments pass through unparsed.
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<void> run() async {
    final flutterArgs = argResults!.rest;

    // Intercept --help / -h when it is the first argument.
    if (flutterArgs.isNotEmpty &&
        (flutterArgs.first == '--help' || flutterArgs.first == '-h')) {
      printUsage();
      return;
    }

    final binary = _resolveFlutterBinary();
    if (binary == null) return;

    final process = await Process.start(
      binary,
      flutterArgs,
      environment: {
        ...Platform.environment,
        // Prevent Flutter from running `git fetch` to check for SDK updates.
        // Version management is fve's responsibility; `flutter upgrade` must
        // not be used inside a version managed by fve.
        'FLUTTER_NO_VERSION_CHECK': '1',
      },
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    exit(exitCode);
  }

  String? _resolveFlutterBinary() {
    final cache = CacheService();

    // 1. Project version from .fverc.
    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final version = projectConfig.flutterVersion;
      if (!cache.isInstalled(version)) {
        Logger.error('Flutter $version (from .fverc) is not installed.');
        Logger.dim('Install it: fve install $version');
        return null;
      }
      return cache.flutterBin(version);
    }

    // 2. Global default.
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null) {
      return cache.flutterBin(globalVersion);
    }

    Logger.error('No Flutter version set.');
    Logger.dim('Set a project version: fve use <version>');
    Logger.dim('Set a global version:  fve global <version>');
    return null;
  }
}
