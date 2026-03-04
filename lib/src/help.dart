import 'dart:io';

/// A positional argument entry shown in command help.
class HelpArg {
  final String syntax;
  final String description;
  const HelpArg(this.syntax, this.description);
}

/// A usage example shown in command help.
class HelpExample {
  final String command; // Without leading 'fve ', e.g. 'install 3.22.2'
  final String? comment; // Optional explanatory comment shown above the line
  const HelpExample(this.command, [this.comment]);
}

/// Renders styled help pages for fve.
class HelpFormatter {
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  static bool get _tty => stdout.hasTerminal && stdout.supportsAnsiEscapes;

  static String _b(String s) => _tty ? '$_bold$s$_reset' : s;
  static String _c(String s) => _tty ? '$_cyan$s$_reset' : s;
  static String _g(String s) => _tty ? '$_gray$s$_reset' : s;

  // ── Root help ─────────────────────────────────────────────────────────────

  static void printRoot() {
    _out('');
    _out('  ${_b("fve")}  Flutter Version & Environment Manager');
    _out('');
    _section('USAGE');
    _out('  fve <command> [arguments]');
    _out('');
    _section('VERSION MANAGEMENT');
    _row('install',  'Download and cache a Flutter SDK version');
    _row('use',      'Pin a version for the current project  (.fverc)');
    _row('global',   'Set the system-wide default Flutter version');
    _row('list',     'Browse available Flutter versions');
    _row('releases', 'Fetch the Flutter release list from the API');
    _row('remove',   'Remove a cached Flutter SDK version');
    _row('current',  'Show the active Flutter version');
    _out('');
    _section('RUNNING FLUTTER');
    _row('flutter', 'Run flutter with the project-pinned version');
    _row('dart',    'Run dart with the project-pinned version');
    _row('exec',    'Run any command inside the version environment');
    _row('spawn',   'Run a one-off command with any installed version');
    _out('');
    _section('TOOLING & DIAGNOSTICS');
    _row('doctor',  'Diagnose your fve environment');
    _row('config',  'View or update global fve settings');
    _row('api',     'JSON output for IDE and script integration');
    _row('destroy', 'Remove the entire fve cache');
    _out('');
    _out(_g('  Run ${_b("fve <command> --help")} for more information about a command.'));
    _out('');
  }

  // ── Sub-command help ──────────────────────────────────────────────────────

  static void printCommand({
    required String name,
    required String summary,
    String argSyntax = '',
    String optionsHelp = '',
    List<HelpArg> arguments = const [],
    Map<String, String> subcommands = const {},
    List<HelpExample> examples = const [],
  }) {
    final invocationParts = ['fve', name];
    if (argSyntax.isNotEmpty) invocationParts.add(argSyntax);
    if (optionsHelp.isNotEmpty) invocationParts.add('[options]');
    final invocation = invocationParts.join(' ');

    _out('');
    _out('  ${_b("fve $name")}  $summary');
    _out('');
    _section('USAGE');
    _out('  $invocation');
    _out('');

    if (arguments.isNotEmpty) {
      _section('ARGUMENTS');
      final width =
          arguments.fold(0, (m, a) => a.syntax.length > m ? a.syntax.length : m);
      for (final arg in arguments) {
        _out('  ${_c(arg.syntax.padRight(width + 2))}  ${arg.description}');
      }
      _out('');
    }

    if (optionsHelp.isNotEmpty) {
      _section('OPTIONS');
      for (final line in optionsHelp.split('\n')) {
        _out('  $line');
      }
      _out('');
    }

    if (subcommands.isNotEmpty) {
      _section('SUBCOMMANDS');
      final width =
          subcommands.keys.fold(0, (m, k) => k.length > m ? k.length : m);
      for (final entry in subcommands.entries) {
        _out('  ${entry.key.padRight(width + 2)}  ${entry.value}');
      }
      _out('');
    }

    if (examples.isNotEmpty) {
      _section('EXAMPLES');
      for (final ex in examples) {
        if (ex.comment != null) {
          _out('  ${_g("# ${ex.comment!}")}');
        }
        _out('  ${_b("fve")} ${ex.command}');
      }
      _out('');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static void _section(String title) => stdout.writeln(_b(title));
  static void _row(String name, String desc) =>
      stdout.writeln('  ${name.padRight(10)}  $desc');
  static void _out(String s) => stdout.writeln(s);
}
