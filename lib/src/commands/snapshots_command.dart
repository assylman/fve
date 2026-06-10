import '../help.dart';
import '../models/project_config.dart';
import '../services/snapshot_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Shows all pubspec.lock snapshots managed by fve.
class SnapshotsCommand extends FveCommand {
  @override
  String get name => 'snapshots';

  @override
  String get description =>
      'List pubspec.lock snapshots saved per Flutter version.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('snapshots', 'Show all snapshots for the current project'),
        HelpExample('snapshots --all', 'Show snapshots across all projects'),
      ];

  SnapshotsCommand() {
    argParser.addFlag(
      'all',
      abbr: 'a',
      help: 'List snapshots for all projects, not just the current directory.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final all = argResults!['all'] as bool;
    final service = SnapshotService();

    if (all) {
      _listAll(service);
      return;
    }

    _listForProject(service);
  }

  void _listForProject(SnapshotService service) {
    final cwd = '.';
    final projectConfig = ProjectConfig.findForDirectory(cwd);

    final snapshots = service.listSnapshots(cwd);

    if (snapshots.isEmpty) {
      Logger.dim('No snapshots found for this project.');
      Logger.dim('Snapshots are saved automatically when you run fve use <version>.');
      return;
    }

    Logger.header('dependency lock snapshots (current project)');
    for (final s in snapshots) {
      final active = projectConfig?.flutterVersion == s.version ? '  ← active' : '';
      Logger.plain('  ${s.version}$active');
      Logger.dim('    ${s.locks.join(', ')}');
      Logger.dim('    ${s.path}');
    }
    Logger.plain('');
    Logger.dim('${snapshots.length} snapshot(s).');
  }

  void _listAll(SnapshotService service) {
    final all = service.listAllSnapshots();

    if (all.isEmpty) {
      Logger.dim('No snapshots found.');
      return;
    }

    Logger.header('dependency lock snapshots (all projects)');
    String? lastProject;
    for (final s in all) {
      final proj = s['project_id'] as String;
      if (proj != lastProject) {
        Logger.plain('  Project: $proj');
        lastProject = proj;
      }
      final locks = (s['locks'] as List).join(', ');
      Logger.plain('    ${s['version']}  ($locks)');
    }
    Logger.plain('');
    Logger.dim('${all.length} snapshot(s) across ${all.map((s) => s['project_id']).toSet().length} project(s).');
  }
}
