import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/arabic_normalizer.dart';

void main() {
  group('ArabicTextNormalizer', () {
    test('removeTashkeel removes diacritics', () {
      final input = 'السَّلَامُ عَلَيْكُمْ';
      final result = ArabicTextNormalizer.removeTashkeel(input);
      expect(result, 'السلام عليكم');
    });

    test('normalizeAlef converts variants to plain alef', () {
      expect(ArabicTextNormalizer.normalizeAlef('أحمد'), 'احمد');
      expect(ArabicTextNormalizer.normalizeAlef('إبراهيم'), 'ابراهيم');
      expect(ArabicTextNormalizer.normalizeAlef('آسيا'), 'اسيا');
    });

    test('normalizeTaaMarbouta converts ة to ه', () {
      expect(ArabicTextNormalizer.normalizeTaaMarbouta('مدرسة'), 'مدرسه');
    });

    test('normalizeYaaAlefMaqsoura converts ى to ي', () {
      expect(ArabicTextNormalizer.normalizeYaaAlefMaqsoura('موسى'), 'موسي');
    });

    test('removeTatweel removes kashida', () {
      final input = 'ســــلام';
      final result = ArabicTextNormalizer.removeTatweel(input);
      expect(result.contains('\u0640'), isFalse);
    });

    test('normalize combines all rules', () {
      final input = 'السَّلامُ عَلَيْكُمْ يَا أَحْمَدُ';
      final result = ArabicTextNormalizer.normalize(input);
      expect(result, 'السلام عليكم يا احمد');
    });

    test('empty string returns empty', () {
      expect(ArabicTextNormalizer.normalize(''), '');
    });
  });
}