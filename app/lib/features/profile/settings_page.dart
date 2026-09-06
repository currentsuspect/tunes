import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
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

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _name;
  final _avatars = AvatarStore();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.displayName);
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

            const _SectionLabel('Library'),
            _Row(label: 'Daemon', value: widget.offline ? 'offline' : 'online'),
            _Row(label: 'Endpoint', value: widget.endpoint),
            _Row(label: 'Tracks', value: '${widget.trackCount}'),
            _Row(label: 'Downloaded', value: '${widget.downloadCount}'),
            _Row(
              label: 'Build',
              value:
                  '${widget.channel} · '
                  '${widget.commit.length > 7 ? widget.commit.substring(0, 7) : widget.commit} · '
                  '${widget.buildNumber}',
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
