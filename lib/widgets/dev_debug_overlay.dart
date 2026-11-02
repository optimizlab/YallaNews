import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/background_crawler_service.dart';
import '../services/yalla_engine_service.dart';
import '../database/news_db.dart';

class DevDebugOverlay extends StatefulWidget {
  const DevDebugOverlay({super.key, required this.child, this.onForceCrawl, this.engineService});

  final Widget child;
  final VoidCallback? onForceCrawl;
  final YallaEngineService? engineService;

  @override
  State<DevDebugOverlay> createState() => _DevDebugOverlayState();
}

class _DevDebugOverlayState extends State<DevDebugOverlay> {
  bool _expanded = false;
  bool _visible = false;
  bool _forceCrawlRequested = false;
  int _articleCount = 0;
  int _cachedCount = 0;
  CrawlerState _crawlerState = const CrawlerState();
  List<String> _recentLogs = <String>[];
  int _memoryMb = 0;

  StreamSubscription<CrawlerState>? _crawlerSubscription;
  StreamSubscription<String>? _logSubscription;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _visible = true;
      _startListeners();
      _tick();
    }
  }

  @override
  void dispose() {
    _crawlerSubscription?.cancel();
    _logSubscription?.cancel();
    super.dispose();
  }

  void _startListeners() {
    _crawlerSubscription = BackgroundCrawlerService.instance.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _crawlerState = state;
        if (state.running || !state.running) {
          _forceCrawlRequested = false;
        }
      });
    });

    _logSubscription = widget.engineService?.logStream.listen((log) {
      if (log.contains('FORCE CRAWL')) {
        _handleForceCrawl();
      }
    });
  }

  void _handleForceCrawl() {
    if (widget.onForceCrawl != null) {
      setState(() => _forceCrawlRequested = true);
      widget.onForceCrawl!();
    }
  }

  Future<void> _tick() async {
    if (!mounted || !_visible) return;
    try {
      int memoryMb = 0;
      if (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          final info = ProcessInfo.currentRss;
          memoryMb = info ~/ 1024 ~/ 1024;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _memoryMb = memoryMb;
        });
      }
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 8));
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !_visible) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    final isRunning = _crawlerState.running;
    final crawlerLabel = isRunning
        ? 'Crawler: RUNNING'
        : _crawlerState.reset
            ? 'Crawler: RESET'
            : 'Crawler: IDLE';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          setState(() => _expanded = !_expanded);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _expanded
                ? Colors.black.withValues(alpha: 0.92)
                : Colors.black.withValues(alpha: 0.65),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border.all(color: Colors.white24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _expanded ? _buildExpandedContent(crawlerLabel) : _buildCollapsedContent(crawlerLabel),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(String crawlerLabel) {
    final isStarting = _forceCrawlRequested || _crawlerState.running;
    return Row(
      children: [
        Icon(Icons.bug_report, size: 16, color: Colors.greenAccent),
        const SizedBox(width: 8),
        Text('DEV', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        Expanded(child: Text(crawlerLabel, style: TextStyle(color: Colors.white70, fontSize: 12))),
        Text('Articles: $_articleCount', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 12),
        Text('Mem: $_memoryMb MB', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: isStarting ? null : _handleForceCrawl,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isStarting ? Colors.grey : Colors.redAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(isStarting ? 'Starting...' : 'FORCE CRAWL', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

      Widget _buildExpandedContent(String crawlerLabel) {
    final logs = _recentLogs.take(12).toList();
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bug_report, size: 18, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text('DEBUG OVERLAY', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('Tap to collapse', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _chip('Articles', '$_articleCount'),
            _chip('Cached', '$_cachedCount'),
            _chip(crawlerLabel, _crawlerState.running ? 'ON' : 'OFF', active: _crawlerState.running),
            _chip('Memory', '$_memoryMb MB'),
          ],
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _crawlerState.running || _forceCrawlRequested ? null : _handleForceCrawl,
          icon: Icon(Icons.download_rounded, size: 16),
          label: Text(_crawlerState.running || _forceCrawlRequested ? 'Starting...' : 'Force crawl now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 4),
        Text('Optimization tips', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_optimizationTip(), style: TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _chip(String label, String value, {bool active = false}) {
    final color = active ? Colors.greenAccent : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _optimizationTip() {
    if (_crawlerState.running) return 'Crawler is active; keep small-memory limits on.';
    if (_memoryMb > 180) return 'Memory is high; consider closing background crawler or refreshing.';
    return 'App is idle; API serving content.';
  }
}
