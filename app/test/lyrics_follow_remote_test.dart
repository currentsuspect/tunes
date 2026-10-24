import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/playhead_clock.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/sync/connect_player.dart';
import 'package:tunes/core/sync/now_sync.dart';
import 'package:tunes/core/sync/sync_models.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/lyrics/lyrics_sheet.dart';

ManifestTrack _t(String c, {String? lyrics}) => ManifestTrack(
  sha: c * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1,
  durationMs: 180000,
  title: 'T$c',
  artist: 'A',
  album: 'B',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  lyrics: lyrics,
);

class _Local extends TunePlayer {
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => 0;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void toggle() {}
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void playAt(int index) {}
  @override
  void seek(Duration target) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

void main() {
  // The PC showing the phone's song (owner's desktop list, 24 Oct, item 3).
  testWidgets('lyrics follow a song playing on the phone', (tester) async {
    PlayheadClock.ticking = false;
    const lyrics =
        '[00:10.00] line one\n[00:20.00] line two\n[00:30.00] line three\n[00:40.00] line four';
    final b = _t('b', lyrics: lyrics);
    final remote = RemoteNow();
    var clock = 1005000;
    final player = ConnectPlayer(
      local: _Local(),
      remote: remote,
      resolve: (s) => s == b.sha ? b : null,
      serverNow: () => clock,
      send: (_) async => true,
    );
    remote.ingest(
      SyncDoc(
        key: 'now',
        value: jsonEncode({
          'sha': b.sha,
          'index': 0,
          'positionMs': 30000,
          'playing': true,
          'since': 900000,
        }),
        updatedAt: 1000000,
        deviceId: 'phone',
      ),
      {'phone': 'Phone'},
      'pc',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.isRemote, isTrue);
    expect(player.position, const Duration(seconds: 35));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsSheet(
            embedded: true,
            track: b,
            player: player,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    double size(String text) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style
        .fontSize!;
    // 35 s into the phone's song: line three is the one being sung, set
    // larger than the rest.
    expect(size('line three'), greaterThan(size('line two')));
    expect(size('line four'), size('line two'));
    // And it moves on as the phone does.
    clock += 10000;
    await tester.pump(const Duration(milliseconds: 600));
    expect(size('line four'), greaterThan(size('line three')));
    player.dispose();
  });
}
