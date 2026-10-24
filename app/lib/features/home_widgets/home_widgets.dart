import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../lyrics/lyric_follow.dart';

/// The lyric lines a home-screen widget shows at [position]: the one being
/// sung and those either side. Line by line, not word by word: Android only
/// lets a widget be redrawn so often (the Roon pass, approved 24 Oct).
///
/// [kind] is "timed" (lines follow the song), "plain" (lyrics with no
/// timing: the first lines, still), or "none".
({String kind, String prev, String current, String next}) lyricWindow(
  String? lyrics,
  Duration position,
) {
  const none = (kind: 'none', prev: '', current: '', next: '');
  if (lyrics == null || lyrics.trim().isEmpty) return none;
  final lrc = LrcParser.parse(lyrics);
  if (lrc.lines.isEmpty) {
    final plain = [
      for (final l in lrc.untimed)
        if (l.trim().isNotEmpty && !RegExp(r'^\[.*\]$').hasMatch(l.trim()))
          l.trim(),
    ];
    if (plain.isEmpty) return none;
    return (
      kind: 'plain',
      prev: '',
      current: plain.first,
      next: plain.length > 1 ? plain[1] : '',
    );
  }
  final i = lyricActiveIndex(lrc, position);
  String at(int? k) =>
      k == null || k < 0 || k >= lrc.lines.length ? '' : lrc.lines[k].text;
  if (i == null) {
    // Before the first line: it is what comes.
    return (kind: 'timed', prev: '', current: '', next: at(0));
  }
  return (kind: 'timed', prev: at(i - 1), current: at(i), next: at(i + 1));
}

/// Everything the widgets draw, as sent to Android. Pure, so it is tested
/// without a device.
Map<String, Object> widgetReport(
  TunePlayer p, {
  String? Function(String sha)? artPathFor,
}) {
  final t = p.current;
  final lines = lyricWindow(t?.lyrics, p.position);
  final upNext = [
    for (var k = p.index + 1; k < p.queue.length && k <= p.index + 2; k++)
      p.queue[k],
  ];
  return {
    'hasTrack': t != null,
    'title': t?.title ?? '',
    'artist': t?.artistDisplay ?? '',
    'art': (t?.artSha == null ? null : artPathFor?.call(t!.artSha!)) ?? '',
    'playing': p.playing,
    'positionMs': p.position.inMilliseconds,
    'durationMs': p.duration.inMilliseconds,
    'lyricsKind': lines.kind,
    'linePrev': lines.prev,
    'line': lines.current,
    'lineNext': lines.next,
    'next1': upNext.isNotEmpty ? upNext[0].title : '',
    'next1Artist': upNext.isNotEmpty ? upNext[0].artistDisplay : '',
    'next2': upNext.length > 1 ? upNext[1].title : '',
    'next2Artist': upNext.length > 1 ? upNext[1].artistDisplay : '',
  };
}

/// Keeps the home-screen widgets (android TunesWidgets.kt) in step with the
/// player, on Android only. Sent when something they show changes: the
/// song, play or pause, the lyric line, the queue; the progress bar only
/// every 15 s, since a widget redraw is not free.
class HomeWidgetsBridge {
  HomeWidgetsBridge._(this._player, this._artPathFor);

  static const _channel = MethodChannel('tunes/widgets');

  static HomeWidgetsBridge? start(
    TunePlayer player, {
    String? Function(String sha)? artPathFor,
  }) {
    if (!Platform.isAndroid) return null;
    final b = HomeWidgetsBridge._(player, artPathFor);
    player.addListener(b._changed);
    b._changed();
    return b;
  }

  final TunePlayer _player;
  final String? Function(String sha)? _artPathFor;
  Map<String, Object>? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  void stop() => _player.removeListener(_changed);

  void _changed() {
    final report = widgetReport(_player, artPathFor: _artPathFor);
    final last = _last;
    if (last != null) {
      final same = report.entries.every(
        (e) => e.key == 'positionMs' || last[e.key] == e.value,
      );
      final stale =
          DateTime.now().difference(_lastAt) > const Duration(seconds: 15);
      if (same && !(stale && _player.playing)) return;
    }
    _last = report;
    _lastAt = DateTime.now();
    unawaited(_channel.invokeMethod<void>('update', report).catchError((_) {}));
  }
}
