import '../models/news_model.dart';
/// Freshness classifications.
enum FreshnessClass {
  veryFresh,   // 0-1 hour
  fresh,       // 1-6 hours
  recent,      // 6-24 hours
  older,       // 24-48 hours
  backfill,    // 48-72 hours
  archive,     // >72 hours
  unknownDate, // publication date unknown
}

extension FreshnessClassExt on FreshnessClass {
  String get label => switch (this) {
        FreshnessClass.veryFresh => 'VERY_FRESH',
        FreshnessClass.fresh => 'FRESH',
        FreshnessClass.recent => 'RECENT',
        FreshnessClass.older => 'OLDER',
        FreshnessClass.backfill => 'BACKFILL',
        FreshnessClass.archive => 'ARCHIVE',
        FreshnessClass.unknownDate => 'UNKNOWN_DATE',
      };
  int get sortOrder => switch (this) {
        FreshnessClass.veryFresh => 0,
        FreshnessClass.fresh => 1,
        FreshnessClass.recent => 2,
        FreshnessClass.older => 3,
        FreshnessClass.backfill => 4,
        FreshnessClass.archive => 5,
        FreshnessClass.unknownDate => 6,
      };
}

/// Configurable freshness thresholds.
class FreshnessConfig {
  /// 0-1 hour
  final Duration veryFreshMax;
  /// 1-6 hours
  final Duration freshMax;
  /// 6-24 hours
  final Duration recentMax;
  /// 24-48 hours
  final Duration olderMax;
  /// 48-72 hours
  final Duration backfillMax;
  /// Articles older than this are ARCHIVE.
  final Duration archiveMax;

  const FreshnessConfig({
    this.veryFreshMax = const Duration(hours: 1),
    this.freshMax = const Duration(hours: 6),
    this.recentMax = const Duration(hours: 24),
    this.olderMax = const Duration(hours: 48),
    this.backfillMax = const Duration(hours: 72),
    this.archiveMax = const Duration(hours: 72),
  });
}

/// Classifies articles by publication-date freshness and provides
/// sorting/filtering helpers.
class FreshnessEngine {
  final FreshnessConfig config;

  FreshnessEngine({FreshnessConfig? config}) : config = config ?? const FreshnessConfig();

  /// Classify a single article. Unknown dates -> unknownDate (lowest priority).
  FreshnessClass classify(NewsModel article) {
    final pub = article.publicationDate;
    if (pub == null) return FreshnessClass.unknownDate;
    if (pub.isAfter(DateTime.now())) return FreshnessClass.veryFresh; // future = treat as breaking
    final age = DateTime.now().difference(pub);
    if (age <= config.veryFreshMax) return FreshnessClass.veryFresh;
    if (age <= config.freshMax) return FreshnessClass.fresh;
    if (age <= config.recentMax) return FreshnessClass.recent;
    if (age <= config.olderMax) return FreshnessClass.older;
    if (age <= config.backfillMax) return FreshnessClass.backfill;
    return FreshnessClass.archive;
  }

  /// Classify and annotate [article] with its freshness class in [metaTags].
  NewsModel annotate(NewsModel article) {
    final cls = classify(article);
    final updated = {...article.metaTags}
      ..['freshness_class'] = cls.label
      ..['freshness_sort_order'] = cls.sortOrder;
    return article.copyWith(metaTags: updated);
  }

  /// Sort articles newest-first: known recent dates first, unknown dates last.
  List<NewsModel> sortNewestFirst(List<NewsModel> articles) {
    final annotated = articles.map(annotate).toList();
    annotated.sort((a, b) {
      final pa = a.publicationDate;
      final pb = b.publicationDate;
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1; // unknown last
      if (pb == null) return -1;
      return pb.compareTo(pa); // newest first
    });
    return annotated;
  }

  /// Filter to articles at least as fresh as [minClass]. Unknown-date articles
  /// are excluded unless [includeUnknown] is true.
  List<NewsModel> filterAtLeastFresh(List<NewsModel> articles,
      {FreshnessClass minClass = FreshnessClass.recent, bool includeUnknown = false}) {
    return articles.where((a) {
      final cls = classify(a);
      if (cls == FreshnessClass.unknownDate) return includeUnknown;
      return cls.sortOrder <= minClass.sortOrder;
    }).toList();
  }

  /// Returns true when [a] is strictly fresher than [b].
  bool isFresher(NewsModel a, NewsModel b) {
    final ca = classify(a);
    final cb = classify(b);
    if (ca != cb) return ca.sortOrder < cb.sortOrder;
    final pa = a.publicationDate;
    final pb = b.publicationDate;
    if (pa == null && pb == null) return false;
    if (pa == null) return false;
    if (pb == null) return true;
    return pa.isAfter(pb);
  }
}
