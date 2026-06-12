import 'dart:io';

import 'package:args/command_runner.dart';

import 'utils/logger.dart';

import 'commands/api_command.dart';
import 'commands/clean_command.dart';
import 'commands/pod_command.dart';
import 'commands/config_command.dart';
import 'commands/current_command.dart';
import 'commands/dart_command.dart';
import 'commands/destroy_command.dart';
import 'commands/doctor_command.dart';
import 'commands/exec_command.dart';
import 'commands/flutter_command.dart';
import 'commands/global_command.dart';
import 'commands/install_command.dart';
import 'commands/list_command.dart';
import 'commands/releases_command.dart';
import 'commands/remove_command.dart';
import 'commands/setup_command.dart';
import 'commands/migrate_command.dart';
import 'commands/snapshots_command.dart';
import 'commands/spawn_command.dart';
import 'commands/uninstall_command.dart';
import 'commands/upgrade_command.dart';
import 'commands/use_command.dart';
import 'help.dart';

const kFveVersion = '0.2.1';

class FveRunner {
  Future<void> run(List<String> args) async {
    // Intercept --version / -V before CommandRunner parses global flags,
    // because CommandRunner does not register --version by default.
    if (args.length == 1 &&
        (args[0] == '--version' || args[0] == '-V')) {
      Logger.plain('fve $kFveVersion');
      return;
    }

    // Apply global flags early so Logger is configured before any command runs.
    if (args.contains('--quiet') || args.contains('-q')) Logger.quiet = true;
    if (args.contains('--verbose') || args.contains('-v')) Logger.verbose = true;

    // 8.7 — CI non-interactive auto-detection.
    if (Logger.isCI) {
      Logger.debug('CI environment detected — running in non-interactive mode.');
    }

    final runner = _FveCommandRunner()
      ..addCommand(ReleasesCommand())
      ..addCommand(InstallCommand())
      ..addCommand(UseCommand())
      ..addCommand(GlobalCommand())
      ..addCommand(ListCommand())
      ..addCommand(RemoveCommand())
      ..addCommand(CurrentCommand())
      ..addCommand(FlutterCommand())
      ..addCommand(DartCommand())
      ..addCommand(ExecCommand())
      ..addCommand(SpawnCommand())
      ..addCommand(PodCommand())
      ..addCommand(CleanCommand())
      ..addCommand(ConfigCommand())
      ..addCommand(DestroyCommand())
      ..addCommand(ApiCommand())
      ..addCommand(SetupCommand())
      ..addCommand(MigrateCommand())
      ..addCommand(SnapshotsCommand())
      ..addCommand(UpgradeCommand())
      ..addCommand(UninstallCommand())
      ..addCommand(DoctorCommand());

    try {
      await runner.run(args);
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      exit(64);
    }
  }
}

class _FveCommandRunner extends CommandRunner<void> {
  _FveCommandRunner()
      : super(
          'fve',
          'Flutter Version & Environment Manager',
        );

  @override
  void printUsage() => HelpFormatter.printRoot();

  @override
  Future<void> run(Iterable<String> args) async {
    try {
      return await super.run(args);
    } on UsageException catch (e) {
      // 6.4 — "Did you mean...?" suggestion for unknown commands.
      final msg = e.message;
      final unknownMatch = RegExp(r'Could not find a command named "([^"]+)"').firstMatch(msg);
      if (unknownMatch != null) {
        final unknown = unknownMatch.group(1)!;
        final suggestion = _suggest(unknown, commands.keys.toList());
        if (suggestion != null) {
          stderr.writeln(msg);
          stderr.writeln('Did you mean "$suggestion"?');
        } else {
          stderr.writeln(msg);
        }
        exit(64);
      }
      rethrow;
    }
  }

  /// Returns the closest command name to [input] by edit distance, or null
  /// if no good match exists.
  static String? _suggest(String input, List<String> candidates) {
    String? best;
    var bestDist = 3; // require at least one character in common
    for (final c in candidates) {
      final d = _editDistance(input.toLowerCase(), c.toLowerCase());
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) { dp[i][0] = i; }
    for (var j = 0; j <= n; j++) { dp[0][j] = j; }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                  .reduce((a, b) => a < b ? a : b);
        }
      }
    }
    return dp[m][n];
  }
}
