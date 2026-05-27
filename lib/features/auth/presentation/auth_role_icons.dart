// Line-art role glyphs — exact transcription of the SVG `path`s in
// role-selection-page.html (lines 313–362). The approved design uses three
// specific stroke icons that the Material icon set does not reproduce
// faithfully, so each is drawn with a [CustomPainter] from the original SVG
// path data (24×24 viewBox, stroke-width 1.6, round joins, no fill).
//
//   CLIENT             → circle(12,7,r=4) + path M4 21c0-4.418 3.582-8 8-8s8 3.582 8 8
//   SALON_OWNER        → path M3 10.5L12 3l9 7.5V21… (house with roof) + door M9 21V12h6v9
//   INDEPENDENT_MASTER → path M20.84 4.61a5.5 5.5 0 0 0-7.78 0… (heart)
//
// Painted into a 24-logical-px box (`.role-icon svg { width:22px }` in the
// mockup → 22, but the parent circle is 44px; we render the glyph at 22 to
// match). The colour is supplied by the caller so the selected/unselected
// camel/white state is driven from the card.

import 'package:flutter/material.dart';

/// Which role glyph to paint.
enum AuthRoleGlyph { client, salonOwner, independentMaster }

/// A 22×22 stroke glyph matching the role-selection-page.html SVG paths.
class AuthRoleIcon extends StatelessWidget {
  const AuthRoleIcon({super.key, required this.glyph, required this.color});

  final AuthRoleGlyph glyph;
  final Color color;

  // role-selection-page.html: .role-icon svg { width: 22px; height: 22px }.
  static const double _kSize = 22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSize,
      height: _kSize,
      child: CustomPaint(
        painter: _RoleIconPainter(glyph: glyph, color: color),
        // Decorative: the card title/desc carry the semantic meaning.
        isComplex: false,
      ),
    );
  }
}

class _RoleIconPainter extends CustomPainter {
  const _RoleIconPainter({required this.glyph, required this.color});

  final AuthRoleGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox is 0 0 24 24 → scale to the painted box.
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      // role-selection-page.html: stroke-width="1.6".
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;

    switch (glyph) {
      case AuthRoleGlyph.client:
        // circle cx=12 cy=7 r=4
        canvas.drawCircle(const Offset(12, 7), 4, stroke);
        // path M4 21c0-4.418 3.582-8 8-8s8 3.582 8 8
        final body = Path()
          ..moveTo(4, 21)
          ..cubicTo(4, 21 - 4.418, 3.582 + 4, 13, 12, 13)
          ..cubicTo(12 + 4.418, 13, 20, 21 - 4.418, 20, 21);
        canvas.drawPath(body, stroke);

      case AuthRoleGlyph.salonOwner:
        // path M3 10.5L12 3l9 7.5V21a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10.5z
        final house = Path()
          ..moveTo(3, 10.5)
          ..lineTo(12, 3)
          ..lineTo(21, 10.5)
          ..lineTo(21, 21)
          // a1 1 0 0 1-1 1  → rounded bottom-right corner
          ..arcToPoint(
            const Offset(20, 22),
            radius: const Radius.circular(1),
            clockwise: true,
          )
          ..lineTo(4, 22)
          // a1 1 0 0 1-1-1  → rounded bottom-left corner
          ..arcToPoint(
            const Offset(3, 21),
            radius: const Radius.circular(1),
            clockwise: true,
          )
          ..close();
        canvas.drawPath(house, stroke);
        // path M9 21V12h6v9  (door)
        final door = Path()
          ..moveTo(9, 21)
          ..lineTo(9, 12)
          ..lineTo(15, 12)
          ..lineTo(15, 21);
        canvas.drawPath(door, stroke);

      case AuthRoleGlyph.independentMaster:
        // path M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06
        //      a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78
        //      1.06-1.06a5.5 5.5 0 0 0 0-7.78z   (heart)
        final heart = Path()
          ..moveTo(20.84, 4.61)
          ..arcToPoint(
            const Offset(13.06, 4.61),
            radius: const Radius.circular(5.5),
            clockwise: false,
          )
          ..lineTo(12, 5.67)
          ..lineTo(10.94, 4.61)
          ..arcToPoint(
            const Offset(3.16, 12.39),
            radius: const Radius.circular(5.5),
            clockwise: false,
          )
          ..lineTo(4.22, 13.45)
          ..lineTo(12, 21.23)
          ..lineTo(19.78, 13.45)
          ..lineTo(20.84, 12.39)
          ..arcToPoint(
            const Offset(20.84, 4.61),
            radius: const Radius.circular(5.5),
            clockwise: false,
          )
          ..close();
        canvas.drawPath(heart, stroke);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoleIconPainter old) =>
      old.glyph != glyph || old.color != color;
}
