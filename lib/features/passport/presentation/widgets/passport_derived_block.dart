// Phase 238 — the passport's derived data block.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`PassportDerivedBlock`). Preview tokens resolved to the shipped scale;
// eyebrows routed through the ARB; `PriceTag` is the shared
// `core/widgets/price_tag.dart`.
//
//   ┌──────────────────────────────────────────────────┐
//   │ ⌖  УЛЮБЛЕНІ РАЙОНИ ТА МІСТА                      │
//   │    Шевченківський · Голосіївський · Печерський   │
//   │    Київ · Бровари                                │
//   │ ────────────────────────────────────────────────  │
//   │ ⛁  СЕРЕДНІЙ ЧЕК                    ≈ ( 750 ₴ )  │
//   └──────────────────────────────────────────────────┘
//
// Sits directly under the identity strip as its DATA PAGE, bound to it by a
// tighter `VelvetSpacing.md` gap while the page's other blocks sit `lg` apart.
// Both values are derived read-only data of exactly the same class as the
// strip's standing line, so keeping them adjacent means the page reads
// identity → history → action rather than scattering one data class across the
// action surface.
//
// READ-ONLY. Every value here is computed from completed bookings — there is no
// add, edit or remove affordance, by locked product rule. The Beauty wish list
// is the page's only user-managed surface.
//
// ## THE TRUNCATION TRAP, HANDLED STRUCTURALLY
//
// «Шевченківський» clipped to «Шев…» in a cramped column is the ORIGINAL BUG
// this whole redesign exists to fix, so the locality names get the strongest
// guarantee available: each name is its own [Text] with NO `maxLines` and NO
// `TextOverflow`, laid out in a [Wrap] whose loose constraints cap it at the
// field width. A name that does not fit the current run moves to the next run;
// a name wider than the whole field would wrap inside itself. Neither path can
// ellipsise at any viewport width.
//
// Measured: after the hanging indent the field is 270 dp at 360 dp and 230 dp
// at 320 dp, against «Шевченківський» at ~92 dp — 2.9x and 2.5x headroom. All
// three districts plus separators (~271 dp) take two runs at both widths.
//
// The guarantee is STRUCTURAL, NOT BUDGETED: it does not depend on those
// numbers staying true. A longer name simply takes another run.
//
// ## Each separator is bundled with the name it FOLLOWS
//
// Emitting «·» as its own [Wrap] child would let a run break between
// «Голосіївський» and its separator, opening the next line with an orphaned
// interpunct. Bundling makes the break land AFTER the separator, which is the
// conventional reading: a run can end with «Голосіївський ·» but can never
// begin with «·».
//
// ## Unknown cases
//
//   * No spend history → the figure drops its pill and renders a bare «—» in
//     `faint`. Never a fabricated number, and never a pill around nothing.
//   * No location history → the locality field AND its hairline are omitted.
//     Never an empty row.
//   * Neither known → the CALLER drops the whole block ([hasContent]).

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/price_tag.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/presentation/widgets/hub_widgets.dart';

/// The approximation marker drawn beside — and deliberately OUTSIDE — the
/// average-spend pill.
///
/// It qualifies the DERIVATION, not the amount. Keeping it out means every
/// price pill in the app contains exactly one money string, so they all read as
/// the same object and the pill's width cap behaves comparably at every site;
/// putting it inside would make this one pill a different shape from all the
/// others.
///
/// A named constant, not an ARB key: «≈» is a mathematical symbol, identical in
/// UA and EN, exactly like `priceUnavailableLabel`'s «—». Naming it is also
/// what keeps the `no_raw_ui_strings` gate satisfied without an ignore comment.
const String kApproximatelyMarker = '≈';

/// The passport's two auto-derived reference values: where the client goes and
/// what they typically spend.
class PassportDerivedBlock extends StatelessWidget {
  const PassportDerivedBlock({
    super.key,
    required this.districts,
    required this.cities,
    required this.averageSpend,
  });

  /// Most-visited districts, rank-ordered (most frequent first). Empty ⇒ no
  /// location history.
  final List<String> districts;

  /// Most-visited cities, rank-ordered. Empty ⇒ no location history.
  final List<String> cities;

  /// The AVERAGE spend, already formatted («750 ₴») — a PURE money string with
  /// no «≈» baked in. Null ⇒ no spend history.
  ///
  /// Deliberately an average, not the ceiling («до 1 200 ₴») the retired
  /// passport card printed. The backend model backs it: `BudgetBand` carries
  /// `avg` alongside `min`/`max`, so the figure is real data.
  final String? averageSpend;

  /// Whether the derivation could name a locality.
  bool get hasLocations => districts.isNotEmpty || cities.isNotEmpty;

  /// Whether there is anything at all to report. False ⇒ the caller omits the
  /// whole block rather than rendering an empty card.
  bool get hasContent => hasLocations || averageSpend != null;

  /// Width of the eyebrow's glyph column (icon + its gap), reused as the value
  /// lines' hanging indent so label and values share one left edge.
  static const double _kGlyph = 14;
  static const double _kGlyphColumn = _kGlyph + AppSpacing.xxs;

  static const double _kHairline = 1;

  /// The SOFT in-card rule, not the standard one. The preview names the pair —
  /// `VelvetAlpha.hairline` (0.5) for a rule that divides two surfaces, and
  /// `VelvetAlpha.hairlineSoft` (0.28) for one dividing two FIELDS inside a
  /// single card (`docs/signup-designs/BeautyPassport/lib/theme/
  /// velvet_tokens.dart:98`). This rule is the latter: it separates the
  /// locality field from the spend row within one flat card, so it must sit
  /// below the identity strip's counter-rule, which is at the full 0.5.
  ///
  /// The shipped scale has no `VelvetAlpha` class to route this through, so the
  /// value is named here beside its only consumer — the preview's number,
  /// verbatim, never a bare literal at the call site.
  static const double _kHairlineAlpha = 0.28;

  static final Color _ruleColor = BrandColors.faint.withValues(
    alpha: _kHairlineAlpha,
  );

  static final TextStyle _unknownStyle = VelvetText.pill().copyWith(
    color: BrandColors.faint,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? average = averageSpend;
    return HubFlatCard(
      key: const Key('passport_derived_block'),
      radius: VelvetRadii.field,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasLocations) ...<Widget>[
            _DerivedEyebrow(
              icon: Icons.place_outlined,
              label: l10n.passportLocalitiesLabel,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Padding(
              // Hanging indent: the values line up under the eyebrow's TEXT,
              // not under its glyph.
              padding: const EdgeInsets.only(left: _kGlyphColumn),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (districts.isNotEmpty)
                    _LocalityLine(
                      names: districts,
                      style: VelvetText.bodyStrong(),
                    ),
                  if (districts.isNotEmpty && cities.isNotEmpty)
                    const SizedBox(height: AppSpacing.xxs),
                  if (cities.isNotEmpty)
                    _LocalityLine(names: cities, style: VelvetText.body11),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // The rule belongs to the locality field: it SEPARATES it from the
            // spend row, so with no localities there is nothing to separate and
            // it goes too. A lone rule above the only remaining row would read
            // as a field that failed to render.
            Container(height: _kHairline, color: _ruleColor),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: _DerivedEyebrow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l10n.passportAverageSpendLabel,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // ── The block's single figure ──────────────────────────────────
              // The SAME [PriceTag] the wish list uses — one pill
              // implementation, one place to change it. This is a full-width
              // surface, so it takes the default vertical padding, like the
              // wish list's full-width row and the shipped >=1h master card.
              //
              // The UNKNOWN case DROPS THE PILL entirely: a recessed well is
              // chrome that says "here is a figure", and wrapping an em dash in
              // it would read as a value that exists. Absence should look like
              // absence — bare «—», faint, but in the pill's OWN type so the
              // figure slot keeps one voice and only the chrome differs.
              if (average == null)
                Text(
                  l10n.passportBudgetUnknown,
                  key: const Key('passport_average_unknown'),
                  textAlign: TextAlign.right,
                  style: _unknownStyle,
                )
              else ...<Widget>[
                // `masterCardTimeShared`, NOT `masterCardTime` — see
                // `wishlist_row.dart`'s identical note: this screen is out of
                // scope for the 2026-08-15 booking-card font-size pass and
                // must render byte-identically. See `velvet_text.dart`'s
                // `masterCardTimeShared` doc.
                Text(
                  kApproximatelyMarker,
                  style: VelvetText.masterCardTimeShared,
                ),
                const SizedBox(width: AppSpacing.xxs),
                PriceTag(price: average),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The eyebrow naming one derived field — a small outline glyph plus an
/// all-caps label. Unbounded: the label WRAPS rather than clipping.
class _DerivedEyebrow extends StatelessWidget {
  const _DerivedEyebrow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: PassportDerivedBlock._kGlyph,
          color: BrandColors.accentDeep,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(child: Text(label.toUpperCase(), style: VelvetText.label11)),
      ],
    );
  }
}

/// One rank-ordered line of locality names, most-frequent first.
///
/// See [PassportDerivedBlock]'s header for why nothing here can truncate and
/// why each separator is bundled with the name it follows.
class _LocalityLine extends StatelessWidget {
  const _LocalityLine({required this.names, required this.style});

  final List<String> names;
  final TextStyle style;

  /// The rank separator. A named constant for the same reason
  /// [kApproximatelyMarker] is one: a punctuation glyph, not translatable copy.
  static const String _kSeparator = '·';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: VelvetSpacing.xs,
      runSpacing: VelvetSpacing.xs / 2,
      children: <Widget>[
        for (int i = 0; i < names.length; i++)
          if (i == names.length - 1)
            Text(names[i], style: style)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // [Flexible], so a name wider than the whole field wraps INSIDE
                // its own bundle rather than overflowing the min-size Row.
                Flexible(child: Text(names[i], style: style)),
                const SizedBox(width: VelvetSpacing.xs),
                Text(
                  _kSeparator,
                  style: style.copyWith(color: BrandColors.faint),
                ),
              ],
            ),
      ],
    );
  }
}
