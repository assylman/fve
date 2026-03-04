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
    final arch = result.stdout.toString().trim();
    if (arch == 'arm64' || arch == 'aarch64') return FveArch.arm64;
  } catch (_) {}
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
