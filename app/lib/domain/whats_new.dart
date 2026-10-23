/// What is new in this release, for the screen shown the first time it opens.
///
/// [id] names the pack. The screen is shown once per id, so a later pack gets its
/// own: change the id and the entries together.
const kWhatsNewId = 'asked-for-2026-10';

class WhatsNewEntry {
  const WhatsNewEntry(this.title, this.body);

  final String title;
  final String body;
}

const kWhatsNewTitle = 'You Asked For It';

const kWhatsNewIntro =
    'Most of this came from you. Dennis asked for half of it. Here is '
    'everything new since the Birthday Pack.';

const kWhatsNewSignoff =
    'Made by Dylan, for the people he listens with. Keep asking.';

const kWhatsNew = <WhatsNewEntry>[
  WhatsNewEntry(
    'Search that gets you',
    'Songs, albums, artists and playlists, each with a count. "travis 2018" '
        'means Travis Scott in 2018; tap a chip to undo how it read you. '
        'Typos are fine.',
  ),
  WhatsNewEntry(
    'Find a song by its words',
    'Type a line you remember. Tunes finds the song and shows you the line.',
  ),
  WhatsNewEntry(
    "Get songs you don't have",
    "If it isn't in the library, search asks Soulseek. Tap Get and it lands "
        "in everyone's library, cover and all.",
  ),
  WhatsNewEntry(
    "Albums show what's missing",
    "The songs you don't have sit in their places, greyed out. Get one, or "
        'get them all.',
  ),
  WhatsNewEntry(
    'Fix a mix',
    'Swipe a song out of a mix the app made. It stays out, and the mix keeps '
        'its length.',
  ),
  WhatsNewEntry(
    'Your listening, tappable',
    'Top artists, albums and songs take you to the real thing.',
  ),
  WhatsNewEntry(
    'Three looks',
    'Room, Noir and Crayon, each light and dark. Crayon tapes the real cover '
        'into a notebook.',
  ),
  WhatsNewEntry(
    'You on every device',
    "Likes, playlists and history follow your account. See what's playing "
        'on your other phone or computer, and control it from here.',
  ),
  WhatsNewEntry(
    'Radio with a mood',
    'Pick how adventurous it gets. It reaches a little further now and then, '
        'and forgets what you have worn out.',
  ),
  WhatsNewEntry(
    'Lyrics for everyone',
    'Add lyrics to a song and everyone sees them.',
  ),
  WhatsNewEntry(
    'Headphone EQ',
    'Profiles in Settings, applied to everything you play.',
  ),
  WhatsNewEntry(
    'Updates that wait for you',
    'Say "not now" on Home and the update waits in Settings until you are '
        'ready.',
  ),
];
