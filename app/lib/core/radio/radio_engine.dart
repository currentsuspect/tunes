import 'dart:math';

import '../../domain/manifest.dart';
import 'session.dart';

/// What the listener has done over time, independent of this session.
///
/// Passed in rather than read here so the engine stays a pure function of its
/// inputs and can be tested without a database (AGENTS.md §1, §6).
class TasteSnapshot {
  const TasteSnapshot({this.playCounts = const {}, this.skipCounts = const {}});

  /// sha -> times played to completion.
  final Map<String, int> playCounts;

  /// sha -> times abandoned.
  final Map<String, int> skipCounts;

  int playsOf(String sha) => playCounts[sha] ?? 0;
  int skipsOf(String sha) => skipCounts[sha] ?? 0;
}

/// One scored candidate. Kept visible so the mix can be inspected rather than
/// guessed at -- docs/RADIO.md §4 wants the radio to know its own proportions
/// even though the listener never sees them.
class ScoredTrack {
  const ScoredTrack(this.track, this.score, this.reasons);
  final ManifestTrack track;
  final double score;

  /// Component name -> contribution. Sums to [score].
  final Map<String, double> reasons;
}

/// Behaviour-only sequencing: generator 3 of docs/RADIO.md §4.
///
/// The other two generators need substrate that does not exist yet -- audio
/// embeddings are unbuilt, and producer/label edges are absent from the tag
/// data. This is the piece that can run today, on the play history the app
/// already keeps, with the scoring seam shaped so the others slot in beside
/// it rather than replacing it.
///
/// Everything here is a pure function of (library, session, taste, seed). No
/// I/O, no Flutter, no clock. That is what makes "given this session, it
/// picks that track" a testable claim rather than an impression.
class RadioEngine {
  RadioEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// How many top candidates to sample from rather than always taking the
  /// best. docs/RADIO.md §4: always taking the maximum converges on one loop
  /// and starts to feel algorithmic.
  static const _sampleWindow = 4;

  /// Picks the next track, or null when the library has nothing eligible.
  ManifestTrack? next({
    required List<ManifestTrack> library,
    required RadioSession session,
    required TasteSnapshot taste,
    ManifestTrack? current,
  }) {
    final ranked = rank(
      library: library,
      session: session,
      taste: taste,
      current: current,
    );
    if (ranked.isEmpty) return null;

    // Sample from the top few, weighted by rank. The width grows with the
    // exploration level, so a listener who keeps skipping gets tighter, more
    // predictable choices and one who lets things play gets more variety.
    final width = 1 + (session.exploration * (_sampleWindow - 1)).round();
    final pool = ranked.take(min(width, ranked.length)).toList();
    return pool[_random.nextInt(pool.length)].track;
  }

  /// Every eligible candidate, best first.
  List<ScoredTrack> rank({
    required List<ManifestTrack> library,
    required RadioSession session,
    required TasteSnapshot taste,
    ManifestTrack? current,
  }) {
    final out = <ScoredTrack>[];
    for (final t in library) {
      // Never suggest what is playing, and never re-suggest something already
      // rejected this session. Both would read as the radio not listening.
      if (current != null && t.sha == current.sha) continue;
      if (session.wasSkipped(t.sha)) continue;

      final reasons = _score(t, session, taste, current);
      final total = reasons.values.fold(0.0, (a, b) => a + b);
      out.add(ScoredTrack(t, total, reasons));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  Map<String, double> _score(
    ManifestTrack candidate,
    RadioSession session,
    TasteSnapshot taste,
    ManifestTrack? current,
  ) {
    final reasons = <String, double>{};

    // Taste: how much this track has earned, damped so a single favourite
    // cannot dominate a 600-track library forever.
    final plays = taste.playsOf(candidate.sha);
    if (plays > 0) reasons['taste'] = 0.30 * (1 - 1 / (1 + plays));

    // Long-run dislike. Distinct from a session skip: that one is absolute,
    // this one is a lasting lean away.
    final skips = taste.skipsOf(candidate.sha);
    if (skips > 0) reasons['disliked'] = -0.35 * (1 - 1 / (1 + skips));

    // Continuity with what is playing. The only "musical fit" available
    // without embeddings: same act, then same release, then the guest graph
    // (features are the one relationship edge the tags actually carry).
    if (current != null) {
      final a = (candidate.primaryArtist ?? candidate.artist).toLowerCase();
      final b = (current.primaryArtist ?? current.artist).toLowerCase();
      if (a.isNotEmpty && a == b) reasons['same-artist'] = 0.25;
      final ra = candidate.releaseId, rb = current.releaseId;
      if (ra != null && ra.isNotEmpty && ra == rb) {
        reasons['same-release'] = 0.15;
      }
      final cg = candidate.featured.map((g) => g.toLowerCase()).toSet();
      final ug = current.featured.map((g) => g.toLowerCase()).toSet();
      if (a.isNotEmpty && ug.contains(a)) {
        // The current track features this candidate's act.
        reasons['feature-in'] = 0.20;
      } else if (b.isNotEmpty && cg.contains(b)) {
        // This candidate features the current act.
        reasons['feature-out'] = 0.20;
      } else if (cg.intersection(ug).isNotEmpty) {
        // A shared guest: adjacent territory through a third act.
        reasons['shared-guest'] = 0.12;
      }
    }

    // Repetition penalties. These are what stop a "radio" being a shuffle
    // that keeps landing on the same six songs.
    if (session.wasRecentlyPlayed(candidate.sha)) {
      reasons['repeat-track'] = -0.80;
    }
    final act = (candidate.primaryArtist ?? candidate.artist);
    final recentArtist = session.recentCountFor(act);
    if (recentArtist > 0) {
      // Grows with each repeat rather than being flat: two in a row is a
      // choice, four in a row is a rut.
      reasons['repeat-artist'] = -0.12 * recentArtist;
    }
    // Lookahead: the scorer optimizes one track, so sequences are policed
    // here, not in the weights. Newest first: a third consecutive track by
    // one act, or the close of an A-B-A-B alternation, is penalized no
    // matter how strong its local fit.
    final recent = session.recentArtists;
    final al = act.toLowerCase();
    if (recent.length >= 2 &&
        recent[0].toLowerCase() == al &&
        recent[1].toLowerCase() == al) {
      reasons['run'] = -0.30;
    } else if (recent.length >= 3 &&
        recent[1].toLowerCase() == al &&
        recent[0].toLowerCase() == recent[2].toLowerCase() &&
        recent[0].toLowerCase() != al) {
      reasons['alternation'] = -0.25;
    }

    // Novelty, scaled by how adventurous the session currently is. A track
    // never played is worth more when the listener has been letting things
    // run, and worth less right after a skip.
    if (plays == 0) {
      reasons['novelty'] = 0.20 * session.exploration;
    }

    // A small amount of noise so equal scores do not always resolve the same
    // way. Deterministic under an injected Random, so tests stay stable.
    reasons['jitter'] = _random.nextDouble() * 0.02;

    return reasons;
  }
}
