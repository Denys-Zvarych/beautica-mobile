// Phase 291 — Widget tests for DeleteSalonDialog.
//
// The dialog's body used to claim `DELETE /salons/{salonId}` was a
// reversible soft-deactivate ("Салон буде деактивовано. Клієнти більше не
// зможуть його знайти.") — false: the shipped backend hard-deletes staff
// accounts (Phase 267), cancels future bookings and notifies clients (Phase
// 269), and permanently purges the salon's photos from R2 (Phase 268 D2).
// This file pins the corrected copy and the additive `isLastSalon` param
// (D2) that swaps in a closing "you'll need to create a new one" sentence
// for an owner deleting their only salon — WITHOUT ever claiming they are
// signed out (D6: there is no sign-out; see `delete_salon_flow.dart`).
//
// Coverage (phase doc test cases 1, 2, 3, 4, 5, 8, 9, 11):
//   1. mentions permanent photo loss (via l10n lookup, not a hard literal).
//   2. never says «деактив» in any form — the regression pin for the actual
//      defect; must outlive any future rewording of case 1.
//   3. isLastSalon: true renders deleteSalonBodyLastSalon.
//   4. isLastSalon: false renders deleteSalonBody (not the last-salon body).
//   5. DeleteSalonDialog() with no arguments still compiles and defaults to
//      the non-last body (additive-parameter pin).
//   8. the last-salon body never mentions being signed out/logged out.
//   9. confirm pops true / cancel pops false — existing behaviour, unchanged.
//  11. the AlertDialog renders unscrolled at 360x640 with the longer
//      last-salon body — no Scrollable descendant, no layout overflow (the
//      suite-wide overflow guard from `flutter_test_config.dart` fails the
//      test automatically if the content overflows at this size).
//
// Finders use Key-based lookups / l10n string lookups per the M3 convention
// — never raw Cyrillic literals.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/delete_salon_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a widget that opens [DeleteSalonDialog] via [showDialog] on button
/// tap, then waits for it to appear.
///
/// Returns the [Future<bool?>] that [showDialog] resolves to.
///
/// Applies the REAL app theme ([velvetTheme]), not Material's default —
/// mobile-qa correction, 2026-09-05. The default Material3 theme resolves
/// `bodyMedium` to Roboto at metrics that measurably differ from the app's
/// actual `GoogleFonts.nunitoTextTheme()`: under the default theme the real
/// (unmutated) `deleteSalonBodyLastSalon` string is silently clipped by the
/// `AlertDialog` at 360x640 (measured 344dp painted vs 400dp natural — a
/// `Text` with no `maxLines`/`overflow` clips silently, no exception, no
/// `RenderFlex` stripe); under the real theme it is not (240dp both ways).
/// D1's shape claim is about what the OWNER sees, so the shape test
/// (`should_renderLastSalonBodyUnclipped_when_pumpedAt360x640`) must render
/// under the real theme or it is asserting against a font nobody sees.
Future<Future<bool?>> _pumpDialogTrigger(
  WidgetTester tester, {
  bool isLastSalon = false,
  Locale locale = const Locale('uk'),
}) async {
  late final Future<bool?> dialogFuture;

  await tester.pumpWidget(
    MaterialApp(
      theme: velvetTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (BuildContext ctx) {
          return Scaffold(
            body: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () {
                dialogFuture = showDialog<bool>(
                  context: ctx,
                  builder: (_) => DeleteSalonDialog(isLastSalon: isLastSalon),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();

  return dialogFuture;
}

/// Pumps [DeleteSalonDialog] with NO arguments — the additive-parameter pin
/// (case 5): the widget must still compile and render with zero args.
Future<void> _pumpDialogWithNoArgs(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: velvetTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: const Center(child: DeleteSalonDialog()),
    ),
  );
  await tester.pump();
}

AppLocalizations _l10n() => lookupAppLocalizations(const Locale('uk'));

void main() {
  testWidgets('should_mentionPermanentPhotoLoss_when_dialogShown', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester);

    final l10n = _l10n();
    expect(find.text(l10n.deleteSalonBody), findsOneWidget);
    // mobile-qa CRITICAL fix (2026-09-05) — the assertion above compares the
    // rendered text against `l10n.deleteSalonBody`, the SAME getter under
    // test: it can never fail, no matter what the ARB says (verified by
    // mutation — reverting `deleteSalonBody` to the old «деактивовано»
    // string left this assertion GREEN). The hard-coded substring below is
    // the actual pin: copy IS the deliverable for this phase, so a literal
    // here is the correct call, not the `find.byKey`-over-`find.text`
    // convention (M2) that applies to LOCATING a widget, not to asserting
    // the CONTENT of a copy-change phase's own acceptance criterion.
    expect(
      l10n.deleteSalonBody.toLowerCase(),
      contains('втрачено назавжди'),
      reason:
          'the body must state the photos are PERMANENTLY lost — this is '
          'the D1 acceptance criterion, not just "the dialog shows some '
          'body text"',
    );
  });

  testWidgets('should_notPromiseReversibility_when_dialogShown', (
    tester,
  ) async {
    // Regression pin for the actual defect — the substring «деактив» must
    // be absent from the rendered body, regardless of how case 1's exact
    // wording is later refined.
    await _pumpDialogTrigger(tester);

    final l10n = _l10n();
    expect(l10n.deleteSalonBody.toLowerCase(), isNot(contains('деактив')));
    expect(find.textContaining('деактив'), findsNothing);
  });

  testWidgets('should_showNoSalonsLeftSentence_when_isLastSalonIsTrue', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester, isLastSalon: true);

    final l10n = _l10n();
    expect(find.text(l10n.deleteSalonBodyLastSalon), findsOneWidget);
    expect(find.text(l10n.deleteSalonBody), findsNothing);
  });

  testWidgets('should_notShowNoSalonsLeftSentence_when_isLastSalonIsFalse', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester, isLastSalon: false);

    final l10n = _l10n();
    expect(find.text(l10n.deleteSalonBody), findsOneWidget);
    expect(find.text(l10n.deleteSalonBodyLastSalon), findsNothing);
  });

  testWidgets('should_defaultToFalse_when_isLastSalonOmitted', (tester) async {
    await _pumpDialogWithNoArgs(tester);

    final l10n = _l10n();
    expect(find.text(l10n.deleteSalonBody), findsOneWidget);
    expect(find.text(l10n.deleteSalonBodyLastSalon), findsNothing);
  });

  testWidgets('should_neverMentionSignOut_when_isLastSalonIsTrue', (
    tester,
  ) async {
    // D6 — there is no sign-out: the flow lands every delete path on «Мої
    // салони» and the backend never revokes the owner's refresh token. Pins
    // the corrected fact so a future editor cannot reintroduce the
    // phase-290 draft's wording.
    final l10n = _l10n();
    final String body = l10n.deleteSalonBodyLastSalon.toLowerCase();
    expect(body, isNot(contains('вихід')));
    expect(body, isNot(contains('вийдете')));
    expect(body, isNot(contains('вийти з акаунт')));
    expect(body, isNot(contains('виведено з акаунт')));
    expect(body, isNot(contains('sign out')));
    expect(body, isNot(contains('signed out')));
    expect(body, isNot(contains('log out')));
    expect(body, isNot(contains('logged out')));
  });

  // mobile-qa gap fix (2026-09-05) — every case above pumps ONLY the
  // Ukrainian locale. `app_en.arb` carries its own independent value for
  // both keys (D4: both files rewritten in the same commit, but nothing
  // enforces the TWO VALUES stay in sync beyond a human copying them
  // correctly) and nothing previously rendered the dialog under
  // `Locale('en')` at all — an English regression (e.g. someone reverting
  // just the EN string to "deactivated" while leaving UK correct) would
  // have shipped with every existing test green. These three mirror cases
  // 1, 2 and 8 for English.
  testWidgets('should_mentionPermanentPhotoLoss_when_dialogShown_en', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester, locale: const Locale('en'));

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.deleteSalonBody), findsOneWidget);
    expect(
      l10n.deleteSalonBody.toLowerCase(),
      contains('lost permanently'),
      reason:
          'the English body must also state the photos are '
          'PERMANENTLY lost, independently of the Ukrainian string',
    );
  });

  testWidgets('should_notPromiseReversibility_when_dialogShown_en', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester, locale: const Locale('en'));

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      l10n.deleteSalonBody.toLowerCase(),
      isNot(contains('deactivat')),
      reason:
          'the English body must not reintroduce "deactivated" — the '
          'same defect class D1 fixed in Ukrainian',
    );
    expect(find.textContaining('deactivat'), findsNothing);
  });

  testWidgets('should_neverMentionSignOut_when_isLastSalonIsTrue_en', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final String body = l10n.deleteSalonBodyLastSalon.toLowerCase();
    expect(body, isNot(contains('sign out')));
    expect(body, isNot(contains('signed out')));
    expect(body, isNot(contains('log out')));
    expect(body, isNot(contains('logged out')));
  });

  testWidgets('should_returnTrue_when_confirmTapped', (tester) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isTrue);
  });

  testWidgets('should_returnFalse_when_cancelTapped', (tester) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-cancel-delete-salon')));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isFalse);
  });

  testWidgets('should_notScroll_when_lastSalonBodyRendered', (tester) async {
    // D1's shape constraint made executable: at the smallest supported
    // phone size, the LONGER last-salon body must still fit inside the
    // plain AlertDialog with no SingleChildScrollView. This only pins that
    // no scroll wrapper was ADDED — it does NOT prove the body renders
    // unclipped (see `should_renderLastSalonBodyUnclipped_when_pumpedAt360x640`
    // below for that; a bare `Text` with no `maxLines`/`overflow` set is
    // silently clipped by a height-constrained ancestor with NO exception
    // and NO RenderFlex overflow stripe — mobile-qa verified this by
    // mutation on 2026-09-05, so the suite-wide overflow guard does
    // **not** catch this failure mode; the comment that used to claim it
    // did was wrong and is corrected here).
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDialogTrigger(tester, isLastSalon: true);

    expect(find.byType(AlertDialog), findsOneWidget);
    final scrollables = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    expect(
      scrollables,
      findsNothing,
      reason:
          'the AlertDialog must render the longer last-salon body '
          'unscrolled — no SingleChildScrollView was added (D1)',
    );
  });

  testWidgets('should_renderLastSalonBodyUnclipped_when_pumpedAt360x640', (
    tester,
  ) async {
    // Ground-truth check for D1's shape claim, independent of the
    // "no Scrollable was added" structural check above. A `Text` with no
    // `maxLines`/`overflow` does not throw or paint an overflow stripe
    // when a height-constrained ancestor gives it less room than it
    // needs — it silently paints only what fits (mobile-qa verified by
    // mutation: inflating `deleteSalonBodyLastSalon` to ~60 extra lines
    // produced ZERO console output, ZERO thrown exception, and the test
    // above STILL PASSED, while the rendered `RenderParagraph` was
    // visibly shorter than its unconstrained natural height).
    //
    // This test renders the SAME `RenderParagraph` (same font, same
    // resolved TextStyle, same real render pipeline) twice — once at the
    // smallest supported phone height, once at an effectively unbounded
    // height — and asserts the two agree. Using the real render twice
    // (rather than an independent `TextPainter` re-layout) avoids any
    // font-metric drift between a hand-rolled comparison and what the
    // widget actually paints.
    // Each call pumps a fresh `MaterialApp`; `tester.pumpWidget` reuses the
    // PREVIOUS `MaterialApp`'s `State` (same widget type), so its
    // `Navigator` — and any still-open dialog route on it — survives into
    // the next pump unless dismissed first. Cancel closes the dialog
    // opened by the prior call before the next one opens its own.
    Future<double> renderedContentHeight(Size viewport) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      await _pumpDialogTrigger(tester, isLastSalon: true);
      final l10n = _l10n();
      final Finder textFinder = find.text(l10n.deleteSalonBodyLastSalon);
      final RenderParagraph rp = tester.renderObject<RenderParagraph>(
        find.descendant(of: textFinder, matching: find.byType(RichText)).first,
      );
      final double height = rp.size.height;
      await tester.tap(find.byKey(const Key('btn-cancel-delete-salon')));
      await tester.pumpAndSettle();
      return height;
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final double constrainedHeight = await renderedContentHeight(
      const Size(360, 640),
    );
    final double naturalHeight = await renderedContentHeight(
      const Size(360, 4000),
    );

    expect(
      constrainedHeight,
      moreOrLessEquals(naturalHeight, epsilon: 1.0),
      reason:
          'the last-salon body must paint at its full natural height at '
          '360x640 — a shorter constrained height means the AlertDialog '
          'silently clipped part of the body (no exception, no overflow '
          'stripe is ever raised for this failure mode)',
    );
  });
}
