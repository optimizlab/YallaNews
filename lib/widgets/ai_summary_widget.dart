// AI Summary Widget for Article Detail Page
// Displays AI-generated summary with loading states and actions

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/ai_service.dart' hide YallaLanguageExt;
import '../services/ai_language_ext.dart';
import '../database/news_db.dart' show NewsDatabase;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

class AISummaryWidget extends StatefulWidget {
  final NewsModel article;
  final VoidCallback? onRegenerate;
  final VoidCallback? onTranslate;
  final bool showActions;

  const AISummaryWidget({
    super.key,
    required this.article,
    this.onRegenerate,
    this.onTranslate,
    this.showActions = true,
  });

  @override
  State<AISummaryWidget> createState() => _AISummaryWidgetState();
}

class _AISummaryWidgetState extends State<AISummaryWidget> {
  final AIService _aiService = AIService.instance;
  String _summary = '';
  bool _isGenerating = false;
  String? _error;
  bool _hasAttemptedGeneration = false;

  @override
  void initState() {
    super.initState();
    _loadExistingSummary();
  }

  Future<void> _loadExistingSummary() async {
    try {
      final db = await NewsDatabase.instance.database;
      final result = await db.query(
        'ai_summaries',
        where: 'article_url = ?',
        whereArgs: [widget.article.url],
        limit: 1,
      );
      if (result.isNotEmpty && mounted) {
        setState(() {
          _summary = result.first['summary'] as String? ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _generateSummary() async {
    if (!_aiService.isReady) {
      setState(() => _error = 'AI model not ready');
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final summary = await _aiService.summarize(
        title: widget.article.title,
        content: widget.article.content,
        language: widget.article.language.isEmpty ? 'en' : widget.article.language,
        maxLength: 150,
      );

      // Save to database
      final db = await NewsDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('ai_summaries', {
        'id': widget.article.urlHash.isEmpty 
            ? widget.article.url.hashCode.toString() 
            : widget.article.urlHash,
        'article_url': widget.article.url,
        'model_version': _aiService.currentModel.id,
        'summary': summary,
        'tokens_used': 0,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (mounted) {
        setState(() {
          _summary = summary;
          _isGenerating = false;
          _hasAttemptedGeneration = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!_hasAttemptedGeneration && _summary.isEmpty) {
      // Show generate button
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.translate('aiSummary'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('aiSummaryDescription'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(l10n.translate('generateSummary')),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isGenerating) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.translate('generatingSummary'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('generatingSummaryDescription'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null && _summary.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.translate('summaryFailed'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.translate('tryAgain')),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('aiSummary'),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      l10n.translate('aiSummaryBadge'),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showActions) ...[
                IconButton(
                  onPressed: _generateSummary,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: l10n.translate('regenerateSummary'),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                if (widget.onTranslate != null)
                  IconButton(
                    onPressed: widget.onTranslate,
                    icon: const Icon(Icons.translate_rounded, size: 20),
                    tooltip: l10n.translate('translate'),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            _summary,
            style: GoogleFonts.outfit(
              fontSize: 14,
              height: 1.7,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// AI Translation Widget
class AITranslationWidget extends StatefulWidget {
  final NewsModel article;
  final String sourceLanguage;
  final List<String> targetLanguages;

  const AITranslationWidget({
    super.key,
    required this.article,
    required this.sourceLanguage,
    this.targetLanguages = const ['ar', 'en', 'fr'],
  });

  @override
  State<AITranslationWidget> createState() => _AITranslationWidgetState();
}

class _AITranslationWidgetState extends State<AITranslationWidget> {
  final AIService _aiService = AIService.instance;
  final Map<String, String> _translations = {};
  String _selectedTargetLang = 'ar';
  bool _isTranslating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExistingTranslations();
  }

  Future<void> _loadExistingTranslations() async {
    try {
      final db = await NewsDatabase.instance.database;
      final results = await db.query(
        'translations',
        where: 'article_url = ?',
        whereArgs: [widget.article.url],
      );
      if (results.isNotEmpty && mounted) {
        setState(() {
          for (final row in results) {
            _translations[row['target_lang'] as String] = row['translated_content'] as String? ?? '';
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _translate() async {
    if (!_aiService.isReady) {
      setState(() => _error = 'AI model not ready');
      return;
    }

    setState(() {
      _isTranslating = true;
      _error = null;
    });

    try {
      final translation = await _aiService.translate(
        text: widget.article.content,
        sourceLang: YallaLanguageExt.fromString(widget.sourceLanguage),
        targetLang: YallaLanguageExt.fromString(_selectedTargetLang),
      );

      // Save to database
      final db = await NewsDatabase.instance.database;
      await db.insert('translations', {
        'id': '${widget.article.urlHash}_$_selectedTargetLang',
        'article_url': widget.article.url,
        'target_lang': _selectedTargetLang,
        'translated_title': '', // Would need title translation
        'translated_content': translation,
        'model_version': _aiService.currentModel.id,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (mounted) {
        setState(() {
          _translations[_selectedTargetLang] = translation;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.translate_rounded,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.translate('translation'),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedTargetLang,
                  decoration: InputDecoration(
                    labelText: l10n.translate('targetLanguage'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: widget.targetLanguages.map((lang) {
                    return DropdownMenuItem(
                      value: lang,
                      child: Text(YallaLanguageExt.fromString(lang).displayName),
                    );
                  }).toList(),
                  onChanged: _isTranslating ? null : (val) {
                    if (val != null) setState(() => _selectedTargetLang = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isTranslating ? null : _translate,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.translate_rounded, size: 18),
                label: Text(_isTranslating ? l10n.translate('translating') : l10n.translate('translate')),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.outfit(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_translations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.translate('availableTranslations'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _translations.entries.map((entry) {
                return ActionChip(
                  label: Text(YallaLanguageExt.fromString(entry.key).displayName),
                  onPressed: () {
                    _showTranslationDialog(entry.value);
                  },
                  backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showTranslationDialog(String translation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    YallaLanguageExt.fromString(_selectedTargetLang).displayName,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                translation,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}