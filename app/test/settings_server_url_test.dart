import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/settings_store.dart';

/// The stored server address.
///
/// It decides which library the app talks to, and until now that was a
/// compile-time constant — so a second person could not use a build without
/// someone rebuilding it for them. The two properties worth pinning are that
/// an existing install is unaffected (null means "use the compiled-in value"),
/// and that a typed address is normalised, because the failure mode of a
/// trailing slash is a request to `//manifest` that reads as the server being
/// down rather than as a bad setting.
void main() {
  late TunesDatabase db;
  late SettingsStore settings;

  setUp(() async {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsStore(db);
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await db.close();
  });

  test('unset by default, so the build decides', () {
    expect(settings.serverUrl, isNull);
  });

  test('stores what was typed', () async {
    await settings.setServerUrl('http://100.100.235.90:4780');
    expect(settings.serverUrl, 'http://100.100.235.90:4780');
  });

  test('a trailing slash is removed', () async {
    // '$baseUrl/manifest' with a stored trailing slash asks for '//manifest'.
    await settings.setServerUrl('http://host:4780/');
    expect(settings.serverUrl, 'http://host:4780');
  });

  test('surrounding whitespace is removed', () async {
    // Pasted addresses routinely carry a space or a newline.
    await settings.setServerUrl('  http://host:4780  ');
    expect(settings.serverUrl, 'http://host:4780');
  });

  test('empty clears it back to the build default', () async {
    await settings.setServerUrl('http://host:4780');
    await settings.setServerUrl('');
    expect(settings.serverUrl, isNull);
  });

  test('whitespace-only also clears, rather than storing a blank', () async {
    // Otherwise the app would point at the empty string and every request
    // would fail with no way back except a reinstall.
    await settings.setServerUrl('http://host:4780');
    await settings.setServerUrl('   ');
    expect(settings.serverUrl, isNull);
  });

  test('null clears it', () async {
    await settings.setServerUrl('http://host:4780');
    await settings.setServerUrl(null);
    expect(settings.serverUrl, isNull);
  });

  test('survives a reload, which is the whole point', () async {
    await settings.setServerUrl('http://100.100.235.90:4780');
    final reopened = SettingsStore(db);
    await reopened.load();
    expect(reopened.serverUrl, 'http://100.100.235.90:4780');
    reopened.dispose();
  });
}
