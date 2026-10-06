import 'dart:async';

import 'package:flutter/widgets.dart';

class Reachability extends ChangeNotifier {
  bool _offline = false;

  bool get offline => _offline;

  int _failures = 0;

  /// How many checks in a row have to fail before the app says it is offline.
  /// One missed answer is a busy box or a bad second on the network, not the
  /// end of the connection; saying "offline" for it and "online" again a few
  /// seconds later is what made the app flicker.
  static const failuresToGoOffline = 3;

  /// A check or a request got an answer: online at once.
  void ok() {
    _failures = 0;
    setOffline(false);
  }

  /// A check or a request got no answer. Offline only once it keeps happening.
  void failed() {
    _failures += 1;
    if (_failures >= failuresToGoOffline) setOffline(true);
  }

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
      final answered = await ping();
      answered ? reachability.ok() : reachability.failed();
    } catch (_) {
      reachability.failed();
    } finally {
      _probing = false;
    }
  }
}
