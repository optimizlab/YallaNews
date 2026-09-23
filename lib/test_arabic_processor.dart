import 'dart:io';
import 'package:flutter/foundation.dart';
import 'arabic_news_processor.dart';

void main() async {
  // Initialize the Arabic News Processor
  final processor = ArabicNewsProcessor.instance;
  
  print('=== Arabic News Processor Standalone Test ===');
  
  try {
    // Start the processor
    print('Starting Arabic News Processor...');
    await processor.start();
    print('Processor started successfully!');
    
    // Let it run for a short period to demonstrate functionality
    print('Running for 10 seconds to demonstrate operation...');
    await Future.delayed(const Duration(seconds: 10));
    
    // Get statistics
    final stats = await processor.getStatistics();
    print('Current Statistics:');
    print('  - Is Running: ${stats['isRunning']}');
    print('  - Total Articles: ${stats['totalArticles']}');
    print('  - Active Sources: ${stats['activeSources']}');
    if (stats['sources'] != null && (stats['sources'] as List).isNotEmpty) {
      print('  - Sources: ${(stats['sources'] as List).take(3).join(', ')}${((stats['sources'] as List).length > 3) ? ' and ${((stats['sources'] as List).length - 3)} more' : ''}');
    }
    print('  - Last Updated: ${stats['lastUpdated']}');
    
    // Stop the processor
    print('Stopping processor...');
    await processor.stop();
    print('Processor stopped successfully!');
    
    print('Test completed successfully!');
    
  } catch (e, stackTrace) {
    print('Error during test: $e');
    print('Stack trace: $stackTrace');
    // Ensure cleanup
    try {
      await processor.stop();
    } catch (e) {
      print('Error during cleanup: $e');
    }
    exit(1);
  }
}