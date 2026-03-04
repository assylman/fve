import '../utils/platform_utils.dart';

class FlutterReleasesResponse {
  final String baseUrl;
  final Map<String, String> currentRelease;
  final List<FlutterRelease> releases;

  const FlutterReleasesResponse({
    required this.baseUrl,
    required this.currentRelease,
    required this.releases,
  });

  factory FlutterReleasesResponse.fromJson(Map<String, dynamic> json) {
    return FlutterReleasesResponse(
      baseUrl: json['base_url'] as String,
      currentRelease: Map<String, String>.from(
        json['current_release'] as Map,
      ),
      releases: (json['releases'] as List)
          .map((r) => FlutterRelease.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Returns the hash of the latest release for a given channel.
  String? latestHashForChannel(String channel) =>
      currentRelease[channel];
}

class FlutterRelease {
  final String hash;
  final String channel;
  final String version;
  final String dartSdkVersion;
  final String dartSdkArch;
  final DateTime releaseDate;
  final String archive;
  final String sha256;

  const FlutterRelease({
    required this.hash,
    required this.channel,
    required this.version,
    required this.dartSdkVersion,
    required this.dartSdkArch,
    required this.releaseDate,
    required this.archive,
    required this.sha256,
  });

  factory FlutterRelease.fromJson(Map<String, dynamic> json) {
    return FlutterRelease(
      hash: json['hash'] as String,
      channel: json['channel'] as String,
      version: json['version'] as String,
      dartSdkVersion: (json['dart_sdk_version'] as String?) ?? '',
      dartSdkArch: (json['dart_sdk_arch'] as String?) ?? 'x64',
      releaseDate: DateTime.parse(json['release_date'] as String),
      archive: json['archive'] as String,
      sha256: (json['sha256'] as String?) ?? '',
    );
  }

  bool get isArm64 => dartSdkArch == 'arm64';

  /// Full download URL for this release.
  String downloadUrl(String baseUrl) => '$baseUrl/$archive';

  /// The version label as shown to users (e.g. "3.22.2 (stable)").
  String get displayVersion {
    final channelLabel = channel == 'stable' ? '' : ' ($channel)';
    return '$version$channelLabel';
  }

  @override
  String toString() => 'FlutterRelease($version, $channel, $dartSdkArch)';
}

/// Selects the best release from a list for the current machine architecture.
FlutterRelease? selectBestRelease(
  List<FlutterRelease> candidates,
) {
  final arch = currentArch;

  // Prefer exact arch match.
  for (final r in candidates) {
    if (arch == FveArch.arm64 && r.isArm64) return r;
    if (arch == FveArch.x64 && !r.isArm64) return r;
  }

  // Fallback: return first candidate regardless of arch.
  return candidates.isEmpty ? null : candidates.first;
}
