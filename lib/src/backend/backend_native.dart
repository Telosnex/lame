import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../lame_bindings_generated.dart' as native;
import '../models.dart';
import 'backend.dart';

Future<LameBackend> loadBackend() async {
  final int abiVersion;
  try {
    abiVersion = native.lame_shim_abi_version();
  } on ArgumentError catch (error) {
    // @Native lookups throw ArgumentError when the code asset is missing.
    throw LameException(-100, 'The lame library did not load: $error');
  }
  if (abiVersion != native.LAME_SHIM_ABI_VERSION) {
    throw LameException(
      -101,
      'lame ABI mismatch: Dart expects ${native.LAME_SHIM_ABI_VERSION}, '
      'the library has $abiVersion',
    );
  }
  return _NativeBackend(
    native.lame_shim_build_info().cast<Utf8>().toDartString(),
  );
}

final class _NativeBackend implements LameBackend {
  const _NativeBackend(this.buildInfo);

  @override
  final String buildInfo;

  @override
  Future<Uint8List> encode(
    Int16List pcm, {
    required int frameCount,
    required int channels,
    required int sampleRate,
    required int mode,
    required int value,
    required int quality,
  }) => Isolate.run(
    () => _encode(pcm, frameCount, channels, sampleRate, mode, value, quality),
  );
}

Uint8List _encode(
  Int16List pcm,
  int frameCount,
  int channels,
  int sampleRate,
  int mode,
  int value,
  int quality,
) {
  final input = malloc<Int16>(pcm.isEmpty ? 1 : pcm.length);
  final out = calloc<Pointer<native.lame_shim_buffer>>();
  try {
    input.asTypedList(pcm.length).setAll(0, pcm);
    final status = native.lame_shim_encode_pcm16(
      input,
      frameCount,
      channels,
      sampleRate,
      mode,
      value,
      quality,
      out,
    );
    if (status != native.LAME_SHIM_OK) {
      throw LameException(
        status,
        native.lame_shim_error_message(status).cast<Utf8>().toDartString(),
      );
    }
    final buffer = out.value;
    try {
      final length = native.lame_shim_buffer_length(buffer);
      return Uint8List.fromList(
        native.lame_shim_buffer_data(buffer).asTypedList(length),
      );
    } finally {
      native.lame_shim_buffer_release(buffer);
    }
  } finally {
    calloc.free(out);
    malloc.free(input);
  }
}
