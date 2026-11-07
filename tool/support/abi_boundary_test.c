// The C ABI test of the built library: tool/kiln/test_build.dart builds it
// with -Werror against src/lame_ffi.h and runs it beside the library.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lame_ffi.h"

static int failures = 0;

#define CHECK(condition)                                        \
  do {                                                          \
    if (!(condition)) {                                         \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
      failures++;                                               \
    }                                                           \
  } while (0)

static void check_stream(uint32_t channels, uint32_t mode, uint32_t value) {
  const uint32_t rate = 44100, frames = rate;
  int16_t *pcm = (int16_t *)malloc(sizeof(int16_t) * frames * channels);
  for (uint32_t i = 0; i < frames; i++) {
    for (uint32_t c = 0; c < channels; c++) {
      pcm[i * channels + c] =
          (int16_t)(sin(6.283185307179586 * (440.0 + 220.0 * c) * i / rate) * 8000);
    }
  }
  lame_ffi_buffer *buffer = NULL;
  int32_t status =
      lame_ffi_encode_pcm16(pcm, frames, channels, rate, mode, value, 2, &buffer);
  CHECK(status == LAME_FFI_OK);
  if (status == LAME_FFI_OK) {
    const uint8_t *data = lame_ffi_buffer_data(buffer);
    uint32_t length = lame_ffi_buffer_length(buffer);
    CHECK(length > 1000);
    CHECK(data[0] == 0xff && (data[1] & 0xe0) == 0xe0);
    int tagged = 0;
    for (uint32_t i = 0; i + 4 <= length && i < 256; i++) {
      if (memcmp(data + i, "Xing", 4) == 0 || memcmp(data + i, "Info", 4) == 0) {
        tagged = 1;
      }
    }
    CHECK(tagged);
  }
  lame_ffi_buffer_release(buffer);
  free(pcm);
}

int main(void) {
  CHECK(lame_ffi_abi_version() == LAME_FFI_ABI_VERSION);
  CHECK(strcmp(lame_ffi_build_info(), "lame_ffi 1, LAME 3.100") == 0);
  CHECK(strcmp(lame_ffi_error_message(LAME_FFI_OK), "OK") == 0);

  check_stream(1, LAME_FFI_MODE_CBR, 128);
  check_stream(2, LAME_FFI_MODE_VBR, 4);
  check_stream(2, LAME_FFI_MODE_ABR, 96);

  lame_ffi_buffer *buffer = (lame_ffi_buffer *)&failures;
  CHECK(lame_ffi_encode_pcm16(NULL, 0, 3, 44100, 0, 128, 2, &buffer) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  CHECK(buffer == NULL);
  CHECK(lame_ffi_encode_pcm16(NULL, 1, 1, 44100, 0, 128, 2, &buffer) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  CHECK(lame_ffi_encode_pcm16(NULL, 0, 1, 44100, 0, 400, 2, &buffer) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  CHECK(lame_ffi_encode_pcm16(NULL, 0, 1, 44100, 1, 10, 2, &buffer) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  CHECK(lame_ffi_encode_pcm16(NULL, 0, 1, 44100, 7, 128, 2, &buffer) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  CHECK(lame_ffi_encode_pcm16(NULL, 0, 1, 44100, 0, 128, 2, NULL) ==
        LAME_FFI_ERROR_INVALID_ARGUMENT);
  lame_ffi_buffer_release(NULL);

  if (failures) {
    fprintf(stderr, "%d failures\n", failures);
    return 1;
  }
  printf("lame_ffi ABI boundary test passed\n");
  return 0;
}
