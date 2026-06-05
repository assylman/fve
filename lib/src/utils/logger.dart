// ignore_for_file: avoid_print
import 'dart:io';

/// ANSI color codes for terminal output.
class Logger {
  /// When true, only error messages are printed (6.7 --quiet).
  static bool quiet = false;

  /// When true, verbose/debug messages are printed (6.6 --verbose).
  static bool verbose = false;

  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _red = '\x1B[31m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  /// True when running in a CI environment (no interactive prompts).
  static bool get isCI =>
      Platform.environment['CI'] == 'true' ||
      Platform.environment['CI'] == '1' ||
      Platform.environment.containsKey('GITHUB_ACTIONS') ||
      Platform.environment.containsKey('GITLAB_CI') ||
      Platform.environment.containsKey('CIRCLECI') ||
      Platform.environment.containsKey('JENKINS_URL') ||
      Platform.environment.containsKey('TRAVIS');

  static bool get _supportsColor =>
      stdout.hasTerminal &&
      stdout.supportsAnsiEscapes &&
      Platform.environment['NO_COLOR'] == null &&
      Platform.environment['TERM'] != 'dumb';

  static String _color(String text, String code) =>
      _supportsColor ? '$code$text$_reset' : text;

  static void info(String message) {
    if (!quiet) print(_color(message, _cyan));
  }

  static void success(String message) {
    if (!quiet) print(_color('✓ $message', _green));
  }

  static void warning(String message) =>
      print(_color('⚠ $message', _yellow));

  static void error(String message) =>
      print(_color('✗ $message', _red));

  static void bold(String message) {
    if (!quiet) print(_color(message, _bold));
  }

  static void dim(String message) {
    if (!quiet) print(_color(message, _gray));
  }

  static void plain(String message) {
    if (!quiet) print(message);
  }

  static void debug(String message) {
    if (verbose) print(_color('[debug] $message', _gray));
  }

  /// Prints a section header.
  static void header(String title) {
    print('');
    print(_color('  $title', _bold));
    print(_color('  ${'─' * title.length}', _gray));
  }

  /// Overwrites the current line (for progress updates).
  static void progress(String message) {
    if (_supportsColor) {
      stdout.write('\r\x1B[K$message');
    } else {
      print(message);
    }
  }

  /// Ends a progress line with a newline.
  static void progressDone() {
    if (_supportsColor) stdout.writeln();
  }
}
