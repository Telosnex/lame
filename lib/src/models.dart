/// @docImport 'lame.dart';
library;

/// How [Lame.encode] chooses the bitrate of each frame.
sealed class Mp3Bitrate {
  const Mp3Bitrate._();

  /// Constant bitrate: every frame is [kbps] kbit/s, 8 to 320. LAME uses the
  /// nearest bitrate that the output sample rate allows.
  const factory Mp3Bitrate.constant(int kbps) = ConstantBitrate;

  /// Variable bitrate: [quality] 0 gives the best sound and the largest file,
  /// 9 the smallest file. LAME's default is 4.
  const factory Mp3Bitrate.variable(int quality) = VariableBitrate;

  /// Average bitrate: the frames vary, and the stream averages about [kbps]
  /// kbit/s, 8 to 320.
  const factory Mp3Bitrate.average(int kbps) = AverageBitrate;
}

/// See [Mp3Bitrate.constant].
final class ConstantBitrate extends Mp3Bitrate {
  /// See [Mp3Bitrate.constant].
  const ConstantBitrate(this.kbps) : super._();

  /// The bitrate in kbit/s.
  final int kbps;

  @override
  String toString() => 'Mp3Bitrate.constant($kbps)';
}

/// See [Mp3Bitrate.variable].
final class VariableBitrate extends Mp3Bitrate {
  /// See [Mp3Bitrate.variable].
  const VariableBitrate(this.quality) : super._();

  /// The VBR quality, 0 (best) to 9 (smallest).
  final int quality;

  @override
  String toString() => 'Mp3Bitrate.variable($quality)';
}

/// See [Mp3Bitrate.average].
final class AverageBitrate extends Mp3Bitrate {
  /// See [Mp3Bitrate.average].
  const AverageBitrate(this.kbps) : super._();

  /// The target bitrate in kbit/s.
  final int kbps;

  @override
  String toString() => 'Mp3Bitrate.average($kbps)';
}

/// A failure of the native library or the Wasm module.
final class LameException implements Exception {
  /// A failure with the status code of `src/lame_shim.h`.
  const LameException(this.status, this.message);

  /// The status code: negative. -1 invalid argument, -2 out of memory, -3
  /// a configuration that LAME does not support, -4 an encode failure. -100
  /// and lower are failures to load the library or the Web Worker.
  final int status;

  /// An English description.
  final String message;

  @override
  String toString() => 'LameException($status): $message';
}

/// The C mode and value of [bitrate] (LAME_SHIM_MODE_* in `src/lame_shim.h`).
(int mode, int value) cModeOf(Mp3Bitrate bitrate) => switch (bitrate) {
  ConstantBitrate(:final kbps) => (0, kbps),
  VariableBitrate(:final quality) => (1, quality),
  AverageBitrate(:final kbps) => (2, kbps),
};
