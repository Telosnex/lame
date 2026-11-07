import 'dart:typed_data';

/// What the native and the web backends implement.
abstract interface class LameBackend {
  String get buildInfo;

  /// Calls `lame_shim_encode_pcm16` with arguments that Lame.encode checked.
  Future<Uint8List> encode(
    Int16List pcm, {
    required int frameCount,
    required int channels,
    required int sampleRate,
    required int mode,
    required int value,
    required int quality,
  });
}
