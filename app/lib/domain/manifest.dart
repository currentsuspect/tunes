class ManifestTrack {
  const ManifestTrack({
    required this.sha,
    required this.size,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitrate,
    required this.durationMs,
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.artSha,
  });

  final String sha;
  final int size;
  final String? codec;
  final int? sampleRate;
  final int? channels;
  final int? bitrate;
  final int? durationMs;
  final String title;
  final String artist;
  final String album;
  final String? year;
  final String? artSha;

  factory ManifestTrack.fromJson(Map<String, dynamic> json) {
    return ManifestTrack(
      sha: json['sha'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      codec: json['codec'] as String?,
      sampleRate: (json['sampleRate'] as num?)?.toInt(),
      channels: (json['channels'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      title: (json['title'] as String?) ?? 'untitled',
      artist: (json['artist'] as String?) ?? 'unknown artist',
      album: (json['album'] as String?) ?? 'unknown album',
      year: json['year'] as String?,
      artSha: json['artSha'] as String?,
    );
  }

  String get qualityLabel {
    if (codec == null) return 'unknown';
    final label = codec!.toUpperCase();
    if (bitrate == null) return label;
    return '$label ${(bitrate! / 1000).round()}k';
  }

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '';
    final seconds = (ms / 1000).round();
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
