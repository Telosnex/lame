@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:lame/lame.dart';
import 'package:lame/src/backend/backend_web.dart';
import 'package:test/test.dart';

void main() {
  test('the default worker URL is in kiln/lame/, with the web version', () {
    final url = resolveWorkerUrl('https://app.example/sub/', null);
    expect(url.path, '/sub/kiln/lame/lame_worker.mjs');
    expect(url.queryParameters['v'], isNotEmpty);
    expect(
      resolveWorkerUrl('https://app.example/', Uri.parse('w.mjs?v=x')).query,
      'v=x',
    );
  });

  // Runs before any test of this file loads the Worker: Lame keeps a loaded
  // backend, and drops a failed one.
  test(
    'a missing worker fails with LameException, then a good one loads',
    () async {
      LameWeb.workerUri = Uri.base.resolve('packages/lame/web/missing.mjs');
      await expectLater(
        Lame.encode(Int16List(2), sampleRate: 44100, channels: 1),
        throwsA(isA<LameException>().having((e) => e.status, 'status', -100)),
      );
      LameWeb.workerUri = Uri.base.resolve(
        'packages/lame/web/lame_worker.mjs?v=test',
      );
      final mp3 = await Lame.encode(
        Int16List(2),
        sampleRate: 44100,
        channels: 1,
      );
      expect(mp3.take(2), [0xff, 0xfb]);
    },
  );

  test('the caller keeps its PCM after a transfer', () async {
    final pcm = Int16List.fromList([1, 2, 3, 4]);
    await Lame.encode(pcm, sampleRate: 44100, channels: 2);
    expect(pcm, [1, 2, 3, 4]);
  });
}
