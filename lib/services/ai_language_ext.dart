// Language extension for YallaLanguage enum
// Maps between YallaLanguage enum and display names/codes

import 'package:yallanews/services/ai_ffi.dart';

extension YallaLanguageExt on YallaLanguage {
  static YallaLanguage fromString(String code) {
    switch (code.toLowerCase()) {
      case 'ar':
      case 'arabic':
        return YallaLanguage.arabic;
      case 'fr':
      case 'french':
        return YallaLanguage.french;
      case 'en':
      case 'english':
      default:
        return YallaLanguage.english;
    }
  }

  String get code {
    switch (this) {
      case YallaLanguage.arabic:
        return 'ar';
      case YallaLanguage.french:
        return 'fr';
      case YallaLanguage.english:
      default:
        return 'en';
    }
  }

  String get displayName {
    switch (this) {
      case YallaLanguage.arabic:
        return 'Arabic';
      case YallaLanguage.french:
        return 'French';
      case YallaLanguage.english:
      default:
        return 'English';
    }
  }

  String get nativeName {
    switch (this) {
      case YallaLanguage.arabic:
        return 'العربية';
      case YallaLanguage.french:
        return 'Français';
      case YallaLanguage.english:
      default:
        return 'English';
    }
  }

  String get flag {
    switch (this) {
      case YallaLanguage.arabic:
        return '🇸🇦'; // Saudi Arabia as representative
      case YallaLanguage.french:
        return '🇫🇷';
      case YallaLanguage.english:
      default:
        return '🇺🇸';
    }
  }
}