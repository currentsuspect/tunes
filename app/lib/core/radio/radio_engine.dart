import 'dart:math';

import '../../domain/manifest.dart';
import '../../domain/mixes.dart' show vagueTags;
import 'session.dart';

/// What the listener has done over time, independent of this session.
///
/// Passed in rather than read here so the engine stays a pure function of its
/// inputs and can be tested without a database (AGENTS.md §1, §6).
class TasteSnapshot {
  const TasteSnapshot({
    this.playCounts = const {},
    this.skipCounts = const {},
    this.artistTags = const {},
    this.recentPlays = const {},
    this.tagWeights = const {},
    this.artistGenres = const {},
    this.affinity = const {},
    this.neighbours = const {},
  });

  /// Builds a snapshot with everything derived in one place: tag weights over
  /// the same tokens the radio compares (clean genres where the box sent
  /// them, raw tags otherwise), and which genre families sit next to each
  /// other in this library.
  factory TasteSnapshot.build({
    Map<String, int> playCounts = const {},
    Map<String, int> skipCounts = const {},
    Map<String, List<String>> artistTags = const {},
    Map<String, int> recentPlays = const {},
    Map<String, List<ArtistGenre>> artistGenres = const {},
    Map<String, double> affinity = const {},
  }) {
    final draft = TasteSnapshot(
      artistTags: artistTags,
      artistGenres: artistGenres,
    );
    final seen = <String, int>{};
    for (final act in {...artistTags.keys, ...artistGenres.keys}) {
      for (final k in draft.tagsOf(act)) {
        seen[k] = (seen[k] ?? 0) + 1;
      }
    }
    return TasteSnapshot(
      playCounts: playCounts,
      skipCounts: skipCounts,
      artistTags: artistTags,
      recentPlays: recentPlays,
      artistGenres: artistGenres,
      affinity: affinity,
      tagWeights: {
        for (final e in seen.entries) e.key: 1 / (1 + log(1 + e.value / 5)),
      },
      neighbours: neighbourFamilies(artistGenres),
    );
  }

  /// Lower-cased act name -> its clean genres from the box (tunesd
  /// genres.ts), strongest first. Preferred over [artistTags] when present.
  final Map<String, List<ArtistGenre>> artistGenres;

  /// sha -> how much this track is loved *now*: completed plays, each
  /// counting less the older it is (see [fadedAffinity]). Empty means "use
  /// the all-time [playCounts]", which is what older callers pass.
  final Map<String, double> affinity;

  /// Family -> families this library pairs with it: acts tagged in both.
  /// Where "next door" goes when it leaves a family.
  final Map<String, Set<String>> neighbours;

  /// Genre families that sit together in this library: two or more acts
  /// carry both.
  static Map<String, Set<String>> neighbourFamilies(
    Map<String, List<ArtistGenre>> artistGenres,
  ) {
    final pairs = <(String, String), int>{};
    for (final gs in artistGenres.values) {
      final fams = {for (final g in gs) g.family}.toList()..sort();
      for (var i = 0; i < fams.length; i++) {
        for (var j = i + 1; j < fams.length; j++) {
          final k = (fams[i], fams[j]);
          pairs[k] = (pairs[k] ?? 0) + 1;
        }
      }
    }
    final out = <String, Set<String>>{};
    for (final MapEntry(key: (a, b), value: n) in pairs.entries) {
      if (n < 2) continue;
      out.putIfAbsent(a, () => {}).add(b);
      out.putIfAbsent(b, () => {}).add(a);
    }
    return out;
  }

  /// Plays faded by age: each counts 0.5 ^ (days ago / [halfLifeDays]). A song
  /// played twenty times a year ago and never since weighs less than one
  /// played five times this month, so old favourites stop locking in.
  static Map<String, double> fadedAffinity(
    Iterable<({String sha, DateTime at})> stamps, {
    required DateTime now,
    double halfLifeDays = 45,
  }) {
    final out = <String, double>{};
    for (final p in stamps) {
      final days = now.difference(p.at).inHours / 24;
      final w = pow(0.5, max(0, days) / halfLifeDays).toDouble();
      out[p.sha] = (out[p.sha] ?? 0) + w;
    }
    return out;
  }

  /// How loved [sha] is now: faded when [affinity] is known, else all-time.
  double affinityOf(String sha) =>
      affinity.isEmpty ? playsOf(sha).toDouble() : (affinity[sha] ?? 0);

  /// The genre families of an act, strongest first; empty without genres.
  List<String> familiesOf(String act) {
    final gs = artistGenres[act.toLowerCase()];
    if (gs == null) return const [];
    return {for (final g in gs.take(2)) g.family}.toList();
  }

  /// How much each tag says, 0..1: a tag on a third of the library ("rap")
  /// tells you little about which song to play next, one on a handful
  /// ("plugg", "afroswing") tells you a lot. Built by [weighTags]; a tag with
  /// no entry counts in full.
  final Map<String, double> tagWeights;

  /// Weights for [artistTags]: the rarer the tag, the more it counts.
  static Map<String, double> weighTags(Map<String, List<String>> artistTags) {
    final seen = <String, int>{};
    for (final raw in artistTags.values) {
      final keys = <String>{
        for (final t in raw.take(5))
          if (!vagueTags.contains(t.toLowerCase())) _key(t),
      }..remove('');
      for (final k in keys) {
        seen[k] = (seen[k] ?? 0) + 1;
      }
    }
    return {
      for (final e in seen.entries) e.key: 1 / (1 + log(1 + e.value / 5)),
    };
  }

  static String _key(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  double weightOf(String tag) => tagWeights[tag] ?? 1.0;

  /// sha -> times played to completion.
  final Map<String, int> playCounts;

  /// sha -> times abandoned.
  final Map<String, int> skipCounts;

  /// Lower-cased act name -> what kind of music it is called ("trap",
  /// "afrobeats"). The only idea of genre the radio has, and what lets it stay
  /// in the kind of music the listener is in the middle of.
  final Map<String, List<String>> artistTags;

  /// sha -> times played in the last week. What keeps the same favourites from
  /// coming round every time, however well they fit.
  final Map<String, int> recentPlays;

  int playsOf(String sha) => playCounts[sha] ?? 0;
  int skipsOf(String sha) => skipCounts[sha] ?? 0;
  int recentPlaysOf(String sha) => recentPlays[sha] ?? 0;

  /// The tags for an act, normalised and without the ones too general to say
  /// anything ("seen live", "american").
  Set<String> tagsOf(String act) {
    // Clean genres when the box sent them: the genre, and its family as a
    // weaker shared token, so Rage and Plugg are neighbours, not strangers.
    final gs = artistGenres[act.toLowerCase()];
    if (gs != null && gs.isNotEmpty) {
      return {
        for (final g in gs.take(2)) ...['g:${g.name}', 'f:${g.family}'],
      };
    }
    final raw = artistTags[act.toLowerCase()];
    if (raw == null) return const {};
    return {
      for (final t in raw.take(5))
        if (!vagueTags.contains(t.toLowerCase()))
          t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ''),
    }..remove('');
  }
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

  /// The least and most top candidates to sample from. docs/RADIO.md §4:
  /// always taking the maximum converges on one loop and starts to feel
  /// algorithmic. The width grows with how adventurous the session is; it used
  /// to be 1 to 4, which at the usual 0.2 meant choosing between the top two
  /// of a thousand tracks, and the next song could be guessed.
  static const _minWindow = 6;
  static const _extraWindow = 54;

  /// How sharply the pick favours the best of the window. Smaller is closer to
  /// always the best; larger is closer to a coin toss across the window. It
  /// loosens as the listener asks for further out.
  static const _baseTemperature = 0.08;
  static const _extraTemperature = 0.25;

  /// Picks the next track, or null when the library has nothing eligible.
  ManifestTrack? next({
    required List<ManifestTrack> library,
    required RadioSession session,
    required TasteSnapshot taste,
    ManifestTrack? current,
  }) {
    final stretch = session.stretchTurn;
    var ranked = rank(
      library: library,
      session: session,
      taste: taste,
      current: current,
      stretch: stretch,
    );
    if (ranked.isEmpty) return null;
    session.picked();
    lastStretch = stretch;

    // Sample from the top few, weighted by rank. The width grows with the
    // exploration level, so a listener who keeps skipping gets tighter, more
    // predictable choices and one who lets things play gets more variety.
    final width = _minWindow + (session.exploration * _extraWindow).round();
    final pool = ranked.take(min(width, ranked.length)).toList();
    // Weighted by score, not uniform: better fits come up more often, but the
    // ones just behind them still do.
    final best = pool.first.score;
    final temperature =
        _baseTemperature + _extraTemperature * session.exploration;
    final weights = [for (final c in pool) exp((c.score - best) / temperature)];
    var roll = _random.nextDouble() * weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < pool.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return pool[i].track;
    }
    return pool.last.track;
  }

  /// Whether the last pick from [next] was a stretch: the queue can say so.
  bool lastStretch = false;

  /// Every eligible candidate, best first. [stretch] ranks for the reserved
  /// slot: next door to what is playing, not more of it.
  List<ScoredTrack> rank({
    required List<ManifestTrack> library,
    required RadioSession session,
    required TasteSnapshot taste,
    ManifestTrack? current,
    bool stretch = false,
  }) {
    final vibe = _vibe(session, taste, current);
    final out = <ScoredTrack>[];
    for (final t in library) {
      // Never suggest what is playing, and never re-suggest something already
      // rejected this session. Both would read as the radio not listening.
      if (current != null && t.sha == current.sha) continue;
      if (session.wasSkipped(t.sha)) continue;

      final reasons = _score(t, session, taste, current, vibe, stretch);
      final total = reasons.values.fold(0.0, (a, b) => a + b);
      out.add(ScoredTrack(t, total, reasons));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// The kind of music the listener is in right now: the tags of what is
  /// playing, and, fading with each step back, of the acts before it. A weight
  /// per tag, so one track of something new does not erase an hour of
  /// something else, and an hour of something new is not undone by one old
  /// favourite.
  Map<String, double> _vibe(
    RadioSession session,
    TasteSnapshot taste,
    ManifestTrack? current,
  ) {
    final vibe = <String, double>{};
    void add(Set<String> tags, double weight) {
      for (final t in tags) {
        vibe[t] = (vibe[t] ?? 0) + weight * taste.weightOf(t);
      }
    }

    if (current != null) {
      add(taste.tagsOf(current.artistKey), 1.0);
    }
    var weight = 0.9;
    for (final act in session.recentArtists.take(8)) {
      add(taste.tagsOf(act), weight);
      weight *= 0.8;
    }
    return vibe;
  }

  Map<String, double> _score(
    ManifestTrack candidate,
    RadioSession session,
    TasteSnapshot taste,
    ManifestTrack? current,
    Map<String, double> vibe,
    bool stretch,
  ) {
    final reasons = <String, double>{};

    // Fit with the kind of music playing now. Only when both sides have tags:
    // an act nobody has tagged is neither rewarded nor punished, so a young
    // library still works.
    final tags = taste.tagsOf(candidate.artistKey);
    double? lane;
    if (vibe.isNotEmpty && tags.isNotEmpty) {
      final top = vibe.values.toList()..sort((a, b) => b.compareTo(a));
      final norm = top.take(3).fold(0.0, (a, b) => a + b);
      final shared = tags.fold(0.0, (a, t) => a + (vibe[t] ?? 0));
      lane = norm == 0 ? 0.0 : (shared / norm).clamp(0.0, 1.0);
      if (stretch) {
        _stretch(reasons, lane, candidate, taste, vibe, session);
      } else {
        // The pull of the lane eases as the listener asks to go further out.
        reasons['lane'] = 0.45 * (1 - 0.5 * session.exploration) * lane;
        // Nothing in common with what is playing. Softer the more adventurous
        // the listener has said they are, so the dial still lets it wander.
        if (shared == 0) {
          reasons['off-lane'] = -0.25 * (1 - session.exploration);
        }
      }
    }

    // Taste: how much this track has earned, damped so a single favourite
    // cannot dominate a 600-track library forever. Scaled by the fit: a
    // favourite from some other kind of music used to win anyway, which is why
    // the radio kept snapping back to the same songs.
    // Loved now, not loved once: plays fade with age (TasteSnapshot
    // .fadedAffinity), so last year's favourites stop locking the radio in.
    final plays = taste.playsOf(candidate.sha);
    final loved = taste.affinityOf(candidate.sha);
    if (loved > 0) {
      reasons['taste'] =
          0.30 *
          (1 - 1 / (1 + loved)) *
          (lane == null ? 1.0 : 0.35 + 0.65 * lane) *
          // A stretch is for what she does not already know by heart.
          (stretch ? 0.4 : 1.0);
    }

    // Worn out: played already this week, however well it fits.
    final worn = taste.recentPlaysOf(candidate.sha);
    if (worn > 0) reasons['fatigue'] = -0.10 * min(worn, 4);

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
      reasons['novelty'] = 0.20 * session.exploration + (stretch ? 0.10 : 0);
    }

    // A small amount of noise so equal scores do not always resolve the same
    // way. Deterministic under an injected Random, so tests stay stable.
    reasons['jitter'] = _random.nextDouble() * 0.02;

    return reasons;
  }

  /// The reserved slot (session.stretchEvery). Too close is pushed away;
  /// next door (sharing the family, or a little of the vibe) is pulled in;
  /// a family this library pairs with the current one counts as next door
  /// too. Further than that only when the listener asked for surprises.
  void _stretch(
    Map<String, double> reasons,
    double lane,
    ManifestTrack candidate,
    TasteSnapshot taste,
    Map<String, double> vibe,
    RadioSession session,
  ) {
    if (lane > 0.6) {
      reasons['too-close'] = -0.40;
    } else if (lane > 0) {
      // Peaks a little way out, not at the edge.
      reasons['next-door'] = 0.40 * (1 - (lane - 0.25).abs() / 0.75);
    } else {
      final here = <String>{
        for (final k in vibe.keys)
          if (k.startsWith('f:')) k.substring(2),
      };
      final there = taste.familiesOf(candidate.artistKey);
      final adjacent = there.any(
        (f) => here.any((h) => taste.neighbours[h]?.contains(f) ?? false),
      );
      // A family away: held back, unless the listener asked for surprises,
      // where it is part of the point.
      reasons[adjacent ? 'next-family' : 'far'] = adjacent
          ? 0.30
          : -0.30 * (1 - session.exploration) +
                0.25 * max(0.0, session.exploration - 0.7) / 0.3;
    }
  }
}
