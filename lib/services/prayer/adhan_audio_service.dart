import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adhan_service.dart';

/// When a prayer time fires and [PrayerReminderConfig.adhanSound] is enabled,
/// this service plays the embedded adhan audio for ~30 seconds in a foreground
/// service so playback continues even when the app is closed or hidden.
///
/// On Android this is driven by a [MethodChannel] from the native
/// [AdhanAudioService] (see android/.../AdhanAudioService.kt). On iOS it runs
/// the audio player directly in the Dart isolate; on desktop it is a no-op.
class AdhanAudioService {
  AdhanAudioService._();
  static final AdhanAudioService instance = AdhanAudioService._();

  static const String _channel = 'inoov.app.yallanews/adhan_audio';
  static const String _methodStart = 'startAdhan';
  static const String _methodStop = 'stopAdhan';
  static const int _playDurationSeconds = 30;

  final AudioPlayer _player = AudioPlayer();
  Timer? _stopTimer;
  bool _started = false;

  /// Whether the adhan is currently playing.
  bool get isPlaying => _player.state == PlayerState.playing;

  /// Stream of player state changes so UI can toggle play/stop.
  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  /// Whether the platform supports background audio playback.
  bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  /// Initialize the service. Safe to call multiple times.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    if (Platform.isAndroid) {
      _setupMethodChannel();
    }
    _player.onPlayerComplete.listen((_) => _scheduleAutoStop());
  }

  void _setupMethodChannel() {
    MethodChannel(_channel).setMethodCallHandler((call) async {
      if (call.method == _methodStart) {
        final muezzin = call.arguments as String?;
        await playAdhan(muezzin: muezzin);
        return true;
      }
      if (call.method == _methodStop) {
        await stopAdhan();
        return true;
      }
      return false;
    });
  }

  /// Start playing the adhan for [muezzinKey] (falls back to the saved
  /// preference). Stops automatically after [_playDurationSeconds].
  Future<void> playAdhan({String? muezzin}) async {
    if (!isSupported) return;
    final key = muezzin ?? AdhanService.instance.selectedMuezzin;
    try {
      await _player.stop();
      final path = AdhanService.assetPaths[key] ?? AdhanService.assetPaths['makkah']!;
      await _player.play(AssetSource(path));
      _stopTimer?.cancel();
      _stopTimer = Timer(const Duration(seconds: _playDurationSeconds), () {
        unawaited(_player.stop());
      });
    } catch (e) {
      debugPrint('[AdhanAudioService] playAdhan error: $e');
    }
  }

  /// Stop any currently playing adhan and cancel the auto-stop timer.
  Future<void> stopAdhan() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AdhanAudioService] stopAdhan error: $e');
    }
  }

  /// Called when the adhan finishes on its own (audio ends before 30s).
  void _scheduleAutoStop() {
    _stopTimer?.cancel();
    _stopTimer = null;
  }

  /// Read the persisted adhan-enabled flag so the native side can decide
  /// whether to start the foreground service on boot.
  static Future<bool> isAdhanEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('prayer_adhan_sound') ?? false;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _stopTimer?.cancel();
    _player.dispose();
  }
}