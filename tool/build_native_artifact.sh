#!/usr/bin/env bash
# Builds the lame library for one target: LAME 3.100's libmp3lame and the
# shim in src/, as one shared library that exports only the lame_shim_* ABI.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"

lame_version=3.100
lame_archive=lame_3.100.orig.tar.gz
lame_sha256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e

usage() {
  cat >&2 <<'USAGE'
Usage: tool/build_native_artifact.sh <target>

Targets:
  macos-arm64              macos-x64
  ios-arm64-iphoneos       ios-arm64-iphonesimulator
  ios-x64-iphonesimulator
  android-arm              android-arm64              android-x64
  linux-arm64              linux-x64
  windows-arm64            windows-x64

Apple targets need Xcode. Android targets need ANDROID_NDK_HOME (or the NDK
in the Android SDK). Linux and Windows targets build on Linux, or with
tool/build_native_linux_docker.sh and tool/build_native_windows_docker.sh.

hook/build.dart runs this script for a source build and sets:
  LAME_SHIM_LAME_SOURCE  the directory of lame_3.100.orig.tar.gz
                        (default: third_party, from tool/fetch_native_sources.sh)
  LAME_SHIM_BUILD_ROOT   intermediate files (default: build/native/<target>)
  LAME_SHIM_OUTPUT       the library (default: build/native_artifacts/<target>/<file>)
  LAME_SHIM_MACOS_VERSION, LAME_SHIM_IOS_VERSION, LAME_SHIM_ANDROID_API
                        minimum OS (defaults: 12.0, 13.0, 24)
USAGE
  exit 64
}

lame_source="${LAME_SHIM_LAME_SOURCE:-$root/third_party}"
macos_version="${LAME_SHIM_MACOS_VERSION:-12.0}"
ios_version="${LAME_SHIM_IOS_VERSION:-13.0}"

os=
artifact_arch=
cc=
strip_tool=
# -ffp-contract=off: no fused multiply-add, which Clang uses on arm64 and not on
# x64 or Wasm. Every target then computes the same MP3 bytes.
cflags=(-std=gnu99 -O3 -ffp-contract=off -fPIC -fvisibility=hidden)
ldflags=()
output_name=
shared_flags=()
system_libraries=(-lm)

case "$target" in
  macos-arm64|macos-x64|ios-arm64-iphoneos|ios-arm64-iphonesimulator|ios-x64-iphonesimulator)
    case "$target" in
      *-x64*) artifact_arch=x86_64 ;;
      *) artifact_arch=arm64 ;;
    esac
    case "$target" in
      macos-*)
        os=macos; sdk=macosx; minimum_flag=-mmacosx-version-min=$macos_version ;;
      *-iphoneos)
        os=ios; sdk=iphoneos; minimum_flag=-miphoneos-version-min=$ios_version ;;
      *)
        os=ios; sdk=iphonesimulator
        minimum_flag=-mios-simulator-version-min=$ios_version ;;
    esac
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cc="$(xcrun --sdk "$sdk" -f clang)"
    strip_tool="$(xcrun --sdk "$sdk" -f strip)"
    cflags+=(-arch "$artifact_arch" "$minimum_flag" -isysroot "$sdk_path")
    ldflags=(-arch "$artifact_arch" "$minimum_flag" -isysroot "$sdk_path")
    output_name=liblame.dylib
    shared_flags=(
      -dynamiclib -Wl,-dead_strip -Wl,-headerpad_max_install_names
      -Wl,-install_name,@rpath/liblame.dylib
    )
    ;;
  android-arm|android-arm64|android-x64)
    os=android
    android_api="${LAME_SHIM_ANDROID_API:-24}"
    ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [[ -z "$ndk" ]]; then
      ndk="$HOME/Library/Android/sdk/ndk/28.2.13676358"
    fi
    [[ -d "$ndk" ]] || { echo 'Set ANDROID_NDK_HOME to an Android NDK.' >&2; exit 1; }
    case "$(uname -s)" in
      Darwin) ndk_host=darwin-x86_64 ;;
      Linux) ndk_host=linux-x86_64 ;;
      *) echo 'Android libraries build only on macOS or Linux.' >&2; exit 1 ;;
    esac
    llvm_bin="$ndk/toolchains/llvm/prebuilt/$ndk_host/bin"
    case "$target" in
      android-arm) artifact_arch=arm; compiler_prefix=armv7a-linux-androideabi ;;
      android-arm64) artifact_arch=aarch64; compiler_prefix=aarch64-linux-android ;;
      android-x64) artifact_arch=x86_64; compiler_prefix=x86_64-linux-android ;;
    esac
    cc="$llvm_bin/${compiler_prefix}${android_api}-clang"
    strip_tool="$llvm_bin/llvm-strip"
    output_name=liblame.so
    shared_flags=(-shared -Wl,-soname,liblame.so -Wl,-z,max-page-size=16384)
    ;;
  linux-arm64|linux-x64)
    os=linux
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Linux libraries build on Linux (use tool/build_native_linux_docker.sh).' >&2
      exit 1
    }
    if [[ "$target" == linux-arm64 ]]; then
      artifact_arch=aarch64
      cc="${CC:-aarch64-linux-gnu-gcc}"
      strip_tool="${STRIP:-aarch64-linux-gnu-strip}"
    else
      artifact_arch=x86_64
      cc="${CC:-gcc}"
      strip_tool="${STRIP:-strip}"
    fi
    output_name=liblame.so
    shared_flags=(-shared -Wl,-soname,liblame.so -Wl,-z,relro,-z,now)
    ;;
  windows-x64|windows-arm64)
    os=windows
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Windows libraries are cross-built on Linux (use tool/build_native_windows_docker.sh).' >&2
      exit 1
    }
    output_name=lame.dll
    if [[ "$target" == windows-x64 ]]; then
      artifact_arch=x86_64
      cc="${CC:-x86_64-w64-mingw32-gcc}"
      strip_tool="${STRIP:-x86_64-w64-mingw32-strip}"
      shared_flags=(-shared -static-libgcc -Wl,--no-insert-timestamp)
    else
      # GCC has no Windows arm64 target: the pinned llvm-mingw (UCRT).
      artifact_arch=aarch64
      cc="${CC:-aarch64-w64-mingw32-clang}"
      strip_tool="${STRIP:-aarch64-w64-mingw32-strip}"
      shared_flags=(-shared -Wl,--no-insert-timestamp)
    fi
    # Windows has no -fPIC.
    cflags=(-std=gnu99 -O3 -ffp-contract=off)
    ;;
  *) usage ;;
esac

for tool in "$cc" "$strip_tool"; do
  command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }
done

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

build_root="${LAME_SHIM_BUILD_ROOT:-$root/build/native/$target}"
artifact="${LAME_SHIM_OUTPUT:-$root/build/native_artifacts/$target/$output_name}"
mkdir -p "$build_root" "$(dirname "$artifact")"

# LAME: the pinned release archive, unpacked once per build directory.
lame="$build_root/lame-$lame_version"
if [[ ! -f "$lame/.lame_shim_complete" ]]; then
  archive="$lame_source/$lame_archive"
  [[ -f "$archive" ]] || {
    echo "$archive is missing: run tool/fetch_native_sources.sh" >&2; exit 1;
  }
  actual="$(sha256_of "$archive")"
  [[ "$actual" == "$lame_sha256" ]] || {
    echo "$archive: sha256 $actual, expected $lame_sha256" >&2; exit 1;
  }
  rm -rf "$lame" "$lame.partial"
  mkdir -p "$lame.partial"
  tar -xzf "$archive" -C "$lame.partial" --strip-components=1
  mv "$lame.partial" "$lame"
  touch "$lame/.lame_shim_complete"
fi

# libmp3lame without the decoder interface (no HAVE_MPGLIB) and without the
# SSE code of vector/. src/lame_config/config.h replaces configure.
sources=()
for file in "$lame"/libmp3lame/*.c; do
  [[ "$(basename "$file")" == mpglib_interface.c ]] && continue
  sources+=("$file")
done
sources+=("$root/src/lame_shim.c")

exports="$build_root/exports.txt"
if [[ "$os" == macos || "$os" == ios ]]; then prefix=_; else prefix=; fi
sed -n 's/^  \(lame_shim_[a-z0-9_]*\)$/\1/p' "$root/src/exports_windows.def" \
  | sed "s/^/$prefix/" > "$exports"

export_flags=()
case "$os" in
  macos|ios) export_flags=(-Wl,-exported_symbols_list,"$exports") ;;
  windows) export_flags=("$root/src/exports_windows.def") ;;
  *)
    version_script="$build_root/exports.map"
    {
      echo 'LAME_SHIM_1 {'
      echo '  global:'
      sed 's/^/    /; s/$/;/' "$exports"
      echo '  local: *;'
      echo '};'
    } > "$version_script"
    export_flags=(-Wl,--version-script="$version_script")
    ;;
esac

# -w: LAME's warnings are upstream's. The shim builds with -Werror in
# tool/kiln/test_build.dart.
"$cc" "${shared_flags[@]}" "${cflags[@]}" -w -DHAVE_CONFIG_H \
  -I"$root/src/lame_config" -I"$root/src" -I"$lame/include" \
  -I"$lame/libmp3lame" "${sources[@]}" ${ldflags[@]+"${ldflags[@]}"} \
  "${system_libraries[@]}" "${export_flags[@]}" -o "$artifact"
"$strip_tool" -x "$artifact" 2>/dev/null || "$strip_tool" --strip-unneeded "$artifact"

# The architecture, the dependencies and the exports.
actual_exports="$build_root/actual_exports.txt"
case "$os" in
  macos|ios)
    actual_arch="$(lipo -archs "$artifact")"
    [[ "$actual_arch" == "$artifact_arch" ]] || {
      echo "Wrong architecture: expected $artifact_arch, got $actual_arch" >&2; exit 1;
    }
    if otool -L "$artifact" | tail -n +2 | grep -v -E '/usr/lib/libSystem|@rpath/liblame'; then
      echo 'The library has a dependency other than libSystem.' >&2; exit 1;
    fi
    nm -gU "$artifact" | awk '{print $3}' | grep '^_lame_shim_' | sort > "$actual_exports"
    ;;
  android|linux)
    if [[ "$os" == android ]]; then
      readelf="$llvm_bin/llvm-readelf"; nm_tool="$llvm_bin/llvm-nm"
    else
      readelf="${READELF:-readelf}"; nm_tool="${NM:-nm}"
    fi
    machine="$("$readelf" -h "$artifact" | awk -F: '/Machine:/ {print $2}')"
    case "$artifact_arch" in
      arm) expected_machine=ARM ;;
      aarch64) expected_machine=AArch64 ;;
      x86_64) expected_machine='X86-64' ;;
    esac
    [[ "$machine" == *"$expected_machine"* ]] || {
      echo "Wrong machine: expected $expected_machine, got$machine" >&2; exit 1;
    }
    needed="$("$readelf" -d "$artifact" | awk '/NEEDED/ {print $NF}' | tr -d '[]' | sort | tr '\n' ' ')"
    for library in $needed; do
      case "$library" in
        libc.so*|libm.so*|libdl.so*) ;;
        *) echo "Unexpected dependency: $library" >&2; exit 1 ;;
      esac
    done
    "$nm_tool" -D --defined-only "$artifact" | awk '{print $3}' \
      | sed 's/@@.*//' | grep '^lame_shim_' | sort > "$actual_exports"
    ;;
  windows)
    objdump_tool="${OBJDUMP:-$(command -v llvm-objdump || command -v x86_64-w64-mingw32-objdump)}"
    "$objdump_tool" -p "$artifact" > "$build_root/pe.txt"
    case "$artifact_arch" in
      x86_64) grep -Eq 'file format (pei-x86-64|coff-x86-64)' "$build_root/pe.txt" ;;
      aarch64) grep -Eq 'file format (pei-aarch64-little|coff-arm64)' "$build_root/pe.txt" ;;
    esac || { echo "Wrong PE machine for $target." >&2; exit 1; }
    if grep -Ei 'DLL Name:.*(libgcc|libstdc|winpthread|libc\+\+|libunwind)' "$build_root/pe.txt"; then
      echo 'The DLL needs a compiler runtime DLL.' >&2; exit 1;
    fi
    awk '/\[[[:space:]]*[0-9]+\] lame_shim_/ {print $NF} /^ +[0-9]+ +0x[0-9a-f]+ +lame_shim_/ {print $NF}' \
      "$build_root/pe.txt" | sort -u > "$actual_exports"
    ;;
esac
sort "$exports" > "$build_root/expected_exports.txt"
if ! diff -u "$build_root/expected_exports.txt" "$actual_exports"; then
  echo 'The exports do not match src/exports_windows.def.' >&2
  exit 1
fi

echo "Built $artifact"
echo "target=$target"
echo "sha256=$(sha256_of "$artifact")"
echo "size=$(wc -c < "$artifact" | tr -d ' ')"
