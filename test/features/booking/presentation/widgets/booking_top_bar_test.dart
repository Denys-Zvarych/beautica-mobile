// mobile-qa Part 1 — regression test for `BookingTopBar` (the shared
// back-button + centered-title top bar extracted for `SlotDateScreen` /
// `SlotTimeScreen` / `BookingConfirmScreen`, see the widget's own file
// header).
//
// BUG THIS GUARDS AGAINST: the two donor widgets it replaced
// (`slot_picker_screen.dart`'s `_BookingTopBar`, `booking_confirm_screen.dart`
// 's `_TopBar`) each rendered an UNCONSTRAINED `Text` (no `maxLines`, no
// `overflow`) centered via `Stack(alignment: Alignment.center, children:
// [Align(centerLeft, backButton), Text(title)])`. `Stack.alignment` centers a
// non-positioned child's bounding box within the FULL stack width, not the
// space remaining after the back button — so a long title (or a large
// accessibility text scale) that needed its full available width to lay out
// produced a title box whose LEFT edge coincided with the stack's own left
// edge, genuinely overlapping the back button's box. Empirically verified
// against a reconstruction of the old `_TopBar` (same title/width/text-scale
// fixture used below): `titleRect == Rect.fromLTRB(24, 8, 296, 56)` versus
// `backRect == Rect.fromLTRB(24, 8, 72, 56)` — a real, non-hypothetical
// overlap, not merely a hypothetical concern.
//
// THE FIX under test: `BookingTopBar` lays the back button and title out as
// Row siblings — a fixed 48dp box for the back button, an `Expanded` +
// `Center` slot for the title with `maxLines: 1` / `TextOverflow.ellipsis` —
// so the title's render box can never extend into the back button's
// reserved column, by construction of the Row/Expanded layout itself.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  group('BookingTopBar', () {
    const String kLongTitle =
        'Дуже довга назва екрану підтвердження запису до майстра';

    testWidgets(
      'a long title at a narrow width and large text scale never renders '
      'overlapping the back button',
      (tester) async {
        await tester.pumpApp(
          Scaffold(
            body: BookingTopBar(
              title: kLongTitle,
              backSemantics: 'Назад',
              onBack: () {},
              backKey: const Key('top-bar-back'),
            ),
          ),
          // Same stress fixture used to empirically reproduce the overlap
          // against the OLD Stack-based layout: 320dp width + 2.0x text
          // scale is enough to force the title to need its full available
          // width, which is exactly the condition that exposed the bug.
          width: 320,
          textScaleFactor: 2.0,
        );
        await tester.pumpAndSettle();

        final Finder backButton = find.byKey(const Key('top-bar-back'));
        final Finder titleText = find.text(kLongTitle);
        expect(backButton, findsOneWidget);
        expect(titleText, findsOneWidget);

        final Rect backRect = tester.getRect(backButton);
        final Rect titleRect = tester.getRect(titleText);

        expect(
          titleRect.overlaps(backRect),
          isFalse,
          reason:
              'BookingTopBar reserves a fixed 48dp Row slot for the back '
              'button and lays the title out in a separate Expanded slot — '
              'the two render boxes must never intersect. Against the PRIOR '
              'Stack-based `_TopBar`/`_BookingTopBar` layout, this exact '
              'title/width/text-scale fixture produces a title rect '
              '(Rect.fromLTRB(24, 8, 296, 56)) that genuinely overlaps the '
              'back button rect (Rect.fromLTRB(24, 8, 72, 56)) — see this '
              'file\'s header for how that was verified.',
        );

        // Safety-net structural check: the ellipsis/single-line constraint
        // is the concrete mechanism that keeps the title's box bounded to
        // its Expanded slot instead of relying on the Row alone — pin it
        // directly so a future edit that drops `maxLines`/`overflow` (while
        // keeping the Row) is still caught even if it doesn't happen to
        // visually overlap for this particular fixture.
        final Text titleWidget = tester.widget<Text>(titleText);
        expect(titleWidget.maxLines, 1);
        expect(titleWidget.overflow, TextOverflow.ellipsis);
      },
    );

    testWidgets(
      'renders the given title and routes a back tap through onBack',
      (tester) async {
        // `BookingTopBar` never looks up its own `title` — it's an opaque
        // caller-supplied String (the real screens pass an
        // `AppLocalizations`-sourced value; `BookingConfirmScreen`'s exact
        // ARB literal is separately pinned in `booking_confirm_test.dart`).
        // This test only proves "renders the given title", so an
        // ASCII placeholder keeps the fixture obviously arbitrary instead of
        // reading like a second, redundant ARB-lock assertion.
        const String kTitle = 'Screen Title';
        int backTaps = 0;
        await tester.pumpApp(
          Scaffold(
            body: BookingTopBar(
              title: kTitle,
              backSemantics: 'Назад',
              onBack: () => backTaps++,
              backKey: const Key('top-bar-back'),
            ),
          ),
        );

        expect(find.text(kTitle), findsOneWidget);

        await tester.tap(find.byKey(const Key('top-bar-back')));
        await tester.pump();

        expect(backTaps, 1);
      },
    );
  });
}
