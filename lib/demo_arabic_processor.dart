import 'dart:io';
import 'package:flutter/foundation.dart';
import 'arabic_news_processor.dart';
import 'models/news_source.dart';

/// Example usage of the Arabic News Processor
void main() async {
  print('=== Arabic News Processor Demo ===');
  
  // Initialize the processor
  final processor = ArabicNewsProcessor.instance;
  
  try {
    // Start the processor
    await processor.start();
    print('Processor started successfully!');
    
    // Get some example sources (in a real app, these would come from the database)
    // For demo purposes, we'll create a mock source
    final exampleSource = NewsSource(
      id: 999,
      country: 'Saudi Arabia',
      countryCode: 'SA',
      name: 'Example News Source',
      url: 'https://www.example.com/news',
      category: 'general_news',
      type: 'digital_news',
      language: 'ar',
      rank: 1,
    );
    
    // Manually trigger a crawl for demonstration
    // Note: This would normally be handled automatically by the scheduler
    print('Triggering manual crawl for demonstration...');
    await processor.crawlSourceNow(exampleSource);
    
    // Wait a bit to see some activity
    print('Waiting 15 seconds to observe processing...');
    await Future.delayed(const Duration(seconds: 15));
    
    // Get statistics
    final stats = await processor.getStatistics();
    print('Current Statistics: $stats');
    
    // Stop the processor
    await processor.stop();
    print('Processor stopped successfully!');
    
  } catch (e) {
    print('Error: $e');
    await processor.stop(); // Ensure cleanup
  }
  
  print('Demo completed.');
}

/// Alternative main function showing how to run as a service
void mainService() {
  // This would be used when running as a background service/daemon
  // For demonstration, we'll just show how to start it
  
  print('Starting Arabic News Service...');
  
  // In a real application, you might call:
  // ArabicNewsService.instance.start();
  
  // And to stop:
  // ArabicNewsService.instance.stop();
}