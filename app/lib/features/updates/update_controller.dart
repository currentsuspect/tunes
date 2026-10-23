import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/net/tunes_client.dart';
import '../../core/net/update_check.dart';
import '../../core/net/update_installer.dart';

/// Whether a newer build exists and how getting it is going, shared by the
/// note on Home and the Updates card in Settings (design approved 23 Oct).
///
/// Dismissing the note on Home used to be the end of it until the next
/// launch. Now it only hides the note: the update waits in Settings, and a
/// dot on the profile picture says so, until it is installed.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.client,
    required this.buildNumber,
    required this.installer,
    bool? supported,
  }) : supported = supported ?? Platform.isAndroid;

  final TunesClient client;
  final String buildNumber;
  final UpdateInstaller installer;

  /// APK self-update is Android-only. The Linux bundle comes from CI
  /// artifacts, and an APK button there would be a dead end.
  final bool supported;

  AvailableUpdate? _available;
  bool _needsPermission = false;
  double? _progress;
  bool _checking = false;
  bool _failed = false;
  DateTime? _checkedAt;
  bool _noteDismissed = false;

  AvailableUpdate? get available => _available;
  bool get needsPermission => _needsPermission;

  /// 0..1 while downloading.
  double? get progress => _progress;
  bool get checking => _checking;

  /// The last check could not reach the box.
  bool get failed => _failed;
  DateTime? get checkedAt => _checkedAt;

  /// Whether Home should show its note now (the listener may have said
  /// not now, or turned the note off in Settings).
  bool showNoteOnHome({required bool enabled}) =>
      _available != null && enabled && !_noteDismissed;

  void dismissNote() {
    _noteDismissed = true;
    notifyListeners();
  }

  /// Asks the box whether a newer build exists. Never throws: an app that
  /// will not start because it could not check for updates has its
  /// priorities backwards.
  Future<void> check() async {
    if (!supported || _checking) return;
    _checking = true;
    notifyListeners();
    try {
      final got = await client.fetchUpdate();
      _failed = false;
      _checkedAt = DateTime.now();
      if (shouldOfferUpdate(buildNumber, got)) {
        _available = got;
        // Asked before offering the download rather than after: on Android
        // 8+ the permission is grantable only from Settings, and finding
        // that out after 100 MB is the wrong order.
        _needsPermission = !await installer.canInstall();
      } else {
        _available = null;
      }
    } catch (_) {
      _failed = true;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Downloads and hands the APK to Android. Returns false on failure.
  Future<bool> start() async {
    final update = _available;
    if (update == null || _progress != null) return true;
    _progress = 0;
    notifyListeners();
    try {
      await installer.downloadAndInstall(
        client.updateApkUrl,
        update.build,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
      _progress = null;
      notifyListeners();
      return true;
    } catch (_) {
      _progress = null;
      notifyListeners();
      return false;
    }
  }

  /// Opens Android's "install unknown apps" page and checks again on return:
  /// the person may have looked and backed out.
  Future<void> grantPermission() async {
    await installer.openInstallSettings();
    _needsPermission = !await installer.canInstall();
    notifyListeners();
  }
}
