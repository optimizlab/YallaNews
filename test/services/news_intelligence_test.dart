import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/news_intelligence.dart';

void main() {
  group('NewsIntelligence', () {
    test('classifyCategory returns politics for political text', () async {
      final result = await NewsIntelligence.classifyCategory(
        'رئيس الوزراء يعلن عن قرار جديد',
      );
      expect(result, 'politics');
    });

    test('classifyCategory returns sports for sports text', () async {
      final result = await NewsIntelligence.classifyCategory(
        'ريال مدريد يفوز ببطولة دوري أبطال أوروبا',
      );
      expect(result, 'sports');
    });

    test('classifyCategory returns technology for technology text', () async {
      final result = await NewsIntelligence.classifyCategory(
        'إطلاق هاتف ذكي جديد بتقنية الذكاء الاصطناعي',
      );
      expect(result, 'technology');
    });

    test('classifyCategory returns economy for economic text', () async {
      final result = await NewsIntelligence.classifyCategory(
        'The economy and stock market are changing',
      );
      expect(result, 'economy');
    });

    test('classifies NFL trade deadline news as sports, not economy', () async {
      final result = await NewsIntelligence.classifyCategory(
        '2026 NFL trade deadline: Proposing deals for Tony Pollard, Riq Woolen, others',
        title:
            '2026 NFL trade deadline: Proposing deals for Tony Pollard, Riq Woolen, others',
      );
      expect(result, 'sports');
    });

    test(
      'uses a sports section URL when the headline has no sports keywords',
      () async {
        final result = await NewsIntelligence.classifyCategory(
          'The club announces a new appointment',
          title: 'The club announces a new appointment',
          url: 'https://example.com/sports/club-announcement',
          validCategoryIds: const ['general', 'sport_news'],
        );
        expect(result, 'sport_news');
      },
    );

    test('maps sports language to a sports API category slug', () async {
      final result = await NewsIntelligence.classifyCategory(
        'The national team won the football match',
        validCategoryIds: const ['general', 'sports_news'],
      );
      expect(result, 'sports_news');
    });

    test(
      'classifies market coverage as economy when it mentions an election',
      () async {
        const title =
            'Decisive election. Dramatic stock swings. How we handled the market last week';
        final result = await NewsIntelligence.classifyCategory(
          title,
          title: title,
        );
        expect(result, 'economy');
      },
    );

    test('returns the matching API category id', () async {
      final result = await NewsIntelligence.classifyCategory(
        'The economy and stock market are changing',
        validCategoryIds: const ['general', 'business', 'sports'],
      );
      expect(result, 'business');
    });

    test('extract returns IntelligenceResult', () {
      final result = NewsIntelligence.extract(
        'عنوان الخبر',
        'محتوى الخبر هنا',
        'ملخص الخبر',
      );
      expect(result, isNotNull);
      expect(result.category, isNotNull);
      expect(result.sentiment, isNotNull);
    });

    test('extractAsync returns same category as extract', () async {
      final syncResult = NewsIntelligence.extract(
        'عنوان الخبر',
        'محتوى الخبر هنا',
        'ملخص الخبر',
      );
      final asyncResult = await NewsIntelligence.extractAsync(
        'عنوان الخبر',
        'محتوى الخبر هنا',
        'ملخص الخبر',
      );
      expect(asyncResult.category, equals(syncResult.category));
    });
  });
}
