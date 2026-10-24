import 'package:flutter/material.dart';

import '../../core/lyrics/adlib_kinds.dart';
import '../../core/lyrics/lyric_fx.dart';
import '../../core/lyrics/word_fx.dart';
import '../../core/theme/tokens.dart';

/// Opens the Lyric Center for one stored line: pick a word or an ad-lib,
/// then its look and its moment. Estimates (an ad-lib at the end of a line,
/// a picture word by its share of it, a kind read from its spelling) are
/// sometimes off; this is where they are put right, by ear, and the fix is
/// saved into the lyric for everyone (lyric_fx.dart).
Future<void> openLyricCenter(
  BuildContext context, {
  required List<String> words,
  required int line,
  required LyricFxTable fixes,
  required int? seed,
  required Future<void> Function(LyricFxTable fixes) onSave,
  required VoidCallback onHear,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tones.surfaceRaised,
    builder: (_) => _LyricCenter(
      words: words,
      line: line,
      fixes: LyricFxTable(Map.of(fixes.fixes)),
      seed: seed,
      onSave: onSave,
      onHear: onHear,
    ),
  );
}

/// What can be fixed on a line: each main word, and each ad-lib as a whole.
class _Item {
  const _Item(this.first, this.text, this.adlib);

  /// The word the fix is keyed by: the word itself, or an ad-lib's first.
  final int first;
  final String text;
  final bool adlib;
}

class _LyricCenter extends StatefulWidget {
  const _LyricCenter({
    required this.words,
    required this.line,
    required this.fixes,
    required this.seed,
    required this.onSave,
    required this.onHear,
  });

  final List<String> words;
  final int line;
  final LyricFxTable fixes;
  final int? seed;
  final Future<void> Function(LyricFxTable fixes) onSave;
  final VoidCallback onHear;

  @override
  State<_LyricCenter> createState() => _LyricCenterState();
}

class _LyricCenterState extends State<_LyricCenter> {
  late final List<_Item> _items = _itemsOf(widget.words);
  int _sel = 0;
  bool _saving = false;

  static List<_Item> _itemsOf(List<String> words) {
    final out = <_Item>[];
    final whole = wholeLineAdlib(words);
    if (whole != null) {
      return [_Item(0, words.join(' '), true)];
    }
    final lfx = resolveLineFx(words);
    final groups = adlibGroups(words, [
      for (var i = 0; i < words.length; i++) lfx.kinds.containsKey(i),
    ]);
    final firstOf = {for (final g in groups) g.words.first: g};
    final inGroup = {
      for (final g in groups)
        for (final i in g.words) i,
    };
    for (var i = 0; i < words.length; i++) {
      if (isPlaceholder(words[i])) continue;
      final g = firstOf[i];
      if (g != null) {
        out.add(_Item(i, [for (final w in g.words) words[w]].join(' '), true));
      } else if (!inGroup.contains(i)) {
        out.add(_Item(i, words[i], false));
      }
    }
    return out;
  }

  FxFix? _fix(int first) => widget.fixes.at(widget.line, first);

  /// What the line does with no fixes at all, for "Auto".
  String? _autoEffect(_Item item) {
    final lfx = resolveLineFx(widget.words, seed: widget.seed);
    if (item.adlib) return lfx.kinds[item.first]?.name;
    final p = lfx.picture;
    return p != null && p.index == item.first ? p.fx.name : null;
  }

  /// The look in effect now: the fix's, else the automatic one.
  String? _current(_Item item) => _fix(item.first)?.effect ?? _autoEffect(item);

  void _setEffect(_Item item, String? effect) {
    final shift = _fix(item.first)?.shiftMs ?? 0;
    setState(() {
      if (effect == null && shift == 0) {
        widget.fixes.set(widget.line, item.first, null);
      } else {
        widget.fixes.set(
          widget.line,
          item.first,
          FxFix(effect ?? _autoEffect(item) ?? 'none', shift),
        );
      }
    });
  }

  void _shift(_Item item, int byMs) {
    final f = _fix(item.first);
    final effect = f?.effect ?? _autoEffect(item);
    if (effect == null || effect == 'none') return;
    final ms = ((f?.shiftMs ?? 0) + byMs).clamp(-5000, 5000);
    setState(() {
      widget.fixes.set(widget.line, item.first, FxFix(effect, ms));
    });
  }

  static String _label(String name) => switch (name) {
    'plain' => 'Plain',
    'none' => 'None',
    'slowmo' => 'Slow-mo',
    _ => name[0].toUpperCase() + name.substring(1),
  };

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox(height: 120);
    final item = _items[_sel.clamp(0, _items.length - 1)];
    final fix = _fix(item.first);
    final current = _current(item);
    final choices = item.adlib
        ? [for (final k in AdlibKind.values) k.name]
        : ['none', for (final f in WordFx.values) f.name];
    final shift = fix?.shiftMs ?? 0;
    final canShift = current != null && current != 'none';
    String shiftLabel(int ms) =>
        ms == 0 ? 'as estimated' : '${ms > 0 ? '+' : '−'}${ms.abs()} ms';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lyric Center', style: TypeScale.title),
              Text(
                'Pick a word or an ad-lib, then how it looks and when it comes.',
                style: TypeScale.caption,
              ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var k = 0; k < _items.length; k++)
                    ChoiceChip(
                      selected: k == _sel,
                      onSelected: (_) => setState(() => _sel = k),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _items[k].text,
                            style: _items[k].adlib
                                ? const TextStyle(fontStyle: FontStyle.italic)
                                : null,
                          ),
                          if (_current(_items[k]) case final c?)
                            if (c != 'none')
                              Text(
                                _label(c) +
                                    (_fix(_items[k].first) != null ? ' •' : ''),
                                style: TypeScale.caption.copyWith(fontSize: 10),
                              ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
              Text(
                item.adlib ? 'How this ad-lib looks' : 'How this word moves',
                style: TypeScale.caption,
              ),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(
                      'Auto${_autoEffect(item) == null ? '' : ' (${_label(_autoEffect(item)!)})'}',
                    ),
                    selected: fix == null || fix.effect == _autoEffect(item),
                    onSelected: (_) => _setEffect(item, null),
                  ),
                  for (final c in choices)
                    ChoiceChip(
                      label: Text(_label(c)),
                      selected: fix != null && fix.effect == c,
                      onSelected: (_) => _setEffect(item, c),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Text('When it comes', style: TypeScale.caption),
                  const Spacer(),
                  Text(
                    shiftLabel(shift),
                    style: TypeScale.caption.copyWith(
                      color: shift == 0 ? Tones.textMuted : Tones.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (label, ms) in const [
                    ('−1s', -1000),
                    ('−250', -250),
                    ('−50', -50),
                    ('+50', 50),
                    ('+250', 250),
                    ('+1s', 1000),
                  ])
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(44, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: canShift ? () => _shift(item, ms) : null,
                      child: Text(label),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.onHear,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Hear the line'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: Space.xs),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final navigator = Navigator.of(context);
                            await widget.onSave(widget.fixes);
                            navigator.pop();
                          },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
