import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/gets.dart';
import 'package:tunes/core/data/settings_store.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/soulseek.dart';
import 'package:tunes/features/notes/note_center.dart';

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
      GetJob(id: 'mine', title: title, artist: artist, state: GetState.queued);

  @override
  Future<List<GetJob>> soulseekJobs({int? days}) async => jobs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TunesDatabase db;
  late SettingsStore settings;
  late _Box box;
  late GetsController gets;
  late List<String> shown;
  var foreground = false;

  setUp(() async {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsStore(db);
    await settings.load();
    box = _Box();
    gets = GetsController(client: box, onLanded: () {});
    shown = [];
    foreground = false;
  });
  tearDown(() async {
    gets.dispose();
    await db.close();
  });

  NoteCenter center() => NoteCenter(
    gets: gets,
    settings: settings,
    updates: null,
    foreground: () => foreground,
    show:
        ({
          required int id,
          required String title,
          String? body,
          String? tap,
          String? actionLabel,
          String? action,
        }) async {
          shown.add(title);
        },
  );

  const landed = GetJob(
    id: 'mine',
    title: 'Desperado',
    artist: 'Rihanna',
    state: GetState.done,
    sha: 'abc',
  );

  test('my song landing is told in the shade, only while away', () async {
    final notes = center();
    await gets.get(null, title: 'Desperado', artist: 'Rihanna');
    box.jobs = const [landed];
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(shown, ['Desperado is in your library']);
    notes.dispose();
  });

  test('not while Tunes is on screen: the message there says it', () async {
    foreground = true;
    final notes = center();
    await gets.get(null, title: 'Desperado', artist: 'Rihanna');
    box.jobs = const [landed];
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(shown, isEmpty);
    notes.dispose();
  });

  test('others\' gets: off by default, then one note per person', () async {
    final notes = center();
    box.jobs = const [];
    await gets.refreshRecent(); // what was there first is not news
    box.jobs = const [
      GetJob(
        id: 'a',
        title: 'Tadow',
        artist: 'Masego',
        state: GetState.done,
        by: 'Dennis',
      ),
    ];
    await gets.refreshRecent();
    expect(shown, isEmpty);

    await settings.setNoteOthers(true);
    box.jobs = const [
      GetJob(
        id: 'a',
        title: 'Tadow',
        artist: 'Masego',
        state: GetState.done,
        by: 'Dennis',
      ),
      GetJob(
        id: 'b',
        title: 'Free Mind',
        artist: 'Tems',
        state: GetState.done,
        by: 'Dennis',
      ),
      GetJob(
        id: 'c',
        title: 'Spectacular',
        artist: 'Skyte',
        state: GetState.done,
        by: 'Dennis',
      ),
    ];
    await gets.refreshRecent();
    expect(shown, ['Dennis got 2 songs']);
    notes.dispose();
  });
}
