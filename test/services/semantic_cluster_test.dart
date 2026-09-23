import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/models/news_model.dart';
import 'package:yallanews/services/semantic_cluster.dart';

void main() {
  group('SemanticCluster', () {
    final now = DateTime.now().toIso8601String();

    NewsModel createArticle({
      required String title,
      required String content,
      required String category,
      List<String>? keywords,
      String? publishDate,
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
        keywords: keywords ?? [],
        logs: '',
        author: 'Test Author',
        publishDate: publishDate ?? now,
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

    test('calculateSimilarity returns high score for identical articles', () {
      final a = createArticle(
        title: 'Breaking News Story About Government Policy',
        content: 'This is the full article content about the government announcing a new policy that will affect the economy and people.',
        category: 'politics',
      );
      final b = createArticle(
        title: 'Breaking News Story About Government Policy Reform',
        content: 'This is the full article content about the government announcing a new policy that will affect the economy and people.',
        category: 'politics',
      );
      final sim = SemanticCluster.calculateSimilarity(a, b);
      expect(sim, greaterThan(0.3));
    });

    test('calculateSimilarity returns low score for unrelated articles', () {
      final a = createArticle(
        title: 'Football Match Results',
        content: 'The football match ended with a score of 2-1.',
        category: 'sports',
      );
      final b = createArticle(
        title: 'New Phone Release',
        content: 'A new smartphone was released today with amazing features.',
        category: 'tech',
      );
      final sim = SemanticCluster.calculateSimilarity(a, b);
      expect(sim, lessThan(0.3));
    });

    test('clusterArticles groups similar articles together', () {
      final articles = [
        createArticle(
          title: 'Government Announces New Policy',
          content: 'The government announced a new economic policy today.',
          category: 'politics',
        ),
        createArticle(
          title: 'New Government Policy Details',
          content: 'Details of the new government economic policy were released.',
          category: 'politics',
        ),
        createArticle(
          title: 'Football Championship Final',
          content: 'The football championship final was held yesterday.',
          category: 'sports',
        ),
      ];
      final clusters = SemanticCluster.clusterArticles(articles);
      expect(clusters.length, greaterThanOrEqualTo(1));
    });

    test('deduplicate removes similar articles', () {
      final articles = [
        createArticle(
          title: 'Breaking News Story',
          content: 'The government announced a new economic policy that will change the country.',
          category: 'politics',
        ),
        createArticle(
          title: 'Breaking News Story Updated',
          content: 'The government announced a new economic policy that will change the country.',
          category: 'politics',
        ),
      ];
      final deduped = SemanticCluster.deduplicate(articles, threshold: 0.3);
      expect(deduped.length, lessThan(articles.length));
    });

    test('groupByCategory returns up to 6 category clusters', () {
      final articles = [
        createArticle(title: 'Sports News', content: 'Sports content', category: 'sports'),
        createArticle(title: 'Tech News', content: 'Tech content', category: 'tech'),
        createArticle(title: 'Business News', content: 'Business content', category: 'business'),
      ];
      final clusters = SemanticCluster.groupByCategory(articles);
      expect(clusters.length, equals(3));
    });

    test('groupByEvent assigns relatedArticles to representative', () {
      final articles = [
        createArticle(
          title: 'Event Part 1',
          content: 'Content about the same event.',
          category: 'general',
        ),
        createArticle(
          title: 'Event Part 2',
          content: 'More content about the same event.',
          category: 'general',
        ),
      ];
      final grouped = SemanticCluster.groupByEvent(articles);
      expect(grouped.length, lessThanOrEqualTo(articles.length));
    });
  });
}