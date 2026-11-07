// The lame Web Worker: it owns one instance of lame_module.wasm and
// runs one request at a time. lib/src/backend/backend_web.dart sends the
// requests.
//
// The query of this Worker URL holds the web version of the package (kiln
// ADR 002 D7). The module and the Wasm file load with the same query, so a
// browser does not combine files of different versions.

// Must match LAME_SHIM_ABI_VERSION in src/lame_shim.h.
const ABI_VERSION = 1;

const assetVersion = new URL(import.meta.url).search;

// Messages that arrive while the module loads have no handler yet. Keep
// them, and dispatch them again at the end of this module.
const earlyMessages = [];
self.onmessage = ({data}) => earlyMessages.push(data);

function versionedSibling(path) {
  const url = new URL(path, import.meta.url);
  url.search = assetVersion;
  return url.href;
}

const {default: createModule} = await import(
  versionedSibling('./lame_module.mjs')
);

let modulePromise;

async function getModule() {
  const module = await (modulePromise ??= createModule({
    // Emscripten fetches the Wasm file itself: give it the same query.
    locateFile: (path) => versionedSibling(path),
  }));
  const abi = module._lame_shim_abi_version();
  if (abi !== ABI_VERSION) {
    throw Object.assign(
      new Error(`lame ABI mismatch: expected ${ABI_VERSION}, got ${abi}`),
      {status: -101},
    );
  }
  return module;
}

// Mirrors lib/src/backend/backend_native.dart: copy the input in, call the
// C ABI once, copy the output out, free the C memory.
function encode(module, request) {
  const pcm = new Uint8Array(request.pcm);
  const input = module._malloc(Math.max(pcm.byteLength, 2));
  const out = module._malloc(4);
  let buffer = 0;
  try {
    module.HEAPU8.set(pcm, input);
    module.HEAPU32[out >>> 2] = 0;
    const status = module._lame_shim_encode_pcm16(
      input,
      request.frameCount,
      request.channels,
      request.sampleRate,
      request.mode,
      request.value,
      request.quality,
      out,
    );
    if (status !== 0) {
      const message = module.UTF8ToString(module._lame_shim_error_message(status));
      throw Object.assign(new Error(message), {status});
    }
    buffer = module.HEAPU32[out >>> 2];
    const data = module._lame_shim_buffer_data(buffer);
    const length = module._lame_shim_buffer_length(buffer);
    return module.HEAPU8.slice(data, data + length);
  } finally {
    module._lame_shim_buffer_release(buffer);
    module._free(out);
    module._free(input);
  }
}

self.onmessage = async ({data}) => {
  const {id, operation} = data;
  try {
    const module = await getModule();
    if (operation === 'buildInfo') {
      self.postMessage({
        id,
        result: {buildInfo: module.UTF8ToString(module._lame_shim_build_info())},
      });
    } else if (operation === 'encode') {
      const bytes = encode(module, data);
      self.postMessage({id, result: {bytes}}, [bytes.buffer]);
    } else if (operation === 'resourceUrls') {
      // For the browser test of the ?v= query on every loaded file.
      self.postMessage({
        id,
        result: {urls: performance.getEntriesByType('resource').map((e) => e.name)},
      });
    } else {
      throw new Error(`Unknown lame operation: ${operation}`);
    }
  } catch (error) {
    self.postMessage({
      id,
      error: {status: error.status ?? -4, message: error.message ?? String(error)},
    });
  }
};

for (const data of earlyMessages.splice(0)) {
  self.dispatchEvent(new MessageEvent('message', {data}));
}
