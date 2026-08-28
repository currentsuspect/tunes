import 'dart:async';

import 'package:flutter/foundation.dart';

class Reachability extends ChangeNotifier {
  bool _offline = false;

  bool get offline => _offline;

  void setOffline(bool value) {
    if (value == _offline) return;
    _offline = value;
    notifyListeners();
  }
}

class Heartbeat {
  Heartbeat({
    required this.ping,
    required this.reachability,
    this.interval = const Duration(seconds: 10),
  });

  final Future<bool> Function() ping;
  final Reachability reachability;
  final Duration interval;

  Timer? _timer;
  bool _probing = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => probe());
    unawaited(probe());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> probe() async {
    if (_probing) return;
    _probing = true;
    try {
      final ok = await ping();
      reachability.setOffline(!ok);
    } catch (_) {
      reachability.setOffline(true);
    } finally {
      _probing = false;
    }
  }
}
