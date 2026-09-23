

class ArabicTextNormalizer {
  // Arabic diacritics (tashkeel) to remove
  static final tashkeel = RegExp(r'[\u064B-\u065F\u0670\u0640]');

  // Alef variants to normalize to plain alef (ا)
  static final alefVariants = RegExp(r'[أإآ]');

  // Taa marbouta to normalize (ة -> ه)
  static final taaMarbouta = RegExp(r'ة');

  // Yaa/alef maqsoura to normalize (ى -> ي)
  static final yaaAlefMaqsoura = RegExp(r'ى');

  // Tatweel (kashida) to remove
  static final tatweel = RegExp(r'\u0640');

  // Arabic-Indic digits to normalize to Western Arabic numerals
  static final arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  /// Remove tashkeel (diacritics) from Arabic text
  static String removeTashkeel(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(tashkeel, '');
  }

  /// Normalize alef variants: أ إ آ -> ا
  static String normalizeAlef(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(alefVariants, 'ا');
  }

  /// Normalize taa marbouta: ة -> ه
  static String normalizeTaaMarbouta(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(taaMarbouta, 'ه');
  }

  /// Normalize yaa/alef maqsoura: ى -> ي
  static String normalizeYaaAlefMaqsoura(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(yaaAlefMaqsoura, 'ي');
  }

  /// Remove tatweel (kashida)
  static String removeTatweel(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(tatweel, '');
  }

  /// Full normalization pipeline
  static String normalize(String text) {
    if (text.isEmpty) return text;
    text = removeTashkeel(text);
    text = normalizeAlef(text);
    text = normalizeYaaAlefMaqsoura(text);
    text = removeTatweel(text);
    // Normalize multiple spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  /// Detect and filter out ad/comment/navigation text
  static bool isAdLike(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    final patterns = [
      r'javascript:',
      r'cookie',
      r'subscribe now',
      r'sign up',
      r'follow us',
      r'read more',
      r'click here',
      r'advertisement',
      r'تبليغ',
      r'اعلان',
      r'مسجل',
      r'تسجيل',
      r'المزيد',
      r'اقرأ المزيد',
      r'شاركنا',
      r'تابعنا',
    ];
    for (final pattern in patterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Detect language of text
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
