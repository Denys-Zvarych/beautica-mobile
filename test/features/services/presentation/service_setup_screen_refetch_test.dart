// [ServiceSetupScreen] widget tests:
// untyped legacy rows, 409 re-read, busy latch, suggestion refetch,
// lazy row cards.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import 'service_setup_test_harness.dart';

void main() {
  late Harness h;

  setUp(() {
    h = Harness();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
    registerFallbackValue(const MasterServiceUpdate());
  });

  // ── Nullable serviceTypeId degrades toward UNDER-blocking ──────────────────
  //
  // `MasterService.serviceTypeId` is nullable: a pre-Phase-16.3 row carries no
  // type id. `_ownedDurationsByType` is built with
  // `if (s.serviceTypeId case final String id when id.isNotEmpty)`, so such a
  // row contributes nothing and the corresponding type stays SELECTABLE.
  //
  // That direction is a deliberate product call, and it is the direction worth
  // pinning: over-blocking would hide a service the master cannot add any other
  // way (this screen is now the ONLY "add services" surface), whereas
  // under-blocking costs at most one recoverable, explained 409.
  //
  // The fixture's display name is identical to the service-type's, so a
  // "helpful" future change that matched owned services by NAME instead of ID
  // turns this test red immediately.

  group('APPEND with an untyped legacy service — exclusion is by ID only', () {
    testWidgets(
      'a catalogue row with a null serviceTypeId blocks NOTHING, even when its '
      'name matches a service type exactly',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
            existingServices: ownsUntypedLegacyRow,
          ),
        );
        await expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // The catalogue is non-empty, so the screen IS in APPEND mode — this
        // proves the snapshot was read and non-empty, i.e. the assertions below
        // are about the ID filter and not about the screen having silently
        // fallen back to SETUP.
        expect(
          find.text(l10n.serviceSetupTitleAppend),
          findsOneWidget,
          reason:
              'precondition: a non-empty catalogue must select APPEND framing, '
              'otherwise this test would pass trivially in SETUP mode',
        );

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
          reason:
              'an untyped legacy row cannot be matched to a service type, so '
              'the type must stay selectable — degrading to a recoverable 409 '
              'beats hiding a service the master has no other way to add',
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsNothing);
        // The denominator counts both types — nothing was excluded.
        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
      },
    );

    testWidgets(
      'CONTRAST — the SAME row carrying the matching serviceTypeId DOES mark '
      'it owned, so the test above is about the null and not about the fixture',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
            existingServices: ownsClassic,
          ),
        );
        await expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        // Phase 468: ownership no longer removes the switch — it marks the row
        // «Вже додано» (and seeds its owned durations).
        expect(
          textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
          findsOneWidget,
        );
        expect(
          textInRow('type-gel', l10n.serviceSetupRowAlreadyAdded),
          findsNothing,
        );
      },
    );
  });

  // ── _flagRowsNowOwned — the 409 catalogue re-read (E) ──────────────────────
  //
  // The 409 handler now re-reads the master's catalogue and switches OFF only
  // the included rows the REFRESHED list actually claims, flagging each
  // `alreadyInMenu`. The claim in the source comment is explicit and narrow:
  // "Every other selection, and every typed value, is untouched."
  //
  // That second half is the part worth pinning. A re-read that resets the whole
  // form would also make the first half's assertion pass, so both directions
  // are asserted in the same test against the SAME screen state — one row that
  // must change, one that must not.

  group('409 catalogue re-read switches off ONLY the newly-owned rows', () {
    testWidgets(
      'the row the refreshed catalogue claims goes off and says «already in '
      'menu»; the other row keeps BOTH its selection and its typed values',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

        // Build 1 is the initState snapshot: an EMPTY catalogue, so both types
        // are freely includable and the screen takes SETUP framing. Build 2 —
        // the read `_flagRowsNowOwned` performs after the handler's invalidate
        // — is the catalogue having gained CLASSIC behind the master's back.
        // That divergence is the whole scenario: a fixed seed would have seeded
        // `alreadyAdded` true on classic, making it un-includable and the 409
        // unreachable.
        final servicesList = MutatingServicesList(<List<MasterService>>[
          const <MasterService>[],
          ownsClassic,
        ]);

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2000),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(() => servicesList),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[manicure],
            ),
            serviceTypesProvider('MANICURE').overrideWith(
              (ref) => const <ServiceTypeOption>[typeClassic, typeGel],
            ),
          ],
        );
        await expand(tester, 'MANICURE');

        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await toggleRowOn(tester, 'type-gel');
        await fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Precondition: BOTH rows are included, so the post-409 count drop is
        // attributable to the re-read and not to a row that was never on.
        expect(
          find.text(l10n.serviceSetupCtaCreate(2)),
          findsOneWidget,
          reason:
              'precondition: two included rows before the save, otherwise the '
              '"only one was switched off" assertion below is vacuous',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The re-read actually happened.
        expect(
          servicesList.builds,
          greaterThanOrEqualTo(2),
          reason:
              '_flagRowsNowOwned must re-read the catalogue after the '
              'invalidate — with one build it is the stale initState snapshot '
              'answering, which can never claim a new row',
        );

        // ── The row that must change ────────────────────────────────────────
        expect(
          textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
          findsOneWidget,
          reason:
              'the refreshed catalogue claims classic, so its row must be '
              'switched off AND say so — going quiet silently is the other bad '
              'option this copy exists to avoid',
        );

        // ── The row that must NOT change ────────────────────────────────────
        expect(
          textInRow('type-gel', l10n.serviceSetupRowAlreadyInMenu),
          findsNothing,
          reason:
              'the refreshed catalogue does NOT claim gel, so a re-read that '
              'flags it is over-reaching',
        );
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'exactly one row was switched off — a count of 0 would mean the '
              're-read wiped the whole selection, which is the failure mode the '
              '"every other selection is untouched" promise rules out',
        );
        // Gel's card is still EXPANDED (it is still included), so its typed
        // values are still on screen to be read back.
        expect(
          durationText(tester, 'type-gel'),
          '90',
          reason:
              'the untouched row must keep the duration the master typed — a '
              're-read that rebuilds rows from scratch loses it',
        );
        expect(
          fixedPriceText(tester, 'type-gel'),
          '700',
          reason: 'and its price',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── _retryingAfterBusy latch (D) ───────────────────────────────────────────
  //
  // A 503 retry can land on a 409 whose meaning is genuinely ambiguous: an edge
  // proxy can return 503 AFTER the write committed, so "duplicate" may mean
  // "your own previous attempt succeeded". The latch swaps the copy for exactly
  // that case.
  //
  // A latch is only as good as its clearing. `_save` consumes it into a local
  // and resets it on the FIRST statement after the mounted guard, so an
  // intervening non-409 failure must leave the next ordinary duplicate reported
  // as a plain duplicate. A latch cleared only inside the 409 branch would pass
  // the first test below and fail the second.

  group('_retryingAfterBusy — ambiguous-duplicate copy is armed, then cleared', () {
    /// Fails `bulkCreate` with `failures` in order, repeating the last one.
    void seedFailures(List<Failure> failures, void Function(int) onCall) {
      var calls = 0;
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        final Failure f = failures[calls.clamp(0, failures.length - 1)];
        calls++;
        onCall(calls);
        throw f;
      });
    }

    Future<void> pumpOneIncludedRow(WidgetTester tester) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
          // Empty, so `_flagRowsNowOwned` early-returns on an empty owned set
          // and cannot disturb the selection between saves.
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, 'type-classic');
      await fillRowFixed(tester, 'type-classic', duration: '60', price: '500');
    }

    testWidgets(
      'a 409 landing on a 503 RETRY reports the ambiguous "may already have '
      'saved" copy, not the plain duplicate',
      (tester) async {
        var seen = 0;
        seedFailures(const <Failure>[
          BulkSetupBusyFailure(),
          ServiceDuplicateFailure(),
        ], (c) => seen = c);

        await pumpOneIncludedRow(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 1);
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // The retry arms the latch, then re-saves into the 409.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(seen, 2);
        expect(
          find.text(l10n.serviceSetupErrDuplicateAfterRetry),
          findsOneWidget,
          reason:
              'after a 503 the batch fate is unknown, so the copy must claim '
              'neither outcome and point the master at their list',
        );
        expect(
          find.text(l10n.serviceErrDuplicate),
          findsNothing,
          reason:
              'the plain duplicate copy asserts the save definitely did not '
              'happen — exactly the claim this path cannot make',
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'the latch does NOT survive a non-409 failure — a later ordinary '
      'duplicate is reported plainly',
      (tester) async {
        var seen = 0;
        seedFailures(const <Failure>[
          // 1: the 503 that offers the retry.
          BulkSetupBusyFailure(),
          // 2: the retry itself fails with something that is NOT a 409, so the
          // latch is consumed by this save and never reaches a duplicate.
          ServerFailure(statusCode: 500),
          // 3: a fresh, deliberate save that duplicates. It is NOT a retry, so
          // it must read as a plain duplicate.
          ServiceDuplicateFailure(),
        ], (c) => seen = c);

        await pumpOneIncludedRow(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 1);

        // Arm the latch, and let the retry fail with the 500.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();
        expect(seen, 2);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'precondition: a 500 is not the 503 branch, so no retry action — '
              'the next save must be a deliberate CTA tap, not a retry',
        );

        // The floating 500 snack sits OVER the CTA, so the next tap would be
        // swallowed by the overlay. `ScaffoldMessenger.clearSnackBars()` is a
        // no-op against VelvetSnack (wrong host entirely — see
        // `test/helpers/velvet_snack_matchers.dart`'s file header); draining
        // its full lifecycle via `pumpPastVelvetSnack` is what actually
        // removes it (and, unlike a raw fixed wait, drives the SAME virtual
        // clock `pumpAndSettle` already uses rather than sleeping real time).
        await pumpPastVelvetSnack(tester);

        // A fresh save, from the CTA, that duplicates.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 3);

        expect(
          find.text(l10n.serviceErrDuplicate),
          findsOneWidget,
          reason:
              'this duplicate followed an ordinary save, so the honest copy is '
              'the plain one — nothing about it is ambiguous',
        );
        expect(
          find.text(l10n.serviceSetupErrDuplicateAfterRetry),
          findsNothing,
          reason:
              'a latch left armed by the intervening 500 would mislabel this '
              'as "may already have saved", telling the master to go hunting '
              'for a service that was never written',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Refetch row identity + deferred disposal (C, second half) ──────────────
  //
  // `_loadCategory` doubles as a REFETCH: surviving service-types keep their
  // EXISTING `ServiceRowState` (same object, so controllers/include flag/pricing
  // mode carry over) and only vanished types are dropped — disposed after the
  // frame that unmounts their card, never during it.
  //
  // The refetch test above pins that the refresh HAPPENS. Neither half of what
  // makes it safe was pinned: that a surviving row keeps what the master typed,
  // and that a vanished row's controllers are not torn down while its card is
  // still reading them.

  group('suggestion refetch — surviving rows carry over, vanished rows are '
      'disposed after the frame', () {
    /// Opens the type-suggestion dialog for `slug` and submits `name`.
    Future<void> suggestType(
      WidgetTester tester,
      String slug,
      String name,
    ) async {
      await tester.ensureVisible(
        find.byKey(ValueKey<String>('suggest_type_$slug')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(ValueKey<String>('suggest_type_$slug')),
              matching: find.byType(GestureDetector),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-type-suggest-name')),
          matching: find.byType(TextField),
        ),
        name,
      );
      await tester.tap(
        find.byKey(const Key('btn-submit-suggest-service-type')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a row that SURVIVES the refetch keeps its include state and every value '
      'the master typed',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        var typeFetches = 0;

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[manicure],
            ),
            // Build 1: classic only. Build 2 (the refetch): classic SURVIVES
            // and gel joins it — so classic is the carried-over row.
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[typeClassic]
                  : const <ServiceTypeOption>[typeClassic, typeGel];
            }),
          ],
        );
        await expand(tester, 'MANICURE');

        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '75',
          price: '650',
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason: 'precondition: classic is included before the refetch',
        );

        await suggestType(tester, 'MANICURE', 'Lamination');
        await pumpPastVelvetSnack(tester);

        // The refetch ran and brought the new type in.
        expect(typeFetches, greaterThanOrEqualTo(2));
        expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);

        // …and classic came through it untouched.
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'the carried-over row must still be INCLUDED — rebuilding it as a '
              'fresh ServiceRowState resets `included` to false and silently '
              'empties the batch the master had assembled',
        );
        expect(
          durationText(tester, 'type-classic'),
          '75',
          reason:
              'identity reuse is what preserves the controllers — a rebuilt row '
              'comes back with empty fields and the master retypes everything '
              'they had already entered',
        );
        expect(fixedPriceText(tester, 'type-classic'), '650');
      },
    );

    testWidgets(
      'a row that VANISHES from the refetched catalogue is dropped without a '
      'use-after-dispose on its still-mounted card',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        var typeFetches = 0;

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[manicure],
            ),
            // Build 2 DROPS gel — the type was retired platform-side between
            // the first expand and the refetch. Its row is orphaned while its
            // card is still mounted and still listening to its controllers.
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[typeClassic, typeGel]
                  : const <ServiceTypeOption>[typeClassic];
            }),
          ],
        );
        await expand(tester, 'MANICURE');

        // Gel is ON and expanded, so its card holds live listeners on all four
        // of the row's controllers — the state that makes an eager dispose
        // observable rather than theoretical.
        await toggleRowOn(tester, 'type-gel');
        await fillRowFixed(tester, 'type-gel', duration: '90', price: '700');
        expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);

        await suggestType(tester, 'MANICURE', 'Lamination');
        // Drain the success snack BEFORE the next tap below (toggleRowOn) —
        // it is bottom-anchored and would otherwise sit over the row's
        // include switch, hit-testing into the overlay and silently missing.
        await pumpPastVelvetSnack(tester);

        expect(typeFetches, greaterThanOrEqualTo(2));
        expect(
          find.byKey(const Key('setup_row_type-gel')),
          findsNothing,
          reason:
              'precondition: the refetched catalogue no longer offers gel, so '
              'its row really was orphaned — without this the no-exception '
              'assertion below proves nothing',
        );
        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsOneWidget,
          reason: 'the surviving type is unaffected',
        );
        // SCOPE, measured rather than assumed (mutation-probed 2026-08-04):
        // this assertion catches disposing the orphans BEFORE the rebuilding
        // `setState` — that goes red with "A TextEditingController was used
        // after being disposed". It does NOT distinguish `addPostFrameCallback`
        // from a plain synchronous dispose placed immediately AFTER that
        // setState; by then the card is already scheduled out of the tree and
        // nothing reads the controllers again. So this pins the invariant
        // ("a vanished row never leaves a use-after-dispose behind"), not the
        // post-frame scheduling as such. Stated here so a later reader does not
        // mistake it for a guard on the callback itself.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'disposing an orphan while its card can still read its '
              'controllers is a use-after-dispose — the ordering in '
              '_disposeAfterFrame exists to keep exactly one owner',
        );

        // The screen must still be usable afterwards — a half-disposed row can
        // leave the tree throwing on the next interaction rather than this one.
        await toggleRowOn(tester, 'type-classic');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── Lazy row cards survive scroll recycling (G) ────────────────────────────
  //
  // Row cards are now built on demand from the `SliverList` delegate rather than
  // eagerly in `_expandedSlots`. That makes an off-screen row's card genuinely
  // UNMOUNT, which is precisely the condition under which per-row state kept in
  // the widget tree — rather than in the `ServiceRowState` the screen owns —
  // would be silently lost.
  //
  // Goldens cannot catch this: they render one frame and never scroll. The
  // regression shape is "master fills a row near the top, scrolls to the bottom
  // of a long category, comes back, and their values are gone".

  group('lazy row cards — state survives a scroll out of and back into view', () {
    testWidgets(
      'a filled row scrolled out of the viewport and back keeps its include '
      'state and typed values',
      (tester) async {
        // Enough rows that the sliver's cache extent cannot keep the first one
        // alive off-screen — with only two or three rows it would stay mounted
        // and the test would pass without ever exercising a recycle.
        final manyTypes = <ServiceTypeOption>[
          typeClassic,
          for (var i = 0; i < 16; i++)
            ServiceTypeOption(
              id: 'type-filler-$i',
              slug: 'FILLER$i',
              nameUk: 'Filler type $i',
              categoryName: 'MANICURE',
            ),
        ];

        await pump(
          tester,
          h,
          // Deliberately SHORT — a tall surface renders every row at once and
          // there is nothing to recycle.
          surfaceSize: const Size(420, 700),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': manyTypes,
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');

        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '45',
          price: '350',
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);

        final Finder scroller = find.byType(Scrollable).first;

        // Scroll far past the row, in steps — one huge drag can be clamped by
        // the scroll physics into a shorter effective distance.
        for (var i = 0; i < 4; i++) {
          await tester.drag(scroller, const Offset(0, -600));
          await tester.pumpAndSettle();
        }

        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsNothing,
          reason:
              'precondition: the lazy SliverList really did unmount the card. '
              'If this row is still in the tree the test is not exercising '
              'recycling at all and the assertions below are vacuous',
        );

        // Back to the top.
        for (var i = 0; i < 6; i++) {
          await tester.drag(scroller, const Offset(0, 600));
          await tester.pumpAndSettle();
        }

        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsOneWidget,
          reason: 'the card is rebuilt on the way back into view',
        );
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'the include flag lives on the ServiceRowState the screen owns, '
              'not in the card — a recycle that resets it silently empties the '
              'batch',
        );
        expect(
          durationText(tester, 'type-classic'),
          '45',
          reason:
              'the controllers are owned by ServiceRowState and outlive the '
              'card — a rebuilt card that re-creates them loses what the master '
              'typed the moment they scroll',
        );
        expect(fixedPriceText(tester, 'type-classic'), '350');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
