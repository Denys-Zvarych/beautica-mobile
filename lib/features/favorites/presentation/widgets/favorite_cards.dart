// Phase 111 (old 13.10) — the two «Улюблені» card kinds + the removed-row dent.
//
// Ported from the approved preview
// `docs/signup-designs/ClientFavorites/lib/widgets/favorite_cards.dart`.
//
// ── The design problem ──────────────────────────────────────────────────────
//
// A master and a salon must be told apart at a glance while still reading as
// ONE list. A «Салон» badge solves that with a label — the reader has to READ
// to know. VelvetTouch has exactly one expressive dimension, depth, so the
// distinction is encoded in depth and silhouette instead:
//
//   * **Master = a person → a RAISED CIRCLE.** A camel-gradient disc that
//     extrudes out of the surface, cream initials facing you.
//   * **Salon = a place → a RECESSED SQUARE.** A rounded-square well of the
//     bare page colour, pressed INTO the surface, with an accentDeep storefront
//     glyph — a doorway, something you enter.
//
// Both marks are the same [kFavoriteMarkSize] square (user decision 2026-08-24).
// Size used to carry part of this cue and no longer does; the separation rests
// on the four ways the marks still differ, which are the strong ones:
//
// |                | master                      | salon                        |
// |----------------|-----------------------------|------------------------------|
// | depth polarity | extruded (light TL, dark BR)| inset (dark TL, light BR)    |
// | fill           | camel gradient — an object  | `base` — the card's own tone |
// | geometry       | full circle                 | squircle, radius 15 of 56    |
// | content        | cream initials (text)       | accentDeep glyph (icon)      |
//
// Depth polarity and fill do the heavy lifting: one mark is a saturated object
// standing on the surface, the other is a hole in it. That is a LUMINANCE
// difference, not an outline one, so it survives peripheral vision and a fast
// scroll in a way a size delta never really did.
//
// Everything else — the card shell, the identity line, the trailing heart — is
// deliberately identical, which is what keeps them one list rather than two.
//
// ── HEIGHT IS A COMPLETENESS SIGNAL, NOT A KIND SIGNAL ──────────────────────
//
// Card height used to run salon < independent < affiliated. It does not any
// more: street, building number and note are all optional and all render when
// present, so each kind spans a RANGE and the ranges interleave — a salon with
// a wrapped note outgrows an affiliated master. Nothing here is padded to
// pretend otherwise. Height now means "how much this provider wrote down",
// which is the ordinary behaviour of any content-driven list. The KIND cue sits
// entirely on the identity mark and the accentDeep affiliation line, neither of
// which varies with how complete a profile is.
//
// ── REUSE ───────────────────────────────────────────────────────────────────
//
// The address is rendered by the SHARED [ResultAddressBlock] (widened
// additively in this phase with an optional `note` row + `topPadding`), not by
// a favourites-local copy. The preview shipped a `FavoriteAddressBlock` that is
// a transcription of that widget; porting it would have made a fifth address
// renderer in this app. See `result_address_block.dart`'s Phase 111 header.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
// Cross-feature import into `discovery/presentation/` — deliberate, and the
// lesser of two evils. `ResultAddressBlock` and `formatLocality` are the app's
// canonical list-row address renderer and district/city composer; the approved
// preview shipped a transcription of both, and porting that transcription
// would have made a FIFTH address renderer (after this one,
// `MasterAddressBlock`, `BookingAddressBlock` and `StreetCityLine`) in a repo
// where the existing four have already drifted. Promoting them to
// `shared/widgets/` + `shared/formatters/` is the tidier end state and is
// filed as follow-up work: it moves two files with four call sites and two
// discovery test files, which is a change with its own golden diff and does
// not belong inside this port.
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/result_card_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';

import '../../domain/favorite_item.dart';

/// **One size for both identity marks** — the master's portrait disc and the
/// salon's storefront well are the same square (user decision 2026-08-24).
///
/// WHY 56 SPECIFICALLY. The mark is a FLOOR under a card's text column:
/// whichever is taller sets the card height. A single mark value S has to
/// thread a needle — below ~58, or a salon carrying a street stops being taller
/// than one without (both flatten to the same height); above ~52, or an
/// independent master falls to the same height as a full-address salon and then
/// below it. 56 is the largest integer inside that window, so it is the biggest
/// mark that still leaves all four row shapes a distinct height.
const double kFavoriteMarkSize = 56;

/// Corner radius of the salon's squircle well — 15 of 56 (27%), which reads
/// squarer against the master's full circle than the same 15 did at 48.
const double _kSalonMarkRadius = 15;

/// The gap between a master card's stacked registers.
///
/// One value for every intra-column gap, deliberately airier than the 4/5/6 an
/// earlier three-line version used. The card carries three registers in three
/// colours (espresso name, accentDeep salon, muted address); tight spacing
/// would let them read as one striped block instead of three statements. Air is
/// what makes a register break legible.
const double _masterBandGap = VelvetSpacing.sm + 4;

/// A rating readout: camel star + one-decimal value.
///
/// ── THE SLOT IS ALWAYS DRAWN; AN UNRATED ROW SHOWS A DASH ───────────────────
///
///     ★ 4.7            ★ –
///
/// User decision, superseding an earlier card that hid the readout entirely on
/// unrated rows. The objection behind that version still stands and is
/// preserved: **`0.0` beside a star reads as a BAD score to a human, not a
/// missing one**, and would libel every unrated provider on the screen. A dash
/// is precisely the mark that is not a zero — it asserts no quantity at all —
/// so the slot can stay constant without lying.
///
/// What the constant slot buys: unrated is the norm for masters and the
/// starting state of every new salon, so on a real list most rows are unrated.
/// A hidden readout meant the identity line changed shape row to row and the
/// star column appeared and vanished down the scroll.
///
/// ── A DERIVED SALON RATING IS DRAWN EXACTLY LIKE A DIRECT MASTER RATING ─────
///
/// A salon's score is the mean of its active masters' means for work done
/// there — an average of averages no single client ever gave. Same star, same
/// size, same camel, same slot. Deliberate: the difference is arithmetic depth,
/// not epistemic kind (a master's 4.8 is ALREADY the mean of their clients'
/// scores; the salon's is a mean one level up, and there is no honest point on
/// that ladder to draw a line). The client has no action to take on the
/// distinction, and any marker — a tilde, a paler star, a footnote glyph —
/// would read as *trust this number less*, a claim the product has not made.
///
/// The real weakness of a derived score is THIN EVIDENCE, not derivation: a
/// salon with one rated master shows 5.0 as confidently as one with twelve. The
/// honest fix is a review count, deliberately not requested for this screen —
/// it holds providers the client has already chosen, where the rating decides
/// nothing. A count belongs on the salon profile.
class RatingReadout extends StatelessWidget {
  const RatingReadout({super.key, required this.rating});

  /// Null or `0.00` → the dash. Never rendered as a score.
  final double? rating;

  /// **U+2013 EN DASH**, not the ASCII hyphen.
  ///
  /// This glyph sits beside numerals, so it has to belong to the figures, not
  /// the prose. In Nunito the ASCII hyphen is short and rides low — next to
  /// `4.7` it reads as a word-break that wandered into a number. The en dash is
  /// cut to roughly digit width and sits on the figure axis. The em dash is far
  /// too wide for a three-glyph slot, and U+2012 FIGURE DASH — nominally the
  /// perfect answer — is missing from a great many faces and risks a
  /// fallback-font substitution that would look worse than either.
  ///
  /// Not an ARB string: this is a typographic mark standing in for a missing
  /// quantity, not translatable copy. The spoken form IS localised — see the
  /// card's semantic label, which says «Без оцінок» in words.
  static const String _noValue = '–';

  /// The value slot is **fixed width**, and that is the whole point.
  ///
  /// The readout is right-aligned at the end of the identity line, so a slot
  /// that shrank to fit a one-glyph dash would drag the star rightwards on
  /// every unrated row — and with most rows unrated, the star column would
  /// visibly wobble down a scrolling list. Pinning the slot keeps every star in
  /// the list on one vertical line whatever the row holds. Every rated value is
  /// exactly three glyphs via `toStringAsFixed(1)`, so centring them is
  /// visually identical to flushing them; the dash then lands under where the
  /// decimal point would be — the optical centre of the quantity it stands in
  /// for, rather than pretending to be one of its digits.
  static const double _valueSlotWidth = 24;

  /// The star at 40% strength for an unrated row. Hoisted: a scrolling list
  /// must not allocate a Color per card build.
  static final Color _dimStar = BrandColors.accent.withValues(alpha: 0.4);

  @override
  Widget build(BuildContext context) {
    final bool rated = rating != null && rating! > 0;
    // The card's own Semantics already says «Рейтинг 4,7» or «Без оцінок»; a
    // screen reader must never be handed a bare "–" to announce.
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.star_rounded,
            size: 16,
            // Dimmed, but still a FILLED star. An OUTLINE star would read as
            // an empty star — "zero out of five" — which is the one meaning
            // this slot must never carry; a filled star at reduced strength
            // reads as a slot with no data in it.
            color: rated ? BrandColors.accent : _dimStar,
          ),
          const SizedBox(width: 3),
          SizedBox(
            width: _valueSlotWidth,
            child: Text(
              // raw-ui-string-ok: a numeral and an en dash — a typographic
              // mark, not translatable copy. The spoken equivalent is
              // localised on the card's Semantics label.
              rated ? rating!.toStringAsFixed(1) : _noValue,
              textAlign: TextAlign.center,
              // The unrated pair dims as a UNIT so it reads as one inactive
              // slot rather than a bright star missing its number.
              style: rated
                  ? VelvetText.favRatingValue
                  : VelvetText.favRatingValue.copyWith(
                      color: BrandColors.muted,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name + rating on one line. Shared verbatim by both card kinds: the rating
/// belongs to the provider, so it sits on the identity line, which also leaves
/// the locality the full column width before it has to ellipsize.
class _IdentityLine extends StatelessWidget {
  const _IdentityLine({required this.name, required this.rating});

  final String name;

  /// Null / zero → the star still draws, dimmed, over a dash. See
  /// [RatingReadout]: the slot is structurally constant on every card.
  final double? rating;

  @override
  Widget build(BuildContext context) {
    // crossAxisAlignment: start — a two-line name must not pull the rating
    // down to the vertical centre of a now-taller column. The star + value
    // stay pinned to the FIRST line, matching where a one-line name always
    // put them, so the readout does not appear to drift down the row on the
    // (now common, on real Ukrainian names) two-line case.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            name,
            // Up to TWO lines, then ellipsized (user decision, superseding the
            // one-line call this comment used to defend). Field testing on
            // real Ukrainian provider names showed truncation on the first
            // pass — a name is the one piece of identity on this card that
            // must not be cut to a fragment. The height-ladder argument for
            // one line no longer holds: this mark is not the tallest element
            // on every row (a wrapped locationNote already runs to 2 lines,
            // see `ResultAddressBlock`), so it was never a true floor, only a
            // common case — and two lines is now the agreed CEILING, not a
            // regression of the ladder. The full name is still one tap away on
            // the profile for the rare row that overflows even that.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.subheading16,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        RatingReadout(rating: rating),
      ],
    );
  }
}

/// The identity mark for a master: a raised camel-gradient disc with initials.
class MasterMark extends StatelessWidget {
  const MasterMark({
    super.key,
    required this.initials,
    this.size = kFavoriteMarkSize,
  });

  final String initials;
  final double size;

  /// The disc's own dark shadow — a deeper warm mocha than the card's, so it
  /// is visibly darker than the camel face and reads as genuine depth.
  static const Color _discShadow = Color(0xFF8C6A44);

  static const BoxDecoration _decoration = BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        BrandColors.accentLogo,
        BrandColors.accent,
        BrandColors.accentLatte,
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
    boxShadow: <BoxShadow>[
      BoxShadow(color: _discShadow, offset: Offset(4, 4), blurRadius: 10),
      BoxShadow(
        color: BrandColors.shadowLightStrong,
        offset: Offset(-4, -4),
        blurRadius: 10,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: _decoration,
      child: Center(
        child: Text(
          // raw-ui-string-ok: the provider's own initials, derived from their
          // name — data, not UI copy.
          initials,
          style: VelvetText.displayName().copyWith(
            // Runtime-computed from [size], not an inline literal: the mark's
            // glyph must stay proportional to the disc at any extent a caller
            // (or a golden) asks for. Allow-listed in
            // `scripts/.inline_fontsize_allow`.
            fontSize: size * 0.32,
            color: BrandColors.white,
          ),
        ),
      ),
    );
  }
}

/// The identity mark for a salon: a recessed rounded-square well with a
/// storefront glyph — a door pressed into the surface.
class SalonMark extends StatelessWidget {
  const SalonMark({super.key, this.size = kFavoriteMarkSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: NeumorphicInset(
        radius: _kSalonMarkRadius,
        child: Center(
          child: Icon(
            Icons.storefront_rounded,
            size: size * 0.46,
            color: BrandColors.accentDeep,
          ),
        ),
      ),
    );
  }
}

/// The unlike control. Filled by definition — everything on this screen is
/// already a favourite — so the heart is a REMOVE affordance, not a toggle. It
/// squeezes on press so the removal reads as a deliberate act.
class UnlikeHeart extends StatefulWidget {
  const UnlikeHeart({super.key, required this.name, required this.onUnlike});

  final String name;
  final VoidCallback onUnlike;

  @override
  State<UnlikeHeart> createState() => _UnlikeHeartState();
}

class _UnlikeHeartState extends State<UnlikeHeart> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.favoritesUnlikeLabel(widget.name),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onUnlike();
        },
        child: SizedBox(
          height: 44,
          width: 44,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.78 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: const Icon(
                Icons.favorite_rounded,
                size: 24,
                color: BrandColors.accentDeep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared card shell — identical for both kinds. Raised taupe pillow that
/// depresses on tap, radius 24, § 9 `extrudedCard` shadows.
///
/// NOT [NeumorphicCard]: that widget is a static raised surface with a fixed
/// `lg` padding and no press state, and giving it one would change every
/// surface in the app that already uses it. This shell adds the press-scale
/// and takes per-kind padding, so it stays local — and it is the ONLY shell
/// either card kind uses, so the two can never drift apart.
class _FavoriteShell extends StatefulWidget {
  const _FavoriteShell({
    required this.semanticLabel,
    required this.onTap,
    required this.padding,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<_FavoriteShell> createState() => _FavoriteShellState();
}

class _FavoriteShellState extends State<_FavoriteShell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.card),
                boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Master favourite: raised circular portrait, name, affiliation line
/// (salon-attached masters only), address block, rating, unlike heart.
class FavoriteMasterCard extends StatelessWidget {
  const FavoriteMasterCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onUnlike,
  });

  final FavoriteItem item;
  final VoidCallback onOpen;
  final VoidCallback onUnlike;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? locality = formatLocality(item.cityLabel, item.districtLabel);
    // No suppression by affiliation any more. Before backend `ca2c98a`, a
    // salon-affiliated master's street/buildingNo/locationNote arrived null
    // (masked server-side via `MasterType.disclosesOwnAddress`), and this card
    // suppressed them defensively on the client too, on the theory that the
    // affiliation line above already named the place and repeating its
    // address underneath would duplicate what the line exists to disambiguate.
    // `ca2c98a` reversed that: an affiliated master now publishes their
    // EMPLOYING SALON's street/building/note, deliberately, and the product
    // decision is to render it — the affiliation line carries the salon's
    // NAME, this block carries its STREET, and nothing is duplicated between
    // them. street/buildingNo/locationNote are therefore computed
    // unconditionally, exactly like an independent master or a salon card. Do
    // NOT restore a client-side guard here: the contract now intends this.
    final String? streetLine = buildStreetLine(item.street, item.buildingNo);
    final String? note = item.locationNote;
    final bool hasAddress =
        locality != null || streetLine != null || note != null;

    return _FavoriteShell(
      semanticLabel: l10n.favoritesMasterCardLabel(
        item.name,
        // The affiliation line has no spoken form of its own (it renders as
        // plain Text, not inside `ExcludeSemantics`, so it still reaches a
        // screen reader as an incidental stop — but the CARD's own composed
        // label should lead with it too, for the same reason it already
        // folds locality/street/note into one spoken blob rather than relying
        // on each Text's own default announcement: a linear swipe should not
        // be the only way to learn where this master works). Leading with the
        // salon name mirrors the visual order — name, affiliation, address.
        <String>[?item.salonName, ?locality, ?streetLine, ?note].join('. '),
        item.hasRating
            ? l10n.favoritesRatingSpoken(item.rating!)
            : l10n.favoritesNoRatingSpoken,
      ),
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.md,
        VelvetSpacing.sm,
        VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          MasterMark(initials: item.initials),
          const SizedBox(width: VelvetSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _IdentityLine(name: item.name, rating: item.rating),
                if (item.salonName case final String salonName) ...<Widget>[
                  const SizedBox(height: _masterBandGap),
                  _AffiliationLine(salonName: salonName),
                ],
                if (hasAddress) ...<Widget>[
                  const SizedBox(height: _masterBandGap),
                  ResultAddressBlock(
                    locality: locality,
                    streetLine: streetLine,
                    note: note,
                    // The card owns its own register gap above the block
                    // (`_masterBandGap`); the block must not add its
                    // search-card default 3dp on top of it.
                    topPadding: 0,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs),
          UnlikeHeart(name: item.name, onUnlike: onUnlike),
        ],
      ),
    );
  }
}

/// Where a master works: a storefront glyph + the salon's name, one register
/// below the person's own name. Shown only when the person is attached to a
/// salon — an independent master gets nothing here, and that silence is the
/// answer to "where do they work". Identical for `SALON_MASTER` and
/// `SALON_OWNER`: to a client, both are "a master at salon X".
///
/// ── WHY THIS LINE IS ACCENT-COLOURED AND THE ADDRESS BELOW IT IS NOT ────────
///
/// It used to be muted, with a last-service line sitting between it and the
/// address. With that line removed (user decision), the affiliation and the
/// address became directly adjacent — two glyph-led secondary lines in the
/// same tone, which is exactly how a card turns to mush. The separator is now
/// HUE, and it is a semantic one rather than decoration: a salon is a NAVIGABLE
/// entity, so it takes `accentDeep`, this design's link colour; an address is
/// INERT orientation, so it stays muted. The two also differ in weight, size
/// and glyph. Colour is the strongest register break VelvetTouch has after
/// depth itself, which makes this a firmer separation than the service line
/// ever provided — that one separated by position alone.
///
/// It also sharpens the hardest pair on the screen: «Crystal Room №1» renders
/// as Comfortaa espresso when the row IS that salon, and as Nunito accentDeep
/// behind a storefront glyph when the row is a person who works there.
class _AffiliationLine extends StatelessWidget {
  const _AffiliationLine({required this.salonName});

  final String salonName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.storefront_outlined,
          size: 15,
          color: BrandColors.accentDeep,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            salonName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.favAffiliation,
          ),
        ),
      ],
    );
  }
}

/// Salon favourite: recessed storefront well, name, rating, unlike, and the
/// full address block — the card kind that most earns a street line, because a
/// salon is a place you travel to and a chain's two branches in one city are
/// told apart by nothing else.
class FavoriteSalonCard extends StatelessWidget {
  const FavoriteSalonCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onUnlike,
  });

  final FavoriteItem item;
  final VoidCallback onOpen;
  final VoidCallback onUnlike;

  /// The gap between the identity line and the address block on a salon card —
  /// tighter than the master card's `_masterBandGap` because the salon column
  /// has two registers, not three, and the extra air would push the column past
  /// its 56dp mark and change the card's height class.
  static const double _salonBandGap = 5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? locality = formatLocality(item.cityLabel, item.districtLabel);
    final String? streetLine = buildStreetLine(item.street, item.buildingNo);

    return _FavoriteShell(
      semanticLabel: l10n.favoritesSalonCardLabel(
        item.name,
        <String>[?locality, ?streetLine, ?item.locationNote].join('. '),
        item.hasRating
            ? l10n.favoritesRatingSpoken(item.rating!)
            : l10n.favoritesNoRatingSpoken,
      ),
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.md - 3,
        VelvetSpacing.sm,
        VelvetSpacing.md - 3,
      ),
      child: Row(
        children: <Widget>[
          const SalonMark(),
          const SizedBox(width: VelvetSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _IdentityLine(name: item.name, rating: item.rating),
                const SizedBox(height: _salonBandGap),
                ResultAddressBlock(
                  locality: locality,
                  streetLine: streetLine,
                  note: item.locationNote,
                  topPadding: 0,
                ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs),
          UnlikeHeart(name: item.name, onUnlike: onUnlike),
        ],
      ),
    );
  }
}

/// ── The dent an unliked row leaves behind ───────────────────────────────────
///
/// Optimistic removal, staged so it never reads as a glitch. The raised card is
/// replaced IN ITS OWN SLOT by a recessed well — literally the dent the pillow
/// left in the surface — carrying who was removed and a «Повернути» action. A
/// camel hairline drains left-to-right so the window is visibly finite; when it
/// runs out the dent closes with a height animation and the row is gone.
///
/// The undo lives at the point of action rather than in a bottom snackbar,
/// which on this screen would sit over the client bottom nav. The list never
/// jumps at the moment of the tap, because the slot is held.
class RemovedDent extends StatelessWidget {
  const RemovedDent({
    super.key,
    required this.name,
    required this.window,
    required this.onUndo,
  });

  final String name;

  /// How long the undo stays available — drives the draining hairline.
  final Duration window;

  final VoidCallback onUndo;

  /// Matches the tallest thing the dent holds (two text rows + the hairline)
  /// without inheriting the card's variable height, so the collapse animates
  /// from one known height rather than from whatever the card happened to be.
  static const double _height = 70;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NeumorphicInset(
      radius: VelvetRadii.card,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.md + 2,
                0,
                VelvetSpacing.sm + 2,
                0,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.favorite_border_rounded,
                    size: 20,
                    color: BrandColors.muted,
                  ),
                  const SizedBox(width: VelvetSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.favDentName,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.favoritesRemovedCaption,
                          style: VelvetText.favDentCaption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  _UndoAction(name: name, onTap: onUndo),
                ],
              ),
            ),
            // The finite-window hairline. Keyed on the name so re-unliking the
            // same row after an undo restarts the drain instead of resuming a
            // half-spent one.
            Positioned(
              left: VelvetSpacing.md + 2,
              right: VelvetSpacing.md + 2,
              bottom: 11,
              height: 2,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('favorites-drain-$name'),
                tween: Tween<double>(begin: 1, end: 0),
                duration: window,
                curve: Curves.linear,
                builder: (BuildContext context, double v, Widget? _) {
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _drainColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hoisted — the drain rebuilds on every animation frame and must not
  /// allocate a Color per tick.
  static final Color _drainColor = BrandColors.accent.withValues(alpha: 0.55);
}

class _UndoAction extends StatelessWidget {
  const _UndoAction({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.favoritesUndoLabel(name),
      child: GestureDetector(
        key: const Key('favorites-undo-button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.sm + 2,
            vertical: VelvetSpacing.sm + 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.undo_rounded,
                size: 17,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: 5),
              Text(l10n.favoritesUndo, style: VelvetText.link()),
            ],
          ),
        ),
      ),
    );
  }
}
