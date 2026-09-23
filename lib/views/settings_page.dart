import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_settings.dart';
import '../services/tts_service.dart';
import '../l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _isNotificationsEnabled = true;
  bool _isBackgroundCrawlerEnabled = true;
  int _topSourcesCount = 10;
  int _maxUrlsPerSource = 100;
  String _selectedLanguage = 'ar';
  List<dynamic> _ttsVoices = [];
  Map<String, String>? _selectedVoice;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTtsSettings();
  }

  Future<void> _loadSettings() async {
    final settings = AppSettings.instance;
    final topSourcesCount = await settings.getTopSourcesCount();
    final maxUrlsPerSource = await settings.getMaxUrlsPerSource();
    final backgroundEnabled = await settings.isBackgroundCrawlerEnabled();
    
    if (mounted) {
      setState(() {
        _topSourcesCount = topSourcesCount;
        _maxUrlsPerSource = maxUrlsPerSource;
        _isDarkMode = _isEffectiveDarkMode(context);
        _selectedLanguage = settings.locale?.languageCode ?? 'ar';
        _isNotificationsEnabled = backgroundEnabled;
      });
    }
  }

  Future<void> _loadTtsSettings() async {
    final voices = await TTSService.instance.getVoices();
    if (mounted) {
      setState(() {
        _ttsVoices = voices;
      });
    }
  }

  bool _isEffectiveDarkMode(BuildContext context) {
    final settings = AppSettings.instance;
    if (settings.themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return settings.themeMode == ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('settings')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Text(
                    l10n.translate('settings'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    l10n.translate('language'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLanguageOption('ar'),
                const SizedBox(height: 8),
                _buildLanguageOption('en'),
                const SizedBox(height: 8),
                _buildLanguageOption('fr'),
                const SizedBox(height: 8),
                _buildLanguageOption('tr'),
                const SizedBox(height: 24),
                _buildToggleOption(
                  l10n.translate('darkMode'),
                  Icons.dark_mode_rounded,
                  _isEffectiveDarkMode(context),
                  (value) async {
                    setState(() => _isDarkMode = value);
                    await AppSettings.instance.setThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildToggleOption(
                  l10n.translate('notifications'),
                  Icons.notifications_active_rounded,
                  _isNotificationsEnabled,
                  (value) => setState(() => _isNotificationsEnabled = value),
                ),
                const SizedBox(height: 12),
                _buildToggleOption(
                  l10n.translate('backgroundCrawler'),
                  Icons.download_rounded,
                  _isBackgroundCrawlerEnabled,
                  (value) async {
                    setState(() => _isBackgroundCrawlerEnabled = value);
                    await AppSettings.instance.setBackgroundCrawlerEnabled(value);
                  },
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    l10n.translate('voiceSelection'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTtsVoiceOption(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String languageCode) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _selectedLanguage == languageCode;
    String title;
    String subtitle;

    switch (languageCode) {
      case 'ar':
        title = 'العربية';
        subtitle = 'اللغة الاماراتية للتطبيق';
        break;
      case 'en':
        title = 'English';
        subtitle = l10n.translate('secondaryLtr');
        break;
      case 'fr':
        title = 'Français';
        subtitle = l10n.translate('french');
        break;
      case 'tr':
        title = 'Türkçe';
        subtitle = l10n.translate('turkish');
        break;
      default:
        title = languageCode;
        subtitle = '';
    }

    return GestureDetector(
      onTap: () async {
        setState(() => _selectedLanguage = languageCode);
        await AppSettings.instance.setLocale(Locale(languageCode));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption(String title, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTtsVoiceOption() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).translate('voiceSelection'),
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, String>>(
            isExpanded: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            value: _selectedVoice,
            items: _ttsVoices.map((voice) {
              final v = Map<String, String>.from(voice);
              final name = v['name'] ?? AppLocalizations.of(context).translate('unknownVoice');
              final locale = v['locale'] ?? '';
              return DropdownMenuItem<Map<String, String>>(
                value: v,
                child: Text('$name ($locale)'),
              );
            }).toList(),
            onChanged: (voice) async {
              if (voice == null) return;
              setState(() => _selectedVoice = voice);
              await TTSService.instance.setVoice(voice);
            },
          ),
        ],
      ),
    );
  }
}