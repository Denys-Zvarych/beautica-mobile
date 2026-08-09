// Phase 224 — the identity-card address block, shared by the own-profile
// (`master_profile_screen.dart`) and public (`public_master_profile_screen.dart`)
// master screens.
//
// WHAT CHANGED AND WHY
// --------------------
// Phase 220 split the address into two independent rows so each got its own
// line budget: locality (city) beside the pin, then street + building indented
// underneath. That is the right answer for a long address, but it spends two
// rows on «Київ, вул. Хрещатик, 22» — a string that comfortably fits on one
// line in the identity card's right-hand column. Phase 224 measures the
// collapsed string at the REAL available width and renders it as a single
// icon-bearing row when it fits, falling back to Phase 220's exact two-row
// split when it does not. Nothing is truncated that was not truncated before:
// the single-line path is only taken when the whole string demonstrably fits.
//
// WHY IT LIVES HERE AND NOT IN EACH SCREEN
// ----------------------------------------
// Phase 220 deleted a copy-pasted `_buildLocationLine` from both screens
// precisely so this composition could not drift between them. Measure-and-
// choose is strictly more logic than that helper was, so it is extracted once
// rather than duplicated twice. The *formatter* stays in `shared/formatters/`
// because the salon feature consumes it too; this *widget* is master-only, so
// it is co-located with its two call sites.
//
// The two screens differ only in their key prefix and their pin glyph (an
// `AppIcon` on the own-profile screen, a Material `Icon` on the public one),
// so both are parameters.
//
// VISUAL RHYTHM IS IDENTICAL ACROSS BOTH PATHS
// --------------------------------------------
// The split path's 16dp indent on row 2 is exactly [iconSize] + [iconGap],
// so the street text hangs on the same left edge as the locality text above
// it — and, in the collapsed path, as the combined text. Whichever path runs,
// the address column starts at the same x. The note row (owned by the call
// sites) keeps its own `EdgeInsets.only(left: 16)` and therefore stays aligned
// under both. The only difference between the paths is that the collapsed one
// is a row shorter, which is the entire point.

import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Renders a master's address inside the profile identity card, collapsing it
/// onto one line when it fits and splitting it over two when it does not.
///
/// Callers pass all three pre-composed strings from
/// `shared/formatters/address_lines.dart` — this widget never composes text
/// itself, it only chooses which composition to show.
///
/// KNOWN, ACCEPTED CONSEQUENCE — BIDI REORDERING ACROSS THE SEPARATORS
/// -------------------------------------------------------------------
/// The collapsed path renders city + street + building as ONE bidi paragraph
/// where the split path rendered two. Explicit direction controls
/// (LRO/RLO/LRE/RLE/PDF, the isolates, LRM/RLM/ALM) are already stripped by
/// `sanitizeDisplayText` before any of these strings arrive, so the classic
/// override attack cannot reach this widget. What one paragraph DOES newly
/// permit is IMPLICIT reordering: the Unicode Bidirectional Algorithm resolves
/// neutrals (the `", "` separators, digits in a building number) against their
/// surrounding runs, and a strong-RTL run is legal in `street` — the backend's
/// `@Pattern` only bars ASCII `\p{Cntrl}`. Per-row rendering used to contain
/// that resolution inside each row; now it can move a neutral across a
/// separator.
///
/// Accepted, not mitigated: the base direction is pinned to
/// `Directionality.of(context)` (LTR in this app) for both the measurement and
/// the render, so the blast radius is a mis-ordered address STRING — no
/// spoofed adjacent widget, no escaped markup (a `Text` has none to
/// re-interpret), no effect outside this one paragraph. Splitting the address
/// back into per-run isolates would defeat the entire point of collapsing it.
///
/// LAYOUT CONSTRAINT — NO INTRINSICS ABOVE THIS WIDGET
/// ---------------------------------------------------
/// The both-fields path is a [LayoutBuilder], which asserts if an ancestor
/// asks it for an intrinsic dimension. Verified safe at both call sites today:
/// the block sits inside the identity card (section 1 of each profile
/// [Column]), while the only `IntrinsicHeight` on either screen wraps the 4-up
/// stats row (section 2) — a SIBLING, not an ancestor
/// (`master_profile_screen.dart:461`, `public_master_profile_screen.dart:436`).
/// Moving this block under an `IntrinsicHeight`/`IntrinsicWidth`, or into a
/// `Row`/`Column` whose own parent measures intrinsics, would crash in debug;
/// measure into a `SizedBox`/`ConstrainedBox` instead.
class MasterAddressBlock extends StatelessWidget {
  const MasterAddressBlock({
    super.key,
    required this.keyPrefix,
    required this.icon,
    required this.localityLine,
    required this.streetLine,
    required this.combinedLine,
  });

  /// Key namespace for this screen's address widgets — `'master-profile'` or
  /// `'public-master-profile'`. Produces `<prefix>-locality-text`,
  /// `<prefix>-address-text` and `<prefix>-address-combined-text`.
  ///
  /// Keys stay CONTENT-scoped, never position-scoped (Phase 220 decision 3):
  /// `-locality-text` always means "the city, alone on its row",
  /// `-address-text` always means "the street line, alone on its row", and the
  /// new `-address-combined-text` always means "city + street + building, all
  /// on one row". A key never denotes two different things.
  final String keyPrefix;

  /// The pin glyph. MUST render at [iconSize] square — the fit measurement
  /// subtracts exactly that much from the available width, so an icon of a
  /// different size would silently make the measurement lie.
  final Widget icon;

  /// `buildLocalityLine(city)` — the city alone, or `null`.
  final String? localityLine;

  /// `buildStreetLine(street, buildingNo)` — street + building, or `null`.
  final String? streetLine;

  /// `buildCombinedAddressLine(city, street, buildingNo)` — the whole address
  /// on one line. Non-null by construction: the call site only builds this
  /// widget when the combined line exists, which is exactly when at least one
  /// of [localityLine] / [streetLine] exists.
  final String combinedLine;

  /// Side length of the pin glyph, in logical pixels.
  ///
  /// Exposed so the call sites size their icon from the same constant the fit
  /// measurement subtracts, instead of two independent `13`s drifting apart.
  static const double iconSize = 13;

  /// Gap between the pin and the first character of the address, in logical
  /// pixels.
  ///
  /// Exposed for TESTS, not for call sites (which never place the pin
  /// themselves — [_primaryRow] does). `master_address_block_test.dart` has to
  /// compute a fixture width that lands inside the narrow band where the raw
  /// and effective text styles disagree, and to do that it must subtract
  /// exactly the same gap [_fitsOnOneLine] subtracts. Mirroring the value there
  /// as a literal was strictly worse than useless: changing this constant would
  /// not have FAILED that test, it would have shifted the fixture width off the
  /// boundary so the test kept passing while exercising nothing. One constant,
  /// one source of truth, so the boundary test tracks the boundary.
  @visibleForTesting
  static const double iconGap = 3;

  /// Left indent of the split path's second row — [iconSize] + [iconGap], so
  /// row 2's text aligns under row 1's text rather than under the pin.
  static const double _kIndent = iconSize + iconGap;

  /// Vertical gap between the split path's two rows.
  static const double _kRowGap = 2;

  @override
  Widget build(BuildContext context) {
    final String? locality = localityLine;
    final String? street = streetLine;

    // THE STYLE THE PAINTER MEASURES MUST BE THE STYLE THE GLYPHS RENDER AT.
    //
    // `Text` does not hand its `style` straight to the paragraph: when the
    // style is `inherit: true` — which every `VelvetText` static is, being
    // built from `GoogleFonts.nunito(...)` — it renders
    // `DefaultTextStyle.of(context).style.merge(style)` instead. That ambient
    // default is real and non-empty here: `useMaterial3: true` gives M3
    // typography, whose `bodyMedium` carries `letterSpacing: 0.25` (preserved
    // through `GoogleFonts.nunitoTextTheme()`), and the `Scaffold` above us
    // installs it as a `DefaultTextStyle` via its `Material`.
    // `feedbackMutedXs` sets no `letterSpacing`, so the merge KEEPS 0.25.
    //
    // Measuring with the raw static therefore undercounted by
    // `0.25 × glyphCount` — ~5.75 px on a 23-character address, ~4 % of the
    // ~134 px budget this block gets in the identity card. An address landing
    // in that band was classified "fits", then ellipsized for real, silently
    // dropping the building number — the exact opposite of this widget's
    // contract that the collapsed path is only taken when nothing is clipped.
    //
    // Resolving ONCE here and passing the SAME `TextStyle` to both the
    // `TextPainter` and every `Text` below makes the two physically incapable
    // of disagreeing. The merged result has `inherit: false` (M3's typography
    // styles do), so `Text` uses it verbatim rather than merging again — and
    // even if a future theme flipped that, `merge` is idempotent here.
    // Resolving in `build` (not inside the `LayoutBuilder` callback) also
    // registers the inherited-widget dependency, so a theme change rebuilds
    // and re-measures.
    final TextStyle effectiveStyle = DefaultTextStyle.of(
      context,
    ).style.merge(VelvetText.feedbackMutedXs);

    return switch ((locality, street)) {
      // Defensive only — the call sites gate on the combined line being
      // non-null, which cannot happen with both of these null.
      (null, null) => const SizedBox.shrink(),

      // ONE field present: there is no two-row split to collapse, because
      // today's rendering is ALREADY a single row. Phase 220 decision 2
      // ("promotion, not omission") is untouched here — the lone line keeps
      // its own content-scoped key and never becomes `-address-combined-text`.
      (final String city, null) => _primaryRow(
        text: city,
        textKey: Key('$keyPrefix-locality-text'),
        style: effectiveStyle,
      ),
      (null, final String road) => _primaryRow(
        text: road,
        textKey: Key('$keyPrefix-address-text'),
        style: effectiveStyle,
      ),

      // BOTH present: measure, then choose.
      (final String city, final String road) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            _fitsOnOneLine(context, constraints.maxWidth, effectiveStyle)
            ? _primaryRow(
                text: combinedLine,
                textKey: Key('$keyPrefix-address-combined-text'),
                style: effectiveStyle,
              )
            : _splitRows(city, road, effectiveStyle),
      ),
    };
  }

  /// Whether [combinedLine] renders within a single line at [maxWidth].
  ///
  /// Lays a [TextPainter] out over the combined string at `maxLines: 1` using
  /// the SAME resolved [style] and the SAME [TextScaler] the real [Text] will
  /// use, against the width the `Flexible` below will actually receive —
  /// [maxWidth] minus the pin ([iconSize]) and the gap ([iconGap]). That is
  /// the identical input `RenderParagraph` gets, so `didExceedMaxLines` is a
  /// faithful prediction of the rendered result rather than a character-count
  /// guess: `false` means the string fits whole and nothing is clipped.
  ///
  /// [style] MUST be the already-merged effective style from `build`, never a
  /// raw `VelvetText` static — see the long note there for the letter-spacing
  /// undercount that measuring the raw static produced.
  ///
  /// NOT MEMOISED, AND THAT IS ALREADY OPTIMAL — do not "optimise" this into a
  /// static cache. The [LayoutBuilder] callback IS the memo: it re-runs only
  /// when the element is dirty or the incoming constraints actually changed
  /// (`layout_builder.dart` — `_needsBuild || layoutInfo != _previousLayoutInfo`),
  /// so this already runs at most once per real width change, and a cache
  /// keyed on (text, width, scale, style) would save ~0 work while adding a
  /// 4-part key to keep correct.
  ///
  /// (An earlier revision of this comment claimed the cache was unsafe because
  /// `google_fonts` resolves Nunito asynchronously. That rationale does not
  /// apply here and is in fact inverted: `main.dart` pre-warms
  /// `GoogleFonts.nunito` at this very weight and awaits
  /// `GoogleFonts.pendingFonts()` BEFORE `runApp`, so there is no font swap to
  /// survive at this call site — and if one did happen, it would fire
  /// `RenderParagraph.systemFontsDidChange()` → `markNeedsLayout()`, which
  /// sets neither of the two flags above and so would NOT re-run this callback
  /// anyway. The hook to listen on, if a future phase ever needs one, is
  /// `PaintingBinding.instance.systemFonts`, a [Listenable].)
  bool _fitsOnOneLine(BuildContext context, double maxWidth, TextStyle style) {
    // An unbounded or degenerate width tells us nothing — keep the split,
    // which is the layout that never over-promises.
    if (!maxWidth.isFinite) return false;
    final double available = maxWidth - iconSize - iconGap;
    if (available <= 0) return false;

    final TextPainter painter = TextPainter(
      text: TextSpan(text: combinedLine, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      painter.layout(maxWidth: available);
      return !painter.didExceedMaxLines;
    } catch (error, stackTrace) {
      // Defence in depth, not a live path. `TextPainter.layout` can throw on a
      // malformed UTF-16 sequence (a lone surrogate reproduces
      // `ArgumentError: string is not well-formed UTF-16`). It should be
      // unreachable — Postgres UTF-8 rejects lone surrogates on the way in,
      // and the identical string already reaches an identical paragraph
      // builder through the `Text` below — but we run INSIDE
      // `LayoutBuilder.builder`, so an escape here fails during LAYOUT, which
      // degrades far harder than a paint-time failure. Fall back to the split:
      // the layout that never over-promises.
      developer.log(
        'address fit measurement failed; falling back to the split layout',
        name: 'feature.master.address',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      // In `finally` so a throw cannot leak the native paragraph handle.
      painter.dispose();
    }
  }

  /// The icon-bearing row: pin, gap, then one line of address text.
  ///
  /// Used verbatim by every path — the collapsed line, the locality line of
  /// the split, and both single-field promotions — so the pin can never end up
  /// optically offset between them.
  /// [style] is the effective (already merged) style resolved in `build` — the
  /// same object the fit measurement used, so what was measured is what paints.
  Widget _primaryRow({
    required String text,
    required Key textKey,
    required TextStyle style,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        icon,
        const SizedBox(width: iconGap),
        Flexible(
          child: Text(
            text,
            key: textKey,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Phase 220's two-row split, unchanged: locality beside the pin, street +
  /// building indented underneath.
  Widget _splitRows(String locality, String street, TextStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _primaryRow(
          text: locality,
          textKey: Key('$keyPrefix-locality-text'),
          style: style,
        ),
        const SizedBox(height: _kRowGap),
        Padding(
          padding: const EdgeInsets.only(left: _kIndent),
          child: Text(
            street,
            key: Key('$keyPrefix-address-text'),
            style: style,
            // Phase 219 (A): an explicit line budget is REQUIRED alongside
            // `overflow: ellipsis` — Flutter's ellipsis-without-maxLines
            // combination silently collapses the whole paragraph to a single
            // line instead of wrapping (see the reproduction test in
            // master_profile_screen_test.dart).
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
