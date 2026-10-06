import 'dart:async';

import 'sync_models.dart';

/// One thing as it stands on this device.
class LocalDoc {
  const LocalDoc(this.value, [this.updatedAt]);

  /// The canonical text of it. The same state must always give the same text:
  /// it is compared against what was last sent, and a text that wobbled would
  /// be sent again every time.
  final String value;

  /// When the listener made it, if the store knows; the engine uses "now" for
  /// a change it only just noticed.
  final int? updatedAt;
}

/// A kind of thing that syncs (likes, playlists...), seen from the engine.
abstract class SyncDomain {
  bool owns(String key);

  /// False while the listener has this kind of thing switched off: nothing is
  /// sent, nothing is taken, and what was sent before is left alone (not
  /// treated as deleted).
  bool get active => true;

  /// Every document of this kind as it stands here.
  Future<Map<String, LocalDoc>> snapshot();

  /// Takes what another device decided. A null [value] is a deletion. Returns
  /// true when something a screen might show has changed.
  Future<bool> apply(String key, String? value, int updatedAt);
}

/// Where the engine remembers what the server last agreed with.
abstract class SyncMemory {
  /// key to "hash|updatedAt" (or "del|updatedAt" for a deletion), and the
  /// number to pull after.
  Future<Map<String, String>> marks();
  Future<void> writeMarks(Map<String, String?> changes);
  Future<int> cursor();
  Future<void> writeCursor(int seq);
}

class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.applied = 0,
    this.reached = false,
    this.changed = const {},
  });

  final int pushed;
  final int applied;

  /// The server answered. False means everything stays queued here.
  final bool reached;

  /// Which domains took something from another device, so the app can refresh
  /// what depends on them.
  final Set<SyncDomain> changed;
}

/// Account sync, state-based.
///
/// Nothing hooks into the stores' write paths. Each cycle looks at what is on
/// this device, compares it with what the server last agreed to, and sends the
/// difference; then takes what other devices sent. That makes offline free
/// (the difference is simply bigger next time) and means a store can change
/// how it saves without anyone remembering to tell sync.
///
/// Push before pull, on purpose: the server settles which of two writes is
/// newer, so by the time anything is pulled a conflict is already decided, and
/// "apply what came back from another device" is always right.
class SyncEngine {
  SyncEngine({
    required this.transport,
    required this.domains,
    required this.memory,
    required this.deviceId,
    this.special,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SyncTransport transport;
  final List<SyncDomain> domains;
  final SyncMemory memory;

  /// This device's id, so its own writes are not applied back to it. Null
  /// before enrolment, when there is nothing to sync.
  final Future<String?> Function() deviceId;

  /// Documents that are not state to merge (where music is playing, the
  /// queue): handed over as they arrive instead.
  final void Function(SyncDoc doc, Map<String, String> devices)? special;

  final int Function() _now;

  /// How far this device's clock is behind the server's, so the time a change
  /// is stamped with is comparable with another device's.
  int skewMs = 0;

  bool _running = false;
  bool _again = false;

  /// A round is in progress.
  bool get running => _running;

  int get _corrected => _now() + skewMs;

  /// Sends a document that is not tracked by difference (where it is playing).
  Future<bool> pushNow(List<SyncDoc> docs) async {
    final at = await transport.push([
      for (final d in docs)
        SyncDoc(key: d.key, value: d.value, updatedAt: d.updatedAt + skewMs),
    ]);
    if (at == null) return false;
    skewMs = at - _now();
    return true;
  }

  int _liveCursor = 0;

  /// The fast lane: only where the music is, the queue and commands, handed to
  /// [special]. Cheap enough to call every second or two. Keeps its own place
  /// so it never moves the main cursor (a document skipped here must still
  /// arrive in the next full round). Returns whether the server answered.
  Future<bool> pollLive() async {
    final me = await deviceId();
    if (me == null) return false;
    final main = await memory.cursor();
    if (_liveCursor < main) _liveCursor = main;
    final page = await transport.pull(_liveCursor, onlyLive: true);
    if (page == null) return false;
    if (page.serverNow > 0) skewMs = page.serverNow - _now();
    for (final doc in page.docs) {
      special?.call(doc, page.devices);
    }
    _liveCursor = page.next;
    return true;
  }

  /// One round. Safe to call as often as likes: a call during a round is
  /// folded into one more round, not run alongside it.
  Future<SyncReport> run() async {
    if (_running) {
      _again = true;
      return const SyncReport();
    }
    _running = true;
    try {
      var report = await _once();
      while (_again) {
        _again = false;
        final next = await _once();
        report = SyncReport(
          pushed: report.pushed + next.pushed,
          applied: report.applied + next.applied,
          reached: report.reached || next.reached,
          changed: {...report.changed, ...next.changed},
        );
      }
      return report;
    } finally {
      _running = false;
    }
  }

  Future<SyncReport> _once() async {
    final me = await deviceId();
    if (me == null) return const SyncReport();

    final marks = await memory.marks();
    final snap = await _snapshot();

    // What changed here since the server last agreed.
    final outgoing = <SyncDoc>[];
    final sent = <String, String?>{};
    for (final e in snap.entries) {
      final h = _hash(e.value.value);
      final mark = marks[e.key];
      if (mark != null && _markHash(mark) == h) continue;
      final at = (e.value.updatedAt ?? _now()) + skewMs;
      outgoing.add(SyncDoc(key: e.key, value: e.value.value, updatedAt: at));
      sent[e.key] = '$h|$at';
    }
    for (final e in marks.entries) {
      if (snap.containsKey(e.key) || _markHash(e.value) == 'del') continue;
      // Switched off is not deleted.
      if (domains.any((d) => !d.active && d.owns(e.key))) continue;
      final at = _corrected;
      outgoing.add(SyncDoc(key: e.key, value: null, updatedAt: at));
      sent[e.key] = 'del|$at';
    }

    var pushed = 0;
    var reached = false;
    for (var i = 0; i < outgoing.length; i += 100) {
      final batch = outgoing.skip(i).take(100).toList();
      final at = await transport.push(batch);
      // Not reached: nothing is marked, so everything not yet sent is sent
      // again next time. Nothing is lost by being offline.
      if (at == null) return SyncReport(pushed: pushed);
      reached = true;
      skewMs = at - _now();
      pushed += batch.length;
      await memory.writeMarks({for (final d in batch) d.key: sent[d.key]});
    }

    // What other devices decided.
    var cursor = await memory.cursor();
    var applied = 0;
    final changed = <SyncDomain>{};
    final took = <String>{};
    while (true) {
      final page = await transport.pull(cursor);
      if (page == null) {
        return SyncReport(
          pushed: pushed,
          applied: applied,
          reached: reached,
          changed: changed,
        );
      }
      reached = true;
      if (page.serverNow > 0) skewMs = page.serverNow - _now();
      for (final doc in page.docs) {
        if (doc.key == 'now' || doc.key == 'queue') {
          special?.call(doc, page.devices);
          continue;
        }
        if (doc.deviceId == me) continue;
        SyncDomain? domain;
        for (final d in domains) {
          if (d.owns(doc.key)) {
            domain = d;
            break;
          }
        }
        if (domain == null || !domain.active) continue;
        try {
          if (await domain.apply(doc.key, doc.value, doc.updatedAt)) {
            changed.add(domain);
          }
          took.add(doc.key);
          applied += 1;
        } catch (_) {
          // One document this build cannot read must not stop the rest, and
          // must not be retried for ever either: it is skipped and the
          // cursor moves on.
        }
      }
      cursor = page.next;
      await memory.writeCursor(cursor);
      if (!page.more) break;
    }

    // Remember what the stores now hold for everything just taken, in the
    // stores' own words, so it is not mistaken for a local change next round.
    if (took.isNotEmpty) {
      final after = await _snapshot();
      final updated = <String, String?>{};
      for (final key in took) {
        final doc = after[key];
        final at = _corrected;
        updated[key] = doc == null ? 'del|$at' : '${_hash(doc.value)}|$at';
      }
      await memory.writeMarks(updated);
    }
    return SyncReport(
      pushed: pushed,
      applied: applied,
      reached: reached,
      changed: changed,
    );
  }

  Future<Map<String, LocalDoc>> _snapshot() async {
    final out = <String, LocalDoc>{};
    for (final d in domains) {
      if (d.active) out.addAll(await d.snapshot());
    }
    return out;
  }

  static String _markHash(String mark) {
    final i = mark.indexOf('|');
    return i < 0 ? mark : mark.substring(0, i);
  }

  /// Two FNV-1a style passes folded to 32 bits each (the multiplications rely on
  /// 64-bit ints, so a web build will want its own). Not for security: it only has to tell "the same text" from
  /// "different text" without keeping a copy of every playlist.
  static String _hash(String s) {
    var a = 0x811c9dc5;
    var b = 0x01000193;
    for (final c in s.codeUnits) {
      a = ((a ^ c) * 0x01000193) & 0xffffffff;
      b = ((b ^ c) * 0x85ebca6b) & 0xffffffff;
    }
    return '${a.toRadixString(36)}${b.toRadixString(36)}';
  }
}
