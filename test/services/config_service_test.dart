import 'dart:io';

import 'package:fve/src/services/cache_service.dart';
import 'package:fve/src/services/config_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  final config = ConfigService();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fve_config_');
    CacheService.fveHomeOverride = tmp.path;
  });

  tearDown(() {
    CacheService.fveHomeOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('defaults (no config file)', () {
    test('vscode-integration defaults to true', () {
      expect(config.getVsCodeIntegration(), isTrue);
    });

    test('auto-pub-get defaults to true', () {
      expect(config.getAutoPubGet(), isTrue);
    });

    test('auto-pod-install defaults to false (opt-in)', () {
      expect(config.getAutoPodInstall(), isFalse);
    });

    test('default-version is null', () {
      expect(config.getDefaultVersion(), isNull);
    });
  });

  group('auto-pod-install', () {
    test('persists when set true', () {
      config.setAutoPodInstall(true);
      expect(config.getAutoPodInstall(), isTrue);
    });

    test('can be turned back off', () {
      config.setAutoPodInstall(true);
      config.setAutoPodInstall(false);
      expect(config.getAutoPodInstall(), isFalse);
    });

    test('does not disturb other settings', () {
      config.setAutoPubGet(false);
      config.setAutoPodInstall(true);
      expect(config.getAutoPubGet(), isFalse);
      expect(config.getAutoPodInstall(), isTrue);
    });

    test('appears in readAll()', () {
      config.setAutoPodInstall(true);
      expect(config.readAll()['auto_pod_install'], isTrue);
    });
  });
}
