/// Forgiving search: typos, missing accents, odd spellings and words run
/// together still find the song.
///
/// "beyonce" finds Beyoncé, "travi$" and "travis" find each other, "hihgest"
/// finds HIGHEST IN THE ROOM, "bonnie clyde" finds '03 Bonnie & Clyde, and
/// "highestintheroom" finds it too. Every word typed has to land somewhere;
/// how well it lands decides the order.
library;

const _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  'œ': 'oe',
  '\$': 's',
  '&': ' and ',
  '@': 'a',
};

/// Lower case, accents off, symbols that stand for letters turned back into
/// them, everything else that is not a letter or digit made a space.
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final f = _fold[ch];
    if (f != null) {
      b.write(f);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch) || ch.codeUnitAt(0) > 0x2ff) {
      b.write(ch);
    } else {
      b.write(' ');
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Edit distance with swaps counted as one, stopping early past [max].
int _distance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  final n = b.length;
  var prev2 = List<int>.filled(n + 1, 0);
  var prev = List<int>.generate(n + 1, (j) => j);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          prev2[j - 2] + 1 < v) {
        v = prev2[j - 2] + 1;
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[n];
}

/// How well one typed word lands on a field's words: 0 when it does not.
double _wordScore(String q, List<String> words, String joined) {
  var best = 0.0;
  for (final w in words) {
    if (w == q) return 4;
    if (w.startsWith(q)) {
      best = best < 3 ? 3 : best;
    } else if (q.length >= 3 && w.contains(q)) {
      best = best < 2 ? 2 : best;
    } else if (q.length >= 4) {
      final allowed = q.length >= 7 ? 2 : 1;
      // Against the word, and against its start, so "hihg" finds "highest".
      final head = w.length > q.length ? w.substring(0, q.length) : w;
      final d = [
        _distance(q, w, allowed),
        _distance(q, head, allowed),
      ].reduce((x, y) => x < y ? x : y);
      if (d <= allowed) {
        final s = d == 1 ? 1.5 : 1.0;
        if (s > best) best = s;
      }
    }
  }
  // Words run together: "highestintheroom".
  if (best == 0 && q.length >= 5 && joined.contains(q)) best = 1.5;
  return best;
}

/// A prepared field (title, artist, album) so the folding is done once.
class SearchField {
  SearchField(String raw, {this.weight = 1})
    : folded = foldForSearch(raw),
      words = foldForSearch(raw).split(' '),
      joined = foldForSearch(raw).replaceAll(' ', '');

  final String folded;
  final List<String> words;
  final String joined;
  final double weight;
}

/// Score of [query] against [fields], or 0 when some typed word lands nowhere.
double fuzzyScore(String query, List<SearchField> fields) {
  final folded = foldForSearch(query);
  if (folded.isEmpty) return 0;
  final tokens = folded.split(' ');
  var total = 0.0;
  for (final t in tokens) {
    var best = 0.0;
    for (final f in fields) {
      final s = _wordScore(t, f.words, f.joined) * f.weight;
      if (s > best) best = s;
    }
    if (best == 0) return 0;
    total += best;
  }
  // The whole phrase intact somewhere is the strongest sign.
  for (final f in fields) {
    if (f.folded.contains(folded)) total += 3 * f.weight;
    if (f.folded == folded) total += 3 * f.weight;
  }
  return total;
}

/// The items that match, best first, ties kept in their original order.
List<T> fuzzyRank<T>(
  String query,
  Iterable<T> items,
  List<SearchField> Function(T) fieldsOf, {
  int limit = 200,
}) {
  final scored = <(T, double, int)>[];
  var i = 0;
  for (final it in items) {
    final s = fuzzyScore(query, fieldsOf(it));
    if (s > 0) scored.add((it, s, i));
    i++;
  }
  scored.sort((a, b) {
    final c = b.$2.compareTo(a.$2);
    return c != 0 ? c : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored.take(limit)) s.$1];
}
