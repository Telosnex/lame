import 'dart:typed_data';

import 'backend/backend.dart';
import 'backend/backend_stub.dart'
    if (dart.library.ffi) 'backend/backend_native.dart'
    if (dart.library.js_interop) 'backend/backend_web.dart'
    as platform;
import 'models.dart';

/// MP3 encoding with LAME 3.100.
///
/// Native platforms encode on a helper isolate, and browsers in a Web
/// Worker, so a call does not block the caller's thread.
abstract final class Lame {
  static Future<LameBackend>? _backend;

  static Future<LameBackend> _getBackend() =>
      _backend ??= platform.loadBackend().catchError((Object error) {
        // A failed Worker load or ABI check must not stay cached.
        _backend = null;
        throw error;
      });

  /// The versions of the library, for example `lame 1, LAME 3.100`.
  static Future<String> get buildInfo async => (await _getBackend()).buildInfo;

  /// Encodes 16-bit PCM to a complete MP3 file.
  ///
  /// [pcm] holds samples of [channels] channels (1 or 2), interleaved for 2.
  /// [sampleRate] is the input rate in Hz, 1 to 192000. LAME resamples to an
  /// MP3 rate when it must, for example when a low bitrate needs a lower
  /// rate.
  ///
  /// [quality] is the algorithm quality, 0 (best and slowest) to 9 (fastest).
  /// 2 is LAME's "high quality" setting.
  ///
  /// The file starts with a Xing/LAME tag frame, so players know its
  /// duration. It has no ID3 tag.
  ///
  /// Throws [ArgumentError] for an invalid argument, and [LameException] if
  /// LAME fails or the library does not load.
  static Future<Uint8List> encode(
    Int16List pcm, {
    required int sampleRate,
    required int channels,
    Mp3Bitrate bitrate = const Mp3Bitrate.constant(128),
    int quality = 2,
  }) async {
    if (channels != 1 && channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 1 or 2');
    }
    if (pcm.length % channels != 0) {
      throw ArgumentError.value(
        pcm.length,
        'pcm.length',
        'must be a multiple of channels ($channels)',
      );
    }
    RangeError.checkValueInInterval(sampleRate, 1, 192000, 'sampleRate');
    RangeError.checkValueInInterval(quality, 0, 9, 'quality');
    switch (bitrate) {
      case ConstantBitrate(:final kbps) || AverageBitrate(:final kbps):
        RangeError.checkValueInInterval(kbps, 8, 320, 'bitrate.kbps');
      case VariableBitrate(quality: final vbr):
        RangeError.checkValueInInterval(vbr, 0, 9, 'bitrate.quality');
    }
    final (mode, value) = cModeOf(bitrate);
    return (await _getBackend()).encode(
      pcm,
      frameCount: pcm.length ~/ channels,
      channels: channels,
      sampleRate: sampleRate,
      mode: mode,
      value: value,
      quality: quality,
    );
  }
}
