// Tests for the layout breakpoint extension on BuildContext. Each case pumps a
// widget under a MediaQuery of a chosen width and reads the getters, covering
// the exact boundary values so an off-by-one in the breakpoints is caught.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/responsive.dart';

void main() {
  /// Pumps at [width] and runs [check] with a context under that MediaQuery.
  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    void Function(BuildContext context) check,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (context) {
            check(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets('below the medium breakpoint the layout is compact',
      (tester) async {
    await pumpAtWidth(tester, 500, (context) {
      expect(context.isCompact, isTrue);
      expect(context.isExpandedWidth, isFalse);
      expect(context.isLargeWidth, isFalse);
    });
  });

  testWidgets('just below medium (759) is still compact', (tester) async {
    await pumpAtWidth(tester, Breakpoints.medium - 1, (context) {
      expect(context.isCompact, isTrue);
      expect(context.isExpandedWidth, isFalse);
    });
  });

  testWidgets('at the medium breakpoint (760) the layout expands',
      (tester) async {
    await pumpAtWidth(tester, Breakpoints.medium, (context) {
      expect(context.isCompact, isFalse);
      expect(context.isExpandedWidth, isTrue);
      expect(context.isLargeWidth, isFalse); // not yet large
    });
  });

  testWidgets('just below the expanded breakpoint (1099) is not large',
      (tester) async {
    await pumpAtWidth(tester, Breakpoints.expanded - 1, (context) {
      expect(context.isExpandedWidth, isTrue);
      expect(context.isLargeWidth, isFalse);
    });
  });

  testWidgets('at the expanded breakpoint (1100) the rail is large',
      (tester) async {
    await pumpAtWidth(tester, Breakpoints.expanded, (context) {
      expect(context.isCompact, isFalse);
      expect(context.isExpandedWidth, isTrue);
      expect(context.isLargeWidth, isTrue);
    });
  });
}
