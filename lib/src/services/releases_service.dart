import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/flutter_release.dart';
import '../utils/platform_utils.dart';

class ReleasesService {
  final http.Client _client;

  ReleasesService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the full releases list for the current platform.
  Future<FlutterReleasesResponse> fetchReleases() async {
    final uri = Uri.parse(releasesJsonUrl);
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch Flutter releases '
        '(HTTP ${response.statusCode}): $releasesJsonUrl',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return FlutterReleasesResponse.fromJson(json);
  }

  /// Finds the best-matching release for [version] on the current platform
  /// and architecture. [version] can be a full version string ("3.22.2"),
  /// a channel name ("stable", "beta", "dev"), or a partial version prefix.
  Future<FlutterRelease?> findRelease(String version) async {
    final resp = await fetchReleases();

    // Resolve channel aliases to the latest release hash.
    if (_isChannel(version)) {
      final hash = resp.latestHashForChannel(version);
      if (hash == null) return null;
      final candidates = resp.releases.where((r) => r.hash == hash).toList();
      return selectBestRelease(candidates);
    }

    // Find all releases that match the requested version string.
    final candidates =
        resp.releases.where((r) => r.version == version).toList();

    if (candidates.isEmpty) return null;
    return selectBestRelease(candidates);
  }

  static bool _isChannel(String value) =>
      value == 'stable' || value == 'beta' || value == 'dev' ||
      value == 'master';
}
