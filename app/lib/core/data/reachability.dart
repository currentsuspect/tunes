import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

class Reachability extends ChangeNotifier {
  bool _offline = false;

  bool get offline => _offline;

  /// Whether the last check found the phone on Wi-Fi (see [onWifi]). Read
  /// synchronously where a decision cannot wait for a lookup.
  bool wifi = false;

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
    this.offlineInterval = const Duration(seconds: 3),
    this.pingTimeout = const Duration(seconds: 10),
  });

  /// The longest one check may take before it counts as unanswered.
  final Duration pingTimeout;

  /// How often to check while offline: coming back should be noticed in
  /// seconds, not after the next ten-second tick.
  final Duration offlineInterval;

  final Future<bool> Function() ping;
  final Reachability reachability;
  final Duration interval;

  Timer? _timer;
  bool _probing = false;

  void start() {
    _timer ??= Timer.periodic(offlineInterval, (_) {
      // Every tick while offline; online, only once per [interval].
      final last = _lastProbe;
      if (!reachability.offline &&
          last != null &&
          DateTime.now().difference(last) < interval) {
        return;
      }
      unawaited(probe());
    });
    unawaited(probe());
  }

  DateTime? _lastProbe;

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> probe() async {
    if (_probing) return;
    _probing = true;
    _lastProbe = DateTime.now();
    try {
      reachability.wifi = await onWifi();
      // No network at all (airplane mode, radios off) needs no three strikes:
      // there is nothing a ping could reach.
      if (!await hasNetworkAddress()) {
        reachability.setOffline(true);
        return;
      }
      // Bounded on its own: a lookup that hangs while the phone changes
      // networks used to hold [_probing] forever, so no check ever ran again
      // and the app stayed offline until it was restarted.
      final answered = await ping().timeout(
        pingTimeout,
        onTimeout: () => false,
      );
      answered ? reachability.ok() : reachability.failed();
    } catch (_) {
      reachability.failed();
    } finally {
      _probing = false;
    }
  }
}

/// Whether this device holds any address a server could be reached from: not
/// loopback, not link-local. In airplane mode there is none, which is known
/// at once, where a ping only says so after its timeout.
Future<bool> hasNetworkAddress({
  Future<List<NetworkInterface>> Function()? list,
}) async {
  try {
    final interfaces = await (list ?? () => NetworkInterface.list())();
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (isRoutableAddress(a)) return true;
      }
    }
    return false;
  } catch (_) {
    // Cannot tell: say yes and let the ping decide.
    return true;
  }
}

bool isRoutableAddress(InternetAddress a) {
  if (a.isLoopback || a.isLinkLocal) return false;
  if (a.type == InternetAddressType.IPv4 && a.address.startsWith('169.254.')) {
    return false;
  }
  return true;
}

/// Whether the phone is on Wi-Fi: a wireless interface (`wlan*`) holds an
/// address that can reach a server. A guess from interface names, good enough
/// to keep a prefetch off mobile data; when it cannot tell, it says no.
Future<bool> onWifi({Future<List<NetworkInterface>> Function()? list}) async {
  try {
    final interfaces = await (list ?? () => NetworkInterface.list())();
    for (final i in interfaces) {
      if (!i.name.startsWith('wlan')) continue;
      if (i.addresses.any(isRoutableAddress)) return true;
    }
  } catch (_) {}
  return false;
}
