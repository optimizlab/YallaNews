import 'dart:convert';
import 'package:http/http.dart' as http;

class OllamaService {
  OllamaService._internal();
  static final OllamaService instance = OllamaService._internal();

  static const String _defaultApiUrl = 'http://localhost:11434';
  static const String _defaultEmbedModel = 'nomic-embed-text';
  static const String _defaultGenModel = 'gemma:2b';

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
}
