// Phase 14.3 — shared "Додати в календар" button.
//
// Promoted out of `booking_success_screen.dart`'s old `_CalendarLink` (a
// borderless text link) into a real, findable BUTTON — a raised neumorphic
// pill in the base tone with a hairline camel edge, deliberately the
// QUIETEST *raised* control in the palette so it reads unmistakably as a
// button without outranking whatever primary action sits below it in a
// pinned footer.
//
// ## ⚠ Why the old text link had to go — on BOTH success screens, not just
//    the detail screen
//
// If a borderless link was too easy to miss on «Деталі запису», it was too
// easy to miss on the success screen too — arguably MORE so, since the
// success screen is the FIRST place a client would ever add the appointment
// to their calendar, and there it competes with a celebration for attention.
// Leaving it split — a link on success, a button on detail — would give ONE
// action two different visual weights inside a single feature, which is
// exactly the drift `BookingSuccessScaffold`'s shared `belowRecap` slot
// exists to prevent. So this widget is now the ONE calendar affordance,
// used from that same slot on all three screens
// (`booking_success_screen.dart`, `salon_booking_success_screen.dart` has no
// analogue since a salon booking has no single "the" appointment, and
// `booking_detail_screen.dart`).
//
// Its action is wired to the `add_2_calendar` (^3.1.1) package: tapping opens
// the OS "new event" editor pre-filled from the booking. The `onTap` callback
// is supplied by each call site.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

class CalendarButton extends StatefulWidget {
  const CalendarButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<CalendarButton> createState() => _CalendarButtonState();
}

class _CalendarButtonState extends State<CalendarButton> {
  // Compile-time constant so the whole BorderRadius is const on the single
  // decoration that carries the fill colour, border and shadow together.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.button),
  );

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.bookingAddCalendarSemantics,
      child: GestureDetector(
        key: const Key('booking-add-calendar'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        // IMPELLER-GLES CORNER FIX: `extrudedButton` pairs a dark shadow with a
        // near-white light shadow (`shadowLightStrong`, alpha FF) at a diagonal
        // `Offset(-6,-6)`. Impeller's OpenGLES backend rasterizes that offset
        // opaque rrect's untranslated corner as a crisp white SQUARE poking past
        // the button's rounded corner onto the taupe `base`. The remedy is the
        // button-scaled `borderedButton` recipe: a single NON-offset,
        // semi-transparent dark shadow whose rrect footprint exactly matches the
        // button (uniform soft halo, no protruding corner), paired with the
        // camel hairline border this button already carries. No shadow while
        // pressed, so the control reads as depressed.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: _radius,
            border: Border.all(
              color: BrandColors.accent.withValues(alpha: 0.35),
            ),
            boxShadow: _pressed ? null : VelvetShadows.borderedButton,
          ),
          child: SizedBox(
            height: VelvetSizes.cta,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 17,
                    color: BrandColors.accentDeep,
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Flexible(
                    child: Text(
                      l10n.bookingSuccessAddCalendarCta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.bookCalendarCta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
