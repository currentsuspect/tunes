import '../../core/platform/device.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/art_store.dart';
import '../../core/data/download_store.dart';
import '../../core/data/play_history.dart';
import '../../core/data/storage_usage.dart';
import '../../core/platform/diag_log.dart';
import '../../core/data/avatar.dart';
import '../../core/auth/tunes_auth.dart';
import '../../core/data/settings_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/sync/account_sync.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/profile_avatar.dart';
import '../../domain/listening_stats.dart';
import '../../domain/manifest.dart';
import '../stats/listening_page.dart';
import '../updates/update_controller.dart';
import '../../domain/whats_new.dart';
import '../../core/theme/looks.dart';
import 'eq_sheet.dart';

/// Who you are and how the app behaves.
///
/// Every control here changes something real. A settings screen full of
/// switches that do nothing is worse than no settings screen, so anything
/// that would need work the app has not done yet is simply not listed.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.auth,
    required this.player,
    required this.endpoint,
    required this.offline,
    required this.commit,
    required this.buildNumber,
    required this.channel,
    required this.trackCount,
    required this.downloadCount,
    required this.store,
    required this.history,
    required this.onResync,
    required this.onServerChanged,
    this.onWhatsNew,
    this.updates,
    this.onUpdate,
    this.supportDir,
    this.accountSync,
    this.library = const {},
    this.artUrlFor,
    this.listeningLinks = const ListeningLinks(),
  });

  /// The library by sha, for the listening page's names and covers.
  final Map<String, ManifestTrack> library;
  final String Function(String sha)? artUrlFor;

  /// Where the names on "Your listening" go.
  final ListeningLinks listeningLinks;

  /// Account sync, when this build has an account. Absent in tests.
  final AccountSync? accountSync;

  /// Opens the What's new page again. Absent where there is nothing to open.
  final VoidCallback? onWhatsNew;

  final SettingsStore settings;

  /// Device identity. Enrolment is the only way the app gets a credential;
  /// nothing usable ships inside the APK.
  final TunesAuth auth;
  final TunePlayer player;
  final String endpoint;
  final bool offline;
  final String commit;
  final String buildNumber;

  /// Whether a newer build exists; null where the app cannot update itself
  /// (the computer). Shown as the Updates card.
  final UpdateController? updates;
  final VoidCallback? onUpdate;
  final String channel;
  final int trackCount;
  final int downloadCount;
  final DownloadStore store;
  final PlayHistory history;

  /// Re-fetches the library. Handed in rather than reached for, because the
  /// shell owns the sync and this screen only asks for one.
  final VoidCallback onResync;

  /// Persists the address, repoints the client, and refetches. Empty string
  /// means "clear it, use the compiled-in default".
  final Future<void> Function(String url) onServerChanged;
  final Directory? supportDir;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _name;
  final _avatars = AvatarStore();
  StorageUsage? _usage;
  ({int count, int bytes})? _covers;

  /// Seven taps on the build line. Hidden rather than absent: these controls
  /// are for whoever is debugging the app, and putting them in front of
  /// everyone else would be clutter that also invites damage.
  int _versionTaps = 0;
  bool _developer = false;

  /// Device id once enrolled, null when this device has no credential.
  /// Read once on open rather than watched: enrolment changes only when
  /// someone on this screen changes it.
  String? _deviceId;
  bool _enrolling = false;

  Future<void> _loadEnrolment() async {
    final id = await widget.auth.deviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  /// Redeems an invite code for this device.
  ///
  /// The three outcomes are reported differently on purpose. "Invalid" and
  /// "could not reach the server" are the same HTTP nothing from the user's
  /// side, and collapsing them is how you get someone retyping a perfectly
  /// good code at a server that is simply down.
  Future<void> _enrolDevice() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Tones.surface,
        title: Text('Invite code', style: TypeScale.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the code you were sent. It works once, on this device.',
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: TypeScale.body,
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Enrol'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;

    setState(() => _enrolling = true);
    // Named for the kind of device it is, because this is the name the other
    // devices show: "playing on Computer" has to mean something.
    final kind = Platform.isAndroid || Platform.isIOS ? 'phone' : 'computer';
    final name = widget.settings.displayName.trim();
    final label = name.isEmpty
        ? (kind == 'phone' ? 'Android device' : 'Computer')
        : "$name's $kind";
    final result = await widget.auth.enrol(code.trim(), label);
    if (!mounted) return;
    setState(() => _enrolling = false);
    await _loadEnrolment();
    if (!mounted) return;

    final message = switch (result) {
      AuthOk() => 'This device is enrolled',
      AuthNeedsEnrolment() =>
        'That code was not accepted. It may be used or expired.',
      AuthUnavailable() => 'Could not reach the server. The code was not used.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (result is AuthOk) widget.onResync();
  }

  /// Asks for the address of a tunesd, and hands it upward.
  ///
  /// Not behind the seven-tap developer section: pointing the app at your own
  /// server is the difference between this being usable by one person and
  /// usable by anyone, which is not a debugging concern.
  ///
  /// Empty means "go back to the address this build was compiled with", so
  /// there is always a way back from a typo without reinstalling.
  Future<void> _editServer() async {
    final controller = TextEditingController(text: widget.endpoint);
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Tones.surface,
        title: Text('Server', style: TypeScale.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where your tunesd is. Include the port.',
              style: TypeScale.caption,
            ),
            SizedBox(height: Space.sm),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: TypeScale.body,
              decoration: InputDecoration(
                hintText: 'http://100.100.235.90:4780',
              ),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            SizedBox(height: Space.sm),
            Text(
              'Leave it empty to go back to the address this build came with.',
              style: TypeScale.caption,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null) return;
    await widget.onServerChanged(entered);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      // The library on screen is still the old server's until something asks
      // again, so say that rather than letting it look like nothing happened.
      SnackBar(content: Text('Server changed — refetching the library')),
    );
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.displayName);
    _measure();
    _loadEnrolment();
  }

  /// The saved covers, found once the widget is in the tree rather than looked
  /// up by context after an await.
  ArtStore? _art;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _art = ArtScope.maybeOf(context);
  }

  Future<void> _measure() async {
    final usage = await StorageUsage.measure(
      store: widget.store,
      manifestPath: widget.supportDir == null
          ? null
          : '${widget.supportDir!.path}/manifest.json',
      logPath: DiagLog.path,
    );
    final covers = await _art?.usage();
    if (mounted) {
      setState(() {
        _usage = usage;
        _covers = covers;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final art = ArtScope.maybeOf(context);
    return Scaffold(
      backgroundColor: Tones.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.sm, 0),
                child: IconButton(
                  onPressed: () => NavScope.of(context).back(),
                  tooltip: 'Back',
                  icon: Icon(Icons.arrow_back_rounded, color: Tones.textMuted),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: s,
                builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
                  children: [
                    Text(
                      'Settings',
                      style: TypeScale.display.copyWith(fontSize: 34),
                    ),
                    SizedBox(height: Space.lg),
                    _Profile(
                      name: s.displayName,
                      path: s.avatarPath,
                      controller: _name,
                      onAvatar: _editAvatar,
                      onName: s.setDisplayName,
                    ),
                    SizedBox(height: Space.sm),
                    _ListeningCard(
                      history: widget.history,
                      library: widget.library,
                      artUrlFor: widget.artUrlFor,
                      links: widget.listeningLinks,
                    ),
                    if (widget.updates case final u?)
                      ListenableBuilder(
                        listenable: u,
                        builder: (context, _) => _Updates(
                          updates: u,
                          buildNumber: widget.buildNumber,
                          channel: widget.channel,
                          noteOnHome: s.updateNoteOnHome,
                          onNoteOnHome: s.setUpdateNoteOnHome,
                          onUpdate: widget.onUpdate ?? () {},
                          onWhatsNew: widget.onWhatsNew,
                        ),
                      ),
                    _Group(
                      title: 'Look',
                      children: [
                        _ThemePicker(
                          choice: s.themeChoice,
                          brightness: s.themeBrightness,
                          onChoice: s.setThemeChoice,
                        ),
                        if (s.themeChoice == 'auto') ...[
                          _LinkTile(
                            title: 'Noir from ${_clock(s.autoNightMinutes)}',
                            detail: 'When Auto turns to Noir for the night.',
                            onTap: () => _pickTime(
                              context,
                              s.autoNightMinutes,
                              s.setAutoNightMinutes,
                            ),
                          ),
                          _LinkTile(
                            title: 'Crayon from ${_clock(s.autoDayMinutes)}',
                            detail: 'When it comes back for the day.',
                            onTap: () => _pickTime(
                              context,
                              s.autoDayMinutes,
                              s.setAutoDayMinutes,
                            ),
                          ),
                        ],
                        _ChoiceTile(
                          title: 'Light or dark',
                          choices: const ['Phone', 'Dark', 'Light'],
                          selected: s.themeBrightness,
                          onChanged: s.setThemeBrightness,
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Listening',
                      children: [
                        _LinkTile(
                          title: 'Headphone EQ: ${s.eqProfile?.name ?? 'Off'}',
                          detail:
                              'Tune how your headphones sound, for everything '
                              'that plays here.',
                          onTap: () => showEqSheet(context, s),
                        ),
                        _SwitchTile(
                          title: 'Gapless playback',
                          detail:
                              'No silence between songs. It only works when two '
                              'files share a format.',
                          value: s.gapless,
                          onChanged: (v) async {
                            await s.setGapless(v);
                            await widget.player.setGapless(v);
                          },
                        ),
                        _SwitchTile(
                          title: 'Keep playing with radio',
                          detail:
                              'When the queue ends, pick what follows from your '
                              'own listening, on ${Device.thisOne}. Added after the '
                              'queue, never mixed into it.',
                          value: s.radioAutoplay,
                          onChanged: s.setRadioAutoplay,
                        ),
                        _ChoiceTile(
                          title: 'Double-tap a cover',
                          choices: ['Like', 'Download'],
                          selected: s.doubleTapDownloads ? 1 : 0,
                          onChanged: (i) => s.setDoubleTapDownloads(i == 1),
                        ),
                        _SwitchTile(
                          title: 'Stop when the app closes',
                          detail:
                              'Off, the music carries on after you swipe the app '
                              'away, with no controls on screen to stop it.',
                          value: s.stopOnClose,
                          onChanged: s.setStopOnClose,
                        ),
                        _SwitchTile(
                          title: 'Turning artwork',
                          detail:
                              'The sleeve turns slowly while a song plays. The '
                              'only thing in the app that moves all the time.',
                          value: s.animatedArtwork,
                          onChanged: s.setAnimatedArtwork,
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Storage',
                      children: [
                        _ChoiceTile(
                          title: 'Keep songs you hear',
                          choices: [
                            for (final gb in SettingsStore.cacheSizesGb)
                              '$gb GB',
                          ],
                          selected: s.cacheSize,
                          onChanged: s.setCacheSize,
                        ),
                        _ChoiceTile(
                          title: 'Fetch the next song early',
                          choices: const ['Off', 'Wi-Fi', 'Always'],
                          selected: s.prefetchNext,
                          onChanged: s.setPrefetchNext,
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Lyrics',
                      children: [
                        _SwitchTile(
                          title: 'Show lyrics on Now Playing',
                          detail:
                              'Off, Now Playing is only the player. Songs '
                              'with no lyrics never show a gap either way. '
                              'Lyrics stay one tap away in the menu.',
                          value: s.showLyrics,
                          onChanged: s.setShowLyrics,
                        ),
                        _ChoiceTile(
                          title: 'Text size',
                          choices: ['Small', 'Medium', 'Large'],
                          selected: s.lyricSize,
                          onChanged: s.setLyricSize,
                        ),
                        _StepperTile(
                          title: 'Tap timing',
                          detail:
                              'When you sync lyrics by tapping, marks land '
                              '${(s.lyricsTapOffset.inMilliseconds / 1000).toStringAsFixed(2)}s '
                              'before the tap, to allow for your reaction.',
                          onMinus: () => _nudgeOffset(-50),
                          onPlus: () => _nudgeOffset(50),
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Storage',
                      children: [
                        _StorageBar(
                          downloads: _usage?.downloadBytes ?? 0,
                          covers: _covers?.bytes ?? 0,
                          library: _usage?.manifestBytes ?? 0,
                          loaded: _usage != null,
                        ),
                        _ValueTile(
                          dot: Tones.held,
                          label: 'Songs on ${Device.thisOne}',
                          value: _usage == null
                              ? '—'
                              : '${_usage!.downloadCount} · '
                                    '${formatBytes(_usage!.downloadBytes)}',
                        ),
                        _ValueTile(
                          dot: Tones.primary,
                          label: 'Saved covers',
                          value: _covers == null
                              ? '—'
                              : '${_covers!.count} · '
                                    '${formatBytes(_covers!.bytes)}',
                        ),
                        _ValueTile(
                          dot: Tones.textMuted,
                          label: 'Library copy',
                          value: _usage == null
                              ? '—'
                              : formatBytes(_usage!.manifestBytes),
                        ),
                        if (_usage != null && _usage!.missingDownloads > 0)
                          _ValueTile(
                            label: 'Gone missing',
                            value:
                                '${_usage!.missingDownloads} '
                                '${_usage!.missingDownloads == 1 ? 'file' : 'files'}',
                            valueColor: Tones.warn,
                          ),
                        if (art != null)
                          _LinkTile(
                            title: 'Clear saved covers',
                            detail:
                                'Covers are saved the first time they are seen, so '
                                'the library looks the same offline. They download '
                                'again when you next connect.',
                            onTap: () async {
                              await art.clear();
                              await _measure();
                            },
                          ),
                        _LinkTile(
                          title: 'Remove all downloads',
                          detail:
                              'Takes every song off ${Device.thisOne}. Your library and '
                              'everything on the box is untouched.',
                          destructive: true,
                          onTap: _usage == null || _usage!.downloadCount == 0
                              ? null
                              : () => _confirm(
                                  title: 'Remove all downloads?',
                                  body:
                                      'Every downloaded song is removed from this '
                                      '${Device.noun}. You can download them again.',
                                  action: 'Remove',
                                  run: () async {
                                    for (final sha in widget.store.shas) {
                                      await widget.store.remove(sha);
                                    }
                                    await _measure();
                                  },
                                ),
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Your music box',
                      children: [
                        _ValueTile(
                          dot: widget.offline ? Tones.warn : Tones.held,
                          label: widget.offline
                              ? 'Cannot reach it right now'
                              : 'Connected',
                          value: '${widget.trackCount} songs',
                        ),
                        _LinkTile(
                          title: 'Server address',
                          detail: widget.endpoint,
                          onTap: _editServer,
                        ),
                        _LinkTile(
                          title: 'Sync the whole library',
                          detail:
                              'Ask the box for everything again, not just what '
                              'changed. Nothing on ${Device.thisOne} is lost.',
                          onTap: () async {
                            widget.onResync();
                            NavScope.of(context).back();
                          },
                        ),
                      ],
                    ),

                    if (widget.accountSync != null)
                      ListenableBuilder(
                        listenable: widget.accountSync!,
                        builder: (context, _) {
                          final sync = widget.accountSync!;
                          final at = sync.lastSyncedAt;
                          return _Group(
                            title: 'Across your devices',
                            children: [
                              _ValueTile(
                                dot: sync.reachable ? Tones.held : Tones.warn,
                                label: sync.syncing
                                    ? 'Syncing…'
                                    : sync.reachable
                                    ? 'In step'
                                    : 'Waiting for a connection',
                                value: at == null ? '' : _ago(at),
                              ),
                              _SwitchTile(
                                title: 'Share what I listen to',
                                detail:
                                    'On, your plays on one device shape '
                                    'recommendations on all of them. Off, '
                                    'this device keeps its own taste, like a '
                                    'TV and a phone that recommend different '
                                    'things.',
                                value: widget.settings.syncHistory,
                                onChanged: (v) =>
                                    widget.settings.setSyncHistory(v),
                              ),
                              _LinkTile(
                                title: 'Sync now',
                                detail:
                                    'Likes, playlists, corrected titles and '
                                    'where you are in the music follow your '
                                    'account to every device you sign in on.',
                                onTap: sync.syncing ? null : sync.run,
                              ),
                            ],
                          );
                        },
                      ),

                    _Group(
                      title: Device.titleThis,
                      children: [
                        _ValueTile(
                          dot: _deviceId == null ? Tones.warn : Tones.held,
                          label: _deviceId == null
                              ? 'Not signed in'
                              : 'Signed in',
                          value: '',
                        ),
                        _LinkTile(
                          title: _enrolling
                              ? 'Signing in...'
                              : _deviceId == null
                              ? 'Enter an invite code'
                              : 'Sign in again with a new code',
                          detail: _deviceId == null
                              ? 'Without this, the box will not send music to '
                                    '${Device.thisOne}. Songs already downloaded keep '
                                    'playing.'
                              : 'Replaces the key on ${Device.thisOne}. The old one '
                                    'stops working.',
                          onTap: _enrolling ? null : _enrolDevice,
                        ),
                      ],
                    ),

                    _Group(
                      title: 'Privacy',
                      children: [
                        _LinkTile(
                          title: 'Clear listening history',
                          detail:
                              'Removes every play and skip the app recorded. On '
                              'repeat, Listen again and your mixes go quiet '
                              'until you listen again. Your music is not '
                              'touched.',
                          destructive: true,
                          onTap: () => _confirm(
                            title: 'Clear listening history?',
                            body:
                                'Everything the app learned about what you '
                                'listen to is discarded. It starts learning '
                                'again from your next play. No files are '
                                'removed.',
                            action: 'Clear',
                            run: widget.history.clear,
                          ),
                        ),
                      ],
                    ),

                    if (widget.onWhatsNew != null)
                      _Group(
                        title: 'About',
                        children: [
                          _LinkTile(
                            title: 'What\'s new',
                            detail:
                                '$kWhatsNewTitle: everything new in this '
                                'release.',
                            onTap: widget.onWhatsNew,
                          ),
                        ],
                      ),

                    SizedBox(height: Space.xl),
                    Center(
                      child: GestureDetector(
                        // Seven taps, the old way in. Nothing here is dangerous
                        // enough to hide behind a password and nothing is
                        // useful enough to put in front of everyone.
                        onTap: () {
                          _versionTaps += 1;
                          if (_versionTaps >= 7 && !_developer) {
                            setState(() => _developer = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Developer section shown'),
                              ),
                            );
                          }
                        },
                        child: Column(
                          children: [
                            Text(
                              'tunes',
                              style: TypeScale.wordmark.copyWith(fontSize: 30),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'A music player for our music.',
                              style: TypeScale.note.copyWith(
                                fontSize: 14,
                                color: Tones.textMuted,
                              ),
                            ),
                            SizedBox(height: Space.sm),
                            Text(
                              '${widget.channel}  ·  '
                              '${widget.commit.length > 7 ? widget.commit.substring(0, 7) : widget.commit}  ·  '
                              'build ${widget.buildNumber}',
                              style: TypeScale.mono,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Made by Aestra Studios',
                              style: TypeScale.mono,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_developer)
                      _Group(
                        title: 'Developer',
                        children: [
                          _ValueTile(label: 'Endpoint', value: widget.endpoint),
                          _ValueTile(
                            label: 'Support dir',
                            value: widget.supportDir?.path ?? 'unknown',
                          ),
                          _ValueTile(label: 'Commit', value: widget.commit),
                          _ValueTile(
                            label: 'Images in memory',
                            value: _usage == null
                                ? '—'
                                : '${_usage!.imageCount} · '
                                      '${formatBytes(_usage!.imageBytes)}',
                          ),
                          _ValueTile(
                            label: 'Log file',
                            value: _usage == null
                                ? '—'
                                : (DiagLog.path == null
                                      ? 'not initialised'
                                      : formatBytes(_usage!.logBytes)),
                          ),
                          _LinkTile(
                            title: 'Free image memory',
                            detail:
                                'Drops decoded covers. They are decoded again as '
                                'you scroll.',
                            onTap: () async {
                              PaintingBinding.instance.imageCache.clear();
                              PaintingBinding.instance.imageCache
                                  .clearLiveImages();
                              await _measure();
                            },
                          ),
                          _LinkTile(
                            title: 'Re-measure storage',
                            detail: 'Walks the download index again.',
                            onTap: _measure,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Choosing, replacing or clearing the profile picture.
  ///
  /// The old file is deleted only once the new path is saved, so a failure
  /// anywhere in here leaves the picture you already had.
  Future<void> _editAvatar() async {
    final s = widget.settings;
    final messenger = ScaffoldMessenger.of(context);
    if (s.avatarPath != null) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Tones.surfaceRaised,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined),
                title: Text('Choose a photo', style: TypeScale.body),
                onTap: () => Navigator.of(context).pop('pick'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('Remove photo', style: TypeScale.body),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      if (choice == 'remove') {
        final old = s.avatarPath;
        await s.setAvatarPath(null);
        await _avatars.discard(old);
        return;
      }
    }
    try {
      final old = s.avatarPath;
      final path = await _avatars.pick();
      // Dismissing the picker is not a change of mind about the picture you
      // already have, so nothing is touched.
      if (path == null) return;
      await s.setAvatarPath(path);
      await _avatars.discard(old);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the photo picker: $e')),
      );
    }
  }

  /// Every destructive action explains itself before it happens, and says
  /// plainly what is not affected. "Clear" with no sentence under it is how
  /// people lose things they meant to keep.
  Future<void> _confirm({
    required String title,
    required String body,
    required String action,
    required Future<void> Function() run,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: Text(title, style: TypeScale.title),
        content: Text(body, style: TypeScale.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run();
    messenger.showSnackBar(SnackBar(content: Text(title.replaceAll('?', ''))));
  }

  Future<void> _nudgeOffset(int ms) async {
    final next = widget.settings.lyricsTapOffset + Duration(milliseconds: ms);
    // Beyond a second either way it is not reaction time any more.
    if (next.inMilliseconds < -1000 || next.inMilliseconds > 1000) return;
    await widget.settings.setLyricsTapOffset(next);
  }
}

/// The picture, with the badge that says it can be changed.
///
/// A tappable avatar with nothing on it reads as decoration, and the one
/// place people look for "change my picture" is the picture itself.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.name,
    required this.path,
    required this.onTap,
  });

  final String name;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        height: 62,
        child: Stack(
          children: [
            ProfileAvatar(name: name, path: path, size: 56),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Tones.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: Tones.surface, width: 2),
                ),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: 12,
                  color: Tones.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// You: the picture and the name, on one card at the top.
class _Profile extends StatelessWidget {
  const _Profile({
    required this.name,
    required this.path,
    required this.controller,
    required this.onAvatar,
    required this.onName,
  });

  final String name;
  final String? path;
  final TextEditingController controller;
  final VoidCallback onAvatar;
  final ValueChanged<String> onName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Tones.surface,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        border: Border.all(color: Tones.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarButton(name: name, path: path, onTap: onAvatar),
              SizedBox(width: Space.md),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TypeScale.display.copyWith(fontSize: 22),
                  decoration: InputDecoration(
                    hintText: 'What should it call you?',
                    hintStyle: TypeScale.note.copyWith(
                      fontSize: 17,
                      color: Tones.textMuted,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  // Written on every keystroke: a name that only saves on a
                  // button nobody pressed is a name that gets lost.
                  onChanged: onName,
                ),
              ),
            ],
          ),
          SizedBox(height: Space.sm),
          Text(
            'Your name follows your account to every device. Your picture stays on this one.',
            style: TypeScale.note.copyWith(
              fontSize: 13,
              color: Tones.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card of related settings, rows divided by hairlines.
/// Updates (design approved 23 Oct): a card that says where things stand --
/// newest, a new one ready, getting it, or Android's one-time permission --
/// with the Home note switch and Check now underneath. Always here, so an
/// update dismissed on Home is never lost.
class _Updates extends StatelessWidget {
  const _Updates({
    required this.updates,
    required this.buildNumber,
    required this.channel,
    required this.noteOnHome,
    required this.onNoteOnHome,
    required this.onUpdate,
    this.onWhatsNew,
  });

  final UpdateController updates;
  final String buildNumber;
  final String channel;
  final bool noteOnHome;
  final ValueChanged<bool> onNoteOnHome;
  final VoidCallback onUpdate;
  final VoidCallback? onWhatsNew;

  static String _ago(DateTime? at) {
    if (at == null) return 'not checked yet';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'checked just now';
    if (d.inMinutes < 60) {
      return 'checked ${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
    }
    final h = d.inHours;
    return 'checked $h hour${h == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final u = updates;
    final crayon = Looks.current.kind == LookKind.crayon;
    final update = u.available;
    final progress = u.progress;
    final Widget card;
    if (update != null && u.needsPermission && progress == null) {
      card = _UpdateCard(
        dashed: true,
        title: 'Let Tunes install its updates',
        detail:
            'Android asks once. Turn on "Allow from this source", then come '
            'back.',
        action: OutlinedButton(
          onPressed: u.grantPermission,
          style: OutlinedButton.styleFrom(
            foregroundColor: Tones.text,
            side: BorderSide(color: Tones.text, width: crayon ? 2 : 1),
            shape: const StadiumBorder(),
          ),
          child: const Text('Open Android settings'),
        ),
      );
    } else if (update != null && progress != null) {
      final total = update.size;
      card = _UpdateCard(
        title: 'Getting build ${update.build}',
        trailing: total > 0
            ? '${(total * progress / 1048576).round()} of '
                  '${(total / 1048576).round()} MB'
            : '${(progress * 100).round()}%',
        detail: 'Keep listening. Android asks you to confirm when it is done.',
        progress: progress,
      );
    } else if (update != null) {
      card = _UpdateCard(
        icon: Icons.system_update_alt_rounded,
        iconFill: Looks.current.crayons[1].withValues(alpha: 0.55),
        title: 'A new Tunes is ready',
        detail: [
          'Build ${update.build}',
          if (update.readableSize.isNotEmpty) update.readableSize,
          'you have $buildNumber',
        ].join(' · '),
        notes: update.notes.isEmpty ? null : update.notes,
        onWhatsNew: onWhatsNew,
        action: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onUpdate,
                style: FilledButton.styleFrom(
                  backgroundColor: Tones.primary,
                  foregroundColor: crayon ? Tones.text : Tones.onPrimary,
                  minimumSize: const Size.fromHeight(46),
                  shape: StadiumBorder(
                    side: crayon
                        ? BorderSide(color: Tones.text, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: const Text('Update now'),
              ),
            ),
          ],
        ),
      );
    } else {
      card = _UpdateCard(
        icon: Icons.check_rounded,
        iconFill: Tones.held.withValues(alpha: 0.25),
        iconColor: Tones.held,
        title: u.failed
            ? "Couldn't check for updates"
            : 'You have the newest Tunes',
        detail: u.failed
            ? 'The box did not answer. Try again in a moment.'
            : 'Build $buildNumber',
      );
    }
    return _Group(
      title: 'Updates',
      children: [
        Padding(padding: const EdgeInsets.all(Space.sm + 2), child: card),
        _SwitchTile(
          title: 'Tell me on Home',
          detail: 'A note at the top when a new one is ready',
          value: noteOnHome,
          onChanged: onNoteOnHome,
        ),
        Padding(
          padding: _tilePadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$channel · build $buildNumber · ${_ago(u.checkedAt)}',
                  style: TypeScale.caption,
                ),
              ),
              OutlinedButton(
                onPressed: u.checking ? null : u.check,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tones.text,
                  side: BorderSide(
                    color: crayon ? Tones.text : Tones.hairline,
                    width: crayon ? 1.5 : 1,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(u.checking ? 'Checking…' : 'Check now'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.title,
    required this.detail,
    this.icon,
    this.iconFill,
    this.iconColor,
    this.notes,
    this.onWhatsNew,
    this.action,
    this.trailing,
    this.progress,
    this.dashed = false,
  });

  final String title;
  final String detail;
  final IconData? icon;
  final Color? iconFill;
  final Color? iconColor;
  final String? notes;
  final VoidCallback? onWhatsNew;
  final Widget? action;
  final String? trailing;
  final double? progress;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    return Container(
      padding: const EdgeInsets.all(Space.md - 2),
      decoration: BoxDecoration(
        color: dashed ? Tones.surface : Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(RadiusTokens.card - 2),
        border: Border.all(
          color: crayon ? Tones.text : Tones.hairline,
          width: crayon ? 2 : 1,
        ),
        boxShadow: crayon && !dashed
            ? [BoxShadow(color: look.inkShadow, offset: const Offset(3, 3))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconFill,
                    borderRadius: BorderRadius.circular(12),
                    border: crayon
                        ? Border.all(color: Tones.text, width: 2)
                        : null,
                  ),
                  child: Icon(icon, color: iconColor ?? Tones.text, size: 22),
                ),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _tileTitle().copyWith(fontSize: 16)),
                    Text(detail, style: TypeScale.caption),
                  ],
                ),
              ),
              if (trailing != null) Text(trailing!, style: TypeScale.caption),
            ],
          ),
          if (notes != null) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md - 4,
                vertical: Space.sm + 2,
              ),
              decoration: BoxDecoration(
                color: Tones.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notes!,
                    style: TypeScale.body.copyWith(color: Tones.text),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (onWhatsNew != null)
                    GestureDetector(
                      onTap: onWhatsNew,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "What's new",
                          style: TypeScale.body.copyWith(
                            color: Tones.text,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: Tones.held,
                backgroundColor: Tones.hairline,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Space.sm + 2),
            action!,
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: Space.xs, bottom: Space.sm),
            child: Text(
              title.toUpperCase(),
              style: TypeScale.mono.copyWith(letterSpacing: 1.3),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Tones.surface,
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              border: Border.all(color: Tones.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 0.5, color: Tones.hairline),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _tilePadding = EdgeInsets.symmetric(
  horizontal: Space.md + 2,
  vertical: Space.md - 2,
);

TextStyle _tileTitle([Color? color]) => TypeScale.title.copyWith(
  fontSize: 15,
  color: color ?? Tones.text,
  fontVariations: const [FontVariation('wght', 500)],
  fontWeight: FontWeight.w500,
);

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: _tilePadding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _tileTitle()),
                  const SizedBox(height: 2),
                  Text(detail, style: TypeScale.caption.copyWith(height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Tones.base,
              activeTrackColor: Tones.primary,
              inactiveThumbColor: Tones.textMuted,
              inactiveTrackColor: Tones.surfaceRaised,
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one of a few: text size, say.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> choices;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _tilePadding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: _tileTitle())),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < choices.length; i++)
                ButtonSegment(value: i, label: Text(choices[i])),
            ],
            selected: {selected},
            onSelectionChanged: (v) => onChanged(v.first),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.title,
    required this.detail,
    required this.onMinus,
    required this.onPlus,
  });

  final String title;
  final String detail;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _tilePadding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _tileTitle()),
                const SizedBox(height: 2),
                Text(detail, style: TypeScale.caption.copyWith(height: 1.4)),
              ],
            ),
          ),
          IconButton.outlined(
            onPressed: onMinus,
            tooltip: 'Earlier',
            icon: const Icon(Icons.remove_rounded, size: 18),
            color: Tones.text,
            style: IconButton.styleFrom(
              side: BorderSide(color: Tones.hairline),
            ),
          ),
          const SizedBox(width: Space.xs),
          IconButton.outlined(
            onPressed: onPlus,
            tooltip: 'Later',
            icon: const Icon(Icons.add_rounded, size: 18),
            color: Tones.text,
            style: IconButton.styleFrom(
              side: BorderSide(color: Tones.hairline),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fact: a label, with an optional coloured dot, and its value in mono.
String _ago(DateTime at) {
  final s = DateTime.now().difference(at).inSeconds;
  if (s < 10) return 'just now';
  if (s < 90) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60} min ago';
  return '${s ~/ 3600} h ago';
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.label,
    required this.value,
    this.dot,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? dot;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _tilePadding,
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.sm + 2),
          ],
          Expanded(child: Text(label, style: _tileTitle())),
          if (value.isNotEmpty)
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TypeScale.mono.copyWith(
                  fontSize: 13,
                  color: valueColor ?? Tones.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row that does something, with the sentence that says what.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.title,
    required this.detail,
    required this.onTap,
    this.destructive = false,
  });

  final String title;
  final String detail;

  /// Null disables the row, so one that is mid-flight can say so.
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: _tilePadding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _tileTitle(destructive ? Tones.warn : Tones.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TypeScale.caption.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Tones.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is taking the space, as one bar: songs, covers, the library copy.
class _StorageBar extends StatelessWidget {
  const _StorageBar({
    required this.downloads,
    required this.covers,
    required this.library,
    required this.loaded,
  });

  final int downloads;
  final int covers;
  final int library;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final total = downloads + covers + library;
    return Padding(
      padding: _tilePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loaded ? formatBytes(total) : '—',
            style: TypeScale.display.copyWith(fontSize: 26),
          ),
          Text('used on ${Device.thisOne}', style: TypeScale.caption),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: total <= 0
                  ? ColoredBox(color: Tones.hairline)
                  : Row(
                      children: [
                        if (downloads > 0)
                          Expanded(
                            flex: downloads,
                            child: ColoredBox(color: Tones.held),
                          ),
                        if (covers > 0)
                          Expanded(
                            flex: covers,
                            child: ColoredBox(color: Tones.primary),
                          ),
                        if (library > 0)
                          Expanded(
                            flex: library,
                            child: ColoredBox(color: Tones.textMuted),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// This week in one line, and the way into the full listening page.
class _ListeningCard extends StatefulWidget {
  const _ListeningCard({
    required this.history,
    required this.library,
    required this.artUrlFor,
    required this.links,
  });

  final PlayHistory history;
  final Map<String, ManifestTrack> library;
  final String Function(String sha)? artUrlFor;
  final ListeningLinks links;

  @override
  State<_ListeningCard> createState() => _ListeningCardState();
}

class _ListeningCardState extends State<_ListeningCard> {
  ListeningStats? _week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await widget.history.listenEvents();
    if (!mounted) return;
    setState(
      () => _week = ListeningStats.compute(
        events: events,
        library: widget.library,
        range: StatsRange.week,
        now: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _week;
    final String line;
    if (w == null) {
      line = ' ';
    } else if (w.isEmpty) {
      line = 'Nothing yet this week';
    } else {
      final h = w.listened.inHours;
      final m = w.listened.inMinutes % 60;
      final time = h == 0 ? '${w.listened.inMinutes} min' : '$h h $m m';
      line = [
        '$time this week',
        if (w.topArtists.isNotEmpty) 'mostly ${w.topArtists.first.name}',
        if (w.streakDays > 1) '${w.streakDays}-day streak',
      ].join(' · ');
    }
    return Material(
      color: Tones.surface,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        onTap: () async {
          ListeningPage page() => ListeningPage(
            history: widget.history,
            library: widget.library,
            artUrlFor: widget.artUrlFor,
            onArtist: widget.links.onArtist,
            onAlbum: widget.links.onAlbum,
            onSong: widget.links.onSong,
          );
          // In the app it is a panel, so an artist or album opened from it
          // stacks on top and Back comes back to it.
          final nav = NavScope.maybeOf(context);
          if (nav != null) {
            nav.openPanel(TunesPanels.listening, page);
            return;
          }
          await Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page()));
          _load();
        },
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            border: Border.all(color: Tones.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your listening', style: _tileTitle(Tones.text)),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: TypeScale.caption.copyWith(height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (w != null && !w.isEmpty) ...[
                const SizedBox(width: Space.md),
                _Spark(values: w.buckets),
              ],
              const SizedBox(width: Space.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Tones.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seven small bars: the week at a glance.
class _Spark extends StatelessWidget {
  const _Spark({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Container(
              width: 5,
              height: v <= 0 ? 2 : (v / max * 28).clamp(2.0, 28.0),
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: v <= 0
                    ? Tones.hairline
                    : Tones.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// One card per theme, each drawn in its own colours and type so the choice
/// is made by looking, plus Auto.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({
    required this.choice,
    required this.brightness,
    required this.onChoice,
  });

  final String choice;
  final int brightness;
  final ValueChanged<String> onChoice;

  @override
  Widget build(BuildContext context) {
    final b = Looks.current.brightness;
    final cards = <(String, String, String, TunesLook, TunesLook?)>[
      for (final t in Looks.all) (t.id, t.name, t.blurb, t.of(b), null),
      (
        'auto',
        'Auto',
        'Crayon by day, Noir after dark.',
        Looks.crayon.of(b),
        Looks.noir.of(b),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Space.sm,
        crossAxisSpacing: Space.sm,
        childAspectRatio: 1.45,
        children: [
          for (final (id, name, blurb, look, second) in cards)
            _ThemeCard(
              name: name,
              blurb: blurb,
              look: look,
              second: second,
              selected: id == choice,
              onTap: () => onChoice(id),
            ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.blurb,
    required this.look,
    required this.second,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String blurb;
  final TunesLook look;

  /// Auto's night half, drawn as a diagonal over the day half.
  final TunesLook? second;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(look.cardRadius.clamp(4, 18));
    return Semantics(
      button: true,
      selected: selected,
      label: '$name theme. $blurb',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: look.base,
            borderRadius: radius,
            border: Border.all(
              color: selected ? Tones.primary : Tones.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                if (second != null)
                  Positioned.fill(
                    child: ClipPath(
                      clipper: _Diagonal(),
                      child: ColoredBox(color: second!.base),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(Space.sm + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final c in [
                            look.primary,
                            look.held,
                            second?.primary ?? look.warn,
                          ])
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ),
                          const Spacer(),
                          if (selected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: look.primary,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: look.display,
                          fontSize: 20,
                          height: 1.1,
                          color: look.text,
                          fontVariations: [
                            ...look.displayAxes,
                            const FontVariation('wght', 500),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: look.body,
                          fontSize: 11,
                          height: 1.25,
                          color: second == null ? look.textMuted : look.text,
                          fontVariations: look.bodyAxes,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Diagonal extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * 0.35, size.height)
    ..close();

  @override
  bool shouldReclip(_Diagonal oldClipper) => false;
}

String _clock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

Future<void> _pickTime(
  BuildContext context,
  int minutes,
  Future<void> Function(int) save,
) async {
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
  );
  if (t != null) await save(t.hour * 60 + t.minute);
}
