// SPDX-License-Identifier: AGPL-3.0-or-later
// dart.library.js_interop is defined on every web target (dart2js, DDC and
// WebAssembly; dart:html is missing under WebAssembly). dart:isolate's
// Isolate.spawn is not available there, so we route to a synchronous
// main-thread fallback instead.
export 'search_worker_io.dart'
    if (dart.library.js_interop) 'search_worker_web.dart';
