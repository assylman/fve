import 'dart:convert';
import 'dart:io';

import 'cache_service.dart';

/// Manages the global fve configuration stored at `~/.fve/config.json`.
class ConfigService {
  static Map<String, dynamic> _read() {
    final file = File(CacheService.globalConfigFile);
    if (!file.existsSync()) return {};
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static void _write(Map<String, dynamic> data) {
    final file = File(CacheService.globalConfigFile);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  // ── Default version ───────────────────────────────────────────────────────

  String? getDefaultVersion() => _read()['default_version'] as String?;

  void setDefaultVersion(String version) {
    final data = _read();
    data['default_version'] = version;
    _write(data);
  }

  void clearDefaultVersion() {
    final data = _read();
    data.remove('default_version');
    _write(data);
  }

  // ── VS Code integration ───────────────────────────────────────────────────

  /// Whether `fve use` automatically updates `.vscode/settings.json`.
  /// Defaults to true.
  bool getVsCodeIntegration() =>
      _read()['vscode_integration'] as bool? ?? true;

  void setVsCodeIntegration(bool value) {
    final data = _read();
    data['vscode_integration'] = value;
    _write(data);
  }

  // ── Auto pub get ──────────────────────────────────────────────────────────

  /// Whether `fve use` automatically runs `flutter pub get` when a
  /// `pubspec.yaml` is present in the current directory.
  /// Defaults to true.
  bool getAutoPubGet() => _read()['auto_pub_get'] as bool? ?? true;

  void setAutoPubGet(bool value) {
    final data = _read();
    data['auto_pub_get'] = value;
    _write(data);
  }

  // ── Raw access (for fve api context) ─────────────────────────────────────

  Map<String, dynamic> readAll() => _read();
}
