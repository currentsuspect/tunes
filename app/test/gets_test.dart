import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/gets.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/soulseek.dart';

class _Box extends TunesClient {
  _Box() : super('http://test');
  List<GetJob> jobs = const [];

  @override
  Future<GetJob> soulseekGet({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? release,
    FoundSong? copy,
  }) async =>
      GetJob(id: 'old', title: title, artist: artist, state: GetState.queued);

  @override
  Future<List<GetJob>> soulseekJobs({int? days}) async => jobs;
}

void main() {
  test(
    'follows a song across a box restart, by song when the id is new',
    () async {
      final box = _Box();
      var landed = 0;
      final g = GetsController(client: box, onLanded: () => landed++);
      await g.get(null, title: 'In Need', artist: 'Skyte');
      box.jobs = const [
        GetJob(
          id: 'new',
          title: 'In Need',
          artist: 'Skyte',
          state: GetState.done,
          sha: 'abc',
        ),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(g.jobFor('Skyte', 'In Need')?.state, GetState.done);
      expect(landed, 1);
      g.dispose();
    },
  );

  test('a get the box no longer knows shows as failed, not forever', () async {
    final box = _Box();
    final g = GetsController(client: box, onLanded: () {});
    await g.get(null, title: 'In Need', artist: 'Skyte');
    box.jobs = const [];
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(g.jobFor('Skyte', 'In Need')?.state, GetState.failed);
    g.dispose();
  });

  test('a check that finds nothing new tells no one', () async {
    final box = _Box();
    final g = GetsController(client: box, onLanded: () {});
    box.jobs = const [
      GetJob(
        id: 'a',
        title: 'Wings',
        artist: 'Little Mix',
        state: GetState.done,
      ),
    ];
    await g.refreshRecent();
    var told = 0;
    g.addListener(() => told++);
    await g.refreshRecent();
    await g.refreshRecent();
    expect(told, 0);
    box.jobs = const [
      GetJob(
        id: 'b',
        title: 'Touch',
        artist: 'Little Mix',
        state: GetState.done,
      ),
      GetJob(
        id: 'a',
        title: 'Wings',
        artist: 'Little Mix',
        state: GetState.done,
      ),
    ];
    await g.refreshRecent();
    expect(told, 1);
    g.dispose();
  });
}
