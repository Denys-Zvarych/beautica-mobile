// Phase 236 — the shared price pill.
//
// PROMOTED, NOT WRITTEN. This is `master_booking_card.dart`'s private
// `_PriceTag` lifted verbatim into `core/widgets/` and made public, so the
// wish-list surfaces and the master's day timeline render ONE pill rather than
// two that look alike today and drift apart tomorrow. Every property is
// unchanged — the `NeumorphicInset` shell at [VelvetRadii.pill], the
// [VelvetSpacing.sm] horizontal padding, the 3 dp / 1 dp vertical density
// split, the 96 dp text cap, the zero-width height anchor and the
// `Flexible` → `ConstrainedBox` → `FittedBox` overflow chain. The two
// pre-resolved `EdgeInsets` constants came across too, so the >=1h card still
// allocates nothing per build.
//
// ## THIS WIDGET NEVER FORMATS MONEY
//
// [price] arrives already formatted — «450 ₴», or a frozen band. The booking
// card feeds it `BookingDisplayX.priceLabel`; the wish list feeds it the
// backend's own `priceDisplay`. Both are snapshots. Do not add a formatter, a
// currency symbol, a separator normaliser or a rounding step here: the whole
// point of a single pill is that the separator, the rounding and the «₴»
// suffix cannot drift between the surfaces that render it.
//
// ## Why the width cap exists
//
// This pill sits beside an `Expanded` service name (compact booking card), a
// status badge (full booking card) or a duration caption (wish list). A long
// band («12500–25000 ₴») is materially wider than the single figure these
// layouts were sized around, so left unbounded it could out-measure the room
// its row has left and trip a `RenderFlex` overflow. Capping the TEXT at
// [maxTextWidth] and letting `FittedBox` scale it down keeps the pill hugging
// its content while making an overflow structurally impossible. `scaleDown`
// shrinks rather than clips, so a pathological band stays legible instead of
// losing its ceiling to an ellipsis.
//
// ## The cap is a CEILING; the incoming constraint is the real limit
//
// [maxTextWidth] alone is NOT enough, and the reason is a `RenderFlex` detail
// rather than a mis-measured constant: a `Row` lays its NON-flex children out
// with an UNBOUNDED `maxWidth`, so a pill parked as a plain non-flex child
// never sees how much room its row actually has — it always takes the full
// capped 112 dp (96 text + 2 x 8 padding). On the master timeline's narrowest
// lane (226 dp) that overflowed BOTH layouts once a frozen band was present.
// The pill's inner band is therefore a [Flexible]: whenever the pill is handed
// a bounded `maxWidth` the `FittedBox` scales into THAT instead of into a flat
// 96. Under an unbounded incoming width `Flexible` lays the child out unbounded
// exactly as a bare `ConstrainedBox` would, so it is a no-op there.

import 'package:flutter/material.dart';

import '../theme/velvet_geometry.dart';
import '../theme/velvet_text.dart';
import 'neumorphic.dart';

/// A price pill — «450 ₴», or a frozen band «300–500 ₴».
///
/// A recessed [NeumorphicInset] well at [VelvetRadii.pill] wrapping the figure
/// in [VelvetText.pill]. There is deliberately no `price` text token in the
/// scale: `velvet_text.dart` says outright that the price pill is `pill()`
/// verbatim, so this uses `pill()` and adds nothing.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.price,
    this.verticalPadding = defaultVerticalPadding,
  });

  /// The pill's default vertical padding — the approved design's own value,
  /// which the master booking card's FULL layout keeps verbatim.
  static const double defaultVerticalPadding = 3;

  /// The tighter vertical padding a dense host passes instead.
  ///
  /// 4 dp (2 x 2) is exactly what paid for the master booking card's compact
  /// hairline divider and its two gaps — see that file's "THE 41dp BUDGET"
  /// header section. It is spent on the pill rather than on a type step-down on
  /// purpose: 6 dp of the pill's 21 dp was air, and a recessed well padded for
  /// a 112 dp card is over-articulated inside a 56 dp one, whereas shrinking
  /// the type would cost the card the legibility-at-a-glance that is its entire
  /// job in a scrolling timeline. The wish list's compact card mirrors the same
  /// density split.
  static const double compactVerticalPadding = 1;

  /// Already-formatted — «450 ₴» or «300–500 ₴». This widget never formats
  /// money itself; see the file header.
  final String price;

  /// Vertical padding inside the pill. Defaults to [defaultVerticalPadding];
  /// dense hosts pass [compactVerticalPadding].
  ///
  /// A PARAMETER rather than a second widget, and defaulted so a full-density
  /// host renders byte-identically. The HEIGHT ANCHOR below is unaffected: it
  /// pins the pill's LINE box, and this knob only moves the padding around it.
  final double verticalPadding;

  /// The widest the pill's TEXT may grow before it scales down. A CAP, not a
  /// column width — a short «450 ₴» still sizes to its own content.
  ///
  /// Sized to the longest band this pill can realistically be asked to draw,
  /// «12500–25000 ₴» (5 + 5 digits), in [VelvetText.pill] (Nunito 11/w800):
  /// 83.8 dp measured, so ~12 dp of headroom under this 96
  /// (`VelvetSpacing.xxl * 2`).
  ///
  /// ## The 96 it shares with `booking_card.dart` is a COINCIDENCE — do not
  /// treat the two as one knob
  ///
  /// `booking_card.dart`'s `_priceMaxWidth` is also 96, but the two caps are
  /// equal in dp and NOT in glyphs, because that card renders its price at a
  /// different type scale (`VelvetText.bookingCardPrice`, Nunito 10/w800: the
  /// same band measures 76.96 dp there, leaving ~19 dp). A future type-scale
  /// bump therefore trips THIS pill roughly 7 dp of band-width earlier.
  /// Deliberately left as two independent constants: unifying them would encode
  /// a coupling that does not exist and would invite the exact wrong edit.
  static const double maxTextWidth = VelvetSpacing.xxl * 2; // 96

  /// The two padding values this widget is ACTUALLY built with, pre-resolved
  /// as compile-time constants (mobile-perf INFO-2).
  ///
  /// Turning the vertical inset into a FIELD cost the `EdgeInsets` its
  /// constness — one allocation per card per build. Only two values exist in
  /// the whole app, so [_resolvePadding] selects between these two instead of
  /// building a third. The knob itself stays a `double` field, so the non-const
  /// branch remains the correct fallback for any other value rather than an
  /// assert that would turn a cosmetic tweak into a crash.
  static const EdgeInsets _paddingDefault = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.sm,
    vertical: defaultVerticalPadding,
  );
  static const EdgeInsets _paddingCompact = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.sm,
    vertical: compactVerticalPadding,
  );

  EdgeInsets _resolvePadding() {
    if (verticalPadding == defaultVerticalPadding) return _paddingDefault;
    if (verticalPadding == compactVerticalPadding) return _paddingCompact;
    return EdgeInsets.symmetric(
      horizontal: VelvetSpacing.sm,
      vertical: verticalPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: _resolvePadding(),
        // HEIGHT IS PINNED INDEPENDENTLY OF THE HORIZONTAL SCALE
        // ---------------------------------------------------------------
        // `BoxFit.scaleDown` scales UNIFORMLY, so the moment [maxTextWidth]
        // binds it shrinks the band's HEIGHT by the same factor, not just its
        // width — measured: an over-cap band renders its text at 13.0 dp
        // instead of the style's natural 15.0 dp. Left alone that silently
        // drags the whole host card shorter (the master card's compact body
        // names this pill's ~20 dp row as its tallest).
        //
        // The zero-width [Text] below is a HEIGHT ANCHOR: an empty string in
        // the same [VelvetText.pill] style lays out at Size(0.0, 15.0) — no
        // width contributed to the [Row], full natural line height held. The
        // [Row] then takes the taller of (anchor, scaled band), which is the
        // anchor for every scale <= 1, so the pill keeps its natural height no
        // matter how far the band scales horizontally.
        //
        // IT MUST STAY A [Text], NOT A `SizedBox(height: 15)`. 15.0 is the line
        // height at textScaler 1.0 ONLY; a box cannot see the ambient scaler,
        // so under the app's own MediaQuery clamp (`main.dart`'s 1.3 ceiling)
        // it would under-anchor and hand the height back to the scaled band —
        // measured with the constant swapped in: at 1.1 the pill goes 23.0
        // (in-cap) vs 21.0 (over-cap), at 1.3 23.76 vs 21.0, i.e. exactly the
        // defect this anchor removes. The [Text] re-derives its height from the
        // inherited scaler on every build; a constant freezes one scale.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('', style: VelvetText.pill()),
            // [Flexible], not a bare [ConstrainedBox] — see the file header's
            // "the cap is a CEILING" section. A [Row] hands its NON-flex
            // children unbounded width, so without this the [ConstrainedBox]
            // below would resolve to a flat [maxTextWidth] even when the pill's
            // own incoming `maxWidth` is narrower than that — and the overflow
            // would simply move INSIDE the pill.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxTextWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(price, style: VelvetText.pill(), maxLines: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
