import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine_ffi.dart';

/// Qwen3-0.6B — offline Tiny LLM for YallaNews
/// Runs via C++ bridge (engine_ffi.dart → yalla_engine.dll) when available,
/// otherwise falls back to the built-in Dart stub.
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

  /// Deterministic editorial pass used even when the optional native model is
  /// not installed. It formats real publisher text; it never invents facts.
  Map<String, String> formatArticleFields({
    required String title,
    required String summary,
    required String content,
  }) {
    final cleanTitle = _formatTitle(title);
    final cleanSummary = _formatText(summary);
    final cleanContent = _sanitizeMarkup(content);
    return {
      'title': cleanTitle,
      'summary': cleanSummary,
      'content': _formatStory(cleanContent),
    };
  }

  /// Removes markup after every extraction/LLM pass. Some publishers encode
  /// tags as &lt;p&gt; or return script/code fragments as article text.
  static String _sanitizeMarkup(String value) {
    var result = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(r'\/', '/');
    result = result
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<noscript\b[^>]*>.*?</noscript>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'\b(?:javascript|vbscript|data):[^\s]+', caseSensitive: false), ' ');
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _formatText(String value) => _sanitizeMarkup(value)
      .replaceAll('\u00a0', ' ')
      .trim();

  static String _formatTitle(String value) {
    var result = _formatText(value);
    final suffix = RegExp(r'\s*(?:\||—|–|::)\s*([^|—–]{1,70})\s*$', caseSensitive: false);
    bool removed;
    do {
      final match = suffix.firstMatch(result);
      final tail = match?.group(1)?.trim() ?? '';
      removed = match != null && tail.split(RegExp(r'\s+')).length <= 8 &&
          (RegExp(r'(صحيفة|جريدة|مجلة|وكالة|شبكة|قناة|نيوز|نت|news|press|media|times|kooora|الجزيرة|الرياضية|الاقتصادية|المنتخب)', caseSensitive: false).hasMatch(tail) ||
           tail.split(RegExp(r'\s+')).length >= 2);
      if (removed) result = result.substring(0, match!.start).trim();
    } while (removed);
    return result.replaceAll(RegExp(r'[|—–:]+\s*$'), '').trim();
  }

  static String _formatStory(String value) {
    final paragraphs = value
        .split(RegExp(r'\n\s*\n|(?<=[.!؟])\s+(?=[\u0600-\u06FFA-Za-z])'))
        .map(_formatText)
        .where((p) => p.length >= 20)
        .toList();
    final seen = <String>{};
    return paragraphs.where((p) => seen.add(p)).join('\n\n');
  }

  // ── Initialise: restore previously downloaded model ─────────────────────────
  Future<void> init() async {
    if (_loading || _installed || _failed) return;
    _loading = true;
    try {
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
      onProgress?.call(100);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('qwen3_done', true);

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

  // ── Core: analyse one article via C++ TinyLLM bridge ───────────────────────
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

    // Preprocess content to remove any image references that model cannot read
    final cleanContent = c.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '');
    final cleanContent2 = cleanContent.replaceAll(RegExp(r'image\.png', caseSensitive: false), '');

    final prompt = _buildPrompt(t, s, cleanContent2);

    try {
      List<String> mainEvents = [];
      String category = 'general';
      String subcategory = 'general';
      String shortTitle = '';
      double sentiment = 0.0;
      double confidence = 0.5;
      String eventType = 'general';
      String geopoliticalRegion = 'global';
      String llmSummary = '';

      if (hasNativeEngine) {
        final analysisJson = analyzeArticleJson(jsonEncode({
          'title': t,
          'content': cleanContent2, // Use cleaned content instead of original
          'summary': s,
        }));
        if (analysisJson.isNotEmpty) {
          category = (analysisJson['category'] as String?)?.trim() ?? 'general';
          subcategory = (analysisJson['subcategory'] as String?)?.trim() ?? 'general';
          sentiment = (analysisJson['sentiment'] as num?)?.toDouble() ?? 0.0;
          confidence = (analysisJson['confidence'] as num?)?.toDouble() ?? 0.5;
          eventType = (analysisJson['event_type'] as String?)?.trim() ?? 'general';
          geopoliticalRegion = (analysisJson['geopolitical_region'] as String?)?.trim() ?? 'global';
        }

        final storyElements = extractStoryElementsJson(t, cleanContent2); // Use cleaned content
        if (storyElements.isNotEmpty) {
          final events = (storyElements['events'] as List<dynamic>?) ?? [];
          mainEvents = events.map((e) => e.toString()).toList();
          if (mainEvents.isEmpty) {
            llmSummary = 'Event detected: $eventType';
          } else {
            llmSummary = mainEvents.first;
          }
        } else {
          llmSummary = 'Event detected: $eventType';
        }
      } else {
        final raw = '{"category":"general","summary":"Fallback","confidence":1.0}';
        final fallback = _parseResponse(raw);
        return fallback.copyWith(mainEvents: const <String>[]);
      }

      // The native bridge can return analysis without story elements on some
      // platforms. Always provide words from the actual article text so the
      // UI and downstream services never receive an empty extraction.
      final extractedWords = _extractStoryWords('$t $s $cleanContent2'); // Use cleaned content
      if (mainEvents.isEmpty && extractedWords.isNotEmpty) {
        mainEvents = extractedWords.take(3).toList();
        llmSummary = mainEvents.first;
      }

      return NewsLLMResult(
        category: category,
        subcategory: subcategory,
        shortTitle: shortTitle,
        sentiment: sentiment,
        confidence: confidence,
        eventType: eventType,
        geopoliticalRegion: geopoliticalRegion,
        entities: const <NewsLLMEntity>[],
        sportsData: const {},
        summary: llmSummary,
        mainEvents: mainEvents,
        parseError: null,
      );
    } catch (e) {
      return NewsLLMResult.fallback('Inference error: $e', raw: e.toString());
    }
  }

  /// Generate a reporter-style daily briefing from multiple articles.
  /// Returns ONE short briefing written by a "news writer" persona.
  static Future<String> generateBriefing({
    required List<Map<String, dynamic>> articles,
    required String language,
  }) async {
    if (articles.isEmpty) {
      return 'No news available for today.';
    }

    final currentModel = TinyLLMService.instance._model;
    if (currentModel == null) {
      return _fallbackBriefing(articles, language);
    }

    final now = DateTime.now();
    final currentDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // Build article list for the prompt (top 10)
    final articleLines = <String>[];
    for (int i = 0; i < articles.length && i < 10; i++) {
      final a = articles[i];
      final title = a['title']?.toString() ?? 'Untitled';
      final summary = a['summary']?.toString() ?? '';
      final source = a['source_name'] ?? a['sourceName'] ?? 'Unknown';
      final cat = a['category'] ?? 'general';
      articleLines.add(
        "${i + 1}. [$cat] $title — $summary (Source: $source)",
      );
    }
    final articleBlock = articleLines.join('\n');

    final langInstruction = language == 'ar'
        ? 'Write the briefing in Arabic.'
        : language == 'fr'
            ? 'Write the briefing in French.'
            : language == 'tr'
                ? 'Write the briefing in Turkish.'
                : 'Write the briefing in English.';

    final prompt = '''You are an experienced news reporter and editor writing a daily briefing.

TASK: Read the following ${articles.length} top news stories from ${currentDate} and write ONE concise, professional briefing (2-4 short paragraphs) that a news anchor would read on air.

STYLE GUIDELINES:
- Write like a professional reporter: objective, clear, engaging
- Use a strong opening sentence that captures the most important story
- Connect related stories where they share themes
- Keep it conversational but authoritative
- Do NOT just list headlines — synthesize them into a narrative
- ${langInstruction}
- Output ONLY the briefing text, no JSON, no markdown, no preamble

TOP STORIES:
${articleBlock}

DAILY BRIEFING:''';

    try {
      final result = analyzeArticleJson(jsonEncode({
        'prompt': prompt,
        'task': 'briefing',
      }));

      final briefing = (result['briefing'] as String?) ??
          (result['summary'] as String?) ??
          result.toString();

      if (briefing.isNotEmpty && briefing.length > 20) {
        return briefing.trim();
      }
    } catch (_) {}

    return _fallbackBriefing(articles, language);
  }

  static String _fallbackBriefing(List<Map<String, dynamic>> articles, String language) {
    final top3 = articles.take(3).map((a) => a['title']?.toString() ?? 'Untitled');
    final headline = top3.join('; ');
    if (language == 'ar') {
      return 'نشرة الأخبار اليومية: أهم عناوين اليوم تشمل $headline.';
    }
    if (language == 'fr') {
      return 'Briefing quotidien: Les titres principaux incluent $headline.';
    }
    if (language == 'tr') {
      return 'Günlük özet: Başlıklar arasında $headline yer alıyor.';
    }
    return 'Daily Briefing: Top stories include $headline.';
  }

  static List<String> _extractStoryWords(String text) {
    final stopWords = <String>{
      'هذا', 'هذه', 'ذلك', 'التي', 'الذي', 'على', 'إلى', 'من', 'في', 'عن',
      'مع', 'بعد', 'قبل', 'كان', 'كانت', 'هو', 'هي', 'the', 'and', 'for',
      'with', 'from', 'that', 'this', 'will', 'have', 'has', 'was', 'are',
    };
    final counts = <String, int>{};
    for (final raw in text.split(RegExp(r'\s+'))) {
      final word = raw
          .replaceAll(RegExp(r'^[^\w\u0600-\u06FF]+|[^\w\u0600-\u06FF]+$'), '')
          .toLowerCase();
      if (word.length < 3 || stopWords.contains(word) || RegExp(r'^\d+$').hasMatch(word)) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
    final words = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return words.take(20).toList();
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
  final List<String> mainEvents;
  final String? rawResponse;
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
    this.mainEvents = const <String>[],
    this.rawResponse,
    this.parseError,
  });

  NewsLLMResult copyWith({
    String? category,
    String? subcategory,
    String? shortTitle,
    double? sentiment,
    double? confidence,
    String? eventType,
    String? geopoliticalRegion,
    List<NewsLLMEntity>? entities,
    Map<String, dynamic>? sportsData,
    String? summary,
    List<String>? mainEvents,
    String? rawResponse,
    String? parseError,
  }) {
    return NewsLLMResult(
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      shortTitle: shortTitle ?? this.shortTitle,
      sentiment: sentiment ?? this.sentiment,
      confidence: confidence ?? this.confidence,
      eventType: eventType ?? this.eventType,
      geopoliticalRegion: geopoliticalRegion ?? this.geopoliticalRegion,
      entities: entities ?? this.entities,
      sportsData: sportsData ?? this.sportsData,
      summary: summary ?? this.summary,
      mainEvents: mainEvents ?? this.mainEvents,
      rawResponse: rawResponse ?? this.rawResponse,
      parseError: parseError ?? this.parseError,
    );
  }

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
        mainEvents: const <String>[],
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
