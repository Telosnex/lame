/// @docImport 'lame.dart';
library;

/// Browser settings of [Lame]. Native platforms ignore them.
abstract final class LameWeb {
  /// Where to load `lame_ffi_worker.mjs` from.
  ///
  /// When null, `kiln/lame_ffi/lame_ffi_worker.mjs`, resolved against the
  /// document base URI. A Flutter web build gets the web files there from
  /// the lame_ffi build hook (kiln ADR 002).
  ///
  /// Other embedders, such as `dart compile js` sites and browser tests, must
  /// serve this package's `lib/web/` directory from the same origin and set
  /// this to its `lame_ffi_worker.mjs`. The worker loads `lame_ffi_module.mjs`
  /// and `lame_ffi_module.wasm` beside it. The query `v=<webRuntimeVersion>`
  /// is added unless the URI has a `v` query, and the worker passes it on.
  ///
  /// Set it before the first encode: the Worker keeps its URL.
  static Uri? workerUri;
}
