import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../audio/tune_player.dart';

/// What the desktop's media controls are told about the player (MPRIS, see
/// linux/runner/mpris.cc). Pure, so it is tested without a bus.
Map<String, Object> mprisReport(
  TunePlayer p, {
  String? Function(String sha)? artPathFor,
}) {
  final t = p.current;
  final status = t == null
      ? 'Stopped'
      : p.playing
      ? 'Playing'
      : 'Paused';
  final art = t?.artSha == null ? null : artPathFor?.call(t!.artSha!);
  return {
    'status': status,
    'loop': switch (p.repeat) {
      PlaybackRepeat.off => 'None',
      PlaybackRepeat.all => 'Playlist',
      PlaybackRepeat.one => 'Track',
    },
    'shuffle': p.shuffle,
    'canNext':
        t != null &&
        (p.index + 1 < p.queue.length || p.repeat != PlaybackRepeat.off),
    'canPrevious': t != null,
    'trackId': t?.sha ?? '',
    'title': t?.title ?? '',
    'artist': t?.artist ?? '',
    'album': t?.album ?? '',
    'artUrl': art == null ? '' : Uri.file(art).toString(),
    'lengthUs': p.duration.inMicroseconds,
    'positionUs': p.position.inMicroseconds,
  };
}

/// Carries out a command from the desktop's media controls.
void mprisCommand(TunePlayer p, String name, Object? value) {
  switch (name) {
    case 'play':
      p.play();
    case 'pause':
      p.pause();
    case 'playPause':
      p.toggle();
    case 'next':
      p.next();
    case 'previous':
      p.previous();
    case 'seek':
      if (value is int) p.seek(Duration(microseconds: value));
    case 'shuffle':
      if (value is bool) p.setShuffle(value);
    case 'loop':
      p.setRepeat(switch (value) {
        'Track' => PlaybackRepeat.one,
        'Playlist' => PlaybackRepeat.all,
        _ => PlaybackRepeat.off,
      });
  }
}

/// Keeps the runner's MPRIS player in step with [player], on Linux only.
///
/// The player notifies often (position, buffering); a report is sent only
/// when something the bus shows has changed, or the position moved other
/// than by playing on (a seek), which the runner announces as Seeked.
class MprisBridge {
  MprisBridge._(this._player, this._artPathFor);

  static const _channel = MethodChannel('tunes/mpris');

  static MprisBridge? start(
    TunePlayer player, {
    String? Function(String sha)? artPathFor,
  }) {
    if (!Platform.isLinux) return null;
    final b = MprisBridge._(player, artPathFor);
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
      final args = call.arguments;
      if (args is! Map) return;
      mprisCommand(b._player, '${args['name']}', args['value']);
    });
    player.addListener(b._changed);
    b._changed();
    return b;
  }

  final TunePlayer _player;
  final String? Function(String sha)? _artPathFor;

  void stop() {
    _player.removeListener(_changed);
    _channel.setMethodCallHandler(null);
  }

  Map<String, Object>? _last;
  DateTime _lastAt = DateTime.now();

  void _changed() {
    final now = _player.position;
    final report = mprisReport(_player, artPathFor: _artPathFor);
    final last = _last;
    if (last != null) {
      final same = report.entries.every(
        (e) => e.key == 'positionUs' || last[e.key] == e.value,
      );
      // Where it should be by now, had it simply played on.
      final ran = report['status'] == 'Playing'
          ? DateTime.now().difference(_lastAt).inMicroseconds
          : 0;
      final expected = (last['positionUs'] as int) + ran;
      final jumped = (now.inMicroseconds - expected).abs() > 1500000;
      if (same && !jumped) return;
    }
    _last = report;
    _lastAt = DateTime.now();
    unawaited(_channel.invokeMethod<void>('update', report).catchError((_) {}));
  }
}
