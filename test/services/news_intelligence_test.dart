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
