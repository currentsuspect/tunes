import 'package:flutter/widgets.dart';

/// How much of the bottom of a page the dock covers.
///
/// Zero in every look but Glass. There the shell lets pages run on under the
/// floating dock (`Scaffold.extendBody`), which reports the dock's height as
/// the body's bottom padding, so a page that ends its list with this much
/// room can still scroll its last row clear of the dock. Elsewhere the
/// Scaffold takes that padding away and this adds nothing.
double dockClearance(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// [dockClearance] as padding, to add to a list's own.
EdgeInsets dockPad(BuildContext context) =>
    EdgeInsets.only(bottom: dockClearance(context));
