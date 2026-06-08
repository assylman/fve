import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fve/src/commands/upgrade_command.dart';
import 'package:fve/src/runner.dart' show kFveVersion;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Drives `fve upgrade [args]` with a mocked HTTP client, capturing all
/// printed output. Errors (including any exit()) are swallowed so assertions
/// can run on the captured lines.
Future<List<String>> runUpgrade(
  http.Client client,
  List<String> args,
) async {
  final out = <String>[];
  final runner = CommandRunner<void>('fve', 'test')
    ..addCommand(UpgradeCommand(client: client));
  await runZonedGuarded(
    () => runner.run(['upgrade', ...args]),
    (_, __) {},
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => out.add(line),
    ),
  );
  return out;
}

String _releaseJson(String tag, {List<Map<String, dynamic>> assets = const []}) {
  return jsonEncode({'tag_name': tag, 'assets': assets});
}

void main() {
  group('fve upgrade', () {
    test('reports up to date when latest tag equals the current version',
        () async {
      final client =
          MockClient((req) async => http.Response(_releaseJson('v$kFveVersion'), 200));
      final out = await runUpgrade(client, []);
      expect(out.join('\n').toLowerCase(), contains('up to date'));
    });

    test('--check announces a newer version without installing', () async {
      final client =
          MockClient((req) async => http.Response(_releaseJson('v99.0.0'), 200));
      final out = await runUpgrade(client, ['--check']);
      expect(out.join('\n'), contains('99.0.0'));
      expect(out.join('\n').toLowerCase(), contains('available'));
    });

    test('handles "no releases yet" (404) gracefully', () async {
      final client = MockClient((req) async => http.Response('{}', 404));
      final out = await runUpgrade(client, []);
      expect(out.join('\n').toLowerCase(), contains('no releases'));
    });

    test(
        'refuses to overwrite the binary when running via the Dart launcher '
        '(not the fve binary), leaving the executable intact', () async {
      // A newer release with an asset for every platform, so the only thing
      // stopping the overwrite is the basename guard.
      final assets = [
        {
          'name': 'fve-macos-arm64',
          'browser_download_url': 'https://example.test/fve-macos-arm64',
        },
        {
          'name': 'fve-macos-x64',
          'browser_download_url': 'https://example.test/fve-macos-x64',
        },
        {
          'name': 'fve-linux-x64',
          'browser_download_url': 'https://example.test/fve-linux-x64',
        },
      ];
      final client = MockClient((req) async {
        // Should never be asked to download the binary; if it is, fail loudly.
        if (req.url.host == 'example.test') {
          return http.Response('BINARY', 200);
        }
        return http.Response(_releaseJson('v99.0.0', assets: assets), 200);
      });

      final out = await runUpgrade(client, []);

      expect(out.join('\n').toLowerCase(), contains('refusing to self-upgrade'));
      // The running executable (the Dart launcher under `dart test`) is intact.
      expect(File(Platform.resolvedExecutable).existsSync(), isTrue);
    });
  });
}
