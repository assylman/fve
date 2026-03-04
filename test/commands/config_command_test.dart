import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Default display ───────────────────────────────────────────────────────

  group('fve config — display mode (no flags)', () {
    test('exits 0', () async {
      expect((await env.run(['config'])).exitCode, 0);
    });

    test('shows vscode-integration setting', () async {
      final r = await env.run(['config']);
      expect(r.output.toLowerCase(), contains('vscode'));
    });

    test('shows auto-pub-get setting', () async {
      final r = await env.run(['config']);
      expect(r.output.toLowerCase(), contains('pub'));
    });

    test('shows default-version (none initially)', () async {
      final r = await env.run(['config']);
      expect(r.output.toLowerCase(), contains('default'));
    });

    test('vscode-integration defaults to true', () async {
      final r = await env.run(['config']);
      expect(r.output, contains('true'));
    });

    test('auto-pub-get defaults to true', () async {
      final r = await env.run(['config']);
      expect(r.output, contains('true'));
    });
  });

  // ── VS Code integration toggle ────────────────────────────────────────────

  group('fve config --vscode-integration', () {
    test('--vscode-integration enables the setting', () async {
      final r = await env.run(['config', '--vscode-integration']);
      expect(r.exitCode, 0);
      expect(r.output, contains('true'));
    });

    test('--no-vscode-integration disables the setting', () async {
      final r = await env.run(['config', '--no-vscode-integration']);
      expect(r.exitCode, 0);
      expect(r.output, contains('false'));
    });

    test('disable then re-enable vscode-integration', () async {
      await env.run(['config', '--no-vscode-integration']);
      final r = await env.run(['config', '--vscode-integration']);
      expect(r.exitCode, 0);
      // Config display after re-enabling should show true.
      final display = await env.run(['config']);
      expect(display.output, contains('true'));
    });

    test('persists vscode-integration = false in config.json', () async {
      await env.run(['config', '--no-vscode-integration']);
      final config = env.readConfig();
      expect(config['vscode_integration'], isFalse);
    });

    test('persists vscode-integration = true in config.json', () async {
      await env.run(['config', '--no-vscode-integration']);
      await env.run(['config', '--vscode-integration']);
      final config = env.readConfig();
      expect(config['vscode_integration'], isTrue);
    });
  });

  // ── Auto pub get toggle ───────────────────────────────────────────────────

  group('fve config --auto-pub-get', () {
    test('--auto-pub-get enables the setting', () async {
      final r = await env.run(['config', '--auto-pub-get']);
      expect(r.exitCode, 0);
      expect(r.output, contains('true'));
    });

    test('--no-auto-pub-get disables the setting', () async {
      final r = await env.run(['config', '--no-auto-pub-get']);
      expect(r.exitCode, 0);
      expect(r.output, contains('false'));
    });

    test('persists auto_pub_get = false in config.json', () async {
      await env.run(['config', '--no-auto-pub-get']);
      final config = env.readConfig();
      expect(config['auto_pub_get'], isFalse);
    });

    test('persists auto_pub_get = true in config.json', () async {
      await env.run(['config', '--no-auto-pub-get']);
      await env.run(['config', '--auto-pub-get']);
      final config = env.readConfig();
      expect(config['auto_pub_get'], isTrue);
    });
  });

  // ── Setting multiple flags at once ────────────────────────────────────────

  group('fve config — multiple flags', () {
    test('can set both flags in one invocation', () async {
      final r = await env.run([
        'config',
        '--no-vscode-integration',
        '--no-auto-pub-get',
      ]);
      expect(r.exitCode, 0);
      final config = env.readConfig();
      expect(config['vscode_integration'], isFalse);
      expect(config['auto_pub_get'], isFalse);
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve config --help', () {
    test('exits 0', () async {
      expect((await env.run(['config', '--help'])).exitCode, 0);
    });
  });
}
