import 'package:args/command_runner.dart';

import '../help.dart';

/// Base class for all fve commands with styled help output.
abstract class FveCommand extends Command<void> {
  /// Positional argument syntax, e.g. '<version>' or '[version]'.
  String get argSyntax => '';

  /// Positional arguments shown in the ARGUMENTS section.
  List<HelpArg> get helpArguments => const [];

  /// Usage examples shown in the EXAMPLES section.
  List<HelpExample> get usageExamples => const [];

  @override
  void printUsage() {
    final subs = subcommands.isEmpty
        ? const <String, String>{}
        : Map.fromEntries(
            subcommands.entries.map((e) => MapEntry(e.key, e.value.description)),
          );

    HelpFormatter.printCommand(
      name: name,
      summary: description.split('\n').first,
      argSyntax: argSyntax,
      optionsHelp: argParser.usage,
      arguments: helpArguments,
      subcommands: subs,
      examples: usageExamples,
    );
  }
}
