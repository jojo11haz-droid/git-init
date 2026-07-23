import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web: the recorder returns a blob: URL; the browser's HTTP stack can read it.
Future<Uint8List> readRecordingBytes(String pathOrUrl) =>
    http.readBytes(Uri.parse(pathOrUrl));
