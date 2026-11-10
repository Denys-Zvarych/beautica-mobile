// [ServiceSetupScreen] widget tests:
// phase 471 — copy rows («+ додати ще» / «Прибрати») + pair check.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
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

  // ── Phase 471 — «+ додати ще» copy rows + client pair check ────────────────────
  group('phase 471 — copy rows («+ додати ще» / «Прибрати») + pair check', () {
    const String classic = 'type-classic';
    const String copy1 = 'type-classic_copy_1';

    Finder inRow(String keyId, Key key) => find.descendant(
      of: find.byKey(Key('setup_row_$keyId')),
      matching: find.byKey(key),
    );

    Future<void> tapKey(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    Future<void> setDuration(
      WidgetTester tester,
      String keyId,
      String value,
    ) async {
      await tester.enterText(
        inRow(keyId, const Key('service-setup-duration')),
        value,
      );
      await tester.pumpAndSettle();
    }

    Future<void> setPrice(WidgetTester tester, String keyId, String v) async {
      await tester.enterText(
        inRow(keyId, const Key('pricing-fixed-amount')),
        v,
      );
      await tester.pumpAndSettle();
    }

    Future<void> setName(WidgetTester tester, String keyId, String v) async {
      // Phase 472 (D3): the name well opens from the card's pencil.
      if (find.byKey(Key('setup_row_name_$keyId')).evaluate().isEmpty) {
        await tapKey(tester, Key('btn-setup-row-name-$keyId'));
      }
      await tester.enterText(
        find.descendant(
          of: find.byKey(Key('setup_row_name_$keyId')),
          matching: find.byType(TextField),
        ),
        v,
      );
      await tester.pumpAndSettle();
    }

    String durationOf(WidgetTester tester, String keyId) =>
        tester
            .widget<TextField>(
              find.descendant(
                of: inRow(keyId, const Key('service-setup-duration')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text ??
        '';

    /// SETUP mode, MANICURE expanded, classic included at 60 / 500 ₴, then
    /// «+ додати ще» tapped once.
    Future<AppLocalizations> pumpWithCopy(
      WidgetTester tester, {
      List<Object>? overrides,
    }) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 2000),
        overrides:
            overrides ??
            h.overrides(
              categories: const AsyncData(<ServiceCategoryOption>[manicure]),
              typesBySlug: <String, List<ServiceTypeOption>>{
                'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
              },
            ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, classic);
      await setDuration(tester, classic, '60');
      await setPrice(tester, classic, '500');
      await tapKey(tester, const Key('btn-setup-row-add-copy-$classic'));
      return AppLocalizations.delegate.load(const Locale('uk'));
    }

    List<List<MasterServiceBulkItem>> captureSaves() {
      final captured = <List<MasterServiceBulkItem>>[];
      when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
        captured.add(
          invocation.positionalArguments.first as List<MasterServiceBulkItem>,
        );
        return createdService;
      });
      return captured;
    }

    testWidgets('«+ додати ще» adds an included copy row with an EMPTY '
        'duration (D4) and an empty price; both rows get a name pencil (D3) '
        'and «Прибрати»', (tester) async {
      final l10n = await pumpWithCopy(tester);

      expect(find.byKey(const Key('setup_row_$copy1')), findsOneWidget);
      expect(durationOf(tester, copy1), isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: inRow(copy1, const Key('pricing-fixed-amount')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        isEmpty,
      );
      for (final k in <String>[classic, copy1]) {
        // Phase 472 (D3): a pencil on each card; the well opens from it.
        expect(find.byKey(Key('btn-setup-row-name-$k')), findsOneWidget);
        expect(find.byKey(Key('setup_row_name_$k')), findsNothing);
        expect(find.byKey(Key('btn-setup-row-remove-$k')), findsOneWidget);
      }
      // A type without copies keeps the pre-471 row: no name, no remove.
      expect(find.byKey(const Key('setup_row_name_type-gel')), findsNothing);
      expect(
        find.byKey(const Key('btn-setup-row-remove-type-gel')),
        findsNothing,
      );
      expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);
    });

    // Pair-check matrix: (duration equal / different) x (name blank /
    // same-normalised / different) -> collision + CTA state.
    final cases =
        <({String duration, String name, bool collides, String label})>[
          (duration: '60', name: '', collides: true, label: 'same + blank'),
          (
            duration: '60',
            name: '  класичний МАНІКЮР ',
            collides: true,
            label: 'same + same name (trim / case)',
          ),
          (
            duration: '60',
            name: 'Авторський',
            collides: false,
            label: 'same + different name',
          ),
          (duration: '90', name: '', collides: false, label: 'diff + blank'),
          (
            duration: '90',
            name: 'класичний манікюр',
            collides: false,
            label: 'diff + same name',
          ),
          (
            duration: '90',
            name: 'Авторський',
            collides: false,
            label: 'diff + different name',
          ),
        ];
    for (final c in cases) {
      testWidgets(
        'pair check: duration ${c.label} -> '
        '${c.collides ? 'collision, CTA disabled' : 'no collision, CTA live'}',
        (tester) async {
          final l10n = await pumpWithCopy(tester);
          await setPrice(tester, copy1, '700');
          await setDuration(tester, copy1, c.duration);
          if (c.name.isNotEmpty) await setName(tester, copy1, c.name);

          expect(
            textInRow(copy1, l10n.serviceSetupCopyCollision),
            c.collides ? findsOneWidget : findsNothing,
          );
          // Only the later row of a pair carries the error.
          expect(
            textInRow(classic, l10n.serviceSetupCopyCollision),
            findsNothing,
          );
          expect(saveOnPressed(tester), c.collides ? isNull : isNotNull);
        },
      );
    }

    testWidgets('acceptance 2: a blank-name copy at 60 is blocked; typing a '
        'name clears it and the save sends two items in order, name only '
        'when non-blank', (tester) async {
      final captured = captureSaves();
      final l10n = await pumpWithCopy(tester);
      await setPrice(tester, copy1, '700');
      await setDuration(tester, copy1, '60');
      expect(saveOnPressed(tester), isNull);

      await setName(tester, copy1, '  Масаж спини авторський ');
      expect(textInRow(copy1, l10n.serviceSetupCopyCollision), findsNothing);
      expect(saveOnPressed(tester), isNotNull);

      await tapKey(tester, const Key('btn-setup-save'));
      expect(captured, hasLength(1));
      final items = captured.single;
      expect(items, hasLength(2));
      expect(items[0].serviceTypeId, classic);
      expect(items[0].durationMinutes, 60);
      expect(items[0].price, 500);
      expect(items[0].name, isNull);
      expect(items[1].serviceTypeId, classic);
      expect(items[1].durationMinutes, 60);
      expect(items[1].price, 700);
      expect(items[1].name, 'Масаж спини авторський');
    });

    testWidgets('acceptance 4: «Прибрати» on the copy removes it — one item '
        'of that type in the payload', (tester) async {
      final captured = captureSaves();
      final l10n = await pumpWithCopy(tester);
      await tapKey(tester, const Key('btn-setup-row-remove-$copy1'));

      expect(find.byKey(const Key('setup_row_$copy1')), findsNothing);
      expect(find.byKey(const Key('setup_row_name_$classic')), findsNothing);
      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);

      await tapKey(tester, const Key('btn-setup-save'));
      expect(captured.single, hasLength(1));
      expect(captured.single.single.durationMinutes, 60);
      expect(tester.takeException(), isNull);
    });

    testWidgets('D3: removing the FIRST row promotes the copy (keeps its '
        'values) under the primary keys', (tester) async {
      await pumpWithCopy(tester);
      await setDuration(tester, copy1, '120');
      await tapKey(tester, const Key('btn-setup-row-remove-$classic'));

      expect(find.byKey(const Key('setup_row_$copy1')), findsNothing);
      expect(find.byKey(const Key('setup_row_$classic')), findsOneWidget);
      expect(durationOf(tester, classic), '120');
      expect(tester.takeException(), isNull);
    });

    testWidgets('D2: a copy renamed away from the type name may share an '
        'owned duration; a blank one at it is blocked', (tester) async {
      final l10n = await pumpWithCopy(
        tester,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
          },
          existingServices: ownsClassic, // classic at 60
        ),
      );
      // Primary moved off the owned 60 so only the copy is under test.
      await setDuration(tester, classic, '45');
      await setPrice(tester, copy1, '700');
      await setDuration(tester, copy1, '60');
      expect(textInRow(copy1, l10n.serviceSetupCopyCollision), findsOneWidget);
      expect(saveOnPressed(tester), isNull);

      await setName(tester, copy1, 'Авторський');
      expect(textInRow(copy1, l10n.serviceSetupCopyCollision), findsNothing);
      expect(saveOnPressed(tester), isNotNull);
    });

    String nameOf(WidgetTester tester, String keyId) =>
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(Key('setup_row_name_$keyId')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text ??
        '';

    Iterable<String> wrapperKeyIds(WidgetTester tester) =>
        (tester.state(find.byType(ServiceSetupScreen))
                as ServiceSetupRowKeysProbe)
            .debugRowWrapperKeyIds;

    Future<void> openPencil(WidgetTester tester, String keyId) =>
        tapKey(tester, Key('btn-setup-row-name-$keyId'));

    testWidgets('D4: pencils opened and left pre-filled count as NO name — '
        'no pair collision at different durations, no name sent', (
      tester,
    ) async {
      final captured = captureSaves();
      final l10n = await pumpWithCopy(tester);
      await setDuration(tester, copy1, '90');
      await setPrice(tester, copy1, '700');
      await openPencil(tester, classic);
      expect(nameOf(tester, classic), typeClassic.nameUk);
      await openPencil(tester, copy1);
      expect(nameOf(tester, copy1), typeClassic.nameUk);

      for (final k in <String>[classic, copy1]) {
        expect(textInRow(k, l10n.serviceSetupCopyCollision), findsNothing);
        expect(textInRow(k, l10n.serviceSetupDurationTaken), findsNothing);
      }
      expect(saveOnPressed(tester), isNotNull);
      await tapKey(tester, const Key('btn-setup-save'));

      expect(
        <(String?, int)>[
          for (final i in captured.single) (i.name, i.durationMinutes),
        ],
        <(String?, int)>[(null, 60), (null, 90)],
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('D4: a pre-filled, unchanged copy at the SAME duration '
        'collides exactly like a blank one', (tester) async {
      final l10n = await pumpWithCopy(tester);
      await setDuration(tester, copy1, '60');
      await setPrice(tester, copy1, '700');
      await openPencil(tester, copy1);
      expect(nameOf(tester, copy1), typeClassic.nameUk);
      expect(textInRow(copy1, l10n.serviceSetupCopyCollision), findsOneWidget);
      expect(saveOnPressed(tester), isNull);
    });

    testWidgets('D4: the pre-filled name, edited, is sent as the custom name', (
      tester,
    ) async {
      final captured = captureSaves();
      await pumpWithCopy(tester);
      await setDuration(tester, copy1, '60');
      await setPrice(tester, copy1, '700');
      await openPencil(tester, copy1);
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      await setName(tester, copy1, '${typeClassic.nameUk} люкс');
      await tapKey(tester, const Key('btn-setup-save'));

      expect(
        <(String?, int)>[
          for (final i in captured.single) (i.name, i.durationMinutes),
        ],
        // i18n-finder-ok: user-typed service name fixture, not UI copy
        <(String?, int)>[(null, 60), ('Класичний манікюр люкс', 60)],
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('the copy name field drops characters outside the backend '
        'allow-list (emoji, #) and keeps the allowed punctuation', (
      tester,
    ) async {
      await pumpWithCopy(tester);
      await setName(tester, copy1, 'Масаж #1 \u{1F600} «Люкс» – №2: 50%!');

      expect(nameOf(tester, copy1), 'Масаж 1  «Люкс» – №2: 50%!');
    });

    testWidgets('a 400 on items[0].name marks THAT row\'s name field with the '
        'localized message, not the copy; editing the name clears it', (
      tester,
    ) async {
      when(() => h.repo.bulkCreate(any())).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'items[0].name': 'Invalid name'},
        ),
      );
      final l10n = await pumpWithCopy(tester);
      // D4: the copy starts with an empty duration.
      await setDuration(tester, copy1, '90');
      await setPrice(tester, copy1, '700');
      await setName(tester, classic, 'Авторський');
      await tapKey(tester, const Key('btn-setup-save'));

      expect(
        textInRow(classic, l10n.serviceSetupCopyNameInvalid),
        findsOneWidget,
      );
      expect(textInRow(copy1, l10n.serviceSetupCopyNameInvalid), findsNothing);
      expect(find.text('Invalid name'), findsNothing);

      await setName(tester, classic, 'Авторський 2');
      expect(
        textInRow(classic, l10n.serviceSetupCopyNameInvalid),
        findsNothing,
      );
    });

    testWidgets('«Прибрати» releases the removed row\'s cached wrapper key; '
        'a promoted row releases its old copy key', (tester) async {
      await pumpWithCopy(tester);
      expect(wrapperKeyIds(tester), containsAll(<String>[classic, copy1]));

      await tapKey(tester, const Key('btn-setup-row-remove-$copy1'));
      expect(wrapperKeyIds(tester), contains(classic));
      expect(wrapperKeyIds(tester), isNot(contains(copy1)));

      // Re-added copy reuses index 1; removing the PRIMARY promotes it.
      await tapKey(tester, const Key('btn-setup-row-add-copy-$classic'));
      expect(wrapperKeyIds(tester), contains(copy1));
      await tapKey(tester, const Key('btn-setup-row-remove-$classic'));
      expect(wrapperKeyIds(tester), contains(classic));
      expect(wrapperKeyIds(tester), isNot(contains(copy1)));
      expect(find.byKey(const Key('setup_row_$classic')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('409 reconcile is on (type, duration, type name): a renamed '
        'copy at a newly-owned duration stays selected', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());
      final servicesList = MutatingServicesList(<List<MasterService>>[
        const <MasterService>[],
        ownsClassic, // classic at 60 appears after the 409
      ]);
      final l10n = await pumpWithCopy(
        tester,
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
      await setPrice(tester, copy1, '700');
      await setDuration(tester, copy1, '60');
      await setName(tester, copy1, 'Авторський');
      expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);

      await tapKey(tester, const Key('btn-setup-save'));

      // The primary (type name, 60) is the duplicate and goes off; the
      // renamed copy at 60 is a distinct service and stays included.
      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      expect(
        textInRow(classic, l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
      );
      expect(textInRow(copy1, l10n.serviceSetupRowAlreadyInMenu), findsNothing);
    });

    testWidgets('409 reconcile matches the canonical NAME too: a NAME '
        'collision (same type + duration, same trimmed / lower-cased name) '
        'switches off the renamed copy and leaves the type-name primary', (
      tester,
    ) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());
      const authored = <MasterService>[
        MasterService(
          id: 'svc-owned-authored',
          serviceDefId: 'def-owned-authored',
          name: 'Авторський',
          serviceTypeId: classic,
          serviceTypeNameUk: 'Класичний манікюр',
          durationMinutes: 60,
          priceMin: 700,
          priceDisplay: '700 ₴',
        ),
      ];
      final servicesList = MutatingServicesList(<List<MasterService>>[
        const <MasterService>[],
        authored, // «Авторський» at 60 appears after the 409
      ]);
      final l10n = await pumpWithCopy(
        tester,
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
      await setPrice(tester, copy1, '700');
      await setDuration(tester, copy1, '60');
      await setName(tester, copy1, '  авторський ');
      expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);

      await tapKey(tester, const Key('btn-setup-save'));

      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      expect(
        textInRow(copy1, l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
        reason: 'the renamed copy is the one the 409 was about',
      );
      expect(
        textInRow(classic, l10n.serviceSetupRowAlreadyInMenu),
        findsNothing,
        reason: 'the type-name primary at 60 differs by name — not a duplicate',
      );
    });

    int pairCheckRuns(WidgetTester tester) =>
        (tester.state(find.byType(ServiceSetupScreen))
                as ServiceSetupRowKeysProbe)
            .debugPairCheckRuns;

    testWidgets('pair check runs once per real edit: caret / selection moves '
        'never re-run it, a rename runs it exactly once', (tester) async {
      await pumpWithCopy(tester);
      await setName(tester, copy1, 'Авторський');

      final Finder nameField = find.descendant(
        of: find.byKey(const Key('setup_row_name_$copy1')),
        matching: find.byType(TextField),
      );
      final Finder durationField = find.descendant(
        of: inRow(copy1, const Key('service-setup-duration')),
        matching: find.byType(TextField),
      );
      final TextEditingController name = tester
          .widget<TextField>(nameField)
          .controller!;
      final TextEditingController duration = tester
          .widget<TextField>(durationField)
          .controller!;

      final int before = pairCheckRuns(tester);
      name.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      name.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      duration.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(
        pairCheckRuns(tester),
        before,
        reason: 'selection-only notifications must not re-run the pair check',
      );

      await setName(tester, copy1, 'Авторський 2');
      expect(
        pairCheckRuns(tester),
        before + 1,
        reason:
            'one rename = one pair check (no screen-listener + onChanged '
            'double trigger)',
      );

      await setDuration(tester, copy1, '45');
      expect(pairCheckRuns(tester), before + 2);
    });

    testWidgets('toggling an owned type ON runs the pair check ONCE and '
        '(phase 472) leaves its duration empty', (tester) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 2000),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
          },
          existingServices: ownsClassic,
        ),
      );
      await expand(tester, 'MANICURE');

      final int before = pairCheckRuns(tester);
      await toggleRowOn(tester, classic);

      expect(
        durationOf(tester, classic),
        isEmpty,
        reason: 'phase 472: no duration autofill on an owned row',
      );
      expect(
        pairCheckRuns(tester),
        before + 1,
        reason: 'one toggle = one pair check',
      );
    });

    testWidgets('409 reconcile canonicalises the name like backend 464: a '
        'renamed copy differing only by internal space runs / case is '
        'switched off', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());
      const authored = <MasterService>[
        MasterService(
          id: 'svc-owned-authored',
          serviceDefId: 'def-owned-authored',
          name: 'Авторський манікюр',
          serviceTypeId: classic,
          serviceTypeNameUk: 'Класичний манікюр',
          durationMinutes: 60,
          priceMin: 700,
          priceDisplay: '700 ₴',
        ),
      ];
      final servicesList = MutatingServicesList(<List<MasterService>>[
        const <MasterService>[],
        authored,
      ]);
      final l10n = await pumpWithCopy(
        tester,
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
      await setPrice(tester, copy1, '700');
      await setDuration(tester, copy1, '60');
      await setName(tester, copy1, ' авторський   МАНІКЮР ');

      await tapKey(tester, const Key('btn-setup-save'));

      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      expect(
        textInRow(copy1, l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
        reason: 'the space-run variant is the same canonical name',
      );
      expect(
        textInRow(classic, l10n.serviceSetupRowAlreadyInMenu),
        findsNothing,
      );
    });

    testWidgets('409 reconcile: an owned copy with a blank name AND no '
        'serviceTypeNameUk falls back to the catalogue type name, like the '
        'row does', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());
      const unnamed = <MasterService>[
        MasterService(
          id: 'svc-owned-unnamed',
          serviceDefId: 'def-owned-unnamed',
          name: '',
          serviceTypeId: classic,
          durationMinutes: 60,
          priceMin: 500,
          priceDisplay: '500 ₴',
        ),
      ];
      final servicesList = MutatingServicesList(<List<MasterService>>[
        const <MasterService>[],
        unnamed,
      ]);
      final l10n = await pumpWithCopy(
        tester,
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
      // D4: the copy starts with an empty duration.
      await setDuration(tester, copy1, '90');
      await setPrice(tester, copy1, '700');

      await tapKey(tester, const Key('btn-setup-save'));

      expect(
        textInRow(classic, l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
        reason: 'type-name primary at 60 = the unnamed owned copy at 60',
      );
      expect(
        textInRow(copy1, l10n.serviceSetupRowAlreadyInMenu),
        findsNothing,
        reason: 'the copy at 90 is a different duration',
      );
    });
  });
}
