import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'l10n/app_localizations.dart';
import 'services/app_settings.dart';
import 'services/category_service.dart';
import 'views/welcome_page.dart';
import 'views/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
  }
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // try {
    //   await MobileAds.instance.initialize();
    // } on MissingPluginException catch (_) {
    // } catch (_) {}
  }
  await AppSettings.instance.loadSettings();
  await CategoryService.instance.loadCategories();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Widget? _initialPage;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
    _resolveInitialPage();
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _resolveInitialPage() async {
    final isFirstRun = await AppSettings.instance.isFirstRun();
    if (!mounted) return;
    setState(() {
      _initialPage = (!kIsWeb && isFirstRun) ? const WelcomePage() : const SplashPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final locale = settings.locale;
    final textDirection =
        (locale?.languageCode == 'ar') ? TextDirection.rtl : TextDirection.ltr;

    return MaterialApp(
      title: AppLocalizations(locale ?? const Locale('ar')).translate('appName'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEFEFEF),
          foregroundColor: Color(0xFF555555),
          elevation: 0,
        ),
        textTheme: GoogleFonts.outfitTextTheme().apply(
          bodyColor: const Color(0xFF333333),
          displayColor: const Color(0xFF222222),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8E8E8E),
          primary: const Color(0xFF333333),
          secondary: const Color(0xFF8E8E8E),
          surface: Colors.white,
          surfaceContainer: const Color(0xFFF4F5F7),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2A2A4A),
          foregroundColor: Color(0xFFE0E0E0),
          elevation: 0,
        ),
        textTheme: GoogleFonts.outfitTextTheme().apply(
          bodyColor: const Color(0xFFE0E0E0),
          displayColor: const Color(0xFFEEEEEE),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF90CAF9),
          primary: const Color(0xFF90CAF9),
          secondary: const Color(0xFF64B5F6),
          surface: const Color(0xFF2A2A4A),
          surfaceContainer: const Color(0xFF1A1A2E),
        ),
      ),
      themeMode: settings.themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
        Locale('fr'),
        Locale('tr'),
      ],
      navigatorObservers: <NavigatorObserver>[],
      builder: (context, child) {
        return Directionality(
          textDirection: textDirection,
          child: child!,
        );
      },
      home: _initialPage ?? const SplashPage(),
    );
  }
}
