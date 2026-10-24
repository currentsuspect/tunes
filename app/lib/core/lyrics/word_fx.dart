/// A vocabulary of words that are images -- ice, smoke, diamonds, money,
/// high, fire -- each with two or three effects it can be sung with.
///
/// Mined from the library's own lyrics (24 Oct: 2,504 songs, 1.1M words):
/// these are the picture words that actually come up, from "money" in 647
/// songs to "drip" in 61. Words too common to mean anything on their own
/// ("time", "love", "down", "pull") are left out, or every line would move.
///
/// Which of a word's effects it gets is chosen per song and line, so the
/// same word varies across a song but is the same every time it is played.
/// At most one word per line, played only while that word is sung.
library;

enum WordFx {
  /// Icy: cool tint, a glint across the word.
  frost,

  /// Diamonds, stars, shine: sparkle glints around the word.
  sparkle,

  /// Gold, chains, rich: a warm gold sheen.
  gold,

  /// Money, racks, bands: a green flash and a lift.
  cash,

  /// Fire, lit, hot: a flickering warm glow.
  flame,

  /// Smoke, gas, lean: drifts and blurs like haze.
  haze,

  /// High, fly, sky: rises while it is sung.
  float,

  /// Low, deep, fall, drop: sinks while it is sung.
  sink,

  /// Crazy, shake, wild: shakes.
  shake,

  /// Bounce, jump: bounces.
  bounce,

  /// Shoot, bang, glock: a white flash and a kick.
  flash,

  /// Blood, dead, hell: a red tint that bleeds in.
  bleed,

  /// Cry, tears, rain: a drop falls from it.
  drip,

  /// Heart: beats.
  pulse,

  /// Slow: stretched out over its length.
  slowmo,

  /// Fast, quick: streaks in.
  rush,
}

/// Word (lower case, letters and apostrophes) to the effects it may get.
const Map<String, List<WordFx>> kWordFx = {
  // Cold
  'ice': [WordFx.frost, WordFx.sparkle],
  'iced': [WordFx.frost, WordFx.sparkle],
  'icy': [WordFx.frost, WordFx.sparkle],
  'cold': [WordFx.frost, WordFx.haze],
  'colder': [WordFx.frost, WordFx.haze],
  'freeze': [WordFx.frost, WordFx.shake],
  'frozen': [WordFx.frost, WordFx.sparkle],
  'froze': [WordFx.frost, WordFx.shake],
  'chill': [WordFx.frost, WordFx.haze],
  'snow': [WordFx.frost, WordFx.drip],
  // Shine
  'diamond': [WordFx.sparkle, WordFx.frost],
  'diamonds': [WordFx.sparkle, WordFx.frost, WordFx.gold],
  'shine': [WordFx.sparkle, WordFx.gold],
  'shinin': [WordFx.sparkle, WordFx.gold],
  'shining': [WordFx.sparkle, WordFx.gold],
  'bling': [WordFx.sparkle, WordFx.gold],
  'star': [WordFx.sparkle, WordFx.float],
  'stars': [WordFx.sparkle, WordFx.float],
  'glow': [WordFx.sparkle, WordFx.flame],
  'drip': [WordFx.drip, WordFx.sparkle],
  'drippin': [WordFx.drip, WordFx.sparkle],
  'dripping': [WordFx.drip, WordFx.sparkle],
  'vvs': [WordFx.sparkle, WordFx.frost],
  // Gold and money
  'gold': [WordFx.gold, WordFx.sparkle],
  'golden': [WordFx.gold, WordFx.sparkle],
  'chain': [WordFx.gold, WordFx.sparkle],
  'chains': [WordFx.gold, WordFx.sparkle],
  'rich': [WordFx.gold, WordFx.cash],
  'money': [WordFx.cash, WordFx.gold],
  'cash': [WordFx.cash, WordFx.gold],
  'racks': [WordFx.cash, WordFx.bounce],
  'bands': [WordFx.cash, WordFx.bounce],
  'guap': [WordFx.cash, WordFx.gold],
  'paper': [WordFx.cash, WordFx.float],
  'bread': [WordFx.cash, WordFx.gold],
  'millions': [WordFx.cash, WordFx.gold, WordFx.sparkle],
  'million': [WordFx.cash, WordFx.gold],
  'commas': [WordFx.cash, WordFx.bounce],
  // Fire
  'fire': [WordFx.flame, WordFx.flash],
  'lit': [WordFx.flame, WordFx.sparkle],
  'flame': [WordFx.flame, WordFx.haze],
  'flames': [WordFx.flame, WordFx.haze],
  'hot': [WordFx.flame, WordFx.shake],
  'heat': [WordFx.flame, WordFx.shake],
  'burn': [WordFx.flame, WordFx.haze],
  'burnin': [WordFx.flame, WordFx.haze],
  'burning': [WordFx.flame, WordFx.haze],
  'blaze': [WordFx.flame, WordFx.haze],
  // Haze
  'smoke': [WordFx.haze, WordFx.float],
  'smokin': [WordFx.haze, WordFx.float],
  'smoking': [WordFx.haze, WordFx.float],
  'gas': [WordFx.haze, WordFx.flame],
  'weed': [WordFx.haze, WordFx.float],
  'lean': [WordFx.haze, WordFx.slowmo, WordFx.drip],
  'pour': [WordFx.drip, WordFx.haze],
  'sip': [WordFx.haze, WordFx.slowmo],
  'sippin': [WordFx.haze, WordFx.slowmo],
  'drank': [WordFx.haze, WordFx.slowmo],
  'cloud': [WordFx.haze, WordFx.float],
  'clouds': [WordFx.haze, WordFx.float],
  'fog': [WordFx.haze, WordFx.frost],
  'dream': [WordFx.haze, WordFx.float],
  'dreams': [WordFx.haze, WordFx.float],
  // Up
  'high': [WordFx.float, WordFx.haze],
  'higher': [WordFx.float, WordFx.haze],
  'fly': [WordFx.float, WordFx.rush],
  'flyin': [WordFx.float, WordFx.rush],
  'flying': [WordFx.float, WordFx.rush],
  'sky': [WordFx.float, WordFx.sparkle],
  'moon': [WordFx.float, WordFx.sparkle],
  'heaven': [WordFx.float, WordFx.gold],
  'float': [WordFx.float, WordFx.haze],
  'floatin': [WordFx.float, WordFx.haze],
  'rise': [WordFx.float, WordFx.flame],
  // Down
  'low': [WordFx.sink, WordFx.slowmo],
  'lower': [WordFx.sink, WordFx.slowmo],
  'deep': [WordFx.sink, WordFx.haze],
  'deeper': [WordFx.sink, WordFx.haze],
  'fall': [WordFx.sink, WordFx.drip],
  'fallin': [WordFx.sink, WordFx.drip],
  'falling': [WordFx.sink, WordFx.drip],
  'drop': [WordFx.sink, WordFx.bounce],
  'drown': [WordFx.sink, WordFx.drip],
  'drowning': [WordFx.sink, WordFx.drip],
  'sink': [WordFx.sink, WordFx.drip],
  // Motion
  'crazy': [WordFx.shake, WordFx.bounce],
  'wild': [WordFx.shake, WordFx.bounce],
  'shake': [WordFx.shake, WordFx.bounce],
  'shakin': [WordFx.shake, WordFx.bounce],
  'bounce': [WordFx.bounce, WordFx.shake],
  'jump': [WordFx.bounce, WordFx.float],
  'jumpin': [WordFx.bounce, WordFx.float],
  'slow': [WordFx.slowmo, WordFx.haze],
  'slowly': [WordFx.slowmo, WordFx.haze],
  'fast': [WordFx.rush, WordFx.shake],
  'quick': [WordFx.rush, WordFx.flash],
  'speed': [WordFx.rush, WordFx.flame],
  'zoom': [WordFx.rush, WordFx.flash],
  // Violence
  'shoot': [WordFx.flash, WordFx.shake],
  'shootin': [WordFx.flash, WordFx.shake],
  'shots': [WordFx.flash, WordFx.shake],
  'glock': [WordFx.flash, WordFx.shake],
  'gun': [WordFx.flash, WordFx.shake],
  'bang': [WordFx.flash, WordFx.shake],
  'boom': [WordFx.flash, WordFx.shake],
  'bullet': [WordFx.flash, WordFx.rush],
  'bullets': [WordFx.flash, WordFx.rush],
  'blood': [WordFx.bleed, WordFx.drip],
  'bleed': [WordFx.bleed, WordFx.drip],
  'bleedin': [WordFx.bleed, WordFx.drip],
  'dead': [WordFx.bleed, WordFx.sink],
  'die': [WordFx.bleed, WordFx.sink],
  'hell': [WordFx.bleed, WordFx.flame],
  'devil': [WordFx.bleed, WordFx.flame],
  'demon': [WordFx.bleed, WordFx.haze],
  'demons': [WordFx.bleed, WordFx.haze],
  // Feeling
  'cry': [WordFx.drip, WordFx.haze],
  'cryin': [WordFx.drip, WordFx.haze],
  'crying': [WordFx.drip, WordFx.haze],
  'tears': [WordFx.drip, WordFx.haze],
  'rain': [WordFx.drip, WordFx.haze],
  'rainin': [WordFx.drip, WordFx.haze],
  'water': [WordFx.drip, WordFx.sink],
  'heart': [WordFx.pulse, WordFx.bleed],
  'heartbeat': [WordFx.pulse, WordFx.shake],
};

String _key(String token) => token
    .toLowerCase()
    .replaceAll(RegExp("[’']"), '')
    .replaceAll(RegExp('[^a-z]'), '');

/// The word on a line that gets an effect, and which: at most one per line.
/// The first word in the vocabulary wins, so a line reads left to right.
/// [seed] fixes the choice for this song and line.
({int index, WordFx fx})? lineWordFx(List<String> words, int seed) {
  for (var i = 0; i < words.length; i++) {
    final options = kWordFx[_key(words[i])];
    if (options == null || options.isEmpty) continue;
    final pick = (seed * 31 + i * 7 + _key(words[i]).hashCode).abs();
    return (index: i, fx: options[pick % options.length]);
  }
  return null;
}

/// A stable seed for a song's line: the same every play, different per line.
int fxSeed(String sha, int line) =>
    sha.codeUnits.take(8).fold(line * 131, (a, c) => (a * 33 + c) & 0x7fffffff);
