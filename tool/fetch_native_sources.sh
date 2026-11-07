#!/usr/bin/env bash
# Downloads the pinned LAME release of native_artifacts/sources.json into
# third_party/, for tool/build_native_artifact.sh outside the build hook.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
url=https://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz
sha256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
archive="$root/third_party/lame_3.100.orig.tar.gz"

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -f "$archive" && "$(sha256_of "$archive")" == "$sha256" ]]; then
  echo "LAME 3.100 already in third_party/"
  exit 0
fi
mkdir -p "$root/third_party"
curl -fsSL -o "$archive.partial" "$url"
actual="$(sha256_of "$archive.partial")"
[[ "$actual" == "$sha256" ]] || {
  rm -f "$archive.partial"
  echo "$url: sha256 $actual, expected $sha256" >&2
  exit 1
}
mv "$archive.partial" "$archive"
echo "Fetched LAME 3.100"
