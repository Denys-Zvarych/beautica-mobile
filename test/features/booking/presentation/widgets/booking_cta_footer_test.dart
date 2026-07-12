// Widget tests for the shared pinned CTA footer `BookingCtaFooter`
// (`lib/features/booking/presentation/widgets/booking_cta_footer.dart`).
//
// Extracted from the byte-identical private `_CtaFooter` in BOTH
// `booking_confirm_screen.dart` (independent flow, button key
// `booking-confirm-submit-cta`) and `salon_booking_confirm_screen.dart` (salon
// flow, key `salon-confirm-submit-cta`, whose label flips «Записатись» →
// «Повторити» on a partial-failure retry). These tests pin the label /
// enabled / loading contract for BOTH composition sites via their distinct
// button keys.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_cta_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// The two production button keys, verbatim from the confirm screens.
const Key _kIndependentKey = Key('booking-confirm-submit-cta');
const Key _kSalonKey = Key('salon-confirm-submit-cta');

Widget _footer({
  required String label,
  required Key buttonKey,
  bool enabled = true,
  bool loading = false,
  VoidCallback? onPressed,
}) {
  return Scaffold(
    bottomNavigationBar: BookingCtaFooter(
      label: label,
      buttonKey: buttonKey,
      enabled: enabled,
      loading: loading,
      onPressed: onPressed ?? () {},
    ),
  );
}

void main() {
  group('BookingCtaFooter — label', () {
    testWidgets('renders the caller-driven label on the independent flow key', (
      tester,
    ) async {
      // i18n-finder-ok: fixture label supplied by the test, not app copy.
      await tester.pumpApp(
        _footer(label: 'Записатись', buttonKey: _kIndependentKey),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_kIndependentKey), findsOneWidget);
      // i18n-finder-ok: fixture label supplied by the test, not app copy.
      expect(find.text('Записатись'), findsOneWidget);
    });

    testWidgets('the salon flow can flip the label to «Повторити» on its own '
        'distinct button key', (tester) async {
      await tester.pumpApp(_footer(label: 'Повторити', buttonKey: _kSalonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_kSalonKey), findsOneWidget);
      // i18n-finder-ok: fixture retry label, not app copy.
      expect(find.text('Повторити'), findsOneWidget);
    });
  });

  group('BookingCtaFooter — enabled / tap', () {
    testWidgets('fires onPressed when enabled', (tester) async {
      int taps = 0;
      await tester.pumpApp(
        _footer(
          label: 'Записатись',
          buttonKey: _kIndependentKey,
          onPressed: () => taps++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kIndependentKey));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('does not fire onPressed when disabled', (tester) async {
      int taps = 0;
      await tester.pumpApp(
        _footer(
          label: 'Записатись',
          buttonKey: _kIndependentKey,
          enabled: false,
          onPressed: () => taps++,
        ),
      );
      await tester.pumpAndSettle();

      // The inner NeumorphicButton receives a null onPressed when disabled, so
      // no gesture fires.
      final NeumorphicButton button = tester.widget<NeumorphicButton>(
        find.byKey(_kIndependentKey),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(_kIndependentKey), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);
    });
  });

  group('BookingCtaFooter — loading', () {
    testWidgets('swaps the check glyph for a spinner while loading', (
      tester,
    ) async {
      await tester.pumpApp(
        _footer(label: 'Надсилаємо…', buttonKey: _kSalonKey, loading: true),
      );
      await tester.pump(); // don't settle — the spinner animates forever.

      // loading: true → the CTA icon is dropped and a spinner takes over.
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the check glyph (no spinner) when not loading', (
      tester,
    ) async {
      await tester.pumpApp(
        _footer(label: 'Записатись', buttonKey: _kIndependentKey),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
