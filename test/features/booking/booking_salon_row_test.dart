// Phase 293 — coverage for the promoted `BookingSalonRow`, extracted verbatim
// out of `BookingCard`'s private `_identity()` helper (lines 374-400 before
// this phase). Pins the two things that made this row worth promoting rather
// than re-deriving: the storefront glyph is always present, and the name
// truncates to a single line instead of wrapping — so a future caller
// (`MasterBookingCard`, phase 294) inherits the exact same contract instead
// of hand-copying it and drifting.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_salon_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('renders the storefront glyph and the salon name', (
    tester,
  ) async {
    await tester.pumpApp(
      const Scaffold(body: BookingSalonRow(salonName: 'Lviv Nails Studio')),
    );

    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    expect(find.text('Lviv Nails Studio'), findsOneWidget);
  });

  // LAYOUT-level pins, not widget-field reads (project_widget_field_assertion_
  // is_vacuous.md): a field read like `icon.size == 12.0` only proves the
  // WIDGET was constructed with that argument, never that it painted at that
  // size. `tester.getSize`/`getTopLeft`/`getTopRight` read the actual laid-out
  // RenderBox geometry, so these two assertions are what the icon-size-12→20
  // mutation (see the QA report) actually turns red — the old field-only test
  // above stayed green through that exact mutation.
  testWidgets('storefront glyph paints at 12x12 with a 3dp gap to the name', (
    tester,
  ) async {
    await tester.pumpApp(
      const Scaffold(body: BookingSalonRow(salonName: 'Lviv Nails Studio')),
    );

    final Size iconSize = tester.getSize(find.byIcon(Icons.storefront_rounded));
    expect(iconSize, const Size(12, 12));

    final double iconRightEdge = tester
        .getTopRight(find.byIcon(Icons.storefront_rounded))
        .dx;
    final double nameLeftEdge = tester
        .getTopLeft(find.text('Lviv Nails Studio'))
        .dx;
    expect(nameLeftEdge - iconRightEdge, 3);
  });

  testWidgets('name Text truncates to a single line with ellipsis', (
    tester,
  ) async {
    await tester.pumpApp(
      const Scaffold(
        body: BookingSalonRow(
          salonName: 'A Very Long Salon Name That Would Otherwise Wrap',
        ),
      ),
      width: 220,
    );

    final Text name = tester.widget<Text>(
      find.text('A Very Long Salon Name That Would Otherwise Wrap'),
    );

    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('dimmed swaps the glyph and text to the muted/faint palette', (
    tester,
  ) async {
    await tester.pumpApp(
      const Scaffold(body: BookingSalonRow(salonName: 'Studio')),
    );
    final Icon liveIcon = tester.widget<Icon>(
      find.byIcon(Icons.storefront_rounded),
    );
    final Text liveText = tester.widget<Text>(find.text('Studio'));

    await tester.pumpApp(
      const Scaffold(body: BookingSalonRow(salonName: 'Studio', dimmed: true)),
    );
    final Icon dimmedIcon = tester.widget<Icon>(
      find.byIcon(Icons.storefront_rounded),
    );
    final Text dimmedText = tester.widget<Text>(find.text('Studio'));

    expect(liveIcon.color, BrandColors.accent.withValues(alpha: 0.9));
    expect(dimmedIcon.color, BrandColors.faint);
    expect(liveText.style?.color, BrandColors.textSecondary);
    expect(dimmedText.style?.color, BrandColors.muted);
  });
}
