// Copyright (c) 2026 Telosnex Inc. MIT License: see LICENSE.
//
// The C ABI of lame_ffi, the same for dart:ffi and the Wasm module. It uses
// only fixed-width types and an opaque buffer handle.
#ifndef LAME_FFI_H
#define LAME_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define LAME_FFI_EXPORT __declspec(dllexport)
#else
#define LAME_FFI_EXPORT __attribute__((visibility("default")))
#endif

// The ABI version. It changes with any change of this header.
#define LAME_FFI_ABI_VERSION 1

// Status codes. 0 is success; the others are negative.
#define LAME_FFI_OK 0
#define LAME_FFI_ERROR_INVALID_ARGUMENT -1
#define LAME_FFI_ERROR_OUT_OF_MEMORY -2
#define LAME_FFI_ERROR_UNSUPPORTED_CONFIG -3
#define LAME_FFI_ERROR_ENCODE_FAILED -4

// Bitrate modes of lame_ffi_encode_pcm16.
// Constant bitrate. value: the bitrate in kbit/s, for example 128.
#define LAME_FFI_MODE_CBR 0
// Variable bitrate. value: the VBR quality, 0 (best) to 9 (smallest).
#define LAME_FFI_MODE_VBR 1
// Average bitrate. value: the target bitrate in kbit/s, 8 to 320.
#define LAME_FFI_MODE_ABR 2

// Encoded MP3 bytes. lame_ffi_buffer_release frees it.
typedef struct lame_ffi_buffer lame_ffi_buffer;

// Returns LAME_FFI_ABI_VERSION of the built library.
LAME_FFI_EXPORT int32_t lame_ffi_abi_version(void);

// Returns the versions of the build, for example "lame_ffi 1, LAME 3.100".
// The string is static.
LAME_FFI_EXPORT const char *lame_ffi_build_info(void);

// Encodes 16-bit PCM to a complete MP3 stream.
//
// pcm holds frame_count frames of channel_count samples (1 or 2), interleaved
// for 2 channels. sample_rate is the input rate in Hz, 1 to 192000; LAME
// resamples it to an MP3 rate if it must. mode and value select the bitrate
// (LAME_FFI_MODE_*). quality is the algorithm quality, 0 (best, slowest) to 9
// (fastest); 2 is LAME's "high quality" preset.
//
// The stream has a Xing/LAME tag frame first, so players know its duration,
// and no ID3 tag. On success, *out is a new buffer and the result is
// LAME_FFI_OK. On failure, *out is NULL and the result is a status code.
LAME_FFI_EXPORT int32_t lame_ffi_encode_pcm16(
    const int16_t *pcm, uint32_t frame_count, uint32_t channel_count,
    uint32_t sample_rate, uint32_t mode, uint32_t value, uint32_t quality,
    lame_ffi_buffer **out);

// The bytes of buffer. Valid until lame_ffi_buffer_release.
LAME_FFI_EXPORT const uint8_t *lame_ffi_buffer_data(
    const lame_ffi_buffer *buffer);

// The number of bytes of buffer.
LAME_FFI_EXPORT uint32_t lame_ffi_buffer_length(const lame_ffi_buffer *buffer);

// Frees buffer. NULL is allowed.
LAME_FFI_EXPORT void lame_ffi_buffer_release(lame_ffi_buffer *buffer);

// A static English message for a status code.
LAME_FFI_EXPORT const char *lame_ffi_error_message(int32_t status);

#ifdef __cplusplus
}
#endif

#endif
