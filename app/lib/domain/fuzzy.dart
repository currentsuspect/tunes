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
  // "don't" is "dont": an apostrophe joins, it does not split.
  "'": '',
  '\u2019': '',
};

/// Lower case, accents off, symbols that stand for letters turned back into
/// them, everything else that is not a letter or digit made a space.
String foldForSearch(String s) {
  // Character by character, with no pattern matching per character: this
  // runs over every title and, for lyric search, every line of every song.
  final b = StringBuffer();
  var space = true;
  for (final ch in s.toLowerCase().split('')) {
    final f = _fold[ch];
    final c = ch.codeUnitAt(0);
    final keep =
        f == null &&
        ((c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c > 0x2ff);
    final out = f ?? (keep ? ch : ' ');
    for (final o in out.split('')) {
      if (o == ' ') {
        if (!space) b.write(' ');
        space = true;
      } else {
        b.write(o);
        space = false;
      }
    }
  }
  return b.toString().trimRight();
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
double _wordScore(
  String q,
  List<String> words,
  String joined, {
  bool typos = true,
  Map<String, int>? near,
}) {
  var best = 0.0;
  for (final w in words) {
    if (w == q) return 4;
    if (w.startsWith(q)) {
      best = best < 3 ? 3 : best;
    } else if (q.length >= 3 && w.contains(q)) {
      best = best < 2 ? 2 : best;
    } else if (typos && q.length >= 4) {
      final allowed = q.length >= 7 ? 2 : 1;
      // Against the word, and against its start, so "hihg" finds "highest".
      // The same word turns up in hundreds of titles; measured once each.
      int measure() {
        final head = w.length > q.length ? w.substring(0, q.length) : w;
        return [
          _distance(q, w, allowed),
          _distance(q, head, allowed),
        ].reduce((x, y) => x < y ? x : y);
      }

      final d = near == null ? measure() : near.putIfAbsent(w, measure);
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
double fuzzyScore(String query, List<SearchField> fields) =>
    PreparedQuery(query).score(fields);

/// A query folded once, for scoring against a whole library: folding it
/// again for each of two thousand songs was most of a keystroke's cost.
///
/// With [typos] off only exact, prefix and inside-a-word matches count: the
/// edit-distance pass is most of the cost, and is only worth paying when the
/// plain pass finds little.
class PreparedQuery {
  PreparedQuery(String query, {this.typos = true})
    : folded = foldForSearch(query),
      tokens = foldForSearch(query).split(' ') {
    for (final t in tokens) {
      _near[t] = {};
    }
  }

  final String folded;
  final List<String> tokens;
  final bool typos;

  /// Per typed word: each library word's edit distance from it.
  final Map<String, Map<String, int>> _near = {};

  double score(List<SearchField> fields) =>
      folded.isEmpty ? 0 : _score(folded, tokens, fields, typos, _near);
}

double _score(
  String folded,
  List<String> tokens,
  List<SearchField> fields,
  bool typos, [
  Map<String, Map<String, int>>? near,
]) {
  var total = 0.0;
  for (final t in tokens) {
    var best = 0.0;
    for (final f in fields) {
      final s =
          _wordScore(t, f.words, f.joined, typos: typos, near: near?[t]) *
          f.weight;
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
  final q = PreparedQuery(query);
  var i = 0;
  for (final it in items) {
    final s = q.score(fieldsOf(it));
    if (s > 0) scored.add((it, s, i));
    i++;
  }
  scored.sort((a, b) {
    final c = b.$2.compareTo(a.$2);
    return c != 0 ? c : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored.take(limit)) s.$1];
}
