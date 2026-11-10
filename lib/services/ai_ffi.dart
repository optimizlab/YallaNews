// AI FFI Service for YallaNews - binds to yalla_core C++ library
// Provides Dart access to ModelManager, InferenceEngine, Summarizer, Translator

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────
// C Type Definitions
// ─────────────────────────────────────────────────────────────

// Language enum (matches yalla_core.h)
enum YallaLanguage {
  unknown(0),
  arabic(1),
  english(2),
  french(3);

  const YallaLanguage(this.value);
  final int value;
}

/// Provider types (matches yalla_core.h)
enum YallaProviderType {
  rss(0),
  atom(1),
  gdelt(2),
  factcheck(3),
  wikimedia(4),
  custom(100);

  const YallaProviderType(this.value);
  final int value;
}

/// Provider configuration (matches yalla_core.h)
class YallaProviderConfig {
  final YallaProviderType type;
  final String providerId;
  final String apiKey;
  final String baseUrl;
  final int timeoutMs;
  final int rateLimitRpm;
  final int maxRetries;
  final String customParams;

  YallaProviderConfig({
    required this.type,
    required this.providerId,
    this.apiKey = '',
    this.baseUrl = '',
    this.timeoutMs = 30000,
    this.rateLimitRpm = 60,
    this.maxRetries = 3,
    this.customParams = '{}',
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'provider_id': providerId,
      'api_key': apiKey,
      'base_url': baseUrl,
      'timeout_ms': timeoutMs,
      'rate_limit_rpm': rateLimitRpm,
      'max_retries': maxRetries,
      'custom_params': customParams,
    };
  }
}

// Opaque handles
typedef YallaModelManagerHandle = ffi.Pointer<ffi.Void>;
typedef YallaInferenceEngineHandle = ffi.Pointer<ffi.Void>;
typedef YallaSummarizerHandle = ffi.Pointer<ffi.Void>;
typedef YallaTranslatorHandle = ffi.Pointer<ffi.Void>;
typedef NewsPipelineHandle = ffi.Pointer<ffi.Void>;

// Structs - using base class for ffi.Struct compatibility
final class YallaModelInfo extends ffi.Struct {
  external ffi.Pointer<Utf8> modelId;
  external ffi.Pointer<Utf8> version;
  external ffi.Pointer<Utf8> quantization;
  @ffi.Int64()
  external int sizeBytes;
  external ffi.Pointer<Utf8> checksum;
  external ffi.Pointer<Utf8> hardwareProfile;
}

final class YallaInferenceRequest extends ffi.Struct {
  external ffi.Pointer<Utf8> prompt;
  @ffi.Int32()
  external int maxTokens;
  @ffi.Float()
  external double temperature;
  @ffi.Float()
  external double topP;
  @ffi.Bool()
  external bool stream;
}

final class YallaInferenceResponse extends ffi.Struct {
  external ffi.Pointer<Utf8> text;
  @ffi.Int32()
  external int tokensUsed;
  @ffi.Bool()
  external bool truncated;
  external ffi.Pointer<Utf8> error;
}

// ─────────────────────────────────────────────────────────────
// FFI Service Class
// ─────────────────────────────────────────────────────────────

class YallaAIService {
  static ffi.DynamicLibrary? _lib;
  static bool _initialized = false;
  static String? _loadError;

  static bool get isSupported => Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isLoaded => _lib != null;
  static String? get loadError => _loadError;

  // ───── Library Loading ─────

  static void loadLibrary() {
    if (_initialized) return;
    _initialized = true;

    if (!isSupported) {
      _loadError = 'Direct FFI loading only supported on Android, Windows, Linux, macOS.';
      return;
    }

    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);

      final possiblePaths = <String>[
        // Android - loaded via System.loadLibrary in MainActivity
        'yalla_core',
        // Windows development
        p.join(exeDir, 'yalla_core.dll'),
        p.join(Directory.current.path, 'windows', 'yalla_engine', 'yalla_core.dll'),
        p.join(Directory.current.path, 'yalla_core.dll'),
        // Linux/macOS
        'libyalla_core.so',
        'libyalla_core.dylib',
      ];

      for (final path in possiblePaths) {
        try {
          _lib = ffi.DynamicLibrary.open(path);
          _loadError = null;
          // ignore: avoid_print
          print('[YallaAI] Loaded library from: $path');
          break;
        } catch (_) {}
      }

      if (_lib == null) {
        _lib = ffi.DynamicLibrary.open('yalla_core');
      }
    } catch (e) {
      _loadError = e.toString();
      _lib = null;
    }
  }

  // ───── Helper Functions ─────

  static ffi.Pointer<Utf8> _toNativeUtf8(String str) => str.toNativeUtf8();
  static String _fromNativeUtf8(ffi.Pointer<Utf8> ptr) => ptr.toDartString();
  static void _freeNativeUtf8(ffi.Pointer<Utf8> ptr) => malloc.free(ptr);

  // ───── Model Manager ─────

  static YallaModelManagerHandle createModelManager(String modelsDir) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        YallaModelManagerHandle Function(ffi.Pointer<Utf8>),
        YallaModelManagerHandle Function(ffi.Pointer<Utf8>)
    >('yalla_model_manager_create');

    final dirPtr = _toNativeUtf8(modelsDir);
    try {
      return func(dirPtr);
    } finally {
      _freeNativeUtf8(dirPtr);
    }
  }

  static void destroyModelManager(YallaModelManagerHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaModelManagerHandle),
        void Function(YallaModelManagerHandle)
    >('yalla_model_manager_destroy');
    func(handle);
  }

  static bool downloadModel(
    YallaModelManagerHandle handle,
    String modelId,
    String url,
    String expectedChecksum,
    Function(int progress, String message) onProgress,
  ) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    // TODO: Implement callback trampoline for progress
    // For now, return false as placeholder
    return false;
  }

  static bool verifyModel(YallaModelManagerHandle handle, String modelId) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Bool Function(YallaModelManagerHandle, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Bool>),
        bool Function(YallaModelManagerHandle, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Bool>)
    >('yalla_model_manager_verify');

    final modelIdPtr = _toNativeUtf8(modelId);
    final verified = calloc<ffi.Bool>();
    try {
      final result = func(handle, modelIdPtr, verified);
      return result && verified.value;
    } finally {
      _freeNativeUtf8(modelIdPtr);
      calloc.free(verified);
    }
  }

  static String? getModelInfo(YallaModelManagerHandle handle, String modelId) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<YallaModelInfo> Function(YallaModelManagerHandle, ffi.Pointer<Utf8>),
        ffi.Pointer<YallaModelInfo> Function(YallaModelManagerHandle, ffi.Pointer<Utf8>)
    >('yalla_model_manager_get_info');

    final freeFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<YallaModelInfo>),
        void Function(ffi.Pointer<YallaModelInfo>)
    >('yalla_model_manager_free_info');

    final modelIdPtr = _toNativeUtf8(modelId);
    try {
      final infoPtr = func(handle, modelIdPtr);
      if (infoPtr == ffi.nullptr) return null;

      final modelIdStr = _fromNativeUtf8(infoPtr.ref.modelId);
      final version = _fromNativeUtf8(infoPtr.ref.version);
      final quantization = _fromNativeUtf8(infoPtr.ref.quantization);
      final sizeBytes = infoPtr.ref.sizeBytes;
      final checksum = _fromNativeUtf8(infoPtr.ref.checksum);
      final hardwareProfile = _fromNativeUtf8(infoPtr.ref.hardwareProfile);

      freeFunc(infoPtr);

      return '{"model_id":"$modelIdStr","version":"$version","quantization":"$quantization","size_bytes":$sizeBytes,"checksum":"$checksum","hardware_profile":"$hardwareProfile"}';
    } finally {
      _freeNativeUtf8(modelIdPtr);
    }
  }

  static List<String> listModels(YallaModelManagerHandle handle) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<ffi.Pointer<Utf8>> Function(YallaModelManagerHandle, ffi.Pointer<ffi.Int32>),
        ffi.Pointer<ffi.Pointer<Utf8>> Function(YallaModelManagerHandle, ffi.Pointer<ffi.Int32>)
    >('yalla_model_manager_list_models');

    final freeFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Pointer<Utf8>>, ffi.Int32),
        void Function(ffi.Pointer<ffi.Pointer<Utf8>>, int)
    >('yalla_model_manager_free_list');

    final count = calloc<ffi.Int32>();
    try {
      final listPtr = func(handle, count);
      if (listPtr == ffi.nullptr) return [];

      final result = <String>[];
      for (int i = 0; i < count.value; i++) {
        final itemPtr = listPtr[i];
        if (itemPtr != ffi.nullptr) {
          result.add(_fromNativeUtf8(itemPtr));
        }
      }
      freeFunc(listPtr, count.value);
      return result;
    } finally {
      calloc.free(count);
    }
  }

  static void unloadModel(YallaModelManagerHandle handle, String modelId) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaModelManagerHandle, ffi.Pointer<Utf8>),
        void Function(YallaModelManagerHandle, ffi.Pointer<Utf8>)
    >('yalla_model_manager_unload');

    final modelIdPtr = _toNativeUtf8(modelId);
    try {
      func(handle, modelIdPtr);
    } finally {
      _freeNativeUtf8(modelIdPtr);
    }
  }

  static void cancelDownload(YallaModelManagerHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaModelManagerHandle),
        void Function(YallaModelManagerHandle)
    >('yalla_model_manager_cancel_download');
    func(handle);
  }

  // ───── Inference Engine ─────

  static YallaInferenceEngineHandle createInferenceEngine(YallaModelManagerHandle modelManager) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        YallaInferenceEngineHandle Function(YallaModelManagerHandle),
        YallaInferenceEngineHandle Function(YallaModelManagerHandle)
    >('yalla_inference_engine_create');

    return func(modelManager);
  }

  static void destroyInferenceEngine(YallaInferenceEngineHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaInferenceEngineHandle),
        void Function(YallaInferenceEngineHandle)
    >('yalla_inference_engine_destroy');
    func(handle);
  }

  static bool loadModel(
    YallaInferenceEngineHandle handle,
    String modelId,
    int contextSize,
    int maxBatchSize,
  ) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Bool Function(YallaInferenceEngineHandle, ffi.Pointer<Utf8>, ffi.Int32, ffi.Int32),
        bool Function(YallaInferenceEngineHandle, ffi.Pointer<Utf8>, int, int)
    >('yalla_inference_engine_load_model');

    final modelIdPtr = _toNativeUtf8(modelId);
    try {
      return func(handle, modelIdPtr, contextSize, maxBatchSize);
    } finally {
      _freeNativeUtf8(modelIdPtr);
    }
  }

  static void unloadInferenceModel(YallaInferenceEngineHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaInferenceEngineHandle),
        void Function(YallaInferenceEngineHandle)
    >('yalla_inference_engine_unload_model');
    func(handle);
  }

  static Map<String, dynamic> infer(
    YallaInferenceEngineHandle handle,
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    double topP = 0.9,
    bool stream = false,
  }) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        YallaInferenceResponse Function(YallaInferenceEngineHandle, ffi.Pointer<YallaInferenceRequest>),
        YallaInferenceResponse Function(YallaInferenceEngineHandle, ffi.Pointer<YallaInferenceRequest>)
    >('yalla_inference_engine_infer');

    final freeStringFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<Utf8>),
        void Function(ffi.Pointer<Utf8>)
    >('yalla_free_string');

    final promptPtr = _toNativeUtf8(prompt);
    final request = calloc<YallaInferenceRequest>();
    try {
      request.ref.prompt = promptPtr;
      request.ref.maxTokens = maxTokens;
      request.ref.temperature = temperature;
      request.ref.topP = topP;
      request.ref.stream = stream;

      final response = func(handle, request);
      final text = response.text == ffi.nullptr ? '' : _fromNativeUtf8(response.text);
      final tokensUsed = response.tokensUsed;
      final truncated = response.truncated;
      final error = response.error == ffi.nullptr ? null : _fromNativeUtf8(response.error);

      if (response.text != ffi.nullptr) freeStringFunc(response.text);
      if (response.error != ffi.nullptr) freeStringFunc(response.error);

      return {
        'text': text,
        'tokens_used': tokensUsed,
        'truncated': truncated,
        'error': error,
      };
    } finally {
      _freeNativeUtf8(promptPtr);
      calloc.free(request);
    }
  }

  static void cancelInference(YallaInferenceEngineHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaInferenceEngineHandle),
        void Function(YallaInferenceEngineHandle)
    >('yalla_inference_engine_cancel');
    func(handle);
  }

  static bool isBusy(YallaInferenceEngineHandle handle) {
    loadLibrary();
    if (_lib == null) return false;

    final func = _lib!.lookupFunction<
        ffi.Bool Function(YallaInferenceEngineHandle),
        bool Function(YallaInferenceEngineHandle)
    >('yalla_inference_engine_is_busy');
    return func(handle);
  }

  static int getMemoryUsage(YallaInferenceEngineHandle handle) {
    loadLibrary();
    if (_lib == null) return 0;

    final func = _lib!.lookupFunction<
        ffi.Int64 Function(YallaInferenceEngineHandle),
        int Function(YallaInferenceEngineHandle)
    >('yalla_inference_engine_get_memory_usage');
    return func(handle);
  }

  static void setSamplingParams(
    YallaInferenceEngineHandle handle,
    double temperature,
    double topP,
    int topK,
    double repeatPenalty,
    int mirostat,
    double mirostatTau,
    double mirostatEta,
  ) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaInferenceEngineHandle, ffi.Float, ffi.Float, ffi.Int32, ffi.Float, ffi.Int32, ffi.Float, ffi.Float),
        void Function(YallaInferenceEngineHandle, double, double, int, double, int, double, double)
    >('yalla_inference_engine_set_sampling_params');

    func(handle, temperature, topP, topK, repeatPenalty, mirostat, mirostatTau, mirostatEta);
  }

  // ───── Summarizer ─────

  static YallaSummarizerHandle createSummarizer(YallaInferenceEngineHandle engine) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        YallaSummarizerHandle Function(YallaInferenceEngineHandle),
        YallaSummarizerHandle Function(YallaInferenceEngineHandle)
    >('yalla_summarizer_create');

    return func(engine);
  }

  static void destroySummarizer(YallaSummarizerHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaSummarizerHandle),
        void Function(YallaSummarizerHandle)
    >('yalla_summarizer_destroy');
    func(handle);
  }

  static String summarize(
    YallaSummarizerHandle handle,
    String title,
    String content,
    String language,
    int maxLength,
  ) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<Utf8> Function(YallaSummarizerHandle, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
        ffi.Pointer<Utf8> Function(YallaSummarizerHandle, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)
    >('yalla_summarizer_summarize');

    final freeStringFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<Utf8>),
        void Function(ffi.Pointer<Utf8>)
    >('yalla_free_string');

    final titlePtr = _toNativeUtf8(title);
    final contentPtr = _toNativeUtf8(content);
    final langPtr = _toNativeUtf8(language);

    try {
      final resultPtr = func(handle, titlePtr, contentPtr, langPtr, maxLength);
      if (resultPtr == ffi.nullptr) return '';

      final result = _fromNativeUtf8(resultPtr);
      freeStringFunc(resultPtr);
      return result;
    } finally {
      _freeNativeUtf8(titlePtr);
      _freeNativeUtf8(contentPtr);
      _freeNativeUtf8(langPtr);
    }
  }

  // ───── Translator ─────

  static YallaTranslatorHandle createTranslator(YallaInferenceEngineHandle engine) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        YallaTranslatorHandle Function(YallaInferenceEngineHandle),
        YallaTranslatorHandle Function(YallaInferenceEngineHandle)
    >('yalla_translator_create');

    return func(engine);
  }

  static void destroyTranslator(YallaTranslatorHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(YallaTranslatorHandle),
        void Function(YallaTranslatorHandle)
    >('yalla_translator_destroy');
    func(handle);
  }

  static String translate(
    YallaTranslatorHandle handle,
    String text,
    YallaLanguage sourceLang,
    YallaLanguage targetLang,
  ) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<Utf8> Function(YallaTranslatorHandle, ffi.Pointer<Utf8>, ffi.Int32, ffi.Int32),
        ffi.Pointer<Utf8> Function(YallaTranslatorHandle, ffi.Pointer<Utf8>, int, int)
    >('yalla_translator_translate');

    final freeStringFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<Utf8>),
        void Function(ffi.Pointer<Utf8>)
    >('yalla_free_string');

    final textPtr = _toNativeUtf8(text);
    try {
      final resultPtr = func(handle, textPtr, sourceLang.value, targetLang.value);
      if (resultPtr == ffi.nullptr) return '';

      final result = _fromNativeUtf8(resultPtr);
      freeStringFunc(resultPtr);
      return result;
    } finally {
      _freeNativeUtf8(textPtr);
    }
  }

  // ───── Utility ─────

  static String getVersion() {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<Utf8> Function(),
        ffi.Pointer<Utf8> Function()
    >('yalla_get_version');

    final freeStringFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<Utf8>),
        void Function(ffi.Pointer<Utf8>)
    >('yalla_free_string');

    final versionPtr = func();
    if (versionPtr == ffi.nullptr) return 'unknown';

    final version = _fromNativeUtf8(versionPtr);
    freeStringFunc(versionPtr);
    return version;
  }

  // ───── News Pipeline ─────

  static NewsPipelineHandle createNewsPipeline(String configJson) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        NewsPipelineHandle Function(ffi.Pointer<Utf8>),
        NewsPipelineHandle Function(ffi.Pointer<Utf8>)
    >('yalla_pipeline_create');

    final configPtr = _toNativeUtf8(configJson);
    try {
      return func(configPtr);
    } finally {
      _freeNativeUtf8(configPtr);
    }
  }

  static void destroyNewsPipeline(NewsPipelineHandle handle) {
    loadLibrary();
    if (_lib == null) return;

    final func = _lib!.lookupFunction<
        ffi.Void Function(NewsPipelineHandle),
        void Function(NewsPipelineHandle)
    >('yalla_pipeline_destroy');
    func(handle);
  }

  static String runPipeline(NewsPipelineHandle handle) {
    loadLibrary();
    if (_lib == null) throw Exception('C++ library not loaded: $_loadError');

    final func = _lib!.lookupFunction<
        ffi.Pointer<Utf8> Function(NewsPipelineHandle),
        ffi.Pointer<Utf8> Function(NewsPipelineHandle)
    >('yalla_pipeline_run');

    final freeStringFunc = _lib!.lookupFunction<
        ffi.Void Function(ffi.Pointer<Utf8>),
        void Function(ffi.Pointer<Utf8>)
    >('yalla_free_string');

    final resultPtr = func(handle);
    if (resultPtr == ffi.nullptr) return '{"success":false,"error":"Pipeline returned null"}';

    final result = _fromNativeUtf8(resultPtr);
    freeStringFunc(resultPtr);
    return result;
  }

  static void setPipelineProgressCallback(
    NewsPipelineHandle handle,
    void Function(String stage, int progress, String message) callback,
  ) {
    // Note: This requires a C callback trampoline
    // For now, we use a simplified approach where the callback is stored globally
    // and called from a Dart isolate
    // TODO: Implement proper callback trampoline
  }

  static void setPipelineCompletionCallback(
    NewsPipelineHandle handle,
    void Function(String resultJson) callback,
  ) {
    // Note: This requires a C callback trampoline
    // For now, we use a simplified approach
    // TODO: Implement proper callback trampoline
  }
}