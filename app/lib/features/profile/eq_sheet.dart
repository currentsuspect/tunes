import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/settings_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/eq.dart';

/// Settings > Listening > Headphone EQ: pick a profile, turn it off, or paste
/// one in (AutoEQ / squig.link / Wavelet / Equalizer APO text).
Future<void> showEqSheet(BuildContext context, SettingsStore s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tones.surface,
    showDragHandle: true,
    builder: (_) => _EqSheet(settings: s),
  );
}

class _EqSheet extends StatelessWidget {
  const _EqSheet({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final active = settings.eqProfile?.id;
        final custom = {for (final p in settings.eqCustom) p.id};
        Widget row({
          required String title,
          String? detail,
          required bool on,
          required VoidCallback onTap,
          VoidCallback? onDelete,
        }) => ListTile(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          leading: Icon(
            on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: on ? Tones.primary : Tones.textMuted,
          ),
          title: Text(title, style: TypeScale.title),
          subtitle: detail == null
              ? null
              : Text(detail, style: TypeScale.caption),
          trailing: onDelete == null
              ? null
              : IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onDelete,
                ),
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Text('Headphone EQ', style: TypeScale.heading),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Text(
                    'Corrects how a pair of headphones sounds, for everything '
                    'that plays on this device.',
                    style: TypeScale.caption,
                  ),
                ),
                row(
                  title: 'Off',
                  on: active == null,
                  onTap: () => settings.setEqActive(null),
                ),
                for (final p in settings.eqProfiles)
                  row(
                    title: p.name,
                    detail:
                        p.note ??
                        '${p.filters.length} filters, preamp ${p.preamp} dB',
                    on: active == p.id,
                    onTap: () => settings.setEqActive(p.id),
                    onDelete: custom.contains(p.id)
                        ? () async {
                            if (active == p.id) {
                              await settings.setEqActive(null);
                            }
                            await settings.setEqCustom([
                              for (final c in settings.eqCustom)
                                if (c.id != p.id) c,
                            ]);
                          }
                        : null,
                  ),
                ListTile(
                  leading: Icon(Icons.add_rounded, color: Tones.primary),
                  title: Text('Paste an EQ', style: TypeScale.title),
                  subtitle: Text(
                    'From AutoEQ, squig.link, Wavelet or Equalizer APO.',
                    style: TypeScale.caption,
                  ),
                  onTap: () => _paste(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _paste(BuildContext context) async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (!context.mounted) return;
    final text = TextEditingController(
      text: parseEqText(clip, id: '', name: '') != null ? clip : '',
    );
    final name = TextEditingController();
    String? error;
    final saved = await showDialog<EqProfile>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Paste an EQ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name, e.g. Aria 2: Neutral',
                  ),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: text,
                  minLines: 5,
                  maxLines: 10,
                  style: TypeScale.mono,
                  decoration: const InputDecoration(
                    hintText:
                        'Preamp: -4.8 dB\n'
                        'Filter 1: ON LSC Fc 97 Hz Gain -6.0 dB Q 0.71\n'
                        '...',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    error!,
                    style: TypeScale.caption.copyWith(color: Tones.warn),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final n = name.text.trim().isEmpty ? 'My EQ' : name.text.trim();
                final p = parseEqText(
                  text.text,
                  id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                  name: n,
                );
                if (p == null) {
                  setState(
                    () => error =
                        'No filters found. Lines look like '
                        '"Filter 1: ON PK Fc 1000 Hz Gain -2 dB Q 1".',
                  );
                  return;
                }
                Navigator.pop(c, p);
              },
              child: const Text('Save and use'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    name.dispose();
    if (saved == null) return;
    await settings.setEqCustom([...settings.eqCustom, saved]);
    await settings.setEqActive(saved.id);
  }
}
