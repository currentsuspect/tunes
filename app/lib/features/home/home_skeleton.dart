import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// What Home looks like before the library arrives.
///
/// Built to the same geometry as the real thing -- same rail heights, same
/// card widths, same section spacing -- so the content replaces the skeleton
/// without anything moving. A spinner in the middle of an empty screen says
/// "wait"; this says what is coming, and it stops the first frame of real
/// content from being a jolt.
class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Slow and shallow. A skeleton that shimmers hard reads as a loading
    // animation in its own right, which is more attention than waiting
    // deserves.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = 0.55 + 0.45 * _pulse.value;
        return Opacity(
          opacity: t,
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Space.lg),
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: _Bar(width: 220, height: 13),
              ),
              _RailSkeleton(),
              _RailSkeleton(),
            ],
          ),
        );
      },
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
          child: _Bar(width: 140, height: 20),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.lg, 0),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) => SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 132, height: 132, radius: RadiusTokens.card),
                  SizedBox(height: Space.sm),
                  _Bar(width: 96, height: 12),
                  SizedBox(height: 6),
                  _Bar(width: 64, height: 10),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, this.radius = 4});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
