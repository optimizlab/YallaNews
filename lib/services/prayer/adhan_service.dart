import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for playing embedded adhan (call to prayer) audio.
/// Users can choose their preferred muezzin from [muezzins].
class AdhanService {
  AdhanService._();
  static final AdhanService instance = AdhanService._();

  static const String _prefKey = 'adhan_muezzin';

  /// Map of muezzin key → Arabic display name
  static const Map<String, String> muezzins = {
    'makkah': 'مكة المكرمة (ماجد الحمذاني)',
    'afasy': 'مشاري راشد العفاسي',
    'qatami': 'ناصر القطامي',
    'imadi': 'أحمد العمادي',
    'madinah': 'المدينة المنورة',
    'egypt': 'مصر (أذان مصري)',
    'yemen': 'اليمن (أذان يمني)',
    'iraq': 'العراق (أذان عراقي)',
    'turkish': 'تركيا (أذان تركي)',
    'moroccan': 'المغرب (أذان مغربي)',
  };

  /// Map of muezzin key → asset path
  static const Map<String, String> assetPaths = {
    'makkah': 'audio/adhan/adhan_makkah.mp3',
    'afasy': 'audio/adhan/adhan_afasy.mp3',
    'qatami': 'audio/adhan/adhan_qatami.mp3',
    'imadi': 'audio/adhan/adhan_imadi.mp3',
    'madinah': 'audio/adhan/adhan_madinah.mp3',
    'egypt': 'audio/adhan/adhan_egypt.mp3',
    'yemen': 'audio/adhan/adhan_yemen.mp3',
    'iraq': 'audio/adhan/adhan_iraq.mp3',
    'turkish': 'audio/adhan/adhan_turkish.mp3',
    'moroccan': 'audio/adhan/adhan_moroccan.mp3',
  };

  /// Map of muezzin key → asset path (legacy alias).
  static const Map<String, String> _assetPaths = assetPaths;

  final AudioPlayer _player = AudioPlayer();
  String _selectedMuezzin = 'makkah';
  bool _initialized = false;

  String get selectedMuezzin => _selectedMuezzin;

  /// Emits the current player state so UI can show play/stop while audio plays.
  Stream<PlayerState> get playerState => _player.onPlayerStateChanged;

  /// Load saved muezzin preference. Must be called once at app start.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedMuezzin = prefs.getString(_prefKey) ?? 'makkah';
    } catch (e) {
      debugPrint('[AdhanService] init error: $e');
    }
  }

  /// Persist the user's muezzin choice.
  Future<void> setMuezzin(String key) async {
    if (!muezzins.containsKey(key)) return;
    _selectedMuezzin = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, key);
    } catch (e) {
      debugPrint('[AdhanService] setMuezzin error: $e');
    }
  }

  /// Play the adhan for the currently selected muezzin.
  Future<void> playAdhan() async {
    try {
      _player.stop();
      final path = _assetPaths[_selectedMuezzin] ?? _assetPaths['makkah']!;
      await _player.play(AssetSource(path));
    } catch (e) {
      debugPrint('[AdhanService] playAdhan error: $e');
    }
  }

  /// Play a preview for [muezzinKey] (used in settings).
  Future<void> previewMuezzin(String muezzinKey) async {
    try {
      _player.stop();
      final path = _assetPaths[muezzinKey] ?? _assetPaths['makkah']!;
      await _player.play(AssetSource(path));
    } catch (e) {
      debugPrint('[AdhanService] previewMuezzin error: $e');
    }
  }

  /// Stop any currently playing adhan.
  Future<void> stopAdhan() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AdhanService] stopAdhan error: $e');
    }
  }

  void dispose() {
    _player.dispose();
  }
}
