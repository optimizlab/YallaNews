import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'l10n/app_localizations.dart';
import 'services/analytics_service.dart';
import 'services/app_settings.dart';
import 'services/category_service.dart';
import 'services/server_api_service.dart';
import 'services/reward_ad_service.dart';
import 'services/native_ad_service.dart';
import 'views/welcome_page.dart';
import 'views/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  SystemChrome.setSystemUIOverlayStyle(
    _systemUiStyle(
      navigationBarColor: brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF4F5F7),
      statusBarColor: brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white,
      navigationBarIconColor: brightness == Brightness.dark
          ? const Color(0xFFF8FAFC)
          : const Color(0xFF1A1A1A),
      statusBarIconColor: brightness == Brightness.dark
          ? const Color(0xFFF8FAFC)
          : const Color(0xFF1A1A1A),
    ),
  );
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
  }
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await MobileAds.instance.initialize();
      await RewardAdService.instance.initialize();
      // Native ads are preloaded into a pool so the feed never waits on one.
      await NativeAdService.instance.initialize();
      NativeAdService.instance.ensurePreloaded();
    } on MissingPluginException catch (_) {
    } catch (_) {}
  }
  runApp(const MyApp());
}

/// Keeps Android's system navigation controls readable against the active
/// application theme. The contrast flag prevents Android 10+ from replacing
/// the requested navigation bar treatment with its own scrim.
SystemUiOverlayStyle _systemUiStyle({
  required Color navigationBarColor,
  required Color statusBarColor,
  required Color navigationBarIconColor,
  required Color statusBarIconColor,
}) {
  return SystemUiOverlayStyle(
    systemNavigationBarColor: navigationBarColor,
    systemNavigationBarDividerColor: navigationBarColor,
    systemNavigationBarIconBrightness: ThemeData.estimateBrightnessForColor(
      navigationBarIconColor,
    ),
    systemNavigationBarContrastEnforced: false,
    statusBarColor: statusBarColor,
    statusBarIconBrightness: ThemeData.estimateBrightnessForColor(
      statusBarIconColor,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Widget? _initialPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSettings.instance.addListener(_onSettingsChanged);
    ServerApiService.startHeartbeat();
    // Real user-behavior analytics (local queue + batched delivery)
    AnalyticsService.instance.init();
    _resolveInitialPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ServerApiService.stopHeartbeat();
    AnalyticsService.instance.dispose();
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ship queued behavior events before the app is killed in background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      AnalyticsService.instance.flush();
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
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
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A1A),
          systemOverlayStyle: _systemUiStyle(
            navigationBarColor: const Color(0xFFF4F5F7),
            statusBarColor: Colors.white,
            navigationBarIconColor: const Color(0xFF1A1A1A),
            statusBarIconColor: const Color(0xFF1A1A1A),
          ),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1A1A1A)),
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
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFFC62828),
          unselectedItemColor: Color(0xFF555555),
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Color(0xFFF8FAFC),
          systemOverlayStyle: _systemUiStyle(
            navigationBarColor: const Color(0xFF0F172A),
            statusBarColor: const Color(0xFF1E293B),
            navigationBarIconColor: const Color(0xFFF8FAFC),
            statusBarIconColor: const Color(0xFFF8FAFC),
          ),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: const IconThemeData(color: Color(0xFFF8FAFC)),
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
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E293B),
          selectedItemColor: Color(0xFF90CAF9),
          unselectedItemColor: Color(0xFFCBD5E1),
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1E293B),
        ),
      ),
      themeMode: settings.themeMode,
      locale: locale,
      builder: (context, child) {
        final theme = Theme.of(context);
        final appBarColor =
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
        final iconColor =
            theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemUiStyle(
            navigationBarColor: theme.scaffoldBackgroundColor,
            statusBarColor: appBarColor,
            navigationBarIconColor: iconColor,
            statusBarIconColor: iconColor,
          ),
          child: Directionality(
            textDirection: textDirection,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
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
      home: _initialPage ?? const SplashPage(),
    );
  }
}
