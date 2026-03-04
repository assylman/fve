import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class SetupCommand extends FveCommand {
  @override
  String get name => 'setup';

  @override
  String get description =>
      'Configure your shell to use fve-managed Flutter versions.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('setup', 'Show the line to add to your shell rc'),
        HelpExample('setup --write', 'Auto-append the PATH export to your shell rc'),
      ];

  SetupCommand() {
    argParser.addFlag(
      'write',
      abbr: 'w',
      help: 'Append the PATH export to your shell rc file automatically.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final write = argResults!['write'] as bool;
    final shell = _detectShell();
    final rcFile = _rcFile(shell);
    final exportLine = _exportLine(shell);
    final alreadyConfigured = _isAlreadyConfigured(rcFile, shell);

    Logger.bold('\nfve shell setup');
    print('');
    Logger.dim('  Shell   : $shell');
    Logger.dim('  RC file : $rcFile');
    print('');

    if (alreadyConfigured) {
      Logger.success('fve is already configured in $rcFile');
      Logger.dim('  Restart your shell or run: source $rcFile');
      return;
    }

    if (write) {
      _writeToRc(rcFile, exportLine, shell);
      Logger.success('Written to $rcFile');
      print('');
      Logger.dim('  Restart your shell or run:');
      Logger.dim('    source $rcFile');
    } else {
      Logger.info('Add the following to $rcFile:');
      print('');
      print('  $exportLine');
      print('');
      Logger.dim('  Then restart your shell or run: source $rcFile');
      print('');
      Logger.dim('  Or run automatically: fve setup --write');
    }
  }

  // ── Shell detection ────────────────────────────────────────────────────────

  String _detectShell() {
    final shellEnv = Platform.environment['SHELL'] ?? '';
    if (shellEnv.contains('zsh')) return 'zsh';
    if (shellEnv.contains('bash')) return 'bash';
    if (shellEnv.contains('fish')) return 'fish';
    return 'sh';
  }

  String _rcFile(String shell) {
    final home = Platform.environment['HOME'] ?? '~';
    return switch (shell) {
      'zsh' => p.join(home, '.zshrc'),
      'bash' => p.join(home, '.bashrc'),
      'fish' => p.join(home, '.config', 'fish', 'config.fish'),
      _ => p.join(home, '.profile'),
    };
  }

  String _exportLine(String shell) {
    if (shell == 'fish') {
      return 'fish_add_path \$HOME/.fve/current/bin';
    }
    return 'export PATH="\$HOME/.fve/current/bin:\$PATH"';
  }

  bool _isAlreadyConfigured(String rcFile, String shell) {
    final file = File(rcFile);
    if (!file.existsSync()) return false;
    final content = file.readAsStringSync();
    return shell == 'fish'
        ? content.contains('.fve/current/bin')
        : content.contains('.fve/current/bin');
  }

  void _writeToRc(String rcFile, String exportLine, String shell) {
    final file = File(rcFile);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    final block = '\n# fve — Flutter Version & Environment Manager\n'
        '$exportLine\n';

    file.writeAsStringSync(block, mode: FileMode.append);
  }
}
