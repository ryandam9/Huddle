import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/widgets.dart';

/// True on the desktop platforms, where native directory picking is available
/// and folder-based workflows make sense (mobile gets multi-select instead).
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Layout breakpoints used to adapt the UI between phones, tablets and desktop.
class Breakpoints {
  /// At or above this width we switch from a bottom nav bar to a side rail and
  /// enable two-pane (master-detail) layouts.
  static const double medium = 760;

  /// At or above this width the navigation rail shows labels (extended).
  static const double expanded = 1100;
}

extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  /// Compact phone-style layout: bottom navigation, single pane.
  bool get isCompact => _width < Breakpoints.medium;

  /// Tablet/desktop layout: navigation rail + master-detail panes.
  bool get isExpandedWidth => _width >= Breakpoints.medium;

  /// Very wide: show an extended (labelled) navigation rail.
  bool get isLargeWidth => _width >= Breakpoints.expanded;
}
