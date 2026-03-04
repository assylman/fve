import 'dart:io';

/// ANSI color codes for terminal output.
class Logger {
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _red = '\x1B[31m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  static bool get _supportsColor =>
      stdout.hasTerminal && stdout.supportsAnsiEscapes;

  static String _color(String text, String code) =>
      _supportsColor ? '$code$text$_reset' : text;

  static void info(String message) => print(_color(message, _cyan));

  static void success(String message) =>
      print(_color('✓ $message', _green));

  static void warning(String message) =>
      print(_color('⚠ $message', _yellow));

  static void error(String message) =>
      print(_color('✗ $message', _red));

  static void bold(String message) => print(_color(message, _bold));

  static void dim(String message) => print(_color(message, _gray));

  static void plain(String message) => print(message);

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
