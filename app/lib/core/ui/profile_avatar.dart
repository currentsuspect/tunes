import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'initials.dart';

/// You, wherever you appear: the home header, settings.
///
/// Three states, in order of how much the app knows about you -- your picture,
/// your initials, or nothing yet. Kept in one place so the header and the
/// settings screen can never drift into showing different things.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.path,
    this.size = 40,
  });

  final String name;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p != null && p.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(p),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Decoded at the size it is drawn at, on a device where the header
          // avatar is 38 logical pixels.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          // A file that has gone -- storage cleared, backup restored -- falls
          // back rather than showing a broken image box. Checked this way and
          // not with existsSync, which would be a disk hit on every rebuild.
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    if (name.trim().isNotEmpty) return InitialsAvatar(name: name, size: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.58,
        color: Tones.textMuted,
      ),
    );
  }
}
