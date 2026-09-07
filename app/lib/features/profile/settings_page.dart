import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/play_history.dart';
import '../../core/data/storage_usage.dart';
import '../../core/platform/diag_log.dart';
import '../../core/data/avatar.dart';
import '../../core/data/settings_store.dart';
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
    this.supportDir,
  });

  final SettingsStore settings;
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

  /// Seven taps on the build line. Hidden rather than absent: these controls
  /// are for whoever is debugging the app, and putting them in front of
  /// everyone else would be clutter that also invites damage.
  int _versionTaps = 0;
  bool _developer = false;

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
  }

  Future<void> _measure() async {
    final usage = await StorageUsage.measure(
      store: widget.store,
      manifestPath: widget.supportDir == null
          ? null
          : '${widget.supportDir!.path}/manifest.json',
      logPath: DiagLog.path,
    );
    if (mounted) setState(() => _usage = usage);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      backgroundColor: Tones.surface,
      appBar: AppBar(
        backgroundColor: Tones.surface,
        title: const Text('Settings', style: TypeScale.heading),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            const _SectionLabel('You'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Row(
                children: [
                  _AvatarButton(
                    name: s.displayName,
                    path: s.avatarPath,
                    onTap: _editAvatar,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      style: TypeScale.body,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'What should the app call you?',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                      // Written on every keystroke: a name that only saves on
                      // a button nobody pressed is a name that gets lost.
                      onChanged: s.setDisplayName,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: Text(
                'Your name and picture stay on this device. Friends and '
                'sharing need an account, which does not exist yet.',
                style: TypeScale.caption,
              ),
            ),

            const _SectionLabel('Playback'),
            SwitchListTile(
              value: s.gapless,
              title: const Text('Gapless playback', style: TypeScale.body),
              subtitle: const Text(
                'Joins tracks with no silence between them. Normally only '
                'happens when two files share a format.',
                style: TypeScale.caption,
              ),
              onChanged: (v) async {
                await s.setGapless(v);
                await widget.player.setGapless(v);
              },
            ),
            SwitchListTile(
              value: s.stopOnClose,
              title: const Text(
                'Stop when the app closes',
                style: TypeScale.body,
              ),
              subtitle: const Text(
                'Off means playback survives swiping the app away, with no '
                'controls on screen to stop it.',
                style: TypeScale.caption,
              ),
              onChanged: s.setStopOnClose,
            ),

            const _SectionLabel('Lyrics'),
            ListTile(
              title: const Text('Tap offset', style: TypeScale.body),
              subtitle: Text(
                'Marks land ${(s.lyricsTapOffset.inMilliseconds / 1000).toStringAsFixed(2)}s '
                'before the tap, to allow for how long it takes to react.',
                style: TypeScale.caption,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _nudgeOffset(-50),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  IconButton(
                    onPressed: () => _nudgeOffset(50),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),

            const _SectionLabel('Now playing'),
            SwitchListTile(
              value: s.animatedArtwork,
              title: const Text('Turning artwork', style: TypeScale.body),
              subtitle: const Text(
                'The sleeve rotates slowly while a track plays. The only '
                'thing in the app that moves continuously.',
                style: TypeScale.caption,
              ),
              onChanged: s.setAnimatedArtwork,
            ),

            const _SectionLabel('Storage'),
            _Row(
              label: 'Downloaded',
              value: _usage == null
                  ? '—'
                  : '${_usage!.downloadCount} '
                        '${_usage!.downloadCount == 1 ? 'track' : 'tracks'} · '
                        '${formatBytes(_usage!.downloadBytes)}',
            ),
            if (_usage != null && _usage!.missingDownloads > 0)
              _Row(
                label: 'Gone missing',
                value:
                    '${_usage!.missingDownloads} downloaded '
                    '${_usage!.missingDownloads == 1 ? 'file' : 'files'} '
                    'no longer on disk',
              ),
            _Row(
              label: 'Library cache',
              value: _usage == null ? '—' : formatBytes(_usage!.manifestBytes),
            ),
            _Row(
              label: 'Artwork in memory',
              value: _usage == null
                  ? '—'
                  : '${_usage!.imageCount} images · '
                        '${formatBytes(_usage!.imageBytes)}',
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
              child: Text(
                'There is no artwork cache on disk to clear. Covers are '
                'fetched as they are shown and kept as decoded images in '
                'memory, which the system reclaims on its own.',
                style: TypeScale.caption,
              ),
            ),
            _Action(
              label: 'Free artwork memory',
              detail:
                  'Drops decoded covers. They are fetched again as you '
                  'scroll, so this is worth doing only if the app feels heavy.',
              onTap: () async {
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                await _measure();
              },
            ),

            const _SectionLabel('Data'),
            _Action(
              label: 'Clear listening history',
              detail:
                  'Removes every play and skip this app recorded. '
                  'Recently played, On repeat and Listen again go empty, and '
                  'Discover falls back to ranking by what you own. Your '
                  'music is not touched.',
              destructive: true,
              onTap: () => _confirm(
                title: 'Clear listening history?',
                body:
                    'Everything the app learned about what you listen to '
                    'is discarded. It starts learning again from your next '
                    'play. No files are removed.',
                action: 'Clear',
                run: widget.history.clear,
              ),
            ),
            _Action(
              label: 'Refetch the library',
              detail:
                  'Asks the daemon for the whole library again, rather '
                  'than the changes since last time. Nothing local is lost.',
              onTap: () async {
                widget.onResync();
                Navigator.of(context).maybePop();
              },
            ),

            const _SectionLabel('Library'),
            _Row(label: 'Daemon', value: widget.offline ? 'offline' : 'online'),
            _Action(
              label: 'Server',
              detail: widget.endpoint,
              onTap: _editServer,
            ),
            _Row(label: 'Tracks', value: '${widget.trackCount}'),
            _Row(label: 'Downloaded', value: '${widget.downloadCount}'),

            const _SectionLabel('About'),
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('tunes', style: TypeScale.heading),
                  SizedBox(height: 2),
                  Text('A music player for our music.', style: TypeScale.body),
                ],
              ),
            ),
            InkWell(
              // Seven taps, the old way in. Nothing here is dangerous enough
              // to hide behind a password and nothing is useful enough to
              // put in front of everyone.
              onTap: () {
                _versionTaps += 1;
                if (_versionTaps >= 7 && !_developer) {
                  setState(() => _developer = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Developer section shown')),
                  );
                }
              },
              child: _Row(
                label: 'Version',
                value:
                    '${widget.channel} · '
                    '${widget.commit.length > 7 ? widget.commit.substring(0, 7) : widget.commit} · '
                    'build ${widget.buildNumber}',
              ),
            ),
            const _Row(label: 'Made by', value: 'Aestra Studios'),

            if (_developer) ...[
              const _SectionLabel('Developer'),
              _Row(label: 'Endpoint', value: widget.endpoint),
              _Row(
                label: 'Support dir',
                value: widget.supportDir?.path ?? 'unknown',
              ),
              _Row(label: 'Commit', value: widget.commit),
              _Row(
                label: 'Image cache',
                value: _usage == null
                    ? '—'
                    : '${_usage!.imageCount} live · '
                          '${formatBytes(_usage!.imageBytes)}',
              ),
              _Row(
                label: 'Log file',
                value: _usage == null
                    ? '—'
                    : (DiagLog.path == null
                          ? 'not initialised'
                          : formatBytes(_usage!.logBytes)),
              ),
              _Action(
                label: 'Re-measure storage',
                detail: 'Walks the download index again.',
                onTap: _measure,
              ),
            ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: TypeScale.caption.copyWith(
          color: Tones.textMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: TypeScale.caption)),
          Expanded(
            child: Text(
              value,
              style: TypeScale.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row that does something, with the sentence that says what.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.detail,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TypeScale.body.copyWith(
                color: destructive ? Tones.primary : Tones.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(detail, style: TypeScale.caption),
          ],
        ),
      ),
    );
  }
}
