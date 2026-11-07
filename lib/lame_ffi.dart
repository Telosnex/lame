/// MP3 encoding with LAME 3.100.
///
/// Native platforms load the library through `dart:ffi`. Browsers run the
/// same C code as WebAssembly in a Web Worker. [Lame.encode] is the same on
/// both.
library;

export 'src/lame.dart' show Lame;
export 'src/models.dart' show LameException, Mp3Bitrate;
export 'src/web_config.dart' show LameWeb;
