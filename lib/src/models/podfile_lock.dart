/// A parsed view of a CocoaPods `Podfile.lock`.
///
/// Only the bits fve needs are extracted:
///   * [pods] — the installed version of each top-level pod (the `PODS:`
///     section, e.g. `Firebase/Core (10.0.0)` → `Firebase/Core: 10.0.0`).
///     Sub-dependency lines (constraints like `(= 10.0.0)` / `(~> 5.14)`,
///     indented deeper) are ignored — only concrete installed versions.
///   * [cocoaPodsVersion] — the `COCOAPODS:` trailer, i.e. the CocoaPods
///     version that generated the lock (null if absent).
class PodfileLock {
  final Map<String, String> pods;
  final String? cocoaPodsVersion;

  const PodfileLock({required this.pods, this.cocoaPodsVersion});

  /// A top-level pod entry: exactly two-space indent, `- Name (version)` where
  /// version starts with a digit (excludes constraint lines like `(= 1.0)`).
  static final _podLine =
      RegExp(r'^  - "?([^"\s]+)"? \((\d[^)]*)\)');

  static final _cocoaPodsLine = RegExp(r'^COCOAPODS:\s*(\S+)', multiLine: true);

  static PodfileLock parse(String content) {
    final pods = <String, String>{};
    var inPods = false;
    for (final line in content.split('\n')) {
      if (line.startsWith('PODS:')) {
        inPods = true;
        continue;
      }
      // A non-indented, non-empty line ends the PODS section.
      if (inPods && line.isNotEmpty && !line.startsWith(' ')) {
        inPods = false;
      }
      if (inPods) {
        final m = _podLine.firstMatch(line);
        if (m != null) pods[m.group(1)!] = m.group(2)!;
      }
    }

    final cp = _cocoaPodsLine.firstMatch(content);
    return PodfileLock(pods: pods, cocoaPodsVersion: cp?.group(1));
  }
}

/// Severity of a CocoaPods version mismatch between a `Podfile.lock` (the
/// version that generated it) and the currently installed `pod` binary.
enum CocoaPodsDrift {
  /// Same version — no drift.
  none,

  /// Patch-level difference only (e.g. `1.16.1` vs `1.16.2`). CocoaPods ships
  /// frequent patch releases that rarely change pod resolution, so this is a
  /// non-fatal warning rather than a hard failure (avoids breaking CI gates on
  /// routine patch bumps).
  patch,

  /// Major or minor difference (e.g. `1.15.x` vs `1.16.x`, or `1.x` vs `2.x`),
  /// which can change dependency resolution or the generated Pods project — a
  /// real problem worth failing on.
  significant,
}

/// Classifies the drift between the CocoaPods version that built a
/// `Podfile.lock` ([lockCp]) and the currently [installedCp] version.
///
/// Versions are compared component-wise (`major.minor.patch`); missing or
/// unparseable components are treated as `0` so `1.16` and `1.16.0` compare
/// equal. A major/minor difference is [CocoaPodsDrift.significant]; a
/// patch-only difference is [CocoaPodsDrift.patch].
CocoaPodsDrift cocoaPodsDrift(String lockCp, String installedCp) {
  List<int> components(String v) {
    final parts = v.split('.');
    int at(int i) {
      if (i >= parts.length) return 0;
      // Take the leading digits of the component so a pre-release/build suffix
      // (`2-rc1`, `2+1`) still reads as its numeric value.
      final digits = RegExp(r'^\d+').firstMatch(parts[i])?.group(0);
      return int.tryParse(digits ?? '') ?? 0;
    }

    return [at(0), at(1), at(2)];
  }

  final a = components(lockCp);
  final b = components(installedCp);
  if (a[0] == b[0] && a[1] == b[1] && a[2] == b[2]) return CocoaPodsDrift.none;
  if (a[0] != b[0] || a[1] != b[1]) return CocoaPodsDrift.significant;
  return CocoaPodsDrift.patch;
}

/// One pod's change between two `Podfile.lock` snapshots.
enum PodChangeKind { added, removed, changed }

class PodChange {
  final String name;
  final PodChangeKind kind;
  final String? from; // null for added
  final String? to; // null for removed

  const PodChange(this.name, this.kind, {this.from, this.to});
}

/// Computes the per-pod differences going from [before] to [after], sorted by
/// pod name. Pods present in both with the same version are omitted.
List<PodChange> diffPodfileLocks(PodfileLock before, PodfileLock after) {
  final names = {...before.pods.keys, ...after.pods.keys}.toList()..sort();
  final out = <PodChange>[];
  for (final name in names) {
    final b = before.pods[name];
    final a = after.pods[name];
    if (b == a) continue;
    if (b == null) {
      out.add(PodChange(name, PodChangeKind.added, to: a));
    } else if (a == null) {
      out.add(PodChange(name, PodChangeKind.removed, from: b));
    } else {
      out.add(PodChange(name, PodChangeKind.changed, from: b, to: a));
    }
  }
  return out;
}
