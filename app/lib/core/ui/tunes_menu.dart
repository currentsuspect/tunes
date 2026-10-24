import 'package:flutter/material.dart';

import '../theme/looks.dart';
import '../theme/tokens.dart';

/// One row of a "more" menu: an icon and a label, so a menu reads at a
/// glance instead of as a column of words. [danger] is for the row that
/// takes something away (remove a download, delete a playlist).
///
/// The card around the rows comes from the theme's `popupMenuTheme`.
PopupMenuItem<T> tunesMenuItem<T>(
  T value,
  IconData icon,
  String label, {
  bool danger = false,
}) {
  final crayon = Looks.current.kind == LookKind.crayon;
  final color = danger ? Tones.warn : Tones.text;
  return PopupMenuItem<T>(
    value: value,
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: Space.md),
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: danger ? Tones.warn : (crayon ? Tones.text : Tones.textMuted),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(label, style: TypeScale.body.copyWith(color: color)),
        ),
      ],
    ),
  );
}

/// A thin rule between groups of rows.
PopupMenuEntry<T> tunesMenuDivider<T>() => const PopupMenuDivider(height: 9);
