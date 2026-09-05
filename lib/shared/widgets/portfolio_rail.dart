import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

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
/// Real photos (backed by R2 storage + `GET/POST /media/portfolio`) are a
/// later phase — every tile here is a static gradient placeholder, and
/// [onSeeAll] (when provided) is expected to be a no-op stub until the
/// gallery route exists.
class PortfolioRail extends StatelessWidget {
  const PortfolioRail({super.key, this.railKey, this.onSeeAll, this.count = 6});

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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final VoidCallback? seeAll = onSeeAll;
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

/// Raised 72×72 tile with a camel-mocha gradient fill — simulates a photo.
/// Replaced by real `Image.network` tiles once R2-backed portfolio uploads
/// ship.
class PortfolioTile extends StatefulWidget {
  const PortfolioTile({super.key, required this.index});

  final int index;

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

  @override
  Widget build(BuildContext context) {
    final List<Color> fill = _fills[widget.index % _fills.length];
    return Semantics(
      label: AppLocalizations.of(
        context,
      ).masterPortfolioTileSemantics(widget.index + 1),
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
            child: Center(
              child: Icon(Icons.photo_outlined, color: _glyphColor, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
