// [ServiceSetupScreen] widget tests:
// APPEND mode — owned types as copies (phase 468), SETUP vs APPEND copy.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
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

  // ── APPEND mode — already-owned types can be added again (phase 468) ──────
  //
  // Backend 464/465: a master may hold the same service type more than once if
  // each active copy differs in duration OR name; an exact duplicate is a 409.
  // The add-services row has no name field, so the client mirrors only the
  // DURATION half: an owned type keeps its switch, starts with an EMPTY
  // duration when selected (phase 472 dropped the free quick-pick seed), and
  // blocks the CTA with an inline error while its
  // duration matches an existing copy. `ownsClassic` owns classic at 60 min.

  group('APPEND mode — an owned type is selectable as a copy (phase 468)', () {
    testWidgets(
      'an already-owned type renders «Вже додано» AND its include toggle; the '
      'unowned sibling is unchanged (toggle, no sub-label)',
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

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
          reason: 'phase 468: an owned type is no longer locked',
        );
        expect(
          textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
          findsOneWidget,
        );
        expect(
          textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
          findsNothing,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expectRowHasNoOffStateSubLabel(tester, l10n, 'type-gel');
        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsNothing);
      },
    );

    testWidgets(
      'the SAME catalogue with an EMPTY services list renders no «Вже додано»',
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
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
      },
    );

    testWidgets(
      'phase 472: selecting the owned type leaves the duration EMPTY (no '
      'autofill); a typed free 90 has no taken error, CTA live, and the '
      'payload carries the copy at 90',
      (tester) async {
        final captured = <List<MasterServiceBulkItem>>[];
        when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
          captured.add(
            invocation.positionalArguments.first as List<MasterServiceBulkItem>,
          );
          return createdService;
        });

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

        await toggleRowOn(tester, 'type-classic');

        expect(
          durationText(tester, 'type-classic'),
          isEmpty,
          reason: 'phase 472: an owned row is no longer autofilled on toggle',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('setup_row_type-classic')),
            matching: find.byKey(const Key('service-setup-duration')),
          ),
          '90',
        );
        await tester.pumpAndSettle();
        expect(
          textInRow('type-classic', l10n.serviceSetupCopyCollision),
          findsNothing,
        );

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('setup_row_type-classic')),
            matching: find.byKey(const Key('pricing-fixed-amount')),
          ),
          '650',
        );
        await tester.pumpAndSettle();
        expect(saveOnPressed(tester), isNotNull);

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        final item = captured.single.single;
        expect(item.serviceTypeId, 'type-classic');
        expect(item.durationMinutes, 90);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'choosing the OWNED duration shows the inline taken error + red rim and '
      'disables the CTA; a free duration clears both',
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

        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );

        expect(
          textInRow('type-classic', l10n.serviceSetupCopyCollision),
          findsOneWidget,
        );
        expect(rowHasErrorRim(tester, 'type-classic'), isTrue);
        expect(
          saveOnPressed(tester),
          isNull,
          reason: 'an exact duplicate must never be submittable',
        );

        await fillRowFixed(
          tester,
          'type-classic',
          duration: '75',
          price: '500',
        );

        expect(
          textInRow('type-classic', l10n.serviceSetupCopyCollision),
          findsNothing,
        );
        expect(rowHasErrorRim(tester, 'type-classic'), isFalse);
        expect(saveOnPressed(tester), isNotNull);
      },
    );

    testWidgets(
      'the payload after including only the UNOWNED sibling carries only its '
      'serviceTypeId — an owned row that is not selected never leaks in',
      (tester) async {
        final captured = <List<MasterServiceBulkItem>>[];
        when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
          captured.add(
            invocation.positionalArguments.first as List<MasterServiceBulkItem>,
          );
          return createdService;
        });

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

        await toggleRowOn(tester, 'type-gel');
        await fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(captured.single.map((i) => i.serviceTypeId).toList(), <String>[
          'type-gel',
        ]);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'the group header "n з m" denominator counts every type now that owned '
      'ones are selectable — 1 of 2 owned reads «0 з 2»',
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

        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
        await toggleRowOn(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupGroupCount(1, 2)), findsOneWidget);
      },
    );

    testWidgets('with an EMPTY catalogue the SAME two types read «0 з 2»', (
      tester,
    ) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
      expect(find.text(l10n.serviceSetupGroupCount(0, 1)), findsNothing);
    });

    testWidgets(
      'when EVERY type in the category is owned the note still says so, but '
      'both rows keep their toggles',
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
            existingServices: ownsClassicAndGel,
          ),
        );
        await expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsOneWidget);
        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNWidgets(2));
        // Nothing included yet → the CTA stays disabled.
        expect(saveOnPressed(tester), isNull);
        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
      },
    );
  });

  // ── Off-state sub-label — the three mutually exclusive facts, together ─────
  //
  // The sub-label slot under a collapsed row's name renders AT MOST one of two
  // facts now (`locked` → «Вже додано», `ownedNow` → «уже у вашому переліку»,
  // emphasised). A THIRD, merely-off row — neither at-load-owned nor just
  // claimed by a catalogue refresh — used to render a generic «Не пропонується»
  // sub-label; that branch was deleted, so it now renders NOTHING beyond the
  // name (regression: see the "renders no sub-label" assertions above, each
  // proven to go RED against the old 3-way branch by a mutation probe).
  //
  // The three states are exercised individually elsewhere in this file. This
  // group is the ONE place that stands all three up side by side in a single
  // screen — classic is owned at load (`locked`), art gets claimed by a
  // catalogue refresh mid-session (`ownedNow`), gel is never touched
  // (merely off) — so mutual exclusivity and the emphasis style are pinned
  // against real siblings rather than in isolation.
  group('off-state sub-label — locked / ownedNow / merely-off side by side', () {
    testWidgets('locked shows AlreadyAdded plainly, ownedNow shows AlreadyInMenu '
        'emphasised, merely-off shows neither — and no row ever renders the '
        'deleted generic «Не пропонується» copy', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

      // Build 1 (initState snapshot): classic already owned → `locked`.
      // Build 2 (post-409 re-read): art JOINS the owned set → `ownedNow`.
      // Gel is never included in either build and never toggled, so it stays
      // merely off for the whole test.
      final servicesList = MutatingServicesList(<List<MasterService>>[
        ownsClassic,
        <MasterService>[
          ...ownsClassic,
          const MasterService(
            id: 'svc-owned-art',
            serviceDefId: 'def-owned-art',
            name: 'Художній розпис',
            serviceTypeId: 'type-art',
            durationMinutes: 45,
            priceMin: 300,
            priceDisplay: '300 ₴',
          ),
        ],
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
            (ref) => const <ServiceTypeOption>[typeClassic, typeGel, typeArt],
          ),
        ],
      );
      await expand(tester, 'MANICURE');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      // Include + fill art, then trigger the 409 re-read that claims it.
      await toggleRowOn(tester, 'type-art');
      await fillRowFixed(tester, 'type-art', duration: '45', price: '300');
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      // ── classic — locked (owned at load) ──────────────────────────────
      expect(
        find.byKey(const Key('setup_row_toggle_type-classic')),
        findsOneWidget,
        reason: 'phase 468: an owned row keeps its include switch',
      );
      expect(
        textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
        findsOneWidget,
      );
      expect(
        textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
        findsNothing,
        reason: 'locked and ownedNow are mutually exclusive facts',
      );
      expect(
        tester
            .widget<Text>(
              textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
            )
            .style
            ?.fontWeight,
        isNot(FontWeight.w800),
        reason:
            'the plain "already added" fact must NOT carry the '
            'catalogue-refresh emphasis style',
      );

      // ── art — ownedNow (claimed by the mid-session catalogue refresh) ──
      expect(
        find.byKey(const Key('setup_row_toggle_type-art')),
        findsOneWidget,
        reason: 'ownedNow keeps its (now-off) switch',
      );
      expect(
        textInRow('type-art', l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
      );
      expect(
        textInRow('type-art', l10n.serviceSetupRowAlreadyAdded),
        findsNothing,
        reason: 'ownedNow and locked are mutually exclusive facts',
      );
      final artSubLabelStyle = tester
          .widget<Text>(
            textInRow('type-art', l10n.serviceSetupRowAlreadyInMenu),
          )
          .style;
      expect(
        artSubLabelStyle?.fontWeight,
        FontWeight.w800,
        reason:
            'ownedNow is the one fact that CHANGED under the master — '
            'it must read as emphasised, not as a routine label',
      );
      expect(artSubLabelStyle?.color, BrandColors.accentDeep);

      // ── gel — merely off (never locked, never claimed) ─────────────────
      expect(
        find.byKey(const Key('setup_row_toggle_type-gel')),
        findsOneWidget,
        reason: 'a merely-off row stays freely selectable',
      );
      // Neither locked nor ownedNow — nothing to say beyond the switch itself.
      expectRowHasNoOffStateSubLabel(tester, l10n, 'type-gel');

      // ── no row, anywhere on screen, resurrects the deleted generic copy ─
      expect(
        // i18n-finder-ok: pins the exact DELETED literal, not live UI copy — asserts serviceSetupRowExcluded never resurfaces under a new l10n key
        find.text('Не пропонується'),
        findsNothing,
        reason:
            'serviceSetupRowExcluded was deleted from both ARBs — this '
            'pins the exact removed literal, not just a Text count, so a '
            'regression that reintroduces it under a NEW l10n key still '
            'fails this assertion',
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  // ── State-level — ServiceRowState copies (phase 468) ──────────────────────

  group('ServiceRowState — owned type as a copy (phase 468)', () {
    test('phase 472: including an owned row succeeds and leaves the duration '
        'EMPTY (no quick-pick autofill)', () {
      final row = ServiceRowState(
        serviceTypeId: 'type-classic',
        nameUk: 'Класичний манікюр',
        alreadyAdded: true,
        ownedDurations: const <int>{60},
      );
      addTearDown(row.dispose);

      row.included = true;

      expect(row.included, isTrue);
      expect(row.duration.text, isEmpty);
      expect(row.durationMinutes, isNull);
      expect(row.durationTaken, isFalse);
    });

    test('a free duration the master typed survives toggling on', () {
      final row = ServiceRowState(
        serviceTypeId: 'type-classic',
        nameUk: 'Класичний манікюр',
        alreadyAdded: true,
        ownedDurations: const <int>{60},
      );
      addTearDown(row.dispose);
      row.duration.text = '75';

      row.included = true;

      expect(row.duration.text, '75');
    });

    test('durationTaken is true only while included at an owned duration', () {
      final row = ServiceRowState(
        serviceTypeId: 'type-classic',
        nameUk: 'Класичний манікюр',
        alreadyAdded: true,
        ownedDurations: const <int>{60, 90},
      );
      addTearDown(row.dispose);
      row.duration.text = '60';
      expect(row.durationTaken, isFalse, reason: 'excluded rows never block');

      row.included = true;
      expect(
        row.duration.text,
        '60',
        reason: 'phase 472: the toggle no longer replaces a taken duration',
      );
      expect(row.durationTaken, isTrue);
      row.duration.text = ' 90 ';
      expect(row.durationTaken, isTrue);
      row.duration.text = '45';
      expect(row.durationTaken, isFalse);
    });

    test('a NON-owned row toggles normally and keeps an empty duration', () {
      final row = ServiceRowState(
        serviceTypeId: 'type-gel',
        nameUk: 'Гель-лак',
      );
      addTearDown(row.dispose);

      var notifications = 0;
      row.addListener(() => notifications++);

      row.included = true;

      expect(row.included, isTrue);
      expect(row.duration.text, isEmpty);
      expect(notifications, 1);
    });
  });

  // ── SETUP vs APPEND copy ───────────────────────────────────────────────────
  //
  // One screen, two framings. `_appending` is derived ONCE in initState from
  // `servicesListProvider.value` being non-empty. Both directions are asserted
  // (and each asserts the OTHER variant is absent) so the switch is genuinely
  // pinned rather than accidentally satisfied by a shared substring.

  group('SETUP vs APPEND copy', () {
    testWidgets(
      'a NON-EMPTY catalogue uses the APPEND title + «Додати N» CTA',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
            // Owns something UNRELATED — APPEND framing with no row exclusion,
            // so this test isolates the copy switch from the exclusion logic.
            existingServices: ownsUnrelated,
          ),
        );
        await expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.text(l10n.serviceSetupTitleAppend), findsOneWidget);
        expect(find.text(l10n.serviceSetupTitle), findsNothing);

        await toggleRowOn(tester, 'type-classic');

        expect(find.text(l10n.serviceSetupCtaAdd(1)), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsNothing);
      },
    );

    testWidgets('an EMPTY catalogue uses the SETUP title + «Створити N» CTA', (
      tester,
    ) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(find.text(l10n.serviceSetupTitle), findsOneWidget);
      expect(find.text(l10n.serviceSetupTitleAppend), findsNothing);

      await toggleRowOn(tester, 'type-classic');

      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      expect(find.text(l10n.serviceSetupCtaAdd(1)), findsNothing);
    });
  });
}
