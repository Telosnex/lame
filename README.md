# lame

MP3 encoding with [LAME](https://lame.sourceforge.io/) 3.100 for Dart and
Flutter. Native platforms load LAME through `dart:ffi`. Browsers run the same
C code as WebAssembly in a Web Worker. Every platform encodes the same input
to the same bytes.

- Constant (CBR), variable (VBR) and average (ABR) bitrate.
- Mono or stereo 16-bit PCM, at any input rate from 1 Hz to 192 kHz. LAME
  resamples to an MP3 rate when it must.
- Each file starts with a Xing/LAME tag frame, so players know its duration.

## Usage

```dart
import 'package:lame/lame.dart';

final mp3 = await Lame.encode(
  pcm, // Int16List, interleaved for stereo
  sampleRate: 44100,
  channels: 2,
  bitrate: const Mp3Bitrate.variable(4),
);
```

`Lame.encode` runs on a helper isolate on native platforms, and in a Web
Worker in browsers. It does not block the caller's thread.

| Bitrate | Value |
|---|---|
| `Mp3Bitrate.constant(kbps)` | 8 to 320 kbit/s. The default is `constant(128)`. |
| `Mp3Bitrate.variable(quality)` | 0 (best sound, largest file) to 9 (smallest file). LAME's default is 4. |
| `Mp3Bitrate.average(kbps)` | 8 to 320 kbit/s, on average. |

`quality` is the algorithm quality, from 0 (best, slowest) to 9 (fastest).
The default is 2, LAME's "high quality" setting.

## Platforms

| Platform | Targets |
|---|---|
| Android | arm, arm64, x64. API 24 and later. |
| iOS | arm64 device, arm64 and x64 simulator. iOS 13 and later. |
| macOS | arm64, x64. macOS 12 and later. |
| Linux | arm64, x64. glibc 2.31 and later. |
| Windows | arm64, x64. Windows 10 and later. |
| Web | Chrome, Firefox and Safari, with dart2js or dart2wasm. |

The build hook downloads a prebuilt library for the target from the GitHub
release in `native_artifacts/prebuilt.json`, and checks its SHA-256. The
GitHub Actions workflow `kiln_release.yml` builds these libraries from the
package sources ([kiln](https://pub.dev/packages/kiln)). If the package
sources do not match the release, the hook builds the library from source. A
source build needs a C compiler for the target. Apple targets build on macOS.
Android targets build on macOS or Linux with the Android NDK. Linux and
Windows targets build on Linux.

### Web

A Flutter web build gets the web files from the build hook, in
`web/kiln/lame/`. The app needs no change.

Other web apps, for example `dart compile js` sites, must serve this
package's `lib/web/` directory from the same origin. Then set
`LameWeb.workerUri` to its `lame_worker.mjs` before the first encode.

## License

The Dart and C code of this package is under the MIT License (`LICENSE`).

The native and Wasm libraries include LAME, which is under the GNU Library
General Public License (LGPL), version 2 or later. `NOTICES` has the LAME
copyright notices and the license text. The app loads LAME, with the shim of
`src/`, as its own dynamic library or Wasm module. To replace it, build `tool/build_native_artifact.sh` or `tool/kiln/build_web.dart`
from the LAME sources of your choice. The build scripts pin the official LAME
3.100 release by SHA-256 (`native_artifacts/sources.json`).

An app that ships these libraries must obey the LGPL. For example, the app
must show the LAME notice, and it must let users replace the LAME library.
Flutter shows the package notices in `showLicensePage`.

## Development

```bash
# The native library for this host, then the VM tests:
dart test

# The web files (Emscripten 5.0.0), then the browser tests:
dart tool/kiln/build_web.dart --out /tmp/lame_web
dart run kiln:web install-dev --from /tmp/lame_web
dart tool/kiln/test_web.dart
```

`src/lame_shim.h` is the C ABI. After a change to it, run
`dart run ffigen --config ffigen.yaml`.
