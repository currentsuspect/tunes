/// Ad-libs: the bracketed words sung under or after the main line
/// ("(Woah, let's go)", "(Yeah)"). Shown on a smaller row of their own beneath
/// the main words, so the line reads as what is being sung and the ad-lib as
/// what is shouted around it. Display only; the text is never changed.
library;

/// Which of [tokens] (words, in order) sit inside brackets. A line wholly in
/// brackets is a backing line, handled by the voices instead, so it has no
/// ad-libs here: every entry false.
List<bool> adlibMask(List<String> tokens) {
  final mask = <bool>[];
  var depth = 0;
  for (final t in tokens) {
    final opens = '('.allMatches(t).length;
    final closes = ')'.allMatches(t).length;
    // A word that opens a bracket is inside it; one that closes it still is.
    final inside = depth > 0 || opens > 0;
    mask.add(inside);
    depth = (depth + opens - closes).clamp(0, 9);
  }
  if (mask.every((m) => m) || !mask.contains(true)) {
    return List.filled(tokens.length, false);
  }
  return mask;
}

/// [text] as its main words and its ad-libs, or null when it has none.
({String main, String adlibs})? splitAdlibText(String text) {
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final mask = adlibMask(tokens);
  if (!mask.contains(true)) return null;
  final main = [
    for (var i = 0; i < tokens.length; i++)
      if (!mask[i]) tokens[i],
  ].join(' ').replaceAll(RegExp(r'\s+([,.!?;:])'), r'$1').trim();
  // Punctuation after a closing bracket belongs to the main line's flow
  // ("Number two (Hahahaha), only…"), not to the ad-lib.
  final adlibs = [
    for (var i = 0; i < tokens.length; i++)
      if (mask[i]) tokens[i].replaceAll(RegExp(r'\)[,.;:!?]+$'), ')'),
  ].join(' ');
  return (main: main, adlibs: adlibs);
}
