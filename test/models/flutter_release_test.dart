import 'package:fve/src/models/flutter_release.dart';
import 'package:test/test.dart';

void main() {
  // ── Fixtures ──────────────────────────────────────────────────────────────

  const baseUrl =
      'https://storage.googleapis.com/flutter_infra_release/releases';

  Map<String, dynamic> releaseJson({
    String hash = 'abc123',
    String channel = 'stable',
    String version = '3.22.2',
    String dartSdkVersion = '3.4.4',
    String dartSdkArch = 'x64',
    String releaseDate = '2024-06-12T15:00:00.000Z',
    String archive = 'stable/macos/flutter_macos_3.22.2-stable.zip',
    String sha256 = 'deadbeef',
  }) =>
      {
        'hash': hash,
        'channel': channel,
        'version': version,
        'dart_sdk_version': dartSdkVersion,
        'dart_sdk_arch': dartSdkArch,
        'release_date': releaseDate,
        'archive': archive,
        'sha256': sha256,
      };

  Map<String, dynamic> responsejson({
    List<Map<String, dynamic>> releases = const [],
    Map<String, String> currentRelease = const {
      'stable': 'stablehash',
      'beta': 'betahash',
      'dev': 'devhash',
    },
  }) =>
      {
        'base_url': baseUrl,
        'current_release': currentRelease,
        'releases': releases,
      };

  // ── FlutterRelease ────────────────────────────────────────────────────────

  group('FlutterRelease.fromJson', () {
    test('parses all required fields', () {
      final r = FlutterRelease.fromJson(releaseJson());

      expect(r.hash, 'abc123');
      expect(r.channel, 'stable');
      expect(r.version, '3.22.2');
      expect(r.dartSdkVersion, '3.4.4');
      expect(r.dartSdkArch, 'x64');
      expect(r.archive, 'stable/macos/flutter_macos_3.22.2-stable.zip');
      expect(r.sha256, 'deadbeef');
      expect(r.releaseDate, DateTime.utc(2024, 6, 12, 15));
    });

    test('defaults dartSdkArch to "x64" when field is absent', () {
      final json = releaseJson()..remove('dart_sdk_arch');
      expect(FlutterRelease.fromJson(json).dartSdkArch, 'x64');
    });

    test('defaults sha256 to empty string when field is absent', () {
      final json = releaseJson()..remove('sha256');
      expect(FlutterRelease.fromJson(json).sha256, '');
    });

    test('defaults dartSdkVersion to empty string when field is absent', () {
      final json = releaseJson()..remove('dart_sdk_version');
      expect(FlutterRelease.fromJson(json).dartSdkVersion, '');
    });
  });

  group('FlutterRelease.isArm64', () {
    test('returns true when dartSdkArch is "arm64"', () {
      final r = FlutterRelease.fromJson(releaseJson(dartSdkArch: 'arm64'));
      expect(r.isArm64, isTrue);
    });

    test('returns false when dartSdkArch is "x64"', () {
      final r = FlutterRelease.fromJson(releaseJson(dartSdkArch: 'x64'));
      expect(r.isArm64, isFalse);
    });
  });

  group('FlutterRelease.downloadUrl', () {
    test('concatenates baseUrl and archive path with a slash', () {
      final r = FlutterRelease.fromJson(releaseJson(
        archive: 'stable/macos/flutter_macos_3.22.2-stable.zip',
      ));
      expect(
        r.downloadUrl(baseUrl),
        '$baseUrl/stable/macos/flutter_macos_3.22.2-stable.zip',
      );
    });

    test('works correctly when baseUrl has no trailing slash', () {
      final r = FlutterRelease.fromJson(releaseJson(archive: 'path/to.zip'));
      final url = r.downloadUrl('https://example.com');
      expect(url, 'https://example.com/path/to.zip');
    });
  });

  group('FlutterRelease.displayVersion', () {
    test('omits channel suffix for stable releases', () {
      final r = FlutterRelease.fromJson(releaseJson(channel: 'stable'));
      expect(r.displayVersion, '3.22.2');
    });

    test('appends "(beta)" for beta channel', () {
      final r = FlutterRelease.fromJson(releaseJson(channel: 'beta'));
      expect(r.displayVersion, '3.22.2 (beta)');
    });

    test('appends "(dev)" for dev channel', () {
      final r = FlutterRelease.fromJson(releaseJson(channel: 'dev'));
      expect(r.displayVersion, '3.22.2 (dev)');
    });

    test('appends "(master)" for master channel', () {
      final r = FlutterRelease.fromJson(releaseJson(channel: 'master'));
      expect(r.displayVersion, '3.22.2 (master)');
    });
  });

  group('FlutterRelease.toString', () {
    test('includes version, channel, and arch', () {
      final r = FlutterRelease.fromJson(releaseJson());
      expect(r.toString(), 'FlutterRelease(3.22.2, stable, x64)');
    });
  });

  // ── FlutterReleasesResponse ───────────────────────────────────────────────

  group('FlutterReleasesResponse.fromJson', () {
    test('parses baseUrl', () {
      final resp = FlutterReleasesResponse.fromJson(responsejson());
      expect(resp.baseUrl, baseUrl);
    });

    test('parses currentRelease map', () {
      final resp = FlutterReleasesResponse.fromJson(responsejson());
      expect(resp.currentRelease['stable'], 'stablehash');
      expect(resp.currentRelease['beta'], 'betahash');
      expect(resp.currentRelease['dev'], 'devhash');
    });

    test('parses releases list', () {
      final resp = FlutterReleasesResponse.fromJson(
        responsejson(releases: [releaseJson()]),
      );
      expect(resp.releases, hasLength(1));
      expect(resp.releases.first.version, '3.22.2');
    });

    test('parses empty releases list', () {
      final resp = FlutterReleasesResponse.fromJson(responsejson());
      expect(resp.releases, isEmpty);
    });
  });

  group('FlutterReleasesResponse.latestHashForChannel', () {
    late FlutterReleasesResponse resp;

    setUp(() => resp = FlutterReleasesResponse.fromJson(responsejson()));

    test('returns the hash for a known channel', () {
      expect(resp.latestHashForChannel('stable'), 'stablehash');
    });

    test('returns null for an unknown channel', () {
      expect(resp.latestHashForChannel('canary'), isNull);
    });

    test('returns different hashes for different channels', () {
      expect(
        resp.latestHashForChannel('stable'),
        isNot(resp.latestHashForChannel('beta')),
      );
    });
  });

  // ── selectBestRelease ─────────────────────────────────────────────────────

  group('selectBestRelease', () {
    FlutterRelease makeRelease(String arch, {String version = '3.22.2'}) =>
        FlutterRelease(
          hash: 'h',
          channel: 'stable',
          version: version,
          dartSdkVersion: '3.4.4',
          dartSdkArch: arch,
          releaseDate: DateTime(2024),
          archive: 'archive.zip',
          sha256: 'sha',
        );

    test('returns null for an empty candidate list', () {
      expect(selectBestRelease([]), isNull);
    });

    test('returns the single candidate regardless of arch', () {
      final only = makeRelease('x64');
      expect(selectBestRelease([only]), same(only));
    });

    test('returns non-null when multiple candidates exist', () {
      final candidates = [makeRelease('x64'), makeRelease('arm64')];
      expect(selectBestRelease(candidates), isNotNull);
    });

    test('result is always one of the provided candidates', () {
      final x64 = makeRelease('x64');
      final arm = makeRelease('arm64');
      final result = selectBestRelease([x64, arm]);
      expect([x64, arm], contains(result));
    });
  });
}
