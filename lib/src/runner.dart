import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/api_command.dart';
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
import 'commands/spawn_command.dart';
import 'commands/use_command.dart';
import 'help.dart';

const kFveVersion = '0.1.0';

class FveRunner {
  Future<void> run(List<String> args) async {
    // Intercept --version / -V before CommandRunner parses global flags,
    // because CommandRunner does not register --version by default.
    if (args.length == 1 &&
        (args[0] == '--version' || args[0] == '-V')) {
      print('fve $kFveVersion');
      return;
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
      ..addCommand(ConfigCommand())
      ..addCommand(DestroyCommand())
      ..addCommand(ApiCommand())
      ..addCommand(SetupCommand())
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
}
