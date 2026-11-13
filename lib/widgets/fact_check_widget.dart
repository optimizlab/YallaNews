// Fact-Check Verification Widget
// Shows fact-check badges and sources for article claims

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/ai_service.dart';

class FactCheckWidget extends StatefulWidget {
  final NewsModel article;
  final bool autoCheck;

  const FactCheckWidget({
    super.key,
    required this.article,
    this.autoCheck = true,
  });

  @override
  State<FactCheckWidget> createState() => _FactCheckWidgetState();
}

class _FactCheckWidgetState extends State<FactCheckWidget> {
  List<Map<String, dynamic>> _factChecks = [];
  bool _isChecking = false;
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCheck) {
      _loadExistingFactChecks();
    }
  }

  Future<void> _loadExistingFactChecks() async {
    if (widget.autoCheck) {
      await _verifyClaims();
    }
  }

  Future<void> _verifyClaims() async {
    if (!_hasChecked) {
      setState(() => _isChecking = true);
    }

    try {
      final claims = _extractClaims(widget.article.content);
      
      final factChecks = <Map<String, dynamic>>[];
      
      final aiService = AIService.instance;
      final aiReady = aiService.isReady;

      for (final claim in claims.take(3)) {
        String verdict = 'unproven';
        String explanation = 'Claim extracted from article. AI verification unavailable.';

        if (aiReady) {
          final result = await AIService.instance.generate(
            prompt: 'Fact-check this claim: "$claim". Provide a verdict (True/False/Misleading/Unproven) with a brief explanation and cite sources if possible.',
            maxTokens: 200,
            temperature: 0.1,
          );
          
          final text = result['text'] as String? ?? '';
          verdict = _parseVerdict(text);
          explanation = text;
        }

        factChecks.add({
          'claim': claim,
          'verdict': verdict,
          'explanation': explanation,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }

      if (mounted) {
        setState(() {
          _factChecks = factChecks;
          _isChecking = false;
          _hasChecked = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  List<String> _extractClaims(String content) {
    final sentences = content.split(RegExp(r'[.!?]\s+'));
    final claims = <String>[];
    
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.length > 30 && trimmed.length < 200) {
        if (RegExp(r'\b(is|are|was|were|has|have|had|will|would|could|should|must)\b', caseSensitive: false).hasMatch(trimmed)) {
          claims.add(trimmed);
        }
      }
    }
    
    return claims.take(5).toList();
  }

  String _parseVerdict(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('true') || lower.contains('accurate') || lower.contains('correct')) {
      return 'true';
    } else if (lower.contains('false') || lower.contains('incorrect') || lower.contains('wrong')) {
      return 'false';
    } else if (lower.contains('misleading') || lower.contains('partial')) {
      return 'misleading';
    } else if (lower.contains('unproven') || lower.contains('unverified') || lower.contains('insufficient')) {
      return 'unproven';
    }
    return 'unproven';
  }

  Color _getVerdictColor(BuildContext context, String verdict) {
    final theme = Theme.of(context);
    switch (verdict) {
      case 'true':
        return const Color(0xFF2E7D32);
      case 'false':
        return const Color(0xFFC62828);
      case 'misleading':
        return const Color(0xFFF57F17);
      case 'unproven':
        return const Color(0xFF1565C0);
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  IconData _getVerdictIcon(String verdict) {
    switch (verdict) {
      case 'true':
        return Icons.check_circle_rounded;
      case 'false':
        return Icons.cancel_rounded;
      case 'misleading':
        return Icons.warning_amber_rounded;
      case 'unproven':
        return Icons.help_outline_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _getVerdictLabel(BuildContext context, String verdict) {
    final l10n = AppLocalizations.of(context);
    switch (verdict) {
      case 'true':
        return l10n.translate('factCheckTrue');
      case 'false':
        return l10n.translate('factCheckFalse');
      case 'misleading':
        return l10n.translate('factCheckMisleading');
      case 'unproven':
        return l10n.translate('factCheckUnproven');
      default:
        return l10n.translate('factCheckUnproven');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!_hasChecked && !_isChecking) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('factCheck'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('factCheckDescription'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _verifyClaims,
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: Text(l10n.translate('verifyClaims')),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
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

    if (_isChecking) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
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
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.translate('verifyingClaims'),
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
              l10n.translate('verifyingClaimsDescription'),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_factChecks.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.translate('noClaimsFound'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fact_check_rounded,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.translate('factCheck'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              if (_factChecks.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_factChecks.length} ${l10n.translate('claimsChecked')}',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ..._factChecks.map((fc) => _buildFactCheckCard(context, fc)),
        ],
      ),
    );
  }

  Widget _buildFactCheckCard(BuildContext context, Map<String, dynamic> fc) {
    final theme = Theme.of(context);
    final verdict = fc['verdict'] as String;
    final color = _getVerdictColor(context, verdict);
    final icon = _getVerdictIcon(verdict);
    final label = _getVerdictLabel(context, verdict);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fc['claim'] as String? ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fc['explanation'] as String? ?? '',
            style: GoogleFonts.outfit(
              fontSize: 12,
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}