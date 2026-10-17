import 'package:flutter/material.dart';

import '../../core/net/update_check.dart';
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
    final downloading = progress != null;
    final size = update.readableSize;
    return Material(
      color: Tones.surfaceRaised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.sm,
          Space.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.system_update_alt_rounded,
              size: 20,
              color: Tones.primary,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    downloading ? 'Downloading update' : 'Update available',
                    style: TypeScale.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (!downloading)
                    Text(
                      // The notes are the commit subject, which says what
                      // actually changed. Size, because this is ~100 MB and
                      // the person tapping may be on mobile data.
                      [
                        if (update.notes.isNotEmpty) update.notes,
                        if (size.isNotEmpty) size,
                      ].join(' · '),
                      style: TypeScale.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (downloading) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: Tones.hairline,
                    ),
                  ],
                ],
              ),
            ),
            if (!downloading) ...[
              if (needsPermission)
                TextButton(
                  onPressed: onGrantPermission,
                  child: const Text('Allow'),
                )
              else
                TextButton(onPressed: onInstall, child: const Text('Update')),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Not now',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
