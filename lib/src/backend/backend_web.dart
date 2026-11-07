import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../models.dart';
import '../web_config.dart';
import '../web_runtime.g.dart';
import 'backend.dart';

/// Where the lame_ffi build hook installs the worker in a Flutter web app
/// (kiln ADR 002 D1).
const defaultWorkerUrl = 'kiln/lame_ffi/lame_ffi_worker.mjs';

/// [workerUri] resolved against [baseUri], with the query
/// `v=<webRuntimeVersion>` unless it has a `v` query (kiln ADR 002 D7).
Uri resolveWorkerUrl(String baseUri, Uri? workerUri) {
  final resolved = Uri.parse(
    baseUri,
  ).resolveUri(workerUri ?? Uri.parse(defaultWorkerUrl));
  if (resolved.queryParameters.containsKey('v')) return resolved;
  return resolved.replace(
    queryParameters: {...resolved.queryParameters, 'v': webRuntimeVersion},
  );
}

Future<LameBackend> loadBackend() async {
  final backend = _WebBackend(
    resolveWorkerUrl(_baseUri, LameWeb.workerUri).toString(),
  );
  final result = _BuildInfoResult._(
    await backend._request(
      (id) => _Request(id: id, operation: 'buildInfo'),
      const [],
    ),
  );
  backend.buildInfo = result.buildInfo;
  return backend;
}

/// The document base URI on a page, the script URI in a worker.
String get _baseUri => _document?.baseURI ?? _location.href;

/// One module Worker. A Worker that fails is replaced at the next request.
final class _WebBackend implements LameBackend {
  _WebBackend(this._workerUrl);

  final String _workerUrl;
  _Worker? _worker;
  final _pending = <int, Completer<JSObject>>{};
  int _nextId = 0;

  @override
  late final String buildInfo;

  @override
  Future<Uint8List> encode(
    Int16List pcm, {
    required int frameCount,
    required int channels,
    required int sampleRate,
    required int mode,
    required int value,
    required int quality,
  }) async {
    // A copy: the transfer detaches it, and the caller keeps its list.
    final buffer = Uint8List.fromList(
      pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
    ).toJS.buffer;
    final result = _EncodeResult._(
      await _request(
        (id) => _Request(
          id: id,
          operation: 'encode',
          pcm: buffer,
          frameCount: frameCount,
          channels: channels,
          sampleRate: sampleRate,
          mode: mode,
          value: value,
          quality: quality,
        ),
        [buffer],
      ),
    );
    return result.bytes.toDart;
  }

  Future<JSObject> _request(
    _Request Function(int id) build,
    List<JSObject> transfer,
  ) {
    final worker = _worker ??= _start();
    final id = _nextId++;
    final completer = Completer<JSObject>();
    _pending[id] = completer;
    worker.postMessage(build(id), transfer.toJS);
    return completer.future;
  }

  _Worker _start() {
    final worker = _Worker(_workerUrl, _WorkerOptions(type: 'module'));
    worker.onmessage = ((_MessageEvent event) {
      final response = _Response._(event.data);
      final completer = _pending.remove(response.id);
      if (completer == null) return;
      final error = response.error;
      if (error != null) {
        completer.completeError(
          LameException(error.status ?? -4, error.message ?? 'lame_ffi error'),
        );
      } else {
        completer.complete(response.result!);
      }
    }).toJS;
    worker.onerror = ((_ErrorEvent event) {
      final detail = event.message;
      _fail(
        LameException(
          -100,
          'The lame_ffi worker failed to load from $_workerUrl'
          '${detail == null || detail.isEmpty ? '' : ': $detail'}. A Flutter '
          'web app gets it from the build hook; other embedders must serve '
          'package:lame_ffi/web/ and set LameWeb.workerUri.',
        ),
      );
    }).toJS;
    return worker;
  }

  void _fail(LameException error) {
    _worker?.terminate();
    _worker = null;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }
}

extension on JSUint8Array {
  external JSArrayBuffer get buffer;
}

extension type _Document._(JSObject _) implements JSObject {
  external String get baseURI;
}

@JS('document')
external _Document? get _document;

extension type _Location._(JSObject _) implements JSObject {
  external String get href;
}

@JS('location')
external _Location get _location;

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external _Worker(String scriptURL, _WorkerOptions options);
  external void postMessage(JSAny? message, JSArray<JSObject> transfer);
  external set onmessage(JSFunction value);
  external set onerror(JSFunction value);
  external void terminate();
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSObject get data;
}

extension type _ErrorEvent._(JSObject _) implements JSObject {
  external String? get message;
}

/// A request of lib/web/lame_ffi_worker.mjs.
extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({
    int id,
    String operation,
    JSArrayBuffer pcm,
    int frameCount,
    int channels,
    int sampleRate,
    int mode,
    int value,
    int quality,
  });
}

extension type _Response._(JSObject _) implements JSObject {
  external int get id;
  external JSObject? get result;
  external _Error? get error;
}

extension type _Error._(JSObject _) implements JSObject {
  external int? get status;
  external String? get message;
}

extension type _BuildInfoResult._(JSObject _) implements JSObject {
  external String get buildInfo;
}

extension type _EncodeResult._(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
}
