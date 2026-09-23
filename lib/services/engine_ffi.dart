// lib/services/engine_ffi.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

DynamicLibrary? _getNativeLib() {
  if (kIsWeb) return null;
  try {
    if (Platform.isWindows) {
      return DynamicLibrary.open('yalla_engine.dll');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libyalla_engine.so');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libyalla_engine.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libyalla_engine.dylib');
    }
  } catch (_) {}
  return null;
}

final DynamicLibrary? _nativeLib = _getNativeLib();

final bool hasNativeEngine = _nativeLib != null;

// C function signatures
typedef _InitEngineC = Void Function(Pointer<Utf8> dbJson);
typedef _InitEngineDart = void Function(Pointer<Utf8> dbJson);

typedef _ProcessUrlC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef _ProcessUrlDart = Pointer<Utf8> Function(Pointer<Utf8> url);

typedef _AnalyzeArticleC = Pointer<Utf8> Function(Pointer<Utf8> jsonInput);
typedef _AnalyzeArticleDart = Pointer<Utf8> Function(Pointer<Utf8> jsonInput);

typedef _FreeStringC = Void Function(Pointer<Utf8> str);
typedef _FreeStringDart = void Function(Pointer<Utf8> str);

typedef _FreeClusterStringC = Void Function(Pointer<Utf8> str);
typedef _FreeClusterStringDart = void Function(Pointer<Utf8> str);

typedef _ClusterArticlesC = Pointer<Utf8> Function(Pointer<Utf8> jsonInput);
typedef _ClusterArticlesDart = Pointer<Utf8> Function(Pointer<Utf8> jsonInput);

typedef _ClusterArticlesExC = Pointer<Utf8> Function(
    Pointer<Utf8> jsonInput,
    Int32 algorithm,
    Int32 nClusters,
    Double eps,
    Int32 minSamples
);
typedef _ClusterArticlesExDart = Pointer<Utf8> Function(
    Pointer<Utf8> jsonInput,
    int algorithm,
    int nClusters,
    double eps,
    int minSamples
);

typedef _CleanArticleContentC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content);
typedef _CleanArticleContentDart = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content);

typedef _ExtractStoryElementsC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content);
typedef _ExtractStoryElementsDart = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content);

typedef _OptimizeSentimentC = Double Function(Pointer<Utf8> text);
typedef _OptimizeSentimentDart = double Function(Pointer<Utf8> text);

typedef _GetEngineLogsC = Pointer<Utf8> Function();
typedef _GetEngineLogsDart = Pointer<Utf8> Function();

typedef _ClearEngineLogsC = Void Function();
typedef _ClearEngineLogsDart = void Function();

typedef _IsValidImageUrlC = Int32 Function(Pointer<Utf8> url);
typedef _IsValidImageUrlDart = int Function(Pointer<Utf8> url);

typedef _SplitParagraphsByDotsC = Pointer<Utf8> Function(Pointer<Utf8> content);
typedef _SplitParagraphsByDotsDart = Pointer<Utf8> Function(Pointer<Utf8> content);

typedef _ValidateImageRelevanceC = Pointer<Utf8> Function(
  Pointer<Utf8> title,
  Pointer<Utf8> description,
  Pointer<Utf8> content,
  Pointer<Utf8> image_url,
);
typedef _ValidateImageRelevanceDart = Pointer<Utf8> Function(
  Pointer<Utf8> title,
  Pointer<Utf8> description,
  Pointer<Utf8> content,
  Pointer<Utf8> image_url,
);

// Lazy-initialized function lookups
_InitEngineDart? _initEngineFn;
_ProcessUrlDart? _processUrlFn;
_FreeStringDart? _freeStringFn;
_ClusterArticlesDart? _clusterArticlesFn;
_ClusterArticlesExDart? _clusterArticlesExFn;
_FreeClusterStringDart? _freeClusterStringFn;
_AnalyzeArticleDart? _analyzeArticleFn;
_CleanArticleContentDart? _cleanArticleContentFn;
_ExtractStoryElementsDart? _extractStoryElementsFn;
_OptimizeSentimentDart? _optimizeSentimentFn;
_GetEngineLogsDart? _getEngineLogsFn;
_ClearEngineLogsDart? _clearEngineLogsFn;
  _IsValidImageUrlDart? _isValidImageUrlFn;
  _SplitParagraphsByDotsDart? _splitParagraphsByDotsFn;
  _ValidateImageRelevanceDart? _validateImageRelevanceFn;

bool get _isNativeReady {
  if (_nativeLib == null) return false;
  try {
    _initEngineFn ??= _nativeLib!.lookup<NativeFunction<_InitEngineC>>('init_engine').asFunction();
    _processUrlFn ??= _nativeLib!.lookup<NativeFunction<_ProcessUrlC>>('process_url').asFunction();
    _freeStringFn ??= _nativeLib!.lookup<NativeFunction<_FreeStringC>>('free_string').asFunction();
    _clusterArticlesFn ??= _nativeLib!.lookup<NativeFunction<_ClusterArticlesC>>('cluster_articles').asFunction();
    _clusterArticlesExFn ??= _nativeLib!.lookup<NativeFunction<_ClusterArticlesExC>>('cluster_articles_ex').asFunction();
    _freeClusterStringFn ??= _nativeLib!.lookup<NativeFunction<_FreeClusterStringC>>('free_cluster_string').asFunction();
    _analyzeArticleFn ??= _nativeLib!.lookup<NativeFunction<_AnalyzeArticleC>>('analyze_article').asFunction();
    _cleanArticleContentFn ??= _nativeLib!.lookup<NativeFunction<_CleanArticleContentC>>('clean_article_content').asFunction();
    _extractStoryElementsFn ??= _nativeLib!.lookup<NativeFunction<_ExtractStoryElementsC>>('extract_story_elements').asFunction();
    _optimizeSentimentFn ??= _nativeLib!.lookup<NativeFunction<_OptimizeSentimentC>>('optimize_sentiment').asFunction();
    _getEngineLogsFn ??= _nativeLib!.lookup<NativeFunction<_GetEngineLogsC>>('get_engine_logs').asFunction();
    _clearEngineLogsFn ??= _nativeLib!.lookup<NativeFunction<_ClearEngineLogsC>>('clear_engine_logs').asFunction();
    _isValidImageUrlFn ??= _nativeLib!.lookup<NativeFunction<_IsValidImageUrlC>>('is_valid_image_url').asFunction();
    _splitParagraphsByDotsFn ??= _nativeLib!.lookup<NativeFunction<_SplitParagraphsByDotsC>>('split_paragraphs_by_dots').asFunction();
    _validateImageRelevanceFn ??= _nativeLib!.lookup<NativeFunction<_ValidateImageRelevanceC>>('validate_image_relevance').asFunction();
    return true;
  } catch (_) {
    return false;
  }
}

/// Convenience wrapper that returns a Dart map decoded from JSON.
Map<String, dynamic> processUrlJson(String url) {
  if (!_isNativeReady) return {};
  final urlPtr = url.toNativeUtf8();
  final resultPtr = _processUrlFn!(urlPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(urlPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as Map<String, dynamic> : {};
}

Map<String, dynamic> analyzeArticleJson(String jsonInput) {
  if (!_isNativeReady) return {};
  final inputPtr = jsonInput.toNativeUtf8();
  final resultPtr = _analyzeArticleFn!(inputPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(inputPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as Map<String, dynamic> : {};
}

/// Initialize engine with a JSON string representing the local DB (optional).
void initEngineWithJson(String dbJson) {
  if (!_isNativeReady) return;
  final dbPtr = dbJson.toNativeUtf8();
  _initEngineFn!(dbPtr);
  calloc.free(dbPtr);
}

/// Cluster articles using native C++ engine.
List<dynamic> clusterArticlesJson(String jsonArticles) {
  if (!_isNativeReady) return [];
  final jsonPtr = jsonArticles.toNativeUtf8();
  final resultPtr = _clusterArticlesFn!(jsonPtr);
  final jsonString = resultPtr.toDartString();
  _freeClusterStringFn!(resultPtr);
  calloc.free(jsonPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as List<dynamic> : [];
}

/// Cluster articles with custom algorithm and parameters.
/// algorithm: 0=K-Means, 1=DBSCAN, 2=Hierarchical
List<dynamic> clusterArticlesExJson(
  String jsonArticles,
  int algorithm,
  int nClusters,
  double eps,
  int minSamples,
) {
  if (!_isNativeReady) return [];
  final jsonPtr = jsonArticles.toNativeUtf8();
  final resultPtr = _clusterArticlesExFn!(jsonPtr, algorithm, nClusters, eps, minSamples);
  final jsonString = resultPtr.toDartString();
  _freeClusterStringFn!(resultPtr);
  calloc.free(jsonPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as List<dynamic> : [];
}

Map<String, dynamic> cleanArticleContentJson(String title, String content) {
  if (!_isNativeReady) return {};
  final titlePtr = title.toNativeUtf8();
  final contentPtr = content.toNativeUtf8();
  final resultPtr = _cleanArticleContentFn!(titlePtr, contentPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(titlePtr);
  calloc.free(contentPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as Map<String, dynamic> : {};
}

Map<String, dynamic> extractStoryElementsJson(String title, String content) {
  if (!_isNativeReady) return {};
  final titlePtr = title.toNativeUtf8();
  final contentPtr = content.toNativeUtf8();
  final resultPtr = _extractStoryElementsFn!(titlePtr, contentPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(titlePtr);
  calloc.free(contentPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as Map<String, dynamic> : {};
}

double optimizeSentiment(String text) {
  if (!_isNativeReady) return 0.0;
  final textPtr = text.toNativeUtf8();
  final result = _optimizeSentimentFn!(textPtr);
  calloc.free(textPtr);
  return result;
}

String getEngineLogs() {
  if (!_isNativeReady) return '';
  final resultPtr = _getEngineLogsFn!();
  final logs = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  return logs;
}

void clearEngineLogs() {
  if (!_isNativeReady) return;
  _clearEngineLogsFn!();
}

bool isValidImageUrl(String url) {
  if (!_isNativeReady) return false;
  final urlPtr = url.toNativeUtf8();
  final result = _isValidImageUrlFn!(urlPtr);
  calloc.free(urlPtr);
  return result == 1;
}

List<String> splitParagraphsByDots(String content) {
  if (!_isNativeReady) return [];
  final contentPtr = content.toNativeUtf8();
  final resultPtr = _splitParagraphsByDotsFn!(contentPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(contentPtr);
  if (jsonString.isEmpty) return [];
  try {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return list.cast<String>();
  } catch (_) {
    return [];
  }
}

Map<String, dynamic> validateImageRelevance({
  required String title,
  required String content,
  String? description,
  required String imageUrl,
}) {
  if (!_isNativeReady) return {'relevant': 0, 'score': 0.0, 'reasons': ['no_native_engine']};
  final titlePtr = title.toNativeUtf8();
  final descPtr = (description ?? '').toNativeUtf8();
  final contentPtr = content.toNativeUtf8();
  final urlPtr = imageUrl.toNativeUtf8();
  final resultPtr = _validateImageRelevanceFn!(titlePtr, descPtr, contentPtr, urlPtr);
  final jsonString = resultPtr.toDartString();
  _freeStringFn!(resultPtr);
  calloc.free(titlePtr);
  calloc.free(descPtr);
  calloc.free(contentPtr);
  calloc.free(urlPtr);
  return jsonString.isNotEmpty ? jsonDecode(jsonString) as Map<String, dynamic> : {'relevant': 0, 'score': 0.0, 'reasons': ['parse_failed']};
}