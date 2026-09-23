import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/models/news_model.dart';
import 'package:yallanews/services/embedding_service.dart';

void main() {
  group('EmbeddingService', () {
    final now = DateTime.now().toIso8601String();

    NewsModel createArticle({
      required String title,
      required String content,
      required String category,
    }) {
      return NewsModel(
        url: 'https://example.com/${title.replaceAll(' ', '-')}',
        title: title,
        shortTitle: '',
        summary: content,
        content: content,
        imageUrl: 'https://example.com/image.jpg',
        category: category,
        sentiment: 0.0,
        keywords: const [],
        logs: '',
        author: 'Test',
        publishDate: now,
        eventType: 'general',
        subcategory: 'general',
        entities: const [],
        structuredData: const {},
        intelligenceJson: '',
        metaTags: const {},
        hashtags: '',
        youtubeVideoId: '',
        instagramVideoId: '',
        twitterVideoUrl: '',
        imageId: '',
        sourceCount: 1,
        sources: const [],
      );
    }

    test('getEmbedding returns non-empty map', () {
      final article = createArticle(
        title: 'Government announces new policy',
        content: 'The government announced a new policy today that will affect the economy.',
        category: 'politics',
      );
      final embedding = EmbeddingService.instance.getEmbedding(article);
      expect(embedding, isA<Map<String, double>>());
      expect(embedding.isNotEmpty, isTrue);
    });

    test('getEmbedding caches result for same URL', () {
      final article = createArticle(
        title: 'Cached article',
        content: 'This article should be cached.',
        category: 'general',
      );
      final first = EmbeddingService.instance.getEmbedding(article);
      final second = EmbeddingService.instance.getEmbedding(article);
      expect(first, equals(second));
    });

    test('cosineSimilarity returns 1.0 for identical vectors', () {
      final v = {'word': 1.0, 'test': 0.5};
      expect(EmbeddingService.cosineSimilarity(v, v), closeTo(1.0, 0.01));
    });

    test('cosineSimilarity returns 0.0 for disjoint vectors', () {
      final a = {'word': 1.0};
      final b = {'test': 1.0};
      expect(EmbeddingService.cosineSimilarity(a, b), equals(0.0));
    });

    test('clearCache does not throw', () {
      final article = createArticle(
        title: 'Cache test article',
        content: 'Content for cache testing.',
        category: 'general',
      );
      EmbeddingService.instance.getEmbedding(article);
      expect(() => EmbeddingService.instance.clearCache(), returnsNormally);
    });
  });
}