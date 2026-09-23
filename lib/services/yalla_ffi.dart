// Conditional export: real FFI on desktop (dart:io available), stub on web
export 'yalla_ffi_stub.dart' if (dart.library.io) 'yalla_ffi_io.dart';
