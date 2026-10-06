import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connect_control.dart';
import 'sync_engine.dart';

/// Keeps the account's state in step, without anyone asking.
///
/// Runs a round when the app starts, comes back to the foreground, regains
/// the network, or when a like or a playlist changes (a moment later, so a
/// burst of taps is one round); and every half minute while open, which is how
/// a change made on the other device arrives.
class AccountSync extends ChangeNotifier {
  AccountSync({
    required this.engine,
    this.onChanged,
    this.debounce = const Duration(seconds: 3),
    this.interval = const Duration(seconds: 30),
  });

  final SyncEngine engine;

  /// Told which kinds of thing another device changed, so what depends on
  /// them (the library after a title edit) can refresh. Set by the screen that
  /// owns the library, which does not exist yet when sync starts.
  void Function(Set<SyncDomain> changed)? onChanged;
  final Duration debounce;
  final Duration interval;

  /// The server's clock in ms, as far as this device can tell: its own,
  /// corrected by how far off it was found to be.
  int serverNowMs() => DateTime.now().millisecondsSinceEpoch + engine.skewMs;

  /// The fast lane for remote control, told when the app leaves and returns.
  ConnectControl? control;

  Timer? _timer;
  Timer? _soon;
  bool _foreground = true;
  bool _disposed = false;

  DateTime? lastSyncedAt;
  bool syncing = false;

  /// False after a round that could not reach the server.
  bool reachable = true;

  void start() {
    _timer ??= Timer.periodic(interval, (_) {
      if (_foreground) unawaited(run());
    });
    unawaited(run());
  }

  void setForeground(bool value) {
    _foreground = value;
    control?.setForeground(value);
    if (value) unawaited(run());
  }

  /// A local change happened: sync shortly, folding a burst into one round.
  void poke() {
    _soon?.cancel();
    _soon = Timer(debounce, () => unawaited(run()));
  }

  Future<void> run() async {
    if (_disposed || engine.running) {
      // A round in progress will pick this change up (the engine folds a call
      // made during a round into one more).
      if (engine.running) unawaited(engine.run());
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      final report = await engine.run();
      // Not reaching the server is the ordinary state of a phone on a train;
      // it is reported, not raised.
      reachable = report.reached;
      if (report.reached) lastSyncedAt = DateTime.now();
      if (report.changed.isNotEmpty && !_disposed) {
        onChanged?.call(report.changed);
      }
    } catch (_) {
      reachable = false;
    } finally {
      syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _soon?.cancel();
    super.dispose();
  }
}
