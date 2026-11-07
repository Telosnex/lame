/// Runs after each native build of the kiln release workflow: the C ABI test
/// of tool/support/abi_boundary_test.c against the built library, on the
/// targets that the build runner can run (macos-arm64, linux-x64). On
/// linux-x64 it also prints the newest glibc requirement.
///
/// It also compiles src/lame_shim.c with -Werror: the release build compiles
/// LAME with -w.
library;

import 'dart:io';

Future<void> main() async {
  final env = Platform.environment;
  final target = env['TARGET']!;
  final dir = '${env['OUT']}/out/$target';
  final test = '${env['RUNNER_TEMP']}/abi_boundary_test';
  const strict = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Isrc'];

  switch (target) {
    case 'macos-arm64':
      await _run('xcrun', [
        'clang',
        ...strict,
        '-fsyntax-only',
        '-I${await _lameInclude()}',
        'src/lame_shim.c',
      ]);
      await _run('xcrun', [
        'clang',
        ...strict,
        '-arch',
        'arm64',
        '-mmacosx-version-min=12',
        'tool/support/abi_boundary_test.c',
        '$dir/liblame.dylib',
        '-Wl,-rpath,$dir',
        '-o',
        test,
      ]);
    case 'linux-x64':
      await _run('gcc', [
        ...strict,
        '-fsyntax-only',
        '-I${await _lameInclude()}',
        'src/lame_shim.c',
      ]);
      await _run('gcc', [
        ...strict,
        'tool/support/abi_boundary_test.c',
        '-L$dir',
        '-llame',
        '-lm',
        '-Wl,-rpath,$dir',
        '-o',
        test,
      ]);
    default:
      return;
  }
  await _run(test, []);

  if (target == 'linux-x64') {
    final symbols = await _run('objdump', [
      '-T',
      '$dir/liblame.so',
    ], quiet: true);
    final versions = {
      for (final m in RegExp(r'GLIBC_([0-9.]+)').allMatches(symbols)) m[1]!,
    }.toList()..sort(_compareVersions);
    stdout.writeln('Newest glibc requirement: ${versions.last}');
  }
}

/// The include directory of the pinned LAME archive, unpacked in RUNNER_TEMP.
Future<String> _lameInclude() async {
  await _run('bash', ['tool/fetch_native_sources.sh']);
  final dir = '${Platform.environment['RUNNER_TEMP']}/lame_headers';
  await Directory(dir).create(recursive: true);
  await _run('tar', [
    '-xzf',
    'third_party/lame_3.100.orig.tar.gz',
    '-C',
    dir,
    '--strip-components=1',
    'lame-3.100/include/lame.h',
  ]);
  return '$dir/include';
}

int _compareVersions(String a, String b) {
  final (x, y) = (
    a.split('.').map(int.parse).toList(),
    b.split('.').map(int.parse).toList(),
  );
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

Future<String> _run(
  String executable,
  List<String> args, {
  bool quiet = false,
}) async {
  if (!quiet) stdout.writeln('+ $executable ${args.join(' ')}');
  final result = await Process.run(executable, args);
  if (!quiet) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    stderr.writeln('$executable: exit ${result.exitCode}');
    exit(result.exitCode);
  }
  return '${result.stdout}';
}
