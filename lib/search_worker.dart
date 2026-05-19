// SPDX-License-Identifier: AGPL-3.0-or-later
// dart.library.html is only defined on Flutter Web (dart2js / DDC).
// dart:isolate's Isolate.spawn is not available there, so we route to a
// synchronous main-thread fallback instead.
export 'search_worker_io.dart'
    if (dart.library.html) 'search_worker_web.dart';
