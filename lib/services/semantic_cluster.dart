import 'dart:convert';
import 'dart:math';
import '../models/news_model.dart';
import 'arabic_normalizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SemanticCluster — Multi-signal article grouping
//
//  Combines three independent similarity signals:
//   1. TF-IDF cosine embedding similarity  (captures semantic meaning)
//   2. Named-entity overlap                (captures "who/what/where")
//   3. Publish-time proximity              (captures temporal relevance)
//
//  This allows grouping articles about the same event even when titles are
//  completely rewritten by different outlets.
// ─────────────────────────────────────────────────────────────────────────────
class SemanticCluster {
  // ═══════════════════════════════════════════════════════════════════════════
  //  1. TF-IDF Embedding Similarity
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build a TF-IDF sparse vector from article text.
  /// Title is weighted 3×, summary 2×, content 1× (truncated to 2000 chars).
  static Map<String, double> buildTfIdfVector(NewsModel article) {
    final title = ArabicTextNormalizer.normalize(article.title);
    final content = ArabicTextNormalizer.normalize(article.content);
    final summary = ArabicTextNormalizer.normalize(article.summary);

    final combined = '$title $title $title '
        '$summary $summary '
        '${content.length > 2000 ? content.substring(0, 2000) : content}';

    final tokens = tokenize(combined);
    final tf = <String, double>{};
    for (final tok in tokens) {
      final stemmed = stem(tok);
      tf[tok] = (tf[tok] ?? 0) + 1;
      if (stemmed != tok) {
        tf[stemmed] = (tf[stemmed] ?? 0) + 1;
      }
    }

    double norm = 0;
    for (final v in tf.values) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (final key in tf.keys.toList()) {
        tf[key] = tf[key]! / norm;
      }
    }
    return tf;
  }

  /// Cosine similarity between two TF-IDF vectors (already L2-normalized).
  static double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    double dot = 0;
    final smaller = a.length <= b.length ? a : b;
    final larger = a.length <= b.length ? b : a;
    for (final entry in smaller.entries) {
      final other = larger[entry.key];
      if (other != null) dot += entry.value * other;
    }
    return dot.clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. Entity Overlap
  // ═══════════════════════════════════════════════════════════════════════════

  /// Extract entities from LLM-produced intelligenceJson, or fall back to
  /// regex-based entity extraction from raw text.
  static Set<String> _extractEntities(NewsModel article) {
    if (article.intelligenceJson.isNotEmpty) {
      try {
        final data = jsonDecode(article.intelligenceJson) as Map<String, dynamic>;
        final entities = <String>{};

        if (data['entities'] is Map) {
          final entMap = data['entities'] as Map<String, dynamic>;
          for (final entry in entMap.entries) {
            if (entry.value is List) {
              for (final v in entry.value) {
                final s = v?.toString().trim().toLowerCase();
                if (s != null && s.length >= 2) entities.add(s);
              }
            }
          }
        } else if (data['entities'] is List) {
          for (final e in data['entities']) {
            if (e is Map<String, dynamic>) {
              final val = e['value']?.toString().trim().toLowerCase();
              if (val != null && val.length >= 2) entities.add(val);
            }
          }
        }

        final cat = data['category']?.toString().toLowerCase();
        if (cat != null && cat.isNotEmpty && cat != 'general') entities.add('_cat:$cat');
        final evt = data['event_type']?.toString().toLowerCase();
        if (evt != null && evt.isNotEmpty && evt != 'general') entities.add('_evt:$evt');

        if (entities.length >= 2) return entities;
      } catch (_) {}
    }

    if (article.structuredData.isNotEmpty) {
      final entities = <String>{};
      for (final entry in article.structuredData.entries) {
        if (entry.value is List) {
          for (final v in entry.value) {
            final s = v?.toString().trim().toLowerCase();
            if (s != null && s.length >= 2) entities.add(s);
          }
        }
      }
      if (entities.length >= 2) return entities;
    }

    return _extractEntityTokensFromText(article);
  }

  /// Regex-based entity extraction for when LLM data is unavailable.
  static Set<String> _extractEntityTokensFromText(NewsModel article) {
    final text = ArabicTextNormalizer.normalize('${article.title} ${article.content}');
    final tokens = <String>{};

    const geoTerms = <String>[
      'مصر', 'السعوديه', 'الامارات', 'الكويت', 'قطر', 'البحرين',
      'عمان', 'العراق', 'سوريا', 'لبنان', 'الاردن', 'فلسطين',
      'ليبيا', 'تونس', 'الجزائر', 'المغرب', 'السودان', 'اليمن',
      'ايران', 'تركيا', 'روسيا', 'فرنسا', 'المانيا', 'الصين',
      'الهند', 'امريكا', 'بريطانيا', 'اسرائيل', 'غزه', 'اوكرانيا',
      'القاهره', 'الرياض', 'دبي', 'بيروت', 'دمشق', 'بغداد',
      'egypt', 'saudi', 'uae', 'qatar', 'iraq', 'syria', 'iran',
      'turkey', 'russia', 'china', 'usa', 'france', 'germany',
      'gaza', 'ukraine', 'israel', 'palestine',
    ];
    final lc = text.toLowerCase();
    for (final geo in geoTerms) {
      if (lc.contains(geo)) tokens.add(geo);
    }

    const orgs = <String>[
      'الامم المتحده', 'البنك الدولي', 'الاتحاد الاوروبي', 'الناتو',
      'الفيفا', 'اوبك', 'جوجل', 'ابل', 'مايكروسوفت', 'ميتا',
      'nato', 'un', 'imf', 'fifa', 'opec', 'google', 'apple', 'microsoft',
    ];
    for (final o in orgs) {
      if (lc.contains(o)) tokens.add(o);
    }

    final pAr = RegExp(r'(?:الرئيس|الملك|الامير|الوزير|الشيخ|الدكتور)(?: )([\u0600-\u06FF]{2,}(?: [\u0600-\u06FF]{2,}){0,2})');
    final pEn = RegExp(r'(?:President|Minister|Dr\.?|Prof\.?) ([A-Z][a-z]{2,}(?: [A-Z][a-z]{2,}){0,2})');
    for (final m in pAr.allMatches(text)) {
      final name = m.group(1)?.trim().toLowerCase();
      if (name != null && name.length >= 3) tokens.add(name);
    }
    for (final m in pEn.allMatches(text)) {
      final name = m.group(1)?.trim().toLowerCase();
      if (name != null && name.length >= 3) tokens.add(name);
    }

    const teams = <String>[
      'ريال مدريد', 'برشلونه', 'الاهلي', 'الزمالك', 'مانشستر',
      'ليفربول', 'بايرن', 'real madrid', 'barcelona', 'liverpool',
      'manchester', 'bayern', 'psg', 'juventus',
    ];
    for (final t in teams) {
      if (lc.contains(t)) tokens.add(t);
    }

    for (final kw in article.keywords) {
      final k = kw.trim().toLowerCase();
      if (k.length >= 3) tokens.add(k);
    }

    if (article.category.isNotEmpty && article.category.toLowerCase() != 'general') {
      tokens.add('_cat:${article.category.toLowerCase()}');
    }

    return tokens;
  }

  /// Weighted Jaccard: intersection / union, but with a bonus for
  /// high-value entity types (persons, geo, orgs count double).
  static double _entityOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b);
    if (intersection.isEmpty) return 0.0;
    final union = a.union(b);
    double score = intersection.length / union.length;
    if (intersection.length >= 2) {
      score = (score * 1.3).clamp(0.0, 1.0);
    }
    return score;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. Publish Time Proximity
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns a 0..1 score: 1.0 for same-hour, decaying to 0.1 at ≥72h apart.
  static double _timeSimilarity(NewsModel a, NewsModel b) {
    if (a.publishDate.isEmpty || b.publishDate.isEmpty) return 0.0;

    try {
      final dateA = DateTime.tryParse(a.publishDate);
      final dateB = DateTime.tryParse(b.publishDate);
      if (dateA == null || dateB == null) return 0.0;

      final diffHours = dateA.difference(dateB).inHours.abs();
      if (diffHours <= 4) return 1.0;
      if (diffHours <= 12) return 0.9;
      if (diffHours <= 24) return 0.75;
      if (diffHours <= 48) return 0.5;
      if (diffHours <= 72) return 0.3;
      return 0.1;
    } catch (_) {
      return 0.0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Combined Similarity Score
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compute the combined similarity between two articles.
  ///
  /// Signal weights:
  ///  - TF-IDF cosine:   0.40  (semantic content similarity)
  ///  - Entity overlap:  0.35  (who/what/where)
  ///  - Time proximity:  0.10  (temporal signal)
  ///  - Keyword overlap: 0.15  (explicit tags)
  ///
  /// An article pair with high entity + content similarity but different
  /// titles will still match (unlike pure title-word overlap).
  static double calculateSimilarity(NewsModel a, NewsModel b) {
    final vecA = buildTfIdfVector(a);
    final vecB = buildTfIdfVector(b);
    final embeddingSim = cosineSimilarity(vecA, vecB);

    final entitiesA = _extractEntities(a);
    final entitiesB = _extractEntities(b);
    final entitySim = _entityOverlap(entitiesA, entitiesB);

    final timeSim = _timeSimilarity(a, b);

    final kwA = a.keywords.map((k) => k.toLowerCase().trim()).where((k) => k.length >= 2).toSet();
    final kwB = b.keywords.map((k) => k.toLowerCase().trim()).where((k) => k.length >= 2).toSet();
    final kwSim = jaccardSimilarity(kwA, kwB);

    final combined = (embeddingSim * 0.40) +
        (entitySim * 0.35) +
        (kwSim * 0.15) +
        (timeSim * 0.10);

    return combined;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Public API: Group articles about the same event
  // ═══════════════════════════════════════════════════════════════════════════

  /// Groups articles into clusters, each representing a unique news event.
  ///
  /// Uses average-linkage: a new article joins a cluster if its average
  /// similarity with all cluster members exceeds the threshold. This is
  /// more robust than single-linkage (which can chain unrelated articles).
  static List<Cluster> clusterArticles(List<NewsModel> articles, {double threshold = 0.28}) {
    final List<Cluster> clusters = [];

    for (final article in articles) {
      double bestScore = 0;
      Cluster? bestCluster;

      for (final cluster in clusters) {
        double total = 0;
        for (final member in cluster.articles) {
          total += calculateSimilarity(article, member);
        }
        final avgSim = total / cluster.articles.length;

        if (avgSim > bestScore) {
          bestScore = avgSim;
          bestCluster = cluster;
        }
      }

      if (bestScore > threshold && bestCluster != null) {
        bestCluster.articles.add(article);
      } else {
        clusters.add(Cluster(articles: [article]));
      }
    }

    return clusters;
  }

  /// Groups articles and returns a flat list where each "representative"
  /// article has its `.relatedArticles` populated with the other cluster members.
  ///
  /// This is the primary entry point for the home page.
  static List<NewsModel> groupByEvent(List<NewsModel> articles, {double threshold = 0.28}) {
    if (articles.length <= 1) return articles;

    final clusters = clusterArticles(articles, threshold: threshold);
    final List<NewsModel> result = [];

    for (final cluster in clusters) {
      cluster.articles.sort((a, b) => b.content.length.compareTo(a.content.length));
      final representative = cluster.articles.first;
      representative.relatedArticles = cluster.articles.length > 1
          ? cluster.articles.sublist(1)
          : [];
      representative.relatedArticles;
      result.add(representative);
    }

    return result;
  }

  /// Deduplicate articles — return unique articles from a list.
  /// Uses a higher threshold than grouping since we want to remove near-copies.
  static List<NewsModel> deduplicate(List<NewsModel> articles, {double threshold = 0.55}) {
    final List<NewsModel> result = [];

    for (final article in articles) {
      bool isDuplicate = false;
      for (final existing in result) {
        if (calculateSimilarity(article, existing) > threshold) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        result.add(article);
      }
    }

    return result;
  }

  /// Group articles by existing category field.
  /// This creates up to 6 category-based clusters: sports, business, tech, world, science, general.
  static List<Cluster> groupByCategory(List<NewsModel> articles) {
    final Map<String, List<NewsModel>> categoryGroups = {};
    
    for (final article in articles) {
      final cat = article.category.isNotEmpty 
          ? article.category.toLowerCase() 
          : 'general';
      categoryGroups.putIfAbsent(cat, () => []).add(article);
    }

    final List<Cluster> clusters = [];
    categoryGroups.forEach((category, catArticles) {
      if (catArticles.isNotEmpty) {
        catArticles.sort((a, b) => b.content.length.compareTo(a.content.length));
        clusters.add(Cluster(articles: catArticles, summary: null, keywords: catArticles.first.keywords));
      }
    });

    // If only one cluster exists, split it by content keywords to create more categories
    if (clusters.length < 6) {
      return _splitIntoMinCategories(articles);
    }

    return clusters;
  }

  /// Split articles into minimum 6 categories based on content keywords
  static List<Cluster> _splitIntoMinCategories(List<NewsModel> articles) {
    final List<String> defaultCategories = ['sports', 'business', 'tech', 'world', 'science', 'general'];
    final Map<String, List<NewsModel>> categoryArticles = {
      for (final c in defaultCategories) c: [],
    };

    for (final article in articles) {
      final lcContent = article.content.toLowerCase();
      final lcTitle = article.title.toLowerCase();
      final combined = '$lcTitle $lcContent';

      // Assign to first matching category
      String assignedCat = 'general';
      if (combined.contains('sport') || combined.contains('football') || combined.contains('soccer') || 
          combined.contains('كرة') || combined.contains('مباريات')) {
        assignedCat = 'sports';
      } else if (combined.contains('business') || combined.contains('econom') || combined.contains('finance') ||
                 combined.contains('اقتصاد') || combined.contains('بنوك')) {
        assignedCat = 'business';
      } else if (combined.contains('tech') || combined.contains('software') || combined.contains('phone') ||
                 combined.contains('تقنية') || combined.contains('ذكاء')) {
        assignedCat = 'tech';
      } else if (combined.contains('science') || combined.contains('research') || combined.contains('study') ||
                 combined.contains('علوم') || combined.contains('بحث')) {
        assignedCat = 'science';
      } else if (combined.contains('world') || combined.contains('international') ||
                 combined.contains('عالم') || combined.contains('دولي')) {
        assignedCat = 'world';
      }

      categoryArticles[assignedCat]!.add(article);
    }

    final List<Cluster> result = [];
    for (final cat in defaultCategories) {
      final catList = categoryArticles[cat]!;
      if (catList.isNotEmpty) {
        catList.sort((a, b) => b.content.length.compareTo(a.content.length));
        result.add(Cluster(articles: catList, summary: null, keywords: catList.first.keywords));
      }
    }

    // Ensure at least one cluster exists
    if (result.isEmpty && articles.isNotEmpty) {
      articles.sort((a, b) => b.content.length.compareTo(a.content.length));
      result.add(Cluster(articles: articles, summary: null, keywords: articles.first.keywords));
    }

    return result;
  }

  /// Ensure minimum cluster count by splitting large clusters or 
  /// forcing category-based groupings when similarity clustering produces too few.
static List<Cluster> ensureMinClusters(List<NewsModel> articles, {int minClusters = 9}) {
  print('SemanticCluster ensureMinClusters: input articles=${articles.length}, minClusters=$minClusters');
  var clusters = clusterArticles(articles);
  print('SemanticCluster ensureMinClusters: after clusterArticles clusters=${clusters.length}');
  
  if (clusters.length >= minClusters) {
    print('SemanticCluster ensureMinClusters: returning early clusters (>= minClusters)');
    return clusters;
  }
  
  // Try category-based grouping
  final categoryClusters = groupByCategory(articles);
  print('SemanticCluster ensureMinClusters: after groupByCategory clusters=${categoryClusters.length}');
  if (categoryClusters.length >= minClusters) {
    print('SemanticCluster ensureMinClusters: returning category clusters (>= minClusters)');
    return categoryClusters;
  }
  
  // Still too few - split large clusters evenly to meet minimum
  if (clusters.length == 1 && clusters.first.articles.length > 1) {
    print('SemanticCluster ensureMinClusters: splitting single large cluster');
    final List<Cluster> result = [];
    final allArticles = List<NewsModel>.from(clusters.first.articles);
    final chunkSize = (allArticles.length / minClusters).ceil();
    
    for (int i = 0; i < allArticles.length; i += chunkSize) {
      final chunk = allArticles.sublist(i, (i + chunkSize).clamp(0, allArticles.length));
      if (chunk.isNotEmpty) {
        chunk.sort((a, b) => b.content.length.compareTo(a.content.length));
        result.add(Cluster(articles: chunk, summary: null, keywords: chunk.first.keywords));
      }
    }
    print('SemanticCluster ensureMinClusters: split into ${result.length} clusters');
    return result;
  }
  
  // Return what we have if we can't split further
  if (clusters.isEmpty && articles.isNotEmpty) {
    print('SemanticCluster ensureMinClusters: returning single cluster from all articles');
    return [Cluster(articles: articles, summary: null, keywords: articles.first.keywords)];
  }
  print('SemanticCluster ensureMinClusters: returning existing clusters (${clusters.length})');
  return clusters;
}

  // ═══════════════════════════════════════════════════════════════════════════
  //  Text utilities
  // ═══════════════════════════════════════════════════════════════════════════

  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toList();
  }

  static double jaccardSimilarity(Set<String> setA, Set<String> setB) {
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB);
    final union = setA.union(setB);
    return intersection.length / union.length;
  }

  static String stem(String word) {
    if (word.length < 4) return word;
    for (final p in ['وال', 'بال', 'فال', 'لل', 'ال', 'و', 'ب', 'ف', 'ل', 'ك']) {
      if (word.startsWith(p) && word.length >= (p.length + 3)) {
        word = word.substring(p.length);
        break;
      }
    }
    for (final s in ['ية', 'يه', 'ون', 'ين', 'ات', 'ان', 'هم', 'ها', 'نا', 'ني', 'ه', 'ي']) {
      if (word.endsWith(s) && word.length >= (s.length + 3)) {
        return word.substring(0, word.length - s.length);
      }
    }
    return word;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cluster data class
// ─────────────────────────────────────────────────────────────────────────────
class Cluster {
  final List<NewsModel> articles;
  final String? summary;
  final List<String>? keywords;

  Cluster({required this.articles, this.summary, this.keywords});

  int get sourceCount {
    final hosts = <String>{};
    for (final a in articles) {
      try {
        hosts.add(Uri.parse(a.url).host);
      } catch (_) {}
    }
    return hosts.length;
  }

  Map<String, dynamic> toJson() {
    final first = articles.first;
    return {
      'representative_title': first.title,
      'representative_url': first.url,
      'article_count': articles.length,
      'sources': articles.map((a) {
        try { return Uri.parse(a.url).host; } catch (_) { return a.url; }
      }).toSet().toList(),
      'keywords': keywords ?? first.keywords,
      'summary': summary ?? first.summary,
      'articles': articles.map((a) => {
        'url': a.url,
        'title': a.title,
        'summary': a.summary,
        'keywords': a.keywords,
      }).toList(),
    };
  }
}