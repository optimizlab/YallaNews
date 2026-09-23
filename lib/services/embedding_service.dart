import 'dart:math';
import 'package:yallanews/models/news_model.dart';
import 'package:yallanews/services/semantic_cluster.dart';
import 'ollama_service.dart';

class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  static const int _maxCacheSize = 500;

  // Cache for Ollama dense embeddings (url -> vector)
  final Map<String, List<double>> _denseCache = {};

  // Cache for TF-IDF sparse embeddings (url -> vector)
  final Map<String, Map<String, double>> _sparseCache = {};

  /// Returns an Ollama dense embedding if available, falls back to null.
  /// Call this in async contexts (background crawling, blending).
  Future<List<double>?> getDenseEmbedding(NewsModel article) async {
    final key = article.url;
    if (_denseCache.containsKey(key)) return _denseCache[key]!;

    final text = '${article.title} ${article.summary}';
    final vector = await OllamaService.instance.getEmbedding(text);
    if (vector != null) {
      _denseCache[key] = vector;
      if (_denseCache.length > _maxCacheSize) {
        final oldest = _denseCache.keys.first;
        _denseCache.remove(oldest);
      }
      return vector;
    }
    return null; // Ollama not available
  }

  /// Synchronous TF-IDF fallback embedding (always available).
  Map<String, double> getSparseFallback(NewsModel article) {
    final key = article.url;
    if (_sparseCache.containsKey(key)) return _sparseCache[key]!;
    final vector = SemanticCluster.buildTfIdfVector(article);
    _sparseCache[key] = vector;
    if (_sparseCache.length > _maxCacheSize) {
      final oldest = _sparseCache.keys.first;
      _sparseCache.remove(oldest);
    }
    return vector;
  }

  // Legacy sync getter for backward compatibility
  Map<String, double> getEmbedding(NewsModel article) => getSparseFallback(article);

  /// Cosine similarity between two dense Ollama vectors.
  static double denseCosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0.0 : (dot / denom).clamp(0.0, 1.0);
  }

  /// Legacy sparse cosine similarity (TF-IDF fallback).
  static double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    return SemanticCluster.cosineSimilarity(a, b);
  }

  void clearCache() {
    _denseCache.clear();
    _sparseCache.clear();
  }
}