import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/city_registry.dart';
import '../../models/prayer_times.dart';
import '../../services/prayer/countdown_engine.dart';
import '../../services/prayer/notification_scheduler.dart';
import '../../services/prayer/repository.dart';
import '../prayer_times/location_selector_widget.dart';
import '../prayer_times/prayer_settings_widget.dart';

class PrayerTimesPage extends StatefulWidget {
  const PrayerTimesPage({super.key});

  @override
  State<PrayerTimesPage> createState() => _PrayerTimesPageState();
}

class _PrayerTimesPageState extends State<PrayerTimesPage>
    with TickerProviderStateMixin {
  late final PrayerTimesRepository _repository;
  late final PrayerNotificationScheduler _notificationScheduler;
  late final CountdownEngine _countdownEngine;
  late final TabController _tabController;

  PrayerTimes? _times;
  bool _isLoading = true;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _repository = PrayerTimesRepository();
    _notificationScheduler = PrayerNotificationScheduler();
    _countdownEngine = CountdownEngine();
    _tabController = TabController(length: 3, vsync: this);
    _loadPrayerTimes();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    await _notificationScheduler.initialize();
  }

  Future<void> _loadPrayerTimes() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _repository.getToday();
      if (!mounted) return;
      setState(() {
        _times = result.times;
        _error = result.error?.message;
        _offline = result.times.fromCache || !result.succeeded;
        _isLoading = false;
      });
      if (_times != null) {
        _countdownEngine.updateTimes(_times!);
        _countdownEngine.start(onTick: () => setState(() {}));
        await _scheduleNotifications(_times!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _scheduleNotifications(PrayerTimes times) async {
    final enabled = await _notificationScheduler.areNotificationsEnabled();
    if (!enabled) return;

    final configs = <Prayer, PrayerReminderConfig>{
      for (final p in kObligatoryPrayers)
        p: const PrayerReminderConfig(enabled: true, offsetMinutes: 0, sound: true),
    };
    _notificationScheduler.setTimeZone(times.timeZone);
    await _notificationScheduler.schedulePrayers(times, configs: configs);
  }

  Future<void> _onCitySelected(CityEntry city) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _repository.setManualLocation(city);
      final result = await _repository.refresh(city);
      if (!mounted) return;
      setState(() {
        _times = result.times;
        _error = result.error?.message;
        _offline = result.times.fromCache || !result.succeeded;
        _isLoading = false;
      });
      if (_times != null) {
        _countdownEngine.updateTimes(_times!);
        await _scheduleNotifications(_times!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    if (_times == null) return;
    await _loadPrayerTimes();
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return DateFormat.Hm().format(time);
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

  @override
  void dispose() {
    _tabController.dispose();
    _countdownEngine.dispose();
    _notificationScheduler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRtl = _isArabicOrPersian(l10n);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildTodayTab(l10n),
                LocationSelectorWidget(
                  repository: _repository,
                  onCitySelected: _onCitySelected,
                ),
                PrayerSettingsWidget(
                  repository: _repository,
                  notificationScheduler: _notificationScheduler,
                  times: _times,
                ),
              ],
            ),
          ),
          SafeArea(
            child: _buildTabBar(l10n),
          ),
        ],
      ),
      floatingActionButton: _times != null
          ? FloatingActionButton.extended(
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.translate('refresh')),
            )
          : null,
    );
  }

  Widget _buildTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabController,
      onTap: (i) {},
      tabs: [
        Tab(
          icon: const Icon(Icons.today_rounded),
          text: l10n.translate('prayerTimes'),
        ),
        Tab(
          icon: const Icon(Icons.location_on_rounded),
          text: l10n.translate('selectCity'),
        ),
        Tab(
          icon: const Icon(Icons.settings_rounded),
          text: l10n.translate('settings'),
        ),
      ],
    );
  }

  bool _isArabicOrPersian(AppLocalizations l10n) {
    final code = l10n.translate('languageCode');
    return code == 'ar' || code == 'fa';
  }

  Widget _buildTodayTab(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_times == null || _times!.times.isEmpty) {
      return _buildErrorState(l10n);
    }

    final next = _countdownEngine.nextPrayer;
    final isRtl = _isArabicOrPersian(l10n);

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
          if (_offline) ...[
            const SizedBox(height: 16),
            _buildOfflineNotice(l10n),
          ],
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
                      '${_times!.cityName}, ${_times!.countryName}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _times!.hijriDate,
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
      stream: _countdownEngineTickStream(),
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

  Stream<int> _countdownEngineTickStream() {
    return Stream.periodic(const Duration(seconds: 1), (_) => 0);
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

  Widget _buildOfflineNotice(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.translate('offlineCachedData'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: _onRefresh,
              child: Text(l10n.translate('retry')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 64,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _error ?? l10n.translate('errorLoadingPrayerTimes'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.translate('retry')),
          ),
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
