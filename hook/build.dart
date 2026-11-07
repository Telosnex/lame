/// Bundles the lame library as a Dart code asset.
///
/// With package:kiln (kiln ADR 001), the hook downloads the library from
/// the GitHub release in native_artifacts/prebuilt.json when the package
/// sources match it (user define `native_build`: auto, download or source).
/// Otherwise it runs tool/build_native_artifact.sh, which needs the target
/// compiler. Apple targets build on macOS, Android targets on macOS or Linux,
/// and Linux and Windows targets on Linux (Windows with MinGW).
///
/// For a web build, the hook installs the web runtime files of
/// native_artifacts/web.json into the app (kiln ADR 002).
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:kiln/kiln.dart';

const _assetName = 'lame_bindings_generated.dart';

/// The NDK of the release builds. A source build uses it if it is installed.
const _androidNdkVersion = '28.2.13676358';

const _targets = {
  'android-arm',
  'android-arm64',
  'android-x64',
  'ios-arm64-iphoneos',
  'ios-arm64-iphonesimulator',
  'ios-x64-iphonesimulator',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x64',
  'windows-arm64',
  'windows-x64',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      // A web build: install the web runtime files (kiln ADR 002).
      return Kiln(input: input, output: output, log: _log).installWeb();
    }

    final target = TargetName.of(input.config.code);
    if (!_targets.contains(target.name)) {
      throw UnsupportedError(
        'lame has no native library for $target. Supported targets: '
        '${_targets.join(', ')}.',
      );
    }
    await Kiln(
      input: input,
      output: output,
      log: _log,
    ).run((source) => _buildFromSource(input, output, target, source));
  });
}

void _log(String message) => stderr.writeln('[lame] $message');

Future<void> _buildFromSource(
  BuildInput input,
  BuildOutputBuilder output,
  TargetName target,
  SourceBuild source,
) async {
  final hostProblem = _hostProblem(target);
  if (hostProblem != null) throw UnsupportedError('lame: $hostProblem');

  final code = input.config.code;
  final library = File.fromUri(
    input.outputDirectory.resolve(target.os.dylibFileName('lame')),
  );
  await Directory.fromUri(input.outputDirectory).create(recursive: true);
  // The unpacked LAME archive stays in the shared directory. Two targets can
  // build at once, so a lock guards it.
  final buildRoot = input.outputDirectoryShared.resolve(
    'build/${target.name}/',
  );
  final environment = {
    // The directory of the pinned archive of native_artifacts/sources.json.
    'LAME_SHIM_LAME_SOURCE': (await source.pinnedSource('lame')).path,
    'LAME_SHIM_BUILD_ROOT': buildRoot.toFilePath(),
    'LAME_SHIM_OUTPUT': library.path,
    if (target.os == OS.macOS)
      'LAME_SHIM_MACOS_VERSION':
          '${code.macOS.deploymentVersion.major}.${code.macOS.deploymentVersion.minor}',
    if (target.os == OS.iOS)
      'LAME_SHIM_IOS_VERSION':
          '${code.iOS.deploymentVersion.major}.${code.iOS.deploymentVersion.minor}',
    if (target.os == OS.android) ...{
      'LAME_SHIM_ANDROID_API': '${code.android.targetNdkApi}',
      'ANDROID_NDK_HOME': _androidNdk(),
    },
  };

  await _withLock(
    File.fromUri(
      input.outputDirectoryShared.resolve('build/${target.name}.lock'),
    ),
    () => _run(input.packageRoot, [
      'tool/build_native_artifact.sh',
      target.name,
    ], environment),
  );

  for (final path in [
    'src/lame_shim.c',
    'src/lame_shim.h',
    'src/lame_config/config.h',
    'src/exports_windows.def',
    'tool/build_native_artifact.sh',
  ]) {
    output.dependencies.add(input.packageRoot.resolve(path));
  }
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _assetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}

/// Why this host cannot build [target] from source, or null if it can.
String? _hostProblem(TargetName target) {
  final (hosts, allowed) = switch (target.os) {
    OS.iOS || OS.macOS => ('macOS', Platform.isMacOS),
    OS.android => ('macOS or Linux', Platform.isMacOS || Platform.isLinux),
    OS.linux => ('Linux', Platform.isLinux),
    // MinGW cross-compiles the Windows libraries on Linux.
    OS.windows => ('Linux, with MinGW', Platform.isLinux),
    _ => ('no host', false),
  };
  if (allowed) return null;
  return 'a source build of $target runs only on $hosts, and this host is '
      '${Platform.operatingSystem}.';
}

/// The Android NDK: the release version if it is installed, else the NDK of
/// the environment, else the newest NDK of the Android SDK.
String _androidNdk() {
  final env = Platform.environment;
  final home = env['HOME'];
  final sdks = [
    ?env['ANDROID_HOME'],
    ?env['ANDROID_SDK_ROOT'],
    if (home != null) ...['$home/Library/Android/sdk', '$home/Android/Sdk'],
  ].where((sdk) => Directory('$sdk/ndk').existsSync());
  bool isNdk(String path) => File('$path/source.properties').existsSync();

  final candidates = [
    for (final sdk in sdks) '$sdk/ndk/$_androidNdkVersion',
    ?env['ANDROID_NDK_HOME'],
    ?env['ANDROID_NDK_ROOT'],
    ?env['ANDROID_NDK'],
    ?env['ANDROID_NDK_LATEST_HOME'],
    for (final sdk in sdks)
      ...(Directory('$sdk/ndk').listSync().whereType<Directory>().toList()
            ..sort((a, b) => _compareVersions(b.path, a.path)))
          .map((d) => d.path),
  ];
  for (final candidate in candidates) {
    if (isNdk(candidate)) {
      _log('Android NDK: $candidate');
      return candidate;
    }
  }
  throw StateError(
    'lame: no Android NDK found. Install NDK $_androidNdkVersion with '
    'the Android SDK manager, or set ANDROID_NDK_HOME.',
  );
}

int _compareVersions(String a, String b) {
  List<int> parts(String path) => [
    for (final part in path.split(RegExp(r'[/\\]')).last.split('.'))
      int.tryParse(part) ?? 0,
  ];
  final (x, y) = (parts(a), parts(b));
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

Future<void> _run(
  Uri packageRoot,
  List<String> bashArguments,
  Map<String, String> environment,
) async {
  // bash runs the script, so the file mode of a checkout does not matter.
  final process = await Process.start(
    bashExecutable(),
    bashArguments,
    workingDirectory: packageRoot.toFilePath(),
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError(
      'lame: ${bashArguments.join(' ')} failed with exit code $exitCode.',
    );
  }
}

Future<T> _withLock<T>(File lockFile, Future<T> Function() action) async {
  await lockFile.parent.create(recursive: true);
  final handle = await lockFile.open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.blockingExclusive);
    return await action();
  } finally {
    await handle.close();
  }
}
