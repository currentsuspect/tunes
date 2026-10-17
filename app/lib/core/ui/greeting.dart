/// What the top of Home says, by the hour -- and, given a [seed], in a
/// different voice from one visit to the next.
///
/// Plain and brief, and it names the listener when the app knows who they are.
/// The small hours get their own line: this is a thing people open at 1 a.m.,
/// and "good morning" at that hour is wrong in a way they would notice.
///
/// With no seed it is the plain line. With one, the plain line still comes up
/// about one time in three -- it is the voice the others are a change from --
/// and the rest of the time it is one of a handful: warm, dry, a little silly.
/// The day matters too: Monday mornings, Friday evenings and weekends get
/// lines of their own. Every line is short, because it is set large and on
/// one line beside the avatar.
String greetingFor(DateTime now, String name, {int? seed}) {
  final hour = now.hour;
  final who = name.trim();
  final slot = switch (hour) {
    >= 5 && < 12 => _Slot.morning,
    >= 12 && < 17 => _Slot.afternoon,
    >= 17 && < 22 => _Slot.evening,
    _ => _Slot.late,
  };
  final base = switch (slot) {
    _Slot.morning => 'Good morning{n}',
    _Slot.afternoon => 'Good afternoon{n}',
    _Slot.evening => 'Good evening{n}',
    _Slot.late => 'Still up{n}',
  };
  var line = base;
  if (seed != null) {
    final pool = [..._lines[slot]!, ..._dayLines(now, slot)];
    final roll = seed.abs();
    if (roll % 3 != 0) line = pool[(roll ~/ 3) % pool.length];
  }
  return _fill(line, who);
}

enum _Slot { morning, afternoon, evening, late }

/// `{n}` is where ", Name" goes, and vanishes when there is no name, so every
/// line reads right either way.
String _fill(String line, String who) =>
    line.replaceAll('{n}', who.isEmpty ? '' : ', $who');

const _lines = {
  _Slot.morning: [
    'Morning{n}',
    'Rise and shine{n}',
    'Up already{n}?',
    'Coffee and a record?',
    'Ease into it{n}',
    'New day, new ears',
    'Top of the morning{n}',
  ],
  _Slot.afternoon: [
    'Afternoon{n}',
    'Hey{n}',
    'Halfway there{n}',
    'Post-lunch slump?',
    'Keep it moving{n}',
    'Back for more{n}?',
  ],
  _Slot.evening: [
    'Evening{n}',
    'Day done{n}?',
    'Wind-down time{n}',
    'Lights low{n}?',
    'Dinner soundtrack?',
    'Kick back{n}',
  ],
  _Slot.late: [
    "Can't sleep{n}?",
    'Night owl hours',
    'Headphones on{n}?',
    'One more song{n}?',
    'The quiet hours',
    'Late one{n}',
  ],
};

List<String> _dayLines(DateTime now, _Slot slot) => switch ((
  now.weekday,
  slot,
)) {
  (DateTime.monday, _Slot.morning) => const [
    'New week{n}',
    'Monday. Be gentle',
  ],
  (DateTime.friday, _Slot.evening) => const [
    "It's Friday{n}",
    'Weekend starts now',
  ],
  (DateTime.saturday, _Slot.morning) => const ['Slow Saturday{n}'],
  (DateTime.sunday, _Slot.morning) => const ['Easy Sunday{n}'],
  (DateTime.saturday || DateTime.friday, _Slot.late) => const ['Big night{n}?'],
  _ => const [],
};
