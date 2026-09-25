import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/news_model.dart';
import 'arabic_normalizer.dart';
import 'news_grouping_service.dart';
import 'ollama_service.dart';
import 'semantic_cluster.dart';

class _BlendArticlesInput {
  final List<NewsModel> rawArticles;
  _BlendArticlesInput(this.rawArticles);
}

List<NewsModel> _blendArticlesIsolate(_BlendArticlesInput input) {
  return NewsBlenderService.instance.blendArticles(input.rawArticles);
}

/// NewsBlenderService — Intelligent multi-source article synthesis engine.
///
/// Blends news articles covering the same subject or event into one rich,
/// cohesive, and optimized article while strictly preserving source counts,
/// source URLs, domains, and individual source attributions.
class NewsBlenderService {
  NewsBlenderService._();
  static final NewsBlenderService instance = NewsBlenderService._();

  static const List<String> _clickbaitKeywords = [
    'شاهد بالفيديو',
    'بالفيديو',
    'لن تصدق',
    'صدمة',
    'فضيحة',
    'عاجل جدا',
    'مثير للجدل',
    'خطير جدا',
    'كارثة',
    'شاهد ما حدث',
  ];

  static const List<String> _boilerplatePatterns = [
    'تابعونا على',
    'اشترك في قناتنا',
    'حقوق النشر محفوظة',
    'إقرأ أيضاً',
    'المصدر:',
    'جميع الحقوق محفوظة',
    'اضغط هنا',
    'شارك المقال',
    'للمزيد من الأخبار',
    'تطبيق هسبريس',
    'تابعنا عبر فيسبوك',
    'تابعنا على',
    'انشر على',
    'أخبار ذات صلة',
    'مقالات مرتبطة',
    'شاهد أيضاً',
    'التعليقات',
    'أضف تعليق',
    'إرسال تعليق',
    'جميع الحقوق',
    '©',
    'كل الحقوق',
  ];

  static final RegExp _hashtagPattern = RegExp(r'\s*#\w+(?:\s*#\w+)*\s*');

  static const Set<String> _stopWords = {
    'في', 'من', 'إلى', 'على', 'هذا', 'هذه', 'أن', 'كان', 'كانت', 'ليس',
    'لكن', 'أو', 'ثم', 'أي', 'كل', 'مع', 'عند', 'بعد', 'قبل', 'حتى',
    'أيضا', 'حيث', 'التي', 'الذي', 'الذين', 'اللتين', 'اللاتي', 'ذلك',
    'هو', 'هي', 'هم', 'هن', 'نحن', 'أنت', 'أنا', 'قد', 'ما', 'لا',
    'إن', 'عبر', 'بين', 'حول', 'ضمن', 'فوق', 'تحت', 'خلال',
  };

  /// Async primary entry point: groups using Ollama embeddings, blends using Ollama text generation.
  Future<List<NewsModel>> blendArticlesAsync(List<NewsModel> rawArticles) async {
    if (rawArticles.isEmpty) return const [];
    if (rawArticles.length == 1) return [_optimizeSingleArticle(rawArticles.first)];
    
    final ollamaAvailable = await OllamaService.instance.isOllamaAvailable();
    if (!ollamaAvailable) {
      return compute(_blendArticlesIsolate, _BlendArticlesInput(rawArticles));
    }
    
    final clusters = await NewsGroupingService.instance.groupBySubjectAsync(rawArticles);
    final blended = <NewsModel>[];
    for (final cluster in clusters) {
      blended.add(await ollamaBlendCluster(cluster));
    }
    return blended;
  }

  /// Sync fallback entry point (TF-IDF grouping, heuristic blending).
  List<NewsModel> blendArticles(List<NewsModel> rawArticles) {
    if (rawArticles.isEmpty) return const [];
    if (rawArticles.length == 1) return [_optimizeSingleArticle(rawArticles.first)];
    final clusters = NewsGroupingService.instance.groupBySubject(rawArticles);
    return clusters.map((c) => blendCluster(c)).toList();
  }

  /// Async Ollama-powered cluster blender.
  Future<NewsModel> ollamaBlendCluster(SubjectCluster cluster) async {
    final articles = cluster.articles;
    if (articles.isEmpty) return NewsModel.empty('');
    if (articles.length == 1) return _optimizeSingleArticle(articles.first);

    final allSources = <String>[];
    final seenUrls = <String>{};
    for (final a in articles) {
      for (final u in [a.url, ...a.sources]) {
        final t = u.trim();
        if (t.isNotEmpty && seenUrls.add(t)) allSources.add(t);
      }
    }

    // 1. Generate title via Ollama
    final titlesInput = articles.map((a) => '- ${a.title}').take(5).join('\n');
    final rawTitle = await OllamaService.instance.generateText(
      'بناءً على هذه العناوين الإخبارية:\n$titlesInput\nاكتب عنواناً صحفياً واحداً موضوعياً ومختصراً باللغة العربية لا يتجاوز 15 كلمة. أجب بالعنوان فقط.',
      system: 'أنت محرر صحفي محترف. تكتب عناوين موضوعية ودقيقة باللغة العربية الفصحى.',
    );
    final masterTitle = (rawTitle?.trim().isNotEmpty == true)
        ? rawTitle!.trim()
        : synthesizeTitle(articles);

    // 2. Generate lead via Ollama
    final summariesInput = articles
        .map((a) => a.summary.isNotEmpty ? a.summary : a.content.substring(0, a.content.length.clamp(0, 200)))
        .take(4)
        .join('\n---\n');
    final rawLead = await OllamaService.instance.generateText(
      'استناداً إلى الملخصات التالية:\n$summariesInput\nاكتب مقدمة صحفية وجيزة من 2-3 جمل باللغة العربية تلخص أبرز الحقائق. أجب بالمقدمة فقط.',
      system: 'أنت محرر صحفي محترف. تكتب مقدمات وجيزة ودقيقة باللغة العربية الفصحى.',
    );
    final executiveLead = rawLead?.trim().isNotEmpty == true ? rawLead!.trim() : synthesizeLead(articles);

    // 3. Generate highlights via Ollama
    final contentInput = articles
        .map((a) => a.content.substring(0, a.content.length.clamp(0, 300)))
        .take(4)
        .join('\n---\n');
    final rawHighlights = await OllamaService.instance.generateText(
      'من النصوص الإخبارية التالية:\n$contentInput\nاستخرج 3-4 نقاط رئيسية مختصرة باللغة العربية. أجب بقائمة منقوطة فقط.',
      system: 'أنت محرر صحفي خبير في استخراج أبرز المعلومات.',
    );
    final highlights = rawHighlights?.trim().isNotEmpty == true
        ? rawHighlights!.trim().split('\n').where((l) => l.trim().isNotEmpty).take(4).toList()
        : extractHighlights(articles, maxHighlights: 4);

    // 4. Generate rich content paragraphs via Ollama
    final richParagraphs = await ollamaGenerateParagraphs(articles, masterTitle);
    final blendedBody = richParagraphs.isNotEmpty ? richParagraphs : blendContent(articles, executiveLead: executiveLead, title: masterTitle);

    final attributions = buildSourceAttributions(articles);
    final bestImageUrl = _selectBestImage(articles);
    final mergedKeywords = _mergeKeywords(articles);
    final mergedEntities = _mergeEntities(articles);
    final avgSentiment = articles.map((a) => a.sentiment).reduce((a, b) => a + b) / articles.length;
    final latestDate = articles.map((a) => a.publishDate).where((d) => d.isNotEmpty)
        .fold<String>('', (prev, d) => d.compareTo(prev) > 0 ? d : prev);
    final primary = articles.first;

    final structuredData = Map<String, dynamic>.from(primary.structuredData)
      ..['is_blended'] = true
      ..['is_ollama_blended'] = true
      ..['highlights'] = highlights
      ..['source_attributions'] = attributions
      ..['subject_topic'] = cluster.subjectTitle
      ..['original_source_count'] = attributions.length;

    final uniqueSourceDomains = <String>{};
    for (final a in articles) {
      final domain = _extractDomain(a.url);
      if (domain.isNotEmpty) uniqueSourceDomains.add(domain);
    }

    final blendedModel = NewsModel(
      url: primary.url, urlHash: primary.urlHash,
      title: masterTitle, shortTitle: cluster.subjectTitle,
      summary: executiveLead, content: blendedBody,
      imageUrl: bestImageUrl, category: cluster.category,
      sentiment: avgSentiment, keywords: mergedKeywords,
      logs: 'ollama_blended_from_${attributions.length}_sources',
      author: primary.author.isNotEmpty ? primary.author : '${attributions.length} مصادر إخبارية',
      publishDate: latestDate.isNotEmpty ? latestDate : primary.publishDate,
      eventType: primary.eventType, subcategory: primary.subcategory,
      entities: mergedEntities, structuredData: structuredData,
      intelligenceJson: primary.intelligenceJson,
      sourceCount: uniqueSourceDomains.length,
      sources: allSources,
    );
    blendedModel.relatedArticles = List<NewsModel>.from(articles);
    return blendedModel;
  }

  /// Uses Ollama to re-write crawled paragraphs into rich, well-structured content.
  Future<String> ollamaGenerateParagraphs(List<NewsModel> articles, String topic) async {
    final combinedLength = articles.fold<int>(0, (s, a) => s + a.content.length);
    final rawText = articles
        .map((a) => a.content.trim())
        .where((c) => c.isNotEmpty)
        .take(5)
        .join('\n\n')
        .substring(0, combinedLength.clamp(0, 2000));

    if (rawText.trim().length < 100) return '';

    final generated = await OllamaService.instance.generateText(
      'الموضوع: $topic\n\nالنصوص المصدر:\n$rawText\n\nأعد كتابة هذا المحتوى على شكل 3 إلى 5 فقرات صحفية متسلسلة باللغة العربية الفصحى. احتفظ بالمعلومات الحقيقية فقط. لا تضف مقدمة أو تعليقاً.',
      system: 'أنت محرر صحفي محترف تكتب مقالات موضوعية بالعربية الفصحى.',
    );

    if (generated == null || generated.trim().isEmpty) return '';

    final paragraphs = generated.trim().split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.length > 30)
        .toList();

    return paragraphs.map((p) => '<p>$p</p>').join('\n\n');
  }

  /// Blends a single SubjectCluster of articles into one rich NewsModel.
  NewsModel blendCluster(SubjectCluster cluster) {
    final articles = cluster.articles;
    if (articles.isEmpty) {
      return NewsModel.empty('');
    }

    if (articles.length == 1) {
      return _optimizeSingleArticle(articles.first);
    }

    if (!_isCoherentCluster(articles)) {
      return _optimizeSingleArticle(articles.first);
    }

    // 1. Synthesize the most objective, informative headline
    final masterTitle = synthesizeTitle(articles);

    // 2. Synthesize a comprehensive executive lead paragraph
    final executiveLead = synthesizeLead(articles);

    // 3. Extract distinct key highlights across all sources
    final highlights = extractHighlights(articles, maxHighlights: 4);

    // 4. Thematic body fusion with sentence deduplication
    final blendedBody = blendContent(articles, executiveLead: executiveLead, title: masterTitle);

    // 5. Gather source URLs and distinct source count
    final allSources = <String>[];
    final seenUrls = <String>{};
    for (final a in articles) {
      final u = a.url.trim();
      if (u.isNotEmpty && !seenUrls.contains(u)) {
        seenUrls.add(u);
        allSources.add(u);
      }
      for (final s in a.sources) {
        final su = s.trim();
        if (su.isNotEmpty && !seenUrls.contains(su)) {
          seenUrls.add(su);
          allSources.add(su);
        }
      }
    }

    // 6. Build structured source attributions
    final attributions = buildSourceAttributions(articles);

    // 7. Select highest quality image
    final bestImageUrl = _selectBestImage(articles);

    // 8. Merge entities & keywords
    final mergedKeywords = _mergeKeywords(articles);
    final mergedEntities = _mergeEntities(articles);

    // 9. Aggregate average sentiment
    final avgSentiment = articles.map((a) => a.sentiment).reduce((a, b) => a + b) / articles.length;

    // 10. Most recent publish date
    final latestDate = articles
        .map((a) => a.publishDate)
        .where((d) => d.isNotEmpty)
        .fold<String>('', (prev, d) => d.compareTo(prev) > 0 ? d : prev);

    // 11. Choose representative author
    final primary = articles.first;
    final author = primary.author.isNotEmpty
        ? primary.author
        : '${attributions.length} مصادر إخبارية متطابقة';

    final structuredData = Map<String, dynamic>.from(primary.structuredData);
    structuredData['is_blended'] = true;
    structuredData['highlights'] = highlights;
    structuredData['source_attributions'] = attributions;
    structuredData['subject_topic'] = cluster.subjectTitle;
    structuredData['original_source_count'] = attributions.length;

    final uniqueSourceDomains = <String>{};
    for (final a in articles) {
      final domain = _extractDomain(a.url);
      if (domain.isNotEmpty) uniqueSourceDomains.add(domain);
    }

    final blendedModel = NewsModel(
      url: primary.url,
      urlHash: primary.urlHash,
      title: masterTitle,
      shortTitle: cluster.subjectTitle,
      summary: executiveLead,
      content: blendedBody,
      imageUrl: bestImageUrl,
      category: cluster.category,
      sentiment: avgSentiment,
      keywords: mergedKeywords,
      logs: 'blended_from_${attributions.length}_sources',
      author: author,
      publishDate: latestDate.isNotEmpty ? latestDate : primary.publishDate,
      eventType: primary.eventType,
      subcategory: primary.subcategory,
      entities: mergedEntities,
      structuredData: structuredData,
      intelligenceJson: primary.intelligenceJson,
      sourceCount: uniqueSourceDomains.length,
      sources: allSources,
    );

    blendedModel.relatedArticles = List<NewsModel>.from(articles);
    return blendedModel;
  }

  /// Synthesizes the optimal headline across all candidate titles
  String synthesizeTitle(List<NewsModel> articles) {
    if (articles.isEmpty) return '';
    if (articles.length == 1) return _cleanTitle(articles.first.title);

    NewsModel? bestArticle;
    double bestScore = -999.0;

    for (final a in articles) {
      final clean = _cleanTitle(a.title);
      final words = clean.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      double score = 0.0;

      // Ideal title word count: 6 to 14 words
      if (words.length >= 6 && words.length <= 14) {
        score += 15.0;
      } else if (words.length >= 4) {
        score += 8.0;
      } else {
        score -= 10.0;
      }

      // Penalty for clickbait terms
      for (final cb in _clickbaitKeywords) {
        if (clean.contains(cb)) {
          score -= 15.0;
        }
      }

      // Bonus for presence of numbers/dates (factual indicator)
      if (RegExp(r'\d+').hasMatch(clean)) {
        score += 5.0;
      }

      // Bonus for authoritative source domain
      final url = a.url.toLowerCase();
      if (url.contains('hespress.com') || url.contains('le360.ma')) {
        score += 6.0;
      } else if (url.contains('alyaoum24.com') || url.contains('almountakhab.com')) {
        score += 4.0;
      }

      if (score > bestScore) {
        bestScore = score;
        bestArticle = a;
      }
    }

    return _cleanTitle(bestArticle?.title ?? articles.first.title);
  }

  /// Synthesizes an executive lead paragraph from the participating articles
  String synthesizeLead(List<NewsModel> articles) {
    if (articles.isEmpty) return '';

    final candidates = <String>[];
    for (final a in articles) {
      if (a.summary.trim().isNotEmpty) {
        candidates.add(_cleanSentence(a.summary.trim()));
      }
    }

    if (candidates.isEmpty) {
      for (final a in articles) {
        final sentences = _splitSentences(a.content);
        if (sentences.isNotEmpty) {
          candidates.add(sentences.first);
        }
      }
    }

    if (candidates.isEmpty) {
      return articles.first.title;
    }

    // Pick the most comprehensive lead (longest within 15-45 words)
    candidates.sort((a, b) {
      final lenA = a.split(' ').length;
      final lenB = b.split(' ').length;
      final scoreA = (lenA >= 15 && lenA <= 45) ? lenA * 2 : lenA;
      final scoreB = (lenB >= 15 && lenB <= 45) ? lenB * 2 : lenB;
      return scoreB.compareTo(scoreA);
    });

    final primaryLead = candidates.first;

    // Check if secondary sources offer additional distinct numbers/dates not in primary
    for (final other in candidates.skip(1)) {
      final numbersInOther = RegExp(r'\b\d+\b').allMatches(other).map((m) => m.group(0)!).toSet();
      final numbersInPrimary = RegExp(r'\b\d+\b').allMatches(primaryLead).map((m) => m.group(0)!).toSet();
      final diff = numbersInOther.difference(numbersInPrimary);
      if (diff.isNotEmpty && !primaryLead.contains(other.substring(0, min(20, other.length)))) {
        return '$primaryLead ووفق معطيات إضافية أكدتها مصادر متابعة، فإن $other';
      }
    }

    return primaryLead;
  }

  /// Extracts key factual bullet highlights across all source articles
  List<String> extractHighlights(List<NewsModel> articles, {int maxHighlights = 4}) {
    final allSentences = <String>[];
    for (final a in articles) {
      final fullText = '${a.summary}. ${a.content}';
      final sList = _splitSentences(fullText);
      for (final s in sList) {
        final clean = _cleanSentence(s);
        if (_isQualityHighlightSentence(clean)) {
          allSentences.add(clean);
        }
      }
    }

    final selected = <String>[];
    for (final s in allSentences) {
      if (selected.length >= maxHighlights) break;

      bool isDuplicate = false;
      for (final existing in selected) {
        if (_sentenceSimilarity(s, existing) > 0.40) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        selected.add(s);
      }
    }

    return selected;
  }

  /// Blends the multi-source content into structured thematic sections
  String blendContent(List<NewsModel> articles, {required String executiveLead, required String title}) {
    if (articles.isEmpty) return '';

    final titleTokens = _tokenize(title).toSet();
    if (titleTokens.isEmpty && articles.isNotEmpty) {
      titleTokens.addAll(_tokenize(articles.first.title).toSet());
    }

    final quoteSentences = <String>[];
    final detailSentences = <String>[];
    final contextSentences = <String>[];

    final seenStems = <String>{};
    final seenExactSentences = <String>{};

    for (final article in articles) {
      final sourceName = _extractSourceName(article);
      final paragraphs = _splitParagraphs(article.content);
      final uniqueParagraphs = <String>[];
      final seenParagraphs = <String>{};

      for (final para in paragraphs) {
        final normalizedPara = _normalizeParagraph(para);
        if (normalizedPara.isEmpty || seenParagraphs.contains(normalizedPara)) continue;
        seenParagraphs.add(normalizedPara);
        uniqueParagraphs.add(para.trim());
      }

      for (final para in uniqueParagraphs) {
        final sentences = _splitSentences(para);
        for (final rawSentence in sentences) {
          final sentence = _cleanSentence(rawSentence);
          if (!_isQualitySentence(sentence)) continue;

          final normalizedSentence = _normalizeParagraph(sentence);
          if (seenExactSentences.contains(normalizedSentence)) continue;
          seenExactSentences.add(normalizedSentence);

          final tokens = _tokenize(sentence);
          if (tokens.isEmpty) continue;

          final tokenKey = tokens.take(8).join(' ');
          if (seenStems.contains(tokenKey)) continue;

          bool duplicate = false;
          for (final seen in seenStems) {
            if (_jaccard(tokens.toSet(), seen.split(' ').toSet()) > 0.45) {
              duplicate = true;
              break;
            }
          }
          if (duplicate) continue;
          seenStems.add(tokenKey);

          final sentenceTokens = tokens.toSet();
          final relevance = titleTokens.isEmpty ? 1.0 : (sentenceTokens.intersection(titleTokens).length / sentenceTokens.length);
          if (relevance < 0.15 && !_isQuoteOrStatement(sentence)) continue;

          if (_isQuoteOrStatement(sentence)) {
            if (!sentence.contains(sourceName)) {
              quoteSentences.add('$sentence (أوردته $sourceName)');
            } else {
              quoteSentences.add(sentence);
            }
          } else if (_isContextOrBackground(sentence)) {
            contextSentences.add(sentence);
          } else {
            detailSentences.add(sentence);
          }
        }
      }
    }

    final buffer = StringBuffer();

    // Opening Lead
    if (executiveLead.isNotEmpty) {
      buffer.writeln(executiveLead);
      buffer.writeln();
    }

    // Section 1: تفاصيل الوقائع والأحداث
    if (detailSentences.isNotEmpty) {
      buffer.writeln('### تفاصيل الوقائع والأحداث');
      buffer.writeln();
      final paragraph = detailSentences.take(6).join(' ');
      buffer.writeln(paragraph);
      buffer.writeln();
    }

    // Section 2: التصريحات والمواقف
    if (quoteSentences.isNotEmpty) {
      buffer.writeln('### المواقف والتصريحات الرسمية');
      buffer.writeln();
      for (final q in quoteSentences.take(4)) {
        buffer.writeln('- $q');
      }
      buffer.writeln();
    }

    // Section 3: السياق والأبعاد
    if (contextSentences.isNotEmpty) {
      buffer.writeln('### السياق والخلفية');
      buffer.writeln();
      final ctx = contextSentences.take(5).join(' ');
      buffer.writeln(ctx);
      buffer.writeln();
    }

    // Fallback if sections were sparse
    if (buffer.length < 100) {
      buffer.clear();
      if (executiveLead.isNotEmpty) buffer.writeln(executiveLead);
      for (final a in articles) {
        if (a.content.isNotEmpty) {
          buffer.writeln();
          buffer.writeln(a.content);
          break;
        }
      }
    }

    final result = buffer.toString().trim();

    // Post-processing: remove duplicate sentences
    return _removeDuplicateSentences(result);
  }

  String _normalizeParagraph(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  List<String> _splitParagraphs(String text) {
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.length >= 20)
        .toList();
  }

  String _removeDuplicateSentences(String text) {
    if (text.isEmpty) return text;
    final sentences = _splitSentences(text);
    final seen = <String>{};
    final unique = <String>[];
    for (final s in sentences) {
      final normalized = _normalizeParagraph(s);
      if (seen.contains(normalized)) continue;
      seen.add(normalized);
      unique.add(s);
    }
    return unique.join(' ');
  }

  /// Builds rich source attributions list with outlet names and links
  List<Map<String, dynamic>> buildSourceAttributions(List<NewsModel> articles) {
    final list = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final a in articles) {
      final u = a.url.trim();
      if (u.isEmpty) continue;
      final domain = _extractDomain(u);
      if (seen.contains(domain)) continue;
      seen.add(domain);

      list.add({
        'name': _domainToName(domain),
        'domain': domain,
        'url': u,
        'title': a.title,
        'publishDate': a.publishDate,
        'author': a.author,
      });
    }

    return list;
  }

  bool _isCoherentCluster(List<NewsModel> articles) {
    if (articles.length <= 1) return true;

    final primary = articles.first;
    final totalSim = <double>[];
    for (final other in articles.skip(1)) {
      final vecA = SemanticCluster.buildTfIdfVector(primary);
      final vecB = SemanticCluster.buildTfIdfVector(other);
      final sim = SemanticCluster.cosineSimilarity(vecA, vecB);
      totalSim.add(sim);
    }

    if (totalSim.isEmpty) return true;
    final avgSim = totalSim.reduce((a, b) => a + b) / totalSim.length;
    return avgSim >= 0.35;
  }

  NewsModel _optimizeSingleArticle(NewsModel article) {
    if (article.highlights.isNotEmpty) return article;

    final highlights = extractHighlights([article], maxHighlights: 3);
    if (highlights.isEmpty) return article;

    final structured = Map<String, dynamic>.from(article.structuredData);
    structured['highlights'] = highlights;
    return article.copyWith(structuredData: structured);
  }

  String _cleanTitle(String title) {
    var clean = title.trim();
    clean = clean.replaceAll(RegExp(r'^(?:فيديو|عاجل|صور|شاهد|حصرياً|متابعة|هام)\s*[:：\-]\s*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }

  String _cleanSentence(String sentence) {
    var s = sentence.trim();
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    for (final bp in _boilerplatePatterns) {
      s = s.replaceAll(bp, '');
    }
    s = s.replaceAll(_hashtagPattern, ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _splitSentences(String text) {
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'(?<=[.!?؟])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.length >= 10)
        .toList();
  }

  bool _isQualityHighlightSentence(String s) {
    final words = s.split(RegExp(r'\s+'));
    if (words.length < 10 || words.length > 30) return false;
    for (final bp in _boilerplatePatterns) {
      if (s.contains(bp)) return false;
    }
    return true;
  }

  bool _isQualitySentence(String s) {
    final words = s.split(RegExp(r'\s+'));
    if (words.length < 8 || words.length > 50) return false;
    for (final bp in _boilerplatePatterns) {
      if (s.contains(bp)) return false;
    }
    return true;
  }

  bool _isQuoteOrStatement(String s) {
    const quoteWords = ['قال', 'أكد', 'أوضح', 'صرّح', 'أفاد', 'أشار', 'أعلن', 'ذكر', 'شدد'];
    for (final w in quoteWords) {
      if (s.contains(w)) return true;
    }
    return s.contains('"') || s.contains('«') || s.contains('”');
  }

  bool _isContextOrBackground(String s) {
    const contextWords = ['سياق', 'خلفية', 'جدير بالذكر', 'يشار إلى', 'في وقت سابق', 'تاريخياً', 'منذ', 'وكانت'];
    for (final w in contextWords) {
      if (s.contains(w)) return true;
    }
    return false;
  }

  double _sentenceSimilarity(String a, String b) {
    final tokA = _tokenize(a).toSet();
    final tokB = _tokenize(b).toSet();
    return _jaccard(tokA, tokB);
  }

  double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  List<String> _tokenize(String s) {
    final norm = ArabicTextNormalizer.normalize(s).toLowerCase();
    final words = norm
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .toList();
    return words;
  }

  String _selectBestImage(List<NewsModel> articles) {
    for (final a in articles) {
      final img = a.imageUrl.trim();
      if (img.isNotEmpty &&
          !img.contains('placeholder') &&
          !img.contains('placehold.co') &&
          (img.startsWith('http://') || img.startsWith('https://'))) {
        return img;
      }
    }
    for (final a in articles) {
      if (a.imageUrl.isNotEmpty) return a.imageUrl;
    }
    return articles.first.imageUrl;
  }

  List<String> _mergeKeywords(List<NewsModel> articles) {
    final freq = <String, int>{};
    for (final a in articles) {
      for (final kw in a.keywords) {
        final clean = kw.trim();
        if (clean.length >= 2) {
          freq[clean] = (freq[clean] ?? 0) + 1;
        }
      }
    }
    final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  List<String> _mergeEntities(List<NewsModel> articles) {
    final set = <String>{};
    for (final a in articles) {
      for (final ent in a.entities) {
        final clean = ent.trim();
        if (clean.length >= 2) set.add(clean);
      }
    }
    return set.toList();
  }

  String _extractSourceName(NewsModel article) {
    final domain = _extractDomain(article.url);
    return _domainToName(domain);
  }

  static String _extractDomain(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host.isNotEmpty ? host : rawUrl;
    } catch (_) {
      return rawUrl;
    }
  }

  static String _domainToName(String domain) {
    final lc = domain.toLowerCase();
    if (lc.contains('hespress')) return 'هسبريس';
    if (lc.contains('le360')) return 'Le360';
    if (lc.contains('alyaoum24')) return 'اليوم 24';
    if (lc.contains('almountakhab')) return 'المنتخب';
    if (lc.contains('chouftv')) return 'شوف تيفي';
    if (lc.contains('febrayer')) return 'فبراير';
    if (lc.contains('rue20')) return 'زنقة 20';
    if (lc.contains('barlamane')) return 'برلمان.كوم';
    if (lc.contains('al3omk')) return 'العمق المغربي';
    if (lc.contains('ifada')) return 'إفادة';
    if (lc.contains('aljazeera')) return 'الجزيرة';
    if (lc.contains('alarabiya')) return 'العربية';
    if (lc.contains('skynews')) return 'سكاي نيوز';
    if (lc.contains('bbc')) return 'BBC عربي';
    if (lc.contains('france24')) return 'فرانس 24';
    return domain.isNotEmpty ? domain : 'مصدر إخباري';
  }
}
