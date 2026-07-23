// Phase 14.3 — the «Додати в календар» pill on the booking-success recap: one
// compact, CARD-SCOPED button per confirmed appointment.
//
// ## Why it is card-scoped, and why there is no page-level variant
//
// The multi-service rework made the booking-success recap ONE CARD PER
// CONFIRMED APPOINTMENT, and the OS INSERT sheet takes exactly one event per
// invocation — so a single page-level pill could only ever seed ONE of N, a
// control that silently does less than it appears to. Every appointment card
// therefore carries its own button (`BookingSummaryCards.trailingAction`) and
// the page-level pill below the recap is GONE (so is the scaffold slot it sat
// in), including for N == 1: one rule, one layout to maintain rather than
// "bottom pill when N == 1, per-card pills otherwise".
//
// That is also why this widget has exactly ONE weight. N full-bleed
// [VelvetSizes.cta] pills stacked down a recap would be a wall of buttons,
// each carrying the same visual weight as the pinned «На головну» footer CTA.
// So the pill hugs its label and sits flush right, on the card's right-hand
// value column where every `LabelledRow` above it already terminates, instead
// of stretching edge to edge. Height stays [VelvetSizes.cta] so the touch
// target never shrinks; only the WIDTH gives way. That leaves the pinned
// footer as the only full-width control on the screen, which is what keeps it
// primary. A full-width variant existed before the rework and was removed
// alongside that page-level slot — do not reintroduce one without a second
// call site to justify it.
//
// Visually it is the QUIETEST *raised* control in the palette — base fill,
// camel hairline, `borderedButton` halo — so it reads unmistakably as a button
// without outranking that footer CTA.
//
// NOT the app's only calendar entry point, but its only [CalendarButton]:
// «Деталі запису» offers the same action through its own header affordance
// (`booking_detail_screen.dart`). Both funnel into the shared
// `addBookingToCalendar` helper, which opens the OS "new event" editor
// pre-filled from the booking. [CalendarButton.onTap] is supplied by the call
// site; because several of these coexist on one screen, the call site MUST
// also supply a per-appointment key and screen-reader label.

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

class CalendarButton extends StatefulWidget {
  const CalendarButton({
    super.key,
    required this.onTap,
    required this.buttonKey,
    required this.semanticsLabel,
  });

  final VoidCallback onTap;

  /// The tappable [GestureDetector]'s key. REQUIRED and per-appointment: the
  /// booking-success recap renders one of these per confirmed appointment, so
  /// a shared key would make the duplicates indistinguishable to `find.byKey`.
  final Key buttonKey;

  /// Screen-reader label. REQUIRED and service-qualified (see
  /// [AppLocalizations.bookingAddCalendarServiceSemantics]) so each button
  /// announces WHICH appointment it adds — a generic label would leave N
  /// identically-announced buttons on one screen.
  final String semanticsLabel;

  @override
  State<CalendarButton> createState() => _CalendarButtonState();
}

class _CalendarButtonState extends State<CalendarButton> {
  // Compile-time constant so the whole BorderRadius is const on the single
  // decoration that carries the fill colour, border and shadow together.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.button),
  );

  // The pill is sized BY its label row, so without side padding the label
  // would sit flush against the camel hairline.
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.md,
  );

  /// Glyph + label — everything that does NOT depend on [_pressed]. Built once
  /// per dependency change (it reads only [AppLocalizations]) and handed to the
  /// [AnimatedContainer] as its `child`, so the two `setState`s a single tap
  /// fires (`onTapDown`, then EITHER `onTapUp` OR `onTapCancel` — never both)
  /// rebuild the decoration alone instead of the icon and text too.
  ///
  /// `late` is safe here: [didChangeDependencies] always runs before the first
  /// [build], and it is non-`final` precisely so a locale change can rebuild it.
  late Widget _content;

  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _content = SizedBox(
      height: VelvetSizes.cta,
      child: Padding(
        padding: _padding,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                // Same «calendar_add_on» (rounded cut) glyph as the
                // booking-detail header affordance, so the calendar-with-«+»
                // reads consistently across every calendar entry point.
                Symbols.calendar_add_on_rounded,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // `Align` (not `Row`) so the pill sizes to its intrinsic width and lands on
    // the card's right-hand value column, where every LabelledRow above it
    // already terminates.
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        label: widget.semanticsLabel,
        child: GestureDetector(
          key: widget.buttonKey,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          // IMPELLER-GLES CORNER FIX: `extrudedButton` pairs a dark shadow with
          // a near-white light shadow (`shadowLightStrong`, alpha FF) at a
          // diagonal `Offset(-6,-6)`. Impeller's OpenGLES backend rasterizes
          // that offset opaque rrect's untranslated corner as a crisp white
          // SQUARE poking past the button's rounded corner onto the taupe
          // `base`. The remedy is the button-scaled `borderedButton` recipe: a
          // single NON-offset, semi-transparent dark shadow whose rrect
          // footprint exactly matches the button (uniform soft halo, no
          // protruding corner), paired with the camel hairline border this
          // button already carries. No shadow while pressed, so the control
          // reads as depressed.
          //
          // PRESS FEEL: mirrors the canonical `NeumorphicButton` depress — an
          // `AnimatedScale` to 0.97 over 120 ms `easeOut`, springing back on
          // release, combined with the shadow clearing while pressed so the
          // scale and the softening halo read together.
          //
          // The `RepaintBoundary` sits ABOVE the `AnimatedScale`, never below
          // it. Three reasons, and they have each been re-litigated once — do
          // NOT "tidy" the boundary back under the transform:
          //   1. `RenderTransform` is NOT itself a repaint boundary, so its
          //      per-frame `markNeedsPaint` walks to the nearest ANCESTOR
          //      boundary. With the boundary above, that ancestor is this
          //      widget's own; move it below and the walk escapes to the
          //      scaffold's per-card `_reveal` boundary
          //      (`booking_success_scaffold.dart`), so the 120 ms press
          //      re-records the WHOLE `NeumorphicCard` — border, neumorphic
          //      halo, every `LabelledRow`, the price recap — each frame.
          //   2. An inner boundary would cache nothing anyway: the
          //      `AnimatedContainer` lerps its `boxShadow` over 150 ms, LONGER
          //      than the 120 ms scale, so the child is dirty on every frame of
          //      the depress. There is no sub-scale during which it is static.
          //   3. A boundary below the transform flips
          //      `RenderTransform.needsCompositing`, so `pushTransform`
          //      allocates a real `TransformLayer` per button — N extra
          //      composited layers for the life of the screen, not just while
          //      pressed.
          child: RepaintBoundary(
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
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
                child: _content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
