import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:lame/lame.dart';

/// Encodes two seconds of a stereo tone as a VBR MP3.
Future<void> main() async {
  const sampleRate = 44100;
  final pcm = Int16List(sampleRate * 2 * 2);
  for (var i = 0; i < pcm.length ~/ 2; i++) {
    pcm[2 * i] = (sin(2 * pi * 440 * i / sampleRate) * 8000).round();
    pcm[2 * i + 1] = (sin(2 * pi * 660 * i / sampleRate) * 8000).round();
  }

  final mp3 = await Lame.encode(
    pcm,
    sampleRate: sampleRate,
    channels: 2,
    bitrate: const Mp3Bitrate.variable(4),
  );
  File('tone.mp3').writeAsBytesSync(mp3);
  print('${await Lame.buildInfo}: wrote ${mp3.length} bytes to tone.mp3');
}
