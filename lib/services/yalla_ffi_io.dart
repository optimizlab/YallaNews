import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// Typedefs for C++ signatures
typedef InitEngineCSig = ffi.Void Function(ffi.Pointer<Utf8> dbContent);
typedef InitEngineDartSig = void Function(ffi.Pointer<Utf8> dbContent);

typedef ProcessUrlCSig = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> url);
typedef ProcessUrlDartSig = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> url);

typedef AnalyzeArticleCSig = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> jsonInput);
typedef AnalyzeArticleDartSig = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> jsonInput);

typedef FreeStringCSig = ffi.Void Function(ffi.Pointer<Utf8> str);
typedef FreeStringDartSig = void Function(ffi.Pointer<Utf8> str);

typedef GetLogsCSig = ffi.Pointer<Utf8> Function();
typedef GetLogsDartSig = ffi.Pointer<Utf8> Function();

typedef ClearLogsCSig = ffi.Void Function();
typedef ClearLogsDartSig = void Function();

class YallaFFIService {
  static ffi.DynamicLibrary? _lib;
  static bool _initialized = false;
  static String? _loadError;

  static bool get isSupported => Platform.isWindows;
  static bool get isLoaded => _lib != null;
  static String? get loadError => _loadError;

  static String clusterAndSummarize(String jsonInput) {
    loadLibrary();
    if (_lib == null) throw Exception("C++ Engine DLL not loaded: $_loadError");
    final func = _lib!.lookupFunction<
        ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>),
        ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>)>('cluster_and_summarize');
    final inputPtr = jsonInput.toNativeUtf8();
    try {
      final resultPtr = func(inputPtr);
      if (resultPtr == ffi.nullptr) return "[]";
      return resultPtr.toDartString();
    } finally {
      malloc.free(inputPtr);
    }
  }

  static void loadLibrary() {
    if (_initialized) return;
    _initialized = true;

    if (!isSupported) {
      _loadError = "Direct FFI DLL loading only supported on Windows Desktop.";
      return;
    }

    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);

      final possiblePaths = [
        p.join(exeDir, 'yalla_engine.dll'),
        p.join(Directory.current.path, 'windows', 'yalla_engine', 'yalla_engine.dll'),
        p.join(Directory.current.path, 'yalla_engine.dll'),
      ];

      for (final path in possiblePaths) {
        if (File(path).existsSync()) {
          _lib = ffi.DynamicLibrary.open(path);
          _loadError = null;
          break;
        }
      }

      if (_lib == null) {
        _lib = ffi.DynamicLibrary.open('yalla_engine.dll');
      }
    } catch (e) {
      _loadError = e.toString();
      _lib = null;
    }
  }

  static void initEngine(String dbContentJson) {
    loadLibrary();
    if (_lib == null) throw Exception("C++ Engine DLL not loaded: $_loadError");

    final initFn = _lib!.lookupFunction<InitEngineCSig, InitEngineDartSig>('init_engine');
    final dbContentPtr = dbContentJson.toNativeUtf8();
    try {
      initFn(dbContentPtr);
    } finally {
      malloc.free(dbContentPtr);
    }
  }

  static String processUrl(String url) {
    loadLibrary();
    if (_lib == null) throw Exception("C++ Engine DLL not loaded: $_loadError");

    final processFn = _lib!.lookupFunction<ProcessUrlCSig, ProcessUrlDartSig>('process_url');
    final freeFn = _lib!.lookupFunction<FreeStringCSig, FreeStringDartSig>('free_string');

    final urlPtr = url.toNativeUtf8();
    ffi.Pointer<Utf8>? resultPtr;
    try {
      resultPtr = processFn(urlPtr);
      if (resultPtr == ffi.Pointer.fromAddress(0)) {
        throw Exception("C++ Engine returned null pointer.");
      }
      return resultPtr.toDartString();
    } finally {
      malloc.free(urlPtr);
      if (resultPtr != null && resultPtr != ffi.Pointer.fromAddress(0)) {
        freeFn(resultPtr);
      }
    }
  }

  static String analyzeArticle(String jsonInput) {
    loadLibrary();
    if (_lib == null) throw Exception("C++ Engine DLL not loaded: $_loadError");

    final analyzeFn = _lib!.lookupFunction<AnalyzeArticleCSig, AnalyzeArticleDartSig>('analyze_article');
    final freeFn = _lib!.lookupFunction<FreeStringCSig, FreeStringDartSig>('free_string');

    final inputPtr = jsonInput.toNativeUtf8();
    ffi.Pointer<Utf8>? resultPtr;
    try {
      resultPtr = analyzeFn(inputPtr);
      if (resultPtr == ffi.Pointer.fromAddress(0)) {
        throw Exception("C++ Engine returned null pointer from analyze_article.");
      }
      return resultPtr.toDartString();
    } finally {
      malloc.free(inputPtr);
      if (resultPtr != null && resultPtr != ffi.Pointer.fromAddress(0)) {
        freeFn(resultPtr);
      }
    }
  }

  static String getLogs() {
    loadLibrary();
    if (_lib == null) return "[SYSTEM] FFI DLL not loaded. Log streaming unavailable.\n";

    final getLogsFn = _lib!.lookupFunction<GetLogsCSig, GetLogsDartSig>('get_engine_logs');
    final freeFn = _lib!.lookupFunction<FreeStringCSig, FreeStringDartSig>('free_string');

    ffi.Pointer<Utf8>? logsPtr;
    try {
      logsPtr = getLogsFn();
      if (logsPtr == ffi.Pointer.fromAddress(0)) return "";
      return logsPtr.toDartString();
    } finally {
      if (logsPtr != null && logsPtr != ffi.Pointer.fromAddress(0)) {
        freeFn(logsPtr);
      }
    }
  }

  static void clearLogs() {
    loadLibrary();
    if (_lib == null) return;

    final clearFn = _lib!.lookupFunction<ClearLogsCSig, ClearLogsDartSig>('clear_engine_logs');
    clearFn();
  }
}
