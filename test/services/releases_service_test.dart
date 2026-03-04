import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fve/src/models/flutter_release.dart';
import 'package:fve/src/services/releases_service.dart';
import 'package:test/test.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

const _baseUrl =
    'https://storage.googleapis.com/flutter_infra_release/releases';

Map<String, dynamic> _release({
  String hash = 'stablehash',
  String channel = 'stable',
  String version = '3.22.2',
  String arch = 'x64',
}) =>
    {
      'hash': hash,
      'channel': channel,
      'version': version,
      'dart_sdk_version': '3.4.4',
      'dart_sdk_arch': arch,
      'release_date': '2024-06-12T15:00:00.000Z',
      'archive': '$channel/macos/flutter_macos_$version-$channel.zip',
      'sha256': 'sha256of$version',
    };

Map<String, dynamic> _apiResponse({
  required List<Map<String, dynamic>> releases,
  String stableHash = 'stablehash',
  String betaHash = 'betahash',
}) =>
    {
      'base_url': _baseUrl,
      'current_release': {
        'stable': stableHash,
        'beta': betaHash,
        'dev': 'devhash',
      },
      'releases': releases,
    };

http.Client _mockClient(Map<String, dynamic> responseBody, {int status = 200}) =>
    MockClient((_) async => http.Response(jsonEncode(responseBody), status));

http.Client _errorClient(int statusCode) =>
    MockClient((_) async => http.Response('error', statusCode));

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('ReleasesService.fetchReleases', () {
    test('parses a well-formed API response', () async {
      final client = _mockClient(
        _apiResponse(releases: [_release()]),
      );
      final service = ReleasesService(client: client);

      final resp = await service.fetchReleases();

      expect(resp.baseUrl, _baseUrl);
      expect(resp.releases, hasLength(1));
      expect(resp.releases.first.version, '3.22.2');
    });

    test('throws when the server returns a non-200 status', () async {
      final service = ReleasesService(client: _errorClient(503));
      expect(service.fetchReleases(), throwsException);
    });

    test('throws when the server returns a 404', () async {
      final service = ReleasesService(client: _errorClient(404));
      expect(service.fetchReleases(), throwsException);
    });
  });

  group('ReleasesService.findRelease — by exact version', () {
    late ReleasesService service;

    setUp(() {
      final body = _apiResponse(releases: [
        _release(hash: 'h1', version: '3.22.2', arch: 'x64'),
        _release(hash: 'h1', version: '3.22.2', arch: 'arm64'),
        _release(hash: 'h2', version: '3.19.0', arch: 'x64'),
      ]);
      service = ReleasesService(client: _mockClient(body));
    });

    test('returns a release matching the requested version', () async {
      final release = await service.findRelease('3.22.2');
      expect(release, isNotNull);
      expect(release!.version, '3.22.2');
    });

    test('returns a release matching an older version', () async {
      final release = await service.findRelease('3.19.0');
      expect(release, isNotNull);
      expect(release!.version, '3.19.0');
    });

    test('returns null for a version that does not exist in the feed', () async {
      final release = await service.findRelease('99.99.99');
      expect(release, isNull);
    });
  });

  group('ReleasesService.findRelease — by channel name', () {
    test('resolves "stable" to the release with the stable hash', () async {
      final body = _apiResponse(
        stableHash: 'h-stable',
        releases: [
          _release(hash: 'h-stable', channel: 'stable', version: '3.22.2'),
          _release(hash: 'h-beta', channel: 'beta', version: '3.23.0-0.1.pre'),
        ],
      );
      final service = ReleasesService(client: _mockClient(body));

      final release = await service.findRelease('stable');

      expect(release, isNotNull);
      expect(release!.channel, 'stable');
      expect(release.version, '3.22.2');
    });

    test('resolves "beta" to the release with the beta hash', () async {
      final body = _apiResponse(
        betaHash: 'h-beta',
        releases: [
          _release(hash: 'h-stable', channel: 'stable', version: '3.22.2'),
          _release(hash: 'h-beta', channel: 'beta', version: '3.23.0-0.1.pre'),
        ],
      );
      final service = ReleasesService(client: _mockClient(body));

      final release = await service.findRelease('beta');

      expect(release, isNotNull);
      expect(release!.channel, 'beta');
    });

    test('returns null when the channel hash maps to no release', () async {
      // stable hash points to a hash not present in the releases list.
      final body = _apiResponse(
        stableHash: 'missing-hash',
        releases: [_release(hash: 'other-hash', version: '3.22.2')],
      );
      final service = ReleasesService(client: _mockClient(body));

      final release = await service.findRelease('stable');
      expect(release, isNull);
    });
  });

  group('ReleasesService channel detection', () {
    // We test the _isChannel logic indirectly: channel strings should trigger
    // hash-based lookup, while non-channel strings trigger version matching.

    test('"stable" is treated as a channel name', () async {
      // If "stable" were treated as a version string, it would find nothing
      // (no release has version == "stable"). By returning a release, we
      // confirm the channel path was taken.
      final body = _apiResponse(
        stableHash: 'h',
        releases: [_release(hash: 'h', channel: 'stable', version: '3.22.2')],
      );
      final service = ReleasesService(client: _mockClient(body));
      final result = await service.findRelease('stable');
      expect(result, isNotNull);
    });

    test('"beta" is treated as a channel name', () async {
      final body = _apiResponse(
        betaHash: 'h',
        releases: [_release(hash: 'h', channel: 'beta', version: '3.23.0-pre')],
      );
      final service = ReleasesService(client: _mockClient(body));
      final result = await service.findRelease('beta');
      expect(result, isNotNull);
    });

    test('an exact version string is not treated as a channel', () async {
      // "3.22.2" must match by version field, not hash lookup.
      final body = _apiResponse(
        stableHash: 'different-hash',
        releases: [_release(hash: 'version-hash', version: '3.22.2')],
      );
      final service = ReleasesService(client: _mockClient(body));
      final result = await service.findRelease('3.22.2');
      // Should find it via version match, not via hash lookup.
      expect(result, isNotNull);
      expect(result!.version, '3.22.2');
    });
  });

  group('ReleasesService — multiple architecture candidates', () {
    test('returns a release when both x64 and arm64 are available', () async {
      final body = _apiResponse(releases: [
        _release(hash: 'h', version: '3.22.2', arch: 'x64'),
        _release(hash: 'h', version: '3.22.2', arch: 'arm64'),
      ]);
      final service = ReleasesService(client: _mockClient(body));

      final result = await service.findRelease('3.22.2');
      expect(result, isNotNull);
      expect(result!.version, '3.22.2');
    });
  });
}
