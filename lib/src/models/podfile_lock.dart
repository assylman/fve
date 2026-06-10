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
