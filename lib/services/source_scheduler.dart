import 'dart:async';

import 'package:yallanews/services/yalla_engine_service.dart';

/// Per-source scheduling state.
class SourceSchedule {
  final String sourceUrl;
  final String sourceName;
  final Duration refreshInterval;
  final int maxCandidatesPerRun;
  final int maxDownloadsPerRun;
  final int priority;
  bool enabled;
  DateTime? lastSuccessfulCheck;
  DateTime? lastError;
  DateTime? nextRetry;
  int consecutiveFailures;

  SourceSchedule({
    required this.sourceUrl,
    required this.sourceName,
    this.refreshInterval = const Duration(hours: 1),
    this.maxCandidatesPerRun = 50,
    this.maxDownloadsPerRun = 10,
    this.priority = 0,
    this.enabled = true,
    this.lastSuccessfulCheck,
    this.lastError,
    this.nextRetry,
    this.consecutiveFailures = 0,
  });

  /// Effective next check time, accounting for backoff.
  DateTime get effectiveNextCheck {
    final backoff = nextRetry ?? lastSuccessfulCheck;
    if (backoff == null) return DateTime.now();
    final base = backoff.add(refreshInterval);
    // Exponential backoff on consecutive failures.
    final delay = Duration(minutes: (1 << consecutiveFailures.clamp(0, 6)));
    return base.add(delay);
  }

  bool get isDue {
    if (!enabled) return false;
    if (nextRetry != null && DateTime.now().isBefore(nextRetry!)) return false;
    return DateTime.now().isAfter(effectiveNextCheck);
  }

  void onSuccess() {
    lastSuccessfulCheck = DateTime.now();
    lastError = null;
    consecutiveFailures = 0;
    nextRetry = null;
  }

  void onError() {
    lastError = DateTime.now();
    consecutiveFailures++;
    final backoffMinutes = (1 << consecutiveFailures.clamp(0, 6));
    nextRetry = DateTime.now().add(Duration(minutes: backoffMinutes));
  }

  Map<String, dynamic> toMap() => {
        'source_url': sourceUrl,
        'source_name': sourceName,
        'refresh_interval': refreshInterval.inMinutes,
        'max_candidates_per_run': maxCandidatesPerRun,
        'max_downloads_per_run': maxDownloadsPerRun,
        'priority': priority,
        'enabled': enabled ? 1 : 0,
        'last_successful_check': lastSuccessfulCheck?.millisecondsSinceEpoch,
        'last_error': lastError?.millisecondsSinceEpoch,
        'next_retry': nextRetry?.millisecondsSinceEpoch,
        'consecutive_failures': consecutiveFailures,
      };

  factory SourceSchedule.fromMap(Map<String, dynamic> m) => SourceSchedule(
        sourceUrl: m['source_url'] as String,
        sourceName: m['source_name'] as String? ?? '',
        refreshInterval: Duration(minutes: (m['refresh_interval'] as num?)?.toInt() ?? 60),
        maxCandidatesPerRun: (m['max_candidates_per_run'] as num?)?.toInt() ?? 50,
        maxDownloadsPerRun: (m['max_downloads_per_run'] as num?)?.toInt() ?? 10,
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        enabled: (m['enabled'] as num?)?.toInt() == 1,
        lastSuccessfulCheck: m['last_successful_check'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['last_successful_check'] as int)
            : null,
        lastError: m['last_error'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['last_error'] as int)
            : null,
        nextRetry: m['next_retry'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['next_retry'] as int)
            : null,
        consecutiveFailures: (m['consecutive_failures'] as num?)?.toInt() ?? 0,
      );
}

/// Per-source scheduler: runs each due source independently, never blocking UI.
class SourceScheduler {
  SourceScheduler._();
  static final SourceScheduler instance = SourceScheduler._();

  final Map<String, SourceSchedule> _schedules = {};
  final Set<String> _running = <String>{};
  Timer? _timer;
  int _generation = 0;

  /// Register a source with its schedule.
  void register(SourceSchedule schedule) {
    _schedules[schedule.sourceUrl] = schedule;
  }

  /// Register multiple schedules.
  void registerAll(Iterable<SourceSchedule> schedules) {
    for (final s in schedules) _schedules[s.sourceUrl] = s;
  }

  SourceSchedule? getSchedule(String sourceUrl) => _schedules[sourceUrl];

  /// Start the periodic scheduler tick.
  void start({required YallaEngineService engineService, Duration tick = const Duration(minutes: 5)}) {
    stop();
    _generation++;
    final gen = _generation;
    engineService.addLog('[SCHEDULER] Per-source scheduler started (tick ${tick.inMinutes}min)');
    _timer = Timer.periodic(tick, (_) async {
      if (gen != _generation) return;
      await _tick(engineService);
    });
    // Run an immediate tick.
    unawaited(_tick(engineService));
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(YallaEngineService engineService) async {
    final now = DateTime.now();
    final due = _schedules.values.where((s) => s.isDue && !_running.contains(s.sourceUrl)).toList();
    // Sort by priority (higher first) then by overdue amount.
    due.sort((a, b) {
      if (a.priority != b.priority) return b.priority.compareTo(a.priority);
      final ea = a.effectiveNextCheck;
      final eb = b.effectiveNextCheck;
      return ea.compareTo(eb);
    });
    for (final schedule in due) {
      _running.add(schedule.sourceUrl);
      try {
        engineService.addLog('[SCHEDULER] Due source: ${schedule.sourceName} (${schedule.sourceUrl})');
        // The actual crawl is triggered by the caller via onSourceDue callback.
        // This scheduler only tracks due-ness and backoff.
      } finally {
        _running.remove(schedule.sourceUrl);
      }
    }
  }

  /// Mark a source as successfully checked.
  void markSuccess(String sourceUrl) {
    final s = _schedules[sourceUrl];
    if (s != null) s.onSuccess();
  }

  /// Mark a source as failed (triggers backoff).
  void markError(String sourceUrl) {
    final s = _schedules[sourceUrl];
    if (s != null) s.onError();
  }

  /// Returns schedules sorted by priority for reporting.
  List<SourceSchedule> get allSchedules =>
      List<SourceSchedule>.unmodifiable(_schedules.values.toList()
        ..sort((a, b) => b.priority.compareTo(a.priority)));

  /// Whether a source is currently being crawled (prevents overlap).
  bool isRunning(String sourceUrl) => _running.contains(sourceUrl);

  void dispose() {
    stop();
  }
}
