// Copyright (c) 2026 Telosnex Inc. MIT License: see LICENSE.
//
// The shim over LAME's libmp3lame. LAME is under the GNU LGPL, version 2 or
// later: see NOTICES.
#include "lame_shim.h"

#include <stdlib.h>
#include <string.h>

#include "lame.h"

#define LAME_SHIM_STRINGIFY_(x) #x
#define LAME_SHIM_STRINGIFY(x) LAME_SHIM_STRINGIFY_(x)

// Frames per lame_encode_buffer call: bounds the work buffer.
#define LAME_SHIM_CHUNK_FRAMES 8192u
// The worst-case output of one call, from lame.h: 1.25 * frames + 7200.
#define LAME_SHIM_CHUNK_BOUND (LAME_SHIM_CHUNK_FRAMES + LAME_SHIM_CHUNK_FRAMES / 4u + 7200u)

struct lame_shim_buffer {
  uint8_t *data;
  uint32_t length;
  uint32_t capacity;
};

int32_t lame_shim_abi_version(void) { return LAME_SHIM_ABI_VERSION; }

const char *lame_shim_build_info(void) {
  return "lame " LAME_SHIM_STRINGIFY(LAME_SHIM_ABI_VERSION) ", LAME 3.100";
}

const char *lame_shim_error_message(int32_t status) {
  switch (status) {
    case LAME_SHIM_OK:
      return "OK";
    case LAME_SHIM_ERROR_INVALID_ARGUMENT:
      return "Invalid argument";
    case LAME_SHIM_ERROR_OUT_OF_MEMORY:
      return "Out of memory";
    case LAME_SHIM_ERROR_UNSUPPORTED_CONFIG:
      return "LAME does not support this configuration";
    case LAME_SHIM_ERROR_ENCODE_FAILED:
      return "LAME failed to encode";
    default:
      return "Unknown error";
  }
}

// Makes room for `extra` more bytes after the current length.
static int lame_shim_reserve(lame_shim_buffer *buffer, uint32_t extra) {
  if (extra > UINT32_MAX - buffer->length) return 0;
  uint32_t needed = buffer->length + extra;
  if (needed <= buffer->capacity) return 1;
  uint32_t capacity = buffer->capacity < 65536u ? 65536u : buffer->capacity;
  while (capacity < needed) {
    capacity = capacity > UINT32_MAX / 2u ? needed : capacity * 2u;
  }
  uint8_t *data = (uint8_t *)realloc(buffer->data, capacity);
  if (data == NULL) return 0;
  buffer->data = data;
  buffer->capacity = capacity;
  return 1;
}

static int lame_shim_configure(lame_global_flags *flags, uint32_t channel_count,
                              uint32_t sample_rate, uint32_t mode,
                              uint32_t value, uint32_t quality) {
  if (lame_set_num_channels(flags, (int)channel_count) < 0) return 0;
  if (lame_set_in_samplerate(flags, (int)sample_rate) < 0) return 0;
  if (lame_set_mode(flags, channel_count == 1 ? MONO : JOINT_STEREO) < 0) {
    return 0;
  }
  if (lame_set_quality(flags, (int)quality) < 0) return 0;
  if (lame_set_bWriteVbrTag(flags, 1) < 0) return 0;
  // No ID3 tags: the Xing/LAME tag must be the first frame.
  lame_set_write_id3tag_automatic(flags, 0);
  switch (mode) {
    case LAME_SHIM_MODE_CBR:
      return lame_set_VBR(flags, vbr_off) >= 0 &&
             lame_set_brate(flags, (int)value) >= 0;
    case LAME_SHIM_MODE_VBR:
      return lame_set_VBR(flags, vbr_default) >= 0 &&
             lame_set_VBR_quality(flags, (float)value) >= 0;
    case LAME_SHIM_MODE_ABR:
      return lame_set_VBR(flags, vbr_abr) >= 0 &&
             lame_set_VBR_mean_bitrate_kbps(flags, (int)value) >= 0;
    default:
      return 0;
  }
}

static int32_t lame_shim_encode_all(lame_global_flags *flags,
                                   const int16_t *pcm, uint32_t frame_count,
                                   uint32_t channel_count,
                                   lame_shim_buffer *buffer) {
  uint32_t done = 0;
  while (done < frame_count) {
    uint32_t frames = frame_count - done;
    if (frames > LAME_SHIM_CHUNK_FRAMES) frames = LAME_SHIM_CHUNK_FRAMES;
    if (!lame_shim_reserve(buffer, LAME_SHIM_CHUNK_BOUND)) {
      return LAME_SHIM_ERROR_OUT_OF_MEMORY;
    }
    const int16_t *chunk = pcm + (size_t)done * channel_count;
    unsigned char *out = buffer->data + buffer->length;
    int written =
        channel_count == 1
            ? lame_encode_buffer(flags, chunk, NULL, (int)frames, out,
                                 (int)LAME_SHIM_CHUNK_BOUND)
            : lame_encode_buffer_interleaved(flags, (short *)chunk,
                                             (int)frames, out,
                                             (int)LAME_SHIM_CHUNK_BOUND);
    if (written < 0) {
      return written == -2 ? LAME_SHIM_ERROR_OUT_OF_MEMORY
                           : LAME_SHIM_ERROR_ENCODE_FAILED;
    }
    buffer->length += (uint32_t)written;
    done += frames;
  }

  // lame_encode_flush writes at most 7200 bytes (lame.h).
  if (!lame_shim_reserve(buffer, 7200u)) return LAME_SHIM_ERROR_OUT_OF_MEMORY;
  int written =
      lame_encode_flush(flags, buffer->data + buffer->length, 7200);
  if (written < 0) return LAME_SHIM_ERROR_ENCODE_FAILED;
  buffer->length += (uint32_t)written;

  // The stream starts with a placeholder frame for the Xing/LAME tag: there
  // is no ID3v2 tag. Now that the totals are known, write the tag over it.
  size_t tag_size = lame_get_lametag_frame(flags, NULL, 0);
  if (tag_size > 0 && tag_size <= buffer->length) {
    if (lame_get_lametag_frame(flags, buffer->data, tag_size) != tag_size) {
      return LAME_SHIM_ERROR_ENCODE_FAILED;
    }
  }
  return LAME_SHIM_OK;
}

int32_t lame_shim_encode_pcm16(const int16_t *pcm, uint32_t frame_count,
                              uint32_t channel_count, uint32_t sample_rate,
                              uint32_t mode, uint32_t value, uint32_t quality,
                              lame_shim_buffer **out) {
  if (out == NULL) return LAME_SHIM_ERROR_INVALID_ARGUMENT;
  *out = NULL;
  if ((pcm == NULL && frame_count > 0) ||
      (channel_count != 1 && channel_count != 2) || sample_rate == 0 ||
      sample_rate > 192000u || quality > 9u ||
      (uint64_t)frame_count * channel_count > INT32_MAX) {
    return LAME_SHIM_ERROR_INVALID_ARGUMENT;
  }
  switch (mode) {
    case LAME_SHIM_MODE_CBR:
    case LAME_SHIM_MODE_ABR:
      if (value < 8u || value > 320u) return LAME_SHIM_ERROR_INVALID_ARGUMENT;
      break;
    case LAME_SHIM_MODE_VBR:
      if (value > 9u) return LAME_SHIM_ERROR_INVALID_ARGUMENT;
      break;
    default:
      return LAME_SHIM_ERROR_INVALID_ARGUMENT;
  }

  lame_shim_buffer *buffer =
      (lame_shim_buffer *)calloc(1, sizeof(lame_shim_buffer));
  if (buffer == NULL) return LAME_SHIM_ERROR_OUT_OF_MEMORY;
  lame_global_flags *flags = lame_init();
  if (flags == NULL) {
    free(buffer);
    return LAME_SHIM_ERROR_OUT_OF_MEMORY;
  }

  int32_t status = LAME_SHIM_OK;
  if (!lame_shim_configure(flags, channel_count, sample_rate, mode, value,
                          quality) ||
      lame_init_params(flags) < 0) {
    status = LAME_SHIM_ERROR_UNSUPPORTED_CONFIG;
  } else {
    status = lame_shim_encode_all(flags, pcm, frame_count, channel_count, buffer);
  }
  lame_close(flags);

  if (status != LAME_SHIM_OK) {
    lame_shim_buffer_release(buffer);
    return status;
  }
  *out = buffer;
  return LAME_SHIM_OK;
}

const uint8_t *lame_shim_buffer_data(const lame_shim_buffer *buffer) {
  return buffer == NULL ? NULL : buffer->data;
}

uint32_t lame_shim_buffer_length(const lame_shim_buffer *buffer) {
  return buffer == NULL ? 0 : buffer->length;
}

void lame_shim_buffer_release(lame_shim_buffer *buffer) {
  if (buffer == NULL) return;
  free(buffer->data);
  free(buffer);
}
