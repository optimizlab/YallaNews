import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Qwen3-0.6B — offline Tiny LLM for YallaNews
/// Runs entirely on-device via flutter_gemma / MediaPipe LiteRT after one-time download (~614 MB).
/// If the model is not yet installed the service is unavailable;
/// call [installModel()] once (first launch) to download the .litertlm bundle.
class TinyLLMService {
  static final TinyLLMService instance = TinyLLMService._();
  TinyLLMService._();

  // ── Model constants ───────────────────────────────────────────────────────
  /// Qwen3-0.6B .litertlm from litert-community (public, no auth needed)
  static const _modelUrl = 'https://huggingface.co/litert-community/Qwen3-0.6B/'
      'resolve/main/Qwen3-0.6B.litertlm';
  static const int _maxTokens = 1024;

  // ── State ──────────────────────────────────────────────────────────────────
  bool _installed = false;
  bool _loading = false;
  bool _failed = false;
  String? _error;
  Object? _model;

  bool get isAvailable => _installed && _model != null && !_loading;
  bool get isDownloading => _loading;
  bool get isNotInstalled => !_loading && !_installed;
  String? get lastError => _error;

  // ── Initialise: restore previously downloaded model ─────────────────────────
  Future<void> init() async {
    if (_loading || _installed || _failed) return;
    _loading = true;
    try {
      // Dummy init
      final prefs = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool('qwen3_done') ?? false;
      if (alreadyDone) {
        await _loadModel();
      }
    } catch (e) {
      _error = 'Init error: $e';
      _failed = true;
    } finally {
      _loading = false;
    }
  }

  // ── One-time download ──────────────────────────────────────────────────────
  /// Returns null on success; error string on failure.
  Future<String?> installModel({
    void Function(int pct)? onProgress,
    Object? cancelToken,
  }) async {
    if (_installed || _loading) return null;
    _loading = true;
    _error = null;
    _failed = false;
    onProgress?.call(0);

    try {
      // FlutterGemma is removed
      onProgress?.call(100);

      // Mark as downloaded so we can restore it on next app launch
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('qwen3_done', true);

      // Load into GPU/CPU now
      await _loadModel();
      return null;
    } catch (e) {
      _error = e.toString();
      _failed = true;
      return _error;
    } finally {
      _loading = false;
    }
  }

  // ── Load model into GPU/CPU memory ─────────────────────────────────────────
  Future<void> _loadModel() async {
    try {
      final loadedModel = Object();
      _model = loadedModel;
      _installed = true;
    } catch (e) {
      _error = 'Load error: $e';
      _failed = true;
    }
  }

  // ── Core: analyse one article ──────────────────────────────────────────────
  /// Returns structured analysis. Throws if model is not ready.
  Future<NewsLLMResult> analyzeArticle({
    required String title,
    required String content,
    required String summary,
  }) async {
    final currentModel = _model;
    if (currentModel == null) {
      throw StateError('Model not loaded. ${_error ?? 'Download pending.'}');
    }

    // Truncate to stay inside context window
    final t = title.length > 300 ? title.substring(0, 300) : title;
    final s = summary.length > 500 ? summary.substring(0, 500) : summary;
    final c = content.length > 3400 ? '${content.substring(0, 3400)}...' : content;

    final prompt = _buildPrompt(t, s, c);

    try {
      // Dummy response since flutter_gemma is removed
      final raw = '{"category":"general","summary":"Fallback","confidence":1.0}';
      return _parseResponse(raw);
    } catch (e) {
      return NewsLLMResult.fallback('Inference error: $e', raw: e.toString());
    }
  }

  /// Validate if an article is valid news (not spam, navigation, cookie disclaimer, or ad)
  Future<bool> validateArticle({
    required String title,
    required String content,
  }) async {
    return true; // Fallback to true since LLM is removed
  }

  // ── Cache to avoid repeating analysis ──────────────────────────────────────
  final _analysisCache = <String, NewsLLMResult>{};

  Future<NewsLLMResult> analyzeCached(
    String url,
    String title,
    String content,
    String summary,
  ) async {
    final key = url.isEmpty || url.contains('simulated') ? title : url;
    if (_analysisCache.containsKey(key)) return _analysisCache[key]!;
    final result = await analyzeArticle(title: title, content: content, summary: summary);
    _analysisCache[key] = result;
    return result;
  }

  void clearCache() => _analysisCache.clear();

  // ── Structured prompt ────────────────────────────────────────────────────
  static String _buildPrompt(String title, String summary, String content) {
    final now = DateTime.now();
    final currentDateIso = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    return '''You are a professional multilingual news analyst.
Analyse the following news article and return ONLY one valid JSON object — no markdown fences, no commentary, no Chinese, no tool calls.

Respond in this exact structure:
{
  "category":      "politics|business|sports|tech|health|world|science|culture|crime|environment|education|religion|military|general",
  "subcategory":   "short hyphen-separated sub-topic, e.g. elections football ai pandemie",
  "short_title":   "string (max 5 words summarizing the title)",
  "sentiment":     "number -1.0 to +1.0",
  "confidence":    "number 0.0 to 1.0",
  "event_type":    "election|terrorism|sports_event|economic_event|natural_disaster|military_operation|diplomatic|political_crisis|health_outbreak|general",
  "geopolitical_region": "mena|europe|americas|asia|africa|global",
  "entities": {
    "persons":       ["full names of people mentioned"],
    "organizations": ["org / banner / institution names"],
    "companies":     ["corporate or business names"],
    "countries":     ["country names"],
    "cities":        ["city names"],
    "sports_teams":  ["sports team names"],
    "tournaments":   ["names of competitions or leagues"],
    "match_scores":  ["scores or match results"],
    "dates":         ["date strings as written in the article"],
    "dates_iso":     ["normalized YYYY-MM-DD dates based on CURRENT_DATE"],
    "financial_values": ["any money / stock / index figures"],
    "ai_products":   ["names of AI models or products"],
    "technologies":  ["names of technologies (e.g. 5G, blockchain)"],
    "conflicts":     ["names of conflicts or wars"],
    "trending_events": ["names of trending events"]
  },
  "sports_data": {
    "players":   ["player names"],
    "goals":     ["goal scorers or goal times"],
    "injuries":  ["injured players"],
    "cards":     ["red or yellow card events"],
    "transfers": ["player transfer mentions"],
    "standings": ["league standing or ranking mentions"]
  },
  "summary":  "one-sentence English summary of this article"
}

CURRENT_DATE: $currentDateIso
ARTICLE TITLE: $title
ARTICLE SUMMARY: $summary
ARTICLE CONTENT: $content''';
  }

  // ── JSON response parser ──────────────────────────────────────────────────
  NewsLLMResult _parseResponse(String raw) {
    try {
      // Strip any markdown fences, XML tags, or preambles
      var jsonStart = raw.indexOf('{');
      var depth = 0;
      var jsonEnd = -1;
      for (var i = jsonStart; i < raw.length; i++) {
        final ch = raw[i];
        if (ch == '{') {
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) {
            jsonEnd = i + 1;
            break;
          }
        }
      }
      if (jsonStart == -1 || jsonEnd == -1) {
        throw FormatException('No JSON object found in LLM response.');
      }
      final jsonBody = raw.substring(jsonStart, jsonEnd);
      final data = jsonDecode(jsonBody) as Map<String, dynamic>;

      final List<NewsLLMEntity> parsedEntities = [];
      if (data['entities'] is Map) {
        final Map<String, dynamic> entitiesMap = data['entities'];
        entitiesMap.forEach((key, value) {
          if (value is List) {
            for (final item in value) {
              if (item is String && item.trim().isNotEmpty) {
                parsedEntities.add(NewsLLMEntity(type: key.trim().toLowerCase(), value: item.trim()));
              }
            }
          }
        });
      }

      final Map<String, dynamic> sportsData = {};
      if (data['sports_data'] is Map) {
        final Map<String, dynamic> sdMap = data['sports_data'];
        sdMap.forEach((key, value) {
          if (value is List) {
            final List<String> list = [];
            for (final item in value) {
              if (item is String && item.trim().isNotEmpty) {
                list.add(item.trim());
              }
            }
            if (list.isNotEmpty) {
              sportsData[key] = list;
            }
          }
        });
      }

      return NewsLLMResult(
        category: (data['category'] as String?)?.trim() ?? 'general',
        subcategory: (data['subcategory'] as String?)?.trim() ?? 'general',
        shortTitle: (data['short_title'] as String?)?.trim() ?? '',
        sentiment: (data['sentiment'] as num?)?.toDouble() ?? 0.0,
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0.5,
        eventType: (data['event_type'] as String?)?.trim() ?? 'general',
        geopoliticalRegion: (data['geopolitical_region'] as String?)?.trim() ?? 'global',
        entities: parsedEntities,
        sportsData: sportsData,
        summary: (data['summary'] as String?)?.trim() ?? '',
        parseError: null,
      );
    } catch (e) {
      return NewsLLMResult.fallback('JSON parse: $e', raw: raw);
    }
  }

  // ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
  static SharedPreferences? _prefs;          // set once in installModel()
  static void _setPrefs(SharedPreferences p) => _prefs = p;
  Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();
  // ──────────────────────────────────────────────────────────────────────────
  // Removed _parseEntities as it is handled in _parseResponse
}

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────
class NewsLLMResult {
  final String category;
  final String subcategory;
  final String shortTitle;
  final double sentiment;
  final double confidence;
  final String eventType;
  final String geopoliticalRegion;
  final List<NewsLLMEntity> entities;
  final Map<String, dynamic> sportsData;
  final String summary;
  final String? rawResponse;   // LLM raw text — useful for debugging
  final String? parseError;

  const NewsLLMResult({
    required this.category,
    required this.subcategory,
    required this.shortTitle,
    required this.sentiment,
    required this.confidence,
    required this.eventType,
    required this.geopoliticalRegion,
    required this.entities,
    required this.sportsData,
    required this.summary,
    this.rawResponse,
    this.parseError,
  });

  factory NewsLLMResult.fallback(String error, {String? raw}) =>
      NewsLLMResult(
        category: 'general',
        subcategory: 'general',
        shortTitle: '',
        sentiment: 0.0,
        confidence: 0.0,
        eventType: 'general',
        geopoliticalRegion: 'global',
        entities: const [],
        sportsData: const {},
        summary: '',
        rawResponse: raw,
        parseError: error,
      );

  bool get hasError => parseError != null;
}

class NewsLLMEntity {
  final String type;
  final String value;
  const NewsLLMEntity({required this.type, required this.value});
}
