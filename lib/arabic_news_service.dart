import 'dart:io';
import 'package:flutter/foundation.dart';
import 'arabic_news_processor.dart';

/// Background service that runs the Arabic news processor
class ArabicNewsService {
  // Singleton pattern
  ArabicNewsService._privateConstructor();
  static final ArabicNewsService instance = ArabicNewsService._privateConstructor();

  final ArabicNewsProcessor _processor = ArabicNewsProcessor.instance;
  bool _isServiceRunning = false;
  
  // For desktop/server applications, we might want to handle process lifetime
  bool _isDesktopPlatform = !kIsWeb && 
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  
  /// Start the service
  Future<void> start() async {
    if (_isServiceRunning) return;
    
    _isServiceRunning = true;
    
    if (kDebugMode) {
      print('[SERVICE] Arabic News Service starting...');
    }
    
    try {
      // Start the processor
      await _processor.start();
      
      if (kDebugMode) {
        print('[SERVICE] Arabic News Service started successfully');
        print('[SERVICE] Listening for log messages...');
        
        // Listen to logs for demonstration
        _processor.logStream.listen((log) {
          print('[LOG] $log');
        });
      }
      
      // Keep the service running (for daemon/background operation)
      if (_isDesktopPlatform && !kIsWeb) {
        await _keepAlive();
      }
    } catch (e) {
      _isServiceRunning = false;
      if (kDebugMode) {
        print('[SERVICE ERROR] Failed to start Arabic News Service: $e');
      }
      rethrow;
    }
  }
  
  /// Stop the service
  Future<void> stop() async {
    if (!_isServiceRunning) return;
    _isServiceRunning = false;
    
    if (kDebugMode) {
      print('[SERVICE] Stopping Arabic News Service...');
    }
    
    await _processor.stop();
    
    if (kDebugMode) {
      print('[SERVICE] Arabic News Service stopped');
    }
  }
  
  /// Keep the service alive (for desktop applications)
  Future<void> _keepAlive() async {
    if (kDebugMode) {
      print('[SERVICE] Entering keep-alive mode (press Ctrl+C to exit)...');
    }
    
    // For desktop applications, we can wait for stdin or use a completer
    // This keeps the isolate alive
    await Future<void>.value(); // Complete immediately for now
    // In a real daemon, you might wait for a signal or use Platform.exitCode
  }
  
  /// Get service status
  Map<String, dynamic> getStatus() {
    final processorStatus = _processor.getStatus();
    return {
      'serviceRunning': _isServiceRunning,
      ...processorStatus,
    };
  }
  
  /// Manual trigger for testing
  Future<void> processNow() async {
    if (!_isServiceRunning) {
      await start();
    }
    
    // In a real implementation, you might want to process specific sources
    // For now, we'll just report status
    final status = getStatus();
    print('[SERVICE] Manual trigger - Current status: $status');
  }
}

/// Helper function to run the service as a standalone executable
void main(List<String> arguments) async {
  // Check if we're running in debug mode or as a compiled executable
  final bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
  
  if (isDebug) {
    print('=== Arabic News Processor ===');
    print('Starting in debug mode...');
    print('Arguments: $arguments');
    print('');
  }
  
  final ArabicNewsService service = ArabicNewsService.instance;
  
  // Handle command line arguments
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printHelp();
    return;
  }
  
  if (arguments.contains('--version') || arguments.contains('-v')) {
    print('Arabic News Processor v1.0.0');
    return;
  }
  
  if (arguments.contains('--test') || arguments.contains('-t')) {
    print('Running in test mode...');
    await service.start();
    await Future.delayed(const Duration(seconds: 10)); // Run for 10 seconds
    await service.stop();
    print('Test completed.');
    return;
  }
  
  // Set up signal handlers for graceful shutdown (desktop only)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    ProcessSignal.sigint.watch().listen((_) {
      print('\n[SERVICE] Received interrupt signal, shutting down...');
      service.stop().then((_) => exit(0));
    });
    
    ProcessSignal.sigterm.watch().listen((_) {
      print('\n[SERVICE] Received terminate signal, shutting down...');
      service.stop().then((_) => exit(0));
    });
  }
  
  try {
    await service.start();
    
    if (isDebug) {
      print('[SERVICE] Arabic News Processor is running...');
      print('[SERVICE] Press Ctrl+C to stop');
      print('');
      
      // In debug mode, we'll just wait a bit then exit for demonstration
      // Remove this in production or for actual daemon usage
      await Future.delayed(const Duration(seconds: 30));
      await service.stop();
      print('[SERVICE] Demo completed.');
    }
    // In production, the service would keep running until stopped
  } catch (e, stackTrace) {
    print('[FATAL] Application error: $e');
    print(stackTrace);
    exit(1);
  }
}

void _printHelp() {
  print('''
Arabic News Processor - Local Arabic News Processing System

Usage:
  arabic_news_processor [options]

Options:
  --help, -h        Show this help message
  --version, -v     Show version information
  --test, -t        Run in test mode (runs for 10 seconds then exits)
  
Examples:
  arabic_news_processor          # Start the processor (debug mode exits after 30s)
  arabic_news_processor --test   # Run test mode
  arabic_news_processor --help   # Show help

Features:
  - Processes Arabic news sources locally
  - No external APIs or cloud services required
  - Optimized for low CPU, RAM, bandwidth, and storage usage
  - Modular, event-driven architecture
  - 10-stage processing pipeline
  - Continuous 24/7 operation capability
''');
}