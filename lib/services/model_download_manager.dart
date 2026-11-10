// WorkManager background task for AI model downloads
// Handles background model downloading with progress tracking

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yallanews/services/ai_service.dart';

/// WorkManager task name for model download
const String kModelDownloadTask = 'com.yallanews.ai_model_download';

/// WorkManager callback dispatcher - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kModelDownloadTask) {
      final modelId = inputData?['modelId'] as String?;
      if (modelId != null) {
        await _downloadModelInBackground(modelId);
      }
      return true;
    }
    return false;
  });
}

/// Download model in background isolate
Future<void> _downloadModelInBackground(String modelId) async {
  try {
    // Update progress in shared preferences
    await _updateProgress(modelId, 0.0, 'preparing');
    
    // Simulate download (real implementation would use AI service)
    // Note: Actual download requires C callback trampoline which isn't implemented yet
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(seconds: 2));
      await _updateProgress(modelId, i.toDouble(), i < 90 ? 'downloading' : 'verifying');
    }
    
    // Mark as complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('model_${modelId}_downloaded', true);
    await prefs.setString('model_${modelId}_status', 'complete');
    
  } catch (e) {
    await _updateProgress(modelId, 0.0, 'error');
    debugPrint('Background model download failed: $e');
  }
}

/// Update download progress in shared preferences
Future<void> _updateProgress(String modelId, double progress, String status) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('model_${modelId}_progress', progress);
  await prefs.setString('model_${modelId}_status', status);
}

/// Model Download Manager - orchestrates WorkManager tasks
class ModelDownloadManager {
  static ModelDownloadManager? _instance;
  static ModelDownloadManager get instance => _instance ??= ModelDownloadManager._();
  ModelDownloadManager._();

  bool _initialized = false;
  StreamController<ModelDownloadProgress>? _progressController;

  /// Initialize WorkManager
  Future<void> initialize() async {
    if (_initialized) return;
    
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    _progressController = StreamController<ModelDownloadProgress>.broadcast();
    _initialized = true;
  }

  /// Start background model download
  Future<bool> startDownload(AIModelType model, {
    bool wifiOnly = true,
    bool autoDownload = false,
  }) async {
    if (!_initialized) await initialize();

    // Check if already downloading
    final prefs = await SharedPreferences.getInstance();
    final currentStatus = prefs.getString('model_${model.id}_status') ?? 'none';
    if (currentStatus == 'downloading' || currentStatus == 'preparing') {
      return false;
    }

    // Check if already downloaded
    final alreadyDownloaded = prefs.getBool('model_${model.id}_downloaded') ?? false;
    if (alreadyDownloaded) {
      return true;
    }

    // Schedule WorkManager task
    final constraints = Constraints(
      networkType: wifiOnly ? NetworkType.unmetered : NetworkType.metered,
      requiresBatteryNotLow: true,
      requiresCharging: false,
      requiresDeviceIdle: false,
    );

    try {
      await Workmanager().registerPeriodicTask(
        'model_download_${model.id}',
        kModelDownloadTask,
        inputData: {'modelId': model.id},
        constraints: constraints,
        frequency: const Duration(hours: 1), // Check hourly
        initialDelay: const Duration(seconds: 5),
      );
      
      // Save preferences
      await prefs.setBool('model_${model.id}_wifi_only', wifiOnly);
      await prefs.setBool('model_${model.id}_auto_download', autoDownload);
      await _updateProgress(model.id, 0.0, 'scheduled');
      
      return true;
    } catch (e) {
      debugPrint('Failed to schedule model download: $e');
      return false;
    }
  }

  /// Cancel background download
  Future<void> cancelDownload(AIModelType model) async {
    await Workmanager().cancelByUniqueName('model_download_${model.id}');
    await _updateProgress(model.id, 0.0, 'cancelled');
  }

  /// Get download progress stream
  Stream<ModelDownloadProgress> get progressStream {
    if (_progressController == null) {
      _progressController = StreamController<ModelDownloadProgress>.broadcast();
    }
    
    // Also listen to SharedPreferences changes
    _listenToPrefs();
    
    return _progressController!.stream;
  }

  void _listenToPrefs() {
    // Periodic polling of SharedPreferences for progress updates
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_initialized) {
        timer.cancel();
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      for (final model in AIModelType.values) {
        final progress = prefs.getDouble('model_${model.id}_progress') ?? 0.0;
        final status = prefs.getString('model_${model.id}_status') ?? 'none';
        
        if (status == 'downloading' || status == 'preparing' || status == 'verifying') {
          _progressController?.add(ModelDownloadProgress(
            modelId: model.id,
            progress: progress,
            status: status,
          ));
        }
      }
    });
  }

  /// Check if model is downloaded
  Future<bool> isDownloaded(AIModelType model) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('model_${model.id}_downloaded') ?? false;
  }

  /// Get current download status
  Future<ModelDownloadStatus> getStatus(AIModelType model) async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('model_${model.id}_status') ?? 'none';
    final progress = prefs.getDouble('model_${model.id}_progress') ?? 0.0;
    final downloaded = prefs.getBool('model_${model.id}_downloaded') ?? false;
    
    return ModelDownloadStatus(
      modelId: model.id,
      status: status,
      progress: progress,
      isDownloaded: downloaded,
    );
  }

  void dispose() {
    _progressController?.close();
    _progressController = null;
    _initialized = false;
  }
}

/// Progress data for UI updates
class ModelDownloadProgress {
  final String modelId;
  final double progress;
  final String status;

  ModelDownloadProgress({
    required this.modelId,
    required this.progress,
    required this.status,
  });
}

/// Download status snapshot
class ModelDownloadStatus {
  final String modelId;
  final String status;
  final double progress;
  final bool isDownloaded;

  ModelDownloadStatus({
    required this.modelId,
    required this.status,
    required this.progress,
    required this.isDownloaded,
  });
}