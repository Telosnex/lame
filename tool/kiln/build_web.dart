/// Builds the lame web runtime: LAME 3.100's libmp3lame and the shim as
/// one Emscripten ES module, lame_module.mjs and lame_module.wasm in
/// --out.
///
/// The kiln release workflow runs it in the pinned emscripten/emsdk:5.0.0
/// image (kiln ADR 002 D10). --toolchain-file gets the Emscripten version
/// for web.json. For a local build, activate Emscripten 5.0.0, or set EMSDK
/// to it, or put it at ../emsdk. Then install the files with
///
///     dart tool/kiln/build_web.dart --out /tmp/lame_web
///     dart run kiln:web install-dev --from /tmp/lame_web
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

const _usage =
    'dart tool/kiln/build_web.dart --out <dir> [--toolchain-file <file>]\n'
    '  --out             Directory for the two generated files.\n'
    '  --toolchain-file  Gets the Emscripten version.';

const _outputs = ['lame_module.mjs', 'lame_module.wasm'];
const _emscripten = '5.0.0 (a7c5deabd7c88ba1c38ebe988112256775f944c6)';

const _exportedFunctions = [
  '_malloc',
  '_free',
  '_lame_shim_abi_version',
  '_lame_shim_build_info',
  '_lame_shim_encode_pcm16',
  '_lame_shim_buffer_data',
  '_lame_shim_buffer_length',
  '_lame_shim_buffer_release',
  '_lame_shim_error_message',
];

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final root = Directory.fromUri(
    Platform.script.resolve('../..'),
  ).absolute.path.replaceFirst(RegExp(r'/$'), '');
  final out = Directory(options['out']!).absolute;
  if (await out.exists()) {
    await for (final entity in out.list()) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (!_outputs.contains(name)) _fail('--out holds other files: $name');
    }
  }
  await out.create(recursive: true);

  final emsdkEnv = await _emsdkEnvironment(root);
  final version = await _output(['emcc', '--version'], root, emsdkEnv);
  if (!version.split('\n').first.contains(_emscripten)) {
    _fail(
      'Emscripten $_emscripten is required, found: ${version.split('\n').first}',
    );
  }
  if (options['toolchain-file'] case final path?) {
    await File(path).writeAsString('Emscripten $_emscripten\n');
  }

  // The same pinned archive and the same file list as
  // tool/build_native_artifact.sh.
  await _run(['bash', 'tool/fetch_native_sources.sh'], root, emsdkEnv);
  final work = await Directory.systemTemp.createTemp('lame_web');
  try {
    final lame = '${work.path}/lame';
    await Directory(lame).create();
    await _run(
      [
        'tar',
        '-xzf',
        '$root/third_party/lame_3.100.orig.tar.gz',
        '-C',
        lame,
        '--strip-components=1',
      ],
      root,
      emsdkEnv,
    );
    final sources = [
      for (final file in Directory('$lame/libmp3lame').listSync())
        if (file.path.endsWith('.c') &&
            !file.path.endsWith('/mpglib_interface.c'))
          file.path,
    ]..sort();

    await _run(
      [
        'emcc',
        '-std=gnu99',
        '-O3',
        // As in tool/build_native_artifact.sh: no fused multiply-add, so
        // every target computes the same bytes.
        '-ffp-contract=off',
        '-w',
        '-DHAVE_CONFIG_H',
        '-I$root/src/lame_config',
        '-I$root/src',
        '-I$lame/include',
        '-I$lame/libmp3lame',
        ...sources,
        '$root/src/lame_shim.c',
        '-lm',
        '--no-entry',
        '-sMODULARIZE=1',
        '-sEXPORT_ES6=1',
        '-sENVIRONMENT=web,worker,node',
        '-sALLOW_MEMORY_GROWTH=1',
        '-sFILESYSTEM=0',
        '-sEXPORTED_FUNCTIONS=${_exportedFunctions.join(',')}',
        '-sEXPORTED_RUNTIME_METHODS=UTF8ToString,HEAPU8,HEAPU32',
        '-o',
        '${out.path}/${_outputs.first}',
      ],
      root,
      emsdkEnv,
    );
  } finally {
    await work.delete(recursive: true);
  }

  stdout.writeln('Built:');
  for (final name in _outputs) {
    final file = File('${out.path}/$name');
    if (!file.existsSync()) _fail('Expected output not found: ${file.path}');
    final bytes = await file.readAsBytes();
    stdout.writeln('  ${sha256.convert(bytes)}  ${bytes.length}  $name');
  }
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final name = switch (args[i]) {
      '-h' || '--help' => _exitHelp(),
      '--out' => 'out',
      '--toolchain-file' => 'toolchain-file',
      _ => _fail('Unknown argument: ${args[i]}\n$_usage'),
    };
    if (i + 1 == args.length) _fail('${args[i]} needs a value.\n$_usage');
    options[name] = args[++i];
  }
  if (options['out'] == null) _fail('Pass --out.\n$_usage');
  return options;
}

Never _exitHelp() {
  stdout.writeln(_usage);
  exit(0);
}

/// Null if the emcc on the PATH is the pinned version, else the
/// emsdk_env.sh of $EMSDK or ../emsdk, which each command then sources.
Future<String?> _emsdkEnvironment(String root) async {
  final probe = await Process.run('bash', ['-c', 'emcc --version']);
  if (probe.exitCode == 0 && '${probe.stdout}'.contains(_emscripten)) {
    return null;
  }
  final candidates = [
    if (Platform.environment['EMSDK'] case final emsdk?)
      File('$emsdk/emsdk_env.sh'),
    File('$root/../emsdk/emsdk_env.sh'),
  ];
  for (final env in candidates) {
    if (env.existsSync()) return env.absolute.path;
  }
  _fail(
    'Emscripten $_emscripten not found. Activate it, set EMSDK, or put it '
    'at ${candidates.last.parent.path}.',
  );
}

List<String> _wrap(List<String> command, String? emsdkEnv) => emsdkEnv == null
    ? command
    : [
        'bash',
        '-c',
        'source "\$0" > /dev/null && exec "\$@"',
        emsdkEnv,
        ...command,
      ];

Future<String> _output(
  List<String> command,
  String cwd,
  String? emsdkEnv,
) async {
  final c = _wrap(command, emsdkEnv);
  final result = await Process.run(
    c.first,
    c.skip(1).toList(),
    workingDirectory: cwd,
    environment: {if (emsdkEnv != null) 'EMSDK_QUIET': '1'},
  );
  if (result.exitCode != 0) {
    _fail('${command.join(' ')} failed: ${result.stderr}');
  }
  return '${result.stdout}';
}

Future<void> _run(List<String> command, String cwd, String? emsdkEnv) async {
  stdout.writeln(
    '+ ${command.take(3).join(' ')}${command.length > 3 ? ' ...' : ''}',
  );
  final c = _wrap(command, emsdkEnv);
  final process = await Process.start(
    c.first,
    c.skip(1).toList(),
    workingDirectory: cwd,
    environment: {if (emsdkEnv != null) 'EMSDK_QUIET': '1'},
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('${command.first} failed with exit code $code.');
}

Never _fail(String message) {
  stderr.writeln('build_web: $message');
  exit(1);
}
