import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/prayer/notification_scheduler.dart';
import '../../services/prayer/repository.dart';
import '../../models/prayer_times.dart';

class PrayerSettingsWidget extends StatefulWidget {
  final PrayerTimesRepository repository;
  final PrayerNotificationScheduler notificationScheduler;
  final PrayerTimes? times;

  const PrayerSettingsWidget({
    super.key,
    required this.repository,
    required this.notificationScheduler,
    required this.times,
  });

  @override
  State<PrayerSettingsWidget> createState() => _PrayerSettingsWidgetState();
}

class _PrayerSettingsWidgetState extends State<PrayerSettingsWidget> {
  bool _notificationsEnabled = false;
  bool _use24Hour = true;
  bool _autoLocationRefresh = true;
  String _selectedProvider = 'waqtazan';
  String? _selectedMethod;
  final Map<Prayer, bool> _prayerEnabled = {};
  final Map<Prayer, int> _offsetMinutes = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    for (final p in kObligatoryPrayers) {
      _prayerEnabled[p] = true;
      _offsetMinutes[p] = 0;
    }
  }

  Future<void> _saveProviderMethod() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prayer_provider', _selectedProvider);
    await prefs.setString('prayer_method', _selectedMethod ?? '');
    widget.repository.selectProvider(_selectedProvider);
    widget.repository.selectMethod(_selectedMethod);
  }

  Future<void> _saveNotificationEnabled(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prayer_notifications_enabled', val);
  }

  Future<void> _savePrayerConfig(Prayer prayer, bool enabled, int offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prayer_${prayer.index}_enabled', enabled);
    await prefs.setInt('prayer_${prayer.index}_offset', offset);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = prefs.getBool('prayer_notifications_enabled') ?? false;
      _use24Hour = prefs.getBool('prayer_time_24h') ?? true;
      _autoLocationRefresh = prefs.getBool('prayer_auto_location_refresh') ?? true;
      _selectedProvider = prefs.getString('prayer_provider') ?? 'waqtazan';
      _selectedMethod = prefs.getString('prayer_method');
      for (final p in kObligatoryPrayers) {
        _prayerEnabled[p] = prefs.getBool('prayer_${p.index}_enabled') ?? true;
        _offsetMinutes[p] = prefs.getInt('prayer_${p.index}_offset') ?? 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRtl = _isRtl(l10n);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('settings'),
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('notificationsPermission'), [
            SwitchListTile(
              value: _notificationsEnabled,
              onChanged: (val) async {
                setState(() => _notificationsEnabled = val);
                await _saveNotificationEnabled(val);
              },
              title: Text(l10n.translate('enableNotifications')),
              secondary: const Icon(Icons.notifications_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('individualPrayerReminders'), [
            ...kObligatoryPrayers.map((prayer) {
              return SwitchListTile(
                value: _prayerEnabled[prayer] ?? true,
                onChanged: (val) async {
                  setState(() => _prayerEnabled[prayer] = val);
                  await _savePrayerConfig(
                    prayer,
                    val,
                    _offsetMinutes[prayer] ?? 0,
                  );
                },
                title: Text(_prayerName(l10n, prayer)),
                subtitle: Text(
                  '${l10n.translate('reminderOffset')}: ${_offsetMinutes[prayer]} min',
                ),
                secondary: Icon(_icon(prayer)),
              );
            }).toList(),
          ]),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('providerSettings'), [
            ListTile(
              title: Text(l10n.translate('selectProvider')),
              trailing: DropdownButton<String>(
                value: _selectedProvider,
                items: const [
                  DropdownMenuItem(value: 'waqtazan', child: Text('Waqtazan')),
                  DropdownMenuItem(value: 'aladhan', child: Text('AlAdhan')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _selectedProvider = val);
                  unawaited(_saveProviderMethod());
                },
              ),
            ),
            ListTile(
              title: Text(l10n.translate('selectMethod')),
              trailing: DropdownButton<String?>(
                value: _selectedMethod,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Default'),
                  ),
                  ...widget.repository.availableMethods
                      .where((m) => m.providerId == _selectedProvider)
                      .map((m) => DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(m.label),
                          )),
                ],
                onChanged: (val) {
                  setState(() => _selectedMethod = val);
                  unawaited(_saveProviderMethod());
                },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('timeFormat12h'), [
            SwitchListTile(
              value: _use24Hour,
              onChanged: (val) => setState(() => _use24Hour = val),
              title: Text(l10n.translate('timeFormat24H')),
              secondary: const Icon(Icons.access_time_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('autoLocationRefresh'), [
            SwitchListTile(
              value: _autoLocationRefresh,
              onChanged: (val) => setState(() => _autoLocationRefresh = val),
              title: Text(l10n.translate('autoLocationRefresh')),
              secondary: const Icon(Icons.my_location_rounded),
            ),
          ]),
        ],
      ),
    );
  }

  bool _isRtl(AppLocalizations l10n) {
    final code = l10n.translate('languageCode');
    return code == 'ar' || code == 'fa';
  }

  Widget _buildSection(AppLocalizations l10n, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  String _prayerName(AppLocalizations l10n, Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return l10n.translate('prayerFajr');
      case Prayer.sunrise:
        return l10n.translate('prayerSunrise');
      case Prayer.dhuhr:
        return l10n.translate('prayerDhuhr');
      case Prayer.asr:
        return l10n.translate('prayerAsr');
      case Prayer.maghrib:
        return l10n.translate('prayerMaghrib');
      case Prayer.isha:
        return l10n.translate('prayerIsha');
    }
  }

  IconData _icon(Prayer p) {
    switch (p) {
      case Prayer.fajr:
        return Icons.wb_twilight_rounded;
      case Prayer.sunrise:
        return Icons.brightness_1_rounded;
      case Prayer.dhuhr:
        return Icons.wb_sunny_rounded;
      case Prayer.asr:
        return Icons.wb_incandescent_rounded;
      case Prayer.maghrib:
        return Icons.wb_twilight_rounded;
      case Prayer.isha:
        return Icons.nights_stay_rounded;
    }
  }
}
