#!/usr/bin/env bash
# Runs the C ABI test (tool/support/abi_boundary_test.c) against the iOS
# Simulator library.
# The library in build/native_artifacts/<target>/ is a local build of
# tool/build_native_artifact.sh, or else the released file
# (tool/prebuilt_artifacts.dart downloads it).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS/Xcode.' >&2; exit 1; }

case "$(uname -m)" in
  arm64) arch_name=arm64; target=ios-arm64-iphonesimulator; minimum=13.0 ;;
  x86_64) arch_name=x86_64; target=ios-x64-iphonesimulator; minimum=13.0 ;;
  *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac
artifact="$root/build/native_artifacts/$target/liblame.dylib"
[[ -f "$artifact" ]] || (cd "$root" && dart run tool/prebuilt_artifacts.dart "$target")

devices_json="$(xcrun simctl list devices available -j)"
read -r udid initial_state < <(python3 -c '
import json, re, sys
obj=json.load(sys.stdin); candidates=[]
for runtime, devices in obj["devices"].items():
  if "SimRuntime.iOS-" not in runtime: continue
  version=tuple(int(x) for x in re.findall(r"\d+", runtime.rsplit("iOS-",1)[-1]))
  for device in devices:
    if device.get("isAvailable", True):
      candidates.append((device.get("state")=="Booted",version,device))
if not candidates: raise SystemExit("No available iOS simulator")
candidates.sort(key=lambda x:(x[0],x[1]),reverse=True)
d=candidates[0][2]; print(d["udid"],d.get("state","Shutdown"))
' <<<"$devices_json")
booted_here=false
cleanup() {
  if [[ "$booted_here" == true && "${LAME_KEEP_SIMULATOR_BOOTED:-0}" != 1 ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if [[ "$initial_state" != Booted ]]; then xcrun simctl boot "$udid"; booted_here=true; fi
xcrun simctl bootstatus "$udid" -b

build="$root/build/ios-simulator-boundary"
rm -rf "$build" && mkdir -p "$build"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -std=c11 -O2 -Wall -Wextra -Werror \
  -arch "$arch_name" -mios-simulator-version-min="$minimum" -isysroot "$sdk" \
  -I"$root/src" "$root/tool/support/abi_boundary_test.c" "$artifact" \
  -Wl,-rpath,@executable_path -o "$build/abi_boundary_test"
cp "$artifact" "$build/liblame.dylib"
codesign -s - --force "$build/abi_boundary_test" \
  "$build/liblame.dylib" >/dev/null
xcrun simctl spawn "$udid" "$build/abi_boundary_test"
echo "PASS: $target library on simulator $udid"
