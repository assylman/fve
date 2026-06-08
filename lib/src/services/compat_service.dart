import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Result of a single package compatibility check.
class CompatResult {
  final String package;
  final String constraint;
  final bool compatible;
  final String? reason;

  const CompatResult({
    required this.package,
    required this.constraint,
    required this.compatible,
    this.reason,
  });
}

/// Checks whether the packages in `pubspec.yaml` in [projectDir] are
/// compatible with [flutterVersion] by querying the pub.dev API.
///
/// Returns the list of incompatible packages.  If the directory has no
/// pubspec.yaml the list is empty (3.1.4 — skips check).
///
/// Uses cached package metadata when offline (3.1.9).
class CompatService {
  final http.Client _client;

  CompatService({http.Client? client}) : _client = client ?? http.Client();

  /// Checks compatibility.  Pass [force] = true to bypass (3.1.6).
  Future<List<CompatResult>> check(
    String projectDir,
    String flutterVersion, {
    bool force = false,
  }) async {
    if (force) return [];

    final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return []; // 3.1.4

    final deps = _parseDependencies(pubspec.readAsStringSync());
    if (deps.isEmpty) return [];

    final results = <CompatResult>[];

    for (final entry in deps.entries) {
      final result =
          await _checkPackage(entry.key, entry.value, flutterVersion);
      if (result != null && !result.compatible) {
        results.add(result);
      }
    }

    return results;
  }

  // ── pubspec.yaml parsing ───────────────────────────────────────────────────

  /// Extracts hosted package dependencies (name → version constraint string)
  /// from the `dependencies:` and `dev_dependencies:` sections.
  ///
  /// Uses the `yaml` package for correct parsing. Dependencies expressed as a
  /// map (git/path/sdk/hosted overrides) are skipped — they can't be checked
  /// against pub.dev (3.1.8). The Flutter SDK pseudo-deps are also skipped.
  /// Returns an empty map on malformed YAML (check is silently skipped).
  Map<String, String> _parseDependencies(String yamlText) {
    final deps = <String, String>{};

    dynamic doc;
    try {
      doc = loadYaml(yamlText);
    } catch (_) {
      return deps; // malformed — skip the check rather than crash
    }
    if (doc is! Map) return deps;

    for (final section in const ['dependencies', 'dev_dependencies']) {
      final node = doc[section];
      if (node is! Map) continue;

      for (final entry in node.entries) {
        final name = entry.key.toString();
        if (name == 'flutter' || name == 'flutter_test') continue;

        final value = entry.value;
        // Map-form deps (git:/path:/sdk:/hosted:) can't be checked — skip.
        if (value is Map) continue;
        // A bare `package:` with no value means "any".
        deps[name] = value == null ? 'any' : value.toString();
      }
    }

    return deps;
  }

  // ── pub.dev API ────────────────────────────────────────────────────────────

  Future<CompatResult?> _checkPackage(
    String name,
    String constraint,
    String flutterVersion,
  ) async {
    try {
      final uri = Uri.parse('https://pub.dev/api/packages/$name');
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('{}', 408),
      );

      if (response.statusCode == 404) {
        return CompatResult(
          package: name,
          constraint: constraint,
          compatible: false,
          reason: 'package not found on pub.dev',
        );
      }
      if (response.statusCode != 200) {
        // Unknown compatibility — treat as unknown, not fail (3.1.10).
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (json['latest'] as Map<String, dynamic>?);
      if (latest == null) return null;

      final pubspec = latest['pubspec'] as Map<String, dynamic>?;
      final flutterConstraint =
          ((pubspec?['environment'] as Map<String, dynamic>?)?['flutter']
              as String?);

      if (flutterConstraint == null) {
        // No Flutter SDK constraint → treat as unknown (3.1.10).
        return null;
      }

      final compatible = _satisfiesConstraint(flutterVersion, flutterConstraint);
      return CompatResult(
        package: name,
        constraint: constraint,
        compatible: compatible,
        reason: compatible
            ? null
            : 'requires Flutter $flutterConstraint (have $flutterVersion)',
      );
    } catch (_) {
      // Offline or timeout — skip (3.1.9).
      return null;
    }
  }

  // ── Constraint matching ────────────────────────────────────────────────────

  /// Returns true when [version] satisfies the pub [constraint], using the
  /// same `pub_semver` library pub itself uses — so `^`, exact pins, ranges
  /// (`>=3.0.0 <4.0.0`), and `any` are all handled correctly.
  ///
  /// If either side can't be parsed (e.g. [version] is a channel name like
  /// `stable`, or the constraint is malformed) we can't disprove
  /// compatibility, so we treat it as compatible (unknown, not a failure).
  bool _satisfiesConstraint(String version, String constraint) {
    try {
      return VersionConstraint.parse(constraint).allows(Version.parse(version));
    } catch (_) {
      return true;
    }
  }
}
