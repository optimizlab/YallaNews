import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OllamaService {
  OllamaService._internal();
  static final OllamaService instance = OllamaService._internal();

  static const String _defaultApiUrl = 'http://localhost:11434';
  static const String _defaultEmbedModel = 'nomic-embed-text';
  static const String _defaultGenModel = 'gemma:2b';

  DateTime? _lastOllamaCheck;
  bool _cachedOllamaAvailable = false;

  Future<List<double>?> getEmbedding(String text) async {
    try {
      final apiUrl = _defaultApiUrl.endsWith('/') ? _defaultApiUrl.substring(0, _defaultApiUrl.length - 1) : _defaultApiUrl;
      final uri = Uri.parse('$apiUrl/api/embeddings');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _defaultEmbedModel,
          'prompt': text,
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['embedding'] != null) {
          return List<double>.from(data['embedding'].map((x) => (x as num).toDouble()));
        }
      } else {
        print('Ollama Embed Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Ollama Embed Exception: $e');
    }
    return null;
  }

  Future<String?> generateText(String prompt, {String? system}) async {
    try {
      final apiUrl = _defaultApiUrl.endsWith('/') ? _defaultApiUrl.substring(0, _defaultApiUrl.length - 1) : _defaultApiUrl;
      final uri = Uri.parse('$apiUrl/api/generate');
      
      final requestBody = <String, dynamic>{
        'model': _defaultGenModel,
        'prompt': prompt,
        'stream': false,
      };
      
      if (system != null) {
        requestBody['system'] = system;
      }

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['response'] != null) {
          return data['response'] as String;
        }
      } else {
        print('Ollama Gen Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Ollama Gen Exception: $e');
    }
    return null;
  }

  Future<String?> cleanNewsContent(String rawTitle, String rawContent) async {
    if (!await isOllamaAvailable()) return null;
    final prompt = '''
أنت صحفي محترف ومحرر أخبار. قم بتحويل النص الخام التالي إلى محتوى إخباري منشور نظيف وقابل للقراءة.
المبادئ:
- احذف كل ما ليس جزءاً من الخبر: روابط، قوائم، إعلانات، تكرارات، نصوص تالفة، وسوم.
- حافظ على الحقائق فقط ولا تضف أي معلومة غير موجودة في النص.
- استخدم لغة صحفية عربية فصحى واضحة، جمل قصيرة، وتنسيق فقرات.
- ابدأ بعنوان فرعي ثم نص الخبر منظم في فقرات قصيرة.
- إذا كان النص غير كافٍ، فاكتب ملخصاً صحفياً موجزاً وعمودياً.

العنوان: $rawTitle

النص:
$rawContent
''';

    final result = await generateText(prompt);
    return result?.trim().isNotEmpty == true ? result : null;
  }

  Future<bool> isOllamaAvailable() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Desktop Ollama server is not hosted on localhost of mobile device
      return false;
    }
    final now = DateTime.now();
    if (_lastOllamaCheck != null && now.difference(_lastOllamaCheck!).inMinutes < 5) {
      return _cachedOllamaAvailable;
    }
    try {
      final apiUrl = _defaultApiUrl.endsWith('/') ? _defaultApiUrl.substring(0, _defaultApiUrl.length - 1) : _defaultApiUrl;
      final uri = Uri.parse('$apiUrl/api/tags');
      final response = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(milliseconds: 500));
      _cachedOllamaAvailable = response.statusCode == 200;
    } catch (_) {
      _cachedOllamaAvailable = false;
    }
    _lastOllamaCheck = now;
    return _cachedOllamaAvailable;
  }

  /// Real LLM chat grounded in a specific news article.
  /// Answers ONLY from the article context; never invents facts outside it.
  Future<String?> generateChat({
    required String title,
    required String summary,
    required String content,
    required String question,
    String source = '',
    String category = '',
    String language = '',
    List<String> history = const [],
  }) async {
    if (!await isOllamaAvailable()) return null;

    final trimmedContent = content.length > 2500
        ? '${content.substring(0, 2500)}...'
        : content;

    final isArabic = language == 'ar';
    final system = isArabic
        ? 'أنت مساعد إخباري محترف. أجب فقط بناءً على المقال الموضح أدناه. إذا لم يكن الجواب موجوداً في المقال، قل بوضوح أنك لا تملك معلومات كافية بدلاً من اختراع معلومات. كن دقيقاً ومقتضباً.'
        : 'You are a professional news assistant. Answer ONLY based on the article provided below. If the answer is not in the article, say clearly that you do not have enough information instead of inventing facts. Be concise and accurate.';

    final prompt = isArabic
        ? '''المقال:
العنوان: $title
المصدر: $source
القسم: $category
الملخص: $summary
المحتوى: $trimmedContent

${history.isNotEmpty ? 'المحادثة السابقة:\n${history.join('\n')}\n' : ''}
السؤال: $question
الإجابة:'''
        : '''ARTICLE
Title: $title
Source: $source
Category: $category
Summary: $summary
Content: $trimmedContent

${history.isNotEmpty ? 'Previous conversation:\n${history.join('\n')}\n' : ''}
Question: $question
Answer:''';

    final result = await generateText(prompt, system: system);
    return result?.trim().isNotEmpty == true ? result : null;
  }
}
