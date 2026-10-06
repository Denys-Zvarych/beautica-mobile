// Phase 13.6 — Salon cover + hero chrome widgets.
//
// Ported verbatim (token names only) from the approved preview app at
// `docs/signup-designs/PublicSalonProfile/lib/widgets/salon_widgets.dart`.
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • Hard-coded UA strings → AppLocalizations
//   • [SalonMasterCard] lives in its own file (`salon_master_card.dart`) per
//     the phase's file list — not ported here.

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Extent (height == width) of the rounded-square controls that float over
/// the cover photo (back button, favourite heart). 48, not 44 — matches the
/// app-wide rounded-square control size used everywhere else (e.g.
/// [NeumorphicIconButton.extent], the sibling [PublicMasterProfileScreen]'s
/// favourite toggle), which this cover control now shares the shape of too
/// (see [CoverIconButton]).
const double kCoverControlSize = 48;

/// The salon logo mark — a raised circular surface filled with a camel/mocha
/// gradient. Mirrors [ProfileAvatar]'s depth and gradient language (the master
/// photo) so the salon hero and the master hero read as one family. Carries a
/// single embossed initial ([monogram]) when supplied; falls back to a
/// storefront glyph.
///
/// Phase 369 (9.8) — paints the salon's uploaded logo ([imageUrl]) inside the
/// cream ring through the allow-listed, disk-cached [RemoteImage], clipped to
/// the circle; null, a disallowed host or a failed fetch keep exactly today's
/// monogram. The owner's editor (management hero) additionally passes a just
/// picked [previewFile], an upload [overlay] and an [editBadge]. Every new
/// parameter is additive and defaults to "absent": a caller passing none of
/// them renders byte-identically to before.
class SalonLogo extends StatelessWidget {
  const SalonLogo({
    super.key,
    this.diameter = VelvetSizes.logoTile,
    this.monogram,
    this.logoGradient = const <Color>[Color(0xFFD8BE9C), Color(0xFF6A4A28)],
    this.imageUrl,
    this.previewFile,
    this.overlay,
    this.editBadge,
  });

  final double diameter;

  /// Single brand initial shown embossed at the centre (e.g. «В» for «Вельвет»).
  /// Null → storefront glyph.
  final String? monogram;
  final List<Color> logoGradient;

  /// Phase 369 — the salon's logo (`Salon.avatarUrl`). Null → the monogram.
  final String? imageUrl;

  /// Phase 369 — a just-picked local file shown instead of [imageUrl] while
  /// it uploads (owner editor only). Goes through [LocalPreviewImage].
  final File? previewFile;

  /// Phase 369 — painted over the logo inside the ring, clipped to the circle
  /// (the 072 `UploadProgressOverlay` / `UploadFailedOverlay`, `circular`).
  final Widget? overlay;

  /// Phase 369 — the owner's camera badge (`PhotoEditBadge`), seated at the
  /// mark's lower-right inside its [diameter] box (no overhang, so the hero's
  /// text column keeps its gutter). Never passed on a read-only surface.
  final Widget? editBadge;

  @override
  Widget build(BuildContext context) {
    final Widget? editBadge = this.editBadge;
    final Widget mark = Semantics(
      label: AppLocalizations.of(context).salonLogoSemanticLabel,
      image: true,
      child: Container(
        height: diameter,
        width: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: logoGradient,
          ),
          boxShadow: VelvetShadows.extrudedSmall,
          // A hairline cream ring lifts the mark off both the cover and the
          // hero card it straddles, the way a printed monogram catches light.
          border: Border.all(
            color: BrandColors.white.withValues(alpha: 0.35),
            width: _borderWidth,
          ),
        ),
        child: _content(),
      ),
    );
    if (editBadge == null) return mark;
    return SizedBox(
      height: diameter,
      width: diameter,
      child: Stack(
        children: <Widget>[
          mark,
          Positioned(right: 0, bottom: 0, child: editBadge),
        ],
      ),
    );
  }

  /// Today's monogram / storefront glyph — the no-photo state and the
  /// fallback of every photo source.
  Widget _monogram() => Center(
    child: monogram == null
        ? Icon(
            Icons.storefront_rounded,
            color: BrandColors.white.withValues(alpha: 0.85),
            size: diameter * 0.42,
          )
        : Text(
            monogram!,
            style: GoogleFonts.comfortaa(
              fontSize: diameter * 0.44,
              fontWeight: FontWeight.w700,
              color: BrandColors.white.withValues(alpha: 0.92),
            ),
          ),
  );

  Widget _content() {
    final Widget monogramMark = _monogram();
    final File? preview = previewFile;
    final String? url = imageUrl;
    final Widget? overlay = this.overlay;
    if (preview == null && url == null && overlay == null) return monogramMark;
    // Inside the 2 dp cream border.
    final double inner = imageDiameter(diameter);
    final Widget image = preview != null
        ? LocalPreviewImage(
            file: preview,
            width: inner,
            height: inner,
            fallback: monogramMark,
          )
        : url != null
        ? RemoteImage(
            url: url,
            width: inner,
            height: inner,
            shape: RemoteImageShape.circle,
            excludeFromSemantics: true,
            fallback: monogramMark,
          )
        : monogramMark;
    // Phase 369 audit (mobile-perf INFO) — the [RemoteImage] branch is
    // clipped twice (its own `ClipOval` + this one). KEPT ON PURPOSE: the two
    // anti-aliased clips compound on the ring edge, and dropping either one
    // moves 195–225 px on the logo goldens (`salon_logo_photo`,
    // `salon_logo_owner_badge`, `salon_manage_hero_*`). Removing it is a
    // baseline change (user call), not a free perf fix; a logo-sized oval
    // clip is cheap.
    if (overlay != null) {
      return ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RepaintBoundary(child: image),
            overlay,
          ],
        ),
      );
    }
    return ClipOval(child: image);
  }

  /// Width of the hairline cream ring.
  static const double _borderWidth = 2;

  /// The logical diameter the photo is decoded at inside a [diameter] mark
  /// (inside the cream ring) — what a precache must request to hit the cache.
  static double imageDiameter(double diameter) => diameter - 2 * _borderWidth;
}

/// Paints the soft atmosphere inside the salon cover: a warm diagonal sheen
/// from the top-left light source, a faint repeating mark pattern, and a
/// gentle vignette that darkens the bottom edge so the overlapping hero card
/// and the white floating controls keep their contrast.
class _CoverAtmospherePainter extends CustomPainter {
  const _CoverAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Warm top-left bloom — the light catching the surface.
    final Paint bloom = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.7, -0.9),
        radius: 1.2,
        colors: <Color>[
          BrandColors.white.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bloom);

    // Faint diagonal mark pattern — a sparse field of soft camel strokes.
    final Paint mark = Paint()
      ..color = BrandColors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const double gap = 34;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), mark);
    }

    // Bottom vignette — darkens the lower edge where the hero card overlaps.
    final Paint vignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.transparent,
          BrandColors.accentDeep.withValues(alpha: 0.45),
        ],
        stops: const <double>[0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(_CoverAtmospherePainter oldDelegate) => false;
}

/// Phase 369 — the legibility veil over a real cover PHOTO: a soft espresso
/// fall-off under the floating top controls and the same bottom vignette the
/// placeholder paints (where the hero card overlaps). No sheen / texture — a
/// photo carries its own.
class _CoverPhotoScrimPainter extends CustomPainter {
  const _CoverPhotoScrimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint top = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          BrandColors.accentDeep.withValues(alpha: 0.32),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.4],
      ).createShader(rect);
    canvas.drawRect(rect, top);
    final Paint vignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.transparent,
          BrandColors.accentDeep.withValues(alpha: 0.45),
        ],
        stops: const <double>[0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(_CoverPhotoScrimPainter oldDelegate) => false;
}

/// The full-bleed salon cover photo. The salon owner uploads a
/// `coverImageUrl`; when [imageUrl] is null this renders an offline-safe
/// stand-in — a warm camel→mocha gradient with a painted sheen, a faint
/// texture and a vignette — plus a centred photo glyph.
///
/// Phase 369 (9.8) — [imageUrl] is now RENDERED (it was accepted but never
/// painted): `BoxFit.cover` through the allow-listed, disk-cached
/// [RemoteImage], under a legibility veil for the floating controls and the
/// overlapping hero card. A null / disallowed URL renders exactly today's
/// placeholder; a failed fetch falls back to it. The owner's editor (the
/// management hero) also passes a just-picked [previewFile] and an upload
/// [overlay]; both are additive and absent everywhere else, so the cover stays
/// read-only for clients.
class SalonCover extends StatelessWidget {
  const SalonCover({
    super.key,
    required this.height,
    required this.topInset,
    this.imageUrl,
    this.coverGradient = const <Color>[
      Color(0xFF8A6840),
      Color(0xFF6A4A28),
      Color(0xFF4A3322),
    ],
    this.previewFile,
    this.overlay,
  });

  final double height;

  /// Top safe-area inset of the enclosing screen — this Stack's own origin
  /// IS the screen's top edge (only the bottom of the cover is padded out
  /// for the overlapping hero card), so this must match the offset the
  /// caller's back/favourite [CoverIconButton]s use for their own
  /// `Positioned.top` to keep the cover's controls aligned in one row.
  final double topInset;

  /// The salon's uploaded cover photo URL. Null (or a host outside the media
  /// allow-list) renders the gradient placeholder.
  final String? imageUrl;
  final List<Color> coverGradient;

  /// Phase 369 — a just-picked local file shown instead of [imageUrl] while it
  /// uploads (owner editor only).
  final File? previewFile;

  /// Phase 369 — painted over the whole cover (the 072 upload overlays).
  final Widget? overlay;

  /// Painted atmosphere (bloom + texture + vignette) and the centred photo
  /// glyph — the no-photo state and the fallback of every photo source.
  static Widget _placeholder() => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      const CustomPaint(painter: _CoverAtmospherePainter()),
      // Centred photo glyph — reinforces "this is a cover image slot".
      Center(
        child: Icon(
          Icons.photo_camera_back_outlined,
          size: 44,
          color: BrandColors.white.withValues(alpha: 0.28),
        ),
      ),
    ],
  );

  Widget _photo(BuildContext context, BoxConstraints c) {
    final double width = c.maxWidth.isFinite
        ? c.maxWidth
        : MediaQuery.sizeOf(context).width;
    final Widget fallback = _placeholder();
    final File? preview = previewFile;
    if (preview != null) {
      return LocalPreviewImage(
        file: preview,
        width: width,
        height: height,
        fallback: fallback,
      );
    }
    return RemoteImage(
      url: imageUrl,
      width: width,
      height: height,
      // Full-bleed: square corners.
      borderRadius: BorderRadius.zero,
      excludeFromSemantics: true,
      fallback: fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPhoto = previewFile != null || isAllowedMediaUrl(imageUrl);
    final Widget? overlay = this.overlay;
    final Widget placeholder = _placeholder();
    return Semantics(
      label: AppLocalizations.of(context).salonCoverSemanticLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Base warm gradient — stands in for the uploaded cover photo
            // (and sits under a real one while it decodes).
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: coverGradient,
                ),
              ),
            ),
            if (hasPhoto)
              // Phase 369 audit (mobile-perf LOW) — the photo + its scrim on
              // their own layer, so an upload overlay ticking above (and the
              // floating controls) never re-rasterise the full-bleed bitmap.
              RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) =>
                          _photo(context, c),
                    ),
                    const CustomPaint(painter: _CoverPhotoScrimPainter()),
                  ],
                ),
              )
            else
              placeholder,
            ?overlay,
          ],
        ),
      ),
    );
  }
}

/// A rounded-square frosted-cream control that floats over the cover photo
/// (back + favourite) — matches the app-wide rounded-square icon-button shape
/// (see [NeumorphicIconButton] / [VelvetRadii.field]) rather than a bespoke
/// circle, so this control reads as the same family as every other icon
/// button in the app. Unlike the page's base-toned neumorphic chips, this
/// sits on a dark photographic surface, so it uses a translucent cream fill
/// with a soft drop shadow to stay legible against any cover.
class CoverIconButton extends StatefulWidget {
  const CoverIconButton({
    super.key,
    this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.iconColor = BrandColors.text,
    this.toggled,
    this.svgIcon,
    this.svgIconTint,
  }) : assert(
         (icon == null) != (svgIcon == null),
         'Provide exactly one of icon or svgIcon.',
       );

  /// Material glyph. Ignored when [svgIcon] is set; exactly one of the two
  /// must be supplied (enforced by an assert).
  final IconData? icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color iconColor;

  /// When non-null the control is a toggle (the favourite heart) and animates
  /// a brief over-shoot on change.
  final bool? toggled;

  /// SVG asset path (from `BeauticaAssetIcons`) — when non-null, [AppIcon] is
  /// rendered instead of [Icon], taking precedence over [icon]. Rendered
  /// `multicolor: true` (no `srcIn` tint) so multi-tone assets — e.g. the
  /// notification bell's baked-in unread dot — keep their own palette;
  /// [iconColor] is ignored in this branch.
  final String? svgIcon;

  /// Phase 361 — when non-null, [svgIcon] is flattened to this single tint
  /// (`srcIn`) instead of rendering `multicolor`. Used by the idle (dotless)
  /// notification bell; the unread asset keeps `null` so its dot survives.
  /// Ignored when [svgIcon] is null. Default `null` = unchanged behaviour.
  final Color? svgIconTint;

  @override
  State<CoverIconButton> createState() => _CoverIconButtonState();
}

class _CoverIconButtonState extends State<CoverIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool? toggled = widget.toggled;
    return Semantics(
      button: true,
      toggled: toggled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            height: kCoverControlSize,
            width: kCoverControlSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              color: BrandColors.white.withValues(alpha: 0.86),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: BrandColors.accentDeep.withValues(alpha: 0.32),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: AnimatedScale(
                scale: toggled == true ? 1.14 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.elasticOut,
                // Sizes intentionally differ: the design (SalonManagementDesign
                // salon_widgets.dart:245 CoverIconButton renders Icon at
                // size: 21; notification_bell.dart:20/27 NotificationBellGlyph
                // defaults to size: 20, matched explicitly at
                // salon_profile_screen.dart:420) makes the SVG bell 1dp
                // smaller than its Material siblings as a deliberate optical-
                // weight choice — do not collapse these into one constant.
                child: widget.svgIcon != null
                    ? AppIcon(
                        widget.svgIcon!,
                        size: 20,
                        color: widget.svgIconTint,
                        multicolor: widget.svgIconTint == null,
                      )
                    : Icon(widget.icon!, size: 21, color: widget.iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// SalonTabBar — PROMOTED to `lib/shared/widgets/profile_tab_bar.dart` as
// `ProfileTabBar` (Phase 351, REUSE-FIRST). Import that instead; every call
// site here keeps its exact `Key('salon-tab-$i')` finders via the widget's
// default `keyPrefix: 'salon'`.
