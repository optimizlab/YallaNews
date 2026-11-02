import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import '../models/news_model.dart';

const bool _isWeb = bool.fromEnvironment('dart.library.js_util');

/// Fetches raw HTML from a URL using the Dart http package.
/// Used on platforms where C++ cannot access the network directly (Android, iOS, Linux, macOS).
Future<String?> _fetchHtmlDart(String url) async {
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36 NewsBrain/1.0',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ar,en-US,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Returns true if we should fetch HTML in Dart (non-Windows platforms)
bool get _useDartHttp => !Platform.isWindows;

/// Representation of a single PageNode within the compact PageSkeleton
class PageNode {
  final int id;
  final String type;
  final int depth;
  final int parent;
  final String tag;
  final String role;
  final String className;
  final String idAttr;
  final String text;
  final int textLength;
  final int linkCount;
  final int imageCount;
  final double linkDensity;
  final double textDensity;
  final double contentScore;
  final bool isGarbage;
  final List<int> children;

  const PageNode({
    required this.id,
    required this.type,
    required this.depth,
    required this.parent,
    required this.tag,
    required this.role,
    required this.className,
    required this.idAttr,
    required this.text,
    required this.textLength,
    required this.linkCount,
    required this.imageCount,
    required this.linkDensity,
    required this.textDensity,
    required this.contentScore,
    required this.isGarbage,
    required this.children,
  });

  factory PageNode.fromJson(Map<String, dynamic> json) {
    return PageNode(
      id: json['id'] as int? ?? -1,
      type: json['type'] as String? ?? 'UNKNOWN',
      depth: json['depth'] as int? ?? 0,
      parent: json['parent'] as int? ?? -1,
      tag: json['tag'] as String? ?? '',
      role: json['role'] as String? ?? '',
      className: json['className'] as String? ?? '',
      idAttr: json['idAttr'] as String? ?? '',
      text: json['text'] as String? ?? '',
      textLength: json['textLength'] as int? ?? 0,
      linkCount: json['linkCount'] as int? ?? 0,
      imageCount: json['imageCount'] as int? ?? 0,
      linkDensity: (json['linkDensity'] as num?)?.toDouble() ?? 0.0,
      textDensity: (json['textDensity'] as num?)?.toDouble() ?? 0.0,
      contentScore: (json['contentScore'] as num?)?.toDouble() ?? 0.0,
      isGarbage: json['isGarbage'] as bool? ?? false,
      children: (json['children'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'depth': depth,
    'parent': parent,
    'tag': tag,
    'role': role,
    'className': className,
    'idAttr': idAttr,
    'text': text,
    'textLength': textLength,
    'linkCount': linkCount,
    'imageCount': imageCount,
    'linkDensity': linkDensity,
    'textDensity': textDensity,
    'contentScore': contentScore,
    'isGarbage': isGarbage,
    'children': children,
  };
}

/// Metadata extracted from HTML (Title, OpenGraph, JSON-LD, etc.)
class PageMetadata {
  final String title;
  final String description;
  final String canonicalUrl;
  final String author;
  final String publishDate;
  final String language;
  final String siteName;
  final String ogTitle;
  final String ogDescription;
  final String ogImage;
  final String ogType;
  final String schemaType;
  final String jsonLd;
  final Map<String, dynamic> openGraph;

  const PageMetadata({
    this.title = '',
    this.description = '',
    this.canonicalUrl = '',
    this.author = '',
    this.publishDate = '',
    this.language = '',
    this.siteName = '',
    this.ogTitle = '',
    this.ogDescription = '',
    this.ogImage = '',
    this.ogType = '',
    this.schemaType = '',
    this.jsonLd = '',
    this.openGraph = const {},
  });

  factory PageMetadata.fromJson(Map<String, dynamic> json) {
    return PageMetadata(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      canonicalUrl: json['canonicalUrl'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publishDate: json['publishDate'] as String? ?? '',
      language: json['language'] as String? ?? '',
      siteName: json['siteName'] as String? ?? '',
      ogTitle: json['ogTitle'] as String? ?? '',
      ogDescription: json['ogDescription'] as String? ?? '',
      ogImage: json['ogImage'] as String? ?? '',
      ogType: json['ogType'] as String? ?? '',
      schemaType: json['schemaType'] as String? ?? '',
      jsonLd: json['jsonLd'] as String? ?? '',
      openGraph: json['openGraph'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'canonicalUrl': canonicalUrl,
    'author': author,
    'publishDate': publishDate,
    'language': language,
    'siteName': siteName,
    'ogTitle': ogTitle,
    'ogDescription': ogDescription,
    'ogImage': ogImage,
    'ogType': ogType,
    'schemaType': schemaType,
    'jsonLd': jsonLd,
    'openGraph': openGraph,
  };
}

/// Image detected inside webpage
class ImageCandidate {
  final String src;
  final String alt;
  final String caption;
  final int width;
  final int height;
  final int nodeId;
  final double relevanceScore;
  final bool isLead;

  const ImageCandidate({
    required this.src,
    this.alt = '',
    this.caption = '',
    this.width = 0,
    this.height = 0,
    this.nodeId = -1,
    this.relevanceScore = 0.0,
    this.isLead = false,
  });

  factory ImageCandidate.fromJson(Map<String, dynamic> json) {
    return ImageCandidate(
      src: json['src'] as String? ?? '',
      alt: json['alt'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      nodeId: json['nodeId'] as int? ?? -1,
      relevanceScore: (json['relevanceScore'] as num?)?.toDouble() ?? 0.0,
      isLead: json['isLead'] as bool? ?? false,
    );
  }
}

/// An identified candidate region that looks like a news article
class ArticleCandidate {
  final int candidateId;
  final int rootNodeId;
  final double score;
  final int nodeCount;
  final int textLength;
  final int paragraphCount;
  final int imageCount;
  final int linkCount;
  final double linkDensity;
  final String previewText;
  final List<int> memberNodeIds;

  const ArticleCandidate({
    required this.candidateId,
    required this.rootNodeId,
    required this.score,
    required this.nodeCount,
    required this.textLength,
    required this.paragraphCount,
    required this.imageCount,
    required this.linkCount,
    required this.linkDensity,
    required this.previewText,
    required this.memberNodeIds,
  });

  factory ArticleCandidate.fromJson(Map<String, dynamic> json) {
    return ArticleCandidate(
      candidateId: json['candidateId'] as int? ?? 0,
      rootNodeId: json['rootNodeId'] as int? ?? -1,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      nodeCount: json['nodeCount'] as int? ?? 0,
      textLength: json['textLength'] as int? ?? 0,
      paragraphCount: json['paragraphCount'] as int? ?? 0,
      imageCount: json['imageCount'] as int? ?? 0,
      linkCount: json['linkCount'] as int? ?? 0,
      linkDensity: (json['linkDensity'] as num?)?.toDouble() ?? 0.0,
      previewText: json['previewText'] as String? ?? '',
      memberNodeIds: (json['memberNodeIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    );
  }
}

/// Milestone 1: PageSkeleton output structure
class PageSkeleton {
  final String url;
  final String canonicalUrl;
  final PageMetadata metadata;
  final List<PageNode> nodes;
  final List<ImageCandidate> images;
  final List<ArticleCandidate> candidates;

  const PageSkeleton({
    required this.url,
    required this.canonicalUrl,
    required this.metadata,
    required this.nodes,
    required this.images,
    required this.candidates,
  });

  factory PageSkeleton.fromJson(Map<String, dynamic> json) {
    return PageSkeleton(
      url: json['url'] as String? ?? '',
      canonicalUrl: json['canonicalUrl'] as String? ?? '',
      metadata: PageMetadata.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
      nodes: (json['nodes'] as List<dynamic>?)?.map((e) => PageNode.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      images: (json['images'] as List<dynamic>?)?.map((e) => ImageCandidate.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      candidates: (json['candidates'] as List<dynamic>?)?.map((e) => ArticleCandidate.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'canonicalUrl': canonicalUrl,
    'metadata': metadata.toJson(),
    'nodes': nodes.map((e) => e.toJson()).toList(),
    'images': images.map((e) => {
      'src': e.src, 'alt': e.alt, 'caption': e.caption,
      'width': e.width, 'height': e.height, 'nodeId': e.nodeId,
      'relevanceScore': e.relevanceScore, 'isLead': e.isLead,
    }).toList(),
    'candidates': candidates.map((e) => {
      'candidateId': e.candidateId, 'rootNodeId': e.rootNodeId,
      'score': e.score, 'nodeCount': e.nodeCount, 'textLength': e.textLength,
      'paragraphCount': e.paragraphCount, 'imageCount': e.imageCount,
      'linkCount': e.linkCount, 'linkDensity': e.linkDensity,
      'previewText': e.previewText, 'memberNodeIds': e.memberNodeIds,
    }).toList(),
  };
}

/// Content block in reconstructed NewsArticle
class ArticleBlock {
  final String type; // PARAGRAPH, HEADING, SUBTITLE, IMAGE, QUOTE, LIST
  final String text;
  final int headingLevel;
  final String? imageUrl;
  final String? caption;
  final String? alt;
  final List<String> listItems;

  const ArticleBlock({
    required this.type,
    this.text = '',
    this.headingLevel = 2,
    this.imageUrl,
    this.caption,
    this.alt,
    this.listItems = const [],
  });

  factory ArticleBlock.fromJson(Map<String, dynamic> json) {
    return ArticleBlock(
      type: json['type'] as String? ?? 'PARAGRAPH',
      text: json['text'] as String? ?? '',
      headingLevel: json['headingLevel'] as int? ?? 2,
      imageUrl: json['imageUrl'] as String?,
      caption: json['caption'] as String?,
      alt: json['alt'] as String?,
      listItems: (json['listItems'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

/// Reconstructed Human-Reading NewsArticle
class NewsArticle {
  final String url;
  final String canonicalUrl;
  final String title;
  final String subtitle;
  final String author;
  final String publishDate;
  final String language;
  final String siteName;
  final String leadImageUrl;
  final String leadImageCaption;
  final List<ArticleBlock> blocks;
  final String plainText;
  final int wordCount;
  final int readingTimeMinutes;
  final double confidenceScore;

  const NewsArticle({
    required this.url,
    required this.canonicalUrl,
    required this.title,
    required this.subtitle,
    required this.author,
    required this.publishDate,
    required this.language,
    required this.siteName,
    required this.leadImageUrl,
    required this.leadImageCaption,
    required this.blocks,
    required this.plainText,
    required this.wordCount,
    required this.readingTimeMinutes,
    required this.confidenceScore,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      url: json['url'] as String? ?? '',
      canonicalUrl: json['canonicalUrl'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publishDate: json['publishDate'] as String? ?? '',
      language: json['language'] as String? ?? '',
      siteName: json['siteName'] as String? ?? '',
      leadImageUrl: json['leadImageUrl'] as String? ?? '',
      leadImageCaption: json['leadImageCaption'] as String? ?? '',
      blocks: (json['blocks'] as List<dynamic>?)?.map((e) => ArticleBlock.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      plainText: json['plainText'] as String? ?? '',
      wordCount: json['wordCount'] as int? ?? 0,
      readingTimeMinutes: json['readingTimeMinutes'] as int? ?? 1,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Converts this NewsArticle directly to the app's NewsModel
NewsModel toNewsModel({String? category}) {
    final effectiveContent = plainText.isNotEmpty ? plainText : (subtitle.isNotEmpty ? subtitle : '');
    final effectiveSummary = subtitle.isNotEmpty ? subtitle : (plainText.isNotEmpty && plainText.length <= 200 ? plainText : (plainText.length > 200 ? plainText.substring(0, 200) : ''));
    final sourceDomain = siteName.isNotEmpty ? siteName : (Uri.tryParse(url)?.host ?? '');
    final sourceAttribution = <Map<String, dynamic>>[
      {
        'name': author.isNotEmpty ? author : siteName,
        'domain': sourceDomain,
        'url': url,
        'title': title,
        'publishDate': publishDate,
      }
    ];
    return NewsModel(
      url: url.isNotEmpty ? url : canonicalUrl,
      title: title,
      summary: effectiveSummary,
      content: effectiveContent,
      imageUrl: leadImageUrl,
      category: category ?? 'General',
      sentiment: 0.0,
      keywords: const [],
      logs: '[newsBrain] Rebuilt from PageSkeleton',
      author: author,
      publishDate: publishDate.isNotEmpty ? publishDate : DateTime.now().toIso8601String(),
      sourceCount: 1,
      sources: siteName.isNotEmpty ? [siteName] : (Uri.tryParse(url)?.host != null ? [Uri.parse(url).host] : const []),
      structuredData: {'source_attributions': sourceAttribution},
      isFresh: NewsModel.computeFreshness(publishDate.isNotEmpty ? publishDate : DateTime.now().toIso8601String()),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// C API Typedefs
// ─────────────────────────────────────────────────────────────

typedef _GetVersionC = Pointer<Utf8> Function();
typedef _GetVersionDart = Pointer<Utf8> Function();

typedef _FreeStringC = Void Function(Pointer<Utf8> str);
typedef _FreeStringDart = void Function(Pointer<Utf8> str);

typedef _ScanUrlC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef _ScanUrlDart = Pointer<Utf8> Function(Pointer<Utf8> url);

typedef _ScanHtmlC = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);
typedef _ScanHtmlDart = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);

typedef _ExtractArticleUrlC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef _ExtractArticleUrlDart = Pointer<Utf8> Function(Pointer<Utf8> url);

typedef _ExtractArticleHtmlC = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);
typedef _ExtractArticleHtmlDart = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);

typedef _ClassifyArticleC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);
typedef _ClassifyArticleDart = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);

typedef _ClassifyCategoryC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);
typedef _ClassifyCategoryDart = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);

typedef _AnalyzeSentimentC = Double Function(Pointer<Utf8> text);
typedef _AnalyzeSentimentDart = double Function(Pointer<Utf8> text);

/// Dart FFI Service to communicate with newsBrain C++ DLL
class NewsBrainService {
  NewsBrainService._internal();
  static final NewsBrainService instance = NewsBrainService._internal();

  DynamicLibrary? _lib;
  bool _initialized = false;

  _GetVersionDart? _getVersion;
  _FreeStringDart? _freeString;
  _ScanUrlDart? _scanUrl;
  _ScanHtmlDart? _scanHtml;
  _ExtractArticleUrlDart? _extractArticleUrl;
  _ExtractArticleHtmlDart? _extractArticleHtml;
  _ClassifyArticleDart? _classifyArticle;
  _ClassifyCategoryDart? _classifyCategory;
  _AnalyzeSentimentDart? _analyzeSentiment;

  bool get isAvailable {
    _ensureInitialized();
    return _lib != null;
  }

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    if (_isWeb) return;

    try {
      if (Platform.isWindows) {
        // Try multiple paths: local directory, runner folder, build outputs
        final possiblePaths = [
          'newsBrain.dll',
          'windows/runner/newsBrain.dll',
          'build/windows/x64/runner/Debug/newsBrain.dll',
          'build/windows/x64/runner/Release/newsBrain.dll',
        ];

        for (final p in possiblePaths) {
          try {
            _lib = DynamicLibrary.open(p);
            break;
          } catch (_) {}
        }
      } else if (Platform.isAndroid || Platform.isLinux) {
        _lib = DynamicLibrary.open('libnewsBrain.so');
      } else if (Platform.isMacOS) {
        _lib = DynamicLibrary.open('libnewsBrain.dylib');
      } else if (Platform.isIOS) {
        _lib = DynamicLibrary.process();
      }

      if (_lib != null) {
        _getVersion = _lib!.lookupFunction<_GetVersionC, _GetVersionDart>('newsbrain_get_version');
        _freeString = _lib!.lookupFunction<_FreeStringC, _FreeStringDart>('newsbrain_free_string');
        _scanUrl = _lib!.lookupFunction<_ScanUrlC, _ScanUrlDart>('newsbrain_scan_url');
        _scanHtml = _lib!.lookupFunction<_ScanHtmlC, _ScanHtmlDart>('newsbrain_scan_html');
        _extractArticleUrl = _lib!.lookupFunction<_ExtractArticleUrlC, _ExtractArticleUrlDart>('newsbrain_extract_article_url');
        _extractArticleHtml = _lib!.lookupFunction<_ExtractArticleHtmlC, _ExtractArticleHtmlDart>('newsbrain_extract_article_html');
        _classifyArticle = _lib!.lookupFunction<_ClassifyArticleC, _ClassifyArticleDart>('newsbrain_classify_article');
        _classifyCategory = _lib!.lookupFunction<_ClassifyCategoryC, _ClassifyCategoryDart>('newsbrain_classify_category');
        _analyzeSentiment = _lib!.lookupFunction<_AnalyzeSentimentC, _AnalyzeSentimentDart>('newsbrain_analyze_sentiment');
      }
    } catch (e) {
      // Library not found or platform unsupported - handled gracefully via isAvailable check
    }
  }

  String getVersion() {
    _ensureInitialized();
    if (_getVersion == null) return 'N/A';
    final ptr = _getVersion!();
    return ptr.toDartString();
  }

  /// Scan a URL to produce PageSkeleton (Milestone 1)
  /// On Android/iOS: fetches HTML via Dart http, then passes to C++ scanner.
  /// On Windows: C++ handles HTTP directly via WinHTTP.
  Future<PageSkeleton?> scanUrl(String url) async {
    _ensureInitialized();
    if (_lib == null) return null;

    if (_useDartHttp) {
      final html = await _fetchHtmlDart(url);
      if (html == null || html.isEmpty) return null;
      return scanHtml(html, url: url);
    }

    if (_scanUrl == null || _freeString == null) return null;
    final urlPtr = url.toNativeUtf8();
    try {
      final resPtr = _scanUrl!(urlPtr);
      if (resPtr == nullptr) return null;
      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);
      return PageSkeleton.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Scan raw HTML to produce PageSkeleton (Milestone 1)
  Future<PageSkeleton?> scanHtml(String html, {String url = ''}) async {
    _ensureInitialized();
    if (_scanHtml == null || _freeString == null) return null;

    final htmlPtr = html.toNativeUtf8();
    final urlPtr = url.toNativeUtf8();
    try {
      final resPtr = _scanHtml!(htmlPtr, urlPtr);
      if (resPtr == nullptr) return null;

      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return PageSkeleton.fromJson(data);
    } finally {
      calloc.free(htmlPtr);
      calloc.free(urlPtr);
    }
  }

  /// Full extraction pipeline from URL -> NewsArticle
  /// On Android/iOS: fetches HTML via Dart http, then passes to C++ pipeline.
  /// On Windows: C++ handles HTTP directly via WinHTTP.
  Future<NewsArticle?> extractArticleUrl(String url) async {
    _ensureInitialized();
    if (_lib == null) return null;

    if (_useDartHttp) {
      final html = await _fetchHtmlDart(url);
      if (html == null || html.isEmpty) return null;
      return extractArticleHtml(html, url: url);
    }

    if (_extractArticleUrl == null || _freeString == null) return null;
    final urlPtr = url.toNativeUtf8();
    try {
      final resPtr = _extractArticleUrl!(urlPtr);
      if (resPtr == nullptr) return null;
      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);
      return NewsArticle.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Full extraction pipeline from raw HTML -> NewsArticle
  Future<NewsArticle?> extractArticleHtml(String html, {String url = ''}) async {
    _ensureInitialized();
    if (_extractArticleHtml == null || _freeString == null) return null;

    final htmlPtr = html.toNativeUtf8();
    final urlPtr = url.toNativeUtf8();
    try {
      final resPtr = _extractArticleHtml!(htmlPtr, urlPtr);
      if (resPtr == nullptr) return null;

      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return NewsArticle.fromJson(data);
    } finally {
      calloc.free(htmlPtr);
      calloc.free(urlPtr);
    }
  }

  /// Classify article via C++ NLP and return raw JSON with category/sentiment/keywords/entities.
  Future<Map<String, dynamic>?> classifyArticle(String title, String content, String summary) async {
    _ensureInitialized();
    if (_classifyArticle == null || _freeString == null) return null;

    final titlePtr = title.toNativeUtf8();
    final contentPtr = content.toNativeUtf8();
    final summaryPtr = summary.toNativeUtf8();
    try {
      final resPtr = _classifyArticle!(titlePtr, contentPtr, summaryPtr);
      if (resPtr == nullptr) return null;
      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);
      return jsonDecode(jsonStr) as Map<String, dynamic>?;
    } finally {
      calloc.free(titlePtr);
      calloc.free(contentPtr);
      calloc.free(summaryPtr);
    }
  }

  /// Classify article category via C++ NLP.
  Future<String?> classifyCategory(String title, String content, String summary) async {
    _ensureInitialized();
    if (_classifyCategory == null || _freeString == null) return null;

    final titlePtr = title.toNativeUtf8();
    final contentPtr = content.toNativeUtf8();
    final summaryPtr = summary.toNativeUtf8();
    try {
      final resPtr = _classifyCategory!(titlePtr, contentPtr, summaryPtr);
      if (resPtr == nullptr) return null;
      final category = resPtr.toDartString();
      _freeString!(resPtr);
      return category;
    } finally {
      calloc.free(titlePtr);
      calloc.free(contentPtr);
      calloc.free(summaryPtr);
    }
  }

  /// Analyze sentiment via C++ NLP.
  Future<double> analyzeSentiment(String text) async {
    _ensureInitialized();
    if (_analyzeSentiment == null) return 0.0;

    final textPtr = text.toNativeUtf8();
    try {
      return _analyzeSentiment!(textPtr);
    } finally {
      calloc.free(textPtr);
    }
  }
}

