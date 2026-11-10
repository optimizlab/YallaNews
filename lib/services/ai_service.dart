// High-level AI Service for YallaNews
// Wraps ai_ffi.dart with Flutter-friendly async APIs and state management

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'ai_ffi.dart'
    show
        YallaAIService,
        YallaLanguage,
        YallaModelManagerHandle,
        YallaInferenceEngineHandle,
        YallaSummarizerHandle,
        YallaTranslatorHandle;
import 'ai_fallback_service.dart';

enum AIModelType {
  qwen3_0_6bQ4('qwen3-0.6b-q4', 'Qwen3-0.6B Q4_K_M', 'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf', 'sha256:placeholder'),
  qwen3_1_7bQ4('qwen3-1.7b-q4', 'Qwen3-1.7B Q4_K_M', 'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/qwen3-1.7b-q4_k_m.gguf', 'sha256:placeholder'),
  gemma2_2bQ4('gemma2-2b-q4', 'Gemma2-2B Q4_K_M', 'https://huggingface.co/google/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-q4_k_m.gguf', 'sha256:placeholder');

  const AIModelType(this.id, this.name, this.url, this.checksum);
  final String id;
  final String name;
  final String url;
  final String checksum;
}

class AIService extends ChangeNotifier {
  static AIService? _instance;
  static AIService get instance => _instance ??= AIService._();
  AIService._();

  final AIFallbackService _fallback = AIFallbackService.instance;

  YallaModelManagerHandle? _modelManager;
  YallaInferenceEngineHandle? _inferenceEngine;
  YallaSummarizerHandle? _summarizer;
  YallaTranslatorHandle? _translator;

  AIModelType _currentModel = AIModelType.qwen3_0_6bQ4;
  bool _isModelLoaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _lastError;
  int _memoryUsageMB = 0;

  // Getters
  AIModelType get currentModel => _currentModel;
  bool get isModelLoaded => _isModelLoaded;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;
  int get memoryUsageMB => _memoryUsageMB;
  bool get isReady => _isModelLoaded && !_isDownloading;

  // Available models
  List<AIModelType> get availableModels => AIModelType.values;

  Future<void> initialize() async {
    try {
      // Get models directory
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(appDir.path, 'models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      // Initialize model manager
      _modelManager = YallaAIService.createModelManager(modelsDir.path);

      // Create inference engine
      _inferenceEngine = YallaAIService.createInferenceEngine(_modelManager!);

      // Create summarizer and translator
      _summarizer = YallaAIService.createSummarizer(_inferenceEngine!);
      _translator = YallaAIService.createTranslator(_inferenceEngine!);

      // Check for existing model
      await _checkExistingModel();

      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to initialize AI service: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _checkExistingModel() async {
    if (_modelManager == null) return;

    try {
      final models = YallaAIService.listModels(_modelManager!);
      if (models.contains(_currentModel.id)) {
        final loaded = await loadModel(_currentModel);
        if (loaded) {
          _isModelLoaded = true;
        }
      }
    } catch (e) {
      // Ignore - model might not exist
    }
  }

  Future<bool> loadModel(AIModelType model) async {
    if (_inferenceEngine == null || _modelManager == null) return false;

    _currentModel = model;
    _lastError = null;

    try {
      // Verify model exists
      final verified = YallaAIService.verifyModel(_modelManager!, model.id);
      if (!verified) {
        _lastError = 'Model not found: ${model.name}. Please download first.';
        notifyListeners();
        return false;
      }

      // Load into inference engine
      final success = YallaAIService.loadModel(
        _inferenceEngine!,
        model.id,
        4096, // context size
        1,    // max batch size
      );

      if (success) {
        _isModelLoaded = true;
        _updateMemoryUsage();
      } else {
        _lastError = 'Failed to load model into memory';
        _isModelLoaded = false;
      }

      notifyListeners();
      return success;
    } catch (e) {
      _lastError = 'Error loading model: $e';
      _isModelLoaded = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> downloadModel(AIModelType model, {Function(double progress)? onProgress}) async {
    if (_modelManager == null) {
      _lastError = 'Model manager not initialized';
      notifyListeners();
      return;
    }

    if (YallaAIService.verifyModel(_modelManager!, model.id)) {
      _lastError = 'Model already downloaded';
      notifyListeners();
      return;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _lastError = null;
    notifyListeners();

    try {
      // Note: The actual download requires callback trampoline implementation
      // For now, we simulate - real implementation needs C callback bridge
      _lastError = 'Model download not fully implemented - callback trampoline needed';
      _isDownloading = false;
      _downloadProgress = 1.0;
      notifyListeners();
    } catch (e) {
      _lastError = 'Download failed: $e';
      _isDownloading = false;
      _downloadProgress = 0.0;
      notifyListeners();
    }
  }

  void _updateMemoryUsage() {
    if (_inferenceEngine != null) {
      final bytes = YallaAIService.getMemoryUsage(_inferenceEngine!);
      _memoryUsageMB = (bytes / (1024 * 1024)).round();
    }
  }

  /// Summarize article - uses AI if available, otherwise fallback
  Future<String> summarize({
    required String title,
    required String content,
    String language = 'en',
    int maxLength = 150,
  }) async {
    if (isReady && _summarizer != null) {
      try {
        return YallaAIService.summarize(
          _summarizer!,
          title,
          content,
          language,
          maxLength,
        );
      } catch (e) {
        _lastError = 'AI summarization failed, using fallback: $e';
        // Fall through to fallback
      }
    }
    
    // Use deterministic fallback
    return _fallback.summarize(
      title: title,
      content: content,
      language: language,
      maxLength: maxLength,
    );
  }

  /// Translate text - uses AI if available, otherwise fallback
  Future<String> translate({
    required String text,
    required YallaLanguage sourceLang,
    required YallaLanguage targetLang,
  }) async {
    if (isReady && _translator != null) {
      try {
        return YallaAIService.translate(
          _translator!,
          text,
          sourceLang,
          targetLang,
        );
      } catch (e) {
        _lastError = 'AI translation failed, using fallback: $e';
        // Fall through to fallback
      }
    }
    
    // Use deterministic fallback
    return _fallback.translate(
      text: text,
      sourceLang: sourceLang,
      targetLang: targetLang,
    );
  }

  /// Classify article - uses AI if available, otherwise fallback
  Future<String> classify({
    required String title,
    required String content,
    String language = 'en',
  }) async {
    if (isReady && _inferenceEngine != null) {
      try {
        final result = YallaAIService.infer(
          _inferenceEngine!,
          'Classify this news article into one category: politics, business, technology, sports, health, science, culture, world, society, entertainment.\n\nTitle: $title\nContent: $content\n\nCategory:',
          maxTokens: 20,
          temperature: 0.1,
        );
        final category = result['text']?.toString().trim().toLowerCase() ?? '';
        if (category.isNotEmpty) return category;
      } catch (e) {
        _lastError = 'AI classification failed, using fallback: $e';
      }
    }
    
    // Use deterministic fallback
    return _fallback.classify(title: title, content: content, language: language);
  }

  /// Extract entities - uses AI if available, otherwise fallback
  Future<List<String>> extractEntities({
    required String title,
    required String content,
    String language = 'en',
  }) async {
    if (isReady && _inferenceEngine != null) {
      try {
        final result = YallaAIService.infer(
          _inferenceEngine!,
          'Extract named entities (people, organizations, locations, dates, money) from this text. Return as comma-separated list.\n\nTitle: $title\nContent: $content\n\nEntities:',
          maxTokens: 100,
          temperature: 0.1,
        );
        final entitiesStr = result['text']?.toString().trim() ?? '';
        if (entitiesStr.isNotEmpty) {
          return entitiesStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      } catch (e) {
        _lastError = 'AI entity extraction failed, using fallback: $e';
      }
    }
    
    // Use deterministic fallback
    return _fallback.extractEntities(title: title, content: content, language: language);
  }

  /// Analyze sentiment - uses AI if available, otherwise fallback
  Future<double> analyzeSentiment(String text) async {
    if (isReady && _inferenceEngine != null) {
      try {
        final result = YallaAIService.infer(
          _inferenceEngine!,
          'Analyze the sentiment of this text. Return a number between -1 (very negative) and 1 (very positive).\n\nText: $text\n\nSentiment:',
          maxTokens: 10,
          temperature: 0.1,
        );
        final sentimentStr = result['text']?.toString().trim() ?? '';
        final sentiment = double.tryParse(sentimentStr);
        if (sentiment != null && sentiment >= -1 && sentiment <= 1) return sentiment;
      } catch (e) {
        _lastError = 'AI sentiment analysis failed, using fallback: $e';
      }
    }
    
    // Use deterministic fallback
    return _fallback.analyzeSentiment(text);
  }

  /// Extract keywords - uses AI if available, otherwise fallback
  Future<List<String>> extractKeywords({
    required String text,
    int maxKeywords = 10,
  }) async {
    if (isReady && _inferenceEngine != null) {
      try {
        final result = YallaAIService.infer(
          _inferenceEngine!,
          'Extract the top $maxKeywords keywords from this text. Return as comma-separated list.\n\nText: $text\n\nKeywords:',
          maxTokens: 50,
          temperature: 0.1,
        );
        final keywordsStr = result['text']?.toString().trim() ?? '';
        if (keywordsStr.isNotEmpty) {
          return keywordsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      } catch (e) {
        _lastError = 'AI keyword extraction failed, using fallback: $e';
      }
    }
    
    // Use deterministic fallback
    return _fallback.extractKeywords(text, maxKeywords: maxKeywords);
  }

  /// Generate text - uses AI if available, otherwise fallback
  Future<Map<String, dynamic>> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
    double topP = 0.9,
  }) async {
    if (isReady && _inferenceEngine != null) {
      try {
        return YallaAIService.infer(
          _inferenceEngine!,
          prompt,
          maxTokens: maxTokens,
          temperature: temperature,
          topP: topP,
        );
      } catch (e) {
        _lastError = 'AI generation failed: $e';
        rethrow;
      }
    }
    
    throw Exception('AI not available for text generation');
  }

  void cancelGeneration() {
    if (_inferenceEngine != null) {
      YallaAIService.cancelInference(_inferenceEngine!);
    }
  }

  void unloadModel() {
    if (_inferenceEngine != null) {
      YallaAIService.unloadInferenceModel(_inferenceEngine!);
      _isModelLoaded = false;
      _memoryUsageMB = 0;
      notifyListeners();
    }
  }

  void setModel(AIModelType model) {
    if (_currentModel != model) {
      _currentModel = model;
      notifyListeners();
    }
  }

  String getVersion() {
    return YallaAIService.getVersion();
  }

  /// Check if AI features are available (model loaded and ready)
  bool get isAIAvailable => isReady;

  @override
  void dispose() {
    if (_summarizer != null) YallaAIService.destroySummarizer(_summarizer!);
    if (_translator != null) YallaAIService.destroyTranslator(_translator!);
    if (_inferenceEngine != null) YallaAIService.destroyInferenceEngine(_inferenceEngine!);
    if (_modelManager != null) YallaAIService.destroyModelManager(_modelManager!);
    super.dispose();
  }
}

// Extension for easier language handling
extension YallaLanguageExt on YallaLanguage {
  static YallaLanguage fromString(String code) {
    switch (code.toLowerCase()) {
      case 'ar':
      case 'arabic':
        return YallaLanguage.arabic;
      case 'fr':
      case 'french':
        return YallaLanguage.french;
      case 'en':
      case 'english':
      default:
        return YallaLanguage.english;
    }
  }

  String get code {
    switch (this) {
      case YallaLanguage.arabic:
        return 'ar';
      case YallaLanguage.french:
        return 'fr';
      case YallaLanguage.english:
      default:
        return 'en';
    }
  }

  String get displayName {
    switch (this) {
      case YallaLanguage.arabic:
        return 'Arabic';
      case YallaLanguage.french:
        return 'French';
      case YallaLanguage.english:
      default:
        return 'English';
    }
  }
}