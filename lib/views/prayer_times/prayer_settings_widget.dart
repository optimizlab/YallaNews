import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/prayer/notification_scheduler.dart';
import '../../services/prayer/repository.dart';
import '../../services/prayer/adhan_service.dart';
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
  String _selectedMuezzin = 'makkah';
  bool _isPreviewingAdhan = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    for (final p in kObligatoryPrayers) {
      _prayerEnabled[p] = true;
      _offsetMinutes[p] = 0;
    }
    AdhanService.instance.init().then((_) {
      if (mounted) setState(() => _selectedMuezzin = AdhanService.instance.selectedMuezzin);
    });
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

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prayer_notifications_enabled', _notificationsEnabled);
    await prefs.setBool('prayer_time_24h', _use24Hour);
    await prefs.setBool('prayer_auto_location_refresh', _autoLocationRefresh);
    await prefs.setString('prayer_provider', _selectedProvider);
    if (_selectedMethod != null) {
      await prefs.setString('prayer_method', _selectedMethod!);
    } else {
      await prefs.remove('prayer_method');
    }
    for (final p in kObligatoryPrayers) {
      await prefs.setBool('prayer_${p.index}_enabled', _prayerEnabled[p]!);
      await prefs.setInt('prayer_${p.index}_offset', _offsetMinutes[p]!);
    }

    // Re-schedule notifications if enabled and we have times
    if (_notificationsEnabled && widget.times != null) {
      final configs = <Prayer, PrayerReminderConfig>{
        for (final p in kObligatoryPrayers)
          p: PrayerReminderConfig(
            enabled: _prayerEnabled[p] ?? true,
            offsetMinutes: _offsetMinutes[p] ?? 0,
            sound: true,
          ),
      };
      await widget.notificationScheduler.schedulePrayers(
        widget.times!,
        configs: configs,
      );
    } else {
      await widget.notificationScheduler.cancelAll();
    }

    if (mounted) {
      widget.repository.selectProvider(_selectedProvider);
      widget.repository.selectMethod(_selectedMethod);
    }
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
              onChanged: (val) => setState(() => _notificationsEnabled = val),
              title: Text(l10n.translate('enableNotifications')),
              secondary: const Icon(Icons.notifications_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection(l10n, l10n.translate('individualPrayerReminders'), [
            ...kObligatoryPrayers.map((prayer) {
              return SwitchListTile(
                value: _prayerEnabled[prayer] ?? true,
                onChanged: (val) => setState(() => _prayerEnabled[prayer] = val),
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
          const SizedBox(height: 16),
          _buildSection(l10n, 'صوت الأذان', [
            ...AdhanService.muezzins.entries.map((entry) {
              final key = entry.key;
              final name = entry.value;
              return RadioListTile<String>(
                value: key,
                groupValue: _selectedMuezzin,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _selectedMuezzin = val);
                  AdhanService.instance.setMuezzin(val);
                },
                title: Text(
                  name,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                secondary: IconButton(
                  icon: _isPreviewingAdhan && _selectedMuezzin == key
                      ? const Icon(Icons.stop_circle_rounded)
                      : const Icon(Icons.play_circle_outline_rounded),
                  tooltip: 'معاينة',
                  onPressed: () async {
                    if (_isPreviewingAdhan) {
                      await AdhanService.instance.stopAdhan();
                      if (mounted) setState(() => _isPreviewingAdhan = false);
                    } else {
                      setState(() {
                        _selectedMuezzin = key;
                        _isPreviewingAdhan = true;
                      });
                      await AdhanService.instance.previewMuezzin(key);
                      if (mounted) setState(() => _isPreviewingAdhan = false);
                    }
                  },
                ),
              );
            }).toList(),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveSettings,
              child: Text(l10n.translate('settings')),
            ),
          ),
          const SizedBox(height: 24),
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
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
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
