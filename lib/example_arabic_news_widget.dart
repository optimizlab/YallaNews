import 'dart:async';
import 'package:flutter/material.dart';
import 'arabic_news_processor.dart';
import 'models/news_model.dart';
import 'database/news_db.dart';

/// Example widget showing how to use the Arabic News Processor in a Flutter app
class ArabicNewsExample extends StatefulWidget {
  const ArabicNewsExample({super.key});

  @override
  State<ArabicNewsExample> createState() => _ArabicNewsExampleState();
}

class _ArabicNewsExampleState extends State<ArabicNewsExample> {
  bool _isProcessorRunning = false;
  List<NewsModel> _recentArticles = [];
  String _statusText = 'Ready to start';
  StreamSubscription<String>? _logSubscription;

  @override
  void initState() {
    super.initState();
    _checkProcessorStatus();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkProcessorStatus() async {
    final status = await ArabicNewsProcessor.instance.getStatistics();
    setState(() {
      _isProcessorRunning = status['isRunning'] ?? false;
      _statusText = _isProcessorRunning ? 'Processor Running' : 'Processor Stopped';
    });
  }

  Future<void> _toggleProcessor() async {
    setState(() {
      _statusText = _isProcessorRunning ? 'Stopping...' : 'Starting...';
    });

    try {
      if (_isProcessorRunning) {
        await ArabicNewsProcessor.instance.stop();
      } else {
        await ArabicNewsProcessor.instance.start();
        
        // Subscribe to logs for processing logs
        _logSubscription = ArabicNewsProcessor.instance.logStream.listen((log) {
          debugPrint(log);
        });
      }
    
      _statusText = _isProcessorRunning ? 'Running' : 'Stopped';
    } catch (e) {
      setState(() {
        _statusText = 'Error: $e';
      });
    }
    
    await _checkProcessorStatus();
  }

  Future<void> _refreshArticles() async {
    setState(() {
      _statusText = 'Fetching recent articles...';
    });
    
    try {
      // Get recent articles from database
      final articles = await NewsDatabase.instance.getAllArticles(limit: 10);
      setState(() {
        _recentArticles = articles;
        _statusText = 'Found ${articles.length} recent articles';
      });
    } catch (e) {
      setState(() {
        _statusText = 'Error fetching articles: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arabic News Processor Example'),
        actions: [
          IconButton(
            icon: Icon(_isProcessorRunning ? Icons.stop : Icons.play_arrow),
            onPressed: _toggleProcessor,
            tooltip: _isProcessorRunning ? 'Stop Processor' : 'Start Processor',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Processor Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 16,
                        color: _isProcessorRunning ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Articles'),
                    onPressed: _refreshArticles,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Show Statistics'),
                    onPressed: _showStatistics,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Recent Articles
            Expanded(
              child: _recentArticles.isEmpty
                  ? const Center(
                      child: Text('No articles yet. Start the processor to collect news.'),
                    )
                  : ListView.builder(
                      itemCount: _recentArticles.length,
                      itemBuilder: (context, index) {
                        final article = _recentArticles[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: ListTile(
                            leading: article.imageUrl.startsWith('http')
                                ? Image.network(
                                    article.imageUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.newspaper),
                            title: Text(
                              article.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Category: ${article.category}'),
                                Text('Sentiment: ${article.sentiment.toStringAsFixed(2)}'),
                                Text('Published: ${article.publishDate}'),
                              ],
                            ),
                            onTap: () => _showArticleDetails(article),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStatistics() async {
    final stats = await ArabicNewsProcessor.instance.getStatistics();
    final processorStatus = await ArabicNewsProcessor.instance.getStatus();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Processing Statistics'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Processor Running: ${processorStatus['isRunning']}'),
              Text('Active Sources: ${processorStatus['activeSources']}'),
              Text('Total Articles: ${stats['totalArticles']}'),
              Text('Sources Processed: ${stats['activeSources']}'),
              Text('Last Updated: ${stats['lastUpdated']}'),
              if (stats.containsKey('error'))
                Text('Error: ${stats['error']}', style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showArticleDetails(NewsModel article) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(article.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (article.imageUrl.startsWith('http'))
                Image.network(
                  article.imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              const SizedBox(height: 12),
              Text('Category: ${article.category}'),
              Text('Sentiment: ${article.sentiment.toStringAsFixed(2)}'),
              Text('Published: ${article.publishDate}'),
              if (article.author.isNotEmpty) Text('Author: ${article.author}'),
              const SizedBox(height: 12),
              const Text('Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(article.summary),
              const SizedBox(height: 12),
              const Text('Content:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(article.content.length > 500 ? '${article.content.substring(0, 500)}...' : article.content),
              if (article.keywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Keywords:', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  children: article.keywords.map((k) => Chip(label: Text(k))).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}