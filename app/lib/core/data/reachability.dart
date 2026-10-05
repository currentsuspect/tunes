import 'dart:async';

import 'package:flutter/widgets.dart';

class Reachability extends ChangeNotifier {
  bool _offline = false;

  bool get offline => _offline;

  void setOffline(bool value) {
    if (value == _offline) return;
    _offline = value;
    notifyListeners();
  }
}

/// Makes [Reachability] readable from any screen, so the places that say where
/// the sound is coming from follow the connection without being handed it.
class ReachabilityScope extends InheritedNotifier<Reachability> {
  const ReachabilityScope({
    super.key,
    required Reachability reachability,
    required super.child,
  }) : super(notifier: reachability);

  static Reachability? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReachabilityScope>()?.notifier;
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
