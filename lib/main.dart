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
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A1A),
          elevation: 0,
        ),
        textTheme: GoogleFonts.outfitTextTheme().apply(
          bodyColor: const Color(0xFF1A1A1A),
          displayColor: const Color(0xFF1A1A1A),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC62828),
          primary: const Color(0xFFC62828),
          secondary: const Color(0xFF8E8E8E),
          surface: Colors.white,
          surfaceContainer: const Color(0xFFF4F5F7),
          onSurface: const Color(0xFF1A1A1A),
          onSurfaceVariant: const Color(0xFF555555),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Color(0xFFF8FAFC),
          elevation: 0,
        ),
        textTheme: GoogleFonts.outfitTextTheme().apply(
          bodyColor: const Color(0xFFF1F5F9),
          displayColor: const Color(0xFFF8FAFC),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF90CAF9),
          primary: const Color(0xFF90CAF9),
          secondary: const Color(0xFF64B5F6),
          surface: const Color(0xFF1E293B),
          surfaceContainer: const Color(0xFF16213E),
          onSurface: const Color(0xFFF1F5F9),
          onSurfaceVariant: const Color(0xFFCBD5E1),
          surfaceContainerHighest: const Color(0xFF334155),
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
