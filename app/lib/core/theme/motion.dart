import 'package:flutter/material.dart';

/// Motion vocabulary — screens never invent their own curves.
/// M0 set: micro (press/settle), standard (transitions), sheet.
abstract final class Motion {
  static const micro = Duration(milliseconds: 110);
  static const standard = Duration(milliseconds: 220);
  static const sheet = Duration(milliseconds: 300);

  static const curve = Curves.easeOutCubic;
  static const sheetCurve = Curves.easeInOutCubic;

  static Duration duration(Duration d, MediaQueryData mq) =>
      mq.disableAnimations ? Duration.zero : d;
}