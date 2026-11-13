// Promoted 2026-11-12 (phase 481) from `master_booking_card.dart`'s private
// `_FixedLinesText` / `_fixedLineHeight` — moved, not copied (REUSE-FIRST).
// The original constructor renders exactly what the private widget rendered;
// [FixedLinesText.fit] is the additive height-driven mode ported from the
// MasterWeekBookings preview's `FitLinesText`.

import 'package:flutter/material.dart';

/// Line-height multiple used when a slot's style carries no explicit `height`
/// (the client-name tokens inherit the font's own metrics, which cannot be
/// computed without a layout pass).
const double kFixedLinesFallbackLineHeight = 1.15;

/// One line box of [style] under the ambient text scaler, in WHOLE dp:
/// `ceil(scaledFontSize x lineHeight)`. Font-independent: it reads only the
/// style's size and (explicit or fallback) height multiple, never the font's
/// ascent/descent. Whole dp so a dense card's height is never fractional.
double fixedLineHeight(BuildContext context, TextStyle style) {
  final double fontSize = style.fontSize ?? 14;
  final double lineHeight = style.height ?? kFixedLinesFallbackLineHeight;
  return (MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight)
      .ceilToDouble();
}

/// A text that ALWAYS occupies exactly [lines] lines of [style]: `maxLines:
/// lines` + ellipsis inside a fixed `SizedBox` of `lines x fixedLineHeight`,
/// with a forced strut so every line box is exactly that tall whatever font
/// renders. A one-line name and a wrapped one therefore render the SAME
/// height, which keeps `MasterBookingCard.occupiedHeightFor(dense: true)`
/// exact on every device.
///
/// [FixedLinesText.fit] is the height-driven mode: it takes as many WHOLE
/// lines as the height it is given allows (`floor(available / line)`, min 1),
/// ellipsizes the last one, and never shrinks the type — text scale 1.3 just
/// yields fewer lines. Unbounded height falls back to [lines] (1 by default,
/// the shipped one-line behaviour). The fit box is the text's own height
/// (top-aligned), not `lines x line`, so a short text in a tall slot is not
/// vertically centred.
class FixedLinesText extends StatelessWidget {
  const FixedLinesText(
    this.text, {
    super.key,
    required this.style,
    this.lines = 1,
    this.semanticsLabel,
  }) : fit = false,
       availableHeight = null;

  /// Height-driven mode — see the class doc.
  const FixedLinesText.fit(
    this.text, {
    super.key,
    required this.style,
    this.semanticsLabel,
    this.lines = 1,
    this.availableHeight,
  }) : fit = true;

  final String text;

  /// Overrides what a screen reader announces (the full name when [text] is
  /// the first name only). `null` announces [text].
  final String? semanticsLabel;
  final TextStyle style;

  /// Exact line count; in [fit] mode, the count used when height is unbounded.
  final int lines;

  /// `true` for [FixedLinesText.fit].
  final bool fit;

  /// [fit] mode only: the height the caller ALREADY knows it has (e.g. from
  /// its own `LayoutBuilder`). Non-null skips this widget's `LayoutBuilder`
  /// and takes `linesFor(availableHeight, line)` lines — same rendering, one
  /// layout callback fewer. `null` (default) measures the parent as before.
  final double? availableHeight;

  /// Whole lines of [lineHeight] that fit in [available] dp, at least 1.
  static int linesFor(double available, double lineHeight) {
    if (lineHeight <= 0) return 1;
    final int n = (available / lineHeight + 1e-6).floor();
    return n < 1 ? 1 : n;
  }

  Text _text(int maxLines) => Text(
    text,
    style: style,
    strutStyle: StrutStyle.fromTextStyle(
      style,
      height: style.height ?? kFixedLinesFallbackLineHeight,
      forceStrutHeight: true,
    ),
    semanticsLabel: semanticsLabel,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );

  @override
  Widget build(BuildContext context) {
    final double line = fixedLineHeight(context, style);
    if (fit) {
      final double? known = availableHeight;
      if (known != null) {
        return Align(
          alignment: Alignment.topLeft,
          heightFactor: 1,
          child: _text(linesFor(known, line)),
        );
      }
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final int n = c.hasBoundedHeight
              ? linesFor(c.maxHeight, line)
              : lines;
          // `heightFactor: 1` — the box is the text's own height, so a loose
          // bounded parent never stretches it (a tight one still sizes it).
          return Align(
            alignment: Alignment.topLeft,
            heightFactor: 1,
            child: _text(n),
          );
        },
      );
    }
    return SizedBox(
      height: line * lines,
      child: Align(alignment: Alignment.centerLeft, child: _text(lines)),
    );
  }
}
