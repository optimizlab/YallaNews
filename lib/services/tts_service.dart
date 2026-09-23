import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService instance = TTSService._();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  TTSService._() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ar-SA"); // Default to Arabic for YallaNews
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setStartHandler(() {
      _isPlaying = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isPlaying = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isPlaying = false;
    });
  }

  Future<List<dynamic>> getVoices() async {
    return await _flutterTts.getVoices;
  }

  Future<void> setVoice(Map<String, String> voice) async {
    await _flutterTts.setVoice(voice);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isPlaying = false;
  }
}
