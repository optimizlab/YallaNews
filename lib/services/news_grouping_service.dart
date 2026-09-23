import '../models/news_model.dart';
import 'arabic_normalizer.dart';
import 'semantic_cluster.dart';
import 'embedding_service.dart';

/// Represents a cluster of news articles covering the same subject or event
class SubjectCluster {
  final String subjectTitle;
  final String category;
  final List<NewsModel> articles;

  SubjectCluster({
    required this.subjectTitle,
    required this.category,
    required this.articles,
  });

  int get sourceCount {
    final hosts = <String>{};
    for (final a in articles) {
      try {
        final host = Uri.parse(a.url).host.toLowerCase();
        if (host.isNotEmpty) hosts.add(host);
      } catch (_) {
        hosts.add(a.url);
      }
    }
    return hosts.isNotEmpty ? hosts.length : articles.length;
  }
}

class NewsGroupingService {
  NewsGroupingService._internal();
  static final NewsGroupingService instance = NewsGroupingService._internal();

  static const int _minTitleWords = 3;
  static const double _titleSimilarityThreshold = 0.32;
  static const double _semanticSimilarityThreshold = 0.28;
  static const double _ollamaEmbeddingThreshold = 0.82;

  bool hasValidTitle(NewsModel article) {
    final words = article.title.trim().split(RegExp(r'\s+'));
    return words.length >= _minTitleWords;
  }

  List<NewsModel> filterValidTitles(List<NewsModel> articles) {
    return articles.where(hasValidTitle).toList();
  }

  /// Groups articles into rich SubjectClusters using Ollama dense embeddings.
  /// Falls back to TF-IDF + title overlap if Ollama is not reachable.
  Future<List<SubjectCluster>> groupBySubjectAsync(List<NewsModel> articles) async {
    if (articles.isEmpty) return const [];
    final valid = filterValidTitles(articles);

    // Try to get Ollama embeddings for all articles
    final embeddings = <String, List<double>?>{};
    bool ollamaAvailable = false;
    for (final a in valid) {
      final vec = await EmbeddingService.instance.getDenseEmbedding(a);
      embeddings[a.url] = vec;
      if (vec != null) ollamaAvailable = true;
    }

    final clusters = <List<NewsModel>>[];
    final assigned = <NewsModel>{};

    for (final article in valid) {
      if (assigned.contains(article)) continue;
      final cluster = <NewsModel>[article];
      assigned.add(article);
      final normalizedTitle = _normalize(article.title);
      final vecA = embeddings[article.url];

      for (final other in valid) {
        if (assigned.contains(other)) continue;
        if (!_isSameCategory(article, other)) continue;

        bool isMatch = false;

        if (ollamaAvailable && vecA != null) {
          // Primary signal: Ollama dense embedding cosine similarity (strict)
          final vecB = embeddings[other.url];
          if (vecB != null) {
            final sim = EmbeddingService.denseCosineSimilarity(vecA, vecB);
            isMatch = sim >= _ollamaEmbeddingThreshold;
          } else {
            // One has Ollama vector, other doesn't — fall back to TF-IDF
            final semanticSim = SemanticCluster.calculateSimilarity(article, other);
            isMatch = semanticSim >= _semanticSimilarityThreshold;
          }
        } else {
          // Ollama not available — use TF-IDF + title overlap fallback
          final otherNormalized = _normalize(other.title);
          final titleSim = _computeSimilarity(normalizedTitle, otherNormalized);
          final semanticSim = SemanticCluster.calculateSimilarity(article, other);
          isMatch = titleSim >= _titleSimilarityThreshold || semanticSim >= _semanticSimilarityThreshold;
        }

        if (isMatch) {
          cluster.add(other);
          assigned.add(other);
        }
      }
      clusters.add(cluster);
    }

    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.map((cList) {
      cList.sort((a, b) => _sourcePriority(b).compareTo(_sourcePriority(a)));
      final subjectTitle = _extractSubjectTitle(cList);
      final category = cList.first.category;
      return SubjectCluster(subjectTitle: subjectTitle, category: category, articles: cList);
    }).toList();
  }

  /// Synchronous fallback grouping (TF-IDF + title overlap). Used when async is not possible.
  List<SubjectCluster> groupBySubject(List<NewsModel> articles) {
    if (articles.isEmpty) return const [];

    final valid = filterValidTitles(articles);
    final clusters = <List<NewsModel>>[];
    final assigned = <NewsModel>{};

    for (final article in valid) {
      if (assigned.contains(article)) continue;

      final cluster = <NewsModel>[article];
      assigned.add(article);

      final normalizedTitle = _normalize(article.title);

      for (final other in valid) {
        if (assigned.contains(other)) continue;
        if (!_isSameCategory(article, other)) continue;

        final otherNormalized = _normalize(other.title);
        final titleSim = _computeSimilarity(normalizedTitle, otherNormalized);
        final semanticSim = SemanticCluster.calculateSimilarity(article, other);

        if (titleSim >= _titleSimilarityThreshold || semanticSim >= _semanticSimilarityThreshold) {
          cluster.add(other);
          assigned.add(other);
        }
      }

      clusters.add(cluster);
    }

    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.map((cList) {
      cList.sort((a, b) => _sourcePriority(b).compareTo(_sourcePriority(a)));
      final subjectTitle = _extractSubjectTitle(cList);
      final category = cList.first.category;
      return SubjectCluster(subjectTitle: subjectTitle, category: category, articles: cList);
    }).toList();
  }

  /// Extracts the most representative topic/subject name for a cluster
  String _extractSubjectTitle(List<NewsModel> cluster) {
    if (cluster.isEmpty) return '';
    if (cluster.length == 1) return cluster.first.title;

    // Look for shared named entities across articles
    final entityFreq = <String, int>{};
    for (final art in cluster) {
      for (final ent in art.entities) {
        final clean = ent.trim();
        if (clean.length >= 3) {
          entityFreq[clean] = (entityFreq[clean] ?? 0) + 1;
        }
      }
    }

    // If strong shared entities exist, construct a concise subject label
    final sortedEntities = entityFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedEntities.isNotEmpty && sortedEntities.first.value >= 2) {
      final topEntities = sortedEntities.take(2).map((e) => e.key).join(' • ');
      return topEntities;
    }

    // Fallback: pick the highest quality headline from the most authoritative source
    return cluster.first.title;
  }

  /// Groups articles purely by similarity (returns lists of NewsModel)
  List<List<NewsModel>> groupBySimilarity(List<NewsModel> articles) {
    final subjectClusters = groupBySubject(articles);
    return subjectClusters.map((sc) => sc.articles).toList();
  }

  /// Legacy helper: returns flat list of representative articles with sources populated
  List<NewsModel> getRepresentativeArticles(List<NewsModel> articles) {
    if (articles.length <= 1) return List.from(articles);

    final clusters = groupBySimilarity(articles);
    final result = <NewsModel>[];
    for (final cluster in clusters) {
      if (cluster.isEmpty) continue;

      cluster.sort((a, b) {
        final aScore = _sourcePriority(a);
        final bScore = _sourcePriority(b);
        return bScore.compareTo(aScore);
      });

      final best = cluster.first;
      final seen = <String>{best.url};
      final sources = [best.url];

      for (final other in cluster.skip(1)) {
        if (!seen.contains(other.url)) {
          seen.add(other.url);
          sources.add(other.url);
        }
      }

      final representative = best.copyWith(
        sourceCount: sources.length,
        sources: sources,
        relatedArticles: cluster,
      );
      result.add(representative);
    }
    return result;
  }

  int _sourcePriority(NewsModel article) {
    final url = article.url.toLowerCase();
    if (url.contains('hespress.com')) return 10;
    if (url.contains('le360.ma')) return 9;
    if (url.contains('alyaoum24.com')) return 8;
    if (url.contains('almountakhab.com')) return 7;
    if (url.contains('chouftv.ma')) return 6;
    if (url.contains('febrayer.com')) return 5;
    if (url.contains('rue20.com')) return 4;
    if (url.contains('barlamane.com')) return 3;
    if (url.contains('al3omk.com')) return 2;
    if (url.contains('ifada.ma')) return 1;
    return 0;
  }

  bool _isSameCategory(NewsModel a, NewsModel b) {
    if (a.category == b.category) return true;

    final aCat = a.category.toLowerCase();
    final bCat = b.category.toLowerCase();

    const equivalentGroups = [
      {'world', 'international'},
      {'politics', 'world'},
      {'business', 'economy'},
      {'technology', 'tech'},
      {'general_news', 'general'},
      {'sport', 'sports'},
    ];

    for (final group in equivalentGroups) {
      if (group.contains(aCat) && group.contains(bCat)) {
        return true;
      }
    }

    return false;
  }

  String _normalize(String text) {
    var normalized = ArabicTextNormalizer.normalize(text);
    normalized = normalized.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  double _computeSimilarity(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final wordsB = b.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

    if (wordsA.isEmpty || wordsB.isEmpty) return 0.0;

    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;

    return union == 0 ? 0.0 : intersection / union;
  }
}
