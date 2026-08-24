// Phase 13.4 — Full-address block shared by the master + salon result cards.
//
// Renders the result's location as up to two muted lines, led by a small
// place-pin glyph so the address group reads apart from the services line:
//
//   📍 Печерський район, Київ           ← locality (city · district), line 1
//      вул. Хрещатик, 22 · вхід з двору  ← street + building + note,  line 2
//
// The address NEVER contains region/oblast — the search contract does not carry
// it, so there is nothing to render or strip here.
//
// Composition split (see SearchMapper):
//   - [locality] is composed AT RENDER via `formatLocality(cityLabel,
//     districtLabel)` because the district/city join is l10n/presentation
//     concern.
//   - [streetLine] is the auth-gated «street, buildingNo · note» line,
//     PRECOMPUTED once at map time (MasterSearchMapper/SalonSearchMapper →
//     `addressLine`) so this list-row widget never re-joins per build().
//
// Null-handling (clean in every state):
//   - anonymous browse → street/building/note null → [streetLine] null → only
//     the locality line renders (pin + city · district);
//   - no locality either → the whole block collapses to a zero-size
//     `SizedBox.shrink()` (no orphan pin);
//   - authed with street but no note → just «street, buildingNo» (the mapper
//     drops the dangling separator).
//
// ── Phase 111 — WIDENED, NOT FORKED, FOR «Улюблені» ─────────────────────────
//
// The favourites design preview shipped a `FavoriteAddressBlock` that is a
// transcription of THIS widget (its own header says so) plus one extra row: the
// provider's free-text arrival note, wrapping to two lines. Porting that
// verbatim would have made a FIFTH address renderer in this app — after this
// one, `MasterAddressBlock`, `BookingAddressBlock` and `StreetCityLine` — and
// the four that exist have already drifted. So the note is an ADDITIVE optional
// parameter here instead, and «Улюблені» uses this widget directly:
//
//   * [note] defaults to null, so the two search-result cards — the only prior
//     callers — pass nothing and render byte-identically to before;
//   * [topPadding] defaults to 3, the value this widget always hard-coded, so
//     the same two callers keep the exact leading gap they had. Favourites
//     passes 0 because its card owns the gap above the block itself (the design
//     specifies a different one per card kind), and a widget that unilaterally
//     adds 3dp to every caller's spacing is a widget that cannot be reused.
//
// The note deliberately breaks this block's own `maxLines: 1` rule, and only
// the note does. Every other line here is a name or a fixed-format string where
// truncation destroys an identifier; the note is prose, and prose wraps without
// loss. Two lines, not three: three would make a list row a paragraph, and at
// the ~183dp favourites column two lines already deliver the observed 54-char
// worst case whole (≈1.84 lines). The ellipsis past that is a backstop for the
// backend's `@Size(max = 1000)` tail, not the expected path.
//
// NO `LayoutBuilder`. `MasterAddressBlock` (phases 221–224) measures the note
// and offers an expander, which is right on a profile screen and wrong here: a
// fixed `maxLines` costs one layout pass per row, a per-row measurement costs
// one on every scroll frame. The earlier objection to measure-and-collapse in a
// list stands; the fixed wrap makes it moot rather than reversing it.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';

import 'result_card_text.dart';

/// The location block on a master/salon/favourite card: a leading pin glyph and
/// up to three muted lines — locality, the auth-gated street detail, and
/// (optionally) the provider's arrival note. Renders nothing when [locality],
/// [streetLine] and [note] are all absent.
class ResultAddressBlock extends StatelessWidget {
  const ResultAddressBlock({
    super.key,
    required this.locality,
    required this.streetLine,
    this.note,
    this.topPadding = _defaultTopPadding,
  });

  /// The leading gap this block reserves above itself. The value this widget
  /// hard-coded before Phase 111, kept as the default so no existing caller's
  /// spacing moves.
  static const double _defaultTopPadding = 3;

  /// The city · district line composed at render via [formatLocality], or null
  /// when neither a city nor a district is known.
  final String? locality;

  /// The precomputed auth-gated «street, buildingNo · note» detail line, or
  /// null for an anonymous caller / a result with no recorded street.
  final String? streetLine;

  /// The provider's free-text arrival note — «вхід з двору». Phase 111,
  /// «Улюблені» only; null everywhere else, and then no row is drawn and no
  /// space is reserved.
  ///
  /// The ONE line in this block allowed to wrap (to exactly 2 lines) — see the
  /// file header for the line budget and why measurement is not used.
  final String? note;

  /// Leading gap above the block. Defaults to the 3dp the search-result cards
  /// have always had; «Улюблені» passes 0 because its cards set that gap
  /// themselves, per card kind.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    // Rows, coarse → fine. An absent field claims no row at all, so a provider
    // who gave only a city gets exactly one line.
    //
    // Ordering note: the FIRST row present takes the anchor style regardless of
    // which field it is — the line beside the pin is always the anchor, so a
    // provider with no locality still gets a legible top line rather than a
    // faint one. That promotion is why this is a list rather than three `if`s.
    final String? primary = locality ?? streetLine ?? note;
    // Nothing to show at all → take up no space (no orphan pin / empty line).
    if (primary == null) return const SizedBox.shrink();

    // When there is no locality, the street line is promoted to the primary
    // line so it still sits beside the pin (rather than leaving a blank line 1).
    final String? secondary = locality == null ? null : streetLine;
    // ...and the note is only a third row when something above it took the
    // anchor. When the note IS the anchor (no locality, no street) it has
    // already been consumed by [primary] and must not be drawn twice.
    final bool noteIsAnchor = locality == null && streetLine == null;

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 4),
            child: Icon(
              Icons.place_outlined,
              size: 13,
              color: BrandColors.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  primary,
                  // The note is prose and wraps even in the anchor slot; a
                  // locality or street there stays a single line.
                  maxLines: noteIsAnchor ? _noteMaxLines : 1,
                  overflow: TextOverflow.ellipsis,
                  style: ResultCardText.locality,
                ),
                if (secondary != null) ...<Widget>[
                  // 3dp matches the card's established intra-line micro-gap.
                  const SizedBox(height: 3),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ResultCardText.addressDetail,
                  ),
                ],
                if (note != null && !noteIsAnchor) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    note!,
                    maxLines: _noteMaxLines,
                    overflow: TextOverflow.ellipsis,
                    // Quietest of all, and on a LOOSER line-height than the
                    // rows above it. That gap is doing real work: it is the
                    // only typographic signal that this line is a sentence
                    // someone wrote rather than another field off a form, and
                    // it is what stops three stacked muted lines from reading
                    // as one grey slab.
                    style: ResultCardText.addressNote,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Two lines for the note, never three — see the file header.
  static const int _noteMaxLines = 2;
}
