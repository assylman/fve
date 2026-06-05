import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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
      final name = entry.key;
      final constraint = entry.value;

      // Skip git/path dependencies (3.1.8).
      if (constraint.startsWith('git:') ||
          constraint.startsWith('path:') ||
          constraint.contains('git:') ||
          constraint.contains('path:')) {
        continue;
      }

      final result = await _checkPackage(name, constraint, flutterVersion);
      if (result != null && !result.compatible) {
        results.add(result);
      }
    }

    return results;
  }

  // ── pubspec.yaml parsing ───────────────────────────────────────────────────

  /// Very lightweight YAML parser that extracts top-level dependency entries
  /// from the `dependencies:` and `dev_dependencies:` sections.
  Map<String, String> _parseDependencies(String yaml) {
    final deps = <String, String>{};
    var inDeps = false;

    for (final rawLine in yaml.split('\n')) {
      final line = rawLine;

      // Start of a relevant section.
      if (line.trimRight() == 'dependencies:' ||
          line.trimRight() == 'dev_dependencies:') {
        inDeps = true;
        continue;
      }

      // New top-level section.
      if (inDeps && line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
        inDeps = false;
      }

      if (!inDeps) continue;

      // Lines like "  package_name: ^1.2.3" or "  package_name: any"
      final match = RegExp(r'^\s{2,4}(\w[\w_-]*):\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      final val = match.group(2)!.trim();
      if (name == 'flutter' || name == 'flutter_test') continue;
      if (val.isNotEmpty) deps[name] = val;
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

  /// Very simplified constraint checker: handles `>=X.Y.Z`, `>=X.Y.Z <A.B.C`,
  /// and `any`.
  bool _satisfiesConstraint(String version, String constraint) {
    if (constraint.trim() == 'any') return true;

    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return true; // can't parse

    final v = _VersionTuple(parts[0]!, parts.length > 1 ? parts[1]! : 0,
        parts.length > 2 ? parts[2]! : 0);

    final ranges = constraint.split(' ').where((s) => s.isNotEmpty).toList();
    for (final range in ranges) {
      final geMatch = RegExp(r'^>=(\d+)\.(\d+)\.(\d+)').firstMatch(range);
      final gtMatch = RegExp(r'^>(\d+)\.(\d+)\.(\d+)').firstMatch(range);
      final ltMatch = RegExp(r'^<(\d+)\.(\d+)\.(\d+)').firstMatch(range);
      final leMatch = RegExp(r'^<=(\d+)\.(\d+)\.(\d+)').firstMatch(range);

      if (geMatch != null) {
        final bound = _VersionTuple(int.parse(geMatch.group(1)!),
            int.parse(geMatch.group(2)!), int.parse(geMatch.group(3)!));
        if (v < bound) return false;
      } else if (gtMatch != null) {
        final bound = _VersionTuple(int.parse(gtMatch.group(1)!),
            int.parse(gtMatch.group(2)!), int.parse(gtMatch.group(3)!));
        if (v <= bound) return false;
      } else if (ltMatch != null) {
        final bound = _VersionTuple(int.parse(ltMatch.group(1)!),
            int.parse(ltMatch.group(2)!), int.parse(ltMatch.group(3)!));
        if (v >= bound) return false;
      } else if (leMatch != null) {
        final bound = _VersionTuple(int.parse(leMatch.group(1)!),
            int.parse(leMatch.group(2)!), int.parse(leMatch.group(3)!));
        if (v > bound) return false;
      }
    }
    return true;
  }
}

class _VersionTuple implements Comparable<_VersionTuple> {
  final int major, minor, patch;
  const _VersionTuple(this.major, this.minor, this.patch);

  @override
  int compareTo(_VersionTuple other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(_VersionTuple other) => compareTo(other) < 0;
  bool operator <=(_VersionTuple other) => compareTo(other) <= 0;
  bool operator >(_VersionTuple other) => compareTo(other) > 0;
  bool operator >=(_VersionTuple other) => compareTo(other) >= 0;
}
