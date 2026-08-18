// Phase 236 — [WishlistCountPill].

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_count_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

BoxDecoration _decoration(WidgetTester tester) {
  final Container box = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(WishlistCountPill),
          matching: find.byType(Container),
        )
        .first,
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  testWidgets('renders the count verbatim', (WidgetTester tester) async {
    await tester.pumpApp(
      const Center(child: WishlistCountPill(count: 12)),
      width: 320,
    );
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a zero count still renders — never blank', (
    WidgetTester tester,
  ) async {
    // The caller decides whether to SHOW the pill; the pill itself must not
    // second-guess that by rendering nothing and leaving a gap in the header.
    await tester.pumpApp(
      const Center(child: WishlistCountPill(count: 0)),
      width: 320,
    );
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('it is camel-tinted and fully rounded', (
    WidgetTester tester,
  ) async {
    await tester.pumpApp(
      const Center(child: WishlistCountPill(count: 3)),
      width: 320,
    );
    final BoxDecoration d = _decoration(tester);

    // Fill and stroke are both the camel accent at different alphas — the
    // stroke must be the STRONGER of the two or the pill reads as a flat blob.
    expect(d.color!.r, closeTo(BrandColors.accent.r, 0.001));
    expect(d.color!.a, lessThan(1.0));
    final BorderSide side = (d.border! as Border).top;
    expect(side.color.r, closeTo(BrandColors.accent.r, 0.001));
    expect(
      side.color.a,
      greaterThan(d.color!.a),
      reason: 'the border must be more opaque than the fill',
    );

    expect(
      (d.borderRadius! as BorderRadius).topLeft.x,
      VelvetRadii.pill,
      reason: 'the counter is a pill, not a rounded square',
    );
  });

  testWidgets('it stays shorter than the section title it trails', (
    WidgetTester tester,
  ) async {
    // The whole reason its vertical padding sits below the AppSpacing floor:
    // a 4dp inset makes the chip taller than the header's own line box and
    // breaks the baseline the section header is built on.
    await tester.pumpApp(
      const Center(child: WishlistCountPill(count: 99)),
      width: 320,
    );
    expect(tester.getSize(find.byType(WishlistCountPill)).height, lessThan(24));
  });
}
