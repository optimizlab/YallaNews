import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// Contact screen for YallaNews.
///
/// Displays the verified publisher contact information only:
///   * Publisher: Inoov Software Engineering
///   * Website:   https://apps.inoov.com/yallanews/
///   * Email:     info@inoov.com
///
/// No telephone number is displayed (none was provided by the publisher).
/// The email address opens the device email client via a mailto intent and
/// the website opens in the browser using HTTPS. Failures (missing email
/// client, no network, ...) are reported to the user gracefully.
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  /// Verified publisher information (from the rejection notice / publisher).
  static const String _publisherName = 'Inoov Software Engineering';
  static const String _developerEmail = 'info@inoov.com';
  static const String _developerWebsite = 'https://apps.inoov.com/yallanews/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
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
                child: Icon(Icons.arrow_back_rounded,
                    size: 20, color: theme.colorScheme.onSurface),
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
                        ? [theme.colorScheme.surfaceContainer,
                           theme.colorScheme.surface,
                           theme.colorScheme.surfaceContainerHighest]
                        : [theme.colorScheme.primary,
                           theme.colorScheme.primary,
                           theme.colorScheme.primaryContainer],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('contact'),
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.translate('contactWriteUs'),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  _publisherName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                _ContactCard(
                  title: l10n.translate('contactEmail'),
                  subtitle: _developerEmail,
                  icon: Icons.email_rounded,
                  color: theme.colorScheme.primary,
                  onTap: () => _launchEmail(context),
                ),
                const SizedBox(height: 12),
                _ContactCard(
                  title: l10n.translate('contactWebsite'),
                  subtitle: _developerWebsite,
                  icon: Icons.language_rounded,
                  color: theme.colorScheme.tertiary,
                  onTap: () => _launchWebsite(context),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Open the device email client addressed to the publisher email.
  /// Shows a graceful error when no email client is available.
  Future<void> _launchEmail(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri(scheme: 'mailto', path: _developerEmail);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('contactEmailNoClient')),
            backgroundColor: themeErrorColor(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } on Exception catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('contactEmailError')),
            backgroundColor: themeErrorColor(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  /// Open the publisher website using HTTPS.
  /// Shows a graceful error when the link cannot be opened.
  Future<void> _launchWebsite(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.parse(_developerWebsite);
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        if (context.mounted) {
          _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
        }
        return;
      }
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
      }
    } on Exception catch (_) {
      if (context.mounted) {
        _showLaunchFailure(context, l10n.translate('contactWebsiteError'));
      }
    }
  }

  void _showLaunchFailure(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: themeErrorColor(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Color themeErrorColor(BuildContext context) =>
      Theme.of(context).colorScheme.error;
}

class _ContactCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ContactCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        )),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
