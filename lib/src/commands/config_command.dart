import 'dart:io';

import '../help.dart';
import '../services/cache_service.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class ConfigCommand extends FveCommand {
  @override
  String get name => 'config';

  @override
  String get description => 'View or update global fve configuration settings.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('config', 'Show all current settings'),
        HelpExample('config --no-vscode-integration', 'Disable auto VS Code settings update'),
        HelpExample('config --vscode-integration', 'Re-enable auto VS Code settings update'),
        HelpExample('config --no-auto-pub-get', 'Disable auto flutter pub get on fve use'),
        HelpExample('config --auto-pub-get', 'Re-enable auto flutter pub get on fve use'),
      ];

  ConfigCommand() {
    argParser
      ..addFlag(
        'vscode-integration',
        help: 'Auto-update .vscode/settings.json when running fve use.',
        defaultsTo: null,
      )
      ..addFlag(
        'auto-pub-get',
        help: 'Auto-run flutter pub get when running fve use.',
        defaultsTo: null,
      );
  }

  @override
  Future<void> run() async {
    final config = ConfigService();
    var didUpdate = false;

    final vsCode = argResults!['vscode-integration'] as bool?;
    if (vsCode != null) {
      config.setVsCodeIntegration(vsCode);
      Logger.success('vscode-integration = $vsCode');
      didUpdate = true;
    }

    final autoPubGet = argResults!['auto-pub-get'] as bool?;
    if (autoPubGet != null) {
      config.setAutoPubGet(autoPubGet);
      Logger.success('auto-pub-get = $autoPubGet');
      didUpdate = true;
    }

    if (!didUpdate) {
      _printAll(config);
    }
  }

  void _printAll(ConfigService config) {
    Logger.header('fve configuration');
    Logger.dim('  ${CacheService.globalConfigFile}');
    print('');

    _row('default-version',    config.getDefaultVersion() ?? '(none)');
    _row('vscode-integration', '${config.getVsCodeIntegration()}');
    _row('auto-pub-get',       '${config.getAutoPubGet()}');

    print('');
    Logger.dim('  Use fve config --[no-]<setting> to change a value.');
  }

  void _row(String key, String value) =>
      stdout.writeln('  ${key.padRight(22)}  $value');
}
