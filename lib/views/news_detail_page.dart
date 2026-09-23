import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import 'package:flutter/foundation.dart';
import '../services/tts_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/comment_service.dart';
import '../services/user_service.dart';
import '../widgets/cached_news_image.dart';
import '../services/server_api_service.dart';
import '../services/knowledge_extraction_service.dart';

class NewsDetailPage extends StatefulWidget {
  final NewsModel article;

  const NewsDetailPage({Key? key, required this.article}) : super(key: key);

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  NewsModel get article => widget.article;
  bool _isSpeaking = false;
  bool _isEnriching = false;
  late ScrollController _scrollController;
  bool _showTitleInAppBar = false;
  String _enrichedContent = '';
  String _enrichedImageUrl = '';
  List<dynamic> _knowledgeEntities = [];
  List<dynamic> _knowledgeEvents = [];
  List<dynamic> _knowledgeTopics = [];
  List<dynamic> _knowledgeClaims = [];
  bool _isLoadingKnowledge = false;

  // ─── Like state ──────────────────────────────────────────────────────────────
  bool _isLiked = false;
  int _likeCount = 0;
  bool _likeLoading = false;
  bool _isLoggedIn = false;

  // ─── Comment refresh key ─────────────────────────────────────────────────────
  int _commentRefreshKey = 0;

  String get effectiveContent => _enrichedContent.isNotEmpty ? _enrichedContent : article.content;
  String get effectiveImageUrl => _enrichedImageUrl.isNotEmpty ? _enrichedImageUrl : article.imageUrl;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _enrichArticleIfNeeded();
    _loadKnowledge();
    _loadLikeState();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    TTSService.instance.stop();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels > 50) {
      if (!_showTitleInAppBar) {
        setState(() => _showTitleInAppBar = true);
      }
    } else {
      if (_showTitleInAppBar) {
        setState(() => _showTitleInAppBar = false);
      }
    }
  }

  Future<void> _loadKnowledge() async {
    setState(() => _isLoadingKnowledge = true);
    try {
      var entities = await KnowledgeExtractionService.instance.getEntitiesForArticle(article.url);
      var events = await KnowledgeExtractionService.instance.getEventsForArticle(article.url);
      var topics = await KnowledgeExtractionService.instance.getTopicsForArticle(article.url);
      var claims = await KnowledgeExtractionService.instance.getClaimsForArticle(article.url);

      if (entities.isEmpty && events.isEmpty && topics.isEmpty) {
        await KnowledgeExtractionService.instance.extractAndStore(
          article.url,
          article.title,
          effectiveContent,
          article.category,
        );
        entities = await KnowledgeExtractionService.instance.getEntitiesForArticle(article.url);
        events = await KnowledgeExtractionService.instance.getEventsForArticle(article.url);
        topics = await KnowledgeExtractionService.instance.getTopicsForArticle(article.url);
        claims = await KnowledgeExtractionService.instance.getClaimsForArticle(article.url);
      }

      if (mounted) {
        setState(() {
          _knowledgeEntities = _deduplicate(entities, (e) => e.value);
          _knowledgeEvents = _deduplicate(events, (e) => e.label);
          _knowledgeTopics = _deduplicate(topics, (t) => t.primaryTopic);
          _knowledgeClaims = _deduplicate(claims, (c) => c.claimText);
          _isLoadingKnowledge = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingKnowledge = false);
    }
  }

  static List<T> _deduplicate<T>(List<T> items, String Function(T) key) {
    final seen = <String>{};
    return items.where((item) {
      final normalized = key(item).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty || seen.contains(normalized)) return false;
      seen.add(normalized);
      return true;
    }).toList();
  }

  void _toggleTts() async {
    if (_isSpeaking) {
      await TTSService.instance.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
      final contentToRead = "${article.title}. ${article.shortTitle}. ${article.summary}. ${effectiveContent}";
      await TTSService.instance.speak(contentToRead);
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  String _getDisplayDate() {
    final datesIso = article.structuredData['dates_iso'] as List<dynamic>?;
    if (datesIso != null && datesIso.isNotEmpty) {
      return datesIso.first.toString();
    }
    final dates = article.structuredData['dates'] as List<dynamic>?;
    if (dates != null && dates.isNotEmpty) {
      return dates.first.toString();
    }
    if (article.publishDate.isNotEmpty) {
      return article.publishDate.split('T')[0];
    }
    return 'Recent';
  }

  /// Load like status and count from API.
  Future<void> _loadLikeState() async {
    try {
      final loggedIn = await ServerApiService.isLoggedIn();
      final count = await ServerApiService.getLikeCount(article.url);
      bool liked = false;
      if (loggedIn) {
        liked = await ServerApiService.checkLike(article.url);
      }
      if (mounted) {
        setState(() {
          _isLoggedIn = loggedIn;
          _isLiked = liked;
          _likeCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _enrichArticleIfNeeded() async {
    if (_isEnriching) return;
    if (article.content.length >= 500) return;

    setState(() => _isEnriching = true);
    try {
      final response = await http.get(Uri.parse(article.url)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return;

      final html = response.body;
      String? fetchedImage;
      final ogImageMatch = RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"[^>]*>', caseSensitive: false).firstMatch(html);
      if (ogImageMatch != null) {
        fetchedImage = ogImageMatch.group(1);
      }

      String cleaned = _extractArticleContent(html);
      cleaned = _decodeHtml(cleaned);
      cleaned = cleaned.trim();

      if (cleaned.length < 120) {
        final pTags = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
            .allMatches(html)
            .map((m) => m.group(1) ?? '')
            .toList();
        if (pTags.isNotEmpty) {
          cleaned = pTags.join('\n\n');
          cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
          cleaned = _decodeHtml(cleaned);
        }
      }

      if (cleaned.isEmpty) return;

      if (mounted) {
        setState(() {
          _enrichedContent = cleaned;
          if (fetchedImage != null && fetchedImage!.isNotEmpty) {
            _enrichedImageUrl = fetchedImage!;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isEnriching = false);
    }
  }

  String _extractArticleContent(String html) {
    String cleaned = html;
    cleaned = cleaned.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<nav\b[^>]*>.*?</nav>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<header\b[^>]*>.*?</header>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<footer\b[^>]*>.*?</footer>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<aside\b[^>]*>.*?</aside>', dotAll: true, caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<iframe\b[^>]*>.*?</iframe>', dotAll: true, caseSensitive: false), '');

    final articlePatterns = [
      RegExp(r'<article[^>]*>(.*?)</article>', dotAll: true, caseSensitive: false),
      RegExp('<div[^>]+class=["\'][^"\']*(?:article|content|post|entry|body)[^"\']*["\'][^>]*>(.*?)</div>', dotAll: true, caseSensitive: false),
      RegExp('<div[^>]+id=["\'][^"\']*(?:article|content|post|entry|body)[^"\']*["\'][^>]*>(.*?)</div>', dotAll: true, caseSensitive: false),
      RegExp(r'<main[^>]*>(.*?)</main>', dotAll: true, caseSensitive: false),
    ];

    String extracted = '';
    int bestLength = 0;
    for (final pattern in articlePatterns) {
      for (final match in pattern.allMatches(cleaned)) {
        final candidate = match.group(1) ?? '';
        if (candidate.length > bestLength) {
          bestLength = candidate.length;
          extracted = candidate;
        }
      }
    }

    String working = extracted;
    if (working.isEmpty) {
      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true, caseSensitive: false).firstMatch(cleaned);
      working = bodyMatch != null ? bodyMatch.group(1)! : cleaned;
    }

    final pTags = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
        .allMatches(working)
        .map((m) => (m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (pTags.isEmpty) {
      working = working.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      working = working.replaceAll(RegExp(r'</?(p|div|li|tr|td|h[1-6]|blockquote|pre|ul|ol|section|article)[^>]*>', caseSensitive: false), '\n');
      working = working.replaceAll(RegExp(r'<[^>]+>'), ' ');
      working = working.replaceAll(RegExp(r'[ \t]+\n'), '\n');
      working = working.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      working = working.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      return working;
    }

    final buffer = StringBuffer();
    for (final p in pTags) {
      final text = p.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
      if (text.isEmpty) continue;
      if (buffer.length > 0) buffer.writeln();
      buffer.writeln(text);
    }

    var result = buffer.toString().trim();
    if (result.isEmpty) {
      result = working.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      result = result.replaceAll(RegExp(r'</?(p|div|li|tr|td|h[1-6]|blockquote|pre|ul|ol|section|article)[^>]*>', caseSensitive: false), '\n');
      result = result.replaceAll(RegExp(r'<[^>]+>'), ' ');
      result = result.replaceAll(RegExp(r'[ \t]+\n'), '\n');
      result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      result = result.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    }

    result = result.replaceAll(RegExp(r'تابعنا على.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'اشترك في.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'حقوق النشر.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'جميع الحقوق.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'اضغط هنا.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'شارك المقال.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'للمزيد من الأخبار.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'تطبيق.*', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'www\..*?\.(com|ma|net|org)', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\p{P}\p{N}]', caseSensitive: false), ' ');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    result = result.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

    return result;
  }

  String _stripHtmlTags(String text) {
    if (text.isEmpty) return text;
    final withoutTags = text.replaceAll(RegExp(r'<[^>]*>'), '');
    return _decodeHtml(withoutTags);
  }

  String _decodeHtml(String text) {
    if (text.isEmpty) return text;
    try {
      final buffer = StringBuffer();
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '&') {
          final semi = text.indexOf(';', i);
          if (semi > i && semi - i < 10) {
            final entity = text.substring(i, semi + 1);
            if (entity.startsWith('&#x') || entity.startsWith('&#X')) {
              final hex = entity.substring(3, entity.length - 1);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) { buffer.writeCharCode(code); i = semi; continue; }
            } else if (entity.startsWith('&#')) {
              final num = entity.substring(2, entity.length - 1);
              final code = int.tryParse(num);
              if (code != null) { buffer.writeCharCode(code); i = semi; continue; }
            } else {
              final decoded = _namedEntity(entity);
              if (decoded != null) { buffer.write(decoded); i = semi; continue; }
            }
          }
        }
        buffer.write(text[i]);
      }
      return buffer.toString();
    } on Exception {
      return text;
    }
  }

  String? _namedEntity(String entity) {
    switch (entity) {
      case '&quot;': return '"';
      case '&apos;': return "'";
      case '&#34;': return '"';
      case '&#39;': return "'";
      case '&lt;': return '<';
      case '&gt;': return '>';
      case '&amp;': return '&';
      case '&nbsp;': return ' ';
      case '&thinsp;': return ' ';
      case '&ensp;': return ' ';
      case '&emsp;': return ' ';
      case '&mdash;': return '—';
      case '&ndash;': return '–';
      case '&hellip;': return '…';
      case '&bull;': return '•';
      case '&lsquo;': return '\u2018';
      case '&rsquo;': return '\u2019';
      case '&ldquo;': return '\u201C';
      case '&rdquo;': return '\u201D';
      case '&copy;': return '©';
      case '&reg;': return '®';
      case '&trade;': return '™';
      case '&euro;': return '€';
      case '&pound;': return '£';
      case '&yen;': return '¥';
      case '&deg;': return '°';
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sentimentScore = article.sentiment;
    final sentimentText = sentimentScore > 0.3
        ? l10n.translate('positive')
        : sentimentScore < -0.3
            ? l10n.translate('negative')
            : l10n.translate('neutral');

    final sentimentColor = sentimentScore > 0.3
        ? const Color(0xFF2E7D32)
        : sentimentScore < -0.3
            ? const Color(0xFFC62828)
            : const Color(0xFFEF6C00);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 22, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _showTitleInAppBar
              ? Text(
                  article.title,
                  key: const ValueKey<String>('title'),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : const Text(
                  '',
                  key: ValueKey<String>('empty'),
                ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleTts,
        backgroundColor: _isSpeaking ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface,
        child: Icon(_isSpeaking ? Icons.stop : Icons.volume_up, color: Theme.of(context).colorScheme.onPrimary),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    article.category.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  _getDisplayDate(),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              article.title,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.3,
              ),
            ),
            if (article.author.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15),
                    child: Text(
                      article.author.isNotEmpty ? article.author[0] : '?',
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.author,
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        Text(
                          'محرر رياضي',
                          style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (article.shortTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "الموجز: ${article.shortTitle}",
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
            if (article.summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          "ملخص تنفيذي من C++ TINY-LLM",
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      article.summary,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        height: 1.7,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // ── Main Article Hero Image ──────────────────────────────────
            if (article.imageUrl.isNotEmpty) ...[
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Hero(
                    tag: 'article_image_${article.url}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          CachedNewsImage(
                            imageUrl: article.imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                                    const Color(0xFF1A1A2E),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Icon(Icons.image_not_supported_rounded,
                                    size: 48, color: Colors.white38),
                              ),
                            ),
                          ),
                          // Subtle gradient at bottom for readability
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "مؤشرات محرك C++ العميق",
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Icon(Icons.analytics_outlined, size: 18, color: Colors.grey),
                    ],
                  ),
                  const Divider(height: 20),
                   Row(
                     children: [
                       Container(
                         width: 14,
                         height: 14,
                         decoration: BoxDecoration(
                           color: sentimentColor,
                           shape: BoxShape.circle,
                         ),
                       ),
                       const SizedBox(width: 10),
                       Text(
                         l10n.translate('sentimentIndicator'),
                         style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                       ),
                      const Spacer(),
                      Text(
                        "${sentimentScore.toStringAsFixed(2)} ($sentimentText)",
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: sentimentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      width: double.infinity,
                      child: LinearProgressIndicator(
                        value: (sentimentScore + 1) / 2,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        color: sentimentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                    if ((article.entities ?? []).isNotEmpty) ...[
                      Text(
                         l10n.translate('definedEntities'),
                         style: GoogleFonts.outfit(fontSize:13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                       ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (article.entities ?? []).map((entity) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Text(
                              entity,
                              style: GoogleFonts.robotoMono(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if ((article.structuredData['persons'] as List<dynamic>?)?.isNotEmpty ?? false) ...[
                      Text(
                        l10n.translate('keyPersons'),
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (article.structuredData['persons'] as List<dynamic>).map((p) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.primary),
                            ),
                            child: Text(
                              p.toString(),
                              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if ((article.structuredData['dates'] as List<dynamic>?)?.isNotEmpty ?? false) ...[
                      Text(
                        l10n.translate('keyDates'),
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.secondary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (article.structuredData['dates'] as List<dynamic>).map((d) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.secondary),
                            ),
                            child: Text(
                              d.toString(),
                              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSecondaryContainer),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if ((article.structuredData['events'] as List<dynamic>?)?.isNotEmpty ?? false) ...[
                      Text(
                        l10n.translate('keyEvents'),
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.tertiary),
                      ),
                      const SizedBox(height: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: (article.structuredData['events'] as List<dynamic>).map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.toString(),
                                    style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Text(
                       l10n.translate('extractedKeywords'),
                       style: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                     ),
                   const SizedBox(height: 10),
                   Wrap(
                     spacing: 8,
                     runSpacing: 8,
                     children: article.keywords.map((kw) {
                       return Container(
                         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                         decoration: BoxDecoration(
                           color: Theme.of(context).colorScheme.surfaceContainer,
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                         ),
                         child: Text(
                           "#$kw",
                           style: GoogleFonts.robotoMono(
                             fontSize: 12,
                             fontWeight: FontWeight.bold,
                             color: Theme.of(context).colorScheme.onSurfaceVariant,
                           ),
                         ),
                       );
                     }).toList(),
                   ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (article.category.toLowerCase() == 'sports')
              _buildSportsDashboard(context),
            // ── Blended article banner ──────────────────────────────────────
            if (article.isBlended) ...[
              _buildBlendedBanner(context),
              const SizedBox(height: 20),
            ],
             Text(
              l10n.translate('fullArticle'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 14),
             ..._buildRichContent(context, effectiveContent),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      article.url,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildBlendedSourcesSection(context),
            const SizedBox(height: 30),
            _buildPipelineInspector(context),
            const SizedBox(height: 30),
            _buildActionButtons(context),
            const SizedBox(height: 30),
            _buildCommentsSection(context),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // ── Like button with count ────────────────────────────────────────
          InkWell(
            onTap: _isLoggedIn ? _toggleLike : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _likeLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 20,
                          color: _isLiked
                              ? const Color(0xFFC62828)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    _likeCount > 0 ? '$_likeCount' : l10n.translate('liked'),
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isLiked
                          ? const Color(0xFFC62828)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildActionChip(
            Icons.bookmark_border_rounded,
            l10n.translate('save'),
            null,
            _isLoggedIn ? () => _toggleSave() : null,
          ),
          _buildActionChip(
            Icons.comment_outlined,
            l10n.translate('comments'),
            null,
            () => _showCommentDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label, Color? color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: (onTap == null ? Colors.grey : null) ?? color ?? Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: onTap == null ? Colors.grey : Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingKnowledge)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_knowledgeEntities.isNotEmpty || _knowledgeEvents.isNotEmpty || _knowledgeTopics.isNotEmpty || _knowledgeClaims.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Knowledge', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 12),
              if (_knowledgeEntities.isNotEmpty) ...[
                Text('Entities', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _knowledgeEntities.map((e) {
                    return Chip(
                      label: Text(e.value, style: GoogleFonts.outfit(fontSize: 12)),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
              if (_knowledgeEvents.isNotEmpty) ...[
                Text('Events', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                ..._knowledgeEvents.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(e.label, style: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                )),
                const SizedBox(height: 16),
              ],
              if (_knowledgeTopics.isNotEmpty) ...[
                Text('Topics', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _knowledgeTopics.map((t) {
                    return Chip(
                      label: Text(t.primaryTopic, style: GoogleFonts.outfit(fontSize: 12)),
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.2),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
              if (_knowledgeClaims.isNotEmpty) ...[
                Text('Claims', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                ..._knowledgeClaims.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('"${c.claimText}"', style: GoogleFonts.outfit(fontSize: 13, fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                )),
                const SizedBox(height: 16),
              ],
            ],
          ),
        // ── Comments (readable by everyone) ──────────────────────────────────
        Text(l10n.translate('comments'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        FutureBuilder<List<Comment>>(
          key: ValueKey(_commentRefreshKey),
          future: CommentService.getComments(article.url),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
            }
            final comments = snapshot.data ?? [];
            if (comments.isEmpty) {
              return Text(l10n.translate('noComments'), style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.onSurfaceVariant));
            }
            return Column(
              children: comments.map((comment) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 16, backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15), child: Text(comment.userName.isNotEmpty ? comment.userName[0] : '?', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(comment.userName, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                            const SizedBox(height: 4),
                            Text(comment.text, style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        // ── Add comment button — login required ───────────────────────────────
        if (!_isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.translate('loginToComment'),
              style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _showCommentDialog(context);
                if (mounted) setState(() => _commentRefreshKey++);
              },
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: Text(l10n.translate('writeComment'), style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Future<void> _showCommentDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final commentController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('writeComment')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(hintText: l10n.translate('email')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              maxLines: 4,
              decoration: InputDecoration(hintText: l10n.translate('writeComment')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.translate('cancel'))),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final text = commentController.text.trim();
              if (text.isEmpty || name.isEmpty) return;
              await CommentService.addComment(Comment(
                id: '',
                articleId: article.url,
                userId: name,
                userName: name,
                text: text,
                createdAt: DateTime.now(),
              ));
              if (mounted) Navigator.pop(context);
            },
            child: Text(l10n.translate('send')),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (!_isLoggedIn || _likeLoading) return;
    setState(() => _likeLoading = true);
    try {
      if (_isLiked) {
        await ServerApiService.unlikeArticle(article.url);
        setState(() {
          _isLiked = false;
          _likeCount = (_likeCount - 1).clamp(0, 99999);
        });
      } else {
        await ServerApiService.likeArticle(article.url);
        setState(() {
          _isLiked = true;
          _likeCount = _likeCount + 1;
        });
      }
    } catch (_) {
      // Revert optimistic update on error
      await _loadLikeState();
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  Future<void> _toggleSave() async {
    final isLoggedIn = await ServerApiService.isLoggedIn();
    if (!isLoggedIn) return;
    await UserService.saveArticle(article.url);
  }

  List<Widget> _buildRichContent(BuildContext context, String text) {
    debugPrint('Building rich content, length: ${text.length}');
    final List<String> persons = List<String>.from(article.structuredData['persons'] as List<dynamic>? ?? []);
    final List<String> dates = List<String>.from(article.structuredData['dates'] as List<dynamic>? ?? []);
    final List<String> events = List<String>.from(article.structuredData['events'] as List<dynamic>? ?? []);
    final List<Widget> widgets = [];

    final imgRegex = RegExp(r'<img\s+src="([^"]+)"[^>]*>', caseSensitive: false);
    int lastMatchEnd = 0;

    for (final match in imgRegex.allMatches(text)) {
        final String precedingText = text.substring(lastMatchEnd, match.start).trim();
        if (precedingText.isNotEmpty) {
            final String cleanPreceding = _stripHtmlTags(precedingText);
            debugPrint('Preceding text length: ${cleanPreceding.length}');
            final paragraphs = _splitIntoParagraphs(cleanPreceding);
            debugPrint('Paragraphs count: ${paragraphs.length}');
            for (final p in paragraphs) {
                widgets.add(_buildParagraphWithEntities(p, persons, dates, events));
                widgets.add(const SizedBox(height: 20));
            }
        }

        final String imgUrl = match.group(1)!;
        debugPrint('Adding image: $imgUrl');
        widgets.add(_buildImageWidget(context, imgUrl));
        widgets.add(const SizedBox(height: 20));

        lastMatchEnd = match.end;
    }

    final String remainingText = text.substring(lastMatchEnd).trim();
    if (remainingText.isNotEmpty) {
        final String cleanRemaining = _stripHtmlTags(remainingText);
        debugPrint('Remaining text length: ${cleanRemaining.length}');
        final paragraphs = _splitIntoParagraphs(cleanRemaining);
        debugPrint('Remaining paragraphs count: ${paragraphs.length}');
        for (final p in paragraphs) {
            widgets.add(_buildParagraphWithEntities(p, persons, dates, events));
            widgets.add(const SizedBox(height: 20));
        }
    }

    if (widgets.isEmpty) {
      debugPrint('No widgets generated, adding fallback text');
      widgets.add(Text(
        text.isEmpty ? 'No content available' : text,
        style: GoogleFonts.outfit(fontSize: 16, color: Theme.of(context).colorScheme.onSurface, height: 1.7),
      ));
    }

    if (widgets.isNotEmpty && widgets.last is SizedBox) {
        widgets.removeLast();
    }

    debugPrint('Total widgets generated: ${widgets.length}');
    return widgets;
  }

  List<String> _splitIntoParagraphs(String text) {
    if (text.isEmpty) return [];
    
    final segments = _splitContentIntoSegments(text);
    if (segments.length >= 2) {
      return segments;
    }
    
    final sentences = text.split(RegExp(r'(?<=[.!?؟!])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.length >= 2)
      .toList();
    
    if (sentences.isEmpty) {
      return [text.trim()];
    }
    
    final result = <String>[];
    final buffer = StringBuffer();
    final sentencesPerParagraph = 3;
    
    for (int i = 0; i < sentences.length; i++) {
      buffer.write(sentences[i]);
      if ((i + 1) % sentencesPerParagraph == 0 || i == sentences.length - 1) {
        final paragraph = buffer.toString().trim();
        if (paragraph.isNotEmpty) {
          result.add(paragraph);
        }
        buffer.clear();
      } else {
        buffer.write(' ');
      }
    }
    
    return result.isEmpty ? [text.trim()] : result;
  }

  List<String> _splitContentIntoSegments(String text) {
    if (text.isEmpty) return const [];
    
    final segments = text
        .split(RegExp(r'(?<=[.!?؟!])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 5)
        .toList();
    
    if (segments.length >= 2) {
      return segments;
    }
    
    final paragraphs = text
        .split(RegExp(r'\n\s*\n|\n{2,}'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 3)
        .toList();
    
    if (paragraphs.length >= 2) {
      return paragraphs;
    }
    
    return [text.trim()];
  }

  Widget _buildImageWidget(BuildContext context, String imgUrl) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenImageScreen(imageUrl: imgUrl),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNewsImage(
          imageUrl: imgUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: _buildImagePlaceholder(article.category, size: 200),
          errorWidget: _buildImagePlaceholder(article.category, size: 200),
        ),
      ),
    );
  }

  Widget _buildParagraphWithEntities(String text, List<String> persons, List<String> dates, List<String> events) {
    final allEntities = <String>[];
    final entityColors = <Color>[];
    final entityTypes = <String>[];
    
    for (final p in persons) {
      allEntities.add(p);
      entityColors.add(Theme.of(context).colorScheme.primary);
      entityTypes.add('person');
    }
    for (final d in dates) {
      allEntities.add(d);
      entityColors.add(Theme.of(context).colorScheme.secondary);
      entityTypes.add('date');
    }
    for (final e in events) {
      allEntities.add(e);
      entityColors.add(Theme.of(context).colorScheme.tertiary);
      entityTypes.add('event');
    }
    
    if (allEntities.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.7,
        ),
        textAlign: TextAlign.justify,
      );
    }

    String pattern = allEntities.map((e) => RegExp.escape(e)).join('|');
    if (pattern.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.7,
        ),
        textAlign: TextAlign.justify,
      );
    }

    final regex = RegExp('($pattern)');
    final matches = regex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.7,
        ),
        textAlign: TextAlign.justify,
      );
    }

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (var match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }
      
      final matchedText = match.group(0)!;
      final entityIndex = allEntities.indexOf(matchedText);
      final entityColor = entityIndex >= 0 ? entityColors[entityIndex] : Theme.of(context).colorScheme.primary;
      final entityType = entityIndex >= 0 ? entityTypes[entityIndex] : 'unknown';
      
      spans.add(TextSpan(
        text: matchedText,
        style: TextStyle(
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.bold,
          color: entityColor,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            _onEntityTap(matchedText, entityType);
          },
      ));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.outfit(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.7,
        ),
        children: spans,
      ),
    );
  }
  
  void _onEntityTap(String entity, String type) {
    debugPrint('Entity tapped: $entity (type: $type)');
    Navigator.pop(context, {'search': entity});
  }

  Widget _buildImagePlaceholder(String category, {double size = 76}) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _getCategoryGradient(category),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _getCategoryIcon(category),
          size: size * 0.4,
          color: Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }

  List<Color> _getCategoryGradient(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return [Colors.green, Colors.lightGreen];
      case 'technology':
        return [Colors.blue, Colors.lightBlue];
      case 'politics':
        return [Colors.red, Colors.redAccent];
      case 'entertainment':
        return [Colors.purple, Colors.purpleAccent];
      case 'business':
        return [Colors.orange, Colors.orangeAccent];
      case 'health':
        return [Colors.teal, Colors.tealAccent];
      case 'science':
        return [Colors.indigo, Colors.indigoAccent];
      case 'general':
      default:
        return [Colors.grey, Colors.grey.shade400];
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return Icons.sports_soccer;
      case 'technology':
        return Icons.computer;
      case 'politics':
        return Icons.account_balance;
      case 'entertainment':
        return Icons.movie;
      case 'business':
        return Icons.business;
      case 'health':
        return Icons.health_and_safety;
      case 'science':
        return Icons.science;
      case 'general':
      default:
        return Icons.article;
    }
  }

  Widget _buildBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildSportsDashboard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sportsData = article.structuredData['sports_data'] as Map<String, dynamic>?;
    final matchScores = article.structuredData['match_scores'] as List<dynamic>?;

    if ((sportsData == null || sportsData.isEmpty) && (matchScores == null || matchScores.isEmpty)) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sports_soccer, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                   Text(
                     l10n.translate('sportsIntelligence'),
                     style: GoogleFonts.outfit(
                       fontSize: 13,
                       fontWeight: FontWeight.w800,
                       color: Colors.white,
                       letterSpacing: 0.5,
                     ),
                   ),
                ],
              ),
              const Divider(color: Colors.white30, height: 28),
              if (matchScores != null && matchScores.isNotEmpty) ...[
                 Text(
                  l10n.translate('matchResult'),
                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                Text(
                  matchScores.first.toString(),
                  style: GoogleFonts.outfit(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              if (sportsData != null) ...[
                if (sportsData['goals'] != null && (sportsData['goals'] as List).isNotEmpty)
                  _buildSportsItem("Goals / Scorers", (sportsData['goals'] as List).join(', ')),
                if (sportsData['players'] != null && (sportsData['players'] as List).isNotEmpty)
                  _buildSportsItem("Key Players", (sportsData['players'] as List).join(', ')),
                if (sportsData['cards'] != null && (sportsData['cards'] as List).isNotEmpty)
                  _buildSportsItem("Cards", (sportsData['cards'] as List).join(', ')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSportsItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }



  // ── Blended article: hero banner with highlights ──────────────────────────
  Widget _buildBlendedBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlights = article.highlights;
    final attrs = article.sourceAttributions;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6A11CB).withOpacity(0.12),
            const Color(0xFF2575FC).withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6A11CB).withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.translate('blendedBadge'),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${attrs.length} ${l10n.translate("sources")}',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Highlights ──────────────────────────────────────────────────
          if (highlights.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                l10n.translate('keyHighlights'),
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF6A11CB),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...highlights.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6A11CB),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
          const Divider(indent: 16, endIndent: 16, height: 1),
          // ── Source pills row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attrs.map((attr) {
                final name = (attr['name'] as String?) ?? (attr['domain'] as String?) ?? '';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A11CB).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF6A11CB).withOpacity(0.30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public, size: 12, color: Color(0xFF6A11CB)),
                      const SizedBox(width: 5),
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6A11CB),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Blended: full source attribution list ──────────────────────────────────
  Widget _buildBlendedSourcesSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final attrs = article.sourceAttributions;
    // For non-blended articles show a simple source link row
    if (!article.isBlended) {
      if (article.url.isEmpty) return const SizedBox();
      return _buildSingleSourceRow(context);
    }
    if (attrs.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('sources'),
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...attrs.asMap().entries.map((entry) {
          final i = entry.key;
          final attr = entry.value;
          final name = (attr['name'] as String?) ?? (attr['domain'] as String?) ?? 'Source';
          final sourceUrl = (attr['url'] as String?) ?? '';
          final sourceTitle = (attr['title'] as String?) ?? '';
          final date = (attr['publishDate'] as String?) ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Index badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (sourceTitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sourceTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              date.split('T').first,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (sourceUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _openSourceUrl(context, sourceUrl),
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new, size: 13, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  sourceUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSingleSourceRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _openSourceUrl(context, article.url),
              child: Text(
                article.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSourceUrl(BuildContext context, String url) {
    if (url.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              Uri.tryParse(url)?.host ?? url,
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            elevation: 0,
          ),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse(url)),
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineInspector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        iconColor: Colors.white,
        collapsedIconColor: Colors.grey,
        title: Row(
          children: [
            const Icon(Icons.history_edu, color: Color(0xFF81C784), size: 20),
            const SizedBox(width: 10),
             Text(
              l10n.translate('cppExecutionLog'),
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF151515),
            child: article.logs.isEmpty
              ? Text(
                  l10n.translate('executionLogNotAvailable'),
                  style: GoogleFonts.robotoMono(color: Colors.grey, fontSize: 12),
                )
                : Text(
                    article.logs,
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      color: Colors.white60,
                      height: 1.5,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class FullScreenImageScreen extends StatelessWidget {
  final String imageUrl;

  const FullScreenImageScreen({Key? key, required this.imageUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNewsImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            errorWidget: Icon(
              Icons.broken_image,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 50,
            ),
          ),
        ),
      ),
    );
  }
}
