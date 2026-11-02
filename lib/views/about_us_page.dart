import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../widgets/custom_logo.dart';
import '../l10n/app_localizations.dart';

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  String _appVersion = 'v1.0.1';
  String _appName = 'Yalla News';

  late final WebViewController _webViewController;

  /// Verified publisher information (from the publisher / rejection notice).
  static const String _publisherName = 'Inoov Software Engineering';
  static const String _developerEmail = 'info@inoov.com';
  static const String _developerWebsite = 'https://apps.inoov.com/yallanews/';
  static const String _privacyPolicyUrl =
      'https://apps.inoov.com/yallanews/#privacy';
  static const String _featuresUrl =
      'https://apps.inoov.com/yallanews/#features';
  static const String _sourcesUrl = 'https://apps.inoov.com/yallanews/#sources';
  static const String _faqUrl = 'https://apps.inoov.com/yallanews/#faq';
  static const String _contactUrl = 'https://apps.inoov.com/yallanews/#contact';
  static const String _youtubeVideoUrl =
      'https://www.youtube.com/watch?v=rXAcW7tGOls';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    if (Platform.isAndroid || Platform.isIOS) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..loadRequest(
          Uri.parse('https://www.youtube.com/embed/rXAcW7tGOls?playsinline=1'),
        );
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = 'v${info.version}';
        _appName = info.appName.isNotEmpty ? info.appName : 'Yalla News';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = 'v1.0.1';
      });
    }
  }

  /// Open an https URL in the system browser, reporting failures gracefully.
  Future<void> _launchUrlExternal(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.parse(url);
    try {
      if (!await canLaunchUrl(uri)) {
        _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
        return;
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
      }
    } on Exception catch (_) {
      if (context.mounted) {
        _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
      }
    }
  }

  /// Open the device email client addressed to the publisher email.
  Future<void> _launchEmail(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri(scheme: 'mailto', path: _developerEmail);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('contactEmailNoClient')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } on Exception catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('contactEmailError')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _showLaunchFailure(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ─── Hero App Bar ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            stretch: true,
            backgroundColor: isDark
                ? theme.colorScheme.surfaceContainer
                : theme.colorScheme.surface,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            theme.colorScheme.surfaceContainer,
                            theme.colorScheme.surface,
                            theme.colorScheme.surfaceContainerHighest,
                          ]
                        : [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary,
                            theme.colorScheme.primaryContainer,
                          ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 90),
                      // App Logo
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/img/play_store_icon_512.png',
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Tagline
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: isDark ? 0.1 : 0.2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          l10n.translate('appTagline'),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onPrimary.withValues(
                                    alpha: 0.95,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Version badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _appVersion,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onPrimary.withValues(
                                    alpha: 0.9,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ─── Content ──────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── Publisher card ─────────────────────────────────────
                _SectionCard(
                  icon: Icons.business_rounded,
                  iconColor: theme.colorScheme.primary,
                  title: l10n.translate('aboutPublisher'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SvgPicture.asset(
                            'assets/img/inoov_logo.svg',
                            width: 130,
                            /*height: 74,*/
                            fit: BoxFit.contain,
                            semanticsLabel: 'Inoov Software Engineering',
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _publisherName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.translate('aboutPublisherDesc'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _PublisherContactRow(
                        icon: Icons.language_rounded,
                        label: l10n.translate('contactWebsite'),
                        value: _contactUrl,
                        onTap: () => _launchUrlExternal(context, _contactUrl),
                      ),
                      const SizedBox(height: 10),
                      _PublisherContactRow(
                        icon: Icons.email_rounded,
                        label: l10n.translate('contactEmail'),
                        value: _developerEmail,
                        onTap: () => _launchEmail(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── App promotion video ──────────────────────────────────
                _SectionCard(
                  icon: Icons.play_circle_fill_rounded,
                  iconColor: theme.colorScheme.primary,
                  title: l10n.translate('aboutVideo'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('aboutVideoDesc'),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (Platform.isAndroid || Platform.isIOS)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 200,
                            child: WebViewWidget(
                              controller: _webViewController,
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: () =>
                              _launchUrlExternal(context, _youtubeVideoUrl),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 56,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.translate('aboutVideoOpenExternal'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Mission Card ────────────────────────────────────────
                _SectionCard(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: theme.colorScheme.tertiary,
                  title: l10n.translate('aboutMission'),
                  child: Text(
                    l10n.translate('aboutMissionDesc'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      height: 1.7,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Aggregator statement (News & Magazines policy) ──────
                _SectionCard(
                  icon: Icons.source_rounded,
                  iconColor: theme.colorScheme.secondary,
                  title: l10n.translate('aboutAggregator'),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(
                        alpha: 0.08,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.translate('aboutAggregatorDesc'),
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              height: 1.7,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Source info ──────────────────────────────────────────
                _SectionCard(
                  icon: Icons.source_rounded,
                  iconColor: theme.colorScheme.secondary,
                  title: l10n.translate('aboutSources'),
                  child: _LegalTile(
                    icon: Icons.open_in_new_rounded,
                    title: l10n.translate('aboutSources'),
                    onTap: () => _launchUrlExternal(context, _sourcesUrl),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Features ─────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.dashboard_customize_rounded,
                  iconColor: theme.colorScheme.secondary,
                  title: l10n.translate('aboutFeatures'),
                  child: Column(
                    children: [
                      _FeatureRow(
                        icon: Icons.psychology_rounded,
                        color: theme.colorScheme.primary,
                        title: l10n.translate('aboutFeatureAi'),
                        subtitle: l10n.translate('aboutFeatureAiDesc'),
                      ),
                      _FeatureRow(
                        icon: Icons.language_rounded,
                        color: theme.colorScheme.secondary,
                        title: l10n.translate('aboutFeatureMultilang'),
                        subtitle: l10n.translate('aboutFeatureMultilangDesc'),
                      ),
                      _FeatureRow(
                        icon: Icons.offline_bolt_rounded,
                        color: theme.colorScheme.tertiary,
                        title: l10n.translate('aboutFeatureOffline'),
                        subtitle: l10n.translate('aboutFeatureOfflineDesc'),
                      ),
                      _FeatureRow(
                        icon: Icons.record_voice_over_rounded,
                        color: theme.colorScheme.error,
                        title: l10n.translate('aboutFeatureTts'),
                        subtitle: l10n.translate('aboutFeatureTtsDesc'),
                      ),
                      _FeatureRow(
                        icon: Icons.speed_rounded,
                        color: theme.colorScheme.outline,
                        title: l10n.translate('aboutFeatureEngine'),
                        subtitle: l10n.translate('aboutFeatureEngineDesc'),
                        isLast: true,
                      ),
                      const SizedBox(height: 8),
                      _LegalTile(
                        icon: Icons.open_in_new_rounded,
                        title: l10n.translate('aboutFeatures'),
                        onTap: () => _launchUrlExternal(context, _featuresUrl),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Developer ────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.code_rounded,
                  iconColor: theme.colorScheme.primary,
                  title: l10n.translate('aboutDeveloper'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primaryContainer,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'iN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.translate('aboutDeveloperName'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.translate('aboutDeveloperCompany'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.translate('aboutDeveloperDesc'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () =>
                            _launchUrlExternal(context, _developerWebsite),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.language_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _developerWebsite,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Legal disclaimer ─────────────────────────────────────
                _SectionCard(
                  icon: Icons.shield_outlined,
                  iconColor: theme.colorScheme.error,
                  title: l10n.translate('aboutDisclaimer'),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.translate('aboutDisclaimerDesc'),
                            style: GoogleFonts.outfit(
                              fontSize: 12.5,
                              height: 1.6,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Legal links ──────────────────────────────────────────
                _SectionCard(
                  icon: Icons.gavel_rounded,
                  iconColor: theme.colorScheme.outline,
                  title: l10n.translate('aboutLegal'),
                  child: Column(
                    children: [
                      _LegalTile(
                        icon: Icons.privacy_tip_outlined,
                        title: l10n.translate('privacyPolicy'),
                        onTap: () =>
                            _launchUrlExternal(context, _privacyPolicyUrl),
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      _LegalTile(
                        icon: Icons.article_outlined,
                        title: l10n.translate('terms'),
                        onTap: () => _showLegalSheet(
                          context,
                          title: l10n.translate('terms'),
                          icon: Icons.article_outlined,
                          sections: const [
                            _LegalSection(
                              heading:
                                  '1. إخلاء مسؤولية المطوّر التقني (INOOV)',
                              body:
                                  'شركة INOOV (Inoov Software Engineering) هي المطوّر التقني للأنظمة والبرمجيات فقط، ولا تتحمل أي مسؤولية قانونية أو مدنية أو أخلاقية عن أي محتوى إخباري أو مقالات أو وسائط أو تعليقات منشورة داخل التطبيق، حيث تعود كامل المسؤولية لمصادر الأخبار الأصلية والناشرين وأصحاب التعليقات.',
                            ),
                            _LegalSection(
                              heading: '2. شروط الاستخدام والخدمة',
                              body:
                                  'باستخدامك لتطبيق يلا نيوز، فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.',
                            ),
                            _LegalSection(
                              heading: '3. حقوق الملكية الفكرية للأخبار',
                              body:
                                  'جميع المقالات والمحتويات الإخبارية والصور المعروضة تعود ملكيتها الفكرية وحقوق النشر إلى مصادرها الأصلية، ويقوم التطبيق بتنسيقها وعرضها مع ذكر المصدر الأصلي.',
                            ),
                            _LegalSection(
                              heading: '4. الاستخدام المقبول',
                              body:
                                  'يُسمح باستخدام هذا التطبيق للأغراض الشخصية والإعلامية غير التجارية. يُمنع منعاً باتاً استغلال التطبيق في أي أنشطة تنتهك القوانين أو حقوق الآخرين.',
                            ),
                            _LegalSection(
                              heading: '5. التحديثات والتعديلات',
                              body:
                                  'يحتفظ فريق التطوير بالحق في تعديل هذه الشروط أو تحسين ميزات التطبيق في أي وقت لتحسين تجربة المستخدم.',
                            ),
                          ],
                        ),
                      ),
                      _LegalTile(
                        icon: Icons.help_outline_rounded,
                        title: l10n.translate('aboutFaq'),
                        onTap: () => _launchUrlExternal(context, _faqUrl),
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      _LegalTile(
                        icon: Icons.open_in_new_rounded,
                        title: l10n.translate('aboutOpenSource'),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: _appName,
                          applicationVersion: _appVersion,
                          applicationIcon: Icon(
                            Icons.newspaper_rounded,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Footer ───────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Text(
                        l10n.translate('aboutMadeWith'),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '© 2026 $_publisherName. ${l10n.translate("aboutAllRights")}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegalSheet(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<_LegalSection> sections,
  }) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Grab handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Sections list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, index) {
                    final section = sections[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.heading,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            section.body,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              height: 1.6,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  final String heading;
  final String body;

  const _LegalSection({required this.heading, required this.body});
}

// ─── Section Card Widget ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─── Feature Row Widget ───────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isLast;

  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Legal Tile Widget ────────────────────────────────────────────────────────

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _LegalTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Publisher contact row ────────────────────────────────────────────────────

class _PublisherContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PublisherContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
