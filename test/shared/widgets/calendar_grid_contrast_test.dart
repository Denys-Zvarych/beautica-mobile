// WCAG contrast + CIE Lab ΔE76 guard for the calendar-grid weekend tone
// (`lib/shared/widgets/calendar_grid.dart`'s [CalendarWeekdayBar], and the
// `BrandColors.weekendMuted` token it — and `month_calendar.dart`'s
// `_dayCell`, `period_range_picker.dart`'s `_DayCell`, and
// `bookings_day_rail.dart`'s `_DayChip` — all read).
//
// WHY THIS FILE EXISTS
// ---------------------
// mobile-security finding (MEDIUM, in-diff on the D3 weekend-muting fix):
// `BrandColors.muted` (#9A8367) measures 2.69:1 on `BrandColors.base`
// (#E6DDD0) — well under WCAG AA's 4.5:1 floor for normal text — but the D3
// fix applied it to weekend captions/day-numbers at four call sites, all of
// which are ACTIVE (tappable or always-visible) text, so WCAG 1.4.3's
// "inactive user interface component" exemption never covers it.
//
// FIRST FIX (WRONG AXIS)
// -----------------------
// `BrandColors.weekendMuted` (#745C47) replaced `BrandColors.muted` at every
// weekend call site, found by binary-searching the `muted` -> `textSecondary`
// LIGHTNESS axis for the most de-emphasized point that still cleared AA.
// That axis is a dead end: against a light base, contrast RISES as the text
// darkens, so "more de-emphasized" (lighter) and "still >= 4.5:1" pull in
// opposite directions — the legal band between the AA floor and the weekday
// tone's own 5.03:1 is a sliver. `#745C47` sat right at the edge of it:
// CIE Lab ΔE76 versus `textSecondary` was only ~2.2, essentially AT the
// ~2.3 just-noticeable-difference threshold — the weekend cue the user
// actually asked for ("put these columns into gray colour") was very likely
// invisible in practice even though it cleared AA on paper. mobile-security
// re-audit LOW.
//
// THE FIX (HUE/CHROMA AXIS)
// ---------------------------
// `BrandColors.weekendMuted` (#5F5A55) now moves along the HUE/CHROMA axis
// instead: `textSecondary`'s warm-neutral RGB, desaturated toward true gray,
// at the SAME (not lighter) darkness — darkness is free contrast on a light
// base, so de-emphasis comes from dropping chroma, not from washing out.
// This clears AA with a WIDER margin than `textSecondary` itself (since it
// is no lighter) while sitting a CIE Lab ΔE76 of ~12.8 away from it —
// comfortably clear of the JND floor, so the cue is actually visible — and
// reads as gray rather than another brown because its own chroma collapses
// to a residual warm cast an order of magnitude below `textSecondary`'s.
//
// WHAT THIS FILE PROVES
// ----------------------
// COMPUTED assertions, not goldens — mobile-security explicitly warned a
// golden cannot catch a contrast OR a perceptibility regression (a
// screenshot diff has no idea what "4.5:1" or "ΔE76 >= 8" mean). This pins:
//   1. `weekendMuted` vs `base` is >= 4.5:1 (the AA floor itself).
//   2. `textSecondary` vs `base` (the weekday tone) is also >= 4.5:1, so the
//      comparison in (3) is meaningful — both tones are legal on their own.
//   3. `weekendMuted` is a CIE Lab ΔE76 of >= 8 away from `textSecondary` —
//      i.e. actually PERCEPTIBLE as a distinct, de-emphasized tone, not
//      merely legally distinct. This replaces a former "weekendMuted must
//      read as strictly LESS contrasty than textSecondary" assertion, which
//      encoded the abandoned lightness-axis theory: on the hue/chroma axis
//      the new tone is legitimately allowed to have an EQUAL OR HIGHER
//      contrast ratio than the weekday tone (it does — see test below) while
//      still reading as visibly, measurably distinct, which is the property
//      that actually guarantees the user can see the weekend cue.
//   4. `muted` (the token this replaces at every weekend site) is NOT
//      reintroduced by accident — it stays under 4.5:1, documenting exactly
//      why it could never have been the fix.
//
// Layer: pure Dart colour math, no widget pump needed — the property under
// test is a relationship between two `Color` constants, not anything a
// render tree resolves.

import 'dart:math' as math;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// WCAG 2.x relative luminance + contrast ratio — same textbook formula as
// `test/features/home/presentation/widgets/hub_filled_button_contrast_test
// .dart` (checked: still no shared helper location for this, so it is
// self-contained here too rather than inventing one for two consumers).
// ---------------------------------------------------------------------------

double _linearise(double channel255) {
  final double c = channel255 / 255.0;
  if (c <= 0.03928) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color c) {
  final double r = _linearise(c.r * 255);
  final double g = _linearise(c.g * 255);
  final double b = _linearise(c.b * 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colours, always >= 1.0.
double _contrastRatio(Color a, Color b) {
  final double la = _relativeLuminance(a);
  final double lb = _relativeLuminance(b);
  final double lighter = math.max(la, lb);
  final double darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

// ---------------------------------------------------------------------------
// CIE Lab ΔE76 — sRGB -> linear -> XYZ (D65) -> Lab -> Euclidean distance.
//
// This is the property the lightness-axis fix could never pin: two colours
// can both individually clear WCAG AA against the same background while
// being nearly indistinguishable FROM EACH OTHER (that is exactly what
// happened to the first `weekendMuted` — ΔE76 ~2.2 against `textSecondary`,
// right at the ~2.3 just-noticeable-difference threshold). WCAG contrast
// ratio says nothing about that; CIE Lab distance is the standard
// perceptual-difference metric that does.
// ---------------------------------------------------------------------------

/// D65 reference white (CIE standard illuminant), used to normalise XYZ
/// before the Lab nonlinearity.
const double _xn = 0.95047;
const double _yn = 1.00000;
const double _zn = 1.08883;

double _labF(double t) {
  const double delta = 6 / 29;
  if (t > delta * delta * delta) {
    return math.pow(t, 1 / 3).toDouble();
  }
  return t / (3 * delta * delta) + 4 / 29;
}

/// sRGB (0-255 channels) -> CIE XYZ under D65, via the linearised channel
/// [_linearise] already computes for WCAG luminance.
(double, double, double) _rgbToXyz(Color c) {
  final double r = _linearise(c.r * 255);
  final double g = _linearise(c.g * 255);
  final double b = _linearise(c.b * 255);
  final double x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375;
  final double y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
  final double z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041;
  return (x, y, z);
}

/// CIE Lab (L*, a*, b*) for [c], relative to the D65 reference white.
(double, double, double) _rgbToLab(Color c) {
  final (double x, double y, double z) = _rgbToXyz(c);
  final double fx = _labF(x / _xn);
  final double fy = _labF(y / _yn);
  final double fz = _labF(z / _zn);
  final double l = 116 * fy - 16;
  final double a = 500 * (fx - fy);
  final double b = 200 * (fy - fz);
  return (l, a, b);
}

/// CIE76 colour difference between [a] and [b] — the Euclidean distance
/// between their Lab coordinates. ~2.3 is the commonly-cited
/// just-noticeable-difference (JND) threshold; below it, two colours read as
/// "the same" to most viewers even side by side.
double _deltaE76(Color a, Color b) {
  final (double l1, double a1, double b1) = _rgbToLab(a);
  final (double l2, double a2, double b2) = _rgbToLab(b);
  final double dl = l1 - l2;
  final double da = a1 - a2;
  final double db = b1 - b2;
  return math.sqrt(dl * dl + da * da + db * db);
}

const double _kWcagAaNormalText = 4.5;

/// Comfortably clear of the ~2.3 JND floor — the bar this fix is held to so
/// the weekend cue is not merely legally distinct but actually perceptible.
const double _kMinPerceptibleDeltaE = 8.0;

void main() {
  group('BrandColors.weekendMuted vs BrandColors.base', () {
    test('clears WCAG AA (4.5:1) for normal text', () {
      final double ratio = _contrastRatio(
        BrandColors.weekendMuted,
        BrandColors.base,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kWcagAaNormalText),
        reason:
            'weekendMuted (#5F5A55) must clear AA on base (#E6DDD0) — '
            'measured $ratio. This is the tone the D3 weekend cue now '
            'renders at every calendar surface (CalendarWeekdayBar, '
            'MonthCalendar, PeriodRangePicker, BookingsDayRail).',
      );
    });

    test('textSecondary (the weekday tone) also clears WCAG AA on its own', () {
      final double weekdayRatio = _contrastRatio(
        BrandColors.textSecondary,
        BrandColors.base,
      );
      expect(
        weekdayRatio,
        greaterThanOrEqualTo(_kWcagAaNormalText),
        reason:
            'textSecondary (the five weekday captions\' colour) must '
            'itself clear AA for the ΔE76 comparison below to mean '
            'anything — measured $weekdayRatio.',
      );
    });

    test('is a perceptible CIE Lab ΔE76 >= 8 away from textSecondary — the '
        'weekend cue is actually VISIBLE, not merely AA-legal', () {
      final double deltaE = _deltaE76(
        BrandColors.weekendMuted,
        BrandColors.textSecondary,
      );
      expect(
        deltaE,
        greaterThanOrEqualTo(_kMinPerceptibleDeltaE),
        reason:
            'weekendMuted vs textSecondary measured ΔE76=$deltaE. A prior '
            'lightness-axis pick (#745C47) measured ΔE76~2.2 here — right at '
            'the ~2.3 just-noticeable-difference threshold — meaning it was '
            'both AA-legal AND very likely invisible next to the weekday '
            'tone, silently deleting the weekend cue the user asked for '
            '("put these columns into gray colour to indicate weekends"). '
            'This assertion is NOT "weekendMuted must be less contrasty than '
            'textSecondary" (that was the abandoned lightness-axis theory, '
            'and is not required here — see the measured ratio below) — it '
            'is the property that actually guarantees a viewer can tell the '
            'two tones apart.',
      );

      // Documents, rather than requires, the actual relationship: on the
      // hue/chroma axis the new tone is no lighter than textSecondary, so
      // its own contrast ratio is legitimately >= textSecondary's — the
      // opposite of what the lightness-axis fix would have produced.
      final double weekendRatio = _contrastRatio(
        BrandColors.weekendMuted,
        BrandColors.base,
      );
      final double weekdayRatio = _contrastRatio(
        BrandColors.textSecondary,
        BrandColors.base,
      );
      expect(
        weekendRatio,
        greaterThanOrEqualTo(weekdayRatio),
        reason:
            'weekendMuted ($weekendRatio) is expected to be AT LEAST as '
            'contrasty as textSecondary ($weekdayRatio) now that de-emphasis '
            'comes from desaturation rather than from lightening — if this '
            'ever flips, weekendMuted has drifted lighter than textSecondary '
            'again, which the hue/chroma fix deliberately avoids.',
      );
    });
  });

  test('BrandColors.muted stays below AA — documents why it could never be '
      'the weekend fix and guards against it being reintroduced at a weekend '
      'call site', () {
    final double ratio = _contrastRatio(BrandColors.muted, BrandColors.base);
    expect(
      ratio,
      lessThan(_kWcagAaNormalText),
      reason:
          'muted (#9A8367) measured $ratio on base (#E6DDD0) — if this '
          'ever rises >= 4.5:1 the token\'s meaning changed and '
          'weekendMuted\'s own reason for existing should be '
          're-evaluated, not silently left stale.',
    );
  });

  // BrandColors.weekendColumn — the whole-column band behind Saturday/Sunday
  // on the master's expanded «Мої записи» calendar
  // (`MonthCalendar.showWeekendColumnBand`, `CalendarWeekendColumnBand`).
  // Every foreground `month_calendar.dart`'s `_dayCell` can now paint INSIDE
  // that band must still clear WCAG AA against the band itself, not just
  // against `BrandColors.base` — a background swap is exactly the kind of
  // regression a plain "contrast vs base" assertion would miss.
  group('BrandColors.weekendColumn vs the foregrounds that land on it', () {
    test('is a perceptible CIE Lab ΔE76 >= 8 away from base — the band is '
        'actually visible, not merely a rounding difference', () {
      final double deltaE = _deltaE76(
        BrandColors.weekendColumn,
        BrandColors.base,
      );
      expect(
        deltaE,
        greaterThanOrEqualTo(_kMinPerceptibleDeltaE),
        reason:
            'weekendColumn vs base measured ΔE76=$deltaE. Held to the same '
            'bar as weekendMuted\'s own fix above — a band nobody can '
            'actually see is not a weekend cue.',
      );
    });

    test('accentDeep (normal/selected day-number colour) clears AA on the '
        'band', () {
      final double ratio = _contrastRatio(
        BrandColors.accentDeep,
        BrandColors.weekendColumn,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kWcagAaNormalText),
        reason:
            'accentDeep on weekendColumn measured $ratio — this is every '
            'available, unselected weekend day number post-D3-reversal '
            '(`_dayCell` no longer special-cases weekend at all).',
      );
    });

    test('textSecondary (unavailable-but-tappable day-number colour) clears '
        'AA on the band', () {
      final double ratio = _contrastRatio(
        BrandColors.textSecondary,
        BrandColors.weekendColumn,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kWcagAaNormalText),
        reason:
            'textSecondary on weekendColumn measured $ratio — a past '
            'weekend day on `BookingsMonthCalendarPanel` '
            '(`allowTapOnUnavailable: true`) renders this tone inside '
            'the band.',
      );
    });

    test('weekendMuted (the сб/нд weekday captions) clears AA on the band', () {
      final double ratio = _contrastRatio(
        BrandColors.weekendMuted,
        BrandColors.weekendColumn,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kWcagAaNormalText),
        reason:
            'weekendMuted on weekendColumn measured $ratio — '
            'CalendarWeekdayBar keeps its Saturday/Sunday captions this '
            'colour (see that class\'s doc for why: a redundant, still-'
            'legal reinforcement of which two columns the band shades, '
            'not the cue\'s only carrier any more).',
      );
    });
  });
}
