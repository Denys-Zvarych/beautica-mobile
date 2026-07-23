// Widget tests for the shared "Коментар для майстра" note field
// `BookingCommentField`
// (`lib/features/booking/presentation/widgets/booking_comment_field.dart`).
//
// Extracted from the private `_CommentField` duplicated in BOTH
// `booking_confirm_screen.dart` (independent flow, field key
// `booking-confirm-comment-field`) and `salon_booking_confirm_screen.dart`
// (salon flow, key `salon-confirm-comment-field`). The refactor bakes the
// `ValueListenableBuilder` counter isolation INTO the widget so BOTH flows get
// it (the independent flow previously drove the counter via a screen-level
// `setState` listener — a regression back to that would rebuild the whole
// host on every keystroke).
//
// These pin: (1) the live "x / maxLength" counter updates as the user types,
// (2) that update is ISOLATED — typing rebuilds only the counter, NOT the
// TextField subtree (proven via the `debugPrintRebuildDirtyWidgets` proxy the
// suite already uses in `booking_summary_bar_test.dart`), and (3) each flow's
// distinct `fieldKey` addresses the exact field it always did.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_comment_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _kIndependentKey = Key('booking-confirm-comment-field');
const Key _kSalonKey = Key('salon-confirm-comment-field');

Widget _field({
  required TextEditingController controller,
  Key fieldKey = _kIndependentKey,
  int maxLength = 500,
}) {
  return Scaffold(
    body: SingleChildScrollView(
      child: BookingCommentField(
        controller: controller,
        fieldKey: fieldKey,
        maxLength: maxLength,
      ),
    ),
  );
}

void main() {
  group('BookingCommentField — counter', () {
    testWidgets('starts at "0 / maxLength" and reflects typed length', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpApp(_field(controller: controller, maxLength: 500));
      await tester.pumpAndSettle();

      // Counter label is a computed string, not app l10n copy → asserting the
      // literal is correct here (it is the value under test).
      expect(find.text('0 / 500'), findsOneWidget);

      await tester.enterText(
        find.byKey(_kIndependentKey),
        'Привіт', // 6 characters
      );
      await tester.pumpAndSettle();

      expect(find.text('6 / 500'), findsOneWidget);
      expect(find.text('0 / 500'), findsNothing);
    });

    testWidgets('honours a custom maxLength (salon flow uses its own cap)', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpApp(
        _field(controller: controller, fieldKey: _kSalonKey, maxLength: 300),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_kSalonKey), findsOneWidget);
      expect(find.text('0 / 300'), findsOneWidget);
    });
  });

  group('BookingCommentField — counter isolation', () {
    testWidgets(
      'typing rebuilds only the counter — the TextField subtree does NOT '
      'rebuild on each keystroke',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpApp(_field(controller: controller, maxLength: 500));
        await tester.pumpAndSettle();

        final List<String> rebuiltLines = <String>[];
        final DebugPrintCallback previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) rebuiltLines.add(message);
        };
        debugPrintRebuildDirtyWidgets = true;
        addTearDown(() {
          debugPrintRebuildDirtyWidgets = false;
          debugPrint = previousDebugPrint;
        });

        // Drive the controller directly (no re-pumpWidget) so ONLY listeners of
        // the controller can dirty anything — mirrors a real keystroke.
        controller.text = 'Ал';
        await tester.pump();

        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;

        // The counter must have updated (proves the ValueListenableBuilder is
        // wired to the controller at all)...
        expect(find.text('2 / 500'), findsOneWidget);

        // ...but the keyed TextField must NOT appear in that frame's rebuild
        // log — a regression back to a screen-level setState listener would
        // rebuild the whole field subtree (including this key) on every char.
        final bool fieldRebuilt = rebuiltLines.any(
          (String l) => l.contains('booking-confirm-comment-field'),
        );
        expect(
          fieldRebuilt,
          isFalse,
          reason:
              'typing must not rebuild the TextField subtree — only the '
              'ValueListenableBuilder counter should react to the controller. '
              'A rebuild of the keyed field here means the isolation regressed.',
        );
      },
    );
  });
}
