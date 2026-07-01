// Phase 13.6 — Salon cover + hero chrome widgets.
//
// Ported verbatim (token names only) from the approved preview app at
// `docs/signup-designs/PublicSalonProfile/lib/widgets/salon_widgets.dart`.
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • Hard-coded UA strings → AppLocalizations
//   • [SalonMasterCard] lives in its own file (`salon_master_card.dart`) per
//     the phase's file list — not ported here.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The salon logo mark — a raised circular surface filled with a camel/mocha
/// gradient. Mirrors [ProfileAvatar]'s depth and gradient language (the master
/// photo) so the salon hero and the master hero read as one family. Carries a
/// single embossed initial ([monogram]) when supplied; falls back to a
/// storefront glyph. Production: becomes an [Image.network] of the salon's
/// real logo once uploaded, with the monogram as the placeholder.
class SalonLogo extends StatelessWidget {
  const SalonLogo({
    super.key,
    this.diameter = VelvetSizes.logoTile,
    this.monogram,
    this.logoGradient = const <Color>[Color(0xFFD8BE9C), Color(0xFF6A4A28)],
  });

  final double diameter;

  /// Single brand initial shown embossed at the centre (e.g. «В» for «Вельвет»).
  /// Null → storefront glyph.
  final String? monogram;
  final List<Color> logoGradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
            width: 2,
          ),
        ),
        child: Center(
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
        ),
      ),
    );
  }
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

/// The full-bleed salon cover photo. The salon owner uploads a
/// `coverImageUrl`; when [imageUrl] is null this renders an offline-safe
/// stand-in — a warm camel→mocha gradient with a painted sheen, a faint
/// texture and a vignette — plus a centred photo glyph.
///
/// The cover is **read-only for clients**. The small camel "Обкладинка" pill
/// in the corner signals that this surface is the salon's own uploadable
/// cover slot (the owner-edit affordance is a future phase).
class SalonCover extends StatelessWidget {
  const SalonCover({
    super.key,
    required this.height,
    this.imageUrl,
    this.coverGradient = const <Color>[
      Color(0xFF8A6840),
      Color(0xFF6A4A28),
      Color(0xFF4A3322),
    ],
  });

  final double height;

  /// The salon's uploaded cover photo URL. Null renders the gradient
  /// placeholder (no real photo pipeline wired yet).
  final String? imageUrl;
  final List<Color> coverGradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).salonCoverSemanticLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Base warm gradient — stands in for the uploaded cover photo.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: coverGradient,
                ),
              ),
            ),
            // Painted atmosphere: bloom + texture + vignette.
            const CustomPaint(painter: _CoverAtmospherePainter()),
            // Centred photo glyph — reinforces "this is a cover image slot".
            Center(
              child: Icon(
                Icons.photo_camera_back_outlined,
                size: 44,
                color: BrandColors.white.withValues(alpha: 0.28),
              ),
            ),
            // Editable-cover affordance pill (bottom-left, clear of the hero).
            const Positioned(
              left: VelvetSpacing.lg,
              bottom: VelvetSpacing.md,
              child: _CoverEditPill(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small translucent camel pill that marks the cover as the salon's own
/// uploadable slot ("Обкладинка"). Read-only in the client view.
class _CoverEditPill extends StatelessWidget {
  const _CoverEditPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: VelvetSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: BrandColors.accentDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BrandColors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            size: 13,
            color: BrandColors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: VelvetSpacing.xs + 1),
          Text(
            AppLocalizations.of(context).salonCoverEditPillLabel,
            style: VelvetText.feedback(
              BrandColors.white,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// A circular frosted-cream control that floats over the cover photo (back +
/// favourite). Unlike the page's base-toned neumorphic chips, these sit on a
/// dark photographic surface, so they use a translucent cream fill with a
/// soft drop shadow to stay legible against any cover.
class CoverCircleButton extends StatefulWidget {
  const CoverCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.iconColor = BrandColors.text,
    this.toggled,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color iconColor;

  /// When non-null the control is a toggle (the favourite heart) and animates
  /// a brief over-shoot on change.
  final bool? toggled;

  @override
  State<CoverCircleButton> createState() => _CoverCircleButtonState();
}

class _CoverCircleButtonState extends State<CoverCircleButton> {
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
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
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
                child: Icon(widget.icon, size: 21, color: widget.iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The salon profile's section switcher — "Про салон" · "Майстри" ·
/// "Послуги" · "Відгуки". A row of text tabs over a faint hairline, with a
/// single camel underline that slides under the active tab. Selection is
/// owned by the parent.
class SalonTabBar extends StatelessWidget {
  const SalonTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BrandColors.faint, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: _SalonTab(
                label: tabs[i],
                active: i == selected,
                onTap: () => onSelect(i),
                tabKey: Key('salon-tab-$i'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SalonTab extends StatelessWidget {
  const _SalonTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.tabKey,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Key tabKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: tabKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: VelvetSpacing.sm + 2,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VelvetText.subheading().copyWith(
                  // 12 (not the original 14) — "Про салон" at w700 Comfortaa
                  // is the widest of the 4 labels and, at 14px, its natural
                  // width (~82px) exceeds a quarter-screen segment on a
                  // 360dp-wide phone (~78dp after the screen's lg/24dp
                  // margins), forcing a wrap. 12px keeps every label on one
                  // line with headroom down to ~360dp; maxLines/overflow
                  // above are the safety net below that.
                  fontSize: 12,
                  color: active ? BrandColors.text : BrandColors.muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            // Sliding camel underline — 3px under the active tab only.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 3,
              width: active ? 44 : 0,
              decoration: BoxDecoration(
                color: BrandColors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
