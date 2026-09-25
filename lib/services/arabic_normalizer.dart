import 'dart:math';

class ArabicTextNormalizer {
  static final tashkeel = RegExp(r'[\u064B-\u065F\u0670\u0640]');
  static final alefVariants = RegExp(r'[أإآ]');
  static final taaMarbouta = RegExp(r'ة');
  static final yaaAlefMaqsoura = RegExp(r'ى');
  static final tatweel = RegExp(r'\u0640');
  static final arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static final westernDigits = '0123456789';

  static final _punctuationAndSymbols = [
    '>',
    '<',
    '‘',
    '\uFEFF',
    '°',
    '©',
    '؛',
    '~',
    '\$',
    '+',
    '»',
    '«',
    '@',
    '"',
    '"',
    '%',
    ':',
    '!',
    '_',
    '-',
    '–',
    '#',
    '*',
    '|',
    '…',
    '¨',
    '’',
    "'",
    ':',
    ')',
    '(',
    '[',
    ']',
    '}',
    '{',
    '/',
    '\\',
    '?',
    '؟',
    '&',
    '=',
    ';',
    ',',
    '¸',
    '،',
    '.',
    '″',
    '“',
    '”',
  ];

  static final _stopWords = <String>{
    'في',
    'من',
    'إلى',
    'على',
    'هذا',
    'هذه',
    'أن',
    'كان',
    'كانت',
    'ليس',
    'لكن',
    'أو',
    'ثم',
    'أي',
    'كل',
    'التي',
    'الذي',
    'الذين',
    'أنه',
    'أنها',
    'ذلك',
    'تلك',
    'قد',
    'لقد',
    'حتى',
    'عبر',
    'مع',
    'بعد',
    'قبل',
    'خلال',
    'بين',
    'عن',
    'هو',
    'هي',
    'نحن',
    'هم',
    'هن',
    'منذ',
    'حيث',
    'كيف',
    'متى',
    'أين',
    'لم',
    'لن',
    'إذا',
    'ما',
    'لا',
    'بل',
    'حتى',
    'كذلك',
    'بعض',
    'جميع',
    ' frente',
  };

  static String removeTashkeel(String text) {
    if (text.isEmpty) return text;
    return tashkeel.allMatches(text).fold<String>(text, (result, m) {
      return result.replaceRange(m.start, m.end, '');
    });
  }

  static String normalizeAlef(String text) {
    if (text.isEmpty) return text;
    return alefVariants.allMatches(text).fold<String>(text, (result, m) {
      return result.replaceRange(m.start, m.end, 'ا');
    });
  }

  static String normalizeTaaMarbouta(String text) {
    if (text.isEmpty) return text;
    return taaMarbouta.allMatches(text).fold<String>(text, (result, m) {
      return result.replaceRange(m.start, m.end, 'ه');
    });
  }

  static String normalizeYaaAlefMaqsoura(String text) {
    if (text.isEmpty) return text;
    return yaaAlefMaqsoura.allMatches(text).fold<String>(text, (result, m) {
      return result.replaceRange(m.start, m.end, 'ي');
    });
  }

  static String removeTatweel(String text) {
    if (text.isEmpty) return text;
    return tatweel.allMatches(text).fold<String>(text, (result, m) {
      return result.replaceRange(m.start, m.end, '');
    });
  }

  static String normalizeDigits(String text) {
    if (text.isEmpty) return text;
    for (int i = 0; i < arabicDigits.length; i++) {
      text = text.replaceAll(arabicDigits[i], westernDigits[i]);
    }
    return text;
  }

  static String removePunctuationAndSymbols(String text) {
    if (text.isEmpty) return text;
    for (final sym in _punctuationAndSymbols) {
      text = text.replaceAll(sym, ' ');
    }
    return text;
  }

  static String collapseSpaces(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String stemSimple(String word) {
    if (word.length <= 2) return word;

    String w = word;

    final prefixes = ['ب', 'ك', 'س', 'و', 'ل', 'أ', 'آ'];
    if (prefixes.contains(w.substring(0, 1))) {
      final second = w.length > 1 ? w.substring(1, 2) : '';
      final third = w.length > 2 ? w.substring(2, 3) : '';

      if (w.startsWith('ب')) {
        if (second == 'أ' || second == 'إ' || second == 'ا') {
          if (second == 'ا' && third == 'ل' && w.length >= 4) {
            w = w.substring(3);
          } else {
            w = w.substring(1);
          }
        }
      } else if (w.startsWith('ك')) {
        if (second == 'أ' || second == 'إ' || second == 'ا') {
          if (second == 'ا' && third == 'ل' && w.length >= 4) {
            w = w.substring(3);
          } else {
            w = w.substring(1);
          }
        }
      } else if (w.startsWith('س')) {
        if (second == 'أ' || second == 'إ') {
          w = w.substring(1);
        } else if (second == 'ت') {
          w = w.substring(2);
        } else if (second == 'ي') {
          w = w.substring(1);
        }
      } else if (w.startsWith('و')) {
        if (second == 'أ' || second == 'إ' || second == 'ا') {
          if (second == 'ا' && third == 'ل' && w.length >= 4) {
            w = w.substring(3);
          } else {
            w = w.substring(1);
          }
        }
      } else if (w.startsWith('ا')) {
        if (second == 'ل' && w.length >= 3) {
          w = w.substring(2);
        }
      } else if (w.startsWith('أ')) {
        if (second == 'أ' && w.length >= 2) {
          w = w.substring(1);
        }
      } else if (w.startsWith('ل')) {
        if (second == 'أ' || second == 'إ' || second == 'ا') {
          w = w.substring(1);
        } else if (second == 'ل') {
          final thirdChar = w.length > 2 ? w.substring(2, 3) : '';
          if (thirdChar == 'أ' || thirdChar == 'ا' || thirdChar == 'إ') {
            w = w.substring(2);
          } else {
            w = w.substring(1);
          }
        }
      } else if (w.startsWith('آ')) {
        w = w.replaceFirst('آ', 'أ');
      }
    }

    return w;
  }

  static String removeStopwords(String text) {
    if (text.isEmpty) return text;
    final words = text.split(RegExp(r'\s+'));
    final filtered = words.where((w) => w.isNotEmpty && !_stopWords.contains(w)).toList();
    return filtered.join(' ');
  }

  static List<String> split(String text) {
    final cleaned = removePunctuationAndSymbols(text);
    final normalized = normalize(cleaned);
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final result = <String>[];
    for (final word in words) {
      final lowered = word.toLowerCase();
      final stemmed = stemSimple(lowered);
      final parts = stemmed.split(' ').where((w) => w.isNotEmpty).toList();
      result.addAll(parts);
    }

    return result;
  }

  static String normalize(String text) {
    if (text.isEmpty) return text;
    text = removeTashkeel(text);
    text = normalizeAlef(text);
    text = normalizeTaaMarbouta(text);
    text = normalizeYaaAlefMaqsoura(text);
    text = removeTatweel(text);
    text = normalizeDigits(text);
    text = removePunctuationAndSymbols(text);
    text = collapseSpaces(text);
    return text;
  }

  static String normalizeForSearch(String text) {
    if (text.isEmpty) return text;
    text = normalize(text);
    text = removeStopwords(text);
    text = collapseSpaces(text);
    return text;
  }

  static bool isArabic(String text) {
    if (text.isEmpty) return true;
    final length = text.length;
    int arabicCount = 0;
    final threshold = max(1, (0.6 * length).floor());

    for (int i = 0; i < length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0600 && code <= 0x06FF) {
        arabicCount++;
        if (arabicCount >= threshold) return true;
      }
    }

    return arabicCount >= threshold;
  }

  static bool isAdLike(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    final patterns = [
      'javascript:',
      'cookie',
      'subscribe now',
      'sign up',
      'follow us',
      'read more',
      'click here',
      'advertisement',
      'تبليغ',
      'اعلان',
      'مسجل',
      'تسجيل',
      'المزيد',
      'اقرأ المزيد',
      'شاركنا',
      'تابعنا',
    ];
    for (final pattern in patterns) {
      if (lower.contains(pattern)) return true;
    }
    return false;
  }

  static String detectLanguage(String text) {
    if (text.isEmpty) return 'unknown';
    int arabicChars = 0;
    int englishChars = 0;
    int frenchChars = 0;

    for (final char in text.runes) {
      if (char >= 0x0600 && char <= 0x06FF) {
        arabicChars++;
      } else if ((char >= 0x0041 && char <= 0x005A) || (char >= 0x0061 && char <= 0x007A)) {
        englishChars++;
      } else if (char >= 0x00C0 && char <= 0x00FF) {
        frenchChars++;
      }
    }

    if (arabicChars > englishChars && arabicChars > frenchChars) return 'ar';
    if (frenchChars > arabicChars && frenchChars > englishChars) return 'fr';
    if (englishChars > arabicChars && englishChars > frenchChars) return 'en';
    return 'mixed';
  }
}
