// Reads the bytes of a finished recording. The `record` package hands back a
// file path on mobile/desktop and a blob: URL on web, so the implementation
// is chosen at compile time.
export 'recording_bytes_io.dart'
    if (dart.library.js_interop) 'recording_bytes_web.dart';
