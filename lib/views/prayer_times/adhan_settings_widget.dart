import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/prayer/adhan_service.dart';
import '../../l10n/app_localizations.dart';

/// Standalone muezzin / adhan voice selector usable from the global settings.
class AdhanSettingsWidget extends StatefulWidget {
  const AdhanSettingsWidget({super.key});

  @override
  State<AdhanSettingsWidget> createState() => _AdhanSettingsWidgetState();
}

class _AdhanSettingsWidgetState extends State<AdhanSettingsWidget> {
  String _selectedMuezzin = 'makkah';
  String? _playingMuezzin;
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _stateSubscription;

  @override
  void initState() {
    super.initState();
    AdhanService.instance.init().then((_) {
      if (mounted) setState(() => _selectedMuezzin = AdhanService.instance.selectedMuezzin);
    });
    _stateSubscription = AdhanService.instance.playerState.listen((state) {
      if (!mounted) return;
      final playing = state == PlayerState.playing;
      if (_isPlaying != playing) {
        setState(() => _isPlaying = playing);
      }
      if (!playing && _playingMuezzin != null) {
        setState(() => _playingMuezzin = null);
      }
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _togglePreview(String key) async {
    if (_playingMuezzin == key && _isPlaying) {
      await AdhanService.instance.stopAdhan();
      if (mounted) setState(() => _playingMuezzin = null);
      return;
    }
    setState(() {
      _selectedMuezzin = key;
      _playingMuezzin = key;
    });
    await AdhanService.instance.setMuezzin(key);
    await AdhanService.instance.previewMuezzin(key);
    if (!mounted) return;
    setState(() {
      _isPlaying = true;
      _playingMuezzin = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.translate('adhanSound'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: AdhanService.muezzins.entries.map((entry) {
                final key = entry.key;
                final isPlaying = _playingMuezzin == key && _isPlaying;
                return RadioListTile<String>(
                  value: key,
                  groupValue: _selectedMuezzin,
                  onChanged: (val) {
                    if (val == null) return;
                    _togglePreview(val);
                  },
                  title: Text(
                    l10n.translate('muezzin_$key'),
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  secondary: IconButton(
                    icon: isPlaying
                        ? const Icon(Icons.stop_circle_rounded)
                        : const Icon(Icons.play_circle_outline_rounded),
                    tooltip: l10n.translate('preview'),
                    onPressed: () => _togglePreview(key),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
