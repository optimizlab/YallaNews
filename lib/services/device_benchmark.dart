import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'yalla_engine_service.dart';
import 'connectivity_service.dart';

/// Measures device hardware/network capability and recommends crawl limits.
class DeviceBenchmark {
  DeviceBenchmark._();

  static final DeviceBenchmark instance = DeviceBenchmark._();

  BenchmarkResult? _lastResult;
  DateTime? _lastBenchmark;

  static const int _benchmarkValidityMs = 24 * 60 * 60 * 1000; // 24 hours

  bool get hasValidBenchmark {
    return _lastResult != null &&
        _lastBenchmark != null &&
        DateTime.now().difference(_lastBenchmark!) < const Duration(milliseconds: _benchmarkValidityMs);
  }

  BenchmarkResult? get lastResult => _lastResult;

  Future<BenchmarkResult> runBenchmark({
    required YallaEngineService engineService,
    String? testArticleUrl,
  }) async {
    final memoryMb = await measureMemoryMb();
    final cpuScore = await measureCpuScore();
    final networkProfile = await measureNetworkProfile(engineService, testArticleUrl);

    final tier = classifyTier(memoryMb, cpuScore, networkProfile);

    final limits = recommendLimits(tier, networkProfile);

    _lastResult = BenchmarkResult(
      memoryMb: memoryMb,
      cpuScore: cpuScore,
      networkProfile: networkProfile,
      tier: tier,
      limits: limits,
      measuredAt: DateTime.now(),
    );
    _lastBenchmark = DateTime.now();

    engineService.addLog('[BENCHMARK] Tier=$tier mem=${memoryMb}MB cpu=$cpuScore net=${networkProfile.speedMbps?.toStringAsFixed(1)}Mbps');

    return _lastResult!;
  }

  Future<int> measureMemoryMb() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final info = ProcessInfo.currentRss;
        return info ~/ 1024 ~/ 1024;
      }
    } catch (_) {}
    return 0;
  }

  Future<int> measureCpuScore() async {
    try {
      return await compute(_computeCpuScore, 50000);
    } catch (_) {
      return 1000;
    }
  }

  static int _computeCpuScore(int iterations) {
    final sw = Stopwatch()..start();
    final random = Random(42);
    double result = 0;
    for (int i = 0; i < iterations; i++) {
      result += sqrt(random.nextDouble()) * log(random.nextDouble() + 1);
    }
    sw.stop();
    final elapsedMs = sw.elapsedMilliseconds;
    if (elapsedMs <= 0) return 1000;
    // Normalized to original 500k scale (x10)
    return (iterations * 10 * 1000) ~/ elapsedMs;
  }

  Future<NetworkProfile> measureNetworkProfile(
    YallaEngineService engineService,
    String? testArticleUrl,
  ) async {
    bool isWifi = false;
    try {
      isWifi = await ConnectivityService.isWifi();
    } catch (_) {}

    ConnectionType connectionType = ConnectionType.none;
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.wifi)) {
        connectionType = ConnectionType.wifi;
      } else if (result.contains(ConnectivityResult.mobile)) {
        connectionType = ConnectionType.mobile;
      } else {
        connectionType = ConnectionType.none;
      }
    } catch (_) {}

    double? speedMbps;
    int? latencyMs;
    if (testArticleUrl != null && testArticleUrl.isNotEmpty) {
      try {
        final sw = Stopwatch()..start();
        final response = await HttpClient()
            .getUrl(Uri.parse(testArticleUrl))
            .timeout(const Duration(seconds: 8))
            .then((req) => req.close())
            .then((resp) => resp.drain());
        sw.stop();
        latencyMs = sw.elapsedMilliseconds;
        if (latencyMs > 0) {
          speedMbps = (8.0 / latencyMs) * 1000;
        }
      } on TimeoutException {
        latencyMs = null;
        speedMbps = 0;
      } catch (_) {
        latencyMs = null;
        speedMbps = null;
      }
    }

    return NetworkProfile(
      connectionType: connectionType,
      isWifi: isWifi,
      speedMbps: speedMbps,
      latencyMs: latencyMs,
    );
  }

  DeviceTier classifyTier(int memoryMb, int cpuScore, NetworkProfile network) {
    final hasGoodNetwork = network.speedMbps != null && network.speedMbps! > 5;
    final hasWifi = network.isWifi;
    final lowMemory = memoryMb < 200;
    final highMemory = memoryMb >= 500;

    if (lowMemory) {
      return DeviceTier.low;
    }

    if (highMemory && hasGoodNetwork && cpuScore >= 800) {
      return DeviceTier.high;
    }

    if (cpuScore < 400 || (!hasWifi && network.connectionType == ConnectionType.mobile)) {
      return DeviceTier.low;
    }

    return DeviceTier.medium;
  }

  CrawlLimits recommendLimits(DeviceTier tier, NetworkProfile network) {
    switch (tier) {
      case DeviceTier.high:
        return CrawlLimits(
          sourcesToCrawl: 5,
          urlsPerSource: 5,
          perSourceLimit: 3,
          pauseBetweenArticles: const Duration(milliseconds: 600),
          pauseBetweenSources: const Duration(milliseconds: 800),
          maxConcurrentRequests: 2,
          batchSize: 5,
        );
      case DeviceTier.medium:
        return CrawlLimits(
          sourcesToCrawl: 1,
          urlsPerSource: 1,
          perSourceLimit: 1,
          pauseBetweenArticles: const Duration(milliseconds: 2500),
          pauseBetweenSources: const Duration(milliseconds: 3000),
          maxConcurrentRequests: 1,
          batchSize: 1,
        );
      case DeviceTier.low:
        return CrawlLimits(
          sourcesToCrawl: 1,
          urlsPerSource: 1,
          perSourceLimit: 1,
          pauseBetweenArticles: const Duration(milliseconds: 2500),
          pauseBetweenSources: const Duration(milliseconds: 3000),
          maxConcurrentRequests: 1,
          batchSize: 1,
        );
    }
  }
}

enum DeviceTier { low, medium, high }

enum ConnectionType { none, wifi, mobile }

class NetworkProfile {
  final ConnectionType connectionType;
  final bool isWifi;
  final double? speedMbps;
  final int? latencyMs;

  const NetworkProfile({
    required this.connectionType,
    required this.isWifi,
    this.speedMbps,
    this.latencyMs,
  });
}

class BenchmarkResult {
  final int memoryMb;
  final int cpuScore;
  final NetworkProfile networkProfile;
  final DeviceTier tier;
  final CrawlLimits limits;
  final DateTime measuredAt;

  const BenchmarkResult({
    required this.memoryMb,
    required this.cpuScore,
    required this.networkProfile,
    required this.tier,
    required this.limits,
    required this.measuredAt,
  });
}

class CrawlLimits {
  final int sourcesToCrawl;
  final int urlsPerSource;
  final int perSourceLimit;
  final Duration pauseBetweenArticles;
  final Duration pauseBetweenSources;
  final int maxConcurrentRequests;
  final int batchSize;

  const CrawlLimits({
    required this.sourcesToCrawl,
    required this.urlsPerSource,
    required this.perSourceLimit,
    required this.pauseBetweenArticles,
    required this.pauseBetweenSources,
    required this.maxConcurrentRequests,
    required this.batchSize,
  });
}
