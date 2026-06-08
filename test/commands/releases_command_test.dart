import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/fve_process.dart';

/// A minimal but valid Flutter releases manifest, served locally so the
/// `releases` command never touches the live Google endpoint (deterministic,
/// fast, offline-safe). Includes both arm64 and x64 entries so it resolves on
/// any host architecture.
Map<String, dynamic> _fixture() {
  Map<String, dynamic> rel(String hash, String channel, String version,
          String arch, String date) =>
      {
        'hash': hash,
        'channel': channel,
        'version': version,
        'dart_sdk_version': '3.4.0',
        'dart_sdk_arch': arch,
        'release_date': date,
        'archive': '$channel/macos/flutter_${arch}_$version-$channel.zip',
        'sha256': 'deadbeef',
      };

  return {
    'base_url':
        'https://storage.googleapis.com/flutter_infra_release/releases',
    'current_release': {'stable': 'hs', 'beta': 'hb', 'dev': 'hd'},
    'releases': [
      rel('hs', 'stable', '3.22.2', 'arm64', '2024-06-06T00:00:00.000Z'),
      rel('hs', 'stable', '3.22.2', 'x64', '2024-06-06T00:00:00.000Z'),
      rel('hb', 'beta', '3.23.0-0.1.pre', 'arm64', '2024-05-01T00:00:00.000Z'),
      rel('hb', 'beta', '3.23.0-0.1.pre', 'x64', '2024-05-01T00:00:00.000Z'),
      rel('hd', 'dev', '3.24.0-0.1.pre', 'arm64', '2024-04-01T00:00:00.000Z'),
      rel('hd', 'dev', '3.24.0-0.1.pre', 'x64', '2024-04-01T00:00:00.000Z'),
    ],
  };
}

void main() {
  late FveTestEnv env;
  late HttpServer server;
  late String releasesUrl;

  setUp(() async {
    env = FveTestEnv.create();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    releasesUrl = 'http://127.0.0.1:${server.port}/releases.json';
    final body = jsonEncode(_fixture());
    server.listen((req) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(body);
      req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    env.dispose();
  });

  /// Runs `fve releases [args]` pointed at the local fixture server.
  Future<FveResult> runReleases(List<String> args) =>
      env.run(['releases', ...args], extraEnv: {'FVE_RELEASES_URL': releasesUrl});

  group('fve releases — argument parsing', () {
    test('--help exits 0', () async {
      expect((await env.run(['releases', '--help'])).exitCode, 0);
    });

    test('lists releases (exit 0) against the fixture', () async {
      final r = await runReleases([]);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.22.2'));
    });

    test('--channel stable is the default', () async {
      final r = await runReleases(['--channel', 'stable']);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.22.2'));
    });

    test('--channel beta lists beta releases', () async {
      final r = await runReleases(['--channel', 'beta']);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.23.0'));
    });

    test('--channel dev lists dev releases', () async {
      final r = await runReleases(['--channel', 'dev']);
      expect(r.exitCode, 0);
      expect(r.output, contains('3.24.0'));
    });

    test('-c is an alias for --channel', () async {
      final r = await runReleases(['-c', 'stable']);
      expect(r.exitCode, 0);
    });

    test('--page-size is accepted', () async {
      final r = await runReleases(['--page-size', '5']);
      expect(r.exitCode, 0);
    });

    test('-n is an alias for --page-size', () async {
      final r = await runReleases(['-n', '5']);
      expect(r.exitCode, 0);
    });

    test('invalid --channel value exits with an error', () async {
      final r = await runReleases(['--channel', 'nonexistent']);
      expect(r.exitCode, isNot(0));
    });
  });

  group('fve releases — error handling', () {
    test('prints a human-readable error when the endpoint is unreachable',
        () async {
      // Point at a dead local port — fast, deterministic connection failure.
      final r = await env.run(['releases'],
          extraEnv: {'FVE_RELEASES_URL': 'http://127.0.0.1:1/releases.json'});
      expect(r.exitCode, isNot(0));
      expect(r.output.toLowerCase(),
          anyOf(contains('releases'), contains('network'), contains('failed')));
    });
  });
}
