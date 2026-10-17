/// Which bytes of a file have arrived, as sorted, non-overlapping half-open
/// runs `[start, end)`.
///
/// A song streamed through [StreamRelay] lands out of order: from the top,
/// then from wherever a seek jumped to, then the holes left behind. This is
/// the record of what can be read back already and what is still missing.
class ByteRanges {
  final List<int> _starts = [];
  final List<int> _ends = [];

  bool get isEmpty => _starts.isEmpty;

  /// Bytes held in total.
  int get length {
    var n = 0;
    for (var i = 0; i < _starts.length; i++) {
      n += _ends[i] - _starts[i];
    }
    return n;
  }

  /// Records `[start, end)` as arrived, merging with any run it touches.
  void add(int start, int end) {
    if (end <= start) return;
    var i = 0;
    while (i < _starts.length && _ends[i] < start) {
      i++;
    }
    var s = start;
    var e = end;
    while (i < _starts.length && _starts[i] <= e) {
      if (_starts[i] < s) s = _starts[i];
      if (_ends[i] > e) e = _ends[i];
      _starts.removeAt(i);
      _ends.removeAt(i);
    }
    _starts.insert(i, s);
    _ends.insert(i, e);
  }

  /// Where the run holding [pos] ends (exclusive), or [pos] itself when that
  /// byte has not arrived.
  int runEnd(int pos) {
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i] > pos) break;
      if (pos < _ends[i]) return _ends[i];
    }
    return pos;
  }

  bool has(int pos) => runEnd(pos) > pos;

  /// The first missing byte at or after [from], below [total]; null when
  /// everything from [from] to [total] has arrived.
  int? firstGap(int from, int total) {
    var pos = from;
    while (pos < total) {
      final end = runEnd(pos);
      if (end == pos) return pos;
      pos = end;
    }
    return null;
  }

  bool covers(int total) => total <= 0 || firstGap(0, total) == null;
}
