// The C ABI test of the built library. tool/kiln/test_build.dart runs it
// after a release build, and tool/support/test_android_artifact.sh and
// tool/support/test_ios_simulator_artifact.sh run it on a device. It is built with
// -Werror against src/lame_shim.h and runs beside the library.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lame_shim.h"

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
  lame_shim_buffer *buffer = NULL;
  int32_t status =
      lame_shim_encode_pcm16(pcm, frames, channels, rate, mode, value, 2, &buffer);
  CHECK(status == LAME_SHIM_OK);
  if (status == LAME_SHIM_OK) {
    const uint8_t *data = lame_shim_buffer_data(buffer);
    uint32_t length = lame_shim_buffer_length(buffer);
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
  lame_shim_buffer_release(buffer);
  free(pcm);
}

// FNV-1a, 64 bits.
static uint64_t fnv1a(const uint8_t *data, uint32_t length) {
  uint64_t hash = 0xcbf29ce484222325ull;
  for (uint32_t i = 0; i < length; i++) {
    hash = (hash ^ data[i]) * 0x100000001b3ull;
  }
  return hash;
}

// The build turns off fused multiply-add, so every target encodes the same
// bytes. A change of a digest is a change of the encoder's output, or a
// target that computes differently.
static void check_digest(uint32_t mode, uint32_t value, uint64_t expected) {
  const uint32_t rate = 44100, frames = rate;
  int16_t *pcm = (int16_t *)malloc(sizeof(int16_t) * frames * 2);
  uint32_t state = 7;
  for (uint32_t i = 0; i < frames * 2; i++) {
    state = state * 1664525u + 1013904223u;
    pcm[i] = (int16_t)((int32_t)((i * 37u) % 12001u) - 6000 +
                       (int32_t)(state >> 22) - 512);
  }
  lame_shim_buffer *buffer = NULL;
  int32_t status =
      lame_shim_encode_pcm16(pcm, frames, 2, rate, mode, value, 2, &buffer);
  CHECK(status == LAME_SHIM_OK);
  if (status == LAME_SHIM_OK) {
    uint64_t hash = fnv1a(lame_shim_buffer_data(buffer),
                          lame_shim_buffer_length(buffer));
    if (hash != expected) {
      fprintf(stderr, "mode %u value %u: digest %016llx, expected %016llx\n",
              mode, value, (unsigned long long)hash,
              (unsigned long long)expected);
      failures++;
    }
  }
  lame_shim_buffer_release(buffer);
  free(pcm);
}

int main(void) {
  CHECK(lame_shim_abi_version() == LAME_SHIM_ABI_VERSION);
  CHECK(strcmp(lame_shim_build_info(), "lame 1, LAME 3.100") == 0);
  CHECK(strcmp(lame_shim_error_message(LAME_SHIM_OK), "OK") == 0);

  check_stream(1, LAME_SHIM_MODE_CBR, 128);
  check_stream(2, LAME_SHIM_MODE_VBR, 4);
  check_stream(2, LAME_SHIM_MODE_ABR, 96);

  check_digest(LAME_SHIM_MODE_CBR, 128, 0x19c24989dae6fb3eull);
  check_digest(LAME_SHIM_MODE_VBR, 4, 0x1806b78e2ba7cedeull);
  check_digest(LAME_SHIM_MODE_ABR, 96, 0x46b8576b0965daecull);

  lame_shim_buffer *buffer = (lame_shim_buffer *)&failures;
  CHECK(lame_shim_encode_pcm16(NULL, 0, 3, 44100, 0, 128, 2, &buffer) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  CHECK(buffer == NULL);
  CHECK(lame_shim_encode_pcm16(NULL, 1, 1, 44100, 0, 128, 2, &buffer) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  CHECK(lame_shim_encode_pcm16(NULL, 0, 1, 44100, 0, 400, 2, &buffer) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  CHECK(lame_shim_encode_pcm16(NULL, 0, 1, 44100, 1, 10, 2, &buffer) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  CHECK(lame_shim_encode_pcm16(NULL, 0, 1, 44100, 7, 128, 2, &buffer) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  CHECK(lame_shim_encode_pcm16(NULL, 0, 1, 44100, 0, 128, 2, NULL) ==
        LAME_SHIM_ERROR_INVALID_ARGUMENT);
  lame_shim_buffer_release(NULL);

  if (failures) {
    fprintf(stderr, "%d failures\n", failures);
    return 1;
  }
  printf("lame ABI boundary test passed\n");
  return 0;
}
