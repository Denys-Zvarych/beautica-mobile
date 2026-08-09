// Phase 238 — [PassportIdentityStrip] widget tests.
//
// WHAT THIS FILE PINS
// -------------------
// The strip's whole reason to exist is that its two FIRST rows — the locked
// «BEAUTY PASSPORT» literal and the client's standing line — are pinned to
// EXACTLY ONE LINE at every viewport by a `FittedBox(BoxFit.scaleDown)`, and
// that they SHRINK rather than wrap, ellipsise or clip. `passport_identity_
// strip.dart`'s header states this as an invariant and adds: "NO `maxLines` AND
// NO `TextOverflow` APPEARS ANYWHERE IN THIS FILE."
//
// A test that only asserted `find.text('BEAUTY PASSPORT') → findsOneWidget`
// would be satisfied by a two-line wrap, by an ellipsised «BEAUTY PASSP…» and
// by a literal clipped off the right edge of the card — all three are the
// failure this widget was built to prevent. So each assertion below is
// GEOMETRIC:
//
//   1. the rendered paragraph box is EXACTLY the size the same span takes when
//      laid out unbounded ⇒ one line, nothing wrapped and nothing clipped;
//   2. `RenderParagraph.didExceedMaxLines` is false;
//   3. the `Text` carries neither `maxLines` nor `overflow` (the structural
//      form of the header's rule — an ellipsis added later fails here even at a
//      width where it would not visibly trigger);
//   4. the PAINTED rect (post-`FittedBox` transform, i.e. what the client
//      actually sees) sits inside the strip's own rect ⇒ the scale-down
//      genuinely happened rather than the literal overhanging the card.
//
// WIDTHS
// ------
// Both required widths are DEVICE widths, and the strip is pumped inside the
// passport page's real horizontal budget — `EdgeInsets.all(VelvetSpacing.lg)`
// on both sides, exactly as `passport_screen.dart`'s ListView applies it. That
// is what makes 360 dp reproduce the widget doc's measured "left column ~134 dp"
// and 320 dp its "~111 dp, literal scales to ~87%".
//
// The year and the review count come from the WIRE (`Passport.memberSinceYear`
// / `reviewsWritten`), never from a clock, so every fixture here is a literal
// int. Nothing in this file reads `DateTime.now()`.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_identity_strip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _kStrip = Key('passport_identity_strip');

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// Pumps the strip at a DEVICE width [width], inside the passport page's own
/// `VelvetSpacing.lg` horizontal padding so the widget sees the same budget it
/// gets on the real page.
Future<void> _pumpStrip(
  WidgetTester tester, {
  required double width,
  int reviewsWritten = 12,
  int memberSinceYear = 2026,
  double? textScaleFactor,
}) async {
  await tester.pumpApp(
    Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: PassportIdentityStrip(
          reviewsWritten: reviewsWritten,
          memberSinceYear: memberSinceYear,
        ),
      ),
    ),
    width: width,
    textScaleFactor: textScaleFactor,
  );
  await tester.pumpAndSettle();
}

/// The size the [Text] found by [finder] would take laid out with NO width
/// constraint — i.e. its natural single-line box.
Size _unboundedTextSize(WidgetTester tester, Finder finder) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(finder);
  final TextPainter painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
  )..layout();
  final Size size = painter.size;
  painter.dispose();
  return size;
}

/// Asserts the [Text] found by [finder] renders on EXACTLY ONE LINE, is not
/// ellipsised or clipped, and — after its `FittedBox` transform — is painted
/// entirely inside [hostRect].
void _expectOneUnclippedLine(
  WidgetTester tester,
  Finder finder, {
  required Rect hostRect,
  required String label,
}) {
  expect(finder, findsOneWidget, reason: '$label must render');

  final Text widget = tester.widget<Text>(finder);
  expect(
    widget.maxLines,
    isNull,
    reason:
        '$label must carry NO maxLines — the one-line guarantee comes from the '
        'FittedBox, and a maxLines here would silently convert a too-wide '
        'literal into a truncation instead of a scale-down',
  );
  expect(
    widget.overflow,
    isNull,
    reason:
        '$label must carry NO TextOverflow — an ellipsis is the exact failure '
        'passport_identity_strip.dart forbids by name',
  );

  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    finder,
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$label must not exceed its line budget',
  );

  final Size laidOut = tester.getSize(finder);
  final Size natural = _unboundedTextSize(tester, finder);
  expect(
    laidOut.width,
    closeTo(natural.width, 0.5),
    reason:
        '$label must occupy its FULL natural width — a narrower box means the '
        'string wrapped or was clipped instead of the FittedBox scaling it '
        '(laidOut=$laidOut natural=$natural)',
  );
  expect(
    laidOut.height,
    closeTo(natural.height, 0.5),
    reason:
        '$label must be exactly ONE line tall — a taller box is a wrap '
        '(laidOut=$laidOut natural=$natural)',
  );

  // The PAINTED rect: getRect applies the FittedBox's scale transform, so this
  // is what the client actually sees rather than the pre-transform layout box.
  final Rect painted = tester.getRect(finder);
  expect(
    painted.left,
    greaterThanOrEqualTo(hostRect.left - 0.5),
    reason: '$label must not be painted past the strip\'s LEFT edge',
  );
  expect(
    painted.right,
    lessThanOrEqualTo(hostRect.right + 0.5),
    reason:
        '$label must not be painted past the strip\'s RIGHT edge — that is the '
        'overhang the FittedBox(scaleDown) exists to prevent (painted=$painted '
        'strip=$hostRect)',
  );
}

void main() {
  // -------------------------------------------------------------------------
  // THE REQUIRED CASE — one line, not ellipsised, at BOTH 320 and 360 dp.
  // -------------------------------------------------------------------------
  group('PassportIdentityStrip — the two FIRST rows never wrap or ellipsise', () {
    for (final double width in <double>[320, 360]) {
      testWidgets('should_renderOneLine_when_titleAtThreeTwentyDp @$width dp', (
        tester,
      ) async {
        await _pumpStrip(tester, width: width);

        final AppLocalizations l10n = await _uk();
        final Rect strip = tester.getRect(find.byKey(_kStrip));

        // Row 1, left column — the locked brand literal.
        _expectOneUnclippedLine(
          tester,
          find.text(kBeautyPassportTitle),
          hostRect: strip,
          label: 'the «BEAUTY PASSPORT» literal',
        );

        // Row 1, right column — the standing line. The SAME guarantee: it is
        // the strip's other FittedBox, and it grows with the review count.
        _expectOneUnclippedLine(
          tester,
          find.text(l10n.passportReviewsLeft(12)),
          hostRect: strip,
          label: 'the reviews-written standing line',
        );
      });
    }

    testWidgets(
      'the literal is genuinely SCALED DOWN at 320 dp, not merely fitting',
      (tester) async {
        // NON-VACUITY PROBE for the pair above. If the literal fitted at full
        // size on both widths, the assertions would be proving nothing about
        // the FittedBox at all — they would pass with the FittedBox deleted.
        // Measuring the painted width against the natural width shows the
        // scale-down is real at the narrow width and the wide one is the
        // comparison baseline.
        await _pumpStrip(tester, width: 320);
        final Finder title = find.text(kBeautyPassportTitle);
        final Rect painted = tester.getRect(title);
        final Size natural = _unboundedTextSize(tester, title);

        // MEASURED 2026-08-07: the left column is 111.4 dp at 320 dp against a
        // natural literal of 134.1 dp, so the scale-down is ~83% — matching the
        // widget doc's "~87%" note within font-metric noise.
        expect(
          painted.width,
          lessThan(natural.width),
          reason:
              'the literal must be genuinely SCALED at 320 dp — if it fitted '
              'at full size the tests above would pass with the FittedBox '
              'deleted, and would be proving nothing',
        );
        // Uniform scale: the painted box shrinks in BOTH axes. Removing the
        // FittedBox makes the width shrink too (the text simply wraps) but the
        // HEIGHT doubles, so this pair is what separates "scaled" from
        // "wrapped".
        expect(
          painted.height,
          lessThan(natural.height),
          reason:
              'BoxFit.scaleDown shrinks uniformly — a painted box that is '
              'narrower but TALLER than natural means the literal wrapped',
        );
        expect(
          painted.width / painted.height,
          closeTo(natural.width / natural.height, 0.05),
          reason: 'the scale must preserve the literal\'s aspect ratio',
        );
      },
    );

    testWidgets(
      'the two SECOND rows are plain, unbounded Text (free to wrap)',
      (tester) async {
        // The counterpart rule from the widget's header: the subtitle and the
        // member-since line are NOT in a FittedBox and must stay free to wrap —
        // so they too carry no maxLines and no overflow.
        await _pumpStrip(tester, width: 320);
        final AppLocalizations l10n = await _uk();

        for (final Finder f in <Finder>[
          find.text(kBeautyPassportSubtitle),
          find.text(l10n.passportMemberSince('2026')),
        ]) {
          expect(f, findsOneWidget);
          final Text w = tester.widget<Text>(f);
          expect(w.maxLines, isNull);
          expect(w.overflow, isNull);
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Content — both right-hand values come from the WIRE, never a clock.
  // -------------------------------------------------------------------------
  group('PassportIdentityStrip — derived standing', () {
    testWidgets(
      'renders the locked brand literals verbatim, not through l10n',
      (tester) async {
        await _pumpStrip(tester, width: 360);

        expect(kBeautyPassportTitle, 'BEAUTY PASSPORT');
        expect(find.byKey(_kStrip), findsOneWidget);
        expect(find.text(kBeautyPassportTitle), findsOneWidget);
        expect(find.text(kBeautyPassportSubtitle), findsOneWidget);
      },
    );

    testWidgets('renders the review count and the member-since YEAR as given', (
      tester,
    ) async {
      await _pumpStrip(
        tester,
        width: 360,
        reviewsWritten: 7,
        // Deliberately NOT the current year: a strip that re-derived the join
        // year from the clock could never produce this value, so the assertion
        // fails against that fabrication instead of passing on a coincidence.
        memberSinceYear: 2019,
      );

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.passportReviewsLeft(7)), findsOneWidget);
      expect(find.text(l10n.passportMemberSince('2019')), findsOneWidget);
      expect(find.text(l10n.passportMemberSince('2026')), findsNothing);
    });

    testWidgets('a brand-new client (0 reviews) still gets a standing line', (
      tester,
    ) async {
      // The `=0` plural branch — «Жодного відгуку залишено». This is what makes
      // the strip meaningful for a client with no history, which is why the
      // page no longer needs an empty hero.
      await _pumpStrip(
        tester,
        width: 320,
        reviewsWritten: 0,
        memberSinceYear: 2026,
      );

      final AppLocalizations l10n = await _uk();
      final Rect strip = tester.getRect(find.byKey(_kStrip));
      _expectOneUnclippedLine(
        tester,
        find.text(l10n.passportReviewsLeft(0)),
        hostRect: strip,
        label: 'the zero-reviews standing line',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Accessibility text scale. The overflow guard installed by pumpApp fails the
  // test on any RenderFlex overflow, so these cells are the a11y regression net
  // for the strip's Row / IntrinsicHeight.
  // -------------------------------------------------------------------------
  group('PassportIdentityStrip — large text scale', () {
    for (final (double width, double scale) in <(double, double)>[
      (320, 1.3),
      (320, 1.5),
      (360, 1.3),
      (360, 1.5),
    ]) {
      testWidgets('no overflow at $width dp @${scale}x', (tester) async {
        await _pumpStrip(
          tester,
          width: width,
          textScaleFactor: scale,
          reviewsWritten: 128,
          memberSinceYear: 2019,
        );

        expect(find.byKey(_kStrip), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The FittedBox rows must STILL be single-line at scale — that is the
        // whole point of scaling down rather than wrapping.
        final Rect strip = tester.getRect(find.byKey(_kStrip));
        _expectOneUnclippedLine(
          tester,
          find.text(kBeautyPassportTitle),
          hostRect: strip,
          label: 'the «BEAUTY PASSPORT» literal @${scale}x',
        );
      });
    }
  });
}
