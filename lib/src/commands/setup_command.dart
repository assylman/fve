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
      'Show the PATH line to add to your shell rc for fve-managed Flutter versions.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('setup', 'Show the PATH line to add to your shell rc'),
        HelpExample('setup --remove', 'Remove the fve PATH entry from your shell rc'),
      ];

  SetupCommand() {
    argParser.addFlag(
      'remove',
      abbr: 'r',
      help: 'Remove the fve PATH entry from your shell rc file.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final remove = argResults!['remove'] as bool;
    final shell = _detectShell();
    final rcFile = _rcFile(shell);
    final exportLine = _exportLine(shell);

    Logger.bold('\nfve shell setup');
    Logger.plain('');
    Logger.dim('  Shell   : $shell');
    Logger.dim('  RC file : $rcFile');
    Logger.plain('');

    if (remove) {
      _removeFromRc(rcFile);
      return;
    }

    if (_isAlreadyConfigured(rcFile)) {
      Logger.success('fve PATH is already present in $rcFile');
      return;
    }

    Logger.info('Add the following line to $rcFile:');
    Logger.plain('');
    Logger.plain('  $exportLine');
    Logger.plain('');
    Logger.dim('  Then restart your terminal.');
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

  bool _isAlreadyConfigured(String rcFile) {
    final file = File(rcFile);
    if (!file.existsSync()) return false;
    return file.readAsStringSync().contains('.fve/current/bin');
  }

  void _removeFromRc(String rcFile) {
    final file = File(rcFile);
    if (!file.existsSync()) {
      Logger.warning('RC file not found: $rcFile');
      return;
    }

    final original = file.readAsStringSync();
    final cleaned = original
        .replaceAll(
          RegExp(
            r'\n# fve — Flutter Version & Environment Manager\n[^\n]+\n',
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\n?export PATH="\$HOME/\.fve/current/bin:\$PATH"\n?'),
          '\n',
        )
        .replaceAll(
          RegExp(r'\n?fish_add_path \$HOME/\.fve/current/bin\n?'),
          '\n',
        );

    if (cleaned == original) {
      Logger.warning('No fve PATH entry found in $rcFile');
      return;
    }

    file.writeAsStringSync(cleaned);
    Logger.success('Removed fve PATH entry from $rcFile');
    Logger.plain('');
    Logger.dim('  Restart your terminal to apply.');
    Logger.dim('  Note: the current session PATH is unchanged — open a new terminal.');
  }
}
