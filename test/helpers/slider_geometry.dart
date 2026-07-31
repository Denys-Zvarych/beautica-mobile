// Shared slider geometry constants for the test tiers.
//
// WHY THIS FILE EXISTS
// --------------------
// Two tests drive the price `RangeSlider` by computing an ABSOLUTE target x
// from the value they want (`_RenderRangeSlider._handleDragUpdate` reads the
// final pointer x, not the drag delta, so a relative `Offset(dx, 0)` is
// meaningless — see the header of
// `test/features/discovery/presentation/search_filters_price_slider_drag_test.dart`):
//
//     trackLeft  = sliderRect.left  + kSliderOverlayInset
//     trackWidth = sliderRect.width - 2 * kSliderOverlayInset
//     targetX    = trackLeft + (target / kSearchPriceCeiling) * trackWidth
//
// Both tiers need the same number, and they live in DIFFERENT test roots
// (`test/` and `integration_test/`). That is not an obstacle: `integration_test/`
// already imports this very directory in ~20 flows (`overflow_guard.dart`,
// `pump_app.dart`, `fakes/fake_secure_storage.dart`), and
// `integration_test/support/app_harness.dart` does the same. The import
// direction is one-way (integration_test → test), so there is no cycle. A
// second hand-copied literal, kept honest only by a pair of "keep these in
// lockstep" comments, would be strictly worse: the comments are not executable
// and the E2E tier is the one place a silent drift is most expensive to
// diagnose.
//
// WHY IT IS A HARD-CODED LITERAL AND NOT DERIVED FROM `SliderThemeData`
// ---------------------------------------------------------------------
// Deriving the inset at runtime (from `SliderTheme.of(context).overlayShape`)
// was considered and REJECTED for the widget tier: that tier's entire purpose
// is to be a PIN that goes red when the real geometry drifts. A pin that reads
// its expected value from the same source as the code under test moves in
// lockstep with it and can never fail — the classic tautological assertion.
// It is also not reliably derivable: `SliderThemeData`'s shape fields are
// nullable and the effective defaults are merged in by the widget's own
// `_RangeSliderDefaults`, not visible on the inherited theme.
//
// The pin's teeth come from the ASSERTED PRICE being hard-coded, not the inset:
// mutate [kSliderOverlayInset] and the computed x moves, the real slider maps
// it to a different price, and the assertion fails. That mutation matrix (12 →
// RED … 48 → RED, every drift ≥ 4 px caught) is recorded in the drag test's
// header and still holds through this shared constant.

/// Horizontal inset, in logical pixels, from a `RangeSlider`'s widget rect to
/// its usable TRACK, on each side.
///
/// This is the default `RoundSliderOverlayShape` radius. `_PriceSection`'s
/// local `SliderThemeData` (see
/// `lib/features/discovery/presentation/search_filters_screen.dart`) sets
/// neither `overlayShape` nor `padding`, so the framework default applies —
/// Flutter's `BaseRangeSliderTrackShape.getPreferredRect` insets the track by
/// `max(overlayWidth, thumbWidth) / 2`, and the default 48-px overlay wins over
/// the 20-px thumb.
///
/// IF THIS GOES STALE the drag-mapping pin in
/// `test/features/discovery/presentation/search_filters_price_slider_drag_test.dart`
/// turns RED first, at the fastest tier, naming itself. Do NOT chase the number
/// until it passes — fix the theme, or update this constant once (both tiers
/// read it) together with that test's expectations.
const double kSliderOverlayInset = 24;
