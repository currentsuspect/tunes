/// Parametric EQ profiles for headphones (owner, 17 Oct: tune the Wan'er
/// S.G 2 to neutral, everywhere Tunes plays). Pure Dart.
///
/// A profile is a preamp and a few filters, exactly as AutoEQ, squig.link,
/// Wavelet and Equalizer APO write them, so any measured headphone's EQ can be
/// pasted in. The player turns it into an mpv audio filter chain: ffmpeg's
/// `equalizer`, `lowshelf` and `highshelf` are the same RBJ biquads those
/// tools design with, so the numbers mean the same thing here as there.
library;

enum EqFilterType { peak, lowShelf, highShelf }

final class EqFilter {
  const EqFilter(this.type, this.freq, this.gain, this.q);

  final EqFilterType type;
  final double freq;
  final double gain;
  final double q;

  Map<String, Object> toJson() => {
    't': type.name,
    'f': freq,
    'g': gain,
    'q': q,
  };

  static EqFilter? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = EqFilterType.values.where((e) => e.name == j['t']).firstOrNull;
    final f = (j['f'] as num?)?.toDouble();
    final g = (j['g'] as num?)?.toDouble();
    final q = (j['q'] as num?)?.toDouble();
    if (t == null || f == null || g == null || q == null) return null;
    return EqFilter(t, f, g, q);
  }
}

final class EqProfile {
  const EqProfile({
    required this.id,
    required this.name,
    required this.preamp,
    required this.filters,
    this.note,
  });

  final String id;
  final String name;

  /// dB, applied before the filters; negative so boosts cannot clip.
  final double preamp;
  final List<EqFilter> filters;

  /// One line on what it is for.
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'preamp': preamp,
    'filters': [for (final f in filters) f.toJson()],
    'note': note,
  };

  static EqProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final pre = (j['preamp'] as num?)?.toDouble();
    if (id is! String || name is! String || pre == null) return null;
    return EqProfile(
      id: id,
      name: name,
      preamp: pre,
      filters: [
        for (final f in (j['filters'] as List?) ?? const [])
          ?EqFilter.fromJson(f),
      ],
      note: j['note'] as String?,
    );
  }

  /// The mpv `af` value for this profile. Filters with no gain are left out;
  /// a filter outside 20 Hz-20 kHz or with an absurd Q is never sent (mpv
  /// would refuse the whole chain and play nothing through it).
  ///
  /// [shelves] false gives the Android chain (see [mpvChain]). Its libmpv
  /// (media_kit_libs_android_audio, mpv 0.35) is built with every ffmpeg
  /// filter off except `equalizer`, so a `lowshelf` or `volume` made mpv
  /// refuse the chain and skip every song (17 Oct). There each shelf becomes
  /// peaking bands fitted to the same curve (see [shelfAsPeaks]).
  String toMpvAf({bool shelves = true}) => mpvChain(full: shelves).af;

  /// The chain for a given libmpv. [full] is desktop mpv, with every ffmpeg
  /// filter: the preamp is a `volume` filter in the chain. Otherwise (the
  /// Android build: `equalizer` only, no `volume`, no shelves) shelves become
  /// peaks and the preamp comes back as [preampDb] for the player to apply
  /// through mpv's own volume.
  ({String af, double preampDb}) mpvChain({required bool full}) {
    final shelves = full;
    var pre = preamp;
    final bands = <EqFilter>[];
    for (final f in filters) {
      final usable =
          f.gain != 0 &&
          f.freq >= 10 &&
          f.freq <= 22000 &&
          f.q > 0 &&
          f.q <= 20;
      if (!usable) continue;
      if (shelves || f.type == EqFilterType.peak) {
        bands.add(f);
      } else {
        final (peaks, flat) = shelfAsPeaks(f);
        bands.addAll(peaks);
        pre += flat;
      }
    }
    final parts = <String>[
      if (full && pre.abs() >= 0.005) 'volume=${_n(pre)}dB',
      for (final f in bands)
        switch (f.type) {
          EqFilterType.peak =>
            'equalizer=f=${_n(f.freq)}:t=q:w=${_n(f.q)}:g=${_n(f.gain)}',
          EqFilterType.lowShelf =>
            'lowshelf=f=${_n(f.freq)}:t=q:w=${_n(f.q)}:g=${_n(f.gain)}',
          EqFilterType.highShelf =>
            'highshelf=f=${_n(f.freq)}:t=q:w=${_n(f.q)}:g=${_n(f.gain)}',
        },
    ];
    return (
      af: parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]',
      preampDb: full ? 0.0 : pre,
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// A shelf as peaking bands plus a flat gain, for players with no shelf
/// filter. Fitted 17 Oct by least squares against RBJ shelves (Q 0.71) of
/// -9..+9 dB: a low shelf is two peaks, within 0.5 dB everywhere; a high
/// shelf is three peaks kept under 19 kHz, within about 1.4 dB below 16 kHz
/// for +/-6 dB.
(List<EqFilter>, double) shelfAsPeaks(EqFilter s) {
  final g = s.gain;
  EqFilter pk(double f, double gain, double q) =>
      EqFilter(EqFilterType.peak, f.clamp(10, 19000).toDouble(), gain, q);
  if (s.type == EqFilterType.lowShelf) {
    return (
      [
        pk(s.freq * 0.124, g * 1.002, 0.253),
        pk(s.freq * 0.593, g * 0.484, 0.84),
      ],
      g * -0.012,
    );
  }
  return (
    [
      pk(s.freq * 1.382, g * 0.243, 1.575),
      pk(s.freq * 2.375, g * 0.458, 0.46),
      pk(s.freq * 6.906, g * 0.749, 0.251),
    ],
    g * -0.01,
  );
}

/// Reads EQ text the way AutoEQ, squig.link and Equalizer APO write it:
///
///     Preamp: -4.8 dB
///     Filter 1: ON LSC Fc 97 Hz Gain -6.0 dB Q 0.71
///     Filter 2: ON PK Fc 173 Hz Gain -2.6 dB Q 1.05
///
/// PK/PEQ are peaks, LSC/LS/LSQ low shelves, HSC/HS/HSQ high shelves. Lines
/// switched OFF are skipped. Null when no filter could be read.
EqProfile? parseEqText(
  String text, {
  required String id,
  required String name,
}) {
  double preamp = 0;
  final filters = <EqFilter>[];
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    final line = raw.trim();
    final pre = RegExp(
      r'^preamp\s*:?\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(line);
    if (pre != null) {
      preamp = double.parse(pre.group(1)!);
      continue;
    }
    final m = RegExp(
      r'filter\s*\d*\s*:\s*(on|off)\s+(\w+)\s+fc\s+(\S+)\s*hz\s+gain\s+(\S+)\s*db(?:\s+q\s+(\S+))?',
      caseSensitive: false,
    ).firstMatch(line);
    if (m == null || m.group(1)!.toLowerCase() == 'off') continue;
    final type = switch (m.group(2)!.toUpperCase()) {
      'PK' || 'PEQ' || 'PEAK' => EqFilterType.peak,
      'LSC' || 'LS' || 'LSQ' || 'LOWSHELF' => EqFilterType.lowShelf,
      'HSC' || 'HS' || 'HSQ' || 'HIGHSHELF' => EqFilterType.highShelf,
      _ => null,
    };
    final f = double.tryParse(m.group(3)!);
    final g = double.tryParse(m.group(4)!);
    final q = m.group(5) == null
        ? (type == EqFilterType.peak ? 1.0 : 0.71)
        : double.tryParse(m.group(5)!);
    if (type == null || f == null || g == null || q == null) continue;
    filters.add(EqFilter(type, f, g, q));
  }
  if (filters.isEmpty) return null;
  return EqProfile(id: id, name: name, preamp: preamp, filters: filters);
}

/// Profiles that come with the app.
abstract final class BuiltInEq {
  /// Tuned 17 Oct from Reference Audio Analyzer's IEC 711 measurement of the
  /// Red Lion edition, then by ear with the owner: Harman IE 2019 bass (the
  /// first cut, 4 dB under it, was "too lean"), the Wan'er's 700-800 Hz
  /// hollow filled and a little 1.5-2 kHz edge taken off ("female vocals
  /// sound hollow"), presence lifted, the 8 kHz peak calmed, treble above
  /// 10 kHz left for air. Owner: "It's perfect now."
  static const wanerRedLionNeutral = EqProfile(
    id: 'waner-sg2-red-lion-neutral',
    name: "Wan'er S.G 2 Red Lion: Neutral",
    note: 'Takes the V out: full bass, clear vocals, calmer 8 kHz.',
    preamp: -4.8,
    filters: [
      EqFilter(EqFilterType.lowShelf, 97, -3.5, 0.71),
      EqFilter(EqFilterType.peak, 173, -1.5, 1.05),
      EqFilter(EqFilterType.peak, 750, 1.6, 1.4),
      EqFilter(EqFilterType.peak, 1900, -1.0, 1.4),
      EqFilter(EqFilterType.peak, 4500, 2.5, 1.52),
      EqFilter(EqFilterType.peak, 6188, 3.5, 2.0),
      EqFilter(EqFilterType.peak, 8645, -2.6, 2.5),
    ],
  );

  static const all = [wanerRedLionNeutral];
}
