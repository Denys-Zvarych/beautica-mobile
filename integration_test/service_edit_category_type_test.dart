// Phase 16.5 regression — E2E: Service-Edit category↔service-type guard.
//
// THE BUG THIS FLOW GUARDS (Step 2.7 Rule 3b — user-flow coverage)
// ----------------------------------------------------------------
// The shared ServiceForm let an edit ship a category↔service-type mismatch.
// Two user-visible behaviours are exercised end-to-end through the REAL HTTP
// path (the fake backend's Dio drives the real HttpServiceRepository):
//
//   POSITIVE (fix #1 + #2). Load a service in category A (NAILS) with a service
//     type that belongs to A. Change the category to B (BROWS). The stale type
//     selection must CLEAR, the type picker must RE-QUERY for category B and
//     repopulate with B's types (and never offer A's type). After re-picking a
//     B type the edit saves successfully — the PATCH carries the NEW type, not
//     the stale cross-category id.
//
//   NEGATIVE (fix #3). Load a service whose PATCH the backend rejects with the
//     fieldless 400 envelope
//       {success:false, message:"service type does not belong to the selected
//        category"}                                       (NO `errors` map)
//     Change the category and submit. The form must surface the LOCALIZED inline
//     error (`l10n.serviceTypeCategoryMismatch`) on the keyed `error-service-type`
//     row — NOT a raw English snackbar.
//
// HARNESS
// -------
// Reuses the shared AppHarness + FakeBackend (support/). FakeBackend was extended
// (additively) with: two approved categories (NAILS + BROWS), a
// `GET /service-types?categoryName=` endpoint keyed on the query slug, a
// type-bearing service (`assign-typed`, PATCH → 200) and a negative-path service
// (`assign-mismatch`, PATCH → fieldless 400). No new harness was invented.
//
// KEY POLICY: navigation taps use key-based finders only (see app_harness.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // Bounded pump — ServiceEditScreen contains a category picker whose loading
  // state shows an infinite CircularProgressIndicator (pumpAndSettle never
  // settles), plus a 1000ms entrance animation. 20 × 100ms = 2000ms covers both.
  Future<void> pumpBounded(WidgetTester tester, {int ticks = 20}) async {
    for (int i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Finder: the closed service-type field showing [text].
  Finder serviceTypeFieldText(String text) => find.descendant(
    of: find.byKey(const Key('select-service-type-field')),
    matching: find.text(text),
  );

  // Open the category sheet, pick [wire], let the sheet dismiss.
  Future<void> selectCategory(WidgetTester tester, String wire) async {
    final Finder field = find.byKey(const Key('select-category-field'));
    await tester.ensureVisible(field);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field);
    await pumpBounded(tester, ticks: 6); // sheet entrance
    final Finder chip = find.byKey(Key('chip-category-$wire'));
    expect(chip, findsOneWidget, reason: '$wire chip must appear in the sheet');
    await tester.tap(chip);
    await pumpBounded(tester, ticks: 6); // sheet exit
  }

  // Open the service-type sheet, pick [id], let the sheet dismiss. The type
  // list is fetched async (GET /service-types) after a category change, so the
  // menu may open on a loading state — pump generously until the option chip
  // appears (bounded), rather than asserting on the first frame.
  Future<void> selectServiceType(WidgetTester tester, String id) async {
    final Finder field = find.byKey(const Key('select-service-type-field'));
    await tester.ensureVisible(field);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field);
    final Finder chip = find.byKey(Key('chip-service-type-$id'));
    for (int i = 0; i < 25 && chip.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(chip, findsOneWidget, reason: 'service-type $id must appear');
    await tester.tap(chip);
    await pumpBounded(tester, ticks: 6);
  }

  // Resolve l10n from the ServiceForm element — AppLocalizations live BELOW the
  // MaterialApp, so reading at the MaterialApp context returns null.
  AppLocalizations l10nFor(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TextField).first));

  // ── POSITIVE — category switch clears the stale type, picker re-queries B ──

  testWidgets(
    'changing category clears the orphan type, the picker re-queries the new '
    'category, and a re-picked type saves',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Open the type-bearing service (NAILS + type belonging to NAILS).
      router.go(RouteNames.serviceEdit('assign-typed'));
      await pumpBounded(tester);
      expectLocation(router, '/services/assign-typed/edit');

      // The loaded NAILS type labels the closed field on load.
      expect(
        serviceTypeFieldText('Класичний манікюр'),
        findsOneWidget,
        reason: 'the loaded service type must pre-seed the closed field',
      );

      // Switch category NAILS → BROWS (incompatible with the loaded type).
      await selectCategory(tester, 'BROWS');

      // The stale type clears from the closed field…
      expect(
        serviceTypeFieldText('Класичний манікюр'),
        findsNothing,
        reason: 'an incompatible category change must clear the loaded type',
      );

      // …and the picker re-queried BROWS: open it and assert BROWS' type is now
      // offered while NAILS' type is gone. The list is fetched async, so pump
      // (bounded) until the BROWS chip resolves rather than on the first frame.
      final Finder typeField = find.byKey(
        const Key('select-service-type-field'),
      );
      await tester.ensureVisible(typeField);
      await tester.tap(typeField);
      final Finder browsChip = find.byKey(
        const Key('chip-service-type-type-brows-correction'),
      );
      for (int i = 0; i < 25 && browsChip.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        browsChip,
        findsOneWidget,
        reason: 'the picker must repopulate with the new category\'s types',
      );
      expect(
        find.byKey(const Key('chip-service-type-type-nails-classic')),
        findsNothing,
        reason: 'the stale category\'s type must no longer be offered',
      );
      // Pick the BROWS type from the open sheet.
      await tester.tap(browsChip);
      await pumpBounded(tester, ticks: 6);

      // Save — the edit must PATCH the NEW type, not the stale cross-category id.
      final Finder submit = find.byKey(const Key('btn-submit-service'));
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(submit);
      await pumpBounded(tester);

      // The picker genuinely re-queried for BROWS.
      expect(
        fb.lastServiceTypesCategory,
        'BROWS',
        reason: 'the type picker must re-query GET /service-types for BROWS',
      );
      // PATCH fired and carried the re-picked BROWS type id (never the stale
      // NAILS id) under the new category.
      expect(fb.patchServiceCalls, greaterThanOrEqualTo(1));
      expect(
        fb.lastTypedPatchBody?['serviceTypeId'],
        'type-brows-correction',
        reason:
            'the PATCH must carry the re-picked BROWS type, not the stale id',
      );
      // Successful save pops back to /services.
      expectLocation(router, RouteNames.services);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  // ── NEGATIVE — fieldless backend 400 → localized inline error, no snackbar ──

  testWidgets(
    'a fieldless mismatch-400 from the backend surfaces as a localized inline '
    'error, not a raw English snackbar',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // assign-mismatch loads valid (NAILS + NAILS type) but its PATCH always
      // returns the fieldless 400 mismatch envelope.
      router.go(RouteNames.serviceEdit('assign-mismatch'));
      await pumpBounded(tester);
      expectLocation(router, '/services/assign-mismatch/edit');

      final AppLocalizations l10n = l10nFor(tester);

      // Make the category dirty (NAILS → BROWS), then re-pick a BROWS type so a
      // type IS selected at submit. The form clears the orphan type locally, but
      // we deliberately re-pick so the submit carries a type and the backend is
      // the one that rejects — exactly the contract under test.
      await selectCategory(tester, 'BROWS');
      await selectServiceType(tester, 'type-brows-correction');

      // Submit → backend replies fieldless 400.
      final Finder submit = find.byKey(const Key('btn-submit-service'));
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(submit);
      await pumpBounded(tester);

      // The localized inline error renders on the keyed row…
      final Finder errorRow = find.byKey(const Key('error-service-type'));
      expect(
        errorRow,
        findsOneWidget,
        reason: 'a fieldless mismatch-400 must surface on the inline error row',
      );
      expect(
        find.descendant(
          of: errorRow,
          matching: find.text(l10n.serviceTypeCategoryMismatch),
        ),
        findsOneWidget,
        reason: 'the inline message must be the LOCALIZED key value',
      );
      // …and NEVER a raw English snackbar.
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'fieldless mismatch must not fall through to a snackbar',
      );
      expect(
        find.text('service type does not belong to the selected category'),
        findsNothing,
        reason: 'the raw English server message must never reach the UI',
      );
      // The PATCH was attempted (the backend rejected it), and we stayed on the
      // edit screen so the master can fix the selection.
      expect(fb.patchServiceCalls, greaterThanOrEqualTo(1));
      expectLocation(router, '/services/assign-mismatch/edit');
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
