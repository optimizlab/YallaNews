import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/news_db.dart';

class KnowledgeEntity {
  final String id;
  final String articleUrl;
  final String type;
  final String value;
  final String normalized;
  final String language;
  final String context;
  final double confidence;
  final int extractedAt;

  KnowledgeEntity({
    required this.id,
    required this.articleUrl,
    required this.type,
    required this.value,
    this.normalized = '',
    this.language = 'ar',
    this.context = '',
    this.confidence = 1.0,
    required this.extractedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'article_url': articleUrl,
      'type': type,
      'value': value,
      'normalized': normalized,
      'language': language,
      'context': context,
      'confidence': confidence,
      'extracted_at': extractedAt,
    };
  }

  factory KnowledgeEntity.fromMap(Map<String, dynamic> map) {
    return KnowledgeEntity(
      id: map['id'] as String,
      articleUrl: map['article_url'] as String,
      type: map['type'] as String,
      value: map['value'] as String,
      normalized: map['normalized'] as String? ?? '',
      language: map['language'] as String? ?? 'ar',
      context: map['context'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      extractedAt: map['extracted_at'] as int,
    );
  }
}

class KnowledgeEvent {
  final String id;
  final String articleUrl;
  final String label;
  final String date;
  final String location;
  final List<String> actors;
  final Map<String, dynamic> evidence;
  final double confidence;
  final int extractedAt;

  KnowledgeEvent({
    required this.id,
    required this.articleUrl,
    required this.label,
    this.date = '',
    this.location = '',
    this.actors = const [],
    this.evidence = const {},
    this.confidence = 1.0,
    required this.extractedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'article_url': articleUrl,
      'label': label,
      'date': date,
      'location': location,
      'actors': jsonEncode(actors),
      'evidence': jsonEncode(evidence),
      'confidence': confidence,
      'extracted_at': extractedAt,
    };
  }

  factory KnowledgeEvent.fromMap(Map<String, dynamic> map) {
    return KnowledgeEvent(
      id: map['id'] as String,
      articleUrl: map['article_url'] as String,
      label: map['label'] as String,
      date: map['date'] as String? ?? '',
      location: map['location'] as String? ?? '',
      actors: (jsonDecode(map['actors'] as String? ?? '[]') as List).cast<String>(),
      evidence: jsonDecode(map['evidence'] as String? ?? '{}') as Map<String, dynamic>,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      extractedAt: map['extracted_at'] as int,
    );
  }
}

class KnowledgeTopic {
  final String id;
  final String articleUrl;
  final String primaryTopic;
  final List<String> secondaryTopics;
  final List<String> themes;
  final double confidence;
  final int extractedAt;

  KnowledgeTopic({
    required this.id,
    required this.articleUrl,
    required this.primaryTopic,
    this.secondaryTopics = const [],
    this.themes = const [],
    this.confidence = 1.0,
    required this.extractedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'article_url': articleUrl,
      'primary_topic': primaryTopic,
      'secondary_topics': jsonEncode(secondaryTopics),
      'themes': jsonEncode(themes),
      'confidence': confidence,
      'extracted_at': extractedAt,
    };
  }

  factory KnowledgeTopic.fromMap(Map<String, dynamic> map) {
    return KnowledgeTopic(
      id: map['id'] as String,
      articleUrl: map['article_url'] as String,
      primaryTopic: map['primary_topic'] as String,
      secondaryTopics: (jsonDecode(map['secondary_topics'] as String? ?? '[]') as List).cast<String>(),
      themes: (jsonDecode(map['themes'] as String? ?? '[]') as List).cast<String>(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      extractedAt: map['extracted_at'] as int,
    );
  }
}

class KnowledgeClaim {
  final String id;
  final String articleUrl;
  final String claimText;
  final String attributedTo;
  final String evidenceSpan;
  final double confidence;
  final int extractedAt;

  KnowledgeClaim({
    required this.id,
    required this.articleUrl,
    required this.claimText,
    this.attributedTo = '',
    this.evidenceSpan = '',
    this.confidence = 1.0,
    required this.extractedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'article_url': articleUrl,
      'claim_text': claimText,
      'attributed_to': attributedTo,
      'evidence_span': evidenceSpan,
      'confidence': confidence,
      'extracted_at': extractedAt,
    };
  }

  factory KnowledgeClaim.fromMap(Map<String, dynamic> map) {
    return KnowledgeClaim(
      id: map['id'] as String,
      articleUrl: map['article_url'] as String,
      claimText: map['claim_text'] as String,
      attributedTo: map['attributed_to'] as String? ?? '',
      evidenceSpan: map['evidence_span'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      extractedAt: map['extracted_at'] as int,
    );
  }
}

class KnowledgeExtractionService {
  KnowledgeExtractionService._internal();
  static final KnowledgeExtractionService instance = KnowledgeExtractionService._internal();

  String _generateId(String prefix, String articleUrl, String value) {
    final bytes = utf8.encode('$prefix|$articleUrl|$value');
    var hash = 0;
    for (final byte in bytes) {
      hash = (hash * 31 + byte) % 0xFFFFFFFF;
    }
    return '$prefix$hash';
  }

  Future<void> extractAndStore(String articleUrl, String title, String content, String category, {String language = 'ar'}) async {
    try {
      final db = await NewsDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final text = '$title. $content';

      final entities = _extractEntities(text, articleUrl, language, now);
      final events = _extractEvents(text, articleUrl, now);
      final topics = _extractTopics(text, articleUrl, category, now);
      final claims = _extractClaims(text, articleUrl, now);

      final uniqueEntities = _deduplicateList(entities, (e) => '${e.type}|${e.value}');
      final uniqueEvents = _deduplicateList(events, (e) => e.label);
      final uniqueTopics = _deduplicateList(topics, (t) => '${t.primaryTopic}|${t.themes.join(',')}|${t.secondaryTopics.join(',')}');
      final uniqueClaims = _deduplicateList(claims, (c) => c.claimText);

      final batch = db.batch();
      for (final entity in uniqueEntities) {
        batch.insert('yn_entities', entity.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final event in uniqueEvents) {
        batch.insert('yn_events', event.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final topic in uniqueTopics) {
        batch.insert('yn_topics', topic.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final claim in uniqueClaims) {
        batch.insert('yn_claims', claim.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      await cleanupDuplicateKnowledge(articleUrl);
    } catch (e) {
      // Silently fail knowledge extraction to avoid breaking crawl
    }
  }

  static List<T> _deduplicateList<T>(List<T> items, String Function(T) key) {
    final seen = <String>{};
    return items.where((item) {
      final normalized = key(item).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty || seen.contains(normalized)) return false;
      seen.add(normalized);
      return true;
    }).toList();
  }

  Future<void> cleanupDuplicateKnowledge(String articleUrl) async {
    try {
      final db = await NewsDatabase.instance.database;
      
      for (final entry in const <Map<String, String>>[
        {'table': 'yn_entities', 'column': 'value'},
        {'table': 'yn_events', 'column': 'label'},
        {'table': 'yn_topics', 'column': 'primary_topic'},
        {'table': 'yn_claims', 'column': 'claim_text'},
      ]) {
        final table = entry['table']!;
        final column = entry['column']!;
        
        final duplicates = await db.query(
          table,
          columns: ['id', column],
          where: 'article_url = ?',
          whereArgs: [articleUrl],
        );
        
        final seen = <String>{};
        final toDelete = <String>[];
        
        for (final row in duplicates) {
          final value = (row[column] as String?)?.trim() ?? '';
          final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (normalized.isEmpty || seen.contains(normalized)) {
            toDelete.add(row['id'] as String);
          } else {
            seen.add(normalized);
          }
        }
        
        for (final id in toDelete) {
          await db.delete(table, where: 'id = ?', whereArgs: [id]);
        }
      }
    } catch (e) {
      // Silently fail cleanup
    }
  }

  List<KnowledgeEntity> _extractEntities(String text, String articleUrl, String language, int now) {
    final entities = <KnowledgeEntity>[];
    final seen = <String>{};

    String? addEntity(String type, String value, String context, double confidence) {
      final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length < 2 || seen.contains(normalized.toLowerCase())) return null;
      for (final s in seen) {
        if (s.contains(normalized.toLowerCase()) || normalized.toLowerCase().contains(s)) return null;
      }
      seen.add(normalized.toLowerCase());
      entities.add(KnowledgeEntity(
        id: '${type}_${_generateId(type, articleUrl, value)}',
        articleUrl: articleUrl,
        type: type,
        value: normalized,
        language: language,
        context: context,
        confidence: confidence,
        extractedAt: now,
      ));
      return normalized;
    }

    String nearestSentence(String text, int matchEnd) {
      final sentences = text.split(RegExp(r'(?<=[.!?؟])\s+|\n+')).toList();
      int bestIndex = 0;
      int bestDist = 999999;
      int currentPos = 0;
      for (int i = 0; i < sentences.length; i++) {
        final s = sentences[i];
        final sStart = text.indexOf(s, currentPos);
        final sEnd = sStart + s.length;
        final dist = (matchEnd - sEnd).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestIndex = i;
        }
        currentPos = sEnd;
      }
      return sentences[bestIndex].trim();
    }

    // 1. Person Entities
    final personPrefixRegex = RegExp(
      r'(?:الملك|الرئيس|الوزير|اللاعب|المدرب|الدكتور|السيد|المسؤول|المستشار|النائب|الأمين العام|الأستاذ|البطل)\s+([ء-ي]{2,15}(?:\s+[ء-ي]{2,15}){1,3})',
    );
    for (final match in personPrefixRegex.allMatches(text)) {
      final value = match.group(1)?.trim();
      if (value != null && value.length >= 3) {
        addEntity('person', value, nearestSentence(text, match.end), 0.85);
      }
    }

    final knownFigures = [
      'محمد السادس', 'عزيز أخنوش', 'فوزي لقجع', 'وليد الركراكي', 'أشرف حكيمي',
      'سمير المرابط', 'حكيم زياش', 'محمد صلاح', 'سفيان أمرابط', 'ياسين بونو',
      'عبد الإله ابن كيران', 'ناصر بوريطة', 'عبد اللطيف لوديي', 'محمد بن سلمان',
      'تميم بن حمد', 'محمد بن زايد', 'عبد الفتاح السيسي', 'جو بايدن', 'دونالد ترامب',
      'إيمانويل ماكرون', 'فلاديمير بوتين', 'بنيامين نتنياهو',
    ];
    for (final figure in knownFigures) {
      if (text.contains(figure)) {
        addEntity('person', figure, nearestSentence(text, text.indexOf(figure) + figure.length), 0.95);
      }
    }

    // 2. Organization Entities
    final orgPrefixRegex = RegExp(
      r'(?:نادي|فريق|حكومة|وزارة|جامعة|برلمان|شركة|بنك|محكمة|منظمة|حزب|مجلس|اتحاد|جمعية|وكالة)\s+([ء-ي]{2,20}(?:\s+[ء-ي]{2,20}){1,3})',
    );
    for (final match in orgPrefixRegex.allMatches(text)) {
      final value = match.group(0)?.trim();
      if (value != null && value.length >= 4) {
        addEntity('organization', value, nearestSentence(text, match.end), 0.8);
      }
    }

    final knownOrgs = [
      'الأمم المتحدة', 'مجلس الأمن', 'الجامعة العربية', 'الاتحاد الإفريقي',
      'الاتحاد الأوروبي', 'الفيفا', 'الكاف', 'صندوق النقد الدولي', 'البنك الدولي',
      'الوداد', 'الرجاء', 'الجيش الملكي', 'ريال مدريد', 'برشلونة', 'لايبزيغ',
      'باريس سان جيرمان', 'مانشستر سيتي', 'ليفربول', 'الأهلي', 'الهلال',
    ];
    for (final org in knownOrgs) {
      if (text.contains(org)) {
        addEntity('organization', org, nearestSentence(text, text.indexOf(org) + org.length), 0.9);
      }
    }

    // 3. Location Entities
    final locations = [
      'الرباط', 'الدار البيضاء', 'مراكش', 'طنجة', 'فاس', 'أكادير', 'تطوان',
      'وجدة', 'مكناس', 'العيون', 'المغرب', 'الجزائر', 'تونس', 'مصر', 'السعودية',
      'الإمارات', 'قطر', 'فلسطين', 'غزة', 'القدس', 'القاهرة', 'الرياض', 'دبي',
      'الدوحة', 'باريس', 'مدريد', 'لندن', 'برلين', 'واشنطن', 'نيويورك', 'موسكو',
      'بكين', 'ألمانيا', 'إسبانيا', 'فرنسا', 'إنجلترا', 'إيطاليا',
    ];
    for (final loc in locations) {
      if (text.contains(loc)) {
        addEntity('location', loc, nearestSentence(text, text.indexOf(loc) + loc.length), 0.9);
      }
    }

    // 4. Numeric Statistics / Currency
    final currencyPattern = RegExp(r'(?:MAD|USD|EUR|AED|SAR|QAR|د\.م\.?|ر\.س\.?|درهم|دولار|يورو)\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*(?:مليون|مليار|ألف|درهم|دولار|يورو|%)');
    for (final match in currencyPattern.allMatches(text)) {
      final value = match.group(0)!.trim();
      addEntity('statistic', value, nearestSentence(text, match.end), 0.85);
    }

    // 5. Date Entities
    final datePattern = RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b|\b\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2}\b');
    for (final match in datePattern.allMatches(text)) {
      final value = match.group(0)!.trim();
      addEntity('date', value, nearestSentence(text, match.end), 0.9);
    }

    return entities;
  }

  List<KnowledgeEvent> _extractEvents(String text, String articleUrl, int now) {
    final events = <KnowledgeEvent>[];
    final seen = <String>{};
    final eventVerbs = [
      'أعلن', 'وقع', 'زار', 'التقى', 'اتفق', 'أطلق', 'انتخب', 'عين', 'استقال',
      'توفي', 'جرح', 'فاز', 'خسر', 'أنشأ', 'دمر', 'هاجم', 'دافع', 'استثمر',
      'اشترى', 'باع', 'صرح', 'حقق', 'انتقل', 'تفاوض', 'أكد', 'كشف', 'افتتح',
      'announced', 'signed', 'visited', 'met', 'agreed', 'launched', 'elected',
      'appointed', 'resigned', 'died', 'injured', 'won', 'lost', 'created',
      'attacked', 'invested', 'opened', 'discovered',
    ];

    final sentences = text.split(RegExp(r'(?<=[.!?؟\n])\s+')).toList();
    for (final sentence in sentences) {
      final clean = sentence.trim();
      if (clean.length < 15 || clean.length > 150) continue;
      for (final verb in eventVerbs) {
        if (clean.contains(verb)) {
          final actorMatch = RegExp(r'(?:الملك|الرئيس|الوزير|اللاعب|المدرب|الدكتور|السيد|المسؤول|المستشار|النائب|الأمين العام|الأستاذ|البطل|الوحدة|الفريق|المنتخب|النادي|الوزارة|الحكومة|الشركة|البنك|الجامعة|المحكمة|المنظمة|الحزب|المجلس|الاتحاد|الجمعية|الوكالة|نادي|فريق|حكومة|وزارة|جامعة|برلمان|شركة|بنك|محكمة|منظمة|حزب|مجلس|اتحاد|جمعية|وكالة)\s+[ء-ي]{2,20}(?:\s+[ء-ي]{2,20}){0,2}').firstMatch(clean);
          final actor = actorMatch?.group(0)?.trim() ?? '';
          final action = clean.substring(clean.indexOf(verb)).substring(0, (clean.length - clean.indexOf(verb)).clamp(0, 80)).trim();
          final label = actor.isNotEmpty ? '$actor $action' : action;
          final normalizedLabel = label.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (normalizedLabel.length < 5 || seen.contains(normalizedLabel)) continue;
          seen.add(normalizedLabel);
          events.add(KnowledgeEvent(
            id: 'evt_${_generateId('event', articleUrl, normalizedLabel)}',
            articleUrl: articleUrl,
            label: normalizedLabel,
            confidence: 0.75,
            extractedAt: now,
          ));
          break;
        }
      }
      if (events.length >= 8) break;
    }

    return events;
  }

  List<KnowledgeTopic> _extractTopics(String text, String articleUrl, String category, int now) {
    final primaryTopic = category.isEmpty ? 'أخبار عامة' : category;
    final secondaryTopics = <String>{};
    final themes = <String>{};

    final lowerText = text.toLowerCase();
    final themeKeywords = {
      'اقتصاد': ['اقتصاد', 'استثمار', 'تجارة', 'سوق', 'أسهم', 'بورصة', 'مال', 'ميزانية', 'ضريبة'],
      'حوكمة': ['حكومة', 'برلمان', 'قانون', 'سياسة', 'انتخابات', 'وزير', 'رئيس', 'نائب', 'مجلس'],
      'تقنية': ['تقنية', 'تكنولوجيا', 'رقمي', 'ذكاء', 'تطبيق', 'برمجيات', 'انترنت', 'رقمي'],
      'رياضة': ['مباراة', 'فريق', 'لاعب', 'دوري', 'بطولة', 'كرة', 'هدف', 'فوز', 'خسارة'],
      'صحة': ['صحة', 'مستشفى', 'دواء', 'طبي', 'علاج', 'أطباء', 'فيروس', 'لقاح', 'وباء'],
      'تعليم': ['مدرسة', 'جامعة', 'تعليم', 'دراسة', 'طلاب', 'أستاذ', 'مناهج', 'امتحان'],
      'بيئة': ['مناخ', 'بيئة', 'طاقة', 'احتباس', 'تلوث', 'نفايات', 'مياه', 'غابات'],
      'ثقافة': ['ثقافة', 'فن', 'مهرجان', 'سينما', 'مسرح', 'كتاب', 'أدب', 'فنان'],
    };

    for (final entry in themeKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword)) {
          if (entry.key != primaryTopic) {
            secondaryTopics.add(entry.key);
          }
          themes.add(entry.key);
          break;
        }
      }
    }

    final titleWords = text
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4 && !_isStopWord(w))
        .take(5)
        .toList();
    final titleTopic = titleWords.isNotEmpty ? titleWords.join(' ') : primaryTopic;

    return [
      KnowledgeTopic(
        id: 'topic_${_generateId('topic', articleUrl, titleTopic + (secondaryTopics.join('') + themes.join('')))}',
        articleUrl: articleUrl,
        primaryTopic: titleTopic,
        secondaryTopics: secondaryTopics.toList(),
        themes: themes.toList(),
        confidence: secondaryTopics.isEmpty ? 0.9 : 0.75,
        extractedAt: now,
      ),
    ];
  }

  bool _isStopWord(String word) {
    const stopWords = <String>{
      'في', 'من', 'إلى', 'على', 'هذا', 'هذه', 'أن', 'كان', 'كانت', 'ليس',
      'لكن', 'أو', 'ثم', 'أي', 'كل', 'مع', 'عند', 'بعد', 'قبل', 'حتى',
      'أيضا', 'حيث', 'التي', 'الذي', 'الذين', 'اللتين', 'اللاتي', 'ذلك',
    };
    return stopWords.contains(word);
  }

  List<KnowledgeClaim> _extractClaims(String text, String articleUrl, int now) {
    final claims = <KnowledgeClaim>[];

    final claimRegex = RegExp(
      r'(?:أكد|صرح|أوضح|قال|أعلن|أشار|شدد|أفاد|كشف)\s+([ء-ي\s]{2,30}?)\s+أ[نّ]\s+([^.!?؟\n]{10,140})',
    );

    for (final match in claimRegex.allMatches(text)) {
      final attributedTo = match.group(1)?.trim() ?? '';
      final statement = match.group(2)?.trim() ?? '';
      final fullClaim = match.group(0)?.trim() ?? '';

      if (statement.length >= 10) {
        claims.add(KnowledgeClaim(
          id: 'claim_${_generateId('claim', articleUrl, fullClaim)}',
          articleUrl: articleUrl,
          claimText: fullClaim,
          attributedTo: attributedTo,
          evidenceSpan: text.substring(match.start, (match.end + 30).clamp(0, text.length)),
          confidence: 0.8,
          extractedAt: now,
        ));
      }
    }

    return claims.take(8).toList();
  }

  Future<List<KnowledgeEntity>> getEntitiesForArticle(String articleUrl) async {
    final db = await NewsDatabase.instance.database;
    final maps = await db.query(
      'yn_entities',
      where: 'article_url = ?',
      whereArgs: [articleUrl],
    );
    return maps.map((map) => KnowledgeEntity.fromMap(map)).toList();
  }

  Future<List<KnowledgeEvent>> getEventsForArticle(String articleUrl) async {
    final db = await NewsDatabase.instance.database;
    final maps = await db.query(
      'yn_events',
      where: 'article_url = ?',
      whereArgs: [articleUrl],
    );
    return maps.map((map) => KnowledgeEvent.fromMap(map)).toList();
  }

  Future<List<KnowledgeTopic>> getTopicsForArticle(String articleUrl) async {
    final db = await NewsDatabase.instance.database;
    final maps = await db.query(
      'yn_topics',
      where: 'article_url = ?',
      whereArgs: [articleUrl],
    );
    return maps.map((map) => KnowledgeTopic.fromMap(map)).toList();
  }

  Future<List<KnowledgeClaim>> getClaimsForArticle(String articleUrl) async {
    final db = await NewsDatabase.instance.database;
    final maps = await db.query(
      'yn_claims',
      where: 'article_url = ?',
      whereArgs: [articleUrl],
    );
    return maps.map((map) => KnowledgeClaim.fromMap(map)).toList();
  }
}
