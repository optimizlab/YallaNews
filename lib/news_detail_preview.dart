import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/news_model.dart';

String _stripHtmlTags(String text) {
  if (text.isEmpty) return text;
  return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

String _getSentimentLabel(double sentiment) {
  if (sentiment >= 0.3) return 'إيجابي';
  if (sentiment <= -0.3) return 'سلبي';
  return 'محايد';
}

/// Enhanced NewsDetailPreview showing how all requested information would be displayed
class NewsDetailPreview extends StatelessWidget {
  final NewsModel article;

  const NewsDetailPreview({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with category, date, and AUTHOR
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  article.category.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                article.author.isNotEmpty ? article.author : 'Unknown Author',
                style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                article.publishDate,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Title
          Text(
            article.title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          
          // Image placeholder
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.image,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          
           // Summary
           Text(
             "ملخص تنفيذي لـ: ${article.title.split(' ').take(8).join(' ')}${article.title.split(' ').length > 8 ? '...' : ''}",
             style: GoogleFonts.outfit(
               fontSize: 12,
               fontWeight: FontWeight.bold,
               color: Theme.of(context).colorScheme.onSurfaceVariant,
             ),
           ),
           const SizedBox(height: 8),
           Text(
             _stripHtmlTags(article.summary),
             style: GoogleFonts.outfit(
               fontSize: 14,
               fontStyle: FontStyle.italic,
               color: Theme.of(context).colorScheme.onSurfaceVariant,
               height: 1.6,
             ),
           ),
          const SizedBox(height: 20),
          
          // NLP Results: Sentiment
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: article.sentiment > 0.3
                      ? Theme.of(context).colorScheme.tertiary
                      : article.sentiment < -0.3
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "مؤشر المشاعر:",
                style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                "${_getSentimentLabel(article.sentiment)} (${article.sentiment.toStringAsFixed(2)})",
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: article.sentiment > 0.3
                      ? Theme.of(context).colorScheme.tertiary
                      : article.sentiment < -0.3
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              width: double.infinity,
              child: LinearProgressIndicator(
                value: (article.sentiment + 1) / 2,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: article.sentiment > 0.3
                    ? Theme.of(context).colorScheme.tertiary
                    : article.sentiment < -0.3
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Entities Section
          if ((article.entities ?? []).isNotEmpty) ...[
            Text(
              "الكائنات المعرفة:",
              style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (article.entities ?? []).map((entity) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    entity,
                    style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          
          // Keywords
          Text(
            "الكلمات المفتاحية المستخرجة:",
            style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: article.keywords.map((kw) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Text(
                  "#$kw",
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          // Source URL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    article.url,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}