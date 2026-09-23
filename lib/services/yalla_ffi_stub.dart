// Web stub for YallaFFIService — dart:ffi is unavailable on web
class YallaFFIService {
  static bool get isSupported => false;
  static bool get isLoaded => false;
  static String? get loadError => 'FFI not supported on web';

  static void loadLibrary() {}
  static void initEngine(String dbContentJson) {}
  static String processUrl(String url) => throw UnsupportedError('FFI not available on web');
  static String getLogs() => '';
  static void clearLogs() {}
  static String clusterAndSummarize(String jsonInput) => '[]';
  static String analyzeArticle(String jsonInput) => '{}';
}
