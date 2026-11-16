import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news_model.dart';
import 'app_settings.dart';

class TTSService {
  static final TTSService instance = TTSService._();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  bool _stopRequested = false;
  bool _batchSpeaking = false;

  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  ValueListenable<bool> get playingNotifier => _playingNotifier;

  NewsModel? _currentArticle;
  NewsModel? get currentArticle => _currentArticle;

  final ValueNotifier<NewsModel?> _articleNotifier = ValueNotifier<NewsModel?>(null);
  ValueListenable<NewsModel?> get articleNotifier => _articleNotifier;

  final ValueNotifier<String?> _activeDetailPageNotifier = ValueNotifier<String?>(null);
  ValueListenable<String?> get activeDetailPageNotifier => _activeDetailPageNotifier;
  String? get activeDetailPageUrl => _activeDetailPageNotifier.value;

  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
  ValueListenable<double> get progressNotifier => _progressNotifier;

  void setActiveDetailPage(String? url) {
    _activeDetailPageNotifier.value = url;
  }

  String? _currentText;
  String? get currentText => _currentText;
  List<String> _currentSentences = [];
  int _currentSentenceIndex = 0;

  void setCurrentArticle(NewsModel? article, {String? text}) {
    _currentArticle = article;
    _articleNotifier.value = article;
    if (text != null && text.isNotEmpty) {
      _currentText = text;
      _currentSentences = _splitIntoSentences(text);
      _currentSentenceIndex = 0;
    } else if (article != null) {
      final t = buildArticleReadText(article);
      _currentText = t;
      _currentSentences = _splitIntoSentences(t);
      _currentSentenceIndex = 0;
    }
  }

  void clearCurrentArticle() {
    stop();
    _currentArticle = null;
    _currentText = null;
    _currentSentences = [];
    _currentSentenceIndex = 0;
    _articleNotifier.value = null;
  }

  VoidCallback? _onSpeakComplete;

  String? _selectedVoiceName;
  String? get selectedVoiceName => _selectedVoiceName;

  bool _newsMode = true;
  bool get newsMode => _newsMode;

  Process? _windowsTtsProcess;
  late final Future<void> _initialization;

  Future<void> get ready => _initialization;

  bool get _isWindows => Platform.isWindows;

  static const Map<String, String> _defaultTtsLocaleByLanguage = {
    'ar': 'ar-SA',
    'en': 'en-US',
    'fr': 'fr-FR',
    'tr': 'tr-TR',
  };

  static const Map<String, String> _defaultWindowsVoiceByLanguage = {
    'ar': 'Microsoft Maha',
    'en': 'Microsoft David',
    'fr': 'Microsoft Hortense',
    'tr': 'Microsoft David',
  };

  String _currentLanguageCode() => AppSettings.instance.locale?.languageCode ?? 'ar';

  String _defaultTtsLocale(String languageCode) =>
      _defaultTtsLocaleByLanguage[languageCode] ?? 'en-US';

  String? _lastLocaleCode;

  TTSService._() {
    _lastLocaleCode = _currentLanguageCode();
    _initialization = _initTts();
    AppSettings.instance.addListener(_onAppSettingsChanged);
  }

  void _setPlaying(bool value) {
    _isPlaying = value;
    _playingNotifier.value = value;
  }

  Future<void> _initTts() async {
    if (!_isWindows) {
      final languageCode = _currentLanguageCode();
      await _flutterTts.setLanguage(_defaultTtsLocale(languageCode));
      await _flutterTts.setSpeechRate(0.42);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.97);
      await _flutterTts.setSharedInstance(true);
      // Make speak() wait for each utterance to finish so sentences can be
      // sequenced reliably instead of all being queued at once.
      await _flutterTts.awaitSpeakCompletion(true);

      _flutterTts.setStartHandler(() {
        _setPlaying(true);
      });

      _flutterTts.setCompletionHandler(() {
        if (!_batchSpeaking) {
          _setPlaying(false);
        }
        final callback = _onSpeakComplete;
        _onSpeakComplete = null;
        if (!_batchSpeaking) {
          callback?.call();
        }
      });

      _flutterTts.setErrorHandler((msg) {
        _setPlaying(false);
        final callback = _onSpeakComplete;
        _onSpeakComplete = null;
        callback?.call();
      });
    }

    await _restoreSavedVoice();
  }

  void _onAppSettingsChanged() {
    final code = AppSettings.instance.locale?.languageCode;
    if (code == _lastLocaleCode) return;
    _lastLocaleCode = code;
    if (_selectedVoiceName == null && !_isWindows) {
      unawaited(_selectBestAvailableVoice(languageCode: code));
    }
  }

  Future<void> _restoreSavedVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('tts_voice_name');
      final savedLocale = prefs.getString('tts_voice_locale');
      if (savedName != null && savedLocale != null) {
        _selectedVoiceName = savedName;
        if (!_isWindows) {
          await _flutterTts.setVoice({'name': savedName, 'locale': savedLocale});
        }
      } else {
        await _selectBestAvailableVoice(languageCode: _currentLanguageCode());
      }
    } catch (_) {
      await _selectBestAvailableVoice(languageCode: _currentLanguageCode());
    }
  }

  Future<void> _selectBestAvailableVoice({String? languageCode}) async {
    await _initialization;
    if (_isWindows) return;
    languageCode ??= _currentLanguageCode();
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return;

      final List<Map<String, dynamic>> voiceList = voices.cast<Map<String, dynamic>>();

      final target = languageCode.toLowerCase();
      Map<String, dynamic>? best;
      for (final v in voiceList) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final locale = (v['locale'] ?? '').toString();
        final isMatchLanguage = locale.toLowerCase().startsWith(target);
        final isLocal = name.contains('local') || name.contains('high') || name.contains('enhanced');

        if (isMatchLanguage && isLocal) {
          best = v;
          break;
        }
        if (isMatchLanguage && best == null) {
          best = v;
        }
      }

      if (best != null) {
        final voiceMap = best.cast<String, String>();
        final voiceName = voiceMap['name'] ?? '';
        await _flutterTts.setVoice(voiceMap);
        _selectedVoiceName = voiceName;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('tts_voice_name', voiceName);
          await prefs.setString('tts_voice_locale', voiceMap['locale'] ?? '');
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<List<dynamic>> getVoices() async {
    await _initialization;
    if (_isWindows) return _windowsVoices();
    return await _flutterTts.getVoices;
  }

  List<dynamic> _windowsVoices() {
    return const [
      {'name': 'Microsoft David', 'locale': 'en-US'},
      {'name': 'Microsoft Zira', 'locale': 'en-US'},
      {'name': 'Microsoft Hazel', 'locale': 'en-GB'},
      {'name': 'Microsoft Hedda', 'locale': 'de-DE'},
      {'name': 'Microsoft Hortense', 'locale': 'fr-FR'},
      {'name': 'Microsoft Helena', 'locale': 'es-ES'},
      {'name': 'Microsoft Laura', 'locale': 'it-IT'},
      {'name': 'Microsoft Maria', 'locale': 'es-MX'},
      {'name': 'Microsoft Ayumi', 'locale': 'ja-JP'},
      {'name': 'Microsoft Heami', 'locale': 'ko-KR'},
      {'name': 'Microsoft Huihui', 'locale': 'zh-CN'},
      {'name': 'Microsoft Yaakov', 'locale': 'he-IL'},
      {'name': 'Microsoft Maha', 'locale': 'ar-SA'},
      {'name': 'Microsoft Naayf', 'locale': 'ar-SA'},
    ];
  }

  Future<List<VoiceInfo>> getFormattedVoices() async {
    if (_isWindows) {
      final raw = _windowsVoices();
      final List<VoiceInfo> voices = [];
      for (final voice in raw) {
        final v = Map<String, String>.from(voice.cast<String, dynamic>());
        final name = v['name'] ?? '';
        final locale = v['locale'] ?? '';
        if (name.isEmpty) continue;
        voices.add(VoiceInfo(
          name: name,
          locale: locale,
          displayName: _humanFriendlyName(name, locale),
          languageLabel: _localeToLanguage(locale),
          flagEmoji: _localeToFlag(locale),
        ));
      }
      voices.sort((a, b) {
        final aOrder = _localeSortOrder(a.locale);
        final bOrder = _localeSortOrder(b.locale);
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
        return a.displayName.compareTo(b.displayName);
      });
      return voices;
    }

    final raw = await _flutterTts.getVoices;
    if (raw == null) return [];

    final List<VoiceInfo> voices = [];
    for (final voice in raw) {
      final v = Map<String, String>.from(voice);
      final name = v['name'] ?? '';
      final locale = v['locale'] ?? '';
      if (name.isEmpty) continue;

      voices.add(VoiceInfo(
        name: name,
        locale: locale,
        displayName: _humanFriendlyName(name, locale),
        languageLabel: _localeToLanguage(locale),
        flagEmoji: _localeToFlag(locale),
      ));
    }

    voices.sort((a, b) {
      final aOrder = _localeSortOrder(a.locale);
      final bOrder = _localeSortOrder(b.locale);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.displayName.compareTo(b.displayName);
    });

    return voices;
  }

  Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoiceName = voice['name'];
    if (_isWindows) return;
    await _flutterTts.setVoice(voice);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_voice_name', voice['name'] ?? '');
      await prefs.setString('tts_voice_locale', voice['locale'] ?? '');
    } catch (_) {}
  }

  Future<void> setNewsMode(bool value) async {
    _newsMode = value;
  }

  Future<void> setSpeechRate(double rate) async {
    if (_isWindows) return;
    await _flutterTts.setSpeechRate(rate);
  }

  static String buildArticleReadText(NewsModel article) {
    String stripHtml(String html) {
      return html
          .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</(p|div|h[1-6]|li)>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final title = stripHtml(article.title).trim();
    final summary = stripHtml(article.summary).trim();
    final content = stripHtml(article.content).trim();

    final parts = <String>[];
    if (title.isNotEmpty) parts.add(title);
    if (summary.isNotEmpty && summary != title) parts.add(summary);
    if (content.isNotEmpty && content != summary && content != title) {
      parts.add(content);
    }

    return parts.join('. ');
  }

  Future<void> speak(String text, {VoidCallback? onCompleted}) async {
    await _initialization;
    if (text.isEmpty) {
      onCompleted?.call();
      return;
    }
    _onSpeakComplete = onCompleted;
    _currentText = text;
    _currentSentences = _splitIntoSentences(text);
    _currentSentenceIndex = 0;

    if (_isWindows) {
      if (_newsMode) {
        await _speakNewsStyleWindows(_currentSentences, 0);
      } else {
        await _speakWindows(text);
      }
      return;
    }

    if (_newsMode) {
      await _speakNewsStyle(_currentSentences, 0);
    } else {
      _setPlaying(true);
      await _flutterTts.speak(text);
    }
  }

  Future<void> pause() async {
    await stop(keepArticle: true);
  }

  Future<void> resume() async {
    await _initialization;
    _stopRequested = false;
    if (_currentSentences.isEmpty) {
      if (_currentArticle != null) {
        final text = buildArticleReadText(_currentArticle!);
        _currentText = text;
        _currentSentences = _splitIntoSentences(text);
        _currentSentenceIndex = 0;
      } else {
        return;
      }
    }
    if (_currentSentenceIndex >= _currentSentences.length) {
      _currentSentenceIndex = 0;
    }
    _setPlaying(true);
    if (_isWindows) {
      await _speakNewsStyleWindows(_currentSentences, _currentSentenceIndex);
    } else {
      await _speakNewsStyle(_currentSentences, _currentSentenceIndex);
    }
  }

  Future<void> togglePlayback() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> _speakSentenceWindows(String text) async {
    final escaped = _escapePowerShell(text);
    final voice = _selectedVoiceName ?? _defaultWindowsVoiceByLanguage[_currentLanguageCode()] ?? 'Microsoft David';
    final command =
        "Add-Type -AssemblyName System.Speech; "
        "\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        "\$s.SelectVoice('$voice'); "
        "\$s.Speak('$escaped'); "
        "\$s.Dispose()";
    try {
      final proc = await Process.start(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      );
      _windowsTtsProcess = proc;
      await proc.exitCode;
      _windowsTtsProcess = null;
    } catch (_) {}
  }

  Future<void> _speakWindows(String text) async {
    _setPlaying(true);
    await _speakSentenceWindows(text);
    _setPlaying(false);
    _onSpeakComplete?.call();
    _onSpeakComplete = null;
  }

  Future<void> _speakNewsStyleWindows(List<String> sentences, int startIndex) async {
    _batchSpeaking = true;
    _stopRequested = false;
    _setPlaying(true);
    try {
      for (int i = startIndex; i < sentences.length; i++) {
        if (_stopRequested) break;
        _currentSentenceIndex = i;
        _progressNotifier.value = sentences.length > 1 ? i / (sentences.length - 1) : 1.0;
        final s = sentences[i].trim();
        if (s.isEmpty) continue;
        await _speakSentenceWindows(s);
        if (i < sentences.length - 1 && !_stopRequested) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      _batchSpeaking = false;
      if (!_stopRequested && _currentSentenceIndex >= sentences.length - 1) {
        _currentSentenceIndex = 0;
        _progressNotifier.value = 0.0;
        _setPlaying(false);
        final cb = _onSpeakComplete;
        _onSpeakComplete = null;
        cb?.call();
      } else if (_stopRequested) {
        _setPlaying(false);
      }
    }
  }

  String _escapePowerShell(String text) {
    return text.replaceAll("'", "''").replaceAll('\n', ' ').replaceAll('\r', '');
  }

  Future<void> _speakNewsStyle(List<String> sentences, int startIndex) async {
    _batchSpeaking = true;
    _stopRequested = false;
    _setPlaying(true);
    try {
      for (int i = startIndex; i < sentences.length; i++) {
        if (_stopRequested) break;
        _currentSentenceIndex = i;
        _progressNotifier.value = sentences.length > 1 ? i / (sentences.length - 1) : 1.0;
        final s = sentences[i].trim();
        if (s.isEmpty) continue;
        await _flutterTts.speak(s);
        if (i < sentences.length - 1 && !_stopRequested) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      _batchSpeaking = false;
      if (!_stopRequested && _currentSentenceIndex >= sentences.length - 1) {
        _currentSentenceIndex = 0;
        _progressNotifier.value = 0.0;
        _setPlaying(false);
        final cb = _onSpeakComplete;
        _onSpeakComplete = null;
        cb?.call();
      } else if (_stopRequested) {
        _setPlaying(false);
      }
    }
  }

  List<String> _splitIntoSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?؟؛])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> stop({bool keepArticle = false}) async {
    _onSpeakComplete = null;
    _stopRequested = true;
    _setPlaying(false);
    if (_isWindows) {
      try {
        _windowsTtsProcess?.kill();
        _windowsTtsProcess = null;
      } catch (_) {}
      Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Add-Type -AssemblyName System.Speech; "
        "(New-Object System.Speech.Synthesis.SpeechSynthesizer).SpeakAsyncCancelAll();"
      ]);
    } else {
      await _flutterTts.stop();
    }
    if (!keepArticle) {
      _currentSentenceIndex = 0;
    }
  }

  static String _humanFriendlyName(String rawName, String locale) {
    String cleaned = rawName;
    for (final prefix in ['com.google.android.tts:', 'com.samsung.SMT:']) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }
    final isLocal = cleaned.contains('local') || cleaned.contains('high') || cleaned.contains('enhanced');
    final quality = isLocal ? '📱' : '';
    final lang = _localeToLanguage(locale);
    final country = locale.contains('-') ? locale.split('-').last.toUpperCase() : '';
    final suffix = isLocal ? 'محلي / Local' : '';
    if (country.isNotEmpty) {
      return '$lang ($country) $quality${suffix.isNotEmpty ? ' · $suffix' : ''}';
    }
    return '$lang $quality${suffix.isNotEmpty ? ' · $suffix' : ''}';
  }

  static String _localeToLanguage(String locale) {
    final code = locale.split('-').first.split('_').first.toLowerCase();
    switch (code) {
      case 'ar': return 'العربية';
      case 'fr': return 'Français';
      case 'en': return 'English';
      case 'tr': return 'Türkçe';
      case 'es': return 'Español';
      case 'de': return 'Deutsch';
      case 'it': return 'Italiano';
      case 'pt': return 'Português';
      case 'ja': return '日本語';
      case 'ko': return '한국어';
      case 'zh': return '中文';
      case 'ru': return 'Русский';
      case 'hi': return 'हिन्दी';
      case 'ur': return 'اردو';
      default: return code.toUpperCase();
    }
  }

  static String _localeToFlag(String locale) {
    final parts = locale.split('-');
    final country = parts.length > 1 ? parts.last.toUpperCase() : parts.first.toUpperCase();
    switch (country) {
      case 'SA': return '🇸🇦';
      case 'EG': return '🇪🇬';
      case 'MA': return '🇲🇦';
      case 'DZ': return '🇩🇿';
      case 'TN': return '🇹🇳';
      case 'AE': return '🇦🇪';
      case 'FR': return '🇫🇷';
      case 'US': return '🇺🇸';
      case 'GB': return '🇬🇧';
      case 'TR': return '🇹🇷';
      case 'AR': return 'العربية';
      case 'EN': return '🇬🇧';
      default: return '🌐';
    }
  }

  static int _localeSortOrder(String locale) {
    final code = locale.split('-').first.split('_').first.toLowerCase();
    switch (code) {
      case 'ar': return 0;
      case 'fr': return 1;
      case 'en': return 2;
      case 'tr': return 3;
      default: return 10;
    }
  }
}

class VoiceInfo {
  final String name;
  final String locale;
  final String displayName;
  final String languageLabel;
  final String flagEmoji;

  const VoiceInfo({
    required this.name,
    required this.locale,
    required this.displayName,
    required this.languageLabel,
    required this.flagEmoji,
  });

  Map<String, String> toVoiceMap() => {'name': name, 'locale': locale};
}
