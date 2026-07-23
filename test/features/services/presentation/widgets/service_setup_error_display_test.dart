// Regression guard — service-setup row error DISPLAY (Step 2.7 Rule 3).
//
// Two bugs were fixed in the compact bulk service-setup row's error display;
// this file reproduces both at the widget layer (the honest unit boundary — the
// card takes a [RowFlagReason] / server-error as its input and owns the render):
//
//   BUG 1 (duplicate error): a `durationTooLong` row (client `> 480` guard)
//   previously rendered `l10n.serviceSetupDurationMax` in BOTH the card header
//   flag line AND the inline duration field — the exact same copy, twice. The
//   fix gates the header with
//     `showHeaderFlag = clientFlagged && reason != RowFlagReason.durationTooLong`
//   so `durationTooLong` is FIELD-ONLY. Summary reasons (missingDuration /
//   missingPrice / missingBoth / invalidRange) keep their header line.
//     → Against the OLD double-render, `findsOneWidget` FAILS (findsNWidgets(2));
//       it passes now. (The pre-existing screen test used `findsWidgets` (>=1),
//       so it did NOT guard the duplicate — this closes that gap.)
//
//   BUG 2 (field shift): when the duration error appeared, the inline error grew
//   the duration well's OWN column inside a `CrossAxisAlignment.center` Row, so
//   the two wells' vertical alignment diverged (the duration well shifted vs its
//   price sibling). The fix hoists every compact per-field message BENEATH the
//   wells Row into an `AnimatedSize` slot (`_PricingInputField.hoistError` in
//   compact mode), so both wells stay equal-top and the well never moves.
//     → Asserted (chosen for this single-card harness) by:
//         (a) the duration well and price well tops stay EQUAL after the error
//             (pre-fix they diverge by ~½ the inline-error height), and
//         (b) the error text renders BENEATH both wells (in the hoisted slot).
//       A raw global before/after compare is deliberately NOT used: the single
//       card is vertically centre-able and the 1.4dp error-rim border shifts the
//       whole card uniformly, both of which confound a raw top-left delta — the
//       sibling-alignment + beneath-row invariants are the robust signal.
//
// Wells are located by stable keys only (service-setup-duration,
// pricing-fixed-amount) — no localised-string finders for interaction. l10n
// values are loaded once via the delegate and compared for content assertions.

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stable key on the duration well's [NeumorphicInset] (compact
/// `_PricingInputField` rendered by [PricingField]).
const Key _kDurationWell = Key('service-setup-duration');

/// The stable key on the fixed-price well's [NeumorphicInset].
const Key _kFixedWell = Key('pricing-fixed-amount');

/// Sub-pixel slack for position comparisons (layout/font rounding).
const double _kEps = 0.5;

/// Builds an INCLUDED row in [mode]; its controllers are disposed via the row's
/// own [dispose] (registered as a tearDown).
ServiceRowState _includedRow(
  WidgetTester tester, {
  ServicePriceType mode = ServicePriceType.fixed,
}) {
  final row = ServiceRowState(serviceTypeId: 'st-1', nameUk: 'Манікюр')
    ..included = true
    ..pricingMode = mode;
  addTearDown(row.dispose);
  return row;
}

/// Pumps a single [ServiceTypeRowCard] at [width] logical px, tall enough that
/// nothing clips, and settles the expand/switch animations.
Future<void> _pumpCard(
  WidgetTester tester,
  ServiceRowState row, {
  double width = 360,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        // Pinned to the TOP (not centred) so the card's own top stays fixed —
        // a vertically-centred single card would re-centre as it grows and
        // confound any position read.
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: ServiceTypeRowCard(
                row: row,
                resolveRangeError: (_) => null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('service-setup row — error display (duplicate + shift regressions)', () {
    // ── BUG 1 — the duplicate is gone: duration-max copy renders ONCE ──────────
    testWidgets(
      'durationTooLong renders serviceSetupDurationMax on the FIELD ONLY — no '
      'header duplicate (findsOneWidget; old double-render = findsNWidgets(2))',
      (tester) async {
        final row = _includedRow(tester);
        await _pumpCard(tester, row);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Realistic input: a > 480 duration + a valid price, then the
        // assemble/save path's result (durationTooLong) is applied to the row —
        // the card's sole input for this state.
        await tester.enterText(find.byKey(_kDurationWell), '600');
        await tester.enterText(find.byKey(_kFixedWell), '500');
        row.flagReason = RowFlagReason.durationTooLong;
        await tester.pumpAndSettle();

        // THE regression: exactly one occurrence (the duration field). The header
        // duplicate is suppressed by the showHeaderFlag gate.
        expect(
          find.text(l10n.serviceSetupDurationMax),
          findsOneWidget,
          reason:
              'durationTooLong copy must render exactly once (the field). The '
              'pre-fix header duplicate → findsNWidgets(2), which this fails.',
        );

        // Guard the gate itself: no header SUMMARY line leaks in for
        // durationTooLong (its _flagMessage fallback would be
        // serviceSetupRowMissingPrice — that must NOT appear, catching a gate
        // removal even though the fallback copy differs from the field copy).
        expect(
          find.text(l10n.serviceSetupRowMissingPrice),
          findsNothing,
          reason:
              'durationTooLong is field-only — no header summary line of any '
              'wording may render',
        );
      },
    );

    // ── BUG 2 — the duration well does NOT shift when the error appears ─────────
    testWidgets(
      'duration well keeps sibling alignment (does NOT shift) when the '
      'durationTooLong error appears — error hoisted beneath the wells Row',
      (tester) async {
        final row = _includedRow(tester);
        await _pumpCard(tester, row);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.enterText(find.byKey(_kDurationWell), '600');
        await tester.pumpAndSettle();

        // Baseline sibling offset (a small constant is fine — the "хв" suffix
        // always shows on the duration well while the currency suffix hides):
        // the invariant we guard is that this offset does NOT CHANGE when the
        // error appears.
        final double beforeDelta =
            tester.getTopLeft(find.byKey(_kDurationWell)).dy -
            tester.getTopLeft(find.byKey(_kFixedWell)).dy;

        // Raise the flag and settle the AnimatedSize grow-in.
        row.flagReason = RowFlagReason.durationTooLong;
        await tester.pumpAndSettle();

        // PRIMARY (a) — the duration/price sibling offset is UNCHANGED. This is
        // the true no-shift signal: pre-fix the inline error grew ONLY the
        // duration column inside the CrossAxisAlignment.center Row, so the two
        // wells' tops diverged by ~½ the error height (~11 dp) — beforeDelta and
        // afterDelta would differ by that much. Post-fix the error is hoisted
        // out, so both wells keep their exact relative alignment.
        final double afterDelta =
            tester.getTopLeft(find.byKey(_kDurationWell)).dy -
            tester.getTopLeft(find.byKey(_kFixedWell)).dy;
        expect(
          (afterDelta - beforeDelta).abs(),
          lessThan(_kEps),
          reason:
              'the duration well must not shift relative to its price sibling '
              'when the error appears (pre-fix it moved ~11 dp inside the '
              'centred wells Row)',
        );

        // PRIMARY (b) — the error text sits BENEATH BOTH wells (the hoisted
        // beneath-row slot), never inside the duration column. Pre-fix the
        // message lived inside the duration column, so it would sit ABOVE the
        // price well's bottom — this fails for that layout.
        final double wellsRowBottom = <double>[
          tester.getBottomLeft(find.byKey(_kDurationWell)).dy,
          tester.getBottomLeft(find.byKey(_kFixedWell)).dy,
        ].reduce((a, b) => a > b ? a : b);
        final double errorTop = tester
            .getTopLeft(find.text(l10n.serviceSetupDurationMax))
            .dy;
        expect(
          errorTop,
          greaterThanOrEqualTo(wellsRowBottom - _kEps),
          reason:
              'the duration-max message must render below the entire wells Row '
              '(the hoisted AnimatedSize slot), not inside the duration well',
        );
      },
    );

    // ── Guard the gate does NOT over-suppress: summary reasons keep a header ────
    testWidgets(
      'missingDuration still renders the header summary line AND the inline '
      'field hint (showHeaderFlag suppresses ONLY durationTooLong)',
      (tester) async {
        final row = _includedRow(tester);
        await _pumpCard(tester, row);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        row.flagReason = RowFlagReason.missingDuration;
        await tester.pumpAndSettle();

        // Header summary copy — distinct string, must survive the gate.
        expect(
          find.text(l10n.serviceSetupRowMissingDuration),
          findsOneWidget,
          reason:
              'summary reasons keep their header line — the showHeaderFlag gate '
              'must not over-suppress beyond durationTooLong',
        );
        // Inline field hint — a DIFFERENT string ("...у хвилинах"), rendered on
        // the duration field beneath the wells Row.
        expect(
          find.text(l10n.serviceSetupDurationRequired),
          findsOneWidget,
          reason:
              'the empty-duration field hint must still render on the field',
        );
      },
    );

    // ── Guard: a server duration error is FIELD-ONLY (no header) — pin it ──────
    testWidgets(
      'serverDurationError renders on the FIELD only, never duplicated in a '
      'header (guards against a future header duplicate for server errors)',
      (tester) async {
        final row = _includedRow(tester);
        await _pumpCard(tester, row);

        const String serverMsg = 'Занадто велика тривалість (сервер)';
        row.serverDurationError = serverMsg;
        await tester.pumpAndSettle();

        expect(
          find.text(serverMsg),
          findsOneWidget,
          reason:
              'a mapped-back server duration error rides the inline field slot '
              'only — a header line would misreport it, so it must appear once',
        );

        // It sits beneath the wells Row (the field slot), not in the header.
        final double wellBottom = tester
            .getBottomLeft(find.byKey(_kDurationWell))
            .dy;
        final double errorTop = tester.getTopLeft(find.text(serverMsg)).dy;
        expect(
          errorTop,
          greaterThanOrEqualTo(wellBottom - _kEps),
          reason:
              'the server duration message must render below the wells Row, not '
              'above them in a header',
        );
      },
    );
  });
}
