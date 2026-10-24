import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('tunes/notifications');

Future<void> requestNotificationPermissionIfNeeded() async {
  try {
    await _channel.invokeMethod<void>('requestPostNotifications');
  } catch (_) {
    // Refused, not Android, or no engine (a test): the get it came with
    // goes ahead either way, and notes stay off.
  }
}

/// A plain note in the shade: a song landed, someone got songs, an update
/// is ready. [tap] and [action] are what the app is told when the note, or
/// its one button, is tapped (`play:<sha>`, `open:gets`, `open:update`).
///
/// Android, and on a computer the desktop's own notifications (Linux,
/// through notify-send, which waits for the click: [_linuxNote]). Only while
/// the app's process is alive: there is no push. Music playing keeps it
/// alive, which is when gets are asked for.
Future<void> showNote({
  required int id,
  required String title,
  String? body,
  String? tap,
  String? actionLabel,
  String? action,
}) async {
  if (Platform.isLinux) {
    return _linuxNote(
      id: id,
      title: title,
      body: body,
      tap: tap,
      actionLabel: actionLabel,
      action: action,
    );
  }
  try {
    await _channel.invokeMethod<void>('show', {
      'id': id,
      'title': title,
      'body': ?body,
      'tap': ?tap,
      'actionLabel': ?actionLabel,
      'action': ?action,
    });
  } on PlatformException {
    // A note that cannot be shown is not worth more than that.
  } on MissingPluginException {
    // Not Android.
  }
}

/// Clicks on the computer's notes, for [noteActions].
final _linuxActions = StreamController<String>.broadcast();

/// The arguments for a desktop note: replacing the one before with the same
/// [id], the app's name and logo, the click ("default") and its one button.
List<String> linuxNoteArgs({
  required int id,
  required String title,
  String? body,
  String? tap,
  String? actionLabel,
  String? action,
}) => [
  '--app-name=Tunes',
  '--icon=com.currentsuspect.tunes',
  '--hint=string:desktop-entry:com.currentsuspect.tunes',
  '--replace-id=$id',
  if (tap != null) '--action=default=Open',
  if (action != null && actionLabel != null) '--action=act=$actionLabel',
  if (tap != null || action != null) '--wait',
  title,
  ?body,
];

Future<void> _linuxNote({
  required int id,
  required String title,
  String? body,
  String? tap,
  String? actionLabel,
  String? action,
}) async {
  try {
    final p = await Process.start(
      'notify-send',
      linuxNoteArgs(
        id: id,
        title: title,
        body: body,
        tap: tap,
        actionLabel: actionLabel,
        action: action,
      ),
    );
    // Waits for the click (or the note closing), in the background.
    unawaited(() async {
      final picked =
          (await p.stdout.transform(const SystemEncoding().decoder).join())
              .trim();
      if (picked == 'act' && action != null) _linuxActions.add(action);
      if (picked == 'default' && tap != null) _linuxActions.add(tap);
    }());
    unawaited(p.stderr.drain<void>());
  } catch (_) {
    // No notify-send: no note, as on a phone that refused them.
  }
}

/// Taps on notes, as they happen and, first, the one that started the app.
Stream<String> noteActions() {
  if (Platform.isLinux) return _linuxActions.stream;
  final out = StreamController<String>();
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'action' && call.arguments is String) {
      out.add(call.arguments as String);
    }
  });
  () async {
    try {
      final first = await _channel.invokeMethod<String>('takeAction');
      if (first != null) out.add(first);
    } on PlatformException {
      // Nothing waiting.
    } on MissingPluginException {
      // Not Android.
    }
  }();
  return out.stream;
}
