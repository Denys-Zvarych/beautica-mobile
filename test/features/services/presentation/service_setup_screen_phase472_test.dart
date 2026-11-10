// [ServiceSetupScreen] widget tests:
// phase 472 — add-copy jump + name pencil on every card.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
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

  // ── Phase 472 — «+ додати ще» jump + owned-service rename ─────────────────
  group('phase 472 — add-copy jump + a name pencil on every card (D3)', () {
    const String classic = 'type-classic';
    const String copy1 = 'type-classic_copy_1';

    Finder inRow(String keyId, Key key) => find.descendant(
      of: find.byKey(Key('setup_row_$keyId')),
      matching: find.byKey(key),
    );

    TextField durationField(WidgetTester tester, String keyId) =>
        tester.widget<TextField>(
          find.descendant(
            of: inRow(keyId, const Key('service-setup-duration')),
            matching: find.byType(TextField),
          ),
        );

    Future<void> tapKey(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    List<Object> ownedOverrides(List<MasterService> existing) => h.overrides(
      categories: const AsyncData(<ServiceCategoryOption>[manicure]),
      typesBySlug: <String, List<ServiceTypeOption>>{
        'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
      },
      existingServices: existing,
    );

    testWidgets('«+ додати ще» shows the new label, scrolls the new copy card '
        'fully into view and focuses its duration well', (tester) async {
      // A short viewport, so the copy lands below the fold without the jump.
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 640),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
          },
        ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, classic);
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      const Key add = Key('btn-setup-row-add-copy-$classic');
      expect(
        find.descendant(
          of: find.byKey(add),
          matching: find.text(l10n.serviceSetupAddCopy),
        ),
        findsOneWidget,
      );
      await tapKey(tester, add);

      final Rect card = tester.getRect(
        find.byKey(const Key('setup_row_$copy1')),
      );
      final Rect viewport = tester.getRect(find.byType(CustomScrollView));
      expect(card.top, greaterThanOrEqualTo(viewport.top));
      expect(
        card.bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: 'the whole new copy card is on screen after the jump',
      );
      expect(
        durationField(tester, copy1).focusNode?.hasFocus,
        isTrue,
        reason: 'focus moves into the new copy duration well',
      );
      expect(durationField(tester, classic).focusNode?.hasFocus, isFalse);
    });

    const List<MasterService> ownsGelTwice = <MasterService>[
      MasterService(
        id: 'svc-gel-1',
        serviceDefId: 'def-gel-1',
        name: 'Гель-лак',
        serviceTypeId: 'type-gel',
        durationMinutes: 60,
        priceMin: 500,
        priceDisplay: '500 ₴',
      ),
      MasterService(
        id: 'svc-gel-2',
        serviceDefId: 'def-gel-2',
        name: 'Гель-лак',
        serviceTypeId: 'type-gel',
        durationMinutes: 90,
        priceMin: 600,
        priceDisplay: '600 ₴',
      ),
    ];

    testWidgets('D3: every switched-on card shows its name pencil — an owned '
        'card (no list of its existing services), a not-owned card and a '
        '«+ додати ще» copy card; none while switched off', (tester) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: ownedOverrides(ownsGelTwice),
      );
      await expand(tester, 'MANICURE');
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(
        find.byKey(const Key('btn-setup-row-name-type-gel')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('btn-setup-row-name-$classic')),
        findsNothing,
      );

      await toggleRowOn(tester, 'type-gel');
      await toggleRowOn(tester, classic);
      expect(
        inRow('type-gel', const Key('btn-setup-row-name-type-gel')),
        findsOneWidget,
        reason: 'D3: an owned card has the pencil too',
      );
      expect(
        inRow(classic, const Key('btn-setup-row-name-$classic')),
        findsOneWidget,
      );
      // The owned card keeps only its «Вже додано» label — none of the
      // master's existing services (or their pencils) is listed inside it.
      expect(
        find.descendant(
          of: find.byKey(const Key('setup_row_type-gel')),
          matching: find.text(l10n.serviceSetupRowAlreadyAdded),
        ),
        findsOneWidget,
      );
      for (final MasterService s in ownsGelTwice) {
        expect(find.byKey(Key('setup_row_owned_${s.id}')), findsNothing);
        expect(find.byKey(Key('btn-setup-row-rename-${s.id}')), findsNothing);
        expect(find.byKey(Key('setup_row_rename_${s.id}')), findsNothing);
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('setup_row_type-gel')),
          matching: find.text(
            '${ownsGelTwice.last.durationMinutes} '
            '${l10n.serviceSetupDurationSuffix}',
          ),
        ),
        findsNothing,
      );

      await tapKey(tester, const Key('btn-setup-row-add-copy-type-gel'));
      expect(
        inRow(
          'type-gel_copy_1',
          const Key('btn-setup-row-name-type-gel_copy_1'),
        ),
        findsOneWidget,
        reason: 'a «+ додати ще» copy card shows its own pencil',
      );
      expect(
        find.byKey(const Key('setup_row_name_type-gel_copy_1')),
        findsNothing,
        reason: 'the copy name well opens from its pencil',
      );
    });

    testWidgets('D3: the pencils of an owned card and its copy card each open '
        'that card\'s name well; each name is sent with its own bulk item, '
        'and no existing service is renamed', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => createdService);
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 2400),
        overrides: ownedOverrides(ownsGelTwice),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, 'type-gel');

      await tapKey(tester, const Key('btn-setup-row-name-type-gel'));
      final Finder ownedWell = find.descendant(
        of: find.byKey(const Key('setup_row_name_type-gel')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(ownedWell).focusNode?.hasFocus, isTrue);
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      await tester.enterText(ownedWell, 'Гель-лак міцний');
      await tester.enterText(
        inRow('type-gel', const Key('service-setup-duration')),
        '60',
      );
      await tester.enterText(
        inRow('type-gel', const Key('pricing-fixed-amount')),
        '500',
      );
      await tester.pumpAndSettle();

      await tapKey(tester, const Key('btn-setup-row-add-copy-type-gel'));
      await tapKey(tester, const Key('btn-setup-row-name-type-gel_copy_1'));
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('setup_row_name_type-gel_copy_1')),
          matching: find.byType(TextField),
        ),
        'Гель-лак експрес',
      );
      await tester.enterText(
        inRow('type-gel_copy_1', const Key('service-setup-duration')),
        '45',
      );
      await tester.enterText(
        inRow('type-gel_copy_1', const Key('pricing-fixed-amount')),
        '400',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, const Key('btn-setup-save'));

      final captured = verify(() => h.repo.bulkCreate(captureAny())).captured;
      final items = captured.single as List<MasterServiceBulkItem>;
      expect(
        <(String?, int)>[for (final i in items) (i.name, i.durationMinutes)],
        <(String?, int)>[('Гель-лак міцний', 60), ('Гель-лак експрес', 45)],
      );
      verifyNever(
        () => h.repo.update(
          any(),
          any(),
          assignmentId: any(named: 'assignmentId'),
        ),
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('D3: the pencil on a switched-on not-owned card reveals its '
        'name well (focused); the typed name is sent with the add', (
      tester,
    ) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => createdService);
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: ownedOverrides(const <MasterService>[]),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, classic);
      await tapKey(tester, const Key('btn-setup-row-name-$classic'));

      final Finder well = find.descendant(
        of: find.byKey(const Key('setup_row_name_$classic')),
        matching: find.byType(TextField),
      );
      expect(well, findsOneWidget);
      expect(tester.widget<TextField>(well).focusNode?.hasFocus, isTrue);
      expect(
        find.byKey(const Key('btn-setup-row-name-$classic')),
        findsNothing,
        reason: 'the pencil gives way to the well it opened',
      );

      // i18n-finder-ok: user-typed service name fixture, not UI copy
      await tester.enterText(well, 'Авторський манікюр');
      await tester.enterText(
        inRow(classic, const Key('service-setup-duration')),
        '60',
      );
      await tester.enterText(
        inRow(classic, const Key('pricing-fixed-amount')),
        '500',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      final captured = verify(() => h.repo.bulkCreate(captureAny())).captured;
      final items = captured.single as List<MasterServiceBulkItem>;
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(items.single.name, 'Авторський манікюр');
      await pumpPastVelvetSnack(tester);
    });

    testWidgets(
      'A1: «+ додати ще» tapped while the source price well has focus '
      'still jumps into the new copy (the source pricing is not rebuilt)',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: ownedOverrides(const <MasterService>[]),
        );
        await expand(tester, 'MANICURE');
        await toggleRowOn(tester, classic);
        final Finder price = find.descendant(
          of: inRow(classic, const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        );
        await tester.tap(price);
        await tester.pumpAndSettle();
        final FocusNode? priceFocus = tester.widget<TextField>(price).focusNode;
        expect(priceFocus?.hasFocus, isTrue);

        await tapKey(tester, const Key('btn-setup-row-add-copy-$classic'));

        expect(
          tester.widget<TextField>(price).focusNode,
          same(priceFocus),
          reason: 'the add keeps the source card\'s pricing wells',
        );
        expect(durationField(tester, copy1).focusNode?.hasFocus, isTrue);
      },
    );

    testWidgets('a user drag stops the «+ додати ще» reveal loop — the list '
        'stays where the master dragged it', (tester) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 640),
        overrides: ownedOverrides(const <MasterService>[]),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, classic);
      const Key add = Key('btn-setup-row-add-copy-$classic');
      await tester.ensureVisible(find.byKey(add));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(add));
      await tester.pump(); // insert + post-frame reveal starts
      // fixed-wait-ok: lands mid-way through the 140 ms reveal animation, so
      // the drag below interrupts a running pass (the case under test).
      await tester.pump(const Duration(milliseconds: 40));
      final Rect viewport = tester.getRect(find.byType(CustomScrollView));
      // Drag the content DOWN (toward the top of the list).
      await tester.dragFrom(
        Offset(viewport.center.dx, viewport.top + 40),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();

      final ScrollPosition position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(
        position.pixels,
        moreOrLessEquals(position.minScrollExtent),
        reason: 'no further reveal pass scrolled the list back down',
      );
    });
  });
}
