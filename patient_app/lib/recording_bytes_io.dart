import 'dart:io';
import 'dart:typed_data';

/// Mobile/desktop: the recorder returns a file path.
Future<Uint8List> readRecordingBytes(String pathOrUrl) =>
    File(pathOrUrl).readAsBytes();
