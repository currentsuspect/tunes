import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A scrolling list you can pull down to refresh.
///
/// The stock Material indicator is a shadowed white-ish disc that drops in from
/// the top and bounces; on this screen it read as a different app. This is flat:
/// a thin ring that fills as you pull, and a line in the serif saying what will
/// happen, what is happening, and that it happened. It rides the list's own
/// motion, so nothing is drawn on top of it.
///
/// Always scrollable, even when the content is shorter than the screen: a feed
/// that cannot be pulled because it happens to be short is a feed whose refresh
/// is a coin toss.
class TunesRefreshList extends StatelessWidget {
  const TunesRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsets padding;

  static const _trigger = 84.0;
  static const _hold = 52.0;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomScrollView(
        // Bouncing, so the list can be pulled past its top at all on Android,
        // where the default clamps and the indicator would have nothing to ride.
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: onRefresh,
            refreshTriggerPullDistance: _trigger,
            refreshIndicatorExtent: _hold,
            builder: _indicator,
          ),
          SliverPadding(
            padding: padding,
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      ),
    );
  }

  static Widget _indicator(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulled,
    double trigger,
    double extent,
  ) {
    final armed = mode == RefreshIndicatorMode.armed;
    final working = mode == RefreshIndicatorMode.refresh;
    final done = mode == RefreshIndicatorMode.done;
    final progress = (pulled / trigger).clamp(0.0, 1.0);

    final String text;
    if (working) {
      text = 'Syncing';
    } else if (done) {
      text = 'Up to date';
    } else if (armed) {
      text = 'Let go to sync';
    } else {
      text = 'Pull to sync';
    }

    // Fades in over the first stretch of the pull, so nothing flashes at the
    // first pixel of an ordinary scroll that overshoots.
    final opacity = working || done ? 1.0 : math.min(1.0, progress * 1.6);
    return Opacity(
      opacity: opacity,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: done
                  ? const Icon(Icons.check_rounded, size: 16, color: Tones.held)
                  : CircularProgressIndicator(
                      // Filling while pulled, turning while it works.
                      value: working ? null : progress,
                      strokeWidth: 1.8,
                      color: armed ? Tones.text : Tones.primary,
                      backgroundColor: Tones.hairline,
                    ),
            ),
            const SizedBox(width: Space.sm + 2),
            Text(
              text,
              style: TypeScale.note.copyWith(
                fontSize: 14,
                color: armed || working ? Tones.text : Tones.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
