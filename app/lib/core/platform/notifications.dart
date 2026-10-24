import 'dart:async';

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
/// Android only, and only while the app's process is alive: there is no
/// push. Music playing keeps it alive, which is when gets are asked for.
Future<void> showNote({
  required int id,
  required String title,
  String? body,
  String? tap,
  String? actionLabel,
  String? action,
}) async {
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

/// Taps on notes, as they happen and, first, the one that started the app.
Stream<String> noteActions() {
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
