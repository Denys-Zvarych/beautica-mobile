// [ServiceSetupScreen] widget tests:
// narrow layout, opt-in flagging, stale flags, deselect, close/exitRoute,
// per-field 400.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'dart:async';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import 'service_setup_test_harness.dart';

void main() {
  late Harness h;

  setUp(() {
    h = Harness();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
    registerFallbackValue(const MasterServiceUpdate());
  });

  // ── Bug 1 regression — narrow-width layout (no RenderFlex overflow) ────────
  //
  // The compact duration+price line used to overflow horizontally on narrow
  // phones — worst in RANGE mode (two numeric fields + two "₴" suffixes
  // beside the duration). pricing_field.dart now stacks duration above price
  // below 360dp, and range min/max stack below 220dp. These tests pump the
  // screen at 320 / 360 / 412 dp, include + expand a row in each pricing mode,
  // and assert NO exception was thrown (a RenderFlex overflow surfaces via
  // tester.takeException()). They FAIL against the pre-fix single-Row layout.

  group('narrow-width layout — no overflow (Bug 1)', () {
    for (final width in <double>[320, 360, 412]) {
      for (final range in <bool>[false, true]) {
        final mode = range ? 'range' : 'fixed';
        testWidgets(
          'included row at ${width.toInt()}dp in $mode mode does not overflow',
          (tester) async {
            await pump(
              tester,
              h,
              surfaceSize: Size(width, 900),
              overrides: h.overrides(
                categories: const AsyncData(<ServiceCategoryOption>[manicure]),
                typesBySlug: <String, List<ServiceTypeOption>>{
                  'MANICURE': <ServiceTypeOption>[typeClassic],
                },
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey<String>('cat_MANICURE')),
            );
            await tester.pumpAndSettle();

            // Reveal the duration + price line by including the row.
            await toggleRowOn(tester, 'type-classic');

            if (range) {
              await tester.tap(find.byKey(const Key('pricing-toggle-range')));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('pricing-range-min')),
                findsOneWidget,
              );
              expect(
                find.byKey(const Key('pricing-range-max')),
                findsOneWidget,
              );
            } else {
              expect(
                find.byKey(const Key('pricing-fixed-amount')),
                findsOneWidget,
              );
            }

            // A RenderFlex overflow is reported as a thrown FlutterError that
            // tester.takeException() surfaces; null means the responsive
            // stacking kept every inner field above its min width.
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  // ── Bug 2 regression — opt-in flagging / premature validation ──────────────
  //
  // Rows used to default included, so expanding a category immediately made
  // every untouched row "required" — tapping save fired
  // "Вкажіть тривалість і ціну" on rows the master never opted into. The opt-in
  // model (rows default OFF) + per-row RowFlagReason fixes both the premature
  // flag AND the disambiguated messages.

  group('opt-in flagging (Bug 2)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'expanding then tapping save with NO row included shows no flag and '
      'never calls bulkCreate (the user-reported premature-flag bug)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // The CTA is disabled (no-op) — tapping it must not flag the untouched
        // row nor reach the repository.
        expect(saveOnPressed(tester), isNull);
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // No flag message of any kind on the untouched row.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingDuration), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingPriceOnly), findsNothing);
        expect(find.text(l10n.serviceSetupRowFixRange), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'included row with empty duration flags missingDuration (not the generic '
      'both) on save',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await expandManicure(tester);
        await toggleRowOn(tester, 'type-classic');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Duration empty, fixed price present → missingDuration only.
        await tester.enterText(
          find.byKey(const Key('pricing-fixed-amount')),
          '500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.serviceSetupRowMissingDuration), findsOneWidget);
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'included fixed row with duration but empty price flags missingPriceOnly',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await expandManicure(tester);
        await toggleRowOn(tester, 'type-classic');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // missingPriceOnly surfaces "Вкажіть ціну" twice: once as the header
        // flag (serviceSetupRowMissingPriceOnly) and once as the inline
        // fixed-price field hint (serviceSetupPriceRequired) — both ARB values
        // are the same string. Two matches proves the price-only path (the
        // missingBoth header would instead read "Вкажіть тривалість і ціну").
        expect(
          find.text(l10n.serviceSetupRowMissingPriceOnly),
          findsNWidgets(2),
        );
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingDuration), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets('included row with both empty falls back to missingBoth '
        '(serviceSetupRowMissingPrice)', (tester) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
        ),
      );
      await expandManicure(tester);
      await toggleRowOn(tester, 'type-classic');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
      verifyNever(() => h.repo.bulkCreate(any()));
    });
  });

  // ── MEDIUM regression — scroll-to-first-flagged on blocked save ────────────
  //
  // Spec required, but was missing in code: when a blocked save leaves an
  // included-and-flagged row BELOW the fold, the screen must scroll the topmost
  // such row back into view (post-frame Scrollable.ensureVisible) so the master
  // never stares at a silently no-op CTA. _scrollToFirstFlagged() now does this
  // off _save()'s blocked branch. This test stands a flagged included row below
  // the fold (small surface + scroll back to top), taps save, and asserts the
  // row is scrolled into view — and bulkCreate is never reached.

  group('scroll-to-first-flagged on blocked save (MEDIUM regression)', () {
    testWidgets(
      'a flagged included row below the fold is scrolled into view after a '
      'blocked save; bulkCreate is never called',
      (tester) async {
        // A short surface so the two manicure rows cannot both fit — the second
        // (type-gel) row sits below the fold once we scroll back to the top.
        //
        // This height is a CALIBRATED FIXTURE, not an arbitrary number: it has
        // to be re-trimmed whenever the header above the rows changes height.
        // Trimmed 440 → 360 on 2026-08-04 when the static three-line helper
        // note became the one-line tappable «Запропонувати категорію» strip —
        // the shorter header pulled both rows above the fold and the
        // `isFalse` PRECONDITION below started failing, which is the fixture
        // going stale, not the behaviour regressing. The precondition assert
        // is what makes that drift loud instead of silently turning this into
        // a test that proves nothing.
        await pump(
          tester,
          h,
          surfaceSize: const Size(360, 360),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final scrollable = find.byType(Scrollable).first;
        final lowerRow = find.byKey(const Key('setup_row_type-gel'));

        // Include the LOWER row (scroll it into view to tap its switch) but
        // leave it invalid (no duration / no price) so the save is blocked.
        await tester.scrollUntilVisible(lowerRow, 200, scrollable: scrollable);
        await toggleRowOn(tester, 'type-gel');

        // Scroll back to the very top so the flagged lower row is below the
        // fold at the moment we trigger the blocked save.
        await tester.drag(scrollable, const Offset(0, 1200));
        await tester.pumpAndSettle();

        // Precondition: the flagged row starts off-screen (below the fold).
        expect(
          isInViewport(tester, lowerRow),
          isFalse,
          reason: 'lower flagged row should start below the fold',
        );

        // Tapping save assembles → null (flagged) → _scrollToFirstFlagged().
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The post-frame ensureVisible ran without throwing AND brought the
        // flagged row into the viewport.
        expect(tester.takeException(), isNull);
        expect(
          isInViewport(tester, lowerRow),
          isTrue,
          reason: 'flagged row must be scrolled into view after blocked save',
        );

        // Its flag hint is now rendered and the save was genuinely blocked.
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'blocked save with the flagged row already on-screen is a no-throw no-op '
      '(ensureVisible path is mounted-safe)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        await toggleRowOn(tester, 'type-classic');

        // Leave the included row invalid (empty) → blocked save scrolls to a
        // row that is already visible; must not throw.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          isInViewport(tester, find.byKey(const Key('setup_row_type-classic'))),
          isTrue,
        );
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );
  });

  // ── HIGH regression — stale flag survives toggle-off / collapse-reexpand ────
  //
  // The user-reported stale-flag bug: an included row flagged on a blocked save
  // (flagReason set → "Вкажіть тривалість і ціну", missingBoth) kept painting
  // its error AFTER the master either (a) toggled the row OFF or (b) collapsed
  // and re-expanded its category. Two independent fixes guard this:
  //   • service_setup_widgets.dart — header flag gated on inclusion
  //     (`final bool flagged = on && row.flagged;`) so an excluded row never
  //     paints the flag/rim and the "excluded" sub-label takes over instead;
  //   • service_setup_screen.dart — `_toggleCategory`'s collapse branch calls
  //     `row.clearFlag()` on every retained row so a re-expanded row never
  //     resurrects a flag predating the collapse.
  // These tests stand a row up, blank both fields, fire a blocked save to set
  // the flag, then exercise each clear path. They FAIL against the pre-fix code
  // (the flag message lingers); they PASS now.

  group('stale flag clears on toggle-off / collapse-reexpand (HIGH regression)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    /// Includes the single manicure row, leaves duration+price blank, and fires
    /// a blocked save so the row carries the missingBoth flag
    /// (`serviceSetupRowMissingPrice`). Returns the loaded l10n bundle.
    Future<AppLocalizations> includeAndBlock(WidgetTester tester) async {
      await expandManicure(tester);
      await toggleRowOn(tester, 'type-classic');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      // Precondition: the blocked save flagged the included row.
      expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
      verifyNever(() => h.repo.bulkCreate(any()));
      return l10n;
    }

    testWidgets(
      'toggling a flagged row OFF removes its flag message and renders no '
      'sub-label at all (no error rim on the merely-off card)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // The flagged card paints a tinted error rim while included+flagged.
        expect(rowHasErrorRim(tester, 'type-classic'), isTrue);

        // Toggle the row OFF — `flagged = on && row.flagged` collapses to false
        // AND `_setIncluded` clears the flag.
        await tapIncludeSwitch(tester, 'type-classic');

        // The flag message is GONE; a merely-off row (neither locked nor
        // ownedNow) renders no sub-label at all.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
        // The merely-off card carries no error rim.
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );

    testWidgets(
      'collapsing then re-expanding a category clears the stale flag AND leaves '
      'the row DESELECTED (collapse == deselect — clearFlag + included=false)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // Collapse the category (tap the chip again). `_expanded` IS the
        // selection set, so collapsing DESELECTS: `_toggleCategory` runs both
        // `row.included = false` AND `row.clearFlag()` on the retained row.
        // Phase 471: the included row carries a «+ додати ще» line, so the
        // blocked save's scroll-to-flagged can now move the chip under the
        // top bar — bring it back before tapping.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('cat_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        // While collapsed there is no flagged card on screen.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);

        // Re-expand — the row state is reused (no refetch). With the fix the
        // flag was cleared on collapse, so the re-expanded card is clean.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
        // (a) The stale-flag guarantee STILL holds — no flag lingers after the
        // collapse/re-expand round-trip (pre-fix this would resurrect).
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
        // (b) NEW contract: collapse deselected the row, so the re-expanded card
        // is now merely off — it renders no sub-label at all, not an
        // unflagged-but-included row.
        expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
      },
    );

    testWidgets(
      'an excluded row never paints a flag even after it had been flagged '
      'while included',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // Toggle OFF (was flagged) → merely off, unflagged, no sub-label.
        await tapIncludeSwitch(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);

        // Toggle back ON — re-including starts clean (clearFlag on include); no
        // stale flag carries over from the earlier blocked save, and no
        // leftover off-state sub-label lingers either (that branch is gated
        // on `!on`, so it never fires once the row is included).
        await tapIncludeSwitch(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
        expect(find.text(l10n.serviceSetupRowAlreadyInMenu), findsNothing);
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );
  });

  // ── HIGH regression — deselecting (collapsing) a category drops its rows ────
  //   from BOTH the footer count AND the bulk-save payload.
  //
  // The user-reported bug: `_expanded` IS the category-selection set, so
  // collapsing a category == deselecting it. Before the fix, collapse was a
  // "pure visibility change" — the retained rows kept `included == true`, so a
  // deselected category still inflated the footer "Створити N послуг" count and
  // (critically) still contributed its serviceTypeIds to the bulk-save payload.
  //
  // The fix resets each retained row's `included = false` (alongside the existing
  // `clearFlag()`) in `_toggleCategory`'s collapse branch. These tests stand up
  // TWO categories, include rows in each, deselect one, then assert:
  //   • the footer count drops to ONLY the remaining category's rows; and
  //   • the assembled payload (captured at `bulkCreate`) carries ONLY the
  //     remaining category's serviceTypeId — proving `_assemble()` excludes the
  //     deselected rows, not just the footer label.
  // Both assertions FAIL against the pre-fix "stays-included" behaviour.

  group('deselect (collapse) drops a category from count + payload (HIGH '
      'regression)', () {
    List<Object> twoCategoryOverrides() => h.overrides(
      categories: const AsyncData(<ServiceCategoryOption>[manicure, hair]),
      typesBySlug: <String, List<ServiceTypeOption>>{
        'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
        'HAIR': <ServiceTypeOption>[typeCut],
      },
    );

    testWidgets(
      'including 2 rows in A + 1 in B reads "3"; deselecting A drops the footer '
      'to "1" (NOT 3)',
      (tester) async {
        // A tall surface so both chips + all three expanded rows fit on screen
        // at once — every chip/row stays laid out, so no scroll juggling is
        // needed and the footer-count assertions are deterministic.
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: twoCategoryOverrides(),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Expand A (MANICURE) and toggle BOTH its rows ON → footer reads "2".
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        await toggleRowOn(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        await toggleRowOn(tester, 'type-gel');
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);

        // Expand B (HAIR) and toggle its single row ON → footer rises to "3".
        await tester.tap(find.byKey(const ValueKey<String>('cat_HAIR')));
        await tester.pumpAndSettle();
        await toggleRowOn(tester, 'type-cut');
        expect(find.text(l10n.serviceSetupCtaCreate(3)), findsOneWidget);

        // Deselect A by tapping its chip again. The reported symptom: pre-fix the
        // footer stayed at "3"; post-fix it drops to "1" (only B's row counts).
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(3)), findsNothing);
      },
    );

    testWidgets(
      'the bulk-save payload after deselecting A carries ONLY category B\'s '
      'serviceTypeId — none of the deselected A rows',
      (tester) async {
        // Capture the assembled payload handed to bulkCreate.
        final captured = <List<MasterServiceBulkItem>>[];
        when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
          captured.add(
            invocation.positionalArguments.first as List<MasterServiceBulkItem>,
          );
          return createdService;
        });

        // A tall surface keeps every chip + row laid out at once.
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: twoCategoryOverrides(),
        );
        await tester.pumpAndSettle();

        // Expand A + include both rows.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        await toggleRowOn(tester, 'type-classic');
        await toggleRowOn(tester, 'type-gel');

        // Expand B + include its row, then give it a VALID duration + price so
        // the (post-deselect) save assembles cleanly.
        await tester.tap(find.byKey(const ValueKey<String>('cat_HAIR')));
        await tester.pumpAndSettle();
        await toggleRowOn(tester, 'type-cut');
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-cut')),
                matching: find.byType(TextField),
              )
              .first,
          '45',
        );
        // All three included rows expand a fixed-price field with the same key,
        // so scope the entry to type-cut's card.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('setup_row_type-cut')),
            matching: find.byKey(const Key('pricing-fixed-amount')),
          ),
          '350',
        );
        await tester.pumpAndSettle();

        // Deselect A — its (incomplete) rows must NOT block the save NOR appear
        // in the payload.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        // Save.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // bulkCreate was called once with EXACTLY B's single serviceTypeId.
        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(captured, hasLength(1));
        final ids = captured.single.map((i) => i.serviceTypeId).toList();
        expect(ids, <String>['type-cut']);
        expect(ids, isNot(contains('type-classic')));
        expect(ids, isNot(contains('type-gel')));
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Close button — pop-with-fallback regression guard ──────────────────────
  //
  // Three close/return sites in ServiceSetupScreen were changed from
  // `context.go(RouteNames.services)` to
  // `canPop ? context.pop() : context.go(RouteNames.services)`.
  //
  // The change ensures deep-link safety: when the screen is reached directly
  // (no back stack), it falls back to go(); when it is pushed (has a back
  // stack), it pops instead of replacing the stack with a go().
  //
  // Test 1 — pushed path (canPop true): pump the setup screen on top of a
  //   previous route. Tap the close button. Assert the navigator returns to the
  //   previous route (pop happened) rather than replacing the stack with
  //   /services (go would have happened).
  //
  // Test 2 — direct-entry path (canPop false): pump the setup screen as the
  //   initial (only) route. Tap close. Assert the router lands on
  //   RouteNames.services (the go() fallback fired).

  group('close button pop-with-fallback (swipe-back regression guard)', () {
    // ── 1. Pushed path — close pops back to previous route ───────────────────

    testWidgets(
      'close button pops back to the previous route when a back stack exists',
      (tester) async {
        // A 3-route router: /prev → /services/setup → /services.
        // Starting at /prev and pushing /services/setup gives us a poppable stack.
        const prevPath = '/prev';
        final router = GoRouter(
          initialLocation: prevPath,
          routes: <RouteBase>[
            GoRoute(
              path: prevPath,
              builder: (_, _) => const Scaffold(body: Text('PREVIOUS_SCREEN')),
            ),
            GoRoute(
              path: RouteNames.serviceSetup,
              builder: (_, _) => const ServiceSetupScreen(),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (_, _) =>
                  const Scaffold(body: Text('SERVICES_LIST_STUB')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            retry: beauticaProviderRetry,
            overrides: h
                .overrides(
                  categories: const AsyncData(<ServiceCategoryOption>[]),
                )
                .cast(),
            child: MediaQuery(
              data: const MediaQueryData(size: Size(800, 1200)),
              child: MaterialApp.router(
                routerConfig: router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('uk'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate from /prev to /services/setup via push.
        unawaited(router.push(RouteNames.serviceSetup));
        await tester.pumpAndSettle();

        // Verify setup screen rendered (categories empty — just the chip area).
        expect(
          router.canPop(),
          isTrue,
          reason: 'canPop must be true — /prev is still on the back stack',
        );

        // Tap the close button.
        final closeBtn = find.byKey(const Key('btn-setup-close'));
        expect(
          closeBtn,
          findsOneWidget,
          reason: 'close button (Key btn-setup-close) must be present',
        );
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Must have returned to /prev, NOT replaced the stack with /services.
        // The PREVIOUS_SCREEN text is present; SERVICES_LIST_STUB is absent.
        expect(
          find.text('PREVIOUS_SCREEN'),
          findsOneWidget,
          reason:
              'close button must pop (return to /prev) when canPop is true. '
              'If this fails, the code reverted to context.go(services) which '
              'replaces the stack instead of popping.',
        );
        expect(
          find.text('SERVICES_LIST_STUB'),
          findsNothing,
          reason:
              'the services-list fallback screen must NOT appear — '
              'context.go(services) must not have fired when canPop was true',
        );
      },
    );

    // ── 2. Direct-entry path — close falls back to go(services) ─────────────

    testWidgets(
      'close button goes to services when there is no back stack (deep-link entry)',
      (tester) async {
        // The harness router uses serviceSetup as initialLocation — no prior
        // route on the stack — so canPop() is false and the fallback go() fires.
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[]),
          ),
        );
        await tester.pumpAndSettle();

        // The harness router starts at serviceSetup with no back-stack entry.
        // canPop() is false, so the close button must fire go(services).
        final closeBtn = find.byKey(const Key('btn-setup-close'));
        expect(
          closeBtn,
          findsOneWidget,
          reason: 'close button (Key btn-setup-close) must be present',
        );
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // The services-list stub body text must be visible — go(services) fired.
        expect(
          find.text('SERVICES_LIST_STUB'),
          findsOneWidget,
          reason:
              'close button must navigate to services via go() when the '
              'back stack is empty (deep-link / direct-entry path)',
        );
      },
    );
  });

  // ── Phase 317 D3 — the additive, nullable `exitRoute` ─────────────────────
  //
  // The phase doc originally claimed this screen needed no change. It was
  // wrong: `_leave()`'s no-stack fallback is a route LITERAL, so under a salon
  // target a cold start on `/salons/S/manage/staff/U/services/setup` would
  // `go` to the OPERATOR's own `/services` — a different master's catalogue
  // under the heading the operator just left. Deep link / cold start is
  // exactly the live case while phase 318's tile is unlanded.
  //
  // Two cases, deliberately paired: the OMITTED one is the "every current
  // caller unchanged" proof (the case above already covers the behaviour, this
  // one pins that the PARAMETER defaults to it), the SUPPLIED one proves the
  // parameter is threaded rather than accepted and ignored. Both assert the
  // PAGE that mounts, never a location string.

  group('Phase 317 D3 — exitRoute (the no-stack `go` fallback)', () {
    const String kSalonServices =
        '/salons/salon-S/manage/staff/user-U/services';

    Future<GoRouter> pumpSetup(WidgetTester tester, {String? exitRoute}) async {
      final router = GoRouter(
        initialLocation: RouteNames.serviceSetup,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.serviceSetup,
            builder: (_, _) => ServiceSetupScreen(exitRoute: exitRoute),
          ),
          GoRoute(
            path: RouteNames.services,
            builder: (_, _) => const Scaffold(body: Text('OWN_SERVICES_STUB')),
          ),
          GoRoute(
            path: '/salons/:salonId/manage/staff/:memberId/services',
            builder: (_, _) =>
                const Scaffold(body: Text('SALON_SERVICES_STUB')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: h
              .overrides(categories: const AsyncData(<ServiceCategoryOption>[]))
              .cast(),
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 1200)),
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets(
      'OMITTED — the fallback still lands on RouteNames.services, unchanged',
      (tester) async {
        await pumpSetup(tester);

        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(find.text('OWN_SERVICES_STUB'), findsOneWidget);
        expect(find.text('SALON_SERVICES_STUB'), findsNothing);
      },
    );

    testWidgets(
      'SUPPLIED — the fallback lands on the SALON services leaf, never the '
      "operator's own list",
      (tester) async {
        await pumpSetup(tester, exitRoute: kSalonServices);

        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(find.text('SALON_SERVICES_STUB'), findsOneWidget);
        expect(
          find.text('OWN_SERVICES_STUB'),
          findsNothing,
          reason:
              "a cold start on the salon setup leaf must not dump the "
              "operator on their OWN catalogue",
        );
      },
    );
  });

  // ── HIGH regression — per-field 400 lands inline on the offending SUBMITTED
  //   row instead of the generic «Перевірте дані» snack.
  //
  // The user-reported bug: a bulk-save 400 carrying per-field errors
  // (`errors: {"items[1].durationMinutes": "…"}`) surfaced the GENERIC
  // `errValidation` snack and flagged NO row, so the master could not tell
  // WHICH service the backend rejected. The fix:
  //   • service_setup_screen.dart — `_assemble()` captures `_submittedRows`
  //     (INCLUDED rows, in submitted order); `_save()` parses each
  //     `items[<i>].<field>` key, maps `i → _submittedRows[i]`, stamps
  //     `serverDurationError` (localized `serviceSetupDurationMax`) /
  //     `serverPriceError`, scrolls to the first flagged row, and only shows the
  //     generic snack when NO key maps;
  //   • service_setup_widgets.dart — the row card coalesces the server error into
  //     its inline field slot + red rim, and clears it on field edit.
  //
  // These tests FAIL against the old behaviour (generic snack, no row
  // flagged) and PASS now.

  group('per-field 400 maps to the offending submitted row (HIGH regression)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'server items[1].durationMinutes flags the 2nd SUBMITTED row inline '
      '(serviceSetupDurationMax + red rim), leaves the 1st clean, and does NOT '
      'show the generic errValidation snackbar',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Include BOTH rows with valid duration + price so a 2-item payload
        // assembles in submitted order [type-classic, type-gel].
        await toggleRowOn(tester, 'type-classic');
        await toggleRowOn(tester, 'type-gel');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The payload WAS submitted (both rows valid) — the 400 came from the
        // network, not the client guard.
        verify(() => h.repo.bulkCreate(any())).called(1);

        // items[1] → the 2nd SUBMITTED row (type-gel): the inline duration
        // message + the card's red error rim.
        expect(
          textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsOneWidget,
          reason:
              'the backend items[1] error must land inline on the 2nd submitted '
              'row (type-gel) as the localized duration-max message',
        );
        expect(rowHasErrorRim(tester, 'type-gel'), isTrue);

        // The 1st submitted row (type-classic) is untouched.
        expect(
          textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);

        // The generic validation snackbar must NOT fire — the OLD behaviour did
        // exactly this (and flagged no row).
        expect(
          find.text(l10n.errValidation),
          findsNothing,
          reason:
              'a per-field 400 that maps to a row must be shown inline, NOT via '
              'the generic errValidation snackbar (the regressed behaviour)',
        );
      },
    );

    testWidgets(
      'the index is into the SUBMITTED list, not the on-screen list — an '
      'EXCLUDED row is skipped so items[1] maps past it to the correct row',
      (tester) async {
        // Rows on screen: [classic (EXCLUDED), gel (incl), art (incl)].
        // Submitted order (only included, in order): [gel, art].
        //   items[0] → gel   (on-screen index 1)
        //   items[1] → art   (on-screen index 2)   ← the error target
        // A NAIVE on-screen index would wrongly resolve items[1] → gel, so
        // asserting the error lands on `art` (and NOT `gel`) proves the mapping
        // walks the submitted list, not the visible one.
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel, typeArt],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Include gel + art (leave classic EXCLUDED), both valid.
        await toggleRowOn(tester, 'type-gel');
        await toggleRowOn(tester, 'type-art');
        await fillRowFixed(tester, 'type-gel', duration: '60', price: '500');
        await fillRowFixed(tester, 'type-art', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);

        // items[1] → `art` (submitted index 1), NOT the on-screen index-1 `gel`.
        expect(
          textInRow('type-art', l10n.serviceSetupDurationMax),
          findsOneWidget,
          reason:
              'items[1] must map to the 2nd SUBMITTED row (art), not the 2nd '
              'on-screen row (gel) — the excluded classic row is not submitted',
        );
        expect(rowHasErrorRim(tester, 'type-art'), isTrue);

        // gel (submitted index 0) + classic (excluded) must be clean.
        expect(
          textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(rowHasErrorRim(tester, 'type-gel'), isFalse);
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );

    testWidgets(
      'client-side > 480 guard flags the row (durationTooLong / '
      'serviceSetupDurationMax) BEFORE the network — bulkCreate is never called',
      (tester) async {
        // No bulkCreate stub — the client guard must short-circuit before any
        // network call, so the repository is never touched.
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await toggleRowOn(tester, 'type-classic');
        // 500 > 480 → the client mirror of the backend @Max(480) guard fires.
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '500',
          price: '500',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The duration-max copy is rendered on the row (header flag + inline
        // duration hint both use serviceSetupDurationMax for durationTooLong).
        expect(
          textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsWidgets,
          reason:
              'the > 480 client guard must surface serviceSetupDurationMax on '
              'the row before any network round-trip',
        );
        expect(rowHasErrorRim(tester, 'type-classic'), isTrue);

        // Proven pre-submit: the repository was NEVER called (count stays 0).
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'a 400 whose field key does NOT match items[i].field falls back to the '
      'generic errValidation snackbar and flags no row',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{'somethingUnknown': 'x'},
          ),
        );

        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);

        // Unmappable key → the generic snack is preserved (fallback intact).
        expect(find.text(l10n.errValidation), findsOneWidget);
        // No row flag / rim — nothing mapped to a row.
        expect(
          textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'editing the flagged row\'s duration clears the mapped-back server error '
      '(inline message + red rim both disappear)',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await toggleRowOn(tester, 'type-classic');
        await toggleRowOn(tester, 'type-gel');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // Precondition: the server error is on type-gel.
        expect(
          textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsOneWidget,
        );
        expect(rowHasErrorRim(tester, 'type-gel'), isTrue);

        // Editing the flagged row's duration clears the mapped-back error.
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-gel')),
                matching: find.byType(TextField),
              )
              .first,
          '75',
        );
        await tester.pumpAndSettle();

        expect(
          textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsNothing,
          reason: 'the server duration error must clear as the master edits it',
        );
        expect(rowHasErrorRim(tester, 'type-gel'), isFalse);
      },
    );
  });
}
