import 'package:flutter/foundation.dart';
import '../models/news_model.dart';
import 'arabic_normalizer.dart';
import 'semantic_cluster.dart';
import 'embedding_service.dart';
import 'ollama_service.dart';

class _GroupBySubjectInput {
  final List<NewsModel> articles;
  final double titleSimilarityThreshold;
  final double semanticSimilarityThreshold;
  _GroupBySubjectInput(this.articles, this.titleSimilarityThreshold, this.semanticSimilarityThreshold);
}

List<SubjectCluster> _groupBySubjectIsolate(_GroupBySubjectInput input) {
  return NewsGroupingService._groupBySubjectSync(input.articles, input.titleSimilarityThreshold, input.semanticSimilarityThreshold);
}

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
  static const double _titleSimilarityThreshold = 0.48;
  static const double _semanticSimilarityThreshold = 0.45;
  static const double _ollamaEmbeddingThreshold = 0.85;

  bool hasValidTitle(NewsModel article) {
    final words = article.title.trim().split(RegExp(r'\s+'));
    return words.length >= _minTitleWords;
  }

  List<NewsModel> filterValidTitles(List<NewsModel> articles) {
    return articles.where(hasValidTitle).toList();
  }

  /// Fast in-memory deduplication of articles by URL and title similarity
  static List<NewsModel> fastDeduplicate(List<NewsModel> articles, {double titleThreshold = 0.55}) {
    if (articles.length <= 1) return articles;

    final seenUrls = <String>{};
    final unique = <NewsModel>[];

    for (final a in articles) {
      final cleanUrl = a.url.trim().toLowerCase();
      if (cleanUrl.isNotEmpty && seenUrls.add(cleanUrl)) {
        unique.add(a);
      }
    }

    final n = unique.length;
    final titleWords = List<Set<String>>.generate(
      n,
      (i) => ArabicTextNormalizer.extractSignificantWords(unique[i].title),
    );

    final toRemove = <int>{};
    for (int i = 0; i < n; i++) {
      if (toRemove.contains(i)) continue;
      final wordsA = titleWords[i];
      if (wordsA.isEmpty) continue;

      for (int j = i + 1; j < n; j++) {
        if (toRemove.contains(j)) continue;
        final wordsB = titleWords[j];
        if (wordsB.isEmpty) continue;

        final sim = _jaccard(wordsA, wordsB);
        if (sim >= titleThreshold) {
          // Keep the one with better content or image
          final scoreA = _qualityScore(unique[i]);
          final scoreB = _qualityScore(unique[j]);
          if (scoreB > scoreA) {
            toRemove.add(i);
            break; // i is removed, move to next i
          } else {
            toRemove.add(j);
          }
        }
      }
    }

    final result = <NewsModel>[];
    for (int i = 0; i < n; i++) {
      if (!toRemove.contains(i)) {
        result.add(unique[i]);
      }
    }
    return result;
  }

  static double _qualityScore(NewsModel a) {
    double s = 0.0;
    if (a.imageUrl.isNotEmpty && !a.imageUrl.contains('placeholder')) s += 5.0;
    if (a.content.length > 200) s += 4.0;
    if (a.summary.length > 50) s += 2.0;
    if (a.author.isNotEmpty) s += 1.0;
    s += _sourcePriority(a);
    return s;
  }

  /// Precomputed, vectorized synchronous grouping engine (O(N) vectorization + fast O(N²) float math)
  static List<SubjectCluster> _groupBySubjectSync(
    List<NewsModel> articles,
    double titleThreshold,
    double semanticThreshold,
  ) {
    if (articles.isEmpty) return const [];
    final valid = articles.where((a) => a.title.trim().split(RegExp(r'\s+')).length >= _minTitleWords).toList();
    if (valid.isEmpty) return const [];
    if (valid.length == 1) {
      return [
        SubjectCluster(
          subjectTitle: valid.first.title,
          category: valid.first.category,
          articles: valid,
        )
      ];
    }

    final n = valid.length;
    // 1. Precalculate all features once (O(N))
    final titleWords = List<Set<String>>.generate(
      n,
      (i) => ArabicTextNormalizer.extractSignificantWords(valid[i].title),
    );
    final tfidfVectors = List<Map<String, double>>.generate(
      n,
      (i) => SemanticCluster.buildTfIdfVector(valid[i]),
    );
    final entitySets = List<Set<String>>.generate(
      n,
      (i) => SemanticCluster.extractEntities(valid[i]),
    );

    final clusters = <List<NewsModel>>[];
    final assignedIndices = <int>{};

    for (int i = 0; i < n; i++) {
      if (assignedIndices.contains(i)) continue;
      final cluster = <NewsModel>[valid[i]];
      assignedIndices.add(i);

      final wordsA = titleWords[i];
      final vecA = tfidfVectors[i];
      final entA = entitySets[i];

      for (int j = i + 1; j < n; j++) {
        if (assignedIndices.contains(j)) continue;

        final wordsB = titleWords[j];
        final titleSim = _jaccard(wordsA, wordsB);
        final contentSim = SemanticCluster.cosineSimilarity(vecA, tfidfVectors[j]);
        final entitySim = SemanticCluster.entityOverlap(entA, entitySets[j]);
        final isCategoryCompatible = _isSameCategory(valid[i], valid[j]);

        bool isMatch = false;

        // Condition 1: High title similarity (shared headline keywords)
        if (titleSim >= titleThreshold) {
          isMatch = true;
        }
        // Condition 2: Solid title overlap + good content or entity overlap
        else if (titleSim >= 0.30 && (contentSim >= 0.35 || entitySim >= 0.35)) {
          isMatch = true;
        }
        // Condition 3: Strong semantic content overlap in compatible category
        else if (contentSim >= 0.55 && isCategoryCompatible) {
          isMatch = true;
        }
        // Condition 4: Shared key entities + related narrative
        else if (entitySim >= 0.50 && contentSim >= 0.30 && (titleSim >= 0.18 || isCategoryCompatible)) {
          isMatch = true;
        }

        if (isMatch) {
          cluster.add(valid[j]);
          assignedIndices.add(j);
        }
      }

      clusters.add(cluster);
    }

    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.map((cList) {
      cList.sort((a, b) => _sourcePriority(b).compareTo(_sourcePriority(a)));
      final subjectTitle = _extractSubjectTitle(cList);
      final category = _resolveClusterCategory(cList);
      return SubjectCluster(subjectTitle: subjectTitle, category: category, articles: cList);
    }).toList();
  }

  /// Groups articles into rich SubjectClusters using Ollama dense embeddings if available.
  /// Falls back to fast precomputed TF-IDF + title overlap.
  Future<List<SubjectCluster>> groupBySubjectAsync(List<NewsModel> articles) async {
    if (articles.isEmpty) return const [];
    final valid = filterValidTitles(articles);
    if (valid.isEmpty) return const [];
    if (valid.length == 1) {
      return [
        SubjectCluster(
          subjectTitle: valid.first.title,
          category: valid.first.category,
          articles: valid,
        )
      ];
    }

    final ollamaAvailable = await OllamaService.instance.isOllamaAvailable();
    if (!ollamaAvailable) {
      return compute(
        _groupBySubjectIsolate,
        _GroupBySubjectInput(valid, _titleSimilarityThreshold, _semanticSimilarityThreshold),
      );
    }

    final embeddings = <String, List<double>?>{};
    for (final a in valid) {
      final vec = await EmbeddingService.instance.getDenseEmbedding(a);
      embeddings[a.url] = vec;
    }

    final n = valid.length;
    final titleWords = List<Set<String>>.generate(
      n,
      (i) => ArabicTextNormalizer.extractSignificantWords(valid[i].title),
    );
    final tfidfVectors = List<Map<String, double>>.generate(
      n,
      (i) => SemanticCluster.buildTfIdfVector(valid[i]),
    );
    final entitySets = List<Set<String>>.generate(
      n,
      (i) => SemanticCluster.extractEntities(valid[i]),
    );

    final clusters = <List<NewsModel>>[];
    final assigned = <int>{};

    for (int i = 0; i < n; i++) {
      if (assigned.contains(i)) continue;
      final cluster = <NewsModel>[valid[i]];
      assigned.add(i);

      final vecA = embeddings[valid[i].url];
      final wordsA = titleWords[i];
      final tfidfA = tfidfVectors[i];
      final entA = entitySets[i];

      for (int j = i + 1; j < n; j++) {
        if (assigned.contains(j)) continue;

        final wordsB = titleWords[j];
        final titleSim = _jaccard(wordsA, wordsB);
        final contentSim = SemanticCluster.cosineSimilarity(tfidfA, tfidfVectors[j]);
        final entitySim = SemanticCluster.entityOverlap(entA, entitySets[j]);
        final isCategoryCompatible = _isSameCategory(valid[i], valid[j]);

        bool isMatch = false;

        final vecB = embeddings[valid[j].url];
        if (vecA != null && vecB != null) {
          final denseSim = EmbeddingService.denseCosineSimilarity(vecA, vecB);
          if (denseSim >= _ollamaEmbeddingThreshold) {
            isMatch = true;
          }
        }

        if (!isMatch) {
          if (titleSim >= _titleSimilarityThreshold) {
            isMatch = true;
          } else if (titleSim >= 0.30 && (contentSim >= 0.35 || entitySim >= 0.35)) {
            isMatch = true;
          } else if (contentSim >= 0.55 && isCategoryCompatible) {
            isMatch = true;
          } else if (entitySim >= 0.50 && contentSim >= 0.30 && (titleSim >= 0.18 || isCategoryCompatible)) {
            isMatch = true;
          }
        }

        if (isMatch) {
          cluster.add(valid[j]);
          assigned.add(j);
        }
      }
      clusters.add(cluster);
    }

    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.map((cList) {
      cList.sort((a, b) => _sourcePriority(b).compareTo(_sourcePriority(a)));
      final subjectTitle = _extractSubjectTitle(cList);
      final category = _resolveClusterCategory(cList);
      return SubjectCluster(subjectTitle: subjectTitle, category: category, articles: cList);
    }).toList();
  }

  /// Synchronous fallback grouping
  List<SubjectCluster> groupBySubject(List<NewsModel> articles) {
    return _groupBySubjectSync(articles, _titleSimilarityThreshold, _semanticSimilarityThreshold);
  }

  /// Extracts the most representative topic/subject name for a cluster
  static String _extractSubjectTitle(List<NewsModel> cluster) {
    if (cluster.isEmpty) return '';
    if (cluster.length == 1) return cluster.first.title;

    final entityFreq = <String, int>{};
    for (final art in cluster) {
      for (final ent in art.entities) {
        final clean = ent.trim();
        if (clean.length >= 3) {
          entityFreq[clean] = (entityFreq[clean] ?? 0) + 1;
        }
      }
    }

    final sortedEntities = entityFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedEntities.isNotEmpty && sortedEntities.first.value >= 2) {
      return sortedEntities.take(2).map((e) => e.key).join(' • ');
    }

    return cluster.first.title;
  }

  /// Resolves the most specific, accurate category across contributing articles
  static String _resolveClusterCategory(List<NewsModel> cluster) {
    for (final a in cluster) {
      final c = a.category.toLowerCase().trim();
      if (c.isNotEmpty && c != 'general' && c != 'general_news' && c != 'local' && c != 'world') {
        return c;
      }
    }
    return cluster.first.category.isNotEmpty ? cluster.first.category : 'general';
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

      cluster.sort((a, b) => _sourcePriority(b).compareTo(_sourcePriority(a)));

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

  static int _sourcePriority(NewsModel article) {
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

  static bool _isSameCategory(NewsModel a, NewsModel b) {
    if (a.category.toLowerCase() == b.category.toLowerCase()) return true;

    final aCat = a.category.toLowerCase().trim();
    final bCat = b.category.toLowerCase().trim();

    if (aCat == 'general' || bCat == 'general' || aCat == 'general_news' || bCat == 'general_news') {
      return true; // General can match with any topic if text similarity is high
    }

    const equivalentGroups = [
      {'world', 'international', 'general'},
      {'politics', 'world', 'local'},
      {'business', 'economy', 'markets'},
      {'technology', 'tech'},
      {'general_news', 'general', 'local'},
      {'sport', 'sports', 'football'},
      {'arts', 'entertainment', 'culture'},
    ];

    for (final group in equivalentGroups) {
      if (group.contains(aCat) && group.contains(bCat)) {
        return true;
      }
    }

    return false;
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0.0 : intersection / union;
  }
}
