// AI Model Download Dialog and Consent UI
// Shows consent dialog before downloading GGUF models

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yallanews/l10n/app_localizations.dart';
import 'package:yallanews/services/ai_service.dart';

class AIModelDownloadDialog extends StatefulWidget {
  final AIModelType model;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const AIModelDownloadDialog({
    Key? key,
    required this.model,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  State<AIModelDownloadDialog> createState() => _AIModelDownloadDialogState();
}

class _AIModelDownloadDialogState extends State<AIModelDownloadDialog> {
  bool _wifiOnly = true;
  bool _autoDownload = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sizeMB = _estimateModelSize(widget.model);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.download_for_offline_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('aiModelDownloadTitle'),
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  widget.model.name,
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('aiModelDownloadDescription'),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _InfoRow(
              icon: Icons.storage_rounded,
              label: l10n.translate('downloadSize'),
              value: '${sizeMB} MB',
            ),
            _InfoRow(
              icon: Icons.memory_rounded,
              label: l10n.translate('ramUsage'),
              value: '${sizeMB + 100} MB',
            ),
            _InfoRow(
              icon: Icons.speed_rounded,
              label: l10n.translate('downloadTime'),
              value: _wifiOnly ? l10n.translate('wifiOnly') : l10n.translate('anyNetwork'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('aiModelFeatures'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FeatureBullet(text: l10n.translate('aiSummaries')),
                  _FeatureBullet(text: l10n.translate('aiTranslation')),
                  _FeatureBullet(text: l10n.translate('aiAskNews')),
                  _FeatureBullet(text: l10n.translate('offlineProcessing')),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.translate('wifiOnly'),
                style: GoogleFonts.inter(fontSize: 14),
              ),
              subtitle: Text(
                l10n.translate('wifiOnlyDescription'),
                style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              value: _wifiOnly,
              onChanged: (v) => setState(() => _wifiOnly = v),
              activeColor: theme.colorScheme.primary,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.translate('autoDownloadUpdates'),
                style: GoogleFonts.inter(fontSize: 14),
              ),
              subtitle: Text(
                l10n.translate('autoDownloadDescription'),
                style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              value: _autoDownload,
              onChanged: (v) => setState(() => _autoDownload = v),
              activeColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: widget.onDecline,
          child: Text(
            l10n.translate('notNow'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded, size: 20),
          onPressed: () {
            widget.onAccept();
            Navigator.of(context).pop();
          },
          label: Text(l10n.translate('downloadModel')),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  int _estimateModelSize(AIModelType model) {
    switch (model) {
      case AIModelType.qwen3_0_6bQ4:
        return 450; // ~450MB for Qwen3-0.6B Q4
      case AIModelType.qwen3_1_7bQ4:
        return 1100; // ~1.1GB for Qwen3-1.7B Q4
      case AIModelType.gemma2_2bQ4:
        return 1600; // ~1.6GB for Gemma2-2B Q4
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.robotoMono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  final String text;

  const _FeatureBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

// Progress Dialog for Model Download
class AIModelDownloadProgressDialog extends StatefulWidget {
  final AIModelType model;
  final Stream<double> progressStream;
  final VoidCallback onCancel;

  const AIModelDownloadProgressDialog({
    Key? key,
    required this.model,
    required this.progressStream,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<AIModelDownloadProgressDialog> createState() => _AIModelDownloadProgressDialogState();
}

class _AIModelDownloadProgressDialogState extends State<AIModelDownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'preparing';
  late StreamSubscription<double> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.progressStream.listen(
      (p) {
        if (mounted) {
          setState(() {
            _progress = p;
            if (p < 10) _status = 'preparing';
            else if (p < 90) _status = 'downloading';
            else if (p < 99) _status = 'verifying';
            else _status = 'complete';
          });
        }
      },
      onDone: () {
        if (mounted && _progress >= 100) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _status = 'error');
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.download_for_offline_rounded,
                color: theme.colorScheme.onPrimaryContainer,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.translate('downloadingModel'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.model.name,
              style: GoogleFonts.robotoMono(
                fontSize: 13,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: LinearProgressIndicator(
                value: _progress / 100.0,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_progress.toStringAsFixed(1)}%',
              style: GoogleFonts.robotoMono(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate(_status),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_status != 'complete' && _status != 'error')
              TextButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.cancel_rounded),
                label: Text(l10n.translate('cancel')),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}