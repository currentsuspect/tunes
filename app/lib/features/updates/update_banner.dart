import 'package:flutter/material.dart';

import '../../core/net/update_check.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';

/// Says a newer build exists, and offers to fetch it.
///
/// Deliberately a strip above the content rather than a dialog. An update is
/// worth knowing about and never worth interrupting for — nobody opened a
/// music app to be told about software. It can be dismissed, and it comes back
/// on the next launch if still relevant, which is the right amount of nagging
/// for something that is genuinely optional.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.update,
    required this.onInstall,
    required this.onDismiss,
    this.progress,
    this.needsPermission = false,
    this.onGrantPermission,
  });

  final AvailableUpdate update;

  /// 0..1 while downloading, null when idle.
  final double? progress;
  final VoidCallback onInstall;
  final VoidCallback onDismiss;

  /// Android 8+ requires per-app permission to open the installer, grantable
  /// only from Settings. Asking for it up front beats downloading 100 MB and
  /// failing at the last step.
  final bool needsPermission;
  final VoidCallback? onGrantPermission;

  @override
  Widget build(BuildContext context) {
    // A note at the top of Home (design approved 23 Oct): a card in the
    // look's own style rather than a grey strip. Not now hides it; the
    // update waits in Settings, with a dot on the profile picture.
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    final downloading = progress != null;
    final size = update.readableSize;
    final onAccent = crayon ? Tones.text : Tones.onPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Transform.rotate(
        angle: crayon ? -0.01 : 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.md, 10, Space.xs, 10),
          decoration: BoxDecoration(
            color: Tones.surfaceRaised,
            borderRadius: BorderRadius.circular(RadiusTokens.card - 4),
            border: Border.all(
              color: crayon ? Tones.text : Tones.hairline,
              width: crayon ? 2 : 1,
            ),
            boxShadow: crayon
                ? [BoxShadow(color: look.inkShadow, offset: const Offset(3, 3))]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 20,
                color: crayon ? Tones.text : Tones.primary,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      downloading
                          ? 'Getting the new Tunes'
                          : 'A new Tunes is ready',
                      style: TypeScale.title.copyWith(fontSize: 14.5),
                    ),
                    if (!downloading)
                      Text(
                        // The notes are the commit subject, which says what
                        // changed. Size, because the person tapping may be
                        // on mobile data.
                        [
                          if (update.notes.isNotEmpty) update.notes,
                          if (size.isNotEmpty) size,
                        ].join(' · '),
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (downloading) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          color: Tones.held,
                          backgroundColor: Tones.hairline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!downloading) ...[
                const SizedBox(width: Space.sm),
                FilledButton(
                  onPressed: needsPermission ? onGrantPermission : onInstall,
                  style: FilledButton.styleFrom(
                    backgroundColor: Tones.primary,
                    foregroundColor: onAccent,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: StadiumBorder(
                      side: crayon
                          ? BorderSide(color: Tones.text, width: 2)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(needsPermission ? 'Allow' : 'Update'),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Tones.textMuted,
                  ),
                  tooltip: 'Not now',
                ),
              ] else
                const SizedBox(width: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}
