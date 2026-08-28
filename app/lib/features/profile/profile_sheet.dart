import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

void showProfileSheet(
  BuildContext context, {
  required String endpoint,
  required bool offline,
  required String commit,
  required String buildNumber,
  required String channel,
  required int downloadCount,
  required int trackCount,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tones.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RadiusTokens.card),
      ),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('tunes', style: TypeScale.title),
                      Text('personal library', style: TypeScale.caption),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              _Row(label: 'Daemon', value: offline ? 'offline' : 'online'),
              _Row(label: 'Endpoint', value: endpoint),
              _Row(label: 'Library', value: '$trackCount tracks'),
              _Row(label: 'Downloaded', value: '$downloadCount tracks'),
              _Row(
                label: 'Build',
                value:
                    '$channel · ${commit.length > 7 ? commit.substring(0, 7) : commit} · $buildNumber',
              ),
              const SizedBox(height: Space.lg),
              const Text(
                'Offline mode plays downloaded tracks only. Reachability '
                'is probed every 10 seconds.',
                style: TypeScale.caption,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TypeScale.caption)),
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
