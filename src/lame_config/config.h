/* The LAME 3.100 build configuration of lame, in place of the one that
 * LAME's configure script makes. Every target is a C99 compiler with the
 * standard headers: Clang (Apple, Android NDK, llvm-mingw, Emscripten) and GCC
 * (Linux, MinGW-w64). The mpglib decoder, the frontend and the NASM and SSE
 * code are not built. */
#ifndef LAME_SHIM_LAME_CONFIG_H
#define LAME_SHIM_LAME_CONFIG_H

#define STDC_HEADERS 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1

#include <stdint.h>
typedef float ieee754_float32_t;
typedef double ieee754_float64_t;
typedef long double ieee854_float80_t;
#define HAVE_IEEE754_FLOAT32_T 1
#define HAVE_IEEE754_FLOAT64_T 1
#define HAVE_IEEE854_FLOAT80_T 1
#define HAVE_INT8_T 1
#define HAVE_INT16_T 1
#define HAVE_INT32_T 1
#define HAVE_INT64_T 1
#define HAVE_UINT8_T 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1

/* No HAVE_MPGLIB: the decoder is not part of this build. No
 * TAKEHIRO_IEEE754_HACK or USE_FAST_LOG: LAME's configure sets them only on x86
 * and PowerPC, and every target here runs the same portable code. */

#define PACKAGE "lame"
#define PACKAGE_NAME "lame"
#define PACKAGE_VERSION "3.100"
#define VERSION "3.100"

#endif
