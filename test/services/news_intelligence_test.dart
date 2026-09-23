import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/news_intelligence.dart';

void main() {
  group('NewsIntelligence', () {
    test('classifyCategory returns politics for political text', () {
      final result = NewsIntelligence.classifyCategory('رئيس الوزراء يعلن عن قرار جديد');
      expect(result, 'politics');
    });

    test('classifyCategory returns sports for sports text', () {
      final result = NewsIntelligence.classifyCategory('ريال مدريد يفوز ببطولة دوري أبطال أوروبا');
      expect(result, 'sports');
    });

    test('classifyCategory returns technology for technology text', () {
      final result = NewsIntelligence.classifyCategory('إطلاق هاتف ذكي جديد بتقنية الذكاء الاصطناعي');
      expect(result, 'technology');
    });

    test('classifyCategory returns business for economic text', () {
      final result = NewsIntelligence.classifyCategory('أسعار النفط ترتفع في الأسواق العالمية');
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
      final syncResult = NewsIntelligence.extract('عنوان الخبر', 'محتوى الخبر هنا', 'ملخص الخبر');
      final asyncResult = await NewsIntelligence.extractAsync('عنوان الخبر', 'محتوى الخبر هنا', 'ملخص الخبر');
      expect(asyncResult.category, equals(syncResult.category));
    });
  });
}