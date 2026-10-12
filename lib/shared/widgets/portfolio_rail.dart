import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncError, AsyncValue;

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show kPortfolioMaxPhotos;
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/prompt_link_text.dart';

/// The shared placeholder "Портфоліо" rail — a section label (optionally
/// paired with a «Всі фото» link) above a horizontal row of gradient
/// placeholder photo tiles.
///
/// REUSE-FIRST — this is the PROMOTION of what used to be two hand-copied
/// private implementations:
///   - `_PortfolioPlaceholderTile` + its inline rail Column, formerly in
///     `features/master/presentation/master_profile_screen.dart` (the
///     master's own editable profile — this is the canonical shape, the one
///     the header-row «Всі фото» link comes from);
///   - `_PortfolioTile` + its inline rail Column, formerly in
///     `features/master/presentation/public_master_profile_screen.dart` (the
///     read-only client-facing view — it omitted the «Всі фото» link, which
///     [onSeeAll] now models as an optional param instead of a fork).
/// The two tile classes were byte-for-byte identical but for the static glyph
/// field's name (`_glyphColor` vs `_photoGlyph`) — no visual difference; this
/// file keeps the master version's name.
///
/// Phase 404 (9.9, D1) — REAL photos, additively. Three optional params, all
/// defaulting to "off", so a caller passing none of them renders the
/// byte-identical placeholder rail (golden-pinned):
///   • [photos] — `null` (default) → the [count] gradient placeholders, also
///     what a caller shows while its portfolio read is LOADING; a list → one
///     [PortfolioTile] per photo, in list order, built lazily and capped at
///     the newest [kPortfolioMaxPhotos] ([count] is ignored);
///   • [hideWhenEmpty] — an EMPTY [photos] list renders nothing at all
///     (public surfaces: a client never sees an empty portfolio section);
///     otherwise an empty list shows the label + [AppLocalizations.portfolioEmptyOwn];
///   • [onRetry] — non-null → the read FAILED: label + an inline
///     «Не вдалося завантажити фото. Спробувати знову» line (owner surfaces;
///     public surfaces hide the section on error instead).
/// The rail itself reads no provider — wiring lives at the call sites.
class PortfolioRail extends StatelessWidget {
  const PortfolioRail({
    super.key,
    this.railKey,
    this.onSeeAll,
    this.count = 6,
    this.photos,
    this.hideWhenEmpty = false,
    this.onRetry,
  });

  /// Maps a portfolio read onto the rail — the ONE place the D2 state
  /// mapping lives, shared by every real-photo call site:
  ///   • a value (incl. a refetch holding the previous list) → [photos];
  ///   • loading with no value → the placeholder tiles (existing look);
  ///   • error with no value → [onRetry] non-null: the inline retry line
  ///     (owner surfaces); [onRetry] null: nothing (public surfaces);
  ///   • [hideWhenEmpty] → an empty list renders nothing (public surfaces).
  factory PortfolioRail.fromAsync(
    AsyncValue<List<PortfolioPhoto>> async, {
    Key? key,
    Key? railKey,
    bool hideWhenEmpty = false,
    VoidCallback? onRetry,
  }) {
    final List<PortfolioPhoto>? value = async.value;
    if (value != null) {
      return PortfolioRail(
        key: key,
        railKey: railKey,
        photos: value,
        hideWhenEmpty: hideWhenEmpty,
      );
    }
    if (async is AsyncError<List<PortfolioPhoto>>) {
      return onRetry == null
          // Public surface: hide the section — an empty list + hide flag is
          // exactly the rail's "render nothing" branch.
          ? PortfolioRail(
              key: key,
              railKey: railKey,
              photos: const <PortfolioPhoto>[],
              hideWhenEmpty: true,
            )
          : PortfolioRail(key: key, railKey: railKey, onRetry: onRetry);
    }
    return PortfolioRail(key: key, railKey: railKey);
  }

  /// Applied to the outer [Column] wrapping the whole section (header row +
  /// tile rail). Lets a screen pin a stable widget-tree key for
  /// golden/integration tests without this widget imposing one of its own —
  /// e.g. `public_master_profile_screen.dart` keeps
  /// `Key('public-master-profile-portfolio')`.
  final Key? railKey;

  /// Tapped when the «Всі фото» link is pressed. When null (the default),
  /// the link is omitted entirely and only the section label renders — used
  /// by the read-only public master profile, which has no gallery route.
  final VoidCallback? onSeeAll;

  /// Number of placeholder tiles to render. Defaults to 6, matching every
  /// current caller.
  final int count;

  /// The real portfolio, newest first. `null` → placeholder path (above).
  final List<PortfolioPhoto>? photos;

  /// When true, an empty [photos] list renders `SizedBox.shrink()`.
  final bool hideWhenEmpty;

  /// Non-null → render the inline load-error line with this retry link.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final VoidCallback? seeAll = onSeeAll;
    final VoidCallback? retry = onRetry;
    final List<PortfolioPhoto>? real = photos;
    if (retry == null && real != null && real.isEmpty && hideWhenEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: railKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
          child: seeAll == null
              ? Text(
                  l10n.masterPortfolioLabel,
                  style: VelvetText.sectionLabel(),
                )
              : Row(
                  children: <Widget>[
                    Text(
                      l10n.masterPortfolioLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: seeAll,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(l10n.masterAllPhotos, style: VelvetText.link()),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: BrandColors.accentDeep,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        if (retry != null)
          Padding(
            key: const Key('portfolio-rail-error'),
            padding: const EdgeInsets.only(left: 4),
            child: PromptLinkText(
              prompt: l10n.portfolioLoadError,
              linkLabel: l10n.retryLabel,
              linkKey: const Key('portfolio-rail-retry'),
              onTap: retry,
            ),
          )
        else if (real != null && real.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              l10n.portfolioEmptyOwn,
              key: const Key('portfolio-rail-empty'),
              style: VelvetText.feedback(BrandColors.muted),
            ),
          )
        else if (real != null)
          // Phase 404 audit R1/R2 — LAZY, unlike the fixed 6-tile placeholder
          // branch below: a real portfolio can hold up to
          // [kPortfolioMaxPhotos] network tiles, and an eager Row started every
          // fetch + decode the moment the tab opened. `ListView.separated`
          // builds only the tiles in (and `cacheExtent` around) the viewport.
          // Same geometry as the Row it replaces: 72px tiles, `md` gaps, no
          // trailing gap, zero padding — so on-screen pixels are unchanged.
          // A horizontal list inside the profile's vertical scroll view does
          // not compete for drags: each scrollable claims only its own axis.
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              // R2 — render at most the product cap. The server may return
              // more (up to 50); the list is newest-first, so the first
              // [kPortfolioMaxPhotos] are the newest.
              itemCount: math.min(real.length, kPortfolioMaxPhotos),
              separatorBuilder: (BuildContext _, int _) =>
                  const SizedBox(width: VelvetSpacing.md),
              itemBuilder: (BuildContext _, int i) => PortfolioTile(
                key: Key('portfolio-photo-${real[i].id}'),
                index: i,
                imageUrl: real[i].url,
                decodeToCover: true,
              ),
            ),
          )
        else
          SizedBox(
            height: 72,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Matches the BouncingScrollPhysics convention used by the outer
              // vertical scroll in profile_scaffold.dart.
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < count; i++) ...<Widget>[
                    PortfolioTile(index: i),
                    if (i < count - 1) const SizedBox(width: VelvetSpacing.md),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Raised 72×72 tile with a camel-mocha gradient fill.
///
/// [imageUrl] `null` (default) → the gradient placeholder, unchanged.
/// Set (phase 404, D1) → the photo, via the shared allow-listed
/// [RemoteImage], clipped to the same [VelvetRadii.field] corner and laid
/// over the gradient — so the gradient is the loading fill, and the glyph on
/// the gradient is the error / disallowed-URL fallback.
class PortfolioTile extends StatefulWidget {
  const PortfolioTile({
    super.key,
    required this.index,
    this.imageUrl,
    this.decodeToCover = false,
  });

  final int index;

  /// The real photo URL, or `null` for the placeholder.
  final String? imageUrl;

  /// Forwarded to [RemoteImage.decodeToCover]: decode the photo so its SHORT
  /// side covers the 72px box (sharp `BoxFit.cover` for non-square photos).
  /// `false` (default) keeps [RemoteImage]'s fit-in-box decode. Ignored for
  /// the placeholder ([imageUrl] null).
  final bool decodeToCover;

  @override
  State<PortfolioTile> createState() => _PortfolioTileState();
}

class _PortfolioTileState extends State<PortfolioTile> {
  bool _pressed = false;

  static const List<List<Color>> _fills = <List<Color>>[
    <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
    <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
    <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
  ];

  static final Color _glyphColor = BrandColors.white.withValues(alpha: 0.65);

  static const double _size = 72;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    final List<Color> fill = _fills[widget.index % _fills.length];
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? url = widget.imageUrl;
    final Widget glyph = Center(
      child: Icon(Icons.photo_outlined, color: _glyphColor, size: 22),
    );
    return Semantics(
      label: url == null
          ? l10n.masterPortfolioTileSemantics(widget.index + 1)
          : l10n.portfolioPhotoSemantics(widget.index + 1),
      image: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            height: 72,
            width: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: fill,
              ),
              boxShadow: _pressed
                  ? null
                  : const <BoxShadow>[
                      BoxShadow(
                        color: BrandColors.shadowDarkButton,
                        offset: Offset(2, 2),
                        blurRadius: 5,
                        spreadRadius: -1,
                      ),
                      BoxShadow(
                        color: BrandColors.shadowLightStrong,
                        offset: Offset(-2, -2),
                        blurRadius: 5,
                        spreadRadius: -1,
                      ),
                    ],
            ),
            child: url == null
                ? glyph
                : RemoteImage(
                    url: url,
                    width: _size,
                    height: _size,
                    borderRadius: _radius,
                    excludeFromSemantics: true,
                    decodeToCover: widget.decodeToCover,
                    fallback: glyph,
                  ),
          ),
        ),
      ),
    );
  }
}
