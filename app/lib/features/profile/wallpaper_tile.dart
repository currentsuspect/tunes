import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/data/avatar.dart';
import '../../core/data/settings_store.dart';
import '../../core/theme/tokens.dart';

/// Glass's background photo (BYOB): choose one from the phone, change it or
/// take it away, and set how dim and how soft it sits under the pages.
///
/// The sliders move their own handles while dragged and set the photo when
/// the finger lifts: every page sits on the photo, and redrawing it for every
/// frame of a drag is wasted work.
class WallpaperTile extends StatefulWidget {
  const WallpaperTile({super.key, required this.settings, this.store});

  final SettingsStore settings;

  /// Where the photo is kept; injectable for tests.
  final AvatarStore? store;

  @override
  State<WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<WallpaperTile> {
  late final _store = widget.store ?? AvatarStore.wallpaper();
  double? _dim;
  double? _blur;

  Future<void> _choose() async {
    final s = widget.settings;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final old = s.wallpaperPath;
      final path = await _store.pick();
      // Dismissing the picker keeps the photo you had.
      if (path == null) return;
      await s.setWallpaperPath(path);
      await _store.discard(old);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the photo picker: $e')),
      );
    }
  }

  Future<void> _remove() async {
    final s = widget.settings;
    final old = s.wallpaperPath;
    await s.setWallpaperPath(null);
    await _store.discard(old);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final path = s.wallpaperPath;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md + 2,
        vertical: Space.md - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Thumb(path: path),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background',
                      style: TypeScale.title.copyWith(
                        fontSize: 15,
                        fontVariations: const [FontVariation('wght', 500)],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      path == null
                          ? 'Your own photo behind every page, under the glass.'
                          : 'Your photo, behind every page.',
                      style: TypeScale.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _choose,
                child: Text(path == null ? 'Choose photo' : 'Change'),
              ),
              if (path != null) ...[
                const SizedBox(width: Space.sm),
                TextButton(onPressed: _remove, child: const Text('Remove')),
              ],
            ],
          ),
          if (path != null) ...[
            const SizedBox(height: Space.sm),
            _Slide(
              label: 'Dim',
              value: _dim ?? s.wallpaperDim,
              max: 0.9,
              onChanged: (v) => setState(() => _dim = v),
              onChangeEnd: (v) async {
                await s.setWallpaperDim(v);
                if (mounted) setState(() => _dim = null);
              },
            ),
            _Slide(
              label: 'Blur',
              value: _blur ?? s.wallpaperBlur,
              max: 40,
              onChanged: (v) => setState(() => _blur = v),
              onChangeEnd: (v) async {
                await s.setWallpaperBlur(v);
                if (mounted) setState(() => _blur = null);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return Container(
      width: 44,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Tones.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Tones.hairline),
      ),
      child: p == null
          ? Icon(Icons.wallpaper_rounded, color: Tones.textMuted, size: 20)
          : Image.file(
              File(p),
              fit: BoxFit.cover,
              cacheWidth: 132,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 44, child: Text(label, style: TypeScale.caption)),
      Expanded(
        child: Slider(
          value: value.clamp(0, max),
          max: max,
          label: label,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    ],
  );
}
