/// Songs that are not in the library yet, as the box finds them on Soulseek
/// (tunesd getter.ts), and the gets that bring them in.
library;

/// One song out there, with the copy a get would take.
class FoundSong {
  const FoundSong({
    required this.key,
    required this.title,
    required this.artist,
    required this.format,
    required this.lossless,
    required this.peers,
    required this.username,
    required this.filename,
    required this.sizeBytes,
    this.album,
    this.bitrate,
    this.durationMs,
    this.inLibrary,
  });

  final String key;
  final String title;
  final String artist;
  final String? album;
  final String format;
  final bool lossless;
  final int? bitrate;
  final int? durationMs;
  final int sizeBytes;

  /// How many people share it.
  final int peers;
  final String username;
  final String filename;

  /// Already in the library: that song's sha.
  final String? inLibrary;

  /// "FLAC", "320 kbps".
  String get quality => lossless
      ? format
      : bitrate == null
      ? format
      : '$bitrate kbps';

  factory FoundSong.fromJson(Map<String, dynamic> j) => FoundSong(
    key: j['key'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    album: j['album'] as String?,
    format: (j['format'] as String?) ?? '',
    lossless: j['lossless'] == true,
    bitrate: (j['bitrate'] as num?)?.toInt(),
    durationMs: (j['durationMs'] as num?)?.toInt(),
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    peers: (j['peers'] as num?)?.toInt() ?? 1,
    username: j['username'] as String,
    filename: j['filename'] as String,
    inLibrary: j['inLibrary'] as String?,
  );
}

enum GetState {
  queued,
  searching,
  downloading,
  checking,
  done,
  failed,
  notFound,
}

/// A get under way or finished, as the box reports it.
class GetJob {
  const GetJob({
    required this.id,
    required this.title,
    required this.artist,
    required this.state,
    this.album,
    this.release,
    this.progress,
    this.sha,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? release;
  final GetState state;
  final double? progress;
  final String? sha;

  bool get finished =>
      state == GetState.done ||
      state == GetState.failed ||
      state == GetState.notFound;

  /// Same song, whichever job asked for it.
  String get songKey => keyOf(artist, title);

  static String keyOf(String artist, String title) =>
      '${_k(artist)}|${_k(title)}';
  static String _k(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  factory GetJob.fromJson(Map<String, dynamic> j) => GetJob(
    id: j['id'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    album: j['album'] as String?,
    release: j['release'] as String?,
    state: GetState.values.firstWhere(
      (s) => s.name == j['state'],
      orElse: () => GetState.failed,
    ),
    progress: (j['progress'] as num?)?.toDouble(),
    sha: j['sha'] as String?,
  );
}

/// One song of an album's full track list, and whether it is here.
class TracklistEntry {
  const TracklistEntry({
    required this.title,
    required this.artist,
    this.durationMs,
    this.trackNumber,
    this.discNumber,
    this.have,
  });

  final String title;
  final String artist;
  final int? durationMs;
  final int? trackNumber;
  final int? discNumber;

  /// The library's song for it, or null when it is missing.
  final String? have;

  factory TracklistEntry.fromJson(Map<String, dynamic> j) => TracklistEntry(
    title: j['title'] as String,
    artist: j['artist'] as String,
    durationMs: (j['durationMs'] as num?)?.toInt(),
    trackNumber: (j['trackNumber'] as num?)?.toInt(),
    discNumber: (j['discNumber'] as num?)?.toInt(),
    have: j['have'] as String?,
  );
}
