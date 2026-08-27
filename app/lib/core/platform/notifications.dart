import 'package:flutter/services.dart';

const _channel = MethodChannel('tunes/notifications');

Future<void> requestNotificationPermissionIfNeeded() async {
  try {
    await _channel.invokeMethod<void>('requestPostNotifications');
  } on PlatformException {
    // permission request failed; playback continues, notification stays off
  } on MissingPluginException {
    // not running on Android; nothing to request
  }
}
