import 'package:flutter/material.dart';

import '../../core/data/playlist_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/profile_avatar.dart';
import '../../core/ui/tunes_nav_bar.dart';

/// The left rail of the desktop layout: where you are, your playlists, and
/// settings. The same four places as the phone's tab bar, laid out as a list.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.selectedTab,
    required this.onTab,
    required this.playlists,
    required this.onPlaylist,
    required this.onSettings,
    required this.name,
    required this.avatarPath,
    this.activePlaylistId,
  });

  /// The tab showing, or null while a page (an album, the player) is open.
  final int? selectedTab;
  final ValueChanged<int> onTab;
  final PlaylistStore? playlists;
  final ValueChanged<PlaylistSummary> onPlaylist;
  final VoidCallback onSettings;
  final String name;
  final String? avatarPath;
  final int? activePlaylistId;

  static const width = 248.0;

  static const _items = [
    (NavGlyph.home, 'Home'),
    (NavGlyph.discover, 'Discover'),
    (NavGlyph.search, 'Search'),
    (NavGlyph.library, 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Tones.base,
        border: Border(right: BorderSide(color: Tones.hairline)),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                Space.md,
              ),
              child: Text('tunes', style: TypeScale.wordmark),
            ),
            for (var i = 0; i < _items.length; i++)
              _Row(
                selected: selectedTab == i,
                onTap: () => onTab(i),
                leading: NavGlyphIcon(
                  glyph: _items[i].$1,
                  size: 22,
                  color: selectedTab == i ? Tones.text : Tones.textMuted,
                ),
                label: _items[i].$2,
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                Space.sm,
              ),
              child: Divider(height: 1, color: Tones.hairline),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
              child: Text('PLAYLISTS', style: TypeScale.mono),
            ),
            Expanded(
              child: _PlaylistList(
                store: playlists,
                onPlaylist: onPlaylist,
                activeId: activePlaylistId,
              ),
            ),
            const Divider(height: 1, color: Tones.hairline),
            InkWell(
              onTap: onSettings,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    ProfileAvatar(name: name, path: avatarPath, size: 32),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Settings' : name,
                        style: TypeScale.title.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: Tones.textMuted,
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
}

class _Row extends StatefulWidget {
  const _Row({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.label,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String label;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? Tones.surfaceRaised
                : _hover
                ? Tones.surfaceRaised.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.title.copyWith(
                    fontSize: 15,
                    color: widget.selected || _hover
                        ? Tones.text
                        : Tones.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.store,
    required this.onPlaylist,
    required this.activeId,
  });

  final PlaylistStore? store;
  final ValueChanged<PlaylistSummary> onPlaylist;
  final int? activeId;

  @override
  Widget build(BuildContext context) {
    final s = store;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => FutureBuilder<List<PlaylistSummary>>(
        future: s.summaries(),
        builder: (context, snap) {
          final lists = snap.data ?? const <PlaylistSummary>[];
          if (lists.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: Text(
                'Playlists you make show up here.',
                style: TypeScale.caption,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.sm),
            children: [
              for (final p in lists)
                _Row(
                  selected: activeId == p.id,
                  onTap: () => onPlaylist(p),
                  leading: const Icon(
                    Icons.queue_music_rounded,
                    size: 22,
                    color: Tones.textMuted,
                  ),
                  label: p.name,
                ),
            ],
          );
        },
      ),
    );
  }
}
