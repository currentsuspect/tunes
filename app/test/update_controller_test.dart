import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/core/net/update_check.dart';
import 'package:tunes/core/net/update_installer.dart';
import 'package:tunes/features/updates/update_controller.dart';

class _Box extends TunesClient {
  _Box(this.build) : super('http://test');
  int? build;

  @override
  Future<AvailableUpdate?> fetchUpdate() async => build == null
      ? null
      : AvailableUpdate(build: build!, name: 'b', notes: 'Search', size: 1);
}

class _Installer extends UpdateInstaller {
  _Installer() : super(cacheDir: Directory.systemTemp);
  bool allowed = true;

  @override
  Future<bool> canInstall() async => allowed;
}

void main() {
  UpdateController make(_Box box, [_Installer? i]) => UpdateController(
    client: box,
    buildNumber: '2410',
    installer: i ?? _Installer(),
    supported: true,
  );

  test('"not now" hides the note on Home, but the update stays', () async {
    final u = make(_Box(2416));
    await u.check();
    expect(u.available?.build, 2416);
    expect(u.showNoteOnHome(enabled: true), isTrue);
    u.dismissNote();
    expect(u.showNoteOnHome(enabled: true), isFalse);
    // Still there for Settings and the dot.
    expect(u.available?.build, 2416);
  });

  test(
    'the Home switch turns the note off without losing the update',
    () async {
      final u = make(_Box(2416));
      await u.check();
      expect(u.showNoteOnHome(enabled: false), isFalse);
      expect(u.available, isNotNull);
    },
  );

  test('nothing newer, nothing offered; a check records when', () async {
    final u = make(_Box(2410));
    await u.check();
    expect(u.available, isNull);
    expect(u.checkedAt, isNotNull);
    expect(u.failed, isFalse);
  });

  test(
    'asks for the install permission before offering the download',
    () async {
      final i = _Installer()..allowed = false;
      final u = make(_Box(2416), i);
      await u.check();
      expect(u.needsPermission, isTrue);
    },
  );

  test('where the app cannot update itself, it never asks', () async {
    final box = _Box(2416);
    final u = UpdateController(
      client: box,
      buildNumber: '2410',
      installer: _Installer(),
      supported: false,
    );
    await u.check();
    expect(u.available, isNull);
    expect(u.checkedAt, isNull);
  });
}
