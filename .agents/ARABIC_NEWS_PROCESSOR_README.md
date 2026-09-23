# Arabic News Processing System

This is a modular, event-driven system for processing Arabic news sources locally, without relying on external APIs or cloud services.

## Features

- **Local Processing Only**: No external APIs or cloud services required
- **Resource Efficient**: Optimized for low CPU, RAM, bandwidth, and storage usage
- **Modular Architecture**: 10-stage processing pipeline
- **Continuous Operation**: Designed for 24/7 operation
- **Easy Extensibility**: Simple to add new Arabic news sources
- **High Data Quality**: Advanced deduplication and event detection

## Processing Pipeline

1. **Source Manager** - Manages configurable list of trusted Arabic news websites
2. **Smart Scheduler** - Dynamically adjusts crawl frequency based on priority and activity
3. **Lightweight Fetcher** - Fetches only HTML/RSS, avoids unnecessary resources
4. **Change Detection** - Uses content hashes/HTTP headers to skip unchanged content
5. **Content Extraction** - Removes boilerplate, extracts key article information
6. **Arabic NLP Processing** - Normalizes text, extracts entities, dates, keywords
7. **Classification** - Assigns categories (Politics, Economy, Technology, Sports, etc.)
8. **Duplicate & Event Detection** - Groups related articles, identifies duplicates
9. **Local Storage & Search** - Stores articles with full-text and entity search
10. **Monitoring** - Logs crawl status, errors, performance metrics

## Installation

Add this package to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  arabic_news_processor:
    path: path/to/this/package
```

Or if published:
```yaml
dependencies:
  arabic_news_processor: ^1.0.0
```

## Usage

### Basic Usage

```dart
import 'package:arabic_news_processor/arabic_news_processor.dart';

// Start the processor
await ArabicNewsProcessor.instance.start();

// The processor will automatically:
// 1. Load all Arabic news sources from the database
// 2. Schedule crawling based on source priority
// 3. Process articles through the 10-stage pipeline
// 4. Store results in the local database

// Stop the processor when needed
await ArabicNewsProcessor.instance.stop();
```

### Manual Control

```dart
// Manually trigger a crawl for a specific source
final source = NewsSource(
  id: 1,
  country: 'Saudi Arabia',
  countryCode: 'SA',
  name: 'Al Riyadh',
  url: 'https://www.alriyadh.com',
  category: 'general_news',
  type: 'newspaper',
  language: 'ar',
  rank: 3,
);

await ArabicNewsProcessor.instance.crawlSourceNow(source);

// Get processing statistics
final stats = await ArabicNewsProcessor.instance.getStatistics();
print('Processed ${stats['totalArticles']} articles from ${stats['activeSources']} sources');

// Listen to logs
ArabicNewsProcessor.instance.logStream.listen((log) {
  print('Processing System

This is a modular, event-driven system for processing Arabic news sources locally, without relying on external APIs or cloud services.

## Features

- **Local Processing Only**: No external APIs or cloud services required
- **Resource Efficient**: Optimized for low CPU, RAM, bandwidth, and storage usage
- **Modular Architecture**: 10-stage processing pipeline
- **Continuous Operation**: Designed for 24/7 operation
- **Easy Extensibility**: Simple to add new Arabic news sources
- **High Data Quality**: Advanced deduplication and event detection

## Processing Pipeline

1. **Source Manager** - Manages configurable list of trusted Arabic news websites
2. **Smart Scheduler** - Dynamically adjusts crawl frequency based on priority and activity
3. **Lightweight Fetcher** - Fetches only HTML/RSS, avoids unnecessary resources
4. **Change Detection** - Uses content hashes/HTTP headers to skip unchanged content
5. **Content Extraction** - Removes boilerplate, extracts key article information
6. **Arabic NLP Processing** - Normalizes text, extracts entities, dates, keywords
7. **Classification** - Assigns categories (Politics, Economy, Technology, Sports, etc.)
8. **Duplicate & Event Detection** - Groups related articles, identifies duplicates
9. **Local Storage & Search** - Stores articles with full-text and entity search
10. **Monitoring** - Logs crawl status, errors, performance metrics

## Installation

Add this package to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  arabic_news_processor:
    path: path/to/this/package
```

Or if published:
```yaml
dependencies:
  arabic_news_processor: ^1.0.0
```

## Usage

### Basic Usage

```dart
import 'package:arabic_news_processor/arabic_news_processor.dart';

// Start the processor
await ArabicNewsProcessor.instance.start();

// The processor will automatically:
// 1. Load all Arabic news sources from the database
// 2. Schedule crawling based on source priority
// 3. Process articles through the 10-stage pipeline
// 4. Store results in the local database

// Stop the processor when needed
await ArabicNewsProcessor.instance.stop();
```

### Manual Control

```dart
// Manually trigger a crawl for a specific source
final source = NewsSource(
  id: 1,
  country: 'Saudi Arabia',
  countryCode: 'SA',
  name: 'Al Riyadh',
  url: 'https://www.alriyadh.com',
  category: 'general_news',
  type: 'newspaper',
  language: 'ar',
  rank: 3,
);

await ArabicNewsProcessor.instance.crawlSourceNow(source);

// Get processing statistics
final stats = await ArabicNewsProcessor.instance.getStatistics();
print('Processed ${stats['totalArticles']} articles from ${stats['activeSources']} sources');

// Listen to processing logs
ArabicNewsProcessor.instance.logStream.listen((log) {
  print('Processing log: $log');
});
```

## Architecture

The system consists of several key components:

### ArabicNewsProcessor
The main processing engine that implements the 10-stage pipeline. It operates as a singleton and manages:
- Source scheduling based on priority
- Article crawling and processing
- Resource management and throttling
- Event-driven updates via streams

### NewsSource Model
Represents an Arabic news source with metadata:
- Country, name, URL, category, language
- Priority ranking for scheduling
- Type (newspaper, digital news, TV news, etc.)

### NewsModel
Represents a processed news article with:
- Core content (title, summary, content, image)
- Metadata (author, publish date, source URL)
- NLP results (keywords, entities, sentiment)
- Classification (category, event type, subcategory)
- Structural data and relationships

### Database Layer
Uses SQLite via sqflite for local storage:
- Sources table for news source configuration
- Crawled articles table for processed content
- Efficient querying and indexing
- Automatic seeding from JSON configuration

## Configuration

Arabic news sources are configured in `assets/news_sources_ar.json` with this structure:

```json
{
  "countries": [
    {
      "country": "Saudi Arabia",
      "country_code": "SA",
      "sources": [
        {
          "name": "Al Riyadh",
          "url": "https://www.alriyadh.com",
          "category": "general_news",
          "type": "newspaper",
          "language": ["ar"],
          "rank": 3
        }
      ]
    }
  ]
}
```

## Performance Characteristics

- **Memory Usage**: Typically < 100MB RAM during operation
- **CPU Usage**: Minimal when idle, spikes during crawling (configurable)
- **Storage**: Efficient SQLite storage, automatic cleanup policies
- **Bandwidth**: Only downloads necessary HTML content, skips assets
- **Latency**: Configurable crawl intervals (5 minutes to 1 hour based on priority)

## Extending the System

### Adding New Sources
1. Add the source to `assets/news_sources_ar.json`
2. Restart the application or refresh sources
3. The system will automatically begin processing the new source

### Customizing Processing
- Modify `arabic_news_processor.dart` to adjust pipeline stages
- Extend `news_intelligence.dart` for custom classification rules
- Update `arabic_normalizer.dart` for specialized Arabic text processing
- Enhance `_extractKeywordsFromText` for better keyword extraction

## Running as a Service

For production deployment as a background service:

```bash
# Run in background (Linux/macOS)
dart run arabic_news_processor.dart &

# Run as a service (Windows)
# Create a Windows Service using nssm or similar

# Docker deployment
FROM dart:stable
COPY . /app
WORKDIR /app
RUN dart compile exe bin/arabic_news_processor.dart -o bin/app
CMD ["./bin/app"]
```

## Monitoring and Logging

The system provides extensive logging through a stream interface:

```dart
ArabicNewsProcessor.instance.logStream.listen((log) {
  // Handle log messages (display, forward to logging service, etc.)
  print(log);
});
```

Log categories include:
- `[SYSTEM]` - System-level events
- `[PIPELINE]` - Pipeline stage progress
- `[SOURCE-MANAGER]` - Source management operations
- `[FETCHER]` - Content fetching operations
- `[CHANGE-DETECTION]` - Change detection results
- `[EXTRACTION]` - Content extraction stats
- `[NLP]` - Natural language processing
- `[CLASSIFICATION]` - Article classification
- `[DEDUPLICATION]` - Duplicate detection results
- `[STORAGE]` - Database operations
- `[MONITORING]` - Performance metrics
- `[ERROR]` - Error conditions
- `[WARNING]` - Non-critical issues
- `[INFO]` - Informational messages

## Requirements

- Dart SDK 3.0+
- Flutter 3.0+ (for mobile/desktop/web deployment)
- SQLite support (included via sqflite)
- Internet connectivity (for fetching news sources)

## Limitations

- Designed primarily for Arabic language content
- Requires periodic restarts for very long-term operation (days/weeks)
- Dependent on the quality of source HTML structure
- May require adjustment for sites with heavy JavaScript reliance
- Storage grows over time; implement archival policies for long-term deployments

## License

This project is proprietary and confidential. All rights reserved.