/// What the top of Home says, by the hour.
///
/// Plain and brief, and it names the listener when the app knows who they are.
/// The small hours get their own line: this is a thing people open at 1 a.m.,
/// and "good morning" at that hour is wrong in a way they would notice.
String greetingFor(DateTime now, String name) {
  final hour = now.hour;
  final who = name.trim();
  final base = switch (hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 17 => 'Good afternoon',
    >= 17 && < 22 => 'Good evening',
    _ => 'Still up',
  };
  return who.isEmpty ? base : '$base, $who';
}
