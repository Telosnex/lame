/// The browser tests of the web runtime files in lib/web/ (kiln ADR 002 D10),
/// with dart2js and dart2wasm. The kiln release workflow runs it after
/// `kiln:web install-dev` of the files that tool/kiln/build_web.dart built.
///
/// Locally, after `dart run kiln:web install-dev`:
///
///     dart tool/kiln/test_web.dart
library;

import 'dart:io';

Future<void> main() async {
  final root = Directory.fromUri(Platform.script.resolve('../..')).path;
  for (final compiler in ['dart2js', 'dart2wasm']) {
    final args = [
      'test',
      '-p',
      'chrome',
      '--compiler',
      compiler,
      '-r',
      'expanded',
    ];
    stdout.writeln('+ dart ${args.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      args,
      workingDirectory: root,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) exit(code);
  }
}
