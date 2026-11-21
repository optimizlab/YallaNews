import 'freshness_engine.dart';

/// A single URL candidate waiting to be fetched and processed.
class CrawlCandidate {
  final String url;
  final String sourceId;
  final String? sourceUrl;
  final String? titleHint;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final DateTime discoveredAt;
  final String discoveryMethod; // rss | sitemap | category | homepage | webview
  final String? language;
  CrawlStatus status;
  final int attempts;
  final DateTime? firstAttemptedAt;
  final String? lastError;
  final FreshnessClass freshness;
  final int sourcePriority;
  final DateTime? retryAfter;

  CrawlCandidate({
    required this.url,
    required this.sourceId,
    this.sourceUrl,
    this.titleHint,
    this.publishedAt,
    this.updatedAt,
    DateTime? discoveredAt,
    required this.discoveryMethod,
    this.language,
    this.status = CrawlStatus.pending,
    this.attempts = 0,
    this.firstAttemptedAt,
    this.lastError,
    required this.freshness,
    this.sourcePriority = 0,
    this.retryAfter,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  CrawlCandidate copyWith({
    String? url,
    String? sourceId,
    String? sourceUrl,
    String? titleHint,
    DateTime? publishedAt,
    DateTime? updatedAt,
    DateTime? discoveredAt,
    String? discoveryMethod,
    String? language,
    CrawlStatus? status,
    int? attempts,
    DateTime? firstAttemptedAt,
    String? lastError,
    FreshnessClass? freshness,
    int? sourcePriority,
    DateTime? retryAfter,
  }) {
    return CrawlCandidate(
      url: url ?? this.url,
      sourceId: sourceId ?? this.sourceId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      titleHint: titleHint ?? this.titleHint,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      language: language ?? this.language,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      firstAttemptedAt: firstAttemptedAt ?? this.firstAttemptedAt,
      lastError: lastError ?? this.lastError,
      freshness: freshness ?? this.freshness,
      sourcePriority: sourcePriority ?? this.sourcePriority,
      retryAfter: retryAfter ?? this.retryAfter,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'source_id': sourceId,
        'source_url': sourceUrl,
        'title_hint': titleHint,
        'published_at': publishedAt?.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
        'discovered_at': discoveredAt.millisecondsSinceEpoch,
        'discovery_method': discoveryMethod,
        'language': language,
        'status': status.name,
        'attempts': attempts,
        'first_attempted_at': firstAttemptedAt?.millisecondsSinceEpoch,
        'last_error': lastError,
        'freshness': freshness.label,
        'source_priority': sourcePriority,
        'retry_after': retryAfter?.millisecondsSinceEpoch,
      };

  factory CrawlCandidate.fromMap(Map<String, dynamic> m) => CrawlCandidate(
        url: m['url'] as String,
        sourceId: m['source_id'] as String,
        sourceUrl: m['source_url'] as String?,
        titleHint: m['title_hint'] as String?,
        publishedAt: m['published_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['published_at'] as int)
            : null,
        updatedAt: m['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int)
            : null,
        discoveredAt: m['discovered_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['discovered_at'] as int)
            : DateTime.now(),
        discoveryMethod: m['discovery_method'] as String? ?? 'unknown',
        language: m['language'] as String?,
        status: CrawlStatus.values.firstWhere(
          (e) => e.name == m['status'],
          orElse: () => CrawlStatus.pending,
        ),
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        firstAttemptedAt: m['first_attempted_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['first_attempted_at'] as int)
            : null,
        lastError: m['last_error'] as String?,
        freshness: FreshnessClass.values.firstWhere(
          (e) => e.label == m['freshness'],
          orElse: () => FreshnessClass.unknownDate,
        ),
        sourcePriority: (m['source_priority'] as num?)?.toInt() ?? 0,
        retryAfter: m['retry_after'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['retry_after'] as int)
            : null,
      );
}

enum CrawlStatus {
  pending,
  fetching,
  extracted,
  failed,
  skipped,
  retrying,
}

/// Bounded priority queue of crawl candidates.
///
/// Prioritization order:
///   1. Freshness (veryFresh first, unknownDate last)
///   2. Source priority (higher = sooner)
///   3. Newly discovered (earlier discoveredAt first)
///   4. Retry-eligible failed candidates
class CandidateQueue {
  static const int _maxQueueSize = 5000;
  static const int _maxAttempts = 3;

  final List<CrawlCandidate> _items = <CrawlCandidate>[];
  final Set<String> _seenUrls = <String>{};
  final Set<String> _processing = <String>{};

  /// Number of pending candidates.
  int get length => _items.length;
  int get pendingCount => _items.where((c) => c.status == CrawlStatus.pending).length;
  int get failedCount => _items.where((c) => c.status == CrawlStatus.failed).length;
  int get processingCount => _processing.length;

  /// Add candidates, deduplicating by canonical URL. Returns count actually added.
  int addAll(Iterable<CrawlCandidate> candidates) {
    int added = 0;
    for (final c in candidates) {
      if (_maxQueueSize <= _items.length) break;
      final key = c.url.trim().toLowerCase();
      if (_seenUrls.contains(key)) continue;
      _seenUrls.add(key);
      _items.add(c);
      added++;
    }
    _rebuildOrder();
    return added;
  }

  /// Add a single candidate. Returns true if added (not a duplicate).
  bool add(CrawlCandidate candidate) {
    if (_maxQueueSize <= _items.length) return false;
    final key = candidate.url.trim().toLowerCase();
    if (_seenUrls.contains(key)) return false;
    _seenUrls.add(key);
    _items.add(candidate);
    _rebuildOrder();
    return true;
  }

  /// Pop the highest-priority pending candidate that is ready (not rate-limited).
  CrawlCandidate? pop() {
    _rebuildOrder();
    final now = DateTime.now();
    for (int i = 0; i < _items.length; i++) {
      final c = _items[i];
      if (c.status != CrawlStatus.pending) continue;
      if (c.retryAfter != null && now.isBefore(c.retryAfter!)) continue;
      if (c.attempts >= _maxAttempts) continue;
      if (_processing.contains(c.url)) continue;
      _processing.add(c.url);
      return c.copyWith(status: CrawlStatus.fetching, attempts: c.attempts + 1, firstAttemptedAt: c.firstAttemptedAt ?? now);
    }
    return null;
  }

  /// Mark a candidate as done and remove from processing set.
  void done(CrawlCandidate candidate, {CrawlStatus status = CrawlStatus.extracted}) {
    _processing.remove(candidate.url);
    final idx = _items.indexWhere((c) => c.url == candidate.url);
    if (idx >= 0) {
      _items[idx] = candidate.copyWith(status: status);
    }
  }

  /// Mark a candidate for retry with backoff.
  void retry(CrawlCandidate candidate, {String? error, Duration? backoff}) {
    _processing.remove(candidate.url);
    final idx = _items.indexWhere((c) => c.url == candidate.url);
    if (idx >= 0) {
      final retryAt = (backoff != null) ? DateTime.now().add(backoff) : null;
      _items[idx] = candidate.copyWith(
        status: CrawlStatus.retrying,
        lastError: error,
        retryAfter: retryAt,
      );
    }
  }

  /// Get all candidates for diagnostics/reporting.
  List<CrawlCandidate> get all => List<CrawlCandidate>.unmodifiable(_items);

  /// Get candidates by status.
  List<CrawlCandidate> byStatus(CrawlStatus status) =>
      _items.where((c) => c.status == status).toList();

  void _rebuildOrder() {
    _items.sort((a, b) {
      // 1. Freshness class
      final fa = a.freshness.sortOrder;
      final fb = b.freshness.sortOrder;
      if (fa != fb) return fa.compareTo(fb);
      // 2. Source priority (higher first)
      if (a.sourcePriority != b.sourcePriority) return b.sourcePriority.compareTo(a.sourcePriority);
      // 3. Newly discovered first
      return a.discoveredAt.compareTo(b.discoveredAt);
    });
  }
}
