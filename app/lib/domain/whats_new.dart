/// What is new in this release, for the screen shown the first time it opens.
///
/// [id] names the pack. The screen is shown once per id, so a later pack gets its
/// own: change the id and the entries together.
const kWhatsNewId = 'birthday-2026-10';

class WhatsNewEntry {
  const WhatsNewEntry(this.title, this.body);

  final String title;
  final String body;
}

const kWhatsNewTitle = 'The Birthday Pack';

const kWhatsNewIntro =
    'A gift from Dylan to the boys. Here is everything that is new in Tunes.';

const kWhatsNewSignoff =
    'Made by Dylan, for the people he listens with. Tell him what you find.';

const kWhatsNew = <WhatsNewEntry>[
  WhatsNewEntry(
    'A new look',
    'Ink and lilac, names set in a serif, and covers that light the screen '
        'with their own colour.',
  ),
  WhatsNewEntry(
    'Now Playing',
    'The cover lights the page. Tap an artist\'s name to go to them. The '
        'lyrics are only there when a song has them, and you scroll down for '
        'the rest: credits, the album, the file.',
  ),
  WhatsNewEntry(
    'Lyrics you can read',
    'A full screen with the line being sung large and the rest fading around '
        'it. Pick a text size, hold a line to copy it.',
  ),
  WhatsNewEntry(
    'Artist pages in the right order',
    'The songs you have come first, then the ones you do not. Faces for the '
        'people they play with.',
  ),
  WhatsNewEntry(
    'Made for you',
    'Playlists the app builds from how you listen: Feel Good Friday, Late '
        'Night, Deep Cuts, and a lane for each kind of music you have. It also '
        'points at albums you own and never opened. All of it stays on your '
        'phone.',
  ),
  WhatsNewEntry(
    'Home that follows you',
    'On repeat is what you have had on today. Listen again is what you left a '
        'while ago. Released this year is genuinely this year.',
  ),
  WhatsNewEntry(
    'Playlists that behave',
    'Shuffle, add songs by searching, drag to reorder, swipe to remove, and '
        'Undo if that was a slip.',
  ),
  WhatsNewEntry(
    'Shuffle that does what it says',
    'Turn it on mid-song and what comes next is random. Turn it off and it '
        'carries on in order from where you are.',
  ),
  WhatsNewEntry(
    'Downloads you can see',
    'A ring that fills, a tick when it is on your phone, and a bar showing how '
        'many are coming down, from any screen.',
  ),
  WhatsNewEntry(
    'It works with no connection',
    'Offline, the app shows only what is on your phone, and search looks only '
        'there. Nothing is offered that cannot play.',
  ),
  WhatsNewEntry(
    'The little things',
    'Pull down to sync, in the same voice as everything else. Tabs that stay '
        'put wherever you are. Settings in plain words.',
  ),
];
