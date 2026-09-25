import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../services/tiny_llm_service.dart';
import '../services/yalla_engine_service.dart';
import '../services/app_settings.dart';
import '../services/category_service.dart';
import '../widgets/custom_logo.dart';
import '../arabic_news_processor.dart';
import 'home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final TinyLLMService _llm = TinyLLMService.instance;
  int? _downloadProgress;
  bool _isDownloading = false;
  String _status = 'initializing';

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
    } catch (_) {}
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
      body: Center(
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
    );
  }
}
