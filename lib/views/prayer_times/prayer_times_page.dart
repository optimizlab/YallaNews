import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/prayer_times.dart';
import '../../services/prayer/athan_service.dart';
import '../../services/prayer/countdown_engine.dart';
import '../../services/prayer/repository.dart';
import '../settings_page.dart';

class PrayerTimesPage extends StatefulWidget {
  const PrayerTimesPage({super.key});

  @override
  State<PrayerTimesPage> createState() => _PrayerTimesPageState();
}

class _PrayerTimesPageState extends State<PrayerTimesPage> {
  late final PrayerTimesRepository _repository;
  late final CountdownEngine _countdownEngine;

  PrayerTimes? _times;
  bool _isLoading = true;
  String? _error;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _repository = PrayerTimesRepository();
    _countdownEngine = CountdownEngine();
    _init();
  }

  Future<void> _init() async {
    // Ensure the background Athan system is initialized (first-install /
    // monthly sync / alarm scheduling). This runs independently of the UI and
    // never triggers an API call as a consequence of opening this screen.
    await AthanService.instance.initialize();

    if (!mounted) return;
    await _loadTodayFromDb();
  }

  /// Load today's prayer times exclusively from the local database. Zero API
  /// requests are made here.
  Future<void> _loadTodayFromDb() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final city = _repository.selectedCity;
      final dbInitialized = await AthanService.instance.isDbInitialized;
      if (city == null) {
        if (!mounted) return;
        setState(() {
          _times = null;
          _error = 'No location set. Choose a city in settings to see prayer times.';
          _isLoading = false;
          _synced = dbInitialized;
        });
        return;
      }

      // Apply saved provider/method so the DB query matches the stored data.
      final prefs = await SharedPreferences.getInstance();
      _repository.selectProvider(prefs.getString('prayer_provider') ?? 'waqtazan');
      _repository.selectMethod(prefs.getString('prayer_method'));

      final times = await _repository.todayFromDb(city);
      if (!mounted) return;

      if (times == null || times.times.isEmpty) {
        // DB empty (first install, sync failed, city just changed): fall back
        // to a live fetch so the user still sees prayer times instead of an
        // empty screen. This is a one-off request for today only.
        final result = await _repository.forCity(city, forceRefresh: true);
        if (!mounted) return;
        if (result.succeeded && result.times.times.isNotEmpty) {
          setState(() {
            _times = result.times;
            _isLoading = false;
            _synced = dbInitialized;
          });
          _countdownEngine.updateTimes(result.times);
          _countdownEngine.start(onTick: () {
            if (mounted) setState(() {});
          });
          await _scheduleAlarms(result.times);
        } else {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          setState(() {
            _times = null;
            _error = result.error?.toString() ??
                l10n.translate('prayerTimesLoadFailedRetry');
            _isLoading = false;
            _synced = dbInitialized;
          });
        }
        return;
      }

      setState(() {
        _times = times;
        _isLoading = false;
        _synced = dbInitialized;
      });

      _countdownEngine.updateTimes(times);
      _countdownEngine.start(onTick: () {
        if (mounted) setState(() {});
      });
      await _scheduleAlarms(times);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Schedule all future enabled Athan alarms from the local database. No API
  /// call is involved.
  Future<void> _scheduleAlarms(PrayerTimes times) async {
    final city = _repository.selectedCity;
    if (city == null) return;
    await AthanService.instance.scheduler.scheduleAllPrayers(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      provider: _repository.selectedProviderId,
      method: _repository.selectedMethod ?? '',
    );
    AthanService.instance.scheduler.setTimeZone(times.timeZone);
  }

  /// Re-read today from the database and re-schedule alarms. No API request.
  Future<void> _onRefresh() async {
    await _loadTodayFromDb();
  }

  @override
  void dispose() {
    _countdownEngine.dispose();
    super.dispose();
  }

  bool _isArabicOrPersian(AppLocalizations l10n) {
    final code = l10n.translate('languageCode');
    return code == 'ar' || code == 'fa';
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return DateFormat.Hm().format(time);
  }

  /// Returns the translated Hijri month name when the provider reported a
  /// month number, otherwise falls back to the raw provider hijri string.
  String _hijriLabel(PrayerTimes times, AppLocalizations l10n) {
    final month = times.hijriDateMonth;
    if (month != null && month >= 1 && month <= 12) {
      final translated = l10n.translate('hijriMonth$month');
      if (translated != 'hijriMonth$month') return translated;
    }
    return times.hijriDate;
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

  String _translatedCityName(PrayerTimes times, AppLocalizations l10n) {
    final translated = l10n.translate('city_${times.citySlug}');
    if (translated == 'city_${times.citySlug}') return times.cityName;
    return translated;
  }

  String _translatedCountryName(PrayerTimes times, AppLocalizations l10n) {
    final translated = l10n.translate('country_${times.countrySlug}');
    if (translated == 'country_${times.countrySlug}') return times.countryName;
    return translated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: _buildTodayTab(l10n),
      floatingActionButton: _times != null
          ? FloatingActionButton.extended(
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.translate('refresh')),
            )
          : null,
    );
  }

  Widget _buildTodayTab(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_times == null || _times!.times.isEmpty) {
      return _buildEmptyState(l10n);
    }

    final next = _countdownEngine.nextPrayer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeCard(l10n, next),
          const SizedBox(height: 16),
          _buildCountdownBanner(l10n),
          const SizedBox(height: 16),
          _buildPrayerSchedule(l10n),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHomeCard(AppLocalizations l10n, NextPrayerInfo? next) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_translatedCityName(_times!, l10n)}, ${_translatedCountryName(_times!, l10n)}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hijriLabel(_times!, l10n),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _times!.isRamadan ? l10n.translate('ramadan') : '',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time_rounded, size: 20,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.translate('nextPrayer'),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (next != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _prayerName(l10n, next.prayer),
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              next.isTomorrow
                                  ? l10n.translate('tomorrow')
                                  : l10n.translate('today'),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(next.time),
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.translate('nextPrayerIn')} ${next.formattedRemaining}',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountdownBanner(AppLocalizations l10n) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (_) => 0),
      builder: (context, snapshot) {
        final current = _countdownEngine.nextPrayer;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _prayerName(l10n, current.prayer),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          current.isTomorrow
                              ? l10n.translate('tomorrow')
                              : l10n.translate('today'),
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    current.formattedRemaining,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrayerSchedule(AppLocalizations l10n) {
    final isRtl = _isArabicOrPersian(l10n);
    final next = _countdownEngine.nextPrayer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('prayerSchedule'),
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...kObligatoryPrayers.map((prayer) {
          final time = _times!.times[prayer];
          final isNext = next.prayer == prayer &&
              next.remaining > Duration.zero &&
              next.remaining.inMinutes < 180;
          return _PrayerRow(
            prayer: prayer,
            label: _prayerName(l10n, prayer),
            time: time != null ? _formatTime(time.localTime) : '--:--',
            isNext: isNext,
            isRtl: isRtl,
          );
        }).toList(),
        const Divider(height: 24),
        _PrayerRow(
          prayer: Prayer.sunrise,
          label: _prayerName(l10n, Prayer.sunrise),
          time: _times!.times[Prayer.sunrise] != null
              ? _formatTime(_times!.times[Prayer.sunrise]!.localTime)
              : '--:--',
          isNext: false,
          isRtl: isRtl,
          isSunrise: true,
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final city = _repository.selectedCity;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_rounded, size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            city == null
                ? l10n.translate('prayerLocationNotSet')
                : (_error ?? l10n.translate('prayerTimesNotAvailable')),
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            city == null
                ? l10n.translate('setLocationForPrayerTimes')
                : l10n.translate('prayerTimesLoadFailedRetry'),
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (city == null) ...[
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
                if (mounted) _loadTodayFromDb();
              },
              icon: const Icon(Icons.add_location_rounded),
              label: Text(l10n.translate('setLocation')),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.translate('retry')),
          ),
          if (_synced) ...[
            const SizedBox(height: 16),
            Text(
              l10n.translate('prayerTimesLoadedFromDatabase'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  final Prayer prayer;
  final String label;
  final String time;
  final bool isNext;
  final bool isRtl;
  final bool isSunrise;

  const _PrayerRow({
    required this.prayer,
    required this.label,
    required this.time,
    this.isNext = false,
    this.isRtl = false,
    this.isSunrise = false,
  });

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

  @override
  Widget build(BuildContext context) {
    final color = isSunrise
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (isNext
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isNext
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isNext || isSunrise)
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(prayer), size: 20,
                color: (isNext || isSunrise)
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Text(
            time,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
