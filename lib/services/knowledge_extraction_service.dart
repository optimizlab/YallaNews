import 'dart:convert';
import 'dart:math';
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

  final Random _random = Random();

  String _generateId(String prefix) {
    return '$prefix${_random.nextInt(100000)}';
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

      final batch = db.batch();
      for (final entity in entities) {
        batch.insert('yn_entities', entity.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final event in events) {
        batch.insert('yn_events', event.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final topic in topics) {
        batch.insert('yn_topics', topic.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final claim in claims) {
        batch.insert('yn_claims', claim.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Silently fail knowledge extraction to avoid breaking crawl
    }
  }

  List<KnowledgeEntity> _extractEntities(String text, String articleUrl, String language, int now) {
    final entities = <KnowledgeEntity>[];
    final seen = <String>{};
    int idCounter = 0;

    // 1. Person Entities with Arabic titles
    final personPrefixRegex = RegExp(
      r'(?:الملك|الرئيس|الوزير|اللاعب|المدرب|الدكتور|السيد|المسؤول|المستشار|النائب|الأمين العام|الأستاذ|البطل)\s+([ء-ي]{2,15}(?:\s+[ء-ي]{2,15}){1,3})',
    );
    for (final match in personPrefixRegex.allMatches(text)) {
      final value = match.group(1)?.trim();
      if (value != null && value.length >= 3 && !seen.contains(value)) {
        seen.add(value);
        entities.add(KnowledgeEntity(
          id: _generateId('person_$idCounter'),
          articleUrl: articleUrl,
          type: 'person',
          value: value,
          language: language,
          context: text.substring(match.start, (match.end + 40).clamp(0, text.length)),
          confidence: 0.85,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    // Prominent known figures
    final knownFigures = [
      'محمد السادس', 'عزيز أخنوش', 'فوزي لقجع', 'وليد الركراكي', 'أشرف حكيمي',
      'سمير المرابط', 'حكيم زياش', 'محمد صلاح', 'سفيان أمرابط', 'ياسين بونو',
      'عبد الإله ابن كيران', 'ناصر بوريطة', 'عبد اللطيف لوديي', 'محمد بن سلمان',
      'تميم بن حمد', 'محمد بن زايد', 'عبد الفتاح السيسي', 'جو بايدن', 'دونالد ترامب',
      'إيمانويل ماكرون', 'فلاديمير بوتين', 'بنيامين نتنياهو',
    ];
    for (final figure in knownFigures) {
      if (text.contains(figure) && !seen.contains(figure)) {
        seen.add(figure);
        entities.add(KnowledgeEntity(
          id: _generateId('person_$idCounter'),
          articleUrl: articleUrl,
          type: 'person',
          value: figure,
          language: language,
          context: 'شخصية قيادية أو عامة ذكرت في المقال',
          confidence: 0.95,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    // 2. Organization Entities
    final orgPrefixRegex = RegExp(
      r'(?:نادي|فريق|حكومة|وزارة|جامعة|برلمان|شركة|بنك|محكمة|منظمة|حزب|مجلس|اتحاد|جمعية|وكالة)\s+([ء-ي]{2,20}(?:\s+[ء-ي]{2,20}){1,3})',
    );
    for (final match in orgPrefixRegex.allMatches(text)) {
      final value = match.group(0)?.trim();
      if (value != null && value.length >= 4 && !seen.contains(value)) {
        seen.add(value);
        entities.add(KnowledgeEntity(
          id: _generateId('org_$idCounter'),
          articleUrl: articleUrl,
          type: 'organization',
          value: value,
          language: language,
          context: text.substring(match.start, (match.end + 40).clamp(0, text.length)),
          confidence: 0.8,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    // Prominent Organizations
    final knownOrgs = [
      'الأمم المتحدة', 'مجلس الأمن', 'الجامعة العربية', 'الاتحاد الإفريقي',
      'الاتحاد الأوروبي', 'الفيفا', 'الكاف', 'صندوق النقد الدولي', 'البنك الدولي',
      'الوداد', 'الرجاء', 'الجيش الملكي', 'ريال مدريد', 'برشلونة', 'لايبزيغ',
      'باريس سان جيرمان', 'مانشستر سيتي', 'ليفربول', 'الأهلي', 'الهلال',
    ];
    for (final org in knownOrgs) {
      if (text.contains(org) && !seen.contains(org)) {
        seen.add(org);
        entities.add(KnowledgeEntity(
          id: _generateId('org_$idCounter'),
          articleUrl: articleUrl,
          type: 'organization',
          value: org,
          language: language,
          context: 'مؤسسة أو منظمة معنية',
          confidence: 0.9,
          extractedAt: now,
        ));
        idCounter++;
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
      if (text.contains(loc) && !seen.contains(loc)) {
        seen.add(loc);
        entities.add(KnowledgeEntity(
          id: _generateId('loc_$idCounter'),
          articleUrl: articleUrl,
          type: 'location',
          value: loc,
          language: language,
          context: 'الموقع الجغرافي للحدث أو التقرير',
          confidence: 0.9,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    // 4. Numeric Statistics / Currency Entities
    final currencyPattern = RegExp(r'(?:MAD|USD|EUR|AED|SAR|QAR|د\.م\.?|ر\.س\.?|درهم|دولار|يورو)\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*(?:مليون|مليار|ألف|درهم|دولار|يورو|%)');
    for (final match in currencyPattern.allMatches(text)) {
      final value = match.group(0)!.trim();
      if (!seen.contains(value)) {
        seen.add(value);
        entities.add(KnowledgeEntity(
          id: _generateId('stat_$idCounter'),
          articleUrl: articleUrl,
          type: 'statistic_currency',
          value: value,
          language: language,
          context: text.substring(match.start, (match.end + 30).clamp(0, text.length)),
          confidence: 0.85,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    // 5. Date Entities
    final datePattern = RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b|\b\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2}\b');
    for (final match in datePattern.allMatches(text)) {
      final value = match.group(0)!.trim();
      if (!seen.contains(value)) {
        seen.add(value);
        entities.add(KnowledgeEntity(
          id: _generateId('date_$idCounter'),
          articleUrl: articleUrl,
          type: 'date',
          value: value,
          language: language,
          context: text.substring(match.start, (match.end + 30).clamp(0, text.length)),
          confidence: 0.9,
          extractedAt: now,
        ));
        idCounter++;
      }
    }

    return entities;
  }

  List<KnowledgeEvent> _extractEvents(String text, String articleUrl, int now) {
    final events = <KnowledgeEvent>[];
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
      final cleanSentence = sentence.trim();
      if (cleanSentence.length < 15 || cleanSentence.length > 150) continue;
      for (final verb in eventVerbs) {
        if (cleanSentence.contains(verb)) {
          events.add(KnowledgeEvent(
            id: 'event_${_random.nextInt(100000)}',
            articleUrl: articleUrl,
            label: cleanSentence,
            confidence: 0.75,
            extractedAt: now,
          ));
          break;
        }
      }
    }

    return events.take(10).toList();
  }

  List<KnowledgeTopic> _extractTopics(String text, String articleUrl, String category, int now) {
    final primaryTopic = category.isEmpty ? 'general' : category;
    final secondaryTopics = <String>[];
    final themes = <String>[];

    final lowerText = text.toLowerCase();
    final themeKeywords = {
      'economy': ['economy', 'investment', 'trade', 'market', 'اقتصاد', 'استثمار', 'تجارة', 'سوق', 'أسهم', 'بورصة'],
      'governance': ['government', 'parliament', 'law', 'policy', 'حكومة', 'برلمان', 'قانون', 'سياسة', 'انتخابات'],
      'technology': ['technology', 'digital', 'ai', 'software', 'تقنية', 'تكنولوجيا', 'رقمي', 'ذكاء', 'تطبيق'],
      'sports': ['match', 'league', 'team', 'player', 'مباراة', 'فريق', 'لاعب', 'دوري', 'بطولة', 'كرة'],
      'health': ['health', 'hospital', 'medicine', 'صحة', 'مستشفى', 'دواء', 'طبي', 'علاج', 'أطباء'],
      'education': ['school', 'university', 'education', 'مدرسة', 'جامعة', 'تعليم', 'دراسة'],
      'environment': ['climate', 'environment', 'energy', 'مناخ', 'بيئة', 'طاقة', 'احتباس'],
      'culture': ['culture', 'art', 'festival', 'ثقافة', 'فن', 'مهرجان', 'سينما', 'مسرح'],
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

    return [
      KnowledgeTopic(
        id: 'topic_${_random.nextInt(100000)}',
        articleUrl: articleUrl,
        primaryTopic: primaryTopic,
        secondaryTopics: secondaryTopics.toSet().toList(),
        themes: themes.toSet().toList(),
        confidence: secondaryTopics.isEmpty ? 0.9 : 0.75,
        extractedAt: now,
      ),
    ];
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
          id: 'claim_${_random.nextInt(100000)}',
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
