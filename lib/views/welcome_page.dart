import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/user_service.dart';
import 'splash_page.dart';
import 'auth/login_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _slides = [
    {
      'icon': Icons.language_rounded,
      'titleKey': 'welcomeLanguageTitle',
      'descKey': 'welcomeLanguageDesc',
      'color': const Color(0xFF1565C0),
    },
    {
      'icon': Icons.newspaper_rounded,
      'titleKey': 'welcomeNewsTitle',
      'descKey': 'welcomeNewsDesc',
      'color': const Color(0xFFC62828),
    },
    {
      'icon': Icons.wifi_rounded,
      'titleKey': 'welcomeBackgroundTitle',
      'descKey': 'welcomeBackgroundDesc',
      'color': const Color(0xFF2E7D32),
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _continueAsGuest() async {
    await AppSettings.instance.completeFirstRun();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SplashPage()),
      );
    }
  }

  Future<void> _showAuthOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(context).translate('connect'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _authenticate();
                  },
                  icon: const Icon(Icons.email_rounded, color: Colors.white),
                  label: Text(AppLocalizations.of(context).translate('email'), style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ).copyWith(elevation: WidgetStateProperty.all(0)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _authenticateWithPhone();
                  },
                  icon: const Icon(Icons.phone_rounded, color: Colors.white),
                  label: Text(AppLocalizations.of(context).translate('phone'), style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ).copyWith(elevation: WidgetStateProperty.all(0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await AppSettings.instance.completeFirstRun();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashPage()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticateWithPhone() async {
    setState(() => _isLoading = true);
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await AppSettings.instance.completeFirstRun();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashPage()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: (slide['color'] as Color).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            slide['icon'] as IconData,
                            size: 56,
                            color: slide['color'] as Color,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          l10n.translate(slide['titleKey'] as String),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.translate(slide['descKey'] as String),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            color: const Color(0xFFB0BEC5),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(_slides.length, (index) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 8),
                            width: _currentPage == index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF424874),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _showAuthOptions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          _currentPage == _slides.length - 1
                              ? l10n.translate('getStarted')
                              : l10n.translate('next'),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _continueAsGuest,
                    child: Text(l10n.translate('skip'), style: const TextStyle(color: Color(0xFFB0BEC5))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
