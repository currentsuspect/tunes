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
import '../../core/theme/tokens.dart';
import '../../core/ui/profile_avatar.dart';

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
    this.supportDir,
  });

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
        title: const Text('Invite code', style: TypeScale.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
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
            child: const Text('Enrol'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;

    setState(() => _enrolling = true);
    final label = widget.settings.displayName.trim().isEmpty
        ? 'Android device'
        : "${widget.settings.displayName.trim()}'s phone";
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
        title: const Text('Server', style: TypeScale.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Where your tunesd is. Include the port.',
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: TypeScale.body,
              decoration: const InputDecoration(
                hintText: 'http://100.100.235.90:4780',
              ),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            const SizedBox(height: Space.sm),
            const Text(
              'Leave it empty to go back to the address this build came with.',
              style: TypeScale.caption,
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
            child: const Text('Save'),
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
      const SnackBar(content: Text('Server changed — refetching the library')),
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
                padding: const EdgeInsets.fromLTRB(
                  Space.xs,
                  Space.sm,
                  Space.sm,
                  0,
                ),
                child: IconButton(
                  onPressed: () => NavScope.of(context).back(),
                  tooltip: 'Back',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Tones.textMuted,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: s,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.xl,
                  ),
                  children: [
                    Text(
                      'Settings',
                      style: TypeScale.display.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: Space.lg),
                    _Profile(
                      name: s.displayName,
                      path: s.avatarPath,
                      controller: _name,
                      onAvatar: _editAvatar,
                      onName: s.setDisplayName,
                    ),

                    _Group(
                      title: 'Listening',
                      children: [
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
                              'own listening, on this phone. Added after the '
                              'queue, never mixed into it.',
                          value: s.radioAutoplay,
                          onChanged: s.setRadioAutoplay,
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
                      title: 'Lyrics',
                      children: [
                        _ChoiceTile(
                          title: 'Text size',
                          choices: const ['Small', 'Medium', 'Large'],
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
                          label: 'Songs on this phone',
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
                              'Takes every song off this phone. Your library and '
                              'everything on the box is untouched.',
                          destructive: true,
                          onTap: _usage == null || _usage!.downloadCount == 0
                              ? null
                              : () => _confirm(
                                  title: 'Remove all downloads?',
                                  body:
                                      'Every downloaded song is removed from this '
                                      'phone. You can download them again.',
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
                              'changed. Nothing on this phone is lost.',
                          onTap: () async {
                            widget.onResync();
                            NavScope.of(context).back();
                          },
                        ),
                      ],
                    ),

                    _Group(
                      title: 'This phone',
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
                                    'this phone. Songs already downloaded keep '
                                    'playing.'
                              : 'Replaces the key on this phone. The old one '
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
                                'The Birthday Pack: everything new in this '
                                'release.',
                            onTap: widget.onWhatsNew,
                          ),
                        ],
                      ),

                    const SizedBox(height: Space.xl),
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
                              const SnackBar(
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
                            const SizedBox(height: 2),
                            Text(
                              'A music player for our music.',
                              style: TypeScale.note.copyWith(
                                fontSize: 14,
                                color: Tones.textMuted,
                              ),
                            ),
                            const SizedBox(height: Space.sm),
                            Text(
                              '${widget.channel}  ·  '
                              '${widget.commit.length > 7 ? widget.commit.substring(0, 7) : widget.commit}  ·  '
                              'build ${widget.buildNumber}',
                              style: TypeScale.mono,
                            ),
                            const SizedBox(height: 2),
                            const Text(
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
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose a photo', style: TypeScale.body),
                onTap: () => Navigator.of(context).pop('pick'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove photo', style: TypeScale.body),
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
            child: const Text('Cancel'),
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
                child: const Icon(
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
      padding: const EdgeInsets.all(Space.md),
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
              const SizedBox(width: Space.md),
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
          const SizedBox(height: Space.sm),
          Text(
            'Your name and picture stay on this phone. Home greets you with it.',
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
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
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
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Tones.hairline,
                    ),
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

TextStyle _tileTitle([Color color = Tones.text]) => TypeScale.title.copyWith(
  fontSize: 15,
  color: color,
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
              side: const BorderSide(color: Tones.hairline),
            ),
          ),
          const SizedBox(width: Space.xs),
          IconButton.outlined(
            onPressed: onPlus,
            tooltip: 'Later',
            icon: const Icon(Icons.add_rounded, size: 18),
            color: Tones.text,
            style: IconButton.styleFrom(
              side: const BorderSide(color: Tones.hairline),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fact: a label, with an optional coloured dot, and its value in mono.
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
              const Icon(
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
          Text('used on this phone', style: TypeScale.caption),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: total <= 0
                  ? const ColoredBox(color: Tones.hairline)
                  : Row(
                      children: [
                        if (downloads > 0)
                          Expanded(
                            flex: downloads,
                            child: const ColoredBox(color: Tones.held),
                          ),
                        if (covers > 0)
                          Expanded(
                            flex: covers,
                            child: const ColoredBox(color: Tones.primary),
                          ),
                        if (library > 0)
                          Expanded(
                            flex: library,
                            child: const ColoredBox(color: Tones.textMuted),
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
