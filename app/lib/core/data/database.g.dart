// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shaMeta = const VerificationMeta('sha');
  @override
  late final GeneratedColumn<String> sha = GeneratedColumn<String>(
    'sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
    'codec',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sampleRateMeta = const VerificationMeta(
    'sampleRate',
  );
  @override
  late final GeneratedColumn<int> sampleRate = GeneratedColumn<int>(
    'sample_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelsMeta = const VerificationMeta(
    'channels',
  );
  @override
  late final GeneratedColumn<int> channels = GeneratedColumn<int>(
    'channels',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bitrateMeta = const VerificationMeta(
    'bitrate',
  );
  @override
  late final GeneratedColumn<int> bitrate = GeneratedColumn<int>(
    'bitrate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('untitled'),
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown artist'),
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown album'),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<String> year = GeneratedColumn<String>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artShaMeta = const VerificationMeta('artSha');
  @override
  late final GeneratedColumn<String> artSha = GeneratedColumn<String>(
    'art_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseIdMeta = const VerificationMeta(
    'releaseId',
  );
  @override
  late final GeneratedColumn<String> releaseId = GeneratedColumn<String>(
    'release_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseIdsJsonMeta = const VerificationMeta(
    'releaseIdsJson',
  );
  @override
  late final GeneratedColumn<String> releaseIdsJson = GeneratedColumn<String>(
    'release_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNumberMeta = const VerificationMeta(
    'discNumber',
  );
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
    'disc_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalTracksMeta = const VerificationMeta(
    'totalTracks',
  );
  @override
  late final GeneratedColumn<int> totalTracks = GeneratedColumn<int>(
    'total_tracks',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _embeddedTitleMeta = const VerificationMeta(
    'embeddedTitle',
  );
  @override
  late final GeneratedColumn<String> embeddedTitle = GeneratedColumn<String>(
    'embedded_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddedArtistMeta = const VerificationMeta(
    'embeddedArtist',
  );
  @override
  late final GeneratedColumn<String> embeddedArtist = GeneratedColumn<String>(
    'embedded_artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddedAlbumMeta = const VerificationMeta(
    'embeddedAlbum',
  );
  @override
  late final GeneratedColumn<String> embeddedAlbum = GeneratedColumn<String>(
    'embedded_album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddedYearMeta = const VerificationMeta(
    'embeddedYear',
  );
  @override
  late final GeneratedColumn<String> embeddedYear = GeneratedColumn<String>(
    'embedded_year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lyricsMeta = const VerificationMeta('lyrics');
  @override
  late final GeneratedColumn<String> lyrics = GeneratedColumn<String>(
    'lyrics',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lyricsSourceMeta = const VerificationMeta(
    'lyricsSource',
  );
  @override
  late final GeneratedColumn<String> lyricsSource = GeneratedColumn<String>(
    'lyrics_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sha,
    size,
    codec,
    sampleRate,
    channels,
    bitrate,
    durationMs,
    title,
    artist,
    album,
    year,
    artSha,
    releaseId,
    releaseIdsJson,
    trackNumber,
    discNumber,
    totalTracks,
    addedAt,
    searchText,
    embeddedTitle,
    embeddedArtist,
    embeddedAlbum,
    embeddedYear,
    lyrics,
    lyricsSource,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sha')) {
      context.handle(
        _shaMeta,
        sha.isAcceptableOrUnknown(data['sha']!, _shaMeta),
      );
    } else if (isInserting) {
      context.missing(_shaMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('codec')) {
      context.handle(
        _codecMeta,
        codec.isAcceptableOrUnknown(data['codec']!, _codecMeta),
      );
    }
    if (data.containsKey('sample_rate')) {
      context.handle(
        _sampleRateMeta,
        sampleRate.isAcceptableOrUnknown(data['sample_rate']!, _sampleRateMeta),
      );
    }
    if (data.containsKey('channels')) {
      context.handle(
        _channelsMeta,
        channels.isAcceptableOrUnknown(data['channels']!, _channelsMeta),
      );
    }
    if (data.containsKey('bitrate')) {
      context.handle(
        _bitrateMeta,
        bitrate.isAcceptableOrUnknown(data['bitrate']!, _bitrateMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('art_sha')) {
      context.handle(
        _artShaMeta,
        artSha.isAcceptableOrUnknown(data['art_sha']!, _artShaMeta),
      );
    }
    if (data.containsKey('release_id')) {
      context.handle(
        _releaseIdMeta,
        releaseId.isAcceptableOrUnknown(data['release_id']!, _releaseIdMeta),
      );
    }
    if (data.containsKey('release_ids_json')) {
      context.handle(
        _releaseIdsJsonMeta,
        releaseIdsJson.isAcceptableOrUnknown(
          data['release_ids_json']!,
          _releaseIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('disc_number')) {
      context.handle(
        _discNumberMeta,
        discNumber.isAcceptableOrUnknown(data['disc_number']!, _discNumberMeta),
      );
    }
    if (data.containsKey('total_tracks')) {
      context.handle(
        _totalTracksMeta,
        totalTracks.isAcceptableOrUnknown(
          data['total_tracks']!,
          _totalTracksMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    if (data.containsKey('embedded_title')) {
      context.handle(
        _embeddedTitleMeta,
        embeddedTitle.isAcceptableOrUnknown(
          data['embedded_title']!,
          _embeddedTitleMeta,
        ),
      );
    }
    if (data.containsKey('embedded_artist')) {
      context.handle(
        _embeddedArtistMeta,
        embeddedArtist.isAcceptableOrUnknown(
          data['embedded_artist']!,
          _embeddedArtistMeta,
        ),
      );
    }
    if (data.containsKey('embedded_album')) {
      context.handle(
        _embeddedAlbumMeta,
        embeddedAlbum.isAcceptableOrUnknown(
          data['embedded_album']!,
          _embeddedAlbumMeta,
        ),
      );
    }
    if (data.containsKey('embedded_year')) {
      context.handle(
        _embeddedYearMeta,
        embeddedYear.isAcceptableOrUnknown(
          data['embedded_year']!,
          _embeddedYearMeta,
        ),
      );
    }
    if (data.containsKey('lyrics')) {
      context.handle(
        _lyricsMeta,
        lyrics.isAcceptableOrUnknown(data['lyrics']!, _lyricsMeta),
      );
    }
    if (data.containsKey('lyrics_source')) {
      context.handle(
        _lyricsSourceMeta,
        lyricsSource.isAcceptableOrUnknown(
          data['lyrics_source']!,
          _lyricsSourceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sha};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      sha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      codec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}codec'],
      ),
      sampleRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_rate'],
      ),
      channels: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channels'],
      ),
      bitrate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bitrate'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}year'],
      ),
      artSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_sha'],
      ),
      releaseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_id'],
      ),
      releaseIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_ids_json'],
      )!,
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      discNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_number'],
      ),
      totalTracks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_tracks'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      ),
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
      embeddedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedded_title'],
      ),
      embeddedArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedded_artist'],
      ),
      embeddedAlbum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedded_album'],
      ),
      embeddedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedded_year'],
      ),
      lyrics: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lyrics'],
      ),
      lyricsSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lyrics_source'],
      ),
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
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
  final String? releaseId;
  final String releaseIdsJson;
  final int? trackNumber;
  final int? discNumber;
  final int? totalTracks;
  final int? addedAt;
  final String searchText;
  final String? embeddedTitle;
  final String? embeddedArtist;
  final String? embeddedAlbum;
  final String? embeddedYear;
  final String? lyrics;
  final String? lyricsSource;
  const Track({
    required this.sha,
    required this.size,
    this.codec,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.durationMs,
    required this.title,
    required this.artist,
    required this.album,
    this.year,
    this.artSha,
    this.releaseId,
    required this.releaseIdsJson,
    this.trackNumber,
    this.discNumber,
    this.totalTracks,
    this.addedAt,
    required this.searchText,
    this.embeddedTitle,
    this.embeddedArtist,
    this.embeddedAlbum,
    this.embeddedYear,
    this.lyrics,
    this.lyricsSource,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sha'] = Variable<String>(sha);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || codec != null) {
      map['codec'] = Variable<String>(codec);
    }
    if (!nullToAbsent || sampleRate != null) {
      map['sample_rate'] = Variable<int>(sampleRate);
    }
    if (!nullToAbsent || channels != null) {
      map['channels'] = Variable<int>(channels);
    }
    if (!nullToAbsent || bitrate != null) {
      map['bitrate'] = Variable<int>(bitrate);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<String>(year);
    }
    if (!nullToAbsent || artSha != null) {
      map['art_sha'] = Variable<String>(artSha);
    }
    if (!nullToAbsent || releaseId != null) {
      map['release_id'] = Variable<String>(releaseId);
    }
    map['release_ids_json'] = Variable<String>(releaseIdsJson);
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || totalTracks != null) {
      map['total_tracks'] = Variable<int>(totalTracks);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<int>(addedAt);
    }
    map['search_text'] = Variable<String>(searchText);
    if (!nullToAbsent || embeddedTitle != null) {
      map['embedded_title'] = Variable<String>(embeddedTitle);
    }
    if (!nullToAbsent || embeddedArtist != null) {
      map['embedded_artist'] = Variable<String>(embeddedArtist);
    }
    if (!nullToAbsent || embeddedAlbum != null) {
      map['embedded_album'] = Variable<String>(embeddedAlbum);
    }
    if (!nullToAbsent || embeddedYear != null) {
      map['embedded_year'] = Variable<String>(embeddedYear);
    }
    if (!nullToAbsent || lyrics != null) {
      map['lyrics'] = Variable<String>(lyrics);
    }
    if (!nullToAbsent || lyricsSource != null) {
      map['lyrics_source'] = Variable<String>(lyricsSource);
    }
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      sha: Value(sha),
      size: Value(size),
      codec: codec == null && nullToAbsent
          ? const Value.absent()
          : Value(codec),
      sampleRate: sampleRate == null && nullToAbsent
          ? const Value.absent()
          : Value(sampleRate),
      channels: channels == null && nullToAbsent
          ? const Value.absent()
          : Value(channels),
      bitrate: bitrate == null && nullToAbsent
          ? const Value.absent()
          : Value(bitrate),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      artSha: artSha == null && nullToAbsent
          ? const Value.absent()
          : Value(artSha),
      releaseId: releaseId == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseId),
      releaseIdsJson: Value(releaseIdsJson),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      totalTracks: totalTracks == null && nullToAbsent
          ? const Value.absent()
          : Value(totalTracks),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      searchText: Value(searchText),
      embeddedTitle: embeddedTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddedTitle),
      embeddedArtist: embeddedArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddedArtist),
      embeddedAlbum: embeddedAlbum == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddedAlbum),
      embeddedYear: embeddedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddedYear),
      lyrics: lyrics == null && nullToAbsent
          ? const Value.absent()
          : Value(lyrics),
      lyricsSource: lyricsSource == null && nullToAbsent
          ? const Value.absent()
          : Value(lyricsSource),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      sha: serializer.fromJson<String>(json['sha']),
      size: serializer.fromJson<int>(json['size']),
      codec: serializer.fromJson<String?>(json['codec']),
      sampleRate: serializer.fromJson<int?>(json['sampleRate']),
      channels: serializer.fromJson<int?>(json['channels']),
      bitrate: serializer.fromJson<int?>(json['bitrate']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      year: serializer.fromJson<String?>(json['year']),
      artSha: serializer.fromJson<String?>(json['artSha']),
      releaseId: serializer.fromJson<String?>(json['releaseId']),
      releaseIdsJson: serializer.fromJson<String>(json['releaseIdsJson']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      totalTracks: serializer.fromJson<int?>(json['totalTracks']),
      addedAt: serializer.fromJson<int?>(json['addedAt']),
      searchText: serializer.fromJson<String>(json['searchText']),
      embeddedTitle: serializer.fromJson<String?>(json['embeddedTitle']),
      embeddedArtist: serializer.fromJson<String?>(json['embeddedArtist']),
      embeddedAlbum: serializer.fromJson<String?>(json['embeddedAlbum']),
      embeddedYear: serializer.fromJson<String?>(json['embeddedYear']),
      lyrics: serializer.fromJson<String?>(json['lyrics']),
      lyricsSource: serializer.fromJson<String?>(json['lyricsSource']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sha': serializer.toJson<String>(sha),
      'size': serializer.toJson<int>(size),
      'codec': serializer.toJson<String?>(codec),
      'sampleRate': serializer.toJson<int?>(sampleRate),
      'channels': serializer.toJson<int?>(channels),
      'bitrate': serializer.toJson<int?>(bitrate),
      'durationMs': serializer.toJson<int?>(durationMs),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'year': serializer.toJson<String?>(year),
      'artSha': serializer.toJson<String?>(artSha),
      'releaseId': serializer.toJson<String?>(releaseId),
      'releaseIdsJson': serializer.toJson<String>(releaseIdsJson),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'totalTracks': serializer.toJson<int?>(totalTracks),
      'addedAt': serializer.toJson<int?>(addedAt),
      'searchText': serializer.toJson<String>(searchText),
      'embeddedTitle': serializer.toJson<String?>(embeddedTitle),
      'embeddedArtist': serializer.toJson<String?>(embeddedArtist),
      'embeddedAlbum': serializer.toJson<String?>(embeddedAlbum),
      'embeddedYear': serializer.toJson<String?>(embeddedYear),
      'lyrics': serializer.toJson<String?>(lyrics),
      'lyricsSource': serializer.toJson<String?>(lyricsSource),
    };
  }

  Track copyWith({
    String? sha,
    int? size,
    Value<String?> codec = const Value.absent(),
    Value<int?> sampleRate = const Value.absent(),
    Value<int?> channels = const Value.absent(),
    Value<int?> bitrate = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    String? title,
    String? artist,
    String? album,
    Value<String?> year = const Value.absent(),
    Value<String?> artSha = const Value.absent(),
    Value<String?> releaseId = const Value.absent(),
    String? releaseIdsJson,
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<int?> totalTracks = const Value.absent(),
    Value<int?> addedAt = const Value.absent(),
    String? searchText,
    Value<String?> embeddedTitle = const Value.absent(),
    Value<String?> embeddedArtist = const Value.absent(),
    Value<String?> embeddedAlbum = const Value.absent(),
    Value<String?> embeddedYear = const Value.absent(),
    Value<String?> lyrics = const Value.absent(),
    Value<String?> lyricsSource = const Value.absent(),
  }) => Track(
    sha: sha ?? this.sha,
    size: size ?? this.size,
    codec: codec.present ? codec.value : this.codec,
    sampleRate: sampleRate.present ? sampleRate.value : this.sampleRate,
    channels: channels.present ? channels.value : this.channels,
    bitrate: bitrate.present ? bitrate.value : this.bitrate,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    year: year.present ? year.value : this.year,
    artSha: artSha.present ? artSha.value : this.artSha,
    releaseId: releaseId.present ? releaseId.value : this.releaseId,
    releaseIdsJson: releaseIdsJson ?? this.releaseIdsJson,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    discNumber: discNumber.present ? discNumber.value : this.discNumber,
    totalTracks: totalTracks.present ? totalTracks.value : this.totalTracks,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    searchText: searchText ?? this.searchText,
    embeddedTitle: embeddedTitle.present
        ? embeddedTitle.value
        : this.embeddedTitle,
    embeddedArtist: embeddedArtist.present
        ? embeddedArtist.value
        : this.embeddedArtist,
    embeddedAlbum: embeddedAlbum.present
        ? embeddedAlbum.value
        : this.embeddedAlbum,
    embeddedYear: embeddedYear.present ? embeddedYear.value : this.embeddedYear,
    lyrics: lyrics.present ? lyrics.value : this.lyrics,
    lyricsSource: lyricsSource.present ? lyricsSource.value : this.lyricsSource,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      sha: data.sha.present ? data.sha.value : this.sha,
      size: data.size.present ? data.size.value : this.size,
      codec: data.codec.present ? data.codec.value : this.codec,
      sampleRate: data.sampleRate.present
          ? data.sampleRate.value
          : this.sampleRate,
      channels: data.channels.present ? data.channels.value : this.channels,
      bitrate: data.bitrate.present ? data.bitrate.value : this.bitrate,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      year: data.year.present ? data.year.value : this.year,
      artSha: data.artSha.present ? data.artSha.value : this.artSha,
      releaseId: data.releaseId.present ? data.releaseId.value : this.releaseId,
      releaseIdsJson: data.releaseIdsJson.present
          ? data.releaseIdsJson.value
          : this.releaseIdsJson,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      discNumber: data.discNumber.present
          ? data.discNumber.value
          : this.discNumber,
      totalTracks: data.totalTracks.present
          ? data.totalTracks.value
          : this.totalTracks,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
      embeddedTitle: data.embeddedTitle.present
          ? data.embeddedTitle.value
          : this.embeddedTitle,
      embeddedArtist: data.embeddedArtist.present
          ? data.embeddedArtist.value
          : this.embeddedArtist,
      embeddedAlbum: data.embeddedAlbum.present
          ? data.embeddedAlbum.value
          : this.embeddedAlbum,
      embeddedYear: data.embeddedYear.present
          ? data.embeddedYear.value
          : this.embeddedYear,
      lyrics: data.lyrics.present ? data.lyrics.value : this.lyrics,
      lyricsSource: data.lyricsSource.present
          ? data.lyricsSource.value
          : this.lyricsSource,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('sha: $sha, ')
          ..write('size: $size, ')
          ..write('codec: $codec, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('channels: $channels, ')
          ..write('bitrate: $bitrate, ')
          ..write('durationMs: $durationMs, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('year: $year, ')
          ..write('artSha: $artSha, ')
          ..write('releaseId: $releaseId, ')
          ..write('releaseIdsJson: $releaseIdsJson, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('totalTracks: $totalTracks, ')
          ..write('addedAt: $addedAt, ')
          ..write('searchText: $searchText, ')
          ..write('embeddedTitle: $embeddedTitle, ')
          ..write('embeddedArtist: $embeddedArtist, ')
          ..write('embeddedAlbum: $embeddedAlbum, ')
          ..write('embeddedYear: $embeddedYear, ')
          ..write('lyrics: $lyrics, ')
          ..write('lyricsSource: $lyricsSource')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    sha,
    size,
    codec,
    sampleRate,
    channels,
    bitrate,
    durationMs,
    title,
    artist,
    album,
    year,
    artSha,
    releaseId,
    releaseIdsJson,
    trackNumber,
    discNumber,
    totalTracks,
    addedAt,
    searchText,
    embeddedTitle,
    embeddedArtist,
    embeddedAlbum,
    embeddedYear,
    lyrics,
    lyricsSource,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.sha == this.sha &&
          other.size == this.size &&
          other.codec == this.codec &&
          other.sampleRate == this.sampleRate &&
          other.channels == this.channels &&
          other.bitrate == this.bitrate &&
          other.durationMs == this.durationMs &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.year == this.year &&
          other.artSha == this.artSha &&
          other.releaseId == this.releaseId &&
          other.releaseIdsJson == this.releaseIdsJson &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.totalTracks == this.totalTracks &&
          other.addedAt == this.addedAt &&
          other.searchText == this.searchText &&
          other.embeddedTitle == this.embeddedTitle &&
          other.embeddedArtist == this.embeddedArtist &&
          other.embeddedAlbum == this.embeddedAlbum &&
          other.embeddedYear == this.embeddedYear &&
          other.lyrics == this.lyrics &&
          other.lyricsSource == this.lyricsSource);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<String> sha;
  final Value<int> size;
  final Value<String?> codec;
  final Value<int?> sampleRate;
  final Value<int?> channels;
  final Value<int?> bitrate;
  final Value<int?> durationMs;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String?> year;
  final Value<String?> artSha;
  final Value<String?> releaseId;
  final Value<String> releaseIdsJson;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int?> totalTracks;
  final Value<int?> addedAt;
  final Value<String> searchText;
  final Value<String?> embeddedTitle;
  final Value<String?> embeddedArtist;
  final Value<String?> embeddedAlbum;
  final Value<String?> embeddedYear;
  final Value<String?> lyrics;
  final Value<String?> lyricsSource;
  final Value<int> rowid;
  const TracksCompanion({
    this.sha = const Value.absent(),
    this.size = const Value.absent(),
    this.codec = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.channels = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.year = const Value.absent(),
    this.artSha = const Value.absent(),
    this.releaseId = const Value.absent(),
    this.releaseIdsJson = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.totalTracks = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.searchText = const Value.absent(),
    this.embeddedTitle = const Value.absent(),
    this.embeddedArtist = const Value.absent(),
    this.embeddedAlbum = const Value.absent(),
    this.embeddedYear = const Value.absent(),
    this.lyrics = const Value.absent(),
    this.lyricsSource = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String sha,
    this.size = const Value.absent(),
    this.codec = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.channels = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.year = const Value.absent(),
    this.artSha = const Value.absent(),
    this.releaseId = const Value.absent(),
    this.releaseIdsJson = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.totalTracks = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.searchText = const Value.absent(),
    this.embeddedTitle = const Value.absent(),
    this.embeddedArtist = const Value.absent(),
    this.embeddedAlbum = const Value.absent(),
    this.embeddedYear = const Value.absent(),
    this.lyrics = const Value.absent(),
    this.lyricsSource = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sha = Value(sha);
  static Insertable<Track> custom({
    Expression<String>? sha,
    Expression<int>? size,
    Expression<String>? codec,
    Expression<int>? sampleRate,
    Expression<int>? channels,
    Expression<int>? bitrate,
    Expression<int>? durationMs,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? year,
    Expression<String>? artSha,
    Expression<String>? releaseId,
    Expression<String>? releaseIdsJson,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? totalTracks,
    Expression<int>? addedAt,
    Expression<String>? searchText,
    Expression<String>? embeddedTitle,
    Expression<String>? embeddedArtist,
    Expression<String>? embeddedAlbum,
    Expression<String>? embeddedYear,
    Expression<String>? lyrics,
    Expression<String>? lyricsSource,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sha != null) 'sha': sha,
      if (size != null) 'size': size,
      if (codec != null) 'codec': codec,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (channels != null) 'channels': channels,
      if (bitrate != null) 'bitrate': bitrate,
      if (durationMs != null) 'duration_ms': durationMs,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (year != null) 'year': year,
      if (artSha != null) 'art_sha': artSha,
      if (releaseId != null) 'release_id': releaseId,
      if (releaseIdsJson != null) 'release_ids_json': releaseIdsJson,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (totalTracks != null) 'total_tracks': totalTracks,
      if (addedAt != null) 'added_at': addedAt,
      if (searchText != null) 'search_text': searchText,
      if (embeddedTitle != null) 'embedded_title': embeddedTitle,
      if (embeddedArtist != null) 'embedded_artist': embeddedArtist,
      if (embeddedAlbum != null) 'embedded_album': embeddedAlbum,
      if (embeddedYear != null) 'embedded_year': embeddedYear,
      if (lyrics != null) 'lyrics': lyrics,
      if (lyricsSource != null) 'lyrics_source': lyricsSource,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? sha,
    Value<int>? size,
    Value<String?>? codec,
    Value<int?>? sampleRate,
    Value<int?>? channels,
    Value<int?>? bitrate,
    Value<int?>? durationMs,
    Value<String>? title,
    Value<String>? artist,
    Value<String>? album,
    Value<String?>? year,
    Value<String?>? artSha,
    Value<String?>? releaseId,
    Value<String>? releaseIdsJson,
    Value<int?>? trackNumber,
    Value<int?>? discNumber,
    Value<int?>? totalTracks,
    Value<int?>? addedAt,
    Value<String>? searchText,
    Value<String?>? embeddedTitle,
    Value<String?>? embeddedArtist,
    Value<String?>? embeddedAlbum,
    Value<String?>? embeddedYear,
    Value<String?>? lyrics,
    Value<String?>? lyricsSource,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      sha: sha ?? this.sha,
      size: size ?? this.size,
      codec: codec ?? this.codec,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      bitrate: bitrate ?? this.bitrate,
      durationMs: durationMs ?? this.durationMs,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      year: year ?? this.year,
      artSha: artSha ?? this.artSha,
      releaseId: releaseId ?? this.releaseId,
      releaseIdsJson: releaseIdsJson ?? this.releaseIdsJson,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      totalTracks: totalTracks ?? this.totalTracks,
      addedAt: addedAt ?? this.addedAt,
      searchText: searchText ?? this.searchText,
      embeddedTitle: embeddedTitle ?? this.embeddedTitle,
      embeddedArtist: embeddedArtist ?? this.embeddedArtist,
      embeddedAlbum: embeddedAlbum ?? this.embeddedAlbum,
      embeddedYear: embeddedYear ?? this.embeddedYear,
      lyrics: lyrics ?? this.lyrics,
      lyricsSource: lyricsSource ?? this.lyricsSource,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sha.present) {
      map['sha'] = Variable<String>(sha.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
    }
    if (sampleRate.present) {
      map['sample_rate'] = Variable<int>(sampleRate.value);
    }
    if (channels.present) {
      map['channels'] = Variable<int>(channels.value);
    }
    if (bitrate.present) {
      map['bitrate'] = Variable<int>(bitrate.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (year.present) {
      map['year'] = Variable<String>(year.value);
    }
    if (artSha.present) {
      map['art_sha'] = Variable<String>(artSha.value);
    }
    if (releaseId.present) {
      map['release_id'] = Variable<String>(releaseId.value);
    }
    if (releaseIdsJson.present) {
      map['release_ids_json'] = Variable<String>(releaseIdsJson.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (totalTracks.present) {
      map['total_tracks'] = Variable<int>(totalTracks.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (embeddedTitle.present) {
      map['embedded_title'] = Variable<String>(embeddedTitle.value);
    }
    if (embeddedArtist.present) {
      map['embedded_artist'] = Variable<String>(embeddedArtist.value);
    }
    if (embeddedAlbum.present) {
      map['embedded_album'] = Variable<String>(embeddedAlbum.value);
    }
    if (embeddedYear.present) {
      map['embedded_year'] = Variable<String>(embeddedYear.value);
    }
    if (lyrics.present) {
      map['lyrics'] = Variable<String>(lyrics.value);
    }
    if (lyricsSource.present) {
      map['lyrics_source'] = Variable<String>(lyricsSource.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('sha: $sha, ')
          ..write('size: $size, ')
          ..write('codec: $codec, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('channels: $channels, ')
          ..write('bitrate: $bitrate, ')
          ..write('durationMs: $durationMs, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('year: $year, ')
          ..write('artSha: $artSha, ')
          ..write('releaseId: $releaseId, ')
          ..write('releaseIdsJson: $releaseIdsJson, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('totalTracks: $totalTracks, ')
          ..write('addedAt: $addedAt, ')
          ..write('searchText: $searchText, ')
          ..write('embeddedTitle: $embeddedTitle, ')
          ..write('embeddedArtist: $embeddedArtist, ')
          ..write('embeddedAlbum: $embeddedAlbum, ')
          ..write('embeddedYear: $embeddedYear, ')
          ..write('lyrics: $lyrics, ')
          ..write('lyricsSource: $lyricsSource, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReleasesTable extends Releases with TableInfo<$ReleasesTable, Release> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReleasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<String> year = GeneratedColumn<String>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artShaMeta = const VerificationMeta('artSha');
  @override
  late final GeneratedColumn<String> artSha = GeneratedColumn<String>(
    'art_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalTracksMeta = const VerificationMeta(
    'totalTracks',
  );
  @override
  late final GeneratedColumn<int> totalTracks = GeneratedColumn<int>(
    'total_tracks',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackShasJsonMeta = const VerificationMeta(
    'trackShasJson',
  );
  @override
  late final GeneratedColumn<String> trackShasJson = GeneratedColumn<String>(
    'track_shas_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _releaseTracksJsonMeta = const VerificationMeta(
    'releaseTracksJson',
  );
  @override
  late final GeneratedColumn<String> releaseTracksJson =
      GeneratedColumn<String>(
        'release_tracks_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    artist,
    year,
    artSha,
    totalTracks,
    trackShasJson,
    releaseTracksJson,
    type,
    searchText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'releases';
  @override
  VerificationContext validateIntegrity(
    Insertable<Release> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('art_sha')) {
      context.handle(
        _artShaMeta,
        artSha.isAcceptableOrUnknown(data['art_sha']!, _artShaMeta),
      );
    }
    if (data.containsKey('total_tracks')) {
      context.handle(
        _totalTracksMeta,
        totalTracks.isAcceptableOrUnknown(
          data['total_tracks']!,
          _totalTracksMeta,
        ),
      );
    }
    if (data.containsKey('track_shas_json')) {
      context.handle(
        _trackShasJsonMeta,
        trackShasJson.isAcceptableOrUnknown(
          data['track_shas_json']!,
          _trackShasJsonMeta,
        ),
      );
    }
    if (data.containsKey('release_tracks_json')) {
      context.handle(
        _releaseTracksJsonMeta,
        releaseTracksJson.isAcceptableOrUnknown(
          data['release_tracks_json']!,
          _releaseTracksJsonMeta,
        ),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Release map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Release(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}year'],
      ),
      artSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_sha'],
      ),
      totalTracks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_tracks'],
      ),
      trackShasJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_shas_json'],
      )!,
      releaseTracksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_tracks_json'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
    );
  }

  @override
  $ReleasesTable createAlias(String alias) {
    return $ReleasesTable(attachedDatabase, alias);
  }
}

class Release extends DataClass implements Insertable<Release> {
  final String id;
  final String title;
  final String artist;
  final String? year;
  final String? artSha;
  final int? totalTracks;
  final String trackShasJson;
  final String releaseTracksJson;
  final String? type;
  final String searchText;
  const Release({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.artSha,
    this.totalTracks,
    required this.trackShasJson,
    required this.releaseTracksJson,
    this.type,
    required this.searchText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<String>(year);
    }
    if (!nullToAbsent || artSha != null) {
      map['art_sha'] = Variable<String>(artSha);
    }
    if (!nullToAbsent || totalTracks != null) {
      map['total_tracks'] = Variable<int>(totalTracks);
    }
    map['track_shas_json'] = Variable<String>(trackShasJson);
    map['release_tracks_json'] = Variable<String>(releaseTracksJson);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['search_text'] = Variable<String>(searchText);
    return map;
  }

  ReleasesCompanion toCompanion(bool nullToAbsent) {
    return ReleasesCompanion(
      id: Value(id),
      title: Value(title),
      artist: Value(artist),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      artSha: artSha == null && nullToAbsent
          ? const Value.absent()
          : Value(artSha),
      totalTracks: totalTracks == null && nullToAbsent
          ? const Value.absent()
          : Value(totalTracks),
      trackShasJson: Value(trackShasJson),
      releaseTracksJson: Value(releaseTracksJson),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      searchText: Value(searchText),
    );
  }

  factory Release.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Release(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      year: serializer.fromJson<String?>(json['year']),
      artSha: serializer.fromJson<String?>(json['artSha']),
      totalTracks: serializer.fromJson<int?>(json['totalTracks']),
      trackShasJson: serializer.fromJson<String>(json['trackShasJson']),
      releaseTracksJson: serializer.fromJson<String>(json['releaseTracksJson']),
      type: serializer.fromJson<String?>(json['type']),
      searchText: serializer.fromJson<String>(json['searchText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'year': serializer.toJson<String?>(year),
      'artSha': serializer.toJson<String?>(artSha),
      'totalTracks': serializer.toJson<int?>(totalTracks),
      'trackShasJson': serializer.toJson<String>(trackShasJson),
      'releaseTracksJson': serializer.toJson<String>(releaseTracksJson),
      'type': serializer.toJson<String?>(type),
      'searchText': serializer.toJson<String>(searchText),
    };
  }

  Release copyWith({
    String? id,
    String? title,
    String? artist,
    Value<String?> year = const Value.absent(),
    Value<String?> artSha = const Value.absent(),
    Value<int?> totalTracks = const Value.absent(),
    String? trackShasJson,
    String? releaseTracksJson,
    Value<String?> type = const Value.absent(),
    String? searchText,
  }) => Release(
    id: id ?? this.id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    year: year.present ? year.value : this.year,
    artSha: artSha.present ? artSha.value : this.artSha,
    totalTracks: totalTracks.present ? totalTracks.value : this.totalTracks,
    trackShasJson: trackShasJson ?? this.trackShasJson,
    releaseTracksJson: releaseTracksJson ?? this.releaseTracksJson,
    type: type.present ? type.value : this.type,
    searchText: searchText ?? this.searchText,
  );
  Release copyWithCompanion(ReleasesCompanion data) {
    return Release(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      year: data.year.present ? data.year.value : this.year,
      artSha: data.artSha.present ? data.artSha.value : this.artSha,
      totalTracks: data.totalTracks.present
          ? data.totalTracks.value
          : this.totalTracks,
      trackShasJson: data.trackShasJson.present
          ? data.trackShasJson.value
          : this.trackShasJson,
      releaseTracksJson: data.releaseTracksJson.present
          ? data.releaseTracksJson.value
          : this.releaseTracksJson,
      type: data.type.present ? data.type.value : this.type,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Release(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('year: $year, ')
          ..write('artSha: $artSha, ')
          ..write('totalTracks: $totalTracks, ')
          ..write('trackShasJson: $trackShasJson, ')
          ..write('releaseTracksJson: $releaseTracksJson, ')
          ..write('type: $type, ')
          ..write('searchText: $searchText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    year,
    artSha,
    totalTracks,
    trackShasJson,
    releaseTracksJson,
    type,
    searchText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Release &&
          other.id == this.id &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.year == this.year &&
          other.artSha == this.artSha &&
          other.totalTracks == this.totalTracks &&
          other.trackShasJson == this.trackShasJson &&
          other.releaseTracksJson == this.releaseTracksJson &&
          other.type == this.type &&
          other.searchText == this.searchText);
}

class ReleasesCompanion extends UpdateCompanion<Release> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> year;
  final Value<String?> artSha;
  final Value<int?> totalTracks;
  final Value<String> trackShasJson;
  final Value<String> releaseTracksJson;
  final Value<String?> type;
  final Value<String> searchText;
  final Value<int> rowid;
  const ReleasesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.year = const Value.absent(),
    this.artSha = const Value.absent(),
    this.totalTracks = const Value.absent(),
    this.trackShasJson = const Value.absent(),
    this.releaseTracksJson = const Value.absent(),
    this.type = const Value.absent(),
    this.searchText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReleasesCompanion.insert({
    required String id,
    required String title,
    required String artist,
    this.year = const Value.absent(),
    this.artSha = const Value.absent(),
    this.totalTracks = const Value.absent(),
    this.trackShasJson = const Value.absent(),
    this.releaseTracksJson = const Value.absent(),
    this.type = const Value.absent(),
    this.searchText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       artist = Value(artist);
  static Insertable<Release> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? year,
    Expression<String>? artSha,
    Expression<int>? totalTracks,
    Expression<String>? trackShasJson,
    Expression<String>? releaseTracksJson,
    Expression<String>? type,
    Expression<String>? searchText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (year != null) 'year': year,
      if (artSha != null) 'art_sha': artSha,
      if (totalTracks != null) 'total_tracks': totalTracks,
      if (trackShasJson != null) 'track_shas_json': trackShasJson,
      if (releaseTracksJson != null) 'release_tracks_json': releaseTracksJson,
      if (type != null) 'type': type,
      if (searchText != null) 'search_text': searchText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReleasesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? artist,
    Value<String?>? year,
    Value<String?>? artSha,
    Value<int?>? totalTracks,
    Value<String>? trackShasJson,
    Value<String>? releaseTracksJson,
    Value<String?>? type,
    Value<String>? searchText,
    Value<int>? rowid,
  }) {
    return ReleasesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      year: year ?? this.year,
      artSha: artSha ?? this.artSha,
      totalTracks: totalTracks ?? this.totalTracks,
      trackShasJson: trackShasJson ?? this.trackShasJson,
      releaseTracksJson: releaseTracksJson ?? this.releaseTracksJson,
      type: type ?? this.type,
      searchText: searchText ?? this.searchText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (year.present) {
      map['year'] = Variable<String>(year.value);
    }
    if (artSha.present) {
      map['art_sha'] = Variable<String>(artSha.value);
    }
    if (totalTracks.present) {
      map['total_tracks'] = Variable<int>(totalTracks.value);
    }
    if (trackShasJson.present) {
      map['track_shas_json'] = Variable<String>(trackShasJson.value);
    }
    if (releaseTracksJson.present) {
      map['release_tracks_json'] = Variable<String>(releaseTracksJson.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReleasesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('year: $year, ')
          ..write('artSha: $artSha, ')
          ..write('totalTracks: $totalTracks, ')
          ..write('trackShasJson: $trackShasJson, ')
          ..write('releaseTracksJson: $releaseTracksJson, ')
          ..write('type: $type, ')
          ..write('searchText: $searchText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArtistsTable extends Artists with TableInfo<$ArtistsTable, Artist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artShaMeta = const VerificationMeta('artSha');
  @override
  late final GeneratedColumn<String> artSha = GeneratedColumn<String>(
    'art_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [name, artSha, searchText];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Artist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('art_sha')) {
      context.handle(
        _artShaMeta,
        artSha.isAcceptableOrUnknown(data['art_sha']!, _artShaMeta),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  Artist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Artist(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_sha'],
      ),
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
    );
  }

  @override
  $ArtistsTable createAlias(String alias) {
    return $ArtistsTable(attachedDatabase, alias);
  }
}

class Artist extends DataClass implements Insertable<Artist> {
  final String name;
  final String? artSha;
  final String searchText;
  const Artist({required this.name, this.artSha, required this.searchText});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || artSha != null) {
      map['art_sha'] = Variable<String>(artSha);
    }
    map['search_text'] = Variable<String>(searchText);
    return map;
  }

  ArtistsCompanion toCompanion(bool nullToAbsent) {
    return ArtistsCompanion(
      name: Value(name),
      artSha: artSha == null && nullToAbsent
          ? const Value.absent()
          : Value(artSha),
      searchText: Value(searchText),
    );
  }

  factory Artist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Artist(
      name: serializer.fromJson<String>(json['name']),
      artSha: serializer.fromJson<String?>(json['artSha']),
      searchText: serializer.fromJson<String>(json['searchText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'artSha': serializer.toJson<String?>(artSha),
      'searchText': serializer.toJson<String>(searchText),
    };
  }

  Artist copyWith({
    String? name,
    Value<String?> artSha = const Value.absent(),
    String? searchText,
  }) => Artist(
    name: name ?? this.name,
    artSha: artSha.present ? artSha.value : this.artSha,
    searchText: searchText ?? this.searchText,
  );
  Artist copyWithCompanion(ArtistsCompanion data) {
    return Artist(
      name: data.name.present ? data.name.value : this.name,
      artSha: data.artSha.present ? data.artSha.value : this.artSha,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Artist(')
          ..write('name: $name, ')
          ..write('artSha: $artSha, ')
          ..write('searchText: $searchText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, artSha, searchText);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Artist &&
          other.name == this.name &&
          other.artSha == this.artSha &&
          other.searchText == this.searchText);
}

class ArtistsCompanion extends UpdateCompanion<Artist> {
  final Value<String> name;
  final Value<String?> artSha;
  final Value<String> searchText;
  final Value<int> rowid;
  const ArtistsCompanion({
    this.name = const Value.absent(),
    this.artSha = const Value.absent(),
    this.searchText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArtistsCompanion.insert({
    required String name,
    this.artSha = const Value.absent(),
    this.searchText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Artist> custom({
    Expression<String>? name,
    Expression<String>? artSha,
    Expression<String>? searchText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (artSha != null) 'art_sha': artSha,
      if (searchText != null) 'search_text': searchText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArtistsCompanion copyWith({
    Value<String>? name,
    Value<String?>? artSha,
    Value<String>? searchText,
    Value<int>? rowid,
  }) {
    return ArtistsCompanion(
      name: name ?? this.name,
      artSha: artSha ?? this.artSha,
      searchText: searchText ?? this.searchText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artSha.present) {
      map['art_sha'] = Variable<String>(artSha.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsCompanion(')
          ..write('name: $name, ')
          ..write('artSha: $artSha, ')
          ..write('searchText: $searchText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrackEditsTable extends TrackEdits
    with TableInfo<$TrackEditsTable, TrackEdit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackEditsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shaMeta = const VerificationMeta('sha');
  @override
  late final GeneratedColumn<String> sha = GeneratedColumn<String>(
    'sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _editedAtMeta = const VerificationMeta(
    'editedAt',
  );
  @override
  late final GeneratedColumn<int> editedAt = GeneratedColumn<int>(
    'edited_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sha, field, value, editedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_edits';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackEdit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sha')) {
      context.handle(
        _shaMeta,
        sha.isAcceptableOrUnknown(data['sha']!, _shaMeta),
      );
    } else if (isInserting) {
      context.missing(_shaMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('edited_at')) {
      context.handle(
        _editedAtMeta,
        editedAt.isAcceptableOrUnknown(data['edited_at']!, _editedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_editedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sha, field};
  @override
  TrackEdit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackEdit(
      sha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      editedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}edited_at'],
      )!,
    );
  }

  @override
  $TrackEditsTable createAlias(String alias) {
    return $TrackEditsTable(attachedDatabase, alias);
  }
}

class TrackEdit extends DataClass implements Insertable<TrackEdit> {
  final String sha;
  final String field;
  final String value;
  final int editedAt;
  const TrackEdit({
    required this.sha,
    required this.field,
    required this.value,
    required this.editedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sha'] = Variable<String>(sha);
    map['field'] = Variable<String>(field);
    map['value'] = Variable<String>(value);
    map['edited_at'] = Variable<int>(editedAt);
    return map;
  }

  TrackEditsCompanion toCompanion(bool nullToAbsent) {
    return TrackEditsCompanion(
      sha: Value(sha),
      field: Value(field),
      value: Value(value),
      editedAt: Value(editedAt),
    );
  }

  factory TrackEdit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackEdit(
      sha: serializer.fromJson<String>(json['sha']),
      field: serializer.fromJson<String>(json['field']),
      value: serializer.fromJson<String>(json['value']),
      editedAt: serializer.fromJson<int>(json['editedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sha': serializer.toJson<String>(sha),
      'field': serializer.toJson<String>(field),
      'value': serializer.toJson<String>(value),
      'editedAt': serializer.toJson<int>(editedAt),
    };
  }

  TrackEdit copyWith({
    String? sha,
    String? field,
    String? value,
    int? editedAt,
  }) => TrackEdit(
    sha: sha ?? this.sha,
    field: field ?? this.field,
    value: value ?? this.value,
    editedAt: editedAt ?? this.editedAt,
  );
  TrackEdit copyWithCompanion(TrackEditsCompanion data) {
    return TrackEdit(
      sha: data.sha.present ? data.sha.value : this.sha,
      field: data.field.present ? data.field.value : this.field,
      value: data.value.present ? data.value.value : this.value,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackEdit(')
          ..write('sha: $sha, ')
          ..write('field: $field, ')
          ..write('value: $value, ')
          ..write('editedAt: $editedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sha, field, value, editedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackEdit &&
          other.sha == this.sha &&
          other.field == this.field &&
          other.value == this.value &&
          other.editedAt == this.editedAt);
}

class TrackEditsCompanion extends UpdateCompanion<TrackEdit> {
  final Value<String> sha;
  final Value<String> field;
  final Value<String> value;
  final Value<int> editedAt;
  final Value<int> rowid;
  const TrackEditsCompanion({
    this.sha = const Value.absent(),
    this.field = const Value.absent(),
    this.value = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrackEditsCompanion.insert({
    required String sha,
    required String field,
    required String value,
    required int editedAt,
    this.rowid = const Value.absent(),
  }) : sha = Value(sha),
       field = Value(field),
       value = Value(value),
       editedAt = Value(editedAt);
  static Insertable<TrackEdit> custom({
    Expression<String>? sha,
    Expression<String>? field,
    Expression<String>? value,
    Expression<int>? editedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sha != null) 'sha': sha,
      if (field != null) 'field': field,
      if (value != null) 'value': value,
      if (editedAt != null) 'edited_at': editedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrackEditsCompanion copyWith({
    Value<String>? sha,
    Value<String>? field,
    Value<String>? value,
    Value<int>? editedAt,
    Value<int>? rowid,
  }) {
    return TrackEditsCompanion(
      sha: sha ?? this.sha,
      field: field ?? this.field,
      value: value ?? this.value,
      editedAt: editedAt ?? this.editedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sha.present) {
      map['sha'] = Variable<String>(sha.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<int>(editedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackEditsCompanion(')
          ..write('sha: $sha, ')
          ..write('field: $field, ')
          ..write('value: $value, ')
          ..write('editedAt: $editedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueEntriesTable extends QueueEntries
    with TableInfo<$QueueEntriesTable, QueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackShaMeta = const VerificationMeta(
    'trackSha',
  );
  @override
  late final GeneratedColumn<String> trackSha = GeneratedColumn<String>(
    'track_sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<int> state = GeneratedColumn<int>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    trackSha,
    state,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('track_sha')) {
      context.handle(
        _trackShaMeta,
        trackSha.isAcceptableOrUnknown(data['track_sha']!, _trackShaMeta),
      );
    } else if (isInserting) {
      context.missing(_trackShaMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      trackSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_sha'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $QueueEntriesTable createAlias(String alias) {
    return $QueueEntriesTable(attachedDatabase, alias);
  }
}

class QueueEntry extends DataClass implements Insertable<QueueEntry> {
  final int id;
  final int position;
  final String trackSha;
  final int state;
  final int addedAt;
  const QueueEntry({
    required this.id,
    required this.position,
    required this.trackSha,
    required this.state,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['position'] = Variable<int>(position);
    map['track_sha'] = Variable<String>(trackSha);
    map['state'] = Variable<int>(state);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  QueueEntriesCompanion toCompanion(bool nullToAbsent) {
    return QueueEntriesCompanion(
      id: Value(id),
      position: Value(position),
      trackSha: Value(trackSha),
      state: Value(state),
      addedAt: Value(addedAt),
    );
  }

  factory QueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueEntry(
      id: serializer.fromJson<int>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      trackSha: serializer.fromJson<String>(json['trackSha']),
      state: serializer.fromJson<int>(json['state']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'position': serializer.toJson<int>(position),
      'trackSha': serializer.toJson<String>(trackSha),
      'state': serializer.toJson<int>(state),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  QueueEntry copyWith({
    int? id,
    int? position,
    String? trackSha,
    int? state,
    int? addedAt,
  }) => QueueEntry(
    id: id ?? this.id,
    position: position ?? this.position,
    trackSha: trackSha ?? this.trackSha,
    state: state ?? this.state,
    addedAt: addedAt ?? this.addedAt,
  );
  QueueEntry copyWithCompanion(QueueEntriesCompanion data) {
    return QueueEntry(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      trackSha: data.trackSha.present ? data.trackSha.value : this.trackSha,
      state: data.state.present ? data.state.value : this.state,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntry(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('trackSha: $trackSha, ')
          ..write('state: $state, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, position, trackSha, state, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueEntry &&
          other.id == this.id &&
          other.position == this.position &&
          other.trackSha == this.trackSha &&
          other.state == this.state &&
          other.addedAt == this.addedAt);
}

class QueueEntriesCompanion extends UpdateCompanion<QueueEntry> {
  final Value<int> id;
  final Value<int> position;
  final Value<String> trackSha;
  final Value<int> state;
  final Value<int> addedAt;
  const QueueEntriesCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.trackSha = const Value.absent(),
    this.state = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  QueueEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int position,
    required String trackSha,
    this.state = const Value.absent(),
    required int addedAt,
  }) : position = Value(position),
       trackSha = Value(trackSha),
       addedAt = Value(addedAt);
  static Insertable<QueueEntry> custom({
    Expression<int>? id,
    Expression<int>? position,
    Expression<String>? trackSha,
    Expression<int>? state,
    Expression<int>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (trackSha != null) 'track_sha': trackSha,
      if (state != null) 'state': state,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  QueueEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? position,
    Value<String>? trackSha,
    Value<int>? state,
    Value<int>? addedAt,
  }) {
    return QueueEntriesCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      trackSha: trackSha ?? this.trackSha,
      state: state ?? this.state,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (trackSha.present) {
      map['track_sha'] = Variable<String>(trackSha.value);
    }
    if (state.present) {
      map['state'] = Variable<int>(state.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntriesCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('trackSha: $trackSha, ')
          ..write('state: $state, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$TunesDatabase extends GeneratedDatabase {
  _$TunesDatabase(QueryExecutor e) : super(e);
  $TunesDatabaseManager get managers => $TunesDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $ReleasesTable releases = $ReleasesTable(this);
  late final $ArtistsTable artists = $ArtistsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $TrackEditsTable trackEdits = $TrackEditsTable(this);
  late final $QueueEntriesTable queueEntries = $QueueEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    releases,
    artists,
    syncState,
    trackEdits,
    queueEntries,
  ];
}

typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  required String sha,
  Value<int> size,
  Value<String?> codec,
  Value<int?> sampleRate,
  Value<int?> channels,
  Value<int?> bitrate,
  Value<int?> durationMs,
  Value<String> title,
  Value<String> artist,
  Value<String> album,
  Value<String?> year,
  Value<String?> artSha,
  Value<String?> releaseId,
  Value<String> releaseIdsJson,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> totalTracks,
  Value<int?> addedAt,
  Value<String> searchText,
  Value<String?> embeddedTitle,
  Value<String?> embeddedArtist,
  Value<String?> embeddedAlbum,
  Value<String?> embeddedYear,
  Value<String?> lyrics,
  Value<String?> lyricsSource,
  Value<int> rowid,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<String> sha,
  Value<int> size,
  Value<String?> codec,
  Value<int?> sampleRate,
  Value<int?> channels,
  Value<int?> bitrate,
  Value<int?> durationMs,
  Value<String> title,
  Value<String> artist,
  Value<String> album,
  Value<String?> year,
  Value<String?> artSha,
  Value<String?> releaseId,
  Value<String> releaseIdsJson,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> totalTracks,
  Value<int?> addedAt,
  Value<String> searchText,
  Value<String?> embeddedTitle,
  Value<String?> embeddedArtist,
  Value<String?> embeddedAlbum,
  Value<String?> embeddedYear,
  Value<String?> lyrics,
  Value<String?> lyricsSource,
  Value<int> rowid,
});

class $$TracksTableFilterComposer
    extends Composer<_$TunesDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sha => $composableBuilder(
    column: $table.sha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get channels => $composableBuilder(
    column: $table.channels,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bitrate => $composableBuilder(
    column: $table.bitrate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseId => $composableBuilder(
    column: $table.releaseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseIdsJson => $composableBuilder(
    column: $table.releaseIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddedTitle => $composableBuilder(
    column: $table.embeddedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddedArtist => $composableBuilder(
    column: $table.embeddedArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddedAlbum => $composableBuilder(
    column: $table.embeddedAlbum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddedYear => $composableBuilder(
    column: $table.embeddedYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lyrics => $composableBuilder(
    column: $table.lyrics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lyricsSource => $composableBuilder(
    column: $table.lyricsSource,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$TunesDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sha => $composableBuilder(
    column: $table.sha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get channels => $composableBuilder(
    column: $table.channels,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bitrate => $composableBuilder(
    column: $table.bitrate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseId => $composableBuilder(
    column: $table.releaseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseIdsJson => $composableBuilder(
    column: $table.releaseIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddedTitle => $composableBuilder(
    column: $table.embeddedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddedArtist => $composableBuilder(
    column: $table.embeddedArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddedAlbum => $composableBuilder(
    column: $table.embeddedAlbum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddedYear => $composableBuilder(
    column: $table.embeddedYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lyrics => $composableBuilder(
    column: $table.lyrics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lyricsSource => $composableBuilder(
    column: $table.lyricsSource,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$TunesDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sha =>
      $composableBuilder(column: $table.sha, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get channels =>
      $composableBuilder(column: $table.channels, builder: (column) => column);

  GeneratedColumn<int> get bitrate =>
      $composableBuilder(column: $table.bitrate, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get artSha =>
      $composableBuilder(column: $table.artSha, builder: (column) => column);

  GeneratedColumn<String> get releaseId =>
      $composableBuilder(column: $table.releaseId, builder: (column) => column);

  GeneratedColumn<String> get releaseIdsJson => $composableBuilder(
    column: $table.releaseIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get embeddedTitle => $composableBuilder(
    column: $table.embeddedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get embeddedArtist => $composableBuilder(
    column: $table.embeddedArtist,
    builder: (column) => column,
  );

  GeneratedColumn<String> get embeddedAlbum => $composableBuilder(
    column: $table.embeddedAlbum,
    builder: (column) => column,
  );

  GeneratedColumn<String> get embeddedYear => $composableBuilder(
    column: $table.embeddedYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lyrics =>
      $composableBuilder(column: $table.lyrics, builder: (column) => column);

  GeneratedColumn<String> get lyricsSource => $composableBuilder(
    column: $table.lyricsSource,
    builder: (column) => column,
  );
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, BaseReferences<_$TunesDatabase, $TracksTable, Track>),
          Track,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$TunesDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sha = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> codec = const Value.absent(),
                Value<int?> sampleRate = const Value.absent(),
                Value<int?> channels = const Value.absent(),
                Value<int?> bitrate = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> artSha = const Value.absent(),
                Value<String?> releaseId = const Value.absent(),
                Value<String> releaseIdsJson = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> totalTracks = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<String?> embeddedTitle = const Value.absent(),
                Value<String?> embeddedArtist = const Value.absent(),
                Value<String?> embeddedAlbum = const Value.absent(),
                Value<String?> embeddedYear = const Value.absent(),
                Value<String?> lyrics = const Value.absent(),
                Value<String?> lyricsSource = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                sha: sha,
                size: size,
                codec: codec,
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                durationMs: durationMs,
                title: title,
                artist: artist,
                album: album,
                year: year,
                artSha: artSha,
                releaseId: releaseId,
                releaseIdsJson: releaseIdsJson,
                trackNumber: trackNumber,
                discNumber: discNumber,
                totalTracks: totalTracks,
                addedAt: addedAt,
                searchText: searchText,
                embeddedTitle: embeddedTitle,
                embeddedArtist: embeddedArtist,
                embeddedAlbum: embeddedAlbum,
                embeddedYear: embeddedYear,
                lyrics: lyrics,
                lyricsSource: lyricsSource,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sha,
                Value<int> size = const Value.absent(),
                Value<String?> codec = const Value.absent(),
                Value<int?> sampleRate = const Value.absent(),
                Value<int?> channels = const Value.absent(),
                Value<int?> bitrate = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> artSha = const Value.absent(),
                Value<String?> releaseId = const Value.absent(),
                Value<String> releaseIdsJson = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> totalTracks = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<String?> embeddedTitle = const Value.absent(),
                Value<String?> embeddedArtist = const Value.absent(),
                Value<String?> embeddedAlbum = const Value.absent(),
                Value<String?> embeddedYear = const Value.absent(),
                Value<String?> lyrics = const Value.absent(),
                Value<String?> lyricsSource = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                sha: sha,
                size: size,
                codec: codec,
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                durationMs: durationMs,
                title: title,
                artist: artist,
                album: album,
                year: year,
                artSha: artSha,
                releaseId: releaseId,
                releaseIdsJson: releaseIdsJson,
                trackNumber: trackNumber,
                discNumber: discNumber,
                totalTracks: totalTracks,
                addedAt: addedAt,
                searchText: searchText,
                embeddedTitle: embeddedTitle,
                embeddedArtist: embeddedArtist,
                embeddedAlbum: embeddedAlbum,
                embeddedYear: embeddedYear,
                lyrics: lyrics,
                lyricsSource: lyricsSource,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, BaseReferences<_$TunesDatabase, $TracksTable, Track>),
      Track,
      PrefetchHooks Function()
    >;
typedef $$ReleasesTableCreateCompanionBuilder = ReleasesCompanion Function({
  required String id,
  required String title,
  required String artist,
  Value<String?> year,
  Value<String?> artSha,
  Value<int?> totalTracks,
  Value<String> trackShasJson,
  Value<String> releaseTracksJson,
  Value<String?> type,
  Value<String> searchText,
  Value<int> rowid,
});
typedef $$ReleasesTableUpdateCompanionBuilder = ReleasesCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> artist,
  Value<String?> year,
  Value<String?> artSha,
  Value<int?> totalTracks,
  Value<String> trackShasJson,
  Value<String> releaseTracksJson,
  Value<String?> type,
  Value<String> searchText,
  Value<int> rowid,
});

class $$ReleasesTableFilterComposer
    extends Composer<_$TunesDatabase, $ReleasesTable> {
  $$ReleasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackShasJson => $composableBuilder(
    column: $table.trackShasJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseTracksJson => $composableBuilder(
    column: $table.releaseTracksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReleasesTableOrderingComposer
    extends Composer<_$TunesDatabase, $ReleasesTable> {
  $$ReleasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackShasJson => $composableBuilder(
    column: $table.trackShasJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseTracksJson => $composableBuilder(
    column: $table.releaseTracksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReleasesTableAnnotationComposer
    extends Composer<_$TunesDatabase, $ReleasesTable> {
  $$ReleasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get artSha =>
      $composableBuilder(column: $table.artSha, builder: (column) => column);

  GeneratedColumn<int> get totalTracks => $composableBuilder(
    column: $table.totalTracks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackShasJson => $composableBuilder(
    column: $table.trackShasJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get releaseTracksJson => $composableBuilder(
    column: $table.releaseTracksJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );
}

class $$ReleasesTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $ReleasesTable,
          Release,
          $$ReleasesTableFilterComposer,
          $$ReleasesTableOrderingComposer,
          $$ReleasesTableAnnotationComposer,
          $$ReleasesTableCreateCompanionBuilder,
          $$ReleasesTableUpdateCompanionBuilder,
          (Release, BaseReferences<_$TunesDatabase, $ReleasesTable, Release>),
          Release,
          PrefetchHooks Function()
        > {
  $$ReleasesTableTableManager(_$TunesDatabase db, $ReleasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReleasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReleasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReleasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> artSha = const Value.absent(),
                Value<int?> totalTracks = const Value.absent(),
                Value<String> trackShasJson = const Value.absent(),
                Value<String> releaseTracksJson = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReleasesCompanion(
                id: id,
                title: title,
                artist: artist,
                year: year,
                artSha: artSha,
                totalTracks: totalTracks,
                trackShasJson: trackShasJson,
                releaseTracksJson: releaseTracksJson,
                type: type,
                searchText: searchText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String artist,
                Value<String?> year = const Value.absent(),
                Value<String?> artSha = const Value.absent(),
                Value<int?> totalTracks = const Value.absent(),
                Value<String> trackShasJson = const Value.absent(),
                Value<String> releaseTracksJson = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReleasesCompanion.insert(
                id: id,
                title: title,
                artist: artist,
                year: year,
                artSha: artSha,
                totalTracks: totalTracks,
                trackShasJson: trackShasJson,
                releaseTracksJson: releaseTracksJson,
                type: type,
                searchText: searchText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReleasesTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $ReleasesTable,
      Release,
      $$ReleasesTableFilterComposer,
      $$ReleasesTableOrderingComposer,
      $$ReleasesTableAnnotationComposer,
      $$ReleasesTableCreateCompanionBuilder,
      $$ReleasesTableUpdateCompanionBuilder,
      (Release, BaseReferences<_$TunesDatabase, $ReleasesTable, Release>),
      Release,
      PrefetchHooks Function()
    >;
typedef $$ArtistsTableCreateCompanionBuilder = ArtistsCompanion Function({
  required String name,
  Value<String?> artSha,
  Value<String> searchText,
  Value<int> rowid,
});
typedef $$ArtistsTableUpdateCompanionBuilder = ArtistsCompanion Function({
  Value<String> name,
  Value<String?> artSha,
  Value<String> searchText,
  Value<int> rowid,
});

class $$ArtistsTableFilterComposer
    extends Composer<_$TunesDatabase, $ArtistsTable> {
  $$ArtistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArtistsTableOrderingComposer
    extends Composer<_$TunesDatabase, $ArtistsTable> {
  $$ArtistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artSha => $composableBuilder(
    column: $table.artSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtistsTableAnnotationComposer
    extends Composer<_$TunesDatabase, $ArtistsTable> {
  $$ArtistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artSha =>
      $composableBuilder(column: $table.artSha, builder: (column) => column);

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );
}

class $$ArtistsTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $ArtistsTable,
          Artist,
          $$ArtistsTableFilterComposer,
          $$ArtistsTableOrderingComposer,
          $$ArtistsTableAnnotationComposer,
          $$ArtistsTableCreateCompanionBuilder,
          $$ArtistsTableUpdateCompanionBuilder,
          (Artist, BaseReferences<_$TunesDatabase, $ArtistsTable, Artist>),
          Artist,
          PrefetchHooks Function()
        > {
  $$ArtistsTableTableManager(_$TunesDatabase db, $ArtistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<String?> artSha = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsCompanion(
                name: name,
                artSha: artSha,
                searchText: searchText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                Value<String?> artSha = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsCompanion.insert(
                name: name,
                artSha: artSha,
                searchText: searchText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArtistsTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $ArtistsTable,
      Artist,
      $$ArtistsTableFilterComposer,
      $$ArtistsTableOrderingComposer,
      $$ArtistsTableAnnotationComposer,
      $$ArtistsTableCreateCompanionBuilder,
      $$ArtistsTableUpdateCompanionBuilder,
      (Artist, BaseReferences<_$TunesDatabase, $ArtistsTable, Artist>),
      Artist,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$TunesDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$TunesDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$TunesDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$TunesDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$TunesDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$TunesDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$TrackEditsTableCreateCompanionBuilder = TrackEditsCompanion Function({
  required String sha,
  required String field,
  required String value,
  required int editedAt,
  Value<int> rowid,
});
typedef $$TrackEditsTableUpdateCompanionBuilder = TrackEditsCompanion Function({
  Value<String> sha,
  Value<String> field,
  Value<String> value,
  Value<int> editedAt,
  Value<int> rowid,
});

class $$TrackEditsTableFilterComposer
    extends Composer<_$TunesDatabase, $TrackEditsTable> {
  $$TrackEditsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sha => $composableBuilder(
    column: $table.sha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrackEditsTableOrderingComposer
    extends Composer<_$TunesDatabase, $TrackEditsTable> {
  $$TrackEditsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sha => $composableBuilder(
    column: $table.sha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrackEditsTableAnnotationComposer
    extends Composer<_$TunesDatabase, $TrackEditsTable> {
  $$TrackEditsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sha =>
      $composableBuilder(column: $table.sha, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);
}

class $$TrackEditsTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $TrackEditsTable,
          TrackEdit,
          $$TrackEditsTableFilterComposer,
          $$TrackEditsTableOrderingComposer,
          $$TrackEditsTableAnnotationComposer,
          $$TrackEditsTableCreateCompanionBuilder,
          $$TrackEditsTableUpdateCompanionBuilder,
          (
            TrackEdit,
            BaseReferences<_$TunesDatabase, $TrackEditsTable, TrackEdit>,
          ),
          TrackEdit,
          PrefetchHooks Function()
        > {
  $$TrackEditsTableTableManager(_$TunesDatabase db, $TrackEditsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackEditsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackEditsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackEditsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sha = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> editedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrackEditsCompanion(
                sha: sha,
                field: field,
                value: value,
                editedAt: editedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sha,
                required String field,
                required String value,
                required int editedAt,
                Value<int> rowid = const Value.absent(),
              }) => TrackEditsCompanion.insert(
                sha: sha,
                field: field,
                value: value,
                editedAt: editedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrackEditsTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $TrackEditsTable,
      TrackEdit,
      $$TrackEditsTableFilterComposer,
      $$TrackEditsTableOrderingComposer,
      $$TrackEditsTableAnnotationComposer,
      $$TrackEditsTableCreateCompanionBuilder,
      $$TrackEditsTableUpdateCompanionBuilder,
      (TrackEdit, BaseReferences<_$TunesDatabase, $TrackEditsTable, TrackEdit>),
      TrackEdit,
      PrefetchHooks Function()
    >;
typedef $$QueueEntriesTableCreateCompanionBuilder =
    QueueEntriesCompanion Function({
      Value<int> id,
      required int position,
      required String trackSha,
      Value<int> state,
      required int addedAt,
    });
typedef $$QueueEntriesTableUpdateCompanionBuilder =
    QueueEntriesCompanion Function({
      Value<int> id,
      Value<int> position,
      Value<String> trackSha,
      Value<int> state,
      Value<int> addedAt,
    });

class $$QueueEntriesTableFilterComposer
    extends Composer<_$TunesDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackSha => $composableBuilder(
    column: $table.trackSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueEntriesTableOrderingComposer
    extends Composer<_$TunesDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackSha => $composableBuilder(
    column: $table.trackSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueEntriesTableAnnotationComposer
    extends Composer<_$TunesDatabase, $QueueEntriesTable> {
  $$QueueEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get trackSha =>
      $composableBuilder(column: $table.trackSha, builder: (column) => column);

  GeneratedColumn<int> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$QueueEntriesTableTableManager
    extends
        RootTableManager<
          _$TunesDatabase,
          $QueueEntriesTable,
          QueueEntry,
          $$QueueEntriesTableFilterComposer,
          $$QueueEntriesTableOrderingComposer,
          $$QueueEntriesTableAnnotationComposer,
          $$QueueEntriesTableCreateCompanionBuilder,
          $$QueueEntriesTableUpdateCompanionBuilder,
          (
            QueueEntry,
            BaseReferences<_$TunesDatabase, $QueueEntriesTable, QueueEntry>,
          ),
          QueueEntry,
          PrefetchHooks Function()
        > {
  $$QueueEntriesTableTableManager(_$TunesDatabase db, $QueueEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> trackSha = const Value.absent(),
                Value<int> state = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
              }) => QueueEntriesCompanion(
                id: id,
                position: position,
                trackSha: trackSha,
                state: state,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int position,
                required String trackSha,
                Value<int> state = const Value.absent(),
                required int addedAt,
              }) => QueueEntriesCompanion.insert(
                id: id,
                position: position,
                trackSha: trackSha,
                state: state,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$TunesDatabase,
      $QueueEntriesTable,
      QueueEntry,
      $$QueueEntriesTableFilterComposer,
      $$QueueEntriesTableOrderingComposer,
      $$QueueEntriesTableAnnotationComposer,
      $$QueueEntriesTableCreateCompanionBuilder,
      $$QueueEntriesTableUpdateCompanionBuilder,
      (
        QueueEntry,
        BaseReferences<_$TunesDatabase, $QueueEntriesTable, QueueEntry>,
      ),
      QueueEntry,
      PrefetchHooks Function()
    >;

class $TunesDatabaseManager {
  final _$TunesDatabase _db;
  $TunesDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$ReleasesTableTableManager get releases =>
      $$ReleasesTableTableManager(_db, _db.releases);
  $$ArtistsTableTableManager get artists =>
      $$ArtistsTableTableManager(_db, _db.artists);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$TrackEditsTableTableManager get trackEdits =>
      $$TrackEditsTableTableManager(_db, _db.trackEdits);
  $$QueueEntriesTableTableManager get queueEntries =>
      $$QueueEntriesTableTableManager(_db, _db.queueEntries);
}
