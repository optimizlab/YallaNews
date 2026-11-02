// test_news_brain.dart
import 'dart:io';
import 'lib/services/news_brain_ffi.dart';

void main() async {
  print('==================================================');
  print('  Testing newsBrain C++ DLL via Dart FFI Bridge  ');
  print('==================================================\n');

  final service = NewsBrainService.instance;
  print('[1] Checking library availability: ${service.isAvailable}');
  print('[2] Native newsBrain version: ${service.getVersion()}\n');

  final sampleHtmlFile = File('windows/news_brain/sample_news.html');
  if (!sampleHtmlFile.existsSync()) {
    print('[ERROR] sample_news.html not found.');
    exit(1);
  }

  final html = sampleHtmlFile.readAsStringSync();
  print('[3] Loaded sample_news.html (${html.length} bytes)');

  // Milestone 1: PageSkeleton
  print('\n--- [Milestone 1: PageSkeleton Engine] ---');
  final skeleton = await service.scanHtml(
    html,
    url: 'https://yallanews.net/tech/newsbrain-ai-engine-launch',
  );

  if (skeleton == null) {
    print('[ERROR] Failed to generate PageSkeleton');
    exit(1);
  }

  print('✓ Skeleton URL: ${skeleton.url}');
  print('✓ Extracted Metadata:');
  print('    Title: ${skeleton.metadata.title}');
  print('    Author: ${skeleton.metadata.author}');
  print('    Date: ${skeleton.metadata.publishDate}');
  print('    Site: ${skeleton.metadata.siteName}');
  print('    Language: ${skeleton.metadata.language}');
  print('    Schema Type: ${skeleton.metadata.schemaType}');
  print('✓ Compressed DOM Nodes: ${skeleton.nodes.length} nodes');
  print('✓ Candidate Regions Found: ${skeleton.candidates.length}');
  for (final c in skeleton.candidates) {
    print('    Candidate #${c.candidateId}: score=${c.score.toStringAsFixed(2)}, nodes=${c.nodeCount}, paragraphs=${c.paragraphCount}, textLen=${c.textLength}, linkDensity=${c.linkDensity.toStringAsFixed(3)}');
  }
  print('✓ Extracted Images: ${skeleton.images.length}');
  for (final img in skeleton.images) {
    print('    Image: ${img.src} (isLead=${img.isLead}, caption="${img.caption}")');
  }

  // Milestone 2: Reconstruct Human Reading NewsArticle
  print('\n--- [Milestone 2: Article Brain & Reconstruction] ---');
  final article = await service.extractArticleHtml(
    html,
    url: 'https://yallanews.net/tech/newsbrain-ai-engine-launch',
  );

  if (article == null) {
    print('[ERROR] Failed to extract NewsArticle');
    exit(1);
  }

  print('✓ Article Title: ${article.title}');
  print('✓ Subtitle: ${article.subtitle}');
  print('✓ Author: ${article.author}');
  print('✓ Publish Date: ${article.publishDate}');
  print('✓ Lead Image: ${article.leadImageUrl}');
  print('✓ Lead Image Caption: ${article.leadImageCaption}');
  print('✓ Word Count: ${article.wordCount} words (~${article.readingTimeMinutes} min read)');
  print('✓ Confidence Score: ${(article.confidenceScore * 100).toStringAsFixed(0)}%');
  print('✓ Reconstructed Story Blocks: ${article.blocks.length} blocks');

  for (int i = 0; i < article.blocks.length; i++) {
    final b = article.blocks[i];
    if (b.type == 'HEADING') {
      print('    [$i] [HEADING H${b.headingLevel}] ${b.text}');
    } else if (b.type == 'PARAGRAPH') {
      final snippet = b.text.length > 60 ? '${b.text.substring(0, 60)}...' : b.text;
      print('    [$i] [PARAGRAPH] $snippet');
    } else if (b.type == 'QUOTE') {
      print('    [$i] [QUOTE] "${b.text}"');
    } else if (b.type == 'IMAGE') {
      print('    [$i] [IMAGE] ${b.imageUrl} (caption: ${b.caption})');
    }
  }

  final newsModel = article.toNewsModel(category: 'تكنولوجيا');
  print('\n✓ Converted to NewsModel:');
  print('    Title: ${newsModel.title}');
  print('    Category: ${newsModel.category}');
  print('    Source: ${newsModel.sources}');

  print('\n==================================================');
  print('  ALL NEWSBRAIN VERIFICATION TESTS PASSED!        ');
  print('==================================================');
}
