import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lame/lame.dart';
import 'package:test/test.dart';

/// [seconds] of a 440 Hz tone (and 660 Hz on the second channel).
Int16List tone({
  required int sampleRate,
  required int channels,
  double seconds = 1,
}) {
  final frames = (sampleRate * seconds).round();
  final pcm = Int16List(frames * channels);
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < channels; c++) {
      pcm[i * channels + c] =
          (sin(2 * pi * (440 + 220 * c) * i / sampleRate) * 8000).round();
    }
  }
  return pcm;
}

/// The MPEG audio frame header at [offset] of [mp3]: sync bits, version,
/// layer III.
({int version, int sampleRate, int channels}) frameHeader(
  Uint8List mp3, [
  int offset = 0,
]) {
  final b1 = mp3[offset + 1], b2 = mp3[offset + 2], b3 = mp3[offset + 3];
  expect(mp3[offset], 0xff, reason: 'frame sync');
  expect(b1 & 0xe0, 0xe0, reason: 'frame sync');
  expect((b1 >> 1) & 3, 1, reason: 'layer III');
  final version = (b1 >> 3) & 3; // 3: MPEG-1, 2: MPEG-2, 0: MPEG-2.5
  const rates = {
    3: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    0: [11025, 12000, 8000],
  };
  return (
    version: version,
    sampleRate: rates[version]![(b2 >> 2) & 3],
    channels: (b3 >> 6) == 3 ? 1 : 2,
  );
}

bool containsAscii(Uint8List bytes, String text, {int limit = 512}) {
  final codes = text.codeUnits;
  final end = min(bytes.length, limit) - codes.length;
  for (var i = 0; i <= end; i++) {
    var match = true;
    for (var j = 0; j < codes.length && match; j++) {
      match = bytes[i + j] == codes[j];
    }
    if (match) return true;
  }
  return false;
}

void main() {
  // The test server maps packages/lame/ to lib/. Native ignores it.
  setUpAll(
    () => LameWeb.workerUri = Uri.base.resolve(
      'packages/lame/web/lame_worker.mjs?v=test',
    ),
  );

  test('buildInfo names LAME 3.100', () async {
    expect(await Lame.buildInfo, 'lame 1, LAME 3.100');
  });

  test('CBR stereo at 44.1 kHz', () async {
    final mp3 = await Lame.encode(
      tone(sampleRate: 44100, channels: 2),
      sampleRate: 44100,
      channels: 2,
    );
    final header = frameHeader(mp3);
    expect(header.sampleRate, 44100);
    expect(header.channels, 2);
    // 1 s at 128 kbit/s is 16 000 bytes, plus the tag frame and padding.
    expect(mp3.length, inInclusiveRange(16000, 17500));
    expect(containsAscii(mp3, 'Info'), isTrue, reason: 'CBR tag frame');
    expect(containsAscii(mp3, 'LAME3.100'), isTrue);
  });

  test('VBR mono has a Xing tag', () async {
    final mp3 = await Lame.encode(
      tone(sampleRate: 24000, channels: 1),
      sampleRate: 24000,
      channels: 1,
      bitrate: const Mp3Bitrate.variable(4),
    );
    final header = frameHeader(mp3);
    expect(header.channels, 1);
    expect(header.sampleRate, 24000);
    expect(containsAscii(mp3, 'Xing'), isTrue);
  });

  test('ABR stereo at 16 kHz', () async {
    final mp3 = await Lame.encode(
      tone(sampleRate: 16000, channels: 2),
      sampleRate: 16000,
      channels: 2,
      bitrate: const Mp3Bitrate.average(48),
      quality: 7,
    );
    expect(frameHeader(mp3).sampleRate, 16000);
    // 1 s at about 48 kbit/s.
    expect(mp3.length, inInclusiveRange(4000, 9000));
  });

  test('an odd input rate resamples', () async {
    final mp3 = await Lame.encode(
      tone(sampleRate: 37000, channels: 1),
      sampleRate: 37000,
      channels: 1,
    );
    expect(frameHeader(mp3).sampleRate, isIn([32000, 44100, 48000]));
  });

  test('empty input gives a valid stream', () async {
    final mp3 = await Lame.encode(Int16List(0), sampleRate: 44100, channels: 1);
    expect(frameHeader(mp3).channels, 1);
  });

  test('longer than one 8192-frame chunk, odd length', () async {
    final pcm = tone(sampleRate: 22050, channels: 2, seconds: 2.3);
    final mp3 = await Lame.encode(
      pcm,
      sampleRate: 22050,
      channels: 2,
      bitrate: const Mp3Bitrate.constant(64),
    );
    // 2.3 s at 64 kbit/s is 18 400 bytes.
    expect(mp3.length, inInclusiveRange(18000, 20500));
  });

  test('the same input gives the same bytes', () async {
    final pcm = tone(sampleRate: 44100, channels: 2, seconds: 0.5);
    final a = await Lame.encode(pcm, sampleRate: 44100, channels: 2);
    final b = await Lame.encode(pcm, sampleRate: 44100, channels: 2);
    expect(a, b);
  });

  // The build turns off fused multiply-add, so native and Wasm output are the
  // same bytes on every target. A change of these digests is a change of the
  // encoder's output.
  test('every target encodes the same bytes', () async {
    final random = Random(7);
    final pcm = Int16List(44100 * 2);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = (sin(i / 9.0) * 6000 + random.nextInt(2000) - 1000).round();
    }
    final digests = {
      for (final bitrate in const [
        Mp3Bitrate.constant(128),
        Mp3Bitrate.variable(4),
        Mp3Bitrate.average(96),
      ])
        '$bitrate':
            '${sha256.convert(await Lame.encode(pcm, sampleRate: 44100, channels: 2, bitrate: bitrate))}',
    };
    expect(digests, {
      'Mp3Bitrate.constant(128)':
          '7f2dbf639d4e4ec47a5b966f634e3ab9e8111472b3c3c66daebed399486a9fc0',
      'Mp3Bitrate.variable(4)':
          'f1b6aeac5ef3db120ab6c22f6a746d2d3cad6462ab00b2cfd3aa1e2c211e65d0',
      'Mp3Bitrate.average(96)':
          '0fcfaaae71b66ccb0b2dc694c461b7c00734c43871f9d7c61ab6f047d847b33b',
    });
  });

  group('invalid arguments', () {
    final pcm = Int16List(4);
    test('channels', () {
      expect(
        () => Lame.encode(pcm, sampleRate: 44100, channels: 3),
        throwsArgumentError,
      );
    });
    test('a partial frame', () {
      expect(
        () => Lame.encode(Int16List(3), sampleRate: 44100, channels: 2),
        throwsArgumentError,
      );
    });
    test('sample rate', () {
      expect(
        () => Lame.encode(pcm, sampleRate: 0, channels: 1),
        throwsRangeError,
      );
    });
    test('bitrate', () {
      expect(
        () => Lame.encode(
          pcm,
          sampleRate: 44100,
          channels: 1,
          bitrate: const Mp3Bitrate.constant(400),
        ),
        throwsRangeError,
      );
      expect(
        () => Lame.encode(
          pcm,
          sampleRate: 44100,
          channels: 1,
          bitrate: const Mp3Bitrate.variable(10),
        ),
        throwsRangeError,
      );
    });
    test('quality', () {
      expect(
        () => Lame.encode(pcm, sampleRate: 44100, channels: 1, quality: -1),
        throwsRangeError,
      );
    });
  });
}
