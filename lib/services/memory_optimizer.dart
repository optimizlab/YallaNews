import 'dart:io';
import 'package:flutter/foundation.dart';

class MemoryOptimizer {
  static bool _isSmallMemory = false;
  static int _memoryMb = 0;

  static Future<void> init() async {
    if (kIsWeb) {
      _isSmallMemory = true;
      return;
    }
    try {
      final info = ProcessInfo.currentRss;
      _memoryMb = info ~/ 1024 ~/ 1024;
      // RSS at app startup is typically 80-150 MB even on high-end devices.
      // Only flag small-memory if usage is genuinely tiny (< 80 MB),
      // which would indicate a severely constrained environment.
      _isSmallMemory = _memoryMb > 0 && _memoryMb < 80;
    } catch (_) {
      _isSmallMemory = false;
    }
  }

  static bool get isSmallMemory => _isSmallMemory;
  static int get memoryMb => _memoryMb;

  static int get maxArticlesToLoad => _isSmallMemory ? 20 : 25;
  static int get maxCachedArticles => _isSmallMemory ? 50 : 100;
  static int get blendThrottleMs => _isSmallMemory ? 8000 : 6000;
  static int get crawlerThrottleMs => _isSmallMemory ? 5000 : 4000;
  static int get maxConcurrentOps => _isSmallMemory ? 1 : 3;
  static int get maxImagesPerArticle => _isSmallMemory ? 3 : 6;
  static int get maxWidgetsPerArticle => _isSmallMemory ? 40 : 80;
  static bool get enableLowResImages => _isSmallMemory;

  static Future<int> getCurrentMemoryMb() async {
    try {
      final info = ProcessInfo.currentRss;
      return info ~/ 1024 ~/ 1024;
    } catch (_) {
      return _memoryMb;
    }
  }

  static Future<bool> isMemoryCritical() async {
    final mb = await getCurrentMemoryMb();
    return mb >= 600;
  }

  static Future<bool> isMemoryWarning() async {
    final mb = await getCurrentMemoryMb();
    return mb >= 400;
  }
}
