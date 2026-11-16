import 'dart:async';
import 'package:flutter/material.dart';
import '../services/background_crawler_service.dart';

class CrawlerStateIndicator extends StatefulWidget {
  const CrawlerStateIndicator({super.key});

  @override
  State<CrawlerStateIndicator> createState() => _CrawlerStateIndicatorState();
}

class _CrawlerStateIndicatorState extends State<CrawlerStateIndicator>
    with SingleTickerProviderStateMixin {
  CrawlerState _state = const CrawlerState();
  StreamSubscription<CrawlerState>? _subscription;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _subscription = BackgroundCrawlerService.instance.stateStream.listen(
      (s) {
        if (!mounted) return;
        setState(() => _state = s);
        if (s.running && !_controller.isAnimating) {
          _controller.repeat(reverse: true);
        } else if (!s.running && _controller.isAnimating) {
          _controller.stop();
        }
      },
      onDone: () {},
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _state.running;
    return Tooltip(
      message: isRunning ? 'Crawler running' : 'Crawler idle',
      child: SizedBox(
        width: 18,
        height: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Container(
              decoration: BoxDecoration(
                color: isRunning
                    ? Colors.greenAccent.withValues(
                        alpha: 0.55 + 0.35 * _controller.value,
                      )
                    : Colors.white24,
                shape: BoxShape.circle,
                boxShadow: isRunning
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.45),
                          blurRadius: 4 * (1 + _controller.value),
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
