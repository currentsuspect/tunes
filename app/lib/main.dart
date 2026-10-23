import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/rendering.dart' show HitTestResult, RenderEditable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/audio/audio_focus.dart';
import 'core/audio/queue_restore.dart';
import 'core/audio/stream_relay.dart';
import 'core/net/update_check.dart';
import 'core/net/update_installer.dart';
import 'core/platform/device.dart';
import 'features/desktop/desktop_keys.dart';
import 'features/lyrics/lyrics_sheet.dart';
import 'features/desktop/desktop_play_bar.dart';
import 'features/desktop/desktop_sidebar.dart';
import 'features/playlists/playlist_page.dart';
import 'features/queue/queue_sheet.dart';
import 'features/updates/update_banner.dart';
import 'core/audio/tune_audio_handler.dart';
import 'core/audio/position_saver.dart';
import 'core/audio/tune_player.dart';
import 'core/data/database.dart';
import 'core/data/art_store.dart';
import 'core/data/download_manager.dart';
import 'core/data/lyric_sharing.dart';
import 'core/data/download_store.dart';
import 'core/data/playback_cache.dart';
import 'core/data/likes_store.dart';
import 'core/sync/account_sync.dart';
import 'core/sync/client_transport.dart';
import 'core/sync/connect_control.dart';
import 'core/sync/connect_player.dart';
import 'core/sync/now_sync.dart';
import 'core/sync/sync_domains.dart';
import 'core/sync/sync_engine.dart';
import 'features/sync/continue_card.dart';
import 'core/data/manifest_store.dart';
import 'core/data/play_history.dart';
import 'core/data/playlist_store.dart';
import 'core/data/queue_store.dart';
import 'core/auth/media_grants.dart';
import 'core/auth/secure_token_store.dart';
import 'core/auth/tunes_auth.dart';
import 'core/data/settings_store.dart';
import 'core/data/reachability.dart';
import 'core/nav/nav_controller.dart';
import 'core/nav/root_route_guard.dart';
import 'core/radio/radio_engine.dart';
import 'core/theme/looks.dart';
import 'core/ui/look_extras.dart';
import 'core/radio/session.dart';
import 'core/net/tunes_client.dart';
import 'core/platform/diag_log.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/tokens.dart';
import 'core/ui/offline_note.dart';
import 'core/ui/downloads_bar.dart';
import 'core/ui/greeting.dart';
import 'core/ui/tunes_nav_bar.dart';
import 'core/ui/profile_avatar.dart';
import 'domain/collection_gaps.dart';
import 'domain/threads.dart';
import 'domain/discography.dart';
import 'domain/manifest.dart';
import 'domain/mixes.dart';
import 'domain/sync_watermark.dart';
import 'domain/whats_new.dart';
import 'features/album/album_page.dart';
import 'features/artist/artist_page.dart';
import 'features/discover/discover_view.dart';
import 'features/downloads/downloads_sheet.dart';
import 'features/home/home_skeleton.dart';
import 'features/home/home_view.dart';
import 'features/mixes/mix_page.dart';
import 'features/whats_new/whats_new_page.dart';
import 'features/library/library_view.dart';
import 'features/now_playing/now_playing_page.dart';
import 'features/player/mini_player_bar.dart';
import 'features/profile/settings_page.dart';
import 'features/search/search_view.dart';

const _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'local');
const _buildNumber = String.fromEnvironment(
  'BUILD_NUMBER',
  defaultValue: 'local',
);
const _channel = String.fromEnvironment('CHANNEL', defaultValue: 'local');

/// Whether streamed songs go through [StreamRelay].
const _relayOn = true;

const _tunesdUrl = String.fromEnvironment(
  'TUNESD_URL',
  defaultValue: 'http://192.168.100.6:4780',
);

/// Where accounts live: sign-in tokens, media grants and sync. Separate from
/// the library address because a computer on the same network as the box reads
/// its library from the box directly, yet its account is still the one the
/// edge knows about.
const _accountUrl = String.fromEnvironment(
  'ACCOUNT_URL',
  defaultValue: 'https://tunes.aestra.studio',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars. Recent Android does this to apps whether
  // they ask or not, so an app that has not opted in gets the layout without
  // the chance to say what the bars should look like over it.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Light icons: this app is dark everywhere, and the bars sit over its
      // own surface rather than over anything the system chose.
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  if (!const bool.fromEnvironment('SKIP_MEDIAKIT')) {
    MediaKit.ensureInitialized();
  }
  await DiagLog.init();
  DiagLog.log('main start');
  final support = await getApplicationSupportDirectory();
  final store = DownloadStore(support);
  await store.load();
  // Covers live beside downloads, not in them: a downloaded library with
  // empty frames is half an offline copy. Content-addressed like the audio,
  // so presence is the whole index and nothing here ever goes stale.
  final artStore = ArtStore(Directory('${support.path}/art'));
  await artStore.load();
  final db = TunesDatabase();
  final manifestStore = ManifestStore(db);
  final queueStore = QueueStore(db);
  // Loaded before the first frame so every screen can read a setting during
  // build. A setting that has to be awaited mid-build is one that flickers.
  final settings = SettingsStore(db);
  await settings.load();
  // Loaded before the first frame for the same reason as settings: a heart
  // that has to await its own state flickers on every row of every list.
  final likes = LikesStore(db);
  await likes.load();
  // Not preloaded: playlists are read when a screen asks for them, and the
  // set can be large enough that holding it all for a heart-sized answer
  // would be the wrong trade.
  final playlists = PlaylistStore(db);
  // A stored address wins over the compiled-in one, so a build can be handed
  // to someone whose tunesd is somewhere else without rebuilding it for them.
  // Falls back to _tunesdUrl when unset, which is every existing install.
  final client = TunesClient(settings.serverUrl ?? _tunesdUrl, support);
  artStore.attachClient(client);
  final reachability = Reachability();
  Heartbeat(ping: client.ping, reachability: reachability).start();
  // Identity, and the signed capabilities it mints. The refresh token lives in
  // the keystore; access tokens are memory-only; media grants are cached until
  // they expire. Nothing here ships inside the APK.
  // The account service is always the edge, wherever the library is read from.
  final accountClient = TunesClient(_accountUrl);
  final auth = TunesAuth(
    post: accountClient.postJson,
    store: SecureTokenStore(),
  );
  final grants = MediaGrants(auth: auth);
  // Streamed bytes land here, LRU-capped, so replaying a track reads from
  // disk instead of fetching from the cloud again. Explicit downloads stay
  // separate: they are forever and user-managed, this is a cache and the app
  // evicts it. One transfer at a time, behind playback in priority.
  final cacheStore = DownloadStore(Directory('${support.path}/stream-cache'));
  await cacheStore.load();
  final streamCache = StreamCache(cacheStore, maxBytes: settings.cacheBytes);
  await streamCache.load();
  settings.addListener(() {
    final size = settings.cacheBytes;
    if (size == streamCache.maxBytes) return;
    streamCache.maxBytes = size;
    unawaited(streamCache.sweep());
  });
  final caching = DownloadManager(
    client: client,
    store: cacheStore,
    maxConcurrent: 1,
  );
  // Streamed songs play through the phone so every byte heard lands in the
  // cache (core/audio/stream_relay.dart). The player is wired to it below;
  // until it is listening, songs stream straight from the server as before.
  late final TunePlayer Function() playerRef;
  final relay = StreamRelay(
    dir: cacheStore.dir,
    upstreamFor: (sha) async {
      final path = '/t/$sha';
      if (!grants.has(path)) {
        try {
          await grants.prime([path]);
        } catch (_) {
          // Unsigned, the edge refuses it: a visible failure, not a hang.
        }
      }
      return Uri.parse('${client.baseUrl}${grants.urlFor(path) ?? path}');
    },
    onRefused: (sha) => grants.forget('/t/$sha'),
    commit: (sha, path) async {
      await cacheStore.add(sha, path);
      // Songs still to come that are now complete play from the file.
      playerRef().refreshSources();
      unawaited(streamCache.sweepSoon());
    },
  );
  try {
    // Partial files from a previous run cannot be trusted: which of their
    // bytes are real was only known in memory.
    await relay.dropPartials(cacheStore.contains);
    // A kill switch: off, songs stream straight from the server as before.
    if (_relayOn) await relay.start();
  } catch (e) {
    DiagLog.log('relay: could not start ($e); streaming directly');
  }
  final resolver = TrackResolver(
    store: store,
    cache: streamCache,
    caching: caching,
    client: client,
    grants: grants,
    relay: relay,
    prefetchOk: () async => switch (settings.prefetchNext) {
      0 => false,
      2 => true,
      _ => await onWifi(),
    },
  );
  // Everything the client fetches itself now carries the device's token. Set
  // after both exist because they are mutually referential: the client is the
  // auth transport, and auth supplies the client's credential.
  client.bearer = () async {
    final res = await auth.accessToken();
    return res is AuthOk ? res.accessToken : null;
  };
  accountClient.bearer = client.bearer;
  final player = MediaKitTunePlayer(
    // Download first, stream cache second, signed URL last -- and resolving
    // a URL also enqueues a background cache of the same bytes, so the
    // second play of anything is a disk read. Sweeping rides along: opens
    // are the only moments new bytes can have landed.
    trackUriFor: (track) {
      final uri = resolver.uriFor(track);
      unawaited(streamCache.sweepSoon());
      return uri;
    },
    // Mint for the whole queue in one round trip before it opens. Downloaded
    // tracks are skipped: they resolve to a local path and never touch the
    // network, so signing them would be pure latency.
    // Anything on the phone -- downloaded or in the stream cache -- is skipped
    // the same way.
    // Through the relay nothing needs signing before the queue opens: the
    // relay signs each song as it fetches it. Signed ahead anyway, in the
    // background, so that fetch does not wait on a round trip.
    prepareQueue: (tracks) async {
      final paths = [
        for (final t in tracks)
          if (!resolver.isLocal(t)) '/t/${t.sha}',
      ];
      if (relay.port != null) {
        unawaited(grants.prime(paths).catchError((_) {}));
        return;
      }
      await grants.prime(paths);
    },
    onQueuePlayed: (tracks) {
      // Mirror the play queue into the persistent store so the
      // QueueSheet reflects what's playing, and the queue survives
      // restarts. All playback entry points (home, library, album,
      // artist, search) route through this single hook.
      unawaited(queueStore.replace(tracks.map((t) => t.sha).toList()));
    },
  );
  playerRef = () => player;

  // Keep what is playing and warm what is next, but only once playback has
  // started, so nothing competes with the stream the listener is waiting on.
  // On Wi-Fi a song is kept whole after 3 s of play; on mobile data only
  // after 30 s, once it has clearly been chosen rather than skipped past.
  final follower = StreamFollower(
    keep: resolver.keep,
    warm: resolver.warm,
    afterFor: () => reachability.wifi
        ? const Duration(seconds: 3)
        : const Duration(seconds: 30),
  );
  player.addListener(
    () => follower.tick(
      queue: player.queue,
      index: player.index,
      position: player.position,
      playing: player.playing,
    ),
  );
  TuneAudioHandler? boundHandler;
  Future<void>? audioInitFlight;

  Future<void> initAudioService() async {
    try {
      final handler = TuneAudioHandler(
        player,
        // A closure, so notification artwork follows the server too rather
        // than being pinned to whatever it was at launch.
        // A closure, so notification artwork follows both the server and
        // the current set of grants rather than being pinned at startup.
        artUriFor: (sha) {
          // The saved copy first: the notification and lock screen fetch this
          // themselves, and a network address there is a blank cover offline.
          final saved = artStore.pathFor(sha);
          if (saved != null && File(saved).existsSync()) {
            return Uri.file(saved).toString();
          }
          final signed = grants.urlFor('/art/$sha');
          return '${client.baseUrl}${signed ?? '/art/$sha'}';
        },
        stopOnTaskRemoved: () => settings.stopOnClose,
      );
      await AudioService.init(
        builder: () => handler,
        config: AudioServiceConfig(
          androidNotificationChannelId:
              'com.currentsuspect.tunes.channel.audio',
          androidNotificationChannelName: 'Tunes playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // The notification carried all four transport controls and a
          // MediaStyle template, and the device drew none of them. Both of
          // these were at their defaults, and audio_service documents that
          // some devices will not render the controls or the seek bar unless
          // the small icon is a monochrome white silhouette and the colour is
          // opaque -- the default icon is the full-colour launcher mipmap and
          // the default colour is fully transparent.
          androidNotificationIcon: 'drawable/ic_stat_music',
          notificationColor: Tones.primary,
        ),
      );
      AudioService.asyncError.listen((e) => DiagLog.log('async error: $e'));
      boundHandler = handler;
      DiagLog.log('audio_service bound');
    } catch (e) {
      DiagLog.log('AudioService.init failed (lazy): $e');
    }
  }

  /// Binds the audio service to the current player generation, re-binding
  /// when it follows a halted one.
  ///
  /// A relaunch builds a new player around the same mpv peer while the
  /// service still observes the old wrapper, whose queue froze at close
  /// time: the notification then follows stale state while the mini-player
  /// follows the live one. Rebinding swaps the service to a handler on the
  /// live wrapper (whose constructor immediately republishes), and the old
  /// generation, detached at claim time, never publishes again. One
  /// publisher, always the live one.
  Future<void> ensureAudioService() {
    if (boundHandler?.player == player) return Future.value();
    return audioInitFlight ??= initAudioService().whenComplete(
      () => audioInitFlight = null,
    );
  }

  // The player is built lazily on first play, so the stored choice has to be
  // handed to it up front rather than applied to an instance that does not
  // exist yet.
  unawaited(player.setGapless(settings.gapless));

  // The headphone EQ (Settings > Sound): applied now, and again whenever the
  // chosen profile or its filters change.
  // Android's libmpv has only ffmpeg's `equalizer` filter: shelves become
  // peaks and the preamp goes through mpv's volume (domain/eq.dart).
  ({String af, double preampDb}) eqChain() =>
      settings.eqProfile?.mpvChain(full: !Platform.isAndroid) ??
      (af: '', preampDb: 0.0);
  var applied = eqChain();
  unawaited(player.setAudioFilter(applied.af, preampDb: applied.preampDb));
  settings.addListener(() {
    final next = eqChain();
    if (next == applied) return;
    applied = next;
    unawaited(player.setAudioFilter(next.af, preampDb: next.preampDb));
  });
  // A chain mpv refuses is dropped by the player so music keeps playing;
  // the setting follows, so Settings shows what is actually on.
  player.onAudioFilterFailed = () {
    applied = (af: '', preampDb: 0.0);
    unawaited(settings.setEqActive(null));
  };

  // Watches the player from here on, so a listen is recorded whether it was
  // started from the library, a notification, or a headset button.
  final history = PlayHistory(db, player);

  // Remember which track is current, so the next launch can put the listener
  // back on it rather than at the top of the queue. Written on change only:
  // the player notifies four times a second, and this is a disk write.
  String? lastSeenSha;
  final positionSaver = PositionSaver();
  player.addListener(() {
    final sha = player.current?.sha;
    if (sha != lastSeenSha) {
      lastSeenSha = sha;
      unawaited(settings.setLastPlayedSha(sha));
    }
    // Where in the track, so a relaunch resumes rather than restarting. The
    // saver decides when it is worth a disk write (see PositionSaver): every
    // five seconds of movement, on a new song, and never for the engine being
    // reset to zero by a stop.
    final write = positionSaver.tick(
      sha: sha,
      position: player.position,
      playing: player.playing,
    );
    if (write != null) unawaited(settings.setLastPosition(write));
  });

  // Account sync: likes, playlists, edits and the name follow the listener
  // from device to device, and where the music is shows on the others.
  final remoteNow = RemoteNow();
  final library = LibraryIndex();
  String? myDeviceId;
  ConnectControl? control;
  final syncEngine = SyncEngine(
    transport: ClientSyncTransport(accountClient),
    domains: [
      LikesDomain(likes),
      PlaylistsDomain(playlists),
      EditsDomain(manifestStore),
      ProfileDomain(settings),
      HistoryDomain(
        history,
        settings,
        () async => myDeviceId ??= await auth.deviceId(),
      ),
    ],
    memory: DbSyncMemory(db),
    deviceId: () async => myDeviceId ??= await auth.deviceId(),
    special: (doc, devices) {
      remoteNow.ingest(doc, devices, myDeviceId);
      control?.onDoc(doc, myDeviceId);
    },
  );
  final accountSync = AccountSync(engine: syncEngine);
  NowPublisher(
    player: player,
    push: syncEngine.pushNow,
    skew: () => syncEngine.skewMs,
  ).start();
  // What the screens talk to: this device's player, or a window onto another
  // device's music when one is playing and this one is silent.
  final connected = ConnectPlayer(
    local: player,
    remote: remoteNow,
    resolve: library.bySha,
    serverNow: accountSync.serverNowMs,
    send: (doc) => syncEngine.pushNow([doc]),
  );
  control = ConnectControl(
    local: player,
    engine: syncEngine,
    serverNow: accountSync.serverNowMs,
    isBusy: () =>
        player.playing ||
        connected.isRemote ||
        remoteNow.isLive(accountSync.serverNowMs()),
  )..start();
  accountSync.control = control;
  // Turning history sharing off drops what other devices sent, so this device's
  // taste is its own again; turning it on asks for everything afresh, since
  // what was skipped while it was off has already gone past the cursor.
  var sharingHistory = settings.syncHistory;
  settings.addListener(() {
    if (settings.syncHistory == sharingHistory) return;
    sharingHistory = settings.syncHistory;
    if (sharingHistory) {
      unawaited(
        syncEngine.memory.writeCursor(0).then((_) => accountSync.poke()),
      );
    } else {
      unawaited(history.dropForeign());
    }
  });
  likes.addListener(accountSync.poke);
  playlists.addListener(accountSync.poke);
  reachability.addListener(() {
    if (!reachability.offline) accountSync.poke();
    // Gone offline: whatever is queued and already on the phone plays from
    // there, the song on included, instead of failing a stream first.
    if (reachability.offline) player.refreshSources(touchCurrent: true);
    if (!reachability.offline) {
      // Back online: sign what is queued again (a queue opened offline holds
      // unsigned addresses the server refuses), move it onto the new
      // addresses, and pick up a song held for the connection.
      final pending = [
        for (final t in player.queue)
          if (!resolver.isLocal(t)) '/t/${t.sha}',
      ];
      unawaited(
        grants
            .prime(pending)
            .catchError((_) {})
            .whenComplete(player.refreshSources),
      );
      player.networkReturned();
    }
  });
  player.isOffline = () => reachability.offline;
  // Asked when a stream fails, so a service that cannot be reached counts
  // toward the same three strikes as the heartbeat instead of flipping the
  // app offline on one transient miss.
  player.checkOnline = () async {
    if (!await hasNetworkAddress()) {
      // Not a miss: there is no address to reach anything from. Saying so at
      // once is honest, and three beats of "online" here would only delay the
      // banner behind a fact that is already known.
      reachability.setOffline(true);
      return false;
    }
    // Bounded: while this runs, further stream errors are ignored, so a
    // check that hung during a network change stalled error handling for
    // good and mpv skipped through the queue on its own.
    final answered = await client.ping().timeout(
      const Duration(seconds: 8),
      onTimeout: () => false,
    );
    if (answered) {
      reachability.ok();
    } else {
      // A single failed stream plus ping can still be a transient server or
      // network wobble. Keep the same three-strike threshold as the heartbeat
      // so one missed request cannot flip the whole app offline.
      reachability.failed();
    }
    return answered;
  };
  // A song that has finished saving moves off the server in the queue too.
  caching.onSaved = (_) => player.refreshSources();

  player.onFirstPlay = ensureAudioService;
  player.onRestored = ensureAudioService;
  // Not awaited: it only has to be in place before the first track, and the
  // library should not wait on the audio session to draw.
  unawaited(AudioFocus(player).attach());

  DiagLog.log('runApp');
  runApp(
    ArtScope(
      store: artStore,
      child: ReachabilityScope(
        reachability: reachability,
        child: TunesApp(
          client: client,
          grants: grants,
          auth: auth,
          player: connected,
          store: store,
          artStore: artStore,
          reachability: reachability,
          manifestStore: manifestStore,
          queueStore: queueStore,
          settings: settings,
          history: history,
          likes: likes,
          playlists: playlists,
          accountSync: accountSync,
          remoteNow: remoteNow,
          localPlayer: player,
          library: library,
        ),
      ),
    ),
  );
  accountSync.start();
}

/// Every path that needs a signed grant: artwork for tracks, releases and
/// artists, plus streamable bytes for anything not already on disk.
///
/// Pure so the set is unit-testable -- a missing category here is invisible
/// (a placeholder where a photo belongs) rather than loud, which is exactly
/// how artist photos went unprimed while every cover around them worked.
/// [pathFor] answers like [DownloadStore.pathFor]: non-null means on disk.
Set<String> grantPathsFor(
  TunesManifest manifest,
  String? Function(String sha) pathFor,
) {
  final paths = <String>{};
  for (final t in manifest.tracks) {
    final art = t.artSha;
    if (art != null && art.isNotEmpty) paths.add('/art/$art');
    // Streaming grants for anything not already on disk. Downloaded tracks
    // resolve to a local path and never touch the network, so a grant for
    // one would be waste. Streams ride /t/, not /track/.
    if (pathFor(t.sha) == null) paths.add('/t/${t.sha}');
  }
  for (final r in manifest.releases) {
    final art = r.artSha;
    if (art != null && art.isNotEmpty) paths.add('/art/$art');
  }
  for (final a in manifest.artists) {
    final art = a.artSha;
    if (art != null && art.isNotEmpty) paths.add('/art/$art');
  }
  return paths;
}

class TunesApp extends StatefulWidget {
  const TunesApp({
    super.key,
    required this.client,
    required this.grants,
    required this.auth,
    required this.player,
    required this.store,
    required this.artStore,
    required this.reachability,
    required this.manifestStore,
    required this.queueStore,
    required this.settings,
    required this.history,
    required this.likes,
    required this.playlists,
    this.accountSync,
    this.remoteNow,
    this.localPlayer,
    this.library,
  });

  final TunesClient client;

  /// Signed media capabilities, consulted when building artwork URLs.
  final MediaGrants grants;

  /// Device identity, so Settings can offer enrolment.
  final TunesAuth auth;
  final TunePlayer player;
  final DownloadStore store;
  final ArtStore artStore;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;
  final SettingsStore settings;
  final PlayHistory history;
  final LikesStore likes;
  final PlaylistStore playlists;

  /// Account sync and where the listener's music is on other devices. Absent
  /// in tests, which have no account.
  final AccountSync? accountSync;
  final RemoteNow? remoteNow;
  final TunePlayer? localPlayer;
  final LibraryIndex? library;

  @override
  State<TunesApp> createState() => _TunesAppState();
}

class _TunesAppState extends State<TunesApp> {
  // Owned here, above MaterialApp, because DownloadScope has to sit above the
  // Navigator. It used to be created inside AppShell, which is MaterialApp's
  // `home` -- so every pushed route (album, artist) was a sibling of the
  // scope rather than a descendant, DownloadScope.maybeOf returned null
  // there, and tapping download on an album page showed nothing at all until
  // the route was rebuilt by leaving and coming back.
  late final DownloadManager _downloads;

  /// Picks the look (theme, light or dark, auto by time of day) and redraws
  /// the app in it.
  late final ThemeController _theme;

  @override
  void initState() {
    super.initState();
    _theme = ThemeController(widget.settings);
    _downloads = DownloadManager(
      client: widget.client,
      store: widget.store,
      artStore: widget.artStore,
    )..onSaved = (_) => widget.player.refreshSources();
  }

  @override
  void dispose() {
    _theme.dispose();
    _downloads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Every scope sits above the Navigator, so a pushed route -- an album
    // page, the player -- can read them. A scope below it is the bug that
    // made download progress invisible on album pages.
    return SettingsScope(
      settings: widget.settings,
      child: LikesScope(
        likes: widget.likes,
        child: PlaylistScope(
          playlists: widget.playlists,
          child: DownloadScope(
            manager: _downloads,
            child: ListenableBuilder(
              listenable: _theme,
              builder: (context, _) => MaterialApp(
                title: 'tunes',
                debugShowCheckedModeBanner: false,
                theme: buildTunesTheme(mq),
                navigatorObservers: [_rootGuard],
                // Crayon's paper, Noir's grain: over every route.
                builder: (context, child) =>
                    LookGround(child: child ?? const SizedBox.shrink()),
                home: _shell(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The shell as the Navigator's one route. Also what the guard puts back if
  /// that route is ever popped, which would otherwise leave a blank screen over
  /// a playing app.
  late final RootRouteGuard _rootGuard = RootRouteGuard(
    restore: () => MaterialPageRoute<void>(builder: (_) => _shell()),
  );

  Widget _shell() => AppShell(
    accountSync: widget.accountSync,
    remoteNow: widget.remoteNow,
    localPlayer: widget.localPlayer,
    library: widget.library,
    client: widget.client,
    grants: widget.grants,
    artStore: widget.artStore,
    auth: widget.auth,
    player: widget.player,
    store: widget.store,
    reachability: widget.reachability,
    manifestStore: widget.manifestStore,
    queueStore: widget.queueStore,
    settings: widget.settings,
    history: widget.history,
    downloads: _downloads,
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.client,
    required this.grants,
    required this.artStore,
    required this.auth,
    required this.player,
    required this.store,
    required this.reachability,
    required this.manifestStore,
    required this.queueStore,
    required this.settings,
    required this.history,
    required this.downloads,
    this.accountSync,
    this.remoteNow,
    this.localPlayer,
    this.library,
  });

  final AccountSync? accountSync;
  final RemoteNow? remoteNow;

  /// The device's own player when [player] is the connected one in front of it.
  final TunePlayer? localPlayer;

  /// Kept up to date with the library so another device's music can be named.
  final LibraryIndex? library;

  final TunesClient client;

  /// Signed media capabilities, consulted when building artwork URLs.
  final MediaGrants grants;

  /// Covers saved on the phone; filled after each sync.
  final ArtStore artStore;

  /// Device identity, so Settings can offer enrolment.
  final TunesAuth auth;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;
  final SettingsStore settings;
  final PlayHistory history;

  /// Owned by [TunesApp], which publishes it above the Navigator so pushed
  /// routes can reach it too.
  final DownloadManager downloads;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// Picks this launch's greeting voice; fixed for the session so Home does
  /// not change its mind every time it rebuilds.
  final _greetingSeed = math.Random().nextInt(1 << 30);
  int _tab = 0;

  /// This device's own player, for everything that is about this device's
  /// listening (history, radio, where to resume). [AppShell.player] is what
  /// the screens show, which can be another device's music.
  TunePlayer get _local => widget.localPlayer ?? widget.player;

  /// Navigation history and the one-instance-per-identity pane registry.
  /// Panels are destinations rendered by this shell, not pushed routes:
  /// history may name an identity any number of times, the registry holds
  /// each identity once, and Back walks history.
  final NavController _nav = NavController();

  void _onNavChanged() {
    if (!mounted) return;
    final current = _nav.current;
    // The bottom bar follows the tab roots. Panels paint their own chrome;
    // when one is up, _tab is whatever tab it was opened from.
    if (current is TabDest && current.index != _tab) {
      _tab = current.index;
    }
    setState(() {});
  }

  /// One key per tab. Re-tapping the active tab swaps in a fresh key, which
  /// remounts that tab's scrollable at the top. The tabs hold no
  /// PageStorageKeys, so a fresh mount always starts at offset zero -- the
  /// cheap, uniform way to do "tap Home to go back to top" without threading
  /// a controller through four views and their conditional lists.
  late final List<Key> _tabKeys = List.generate(4, (_) => UniqueKey());
  TunesManifest? _manifest;
  Map<String, int> _playsByArtist = const {};
  List<ManifestTrack> _onRepeat = const [];
  List<ManifestTrack> _listenAgain = const [];
  List<Mix> _mixes = const [];
  List<UnheardAlbum> _unheard = const [];
  bool _syncing = false;
  Object? _lastSyncError;
  DateTime? _lastSyncAt;

  /// The fingerprint of the manifest last applied. /changes only lists songs
  /// that are new, so a song shown the moment it landed -- titled from its
  /// file name, no cover yet -- and then filled in by the daemon a minute
  /// later never counted as a change, and the phone kept the placeholder
  /// until it was restarted. A moved fingerprint means fetch it all again.
  String? _syncedIntegrity;

  /// When a moved fingerprint alone last caused a full fetch. The copy the
  /// phone downloads is published by the box in batches and can lag the
  /// fingerprint /changes reports, so without a limit a lagging copy would
  /// mean 5 MB on every poll until it caught up. Five minutes apart at most.
  DateTime? _integrityRefetchAt;
  final Set<String> _downloading = {};
  DownloadManager get _downloads => widget.downloads;
  final String _libraryFilter = '';
  List<ManifestTrack> _recents = [];
  // Fetched, not derived: deciding what is missing entirely needs the artist
  // discographies, which live on the daemon. Failure is silent -- the section
  // simply does not appear, which is the right answer when we cannot say.
  List<MissingRelease> _missingAlbums = const [];

  /// The radio session: what the listener is in the middle of, right now.
  ///
  /// In memory only, rebuilt on every launch -- a session that survives a
  /// restart is not a session (docs/RADIO.md §2). Fed by [_feedRadio] below.
  final RadioSession _radioSession = RadioSession();
  final RadioEngine _radioEngine = RadioEngine();

  /// Long-run taste for the engine's taste component. Refreshed with the other
  /// history-derived rails, so radio and the home screen never disagree about
  /// what was played.
  TasteSnapshot _taste = const TasteSnapshot();

  /// Relationship rails for Discover, from the same counts. Empty until
  /// there is a library worth threading -- and absent, not stubbed.
  List<ThreadRail> _threads = const [];

  /// The track the radio feeder last saw, and where it was. When the identity
  /// flips, the previous entry is settled as heard-to-the-end or abandoned.
  ManifestTrack? _radioPrev;
  Duration _radioPrevPos = Duration.zero;
  Duration _radioPrevDur = Duration.zero;

  bool _wasOffline = false;

  /// The library is asked about again on this beat while the app is on screen.
  /// The edge keeps the manifest for only a minute, so a few minutes is
  /// cheap, and new music turns up without anyone having to pull to refresh.
  /// /changes answers first, so most beats are one small request.
  static const _refreshEvery = Duration(minutes: 3);
  Timer? _refreshTimer;
  bool _foreground = true;

  /// Lyrics a listener adds go to the daemon and from there to everyone.
  late final LyricSharing _lyricSharing = LyricSharing(
    store: widget.manifestStore,
    put: widget.client.putLyrics,
    onChanged: () => unawaited(_refreshPlayerTracks()),
  );

  /// Puts what the store now says about every queued track in front of the
  /// screens that read the player. The queue keeps the copy it was given, so
  /// without this a saved lyric, or one the daemon sent, was invisible on Now
  /// Playing and in the lyrics sheet until the app was closed and reopened.
  Future<void> _refreshPlayerTracks() async {
    final shas = {for (final t in widget.player.queue) t.sha};
    if (shas.isEmpty) return;
    final fresh = <String, ManifestTrack>{};
    for (final sha in shas) {
      try {
        fresh[sha] = await widget.manifestStore.trackBySha(sha);
      } catch (_) {
        // Not in the store (dropped from the library): keep what is queued.
      }
    }
    if (mounted) widget.player.refreshTracks(fresh);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nav.addListener(_onNavChanged);
    // The screens below still take a Set<String> of in-flight shas; keep it in
    // step with the manager rather than re-plumbing six widgets.
    _downloads.addListener(_onDownloadsChanged);
    _wasOffline = widget.reachability.offline;
    widget.reachability.addListener(_onReachability);
    widget.accountSync?.onChanged = _onAccountSynced;
    FocusManager.instance.addListener(_regainFocus);
    _refreshTimer = Timer.periodic(_refreshEvery, (_) {
      if (_foreground && mounted) _reload();
    });
    _local.addListener(_trackRecents);
    _local.addListener(_feedRadio);
    widget.player.onQueueEnded = _pickRadio;
    // Recents used to live only in memory, so closing the app forgot what you
    // had been listening to. They come from the recorded history now.
    widget.history.addListener(_onHistoryChanged);
    _onHistoryChanged();
    // Hydrate from the store before kicking off a sync, so the sync's
    // setState doesn't race against a stale in-memory snapshot.
    _bootstrap();
    // After the first frame, so there is a screen under it to come back to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew());
  }

  /// The first time a release opens, say what is new in it. Once per pack: it is
  /// recorded as soon as it is shown, so being interrupted does not bring it
  /// back, and Settings can open it again whenever.
  void _maybeShowWhatsNew() {
    if (!mounted) return;
    if (widget.settings.whatsNewSeen == kWhatsNewId) return;
    unawaited(widget.settings.setWhatsNewSeen(kWhatsNewId));
    _openWhatsNew();
  }

  void _openWhatsNew() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (page) => WhatsNewPage(onDone: () => Navigator.of(page).pop()),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_regainFocus);
    _keys.dispose();
    if (widget.accountSync?.onChanged == _onAccountSynced) {
      widget.accountSync?.onChanged = null;
    }
    widget.reachability.removeListener(_onReachability);
    _local.removeListener(_trackRecents);
    _refreshTimer?.cancel();
    _local.removeListener(_feedRadio);
    widget.player.onQueueEnded = null;
    widget.history.removeListener(_onHistoryChanged);
    _nav.removeListener(_onNavChanged);
    _nav.dispose();
    // Only the listener: the manager itself belongs to TunesApp, which
    // outlives this shell.
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  /// Persists the exact resume point: which track, and where in it.
  ///
  /// Awaited -- every write here must commit before the caller lets the
  /// process die. The settings writes look instant (cache first) but commit
  /// to disk asynchronously; an unawaited save followed by an immediate
  /// close loses the resume point to the kill, which reads exactly like
  /// "resume doesn't store".
  Future<void> _persistResume() async {
    // Settle the listen in progress. Leaving mid-track is ordinary, and an
    // unsettled listen is one that never happened.
    widget.history.flush();
    // Pin the exact resume point. The player listener persists the position
    // every five seconds, so without this a close could lose most of a
    // track's progress -- and the sha, if the track changed within the gap.
    final current = _local.current;
    await widget.settings.setLastPlayedSha(current?.sha);
    // Not a zero from a stopped player: backing out halts the player, the
    // engine then reports 0:00, and the lifecycle change that follows used to
    // write that over the place just saved (see PositionSaver).
    final position = _local.position;
    if (_local.playing || position > Duration.zero) {
      await widget.settings.setLastPosition(position);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    widget.accountSync?.setForeground(_foreground);
    // Always on coming back, offline or not: a sync that succeeds is also how
    // an app that thinks it is offline finds out it is not.
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
    if (state == AppLifecycleState.paused) {
      unawaited(_persistResume());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadMixes());
    }
  }

  /// Newest first, and only tracks still in the library -- history outlives
  /// the files it refers to, and a recent play of something since removed is
  /// not something to put on the home screen.
  Future<void> _loadRecents() async {
    final shas = await widget.history.recentShas();
    if (!mounted) return;
    final manifest = _manifest;
    if (manifest == null) return;
    final bySha = {for (final t in manifest.tracks) t.sha: t};
    final tracks = [
      for (final sha in shas)
        if (bySha[sha] case final ManifestTrack t) t,
    ];
    if (tracks.isEmpty) return;
    setState(() => _recents = tracks);
  }

  /// A listen finished. Both the recents rail and the discover ranking read
  /// from history, and they are refreshed together so the two views can never
  /// disagree about what was played.
  Future<void> _onHistoryChanged() async {
    await _loadRecents();
    await _loadPlays();
    await _loadDerivedRails();
  }

  /// The sections the app assembles from listening rather than from choice.
  ///
  /// Resolved against the current manifest and dropped if the track has left
  /// the library, so a rail never offers something that cannot be played.
  Future<void> _loadDerivedRails() async {
    final top = await widget.history.topShas();
    // Kept apart from what is on repeat: the two are about different stretches
    // of time and must never offer the same song.
    final again = await widget.history.listenAgainShas(exclude: top.toSet());
    if (!mounted) return;
    final manifest = _manifest;
    if (manifest == null) return;
    final bySha = {for (final t in manifest.tracks) t.sha: t};
    List<ManifestTrack> resolve(List<String> shas) => [
      for (final sha in shas)
        if (bySha[sha] case final ManifestTrack t) t,
    ];
    setState(() {
      _onRepeat = resolve(top);
      _listenAgain = resolve(again);
    });
    await _loadMixes();
  }

  /// Playlists built from how you listen, and records you never opened.
  ///
  /// Rebuilt when a listen finishes, after a sync, and when the app comes back to
  /// the front (an hour passing is what brings Late Night in, with no play to
  /// signal it). Cheap: a thousand tracks and the history's finished plays.
  Future<void> _loadMixes() async {
    final manifest = _manifest;
    if (manifest == null || !mounted) return;
    final stamps = await widget.history.playStamps();
    if (!mounted) return;
    final liked = LikesScope.maybeOf(context)?.shas.toSet() ?? const <String>{};
    final inputs = MixInputs(
      tracks: manifest.tracks,
      artists: manifest.artists,
      releases: manifest.releases,
      stamps: stamps,
      liked: liked,
      now: DateTime.now(),
    );
    setState(() {
      _mixes = buildMixes(inputs);
      _unheard = unheardAlbums(inputs);
    });
  }

  void _openMix(Mix mix) {
    final tag = mix.tracks.isEmpty ? '' : mix.tracks.first.sha.substring(0, 6);
    _nav.openPanel(
      TunesPanels.mix('${mix.id}-${mix.tracks.length}-$tag'),
      () => MixPage(
        mix: mix,
        player: widget.player,
        artUrlFor: _artUrlFor,
        playlists: PlaylistScope.maybeOf(context),
      ),
    );
  }

  /// Folds the play counters into a per-act tally for the discover ranking.
  ///
  /// Recomputed on the same signal as recents rather than on a timer: the
  /// only thing that changes it is a listen finishing, which is exactly when
  /// the history notifies.
  Future<void> _loadPlays() async {
    final counts = await widget.history.playCounts();
    if (!mounted) return;
    final skips = await widget.history.skipCounts();
    if (!mounted) return;
    // A year of plays, faded by age, for what the radio thinks is loved now;
    // the last week of it for what is worn out.
    final year = await widget.history.playStamps(
      within: const Duration(days: 365),
    );
    if (!mounted) return;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final week = [
      for (final p in year)
        if (p.at.isAfter(weekAgo)) p,
    ];
    final manifest = _manifest;
    if (manifest == null) return;
    final plays = playsByArtist(counts, manifest.tracks);
    final tags = {
      for (final a in manifest.artists)
        if (a.tags.isNotEmpty) a.name.toLowerCase(): a.tags,
    };
    final recentPlays = <String, int>{};
    for (final p in week) {
      recentPlays[p.sha] = (recentPlays[p.sha] ?? 0) + 1;
    }
    setState(() {
      _playsByArtist = plays;
      _taste = TasteSnapshot.build(
        playCounts: counts,
        skipCounts: skips,
        // What the radio knows of genre: the box's clean genres where it
        // sent them, the crowd tags otherwise, so it can stay in the kind of
        // music being played and knows what is next door.
        artistTags: tags,
        artistGenres: {
          for (final a in manifest.artists)
            if (a.genres.isNotEmpty) a.name.toLowerCase(): a.genres,
        },
        affinity: TasteSnapshot.fadedAffinity([
          for (final p in year) (sha: p.sha, at: p.at),
        ], now: DateTime.now()),
        recentPlays: recentPlays,
      );
      _threads = followThreads(library: manifest.tracks, plays: counts);
    });
  }

  void _onReachability() {
    final offline = widget.reachability.offline;
    if (_wasOffline && !offline) {
      _reload();
    }
    // Pages already visited were built from the library as it was: offline that
    // is only what is downloaded. Forget them, so the next visit is built fresh.
    if (_wasOffline != offline) _nav.forgetUnused();
    _wasOffline = offline;
  }

  void _trackRecents() {
    final current = _local.current;
    if (_local.playing && current != null) {
      final next = [
        current,
        ..._recents.where((t) => t.sha != current.sha),
      ].take(10).toList();
      if (next.length != _recents.length ||
          next.first.sha != (_recents.isEmpty ? '' : _recents.first.sha)) {
        setState(() => _recents = next);
      }
    }
  }

  /// Settles the previous track into the radio session as heard or abandoned.
  ///
  /// Heard-to-the-end means the position had reached the track's tail when the
  /// identity flipped -- which covers both playing through and skipping past
  /// the last seconds. Anything else is a skip, the strongest signal the
  /// listener gives without typing anything. Repeat-one restarts never flip
  /// the identity, so replaying one track on loop does not count as playing
  /// it a dozen times.
  void _feedRadio() {
    final player = _local;
    final current = player.current;
    if (current?.sha != _radioPrev?.sha) {
      final prev = _radioPrev;
      if (prev != null) {
        final dur = _radioPrevDur;
        final heard =
            dur > Duration.zero &&
            _radioPrevPos >= dur - const Duration(seconds: 5);
        if (heard) {
          _radioSession.completed(prev);
        } else {
          _radioSession.skipped(prev);
        }
      }
      _radioPrev = current;
      _radioPrevPos = Duration.zero;
      _radioPrevDur = Duration.zero;
    }
    if (current != null) {
      _radioPrevPos = player.position;
      final decoder = player.duration;
      if (decoder > Duration.zero) {
        _radioPrevDur = decoder;
      } else if (current.durationMs != null) {
        _radioPrevDur = Duration(milliseconds: current.durationMs!);
      }
    }
  }

  /// The player's continuation hook: what follows the track that just ended.
  ///
  /// Null ends the queue in silence -- the setting is off, there is no
  /// library yet, or nothing is eligible. Offline the library is filtered to
  /// what is downloaded, so radio never offers a track that cannot play.
  Future<ManifestTrack?> _pickRadio(ManifestTrack seed) async {
    if (!widget.settings.radioAutoplay) return null;
    final manifest = _manifest;
    if (manifest == null || manifest.tracks.isEmpty) return null;
    final library = widget.reachability.offline
        ? manifest.tracks
              .where((t) => widget.store.pathFor(t.sha) != null)
              .toList()
        : manifest.tracks;
    if (library.isEmpty) return null;
    _radioSession.useMode(widget.settings.radioMode);
    return _radioEngine.next(
      library: library,
      session: _radioSession,
      taste: _taste,
      current: seed,
    );
  }

  /// Another device changed something that shapes the library (a corrected
  /// title or artist): re-read it from the store, and refresh what is queued.
  /// Likes and playlists announce themselves and need nothing here.
  void _onAccountSynced(Set<SyncDomain> changed) {
    if (!changed.any((d) => d is EditsDomain)) return;
    unawaited(() async {
      final fresh = await _manifestFromStore();
      if (!mounted) return;
      setState(() => _manifest = fresh);
      unawaited(_refreshPlayerTracks());
    }());
  }

  Future<void> _hydrateFromStore() async {
    try {
      final manifest = await _manifestFromStore();
      if (mounted) setState(() => _manifest = manifest);
      await _restoreQueue(manifest);
    } catch (_) {
      // cold start with empty db is fine; _sync will fill it.
    }
  }

  // --- updates -------------------------------------------------------------

  AvailableUpdate? _update;
  bool _updateDismissed = false;
  bool _needsInstallPermission = false;
  double? _updateProgress;
  late final UpdateInstaller _installer = UpdateInstaller(
    // Must sit under the path res/xml/update_paths.xml exposes, or the
    // installer is handed a URI the FileProvider refuses to resolve.
    cacheDir: Directory('${widget.store.dir.path}/updates'),
  );

  /// Asks the daemon whether a newer build exists.
  ///
  /// The daemon answers, not GitHub: the repository is private and a token
  /// inside an APK is a token anyone can read out of it.
  ///
  /// Never throws and never blocks anything: an app that fails to start
  /// because it could not check for updates has its priorities backwards.
  Future<void> _checkForUpdate() async {
    // APK self-update is Android-only. The Linux bundle is delivered by CI
    // artifacts, and offering an APK download there would be a dead button
    // behind a permission prompt that can never be granted.
    if (!Platform.isAndroid) return;
    try {
      final available = await widget.client.fetchUpdate();
      if (!mounted) return;
      if (!shouldOfferUpdate(_buildNumber, available)) return;
      final canInstall = await _installer.canInstall();
      if (!mounted) return;
      setState(() {
        _update = available;
        // Asked before offering the download rather than after: the permission
        // is grantable only from Settings on Android 8+, and discovering that
        // after 100 MB is the wrong order.
        _needsInstallPermission = !canInstall;
      });
    } catch (_) {
      // No update is the correct answer when the question could not be asked.
    }
  }

  Future<void> _startUpdate() async {
    final update = _update;
    if (update == null) return;
    try {
      await _installer.downloadAndInstall(
        widget.client.updateApkUrl,
        update.build,
        onProgress: (p) {
          if (mounted) setState(() => _updateProgress = p);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _updateProgress = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Update download failed')));
    }
  }

  /// Whether the saved queue has already been put back. Once only: after this,
  /// the queue in the player is the live one, and re-reading the database would
  /// overwrite whatever the listener has since chosen.
  bool _queueRestored = false;

  /// Set when restore threw, so the UI can say so once instead of failing
  /// silently. A resume that fails invisibly reads as "resume doesn't work"
  /// with no way to tell a store failure from a restore crash.
  bool _restoreFailed = false;

  /// Puts back what was playing when the app was last closed.
  ///
  /// The queue was already being written on every play and never read, so
  /// closing the app lost the listener's place entirely — and with no current
  /// track there is no mini-player, so the app came back looking like nothing
  /// had ever been played.
  ///
  /// Runs after the manifest because a stored queue is a list of shas and
  /// nothing else; the titles and artwork come from the library. Restored
  /// paused, never playing: an app that starts making noise because it was
  /// opened is worse than one that forgets.
  Future<void> _restoreQueue(TunesManifest manifest) async {
    if (_queueRestored) return;
    // Something is already playing -- the app was reopened rather than
    // restarted, or playback began before the manifest landed. Leave it.
    if (_local.current != null) {
      _queueRestored = true;
      return;
    }
    try {
      // load() already resolves each sha against the library, applies user
      // edits, orders by position and drops anything the library no longer
      // has — so there is nothing to re-derive here.
      final saved = await widget.queueStore.load();
      final tracks = [for (final item in saved) item.track];
      if (tracks.isEmpty) return;
      _queueRestored = true;
      final index = restoreIndexFor(tracks, widget.settings.lastPlayedSha);
      _local.restoreQueue(
        tracks,
        index,
        // Only resume mid-track when that is genuinely useful: not eight
        // seconds in, and not in the outro of something already finished.
        at: resumePosition(
          widget.settings.lastPosition,
          tracks[index].durationMs == null
              ? null
              : Duration(milliseconds: tracks[index].durationMs!),
        ),
      );
    } catch (e) {
      // A queue that cannot be restored is not worth failing a launch over --
      // but it is worth one honest line and one notice, so a broken restore
      // reads as broken rather than as forgotten.
      DiagLog.log('restore failed: $e');
      if (mounted) setState(() => _restoreFailed = true);
    }
  }

  Future<void> _bootstrap() async {
    // Warmed first and never awaited. Everything below needs a token
    // eventually, and minting it lazily puts a round trip in front of
    // whichever request happens to be first -- usually the one the listener
    // is waiting on.
    unawaited(widget.auth.accessToken());
    await _hydrateFromStore();
    if (mounted) await _sync();
    // Last, and not awaited by anything. The library is what the app is for;
    // an update notice is worth exactly as much attention as is left over.
    if (mounted) unawaited(_checkForUpdate());
  }

  Future<TunesManifest> _manifestFromStore() async {
    final tracks = await widget.manifestStore.allTracksNewestFirst();
    final releases = await widget.manifestStore.allReleases();
    final artists = await widget.manifestStore.allArtists();
    widget.library?.update(tracks);
    return TunesManifest(tracks: tracks, releases: releases, artists: artists);
  }

  /// When the sync in flight began, so one that never comes back can be told
  /// from one that is merely slow.
  DateTime? _syncStartedAt;

  /// A sync was asked for while another was running (the connection came
  /// back during the offline attempt). Run once more when this one ends.
  bool _syncAgain = false;

  static const _syncPatience = Duration(seconds: 75);

  /// One sync at a time, but never a stuck one.
  ///
  /// `_syncing` is the only thing that stops a second sync, so a first that
  /// hangs -- a socket that died with the phone's network switch -- used to
  /// block every later one, including the one the reconnect triggers: the app
  /// stayed on stale content until it was closed and reopened. Now a sync has a
  /// deadline, always lets go of the flag, and a request made while one runs is
  /// remembered instead of dropped.
  Future<void> _sync() async {
    final started = _syncStartedAt;
    if (_syncing) {
      final stuck =
          started != null && DateTime.now().difference(started) > _syncPatience;
      if (!stuck) {
        _syncAgain = true;
        return;
      }
    }
    _syncStartedAt = DateTime.now();
    try {
      await _syncOnce().timeout(_syncPatience);
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _lastSyncError ??= TimeoutException('sync took too long');
        });
      }
    } finally {
      _syncStartedAt = null;
    }
    if (_syncAgain && mounted) {
      _syncAgain = false;
      unawaited(_sync());
    }
  }

  Future<void> _syncOnce() async {
    if (!mounted) return;
    setState(() {
      _syncing = true;
      _lastSyncError = null;
    });
    // True iff the local store is now in sync with the daemon. Only
    // advance the watermark when this is true — otherwise a transient
    // error could mask new tracks behind a stale timestamp.
    var synced = false;
    // The build time and the track timestamps the applied manifest actually
    // carried. The watermark is derived from those rather than from the clock:
    // the clock would claim this phone holds tracks that a stale manifest
    // never contained, and those tracks would then never be named again
    // (domain/sync_watermark).
    DateTime? appliedGeneratedAt;
    final appliedAddedAts = <DateTime?>[];
    // Try the delta endpoint first. If the daemon says nothing has
    // changed since our last sync, skip the full manifest download
    // entirely. Falls through to /manifest on any error.
    var needFull = true;
    var lastSync = _lastSyncAt;
    if (lastSync != null) {
      try {
        final changes = await widget.client.fetchChanges(lastSync);
        // New lyrics add no track, so they are asked about separately: a
        // phone that only checked for added tracks would never see them.
        final now = DateTime.now();
        final drifted =
            _syncedIntegrity != null && changes.integrity != _syncedIntegrity;
        final mayRefetch =
            _integrityRefetchAt == null ||
            now.difference(_integrityRefetchAt!) > const Duration(minutes: 5);
        final same = !drifted || !mayRefetch;
        if (drifted &&
            mayRefetch &&
            changes.addedShas.isEmpty &&
            changes.lyricsChanged.isEmpty) {
          _integrityRefetchAt = now;
        }
        if (changes.addedShas.isEmpty &&
            changes.lyricsChanged.isEmpty &&
            same) {
          needFull = false;
          widget.reachability.ok();
          synced = true;
        }
      } catch (_) {
        // Any /changes failure → fall through to /manifest.
      }
    }
    if (needFull) {
      TunesManifest? raw;
      Object? fetchError;
      try {
        raw = await widget.client.fetchManifest(fromCacheOnFailure: false);
        widget.reachability.ok();
      } catch (e) {
        fetchError = e;
        widget.reachability.failed();
      }
      if (raw != null && mounted) {
        var applyOk = false;
        try {
          await widget.manifestStore.apply(raw);
          applyOk = true;
          if (raw.pointers.isNotEmpty) {
            // Likes kept under a copy that stopped being listed were moved
            // onto the listed copy; read them again, which also tells account
            // sync, so the account learns the new sha rather than handing the
            // old one back on the next pull.
            final likes = mounted
                ? context.getInheritedWidgetOfExactType<LikesScope>()?.notifier
                : null;
            await likes?.load();
            widget.accountSync?.poke();
          }
          _syncedIntegrity = raw.integrity;
        } catch (e) {
          if (mounted) setState(() => _lastSyncError = e);
        }
        if (mounted && applyOk) {
          appliedGeneratedAt = raw.generatedAt;
          appliedAddedAts
            ..clear()
            ..addAll(raw.tracks.map((t) => t.addedAt));
          final fresh = await _manifestFromStore();
          if (mounted) setState(() => _manifest = fresh);
          unawaited(_refreshPlayerTracks());
          // The first load happens before the manifest exists, so recents
          // cannot resolve their tracks until now.
          unawaited(_onHistoryChanged());
          synced = true;
        }
      } else if (fetchError != null && mounted) {
        setState(() => _lastSyncError = fetchError);
      }
    }
    if (mounted) {
      setState(() {
        if (synced) {
          _lastSyncAt = watermarkAfterApply(
            current: _lastSyncAt,
            generatedAt: appliedGeneratedAt,
            addedAts: appliedAddedAts,
          );
        }
        _syncing = false;
      });
    }
    // Not awaited: this is a suggestion rail, and the library must not wait
    // on it. Only refreshed after a real sync, since the answer changes only
    // when what we hold changes.
    if (mounted && synced) unawaited(_loadMissing());
    // The daemon's lyrics are fresh now: drop what it has caught up with and
    // send what it has not seen.
    if (mounted && synced) unawaited(_lyricSharing.reconcile());

    // Grants are minted here, off the critical path, rather than when the play
    // button is pressed.
    //
    // prepareQueue awaits a mint before the player opens, so a cold first play
    // cost a token round trip plus a grant round trip -- measured at ~1.5s
    // and ~1.0s over the real hostname, before mpv had asked for a byte.
    // Priming during sync makes prepareQueue find everything cached and return
    // without touching the network.
    //
    // Deliberately after BOTH sync paths rather than inside the full-manifest
    // branch: /changes short-circuits when nothing was added, which is the
    // common case on a warm launch, and priming only on the rare path would
    // have left exactly the launches people notice paying the full cost.
    final current = _manifest;
    if (mounted && synced && current != null) {
      unawaited(_primeGrants(current));
      unawaited(_saveCovers(current));
    }
  }

  /// Keeps every cover on the phone, so the library looks the same on a train
  /// as it does at home. Runs after a real sync, which is when the server is
  /// known to be reachable, and goes through the authenticated client rather
  /// than signed URLs, which expire during a long session.
  Future<void> _saveCovers(TunesManifest manifest) async {
    final shas = <String>{
      for (final t in manifest.tracks)
        if (t.artSha != null) t.artSha!,
      for (final a in manifest.artists)
        if (a.artSha != null) a.artSha!,
    };
    await widget.artStore.prefetch(shas);
  }

  /// Mints artwork grants for everything the library can show.
  ///
  /// Not awaited by the sync: a cover that arrives a moment late shows a
  /// placeholder and then resolves, whereas blocking the library on it would
  /// trade a visible screen for a spinner.
  Future<void> _primeGrants(TunesManifest manifest) async {
    final paths = grantPathsFor(manifest, widget.store.pathFor);
    if (paths.isEmpty) return;
    try {
      await widget.grants.prime(paths);
      if (mounted) setState(() {});
    } catch (_) {
      // Best effort. Anything missed is minted on demand by prepareQueue, at
      // the cost of the latency this exists to avoid -- never of playback.
    }
  }

  Future<void> _loadMissing() async {
    try {
      // The daemon caps at 200. The home rail only shows a handful, but the
      // discover screen counts what it was given and says so out loud -- a
      // default of forty made it report "40 releases by 4 artists" for a
      // library with fifty-four by six.
      final albums = await widget.client.missing(limit: 200);
      if (mounted) setState(() => _missingAlbums = albums);
      unawaited(
        widget.artStore.prefetch([
          for (final a in albums)
            if (a.artSha != null) a.artSha!,
        ]),
      );
    } catch (_) {
      // An older daemon answers 404 here, and offline answers nothing. Both
      // mean "cannot say", so leave whatever we last knew on screen rather
      // than blanking a section that was correct a minute ago.
    }
  }

  void _reload() {
    _sync();
  }

  /// The library in one line.
  ///
  /// Artists are counted the way the library screen groups them -- by act,
  /// with guests counted as their own entry -- so the header and the artist
  /// list never disagree about how many there are.
  static String _libraryLine(TunesManifest m) {
    final acts = <String>{};
    for (final track in m.tracks) {
      acts.add(track.artistKey);
      acts.addAll(track.featured.where((g) => g != track.artistKey));
    }
    final t = m.tracks.length;
    final a = acts.length;
    final r = m.releases.length;
    return '$t ${t == 1 ? 'track' : 'tracks'} · '
        '$a ${a == 1 ? 'artist' : 'artists'} · '
        '$r ${r == 1 ? 'release' : 'releases'}';
  }

  /// Pull to refresh. Awaits the sync so the indicator stays until the work
  /// is actually done.
  ///
  /// A failure keeps whatever is on screen and says so quietly. Blanking a
  /// feed that was correct a moment ago is a worse outcome than a stale one,
  /// and a refresh that succeeded needs no announcement at all.
  Future<void> _refresh() async {
    await _sync();
    if (!mounted) return;
    if (_lastSyncError != null && _manifest != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't refresh"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    final active = _downloads.jobs.entries
        .where((e) => e.value.phase != DownloadPhase.failed)
        .map((e) => e.key)
        .toSet();
    // Progress fires per chunk — roughly 300 times for a 20 MB track. Only the
    // membership of this set matters to the screens below, so rebuild the shell
    // when a download starts or stops, never on every chunk. The rows that show
    // progress rebuild through DownloadScope instead.
    if (active.length == _downloading.length &&
        active.every(_downloading.contains)) {
      return;
    }
    setState(() {
      _downloading
        ..clear()
        ..addAll(active);
    });
  }

  /// Hands the track to the queue. The transfer used to run inline here with
  /// no progress callback and no way to stop it.
  Future<void> _download(ManifestTrack track) async {
    _downloads.enqueue(track.sha, artSha: track.artSha);
  }

  String _artUrlFor(String sha) {
    final signed = widget.grants.urlFor('/art/$sha');
    return '${widget.client.baseUrl}${signed ?? '/art/$sha'}';
  }

  /// The header avatar now goes straight to settings. The old sheet was a
  /// read-only diagnostics panel, and its contents live under Library there.
  void _openProfile(int trackCount) {
    _nav.openPanel(
      TunesPanels.settings,
      () => SettingsPage(
        accountSync: widget.accountSync,
        settings: widget.settings,
        auth: widget.auth,
        onWhatsNew: _openWhatsNew,
        player: widget.player,
        endpoint: widget.client.baseUrl,
        offline: widget.reachability.offline,
        commit: _gitCommit,
        buildNumber: _buildNumber,
        channel: _channel,
        trackCount: trackCount,
        downloadCount: widget.store.shas.length,
        store: widget.store,
        history: widget.history,
        library: {
          for (final t in _manifest?.tracks ?? const <ManifestTrack>[])
            t.sha: t,
        },
        artUrlFor: _artUrlFor,
        supportDir: widget.store.dir,
        onResync: _reload,
        onServerChanged: (url) async {
          await widget.settings.setServerUrl(url);
          // Repoint the live client rather than asking for a restart. Every
          // request builds its URL from baseUrl at call time, so the next
          // one already goes to the new address.
          widget.client.baseUrl = widget.settings.serverUrl ?? _tunesdUrl;
          // What is on screen still came from the old server, so fetch the
          // library again instead of leaving a stale one that looks current.
          _reload();
        },
      ),
    );
  }

  void _openArtist(String artist, TunesManifest manifest) {
    _nav.openPanel(
      TunesPanels.artist(artist),
      () => ArtistPage(
        artist: artist,
        manifest: manifest,
        client: widget.client,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: widget.reachability.offline,
        artUrlFor: _artUrlFor,
        manifestStore: widget.manifestStore,
        queueStore: widget.queueStore,
      ),
    );
  }

  void _openAlbum(ManifestRelease release, TunesManifest manifest) {
    _nav.openPanel(
      TunesPanels.album(release.id),
      () => AlbumPage(
        release: release,
        manifest: manifest,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: widget.reachability.offline,
        artUrlFor: _artUrlFor,
        manifestStore: widget.manifestStore,
        queueStore: widget.queueStore,
      ),
    );
  }

  void _openNowPlaying() {
    _nav.openPanel(
      TunesPanels.nowPlaying,
      () => NowPlayingPage(
        player: widget.player,
        manifest: _manifest ?? const TunesManifest(tracks: [], releases: []),
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: widget.reachability.offline,
        artUrlFor: _artUrlFor,
        manifestStore: widget.manifestStore,
        queueStore: widget.queueStore,
        shareLyrics: _lyricSharing.save,
      ),
    );
  }

  Widget _buildUnreachableState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: Tones.textMuted, size: 40),
            const SizedBox(height: Space.md),
            Text('No library yet', style: TypeScale.title),
            const SizedBox(height: Space.sm),
            Text(
              // The server actually being asked. Naming the compiled-in one
              // sent anybody who had changed it looking at the wrong machine.
              'tunesd is not answering at ${widget.client.baseUrl}.\n'
              'Start the daemon on the box, then refresh.',
              textAlign: TextAlign.center,
              style: TypeScale.body,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'debug: ${_lastSyncError.runtimeType}\n$_lastSyncError',
              textAlign: TextAlign.center,
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The scope lives in TunesApp, above the Navigator. Re-publishing it here
    // would cover this shell only, which is the bug that was.
    return _buildShell(context);
  }

  Widget _buildShell(BuildContext context) {
    if (_restoreFailed) {
      // Consumed, not setState: the notice is the only output, and it fires
      // once via the post-frame callback below.
      _restoreFailed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't pick up where you left off"),
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
    // Backing out of the last screen means leaving the app, and leaving should
    // behave the same way whether you backed out or swiped it away.
    //
    // It did not. stopOnTaskRemoved covers the swipe only, so Back left the
    // audio_service foreground service running: the process stayed alive with
    // mpv still playing while the Activity -- and with it the mini-player,
    // which is Activity UI -- was destroyed. Music playing, with no control
    // anywhere in the app.
    //
    // Reopening then built a fresh engine and ran main() again, so a SECOND
    // player was created beside the one still going. Confirmed on device: two
    // AudioPlaybackConfigurations in one process, piid:10239 started and
    // piid:10247 stopped. The stopped one is what the mini-player showed,
    // which is why the app came back paused while music kept playing.
    //
    // Inside the root route on purpose: a PopScope above the Navigator has no
    // enclosing route to register with and never fires.
    return PopScope(
      // canPop: false, and the exit is performed by hand below.
      //
      // The obvious version -- canPop: true and do the work in the callback --
      // does nothing, which was measured on device before this replaced it. At
      // the ROOT route Flutter never pops anything: there is no route beneath,
      // so the framework hands the back press to the platform and Android
      // finishes the Activity. No pop happens, so the callback never fires
      // with didPop true, and playback carried on exactly as before.
      //
      // Refusing the pop is what puts this code in the path at all. The exit
      // then has to be asked for explicitly.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // History first: Back walks the panel trail, and only the tab root
        // below it means leaving the app.
        if (_nav.back()) return;
        // Persist first, then halt, then leave: the resume writes must commit
        // before the process can die, or the close loses them to the kill.
        // Bounded: a wedged write must never trap Back.
        unawaited(
          _persistResume()
              .timeout(const Duration(seconds: 2), onTimeout: () {})
              .then((_) {
                // Halt, not stop: backing out of the app quiets it, but the queue and
                // the resume point survive so reopening lands back where it was.
                // Stopping here used to wipe the persisted queue with it.
                if (widget.settings.stopOnClose) widget.player.halt();
                // Leave regardless of the setting: refusing to pop is a mechanism for
                // getting here, not a decision about whether the app should close.
                // Swallowing it would trap someone who has turned stopOnClose off.
                SystemNavigator.pop();
              }),
        );
      },
      child: Listener(
        // A click outside a text box lets go of it. On a computer a box keeps
        // focus until something else asks for it, and while it has focus every
        // key is read as typing, so after one search the shortcuts were dead.
        onPointerDown: _releaseTextFocus,
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: LayoutBuilder(
            builder: (context, box) => isWideWindow(box.biggest)
                ? _buildWide(context)
                : _buildNarrow(),
          ),
        ),
      ),
    );
  }

  final FocusNode _keys = FocusNode(debugLabel: 'tunes-keys');

  /// Whether the focused thing is a text box.
  static bool _inTextBox(FocusNode? f) =>
      f?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  void _releaseTextFocus(PointerDownEvent event) {
    if (!_inTextBox(FocusManager.instance.primaryFocus)) return;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    final onBox = hit.path.any((e) => e.target is RenderEditable);
    if (!onBox) _keys.requestFocus();
  }

  /// Focus can be lost altogether (the box that had it was removed), after
  /// which no key reaches the shortcuts. Take it back.
  void _regainFocus() {
    if (!mounted) return;
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f is FocusScopeNode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_keys.hasFocus) _keys.requestFocus();
      });
    }
  }

  /// Keyboard control, on a computer: space plays and pauses, the arrows seek,
  /// ctrl+arrows skip, L likes, / searches, Esc goes back, and the media keys
  /// do what they say.
  ///
  /// Only for keys nothing else wanted: a focused button or text field sees
  /// them first, and while a text field has focus none of this runs, so typing
  /// a space into a search or a playlist name is never taken for "pause".
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!Device.isDesktop) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final keys = HardwareKeyboard.instance;
    return handleDesktopKey(
      event: event,
      player: widget.player,
      typing:
          focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null,
      ctrl: keys.isControlPressed || keys.isMetaPressed,
      alt: keys.isAltPressed,
      onLike: () {
        final sha = widget.player.current?.sha;
        if (sha != null) unawaited(LikesScope.maybeOf(context)?.toggle(sha));
      },
      onSearch: () => _onTabSelected(2),
      onBack: _nav.back,
    );
  }

  bool _wideNow(BuildContext context) =>
      isWideWindow(MediaQuery.sizeOf(context));

  Widget _buildNarrow() {
    return Scaffold(
      body: NavScope(controller: _nav, child: _buildBody()),
      // The player sits above the navigation rather than beside it: it is a
      // layer over the app, and the nav is the app's own furniture. The
      // separation is a hairline and a surface change, not a shadow -- this
      // interface has no other shadows and one would read as a mistake.
      //
      // On every page but the player. The mini bar and the tabs are one dock,
      // so the way out of an artist, an album or a playlist is always the
      // same: the tab you want, one tap. Pages used to cover it and each
      // supplied a mini bar of its own, some forgetting to, which is why it
      // was there on some screens and not on others. Now Playing is the one
      // exception: it is the layer over the app, lit by the record, and
      // carries its own controls.
      bottomNavigationBar:
          _nav.current == const PanelDest(TunesPanels.nowPlaying)
          ? null
          : _buildBottomNav(),
    );
  }

  /// Now Playing on a wide window: the player as on a phone on the left, and
  /// the lyrics open beside it on the right, where a phone would need a sheet.
  Widget _buildWideNowPlaying() {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.player, widget.settings]),
      builder: (context, _) {
        final track = widget.player.current;
        final showPane =
            track != null &&
            widget.settings.showLyrics &&
            (track.lyrics ?? '').trim().isNotEmpty;
        return _wideNowPlayingRow(track, showPane);
      },
    );
  }

  Widget _wideNowPlayingRow(ManifestTrack? track, bool showPane) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _buildBody(),
            ),
          ),
        ),
        // Lyrics beside the player only when there are lyrics to show and the
        // listener wants them; otherwise the player has the room to itself.
        if (showPane) ...[
          VerticalDivider(width: 1, color: Tones.hairline),
          Expanded(
            flex: 6,
            child: LyricsSheet(
              embedded: true,
              track: track!,
              player: widget.player,
              onSave: (saved, text) => _lyricSharing.save(saved.sha, text),
            ),
          ),
        ],
      ],
    );
  }

  /// The desktop layout: sidebar left, the page in the middle, the player
  /// across the bottom. The same pages as the phone, in a frame that suits a
  /// window; Now Playing sits in the middle column rather than covering all.
  Widget _buildWide(BuildContext context) {
    final onTab = _nav.current is! PanelDest;
    final count = _manifest?.tracks.length ?? 0;
    final tracks = [
      for (final t in _manifest?.tracks ?? const <ManifestTrack>[])
        if (!widget.reachability.offline || widget.store.pathFor(t.sha) != null)
          t,
    ];
    final current = _nav.current;
    final playingPage =
        current is PanelDest && current.id == TunesPanels.nowPlaying;
    final store = PlaylistScope.maybeOf(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                ListenableBuilder(
                  listenable: widget.settings,
                  builder: (context, _) => DesktopSidebar(
                    selectedTab: onTab ? _tab : null,
                    onTab: _onTabSelected,
                    playlists: store,
                    onPlaylist: (p) => _nav.openPanel(
                      TunesPanels.playlist(p.id),
                      () => PlaylistPage(
                        summary: p,
                        store: store!,
                        player: widget.player,
                        tracks: tracks,
                        artUrlFor: _artUrlFor,
                      ),
                    ),
                    onSettings: () => _openProfile(count),
                    name: widget.settings.displayName,
                    avatarPath: widget.settings.avatarPath,
                    activePlaylistId:
                        current is PanelDest &&
                            current.id.startsWith('tunes/playlist/')
                        ? int.tryParse(current.id.split('/').last)
                        : null,
                  ),
                ),
                Expanded(
                  child: NavScope(
                    controller: _nav,
                    // Now Playing is a phone-shaped page; centred and held to a
                    // comfortable width it reads as a panel rather than a
                    // stretched poster.
                    child: playingPage ? _buildWideNowPlaying() : _buildBody(),
                  ),
                ),
              ],
            ),
          ),
          DownloadsBar(
            manager: _downloads,
            onTap: () {
              final bySha = {
                for (final t in _manifest?.tracks ?? const <ManifestTrack>[])
                  t.sha: t,
              };
              DownloadsSheet.show(
                context,
                manager: _downloads,
                trackFor: (sha) => bySha[sha],
              );
            },
          ),
          DesktopPlayBar(
            player: widget.player,
            artUrlFor: _artUrlFor,
            volume: widget.settings.volume,
            onVolume: (v) => unawaited(widget.settings.setVolume(v)),
            onOpenNowPlaying: _openNowPlaying,
            onQueue: () => QueueSheet.show(
              context,
              queueStore: widget.queueStore,
              player: widget.player,
            ),
            statusBuilder: (context) => SourceTag(
              player: widget.player,
              held:
                  widget.player.current != null &&
                  widget.store.pathFor(widget.player.current!.sha) != null,
              offline: widget.reachability.offline,
              reachability: widget.reachability,
            ),
          ),
        ],
      ),
    );
  }

  /// What the Scaffold body shows: the history top. Tab roots render the
  /// header, feed and navigation chrome; panels paint full-screen.
  Widget _buildBody() {
    final current = _nav.current;
    if (current is PanelDest) {
      // Keyed by identity, so a revisit re-activates the same instance
      // rather than rebuilding it -- one pane per identity, always.
      return KeyedSubtree(
        key: ValueKey(current.id),
        child: _nav.instanceFor(current.id),
      );
    }
    return _buildTabRoot();
  }

  Widget _buildTabRoot() {
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.reachability,
        builder: (context, _) {
          final offline = widget.reachability.offline;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Above everything, and only when there is something to say.
              // A strip rather than a dialog: nobody opened a music app to
              // be told about software.
              if (_update != null && !_updateDismissed)
                UpdateBanner(
                  update: _update!,
                  progress: _updateProgress,
                  needsPermission: _needsInstallPermission,
                  onGrantPermission: () async {
                    await _installer.openInstallSettings();
                    // Re-checked on return rather than assumed: the person
                    // may have looked at the settings page and backed out.
                    final ok = await _installer.canInstall();
                    if (mounted) {
                      setState(() => _needsInstallPermission = !ok);
                    }
                  },
                  onInstall: _startUpdate,
                  onDismiss: () => setState(() => _updateDismissed = true),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.lg,
                  Space.lg,
                  0,
                ),
                child: Row(
                  children: [
                    // The sidebar has the profile on a wide window.
                    if (!_wideNow(context)) ...[
                      GestureDetector(
                        onTap: () {
                          final count = _manifest?.tracks.length ?? 0;
                          _openProfile(count);
                        },
                        // Listens to settings directly: choosing a picture in
                        // the screen this opens should change the thing you
                        // came back to, without a restart.
                        child: ListenableBuilder(
                          listenable: widget.settings,
                          builder: (context, _) => ProfileAvatar(
                            name: widget.settings.displayName,
                            path: widget.settings.avatarPath,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Home greets you; the other tabs keep the name over the
                          // door, so each still says where you are.
                          if (_tab == 0)
                            ListenableBuilder(
                              listenable: widget.settings,
                              // Shrinks rather than cuts off: Crayon's hand
                              // lettering is wider than the serif, and "Back
                              // for more, Dy..." is no greeting.
                              builder: (context, _) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  greetingFor(
                                    DateTime.now(),
                                    widget.settings.displayName,
                                    seed: _greetingSeed,
                                    voice: switch (Looks.current.kind) {
                                      LookKind.crayon => GreetingVoice.crayon,
                                      LookKind.noir => GreetingVoice.noir,
                                      LookKind.room => GreetingVoice.room,
                                    },
                                  ),
                                  style: TypeScale.wordmark.copyWith(
                                    fontSize: 28,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                          else
                            Text('tunes', style: TypeScale.wordmark),
                          // The library's size belongs to the wordmark, not
                          // to the feed. It used to scroll away with the
                          // first rail, which made it read as a caption on
                          // "Just added" rather than a description of the
                          // library.
                          //
                          // Home only: on Search or Discover it would be a
                          // number about somewhere else.
                          if (_tab == 0 && _manifest != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _libraryLine(_manifest!),
                                style: TypeScale.caption,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (offline) const OfflineNote(),
              Expanded(child: _buildContent(offline)),
            ],
          );
        },
      ),
    );
  }

  /// The mini-player over the tab bar: a layer over the app while the nav is
  /// its furniture. Tab roots only -- panels paint their own chrome.
  Widget _buildBottomNav() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tones.base,
        border: Border(top: BorderSide(color: Tones.hairline)),
      ),
      // Bottom only: the top edge of this bar is the app's own, and the
      // gesture strip is what would otherwise sit over the labels.
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DownloadsBar(
              manager: _downloads,
              onTap: () {
                final bySha = {
                  for (final t in _manifest?.tracks ?? const <ManifestTrack>[])
                    t.sha: t,
                };
                DownloadsSheet.show(
                  context,
                  manager: _downloads,
                  trackFor: (sha) => bySha[sha],
                );
              },
            ),
            MiniPlayerBar(
              player: widget.player,
              onTap: _openNowPlaying,
              artUrlFor: _artUrlFor,
            ),
            TunesNavBar(
              selectedIndex: _tab,
              onSelected: _onTabSelected,
              items: const [
                TunesNavItem(glyph: NavGlyph.home, label: 'Home'),
                TunesNavItem(glyph: NavGlyph.discover, label: 'Discover'),
                TunesNavItem(glyph: NavGlyph.search, label: 'Search'),
                TunesNavItem(glyph: NavGlyph.library, label: 'Library'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool offline) {
    if (_manifest == null) {
      if (_lastSyncError != null) {
        return _buildUnreachableState();
      }
      // Geometry, not a spinner: the skeleton is built to the same shape as
      // the feed, so the library replaces it without anything moving.
      return const HomeSkeleton();
    }
    if (_manifest!.tracks.isEmpty && _lastSyncError != null) {
      return _buildUnreachableState();
    }
    // Without a connection the library is what is on this phone. Everything
    // below, the lists and search and the pages opened from them, is built from
    // this, so nothing is offered that cannot be played and a search cannot come
    // back empty because the match was a song that was never downloaded.
    bool held(String sha) => widget.store.pathFor(sha) != null;
    final manifest = offline ? _manifest!.onlyHeld(held) : _manifest!;
    final tracks = manifest.tracks;
    List<ManifestTrack> playable(List<ManifestTrack> l) => offline
        ? [
            for (final t in l)
              if (held(t.sha)) t,
          ]
        : l;
    final content = switch (_tab) {
      1 => DiscoverView(
        gaps: offline
            ? const []
            : collectionGaps(missing: _missingAlbums, plays: _playsByArtist),
        threads: offline
            ? [
                for (final r in _threads)
                  if (playable(r.tracks).length >= 3)
                    ThreadRail(
                      act: r.act,
                      title: r.title,
                      subtitle: r.subtitle,
                      tracks: playable(r.tracks),
                    ),
              ]
            : _threads,
        offline: offline,
        artUrlFor: _artUrlFor,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        onPlay: (list, index) => widget.player.playQueue(list, index),
        hasHistory: _playsByArtist.isNotEmpty,
      ),
      2 => SearchView(
        tracks: tracks,
        releases: manifest.releases,
        client: widget.client,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: offline,
        artUrlFor: _artUrlFor,
        onAlbumTap: (release) => _openAlbum(release, manifest),
        onArtistTap: (artist) => _openArtist(artist, manifest),
      ),
      3 => LibraryView(
        tracks: tracks,
        releases: manifest.releases,
        artists: manifest.artists,
        filter: _libraryFilter,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: offline,
        artUrlFor: _artUrlFor,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        onAlbumTap: (release) => _openAlbum(release, manifest),
        queueStore: widget.queueStore,
        manifestStore: widget.manifestStore,
        recents: playable(_recents),
      ),
      _ => HomeView(
        aboveFeed: widget.remoteNow == null || widget.accountSync == null
            ? null
            : ContinueCard(
                remote: widget.remoteNow!,
                player: widget.player,
                manifest: manifest,
                serverNow: widget.accountSync!.serverNowMs,
                onContinue: (tracks, index, at) {
                  // Load it where it was, then play: the place is restored the
                  // way a relaunch restores it, so it resumes at the second.
                  widget.player.restoreQueue(tracks, index, at: at);
                  widget.player.play();
                },
              ),
        manifest: manifest,
        missingAlbums: offline ? const [] : _missingAlbums,
        onRefresh: _refresh,
        onRepeat: playable(_onRepeat),
        listenAgain: playable(_listenAgain),
        mixes: [
          for (final m in _mixes)
            if (playable(m.tracks).length >= 8)
              Mix(
                id: m.id,
                title: m.title,
                note: m.note,
                kind: m.kind,
                tracks: playable(m.tracks),
              ),
        ],
        unheard: offline
            ? [
                for (final u in _unheard)
                  if (u.release.trackShas.any(held)) u,
              ]
            : _unheard,
        onMixTap: _openMix,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        onAlbumTap: (release) => _openAlbum(release, manifest),
        onPlay: (list, index) {
          // Mirror is handled by the player's onQueuePlayed hook.
          widget.player.playQueue(list, index);
        },
        artUrlFor: _artUrlFor,
      ),
    };
    // Keyed by tab and by tap: re-tapping the active tab swaps the key (see
    // _onTabSelected), which remounts the scrollable back at the top.
    return KeyedSubtree(key: _tabKeys[_tab], child: content);
  }

  /// A tab tap either switches tabs, or -- when the tab is already active --
  /// goes back to its top: any pushed panels are dismissed and the feed
  /// remounts at offset zero. Tapping Home twice doing nothing was the
  /// complaint; every tab behaves the same way.
  void _onTabSelected(int i) {
    // The tab bar only answers at tab roots -- panels cover it -- but a tap
    // can still land with panels above (rotation, restoration), so drain
    // those first either way.
    if (i == _tab) {
      while (_nav.current is PanelDest) {
        _nav.back();
      }
      setState(() => _tabKeys[i] = UniqueKey());
      return;
    }
    _nav.selectTab(i);
    setState(() => _tab = i);
  }
}
