import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yallanews/l10n/app_localizations.dart';
import 'package:yallanews/services/tiny_llm_service.dart';
import 'package:yallanews/services/yalla_engine_service.dart';
import 'package:yallanews/services/app_settings.dart';
import 'package:yallanews/services/category_service.dart';
import 'package:yallanews/services/ai_service.dart';
import 'package:yallanews/services/model_download_manager.dart';
import 'package:yallanews/ui/ai_model_download_dialog.dart';
import 'package:yallanews/widgets/custom_logo.dart';
import 'package:yallanews/arabic_news_processor.dart';
import 'home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final TinyLLMService _llm = TinyLLMService.instance;
  final AIService _aiService = AIService.instance;
  final ModelDownloadManager _downloadManager = ModelDownloadManager.instance;
  
  int? _downloadProgress;
  bool _isDownloading = false;
  String _status = 'initializing';
  bool _showedModelDialog = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    
    // Start background initialization
    _backgroundInit();
    
    // Show AI model download consent after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_showedModelDialog) {
        _showModelDownloadDialog();
      }
    });
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(engineService: YallaEngineService()),
        ),
      );
    }
  }
  
  Future<void> _backgroundInit() async {
    try {
      await AppSettings.instance.loadSettings();
      await CategoryService.instance.loadCategories();
      await _downloadManager.initialize();
    } catch (_) {}
  }

  Future<void> _showModelDownloadDialog() async {
    _showedModelDialog = true;
    
    // Check if AI is already enabled and model loaded
    if (_aiService.isReady) return;
    
    // Check if user already declined
    final prefs = await SharedPreferences.getInstance();
    final declined = prefs.getBool('ai_model_declined') ?? false;
    if (declined) return;
    
    // Check if model already downloaded
    final downloaded = await _downloadManager.isDownloaded(_aiService.currentModel);
    if (downloaded) {
      await _loadModel();
      return;
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AIModelDownloadDialog(
        model: _aiService.currentModel,
        onAccept: () async {
          await _loadModel();
        },
        onDecline: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('ai_model_declined', true);
        },
      ),
    );
  }

  Future<void> _loadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _status = 'preparing';
    });
    
    // Start background download
    final success = await _downloadManager.startDownload(_aiService.currentModel);
    
    if (!success) {
      setState(() {
        _isDownloading = false;
        _status = 'error';
      });
      return;
    }
    
    // Listen to progress
    final subscription = _downloadManager.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = progress.progress.round();
        _status = progress.status;
      });
    });
    
    // Wait for download to complete (with timeout)
    try {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 2));
        final status = await _downloadManager.getStatus(_aiService.currentModel);
        return !status.isDownloaded && status.status != 'error' && status.status != 'cancelled';
      });
    } catch (_) {}
    
    await subscription.cancel();
    
    final status = await _downloadManager.getStatus(_aiService.currentModel);
    if (status.isDownloaded) {
      // Load model into AI service
      final loaded = await _aiService.loadModel(_aiService.currentModel);
      if (loaded && mounted) {
        setState(() {
          _isDownloading = false;
          _status = 'ready';
        });
      }
    } else {
      setState(() {
        _isDownloading = false;
        _status = 'error';
      });
    }
  }

  static Future<int> _installModelIsolate(_) async {
    final llm = TinyLLMService.instance;
    final completer = Completer<int>();
    await llm.installModel(onProgress: (pct) {
      if (!completer.isCompleted) completer.complete(pct);
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 80),
            const YallaNewsLogo(size: 40, color: Colors.white70),
            const SizedBox(height: 32),
            Text(
              l10n.translate('appName'),
              style: GoogleFonts.outfit(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('appTagline'),
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF90CAF9),
              ),
            ),
            const SizedBox(height: 48),
            if (_isDownloading) ...[
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: (_downloadProgress ?? 0) / 100.0,
                  backgroundColor: const Color(0xFF2A2A4A),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${l10n.translate(_status)} (${_downloadProgress ?? 0}%)',
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  color: const Color(0xFF78909C),
                ),
              ),
            ] else
              Text(
                l10n.translate(_status),
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  color: const Color(0xFF78909C),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                'v1.0.0',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  color: const Color(0xFF5A5A7A),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
