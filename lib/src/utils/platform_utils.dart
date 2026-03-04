import 'dart:io';

enum FvePlatform { macOS, linux, windows }

enum FveArch { x64, arm64 }

FvePlatform get currentPlatform {
  if (Platform.isMacOS) return FvePlatform.macOS;
  if (Platform.isLinux) return FvePlatform.linux;
  if (Platform.isWindows) return FvePlatform.windows;
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

FveArch get currentArch {
  try {
    final result = Process.runSync('uname', ['-m']);
    if (result.exitCode == 0) {
      final arch = result.stdout.toString().trim();
      if (arch == 'arm64' || arch == 'aarch64') return FveArch.arm64;
      return FveArch.x64;
    }
  } catch (_) {}
  // uname unavailable — warn so the user knows a wrong binary may be selected.
  stderr.writeln(
    'fve warning: could not detect CPU architecture via uname. '
    'Assuming x64 — if you are on arm64, use --no-git to force archive download.',
  );
  return FveArch.x64;
}

String get platformKey {
  switch (currentPlatform) {
    case FvePlatform.macOS:
      return 'macos';
    case FvePlatform.linux:
      return 'linux';
    case FvePlatform.windows:
      return 'windows';
  }
}

String get releasesJsonUrl =>
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_$platformKey.json';

String get flutterBinaryName =>
    Platform.isWindows ? 'flutter.bat' : 'flutter';

String get dartBinaryName => Platform.isWindows ? 'dart.bat' : 'dart';
