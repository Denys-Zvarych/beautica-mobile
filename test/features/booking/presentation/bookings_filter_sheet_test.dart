// Phase 7.7 — the «Мої записи» filter sheet (Дата · Статус · Послуга).
//
// Every test here was mutation-verified — the pinned production line was
// broken, the test confirmed RED, the line restored. Mutations are recorded per
// group.
//
// The recurring defect this file is written against: a test that derives its
// expectation from the code under test cannot fail. So every wire string below
// is a LITERAL, never `BookingStatus.wireValue` read back out of the enum.
//
// The scope assertions («Майстер» / «Очікує» must never appear) are STRUCTURAL
// — row keys and row counts — rather than `find.text('Майстер')`. Two reasons,
// and the second is the important one:
//   1. `scripts/forbid_cyrillic_finder.sh` bans a Cyrillic `find.text` outright.
//   2. A `findsNothing` on a UA literal is exactly the shape of test that stops
//      failing the day EN ships: the literal matches nothing because the app is
//      in English, and the assertion passes for the wrong reason. Counting keyed
//      rows cannot decay that way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

MasterService _service(String id, String name) => MasterService(
  id: id,
  serviceDefId: 'def-$id',
  name: name,
  durationMinutes: 60,
);

final List<MasterService> _catalogue = <MasterService>[
  _service('s-1', 'Манікюр з покриттям'),
  _service('s-2', 'Педикюр'),
  _service('s-3', 'Корекція брів'),
];

void main() {
  /// Pumps a routed host that opens the sheet. `context.pop(selection)` needs a
  /// real GoRouter above it.
  Future<void> pumpSheet(
    WidgetTester tester, {
    BookingsFilterSelection initial = const BookingsFilterSelection(),
    List<MasterService> services = const <MasterService>[],
    void Function(BookingsFilterSelection?)? onPopped,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Builder(
              builder: (BuildContext inner) => Center(
                child: ElevatedButton(
                  key: const Key('open-sheet'),
                  onPressed: () async {
                    final BookingsFilterSelection? r =
                        await BookingsFilterSheet.show(
                          inner,
                          initial: initial,
                          services: services,
                        );
                    onPopped?.call(r);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();
  }

  /// The sheet's scrollable body. Rows past the fold are genuinely unbuilt in
  /// a `ListView`, so a `find.text` on one returns 0 matches — scroll first.
  final Finder sheetScrollable = find.descendant(
    of: find.byKey(const Key('master-bookings-filter-sheet')),
    matching: find.byType(Scrollable),
  );

  Future<void> scrollTo(WidgetTester tester, Finder row) =>
      tester.scrollUntilVisible(row, 80, scrollable: sheetScrollable);

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();
  }

  group('scope — what must NEVER be offered', () {
    // MUTATION: added a «Майстер» section (a `_SectionLabel('Майстер')` plus a
    // picker row) → this test failed. Removed again.
    //
    // A single master's own list never offers a teammate filter; there is no
    // `masterId` parameter on `GET /bookings/me` and backend 26.x deliberately
    // did not add one. If someone ports the design's `_MasterFilterSheet` code
    // paths across, this is what stops it.
    testWidgets('renders NO «Майстер» section', (WidgetTester tester) async {
      await pumpSheet(tester, services: _catalogue);

      // Exactly two sections (Дата was retired Phase 7.13 — see
      // `bookings_filter_sheet.dart`'s header), and «Майстер» is not among
      // them.
      for (final String section in <String>['status', 'service']) {
        expect(
          find.byKey(Key('master-bookings-filter-section-$section')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const Key('master-bookings-filter-section-date')),
        findsNothing,
        reason: 'Дата was retired Phase 7.13 — the rail owns the day now',
      );
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'master-bookings-filter-section-',
              ),
        ),
        findsNWidgets(2),
        reason: 'a third section can only be the teammate filter',
      );
      // …and no picker row belongs to a master.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'master-bookings-filter-master-',
              ),
        ),
        findsNothing,
      );
    });

    // MUTATION: added a `pending` member to `BookingStatusFilterGroup` labelled
    // «Очікує» → this test failed. Removed again.
    //
    // PENDING was retired backend-side by track 24.x (booking creation
    // auto-confirms) and the server can no longer emit or accept it. The design
    // preview still shows it; the design is stale on this point and the backend
    // wins.
    //
    // 2026-08-15: also pins the retirement of the «Візит не відбувся» row —
    // NOT_COMPLETED cannot be SET from anywhere in the app (no button, dialog,
    // or menu calls `/not-complete`; see `BookingStatusFilterGroup`'s header),
    // so a filter for it was dead control surface. `BookingStatus.notCompleted`
    // itself is untouched — an already-NOT_COMPLETED booking still renders
    // everywhere; only the independent filter row is gone. See
    // `booking_status_test.dart` and `master_bookings_filter_wiring_test.dart`
    // for the proof that it stays reachable through the unfiltered default and
    // through "every remaining row ticked".
    testWidgets('offers NO «Очікує» and NO «Візит не відбувся» status — '
        'exactly three status rows', (WidgetTester tester) async {
      await pumpSheet(tester, services: _catalogue);

      // The three sanctioned rows, by key, and NOTHING else.
      for (final String g in <String>['confirmed', 'completed', 'cancelled']) {
        expect(
          find.byKey(Key('master-bookings-filter-status-$g')),
          findsOneWidget,
        );
      }
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'master-bookings-filter-status-',
              ),
        ),
        findsNWidgets(3),
      );
      expect(
        find.byKey(const Key('master-bookings-filter-status-pending')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('master-bookings-filter-status-notCompleted')),
        findsNothing,
      );
    });

    // MUTATION: swapped `BookingStatusFilterGroup.values` for a literal list
    // that also emitted a row per `BookingStatus.values` member (i.e. including
    // `unknown`) → this test failed. Restored.
    //
    // `unknown` is a DECODE-only member: `status=UNKNOWN` is a 400, and the
    // backend's `@Size(max = 5)` cap is sized to the five real states exactly.
    testWidgets('never offers BookingStatus.unknown', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, services: _catalogue);

      for (final BookingStatusFilterGroup g
          in BookingStatusFilterGroup.values) {
        expect(
          g.statuses.contains(BookingStatus.unknown),
          isFalse,
          reason: '${g.name} must not carry the decode-only unknown member',
        );
      }
    });
  });

  group('status multi-select', () {
    // MUTATION: changed the `cancelled` group's set to
    // `{BookingStatus.cancelled}` alone → this test failed (declined missing).
    // Restored.
    //
    // DECLINED and CANCELLED both read «Скасовано» app-wide (the who-cancelled
    // distinction was deliberately collapsed), so the single visible row must
    // select BOTH wire statuses — otherwise a master filtering «Скасовано»
    // silently loses every booking the CLIENT cancelled.
    testWidgets('«Скасовано» selects BOTH cancelled and declined', (
      WidgetTester tester,
    ) async {
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-cancelled')),
      );
      await tester.pumpAndSettle();
      await apply(tester);

      expect(out, isNotNull);
      // Wire strings as LITERALS — not `.wireValue` read back off the enum.
      expect(
        out!.statuses.map((BookingStatus s) => s.wireValue).toSet(),
        <String>{'CANCELLED', 'DECLINED'},
      );
    });

    // MUTATION: made `_toggleGroup` REPLACE the draft set instead of adding to
    // it (`_statuses = {...g.statuses}`) → this test failed (one group instead
    // of two). Restored.
    testWidgets('two groups accumulate into one selection', (
      WidgetTester tester,
    ) async {
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-confirmed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await tester.pumpAndSettle();
      await apply(tester);

      expect(
        out!.statuses.map((BookingStatus s) => s.wireValue).toSet(),
        <String>{'CONFIRMED', 'COMPLETED'},
      );
    });

    // MUTATION: made `_toggleGroup` add unconditionally (never remove) → this
    // test failed (selection non-empty). Restored.
    testWidgets('tapping a selected group deselects it', (
      WidgetTester tester,
    ) async {
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        initial: const BookingsFilterSelection(
          statuses: <BookingStatus>{BookingStatus.completed},
        ),
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await tester.pumpAndSettle();
      await apply(tester);

      expect(out!.statuses, isEmpty);
    });

    // MUTATION: none needed for a bound — this is a structural assertion that
    // the three rows cannot exceed the server's 5-status cap. It fails by
    // construction the moment a new INDEPENDENT group pushes the union past 5
    // (a 6th wire status would be a 400).
    //
    // 2026-08-15: the union no longer equals `BookingStatus.filterable` — that
    // was true only while a `notCompleted` group existed. Written as a LITERAL
    // set, per this file's own convention (a re-derivation from the enum would
    // compare the code under test against itself). NOT_COMPLETED staying
    // reachable despite being absent here is proven elsewhere — see
    // `booking_status_test.dart`'s `maximal`-parameter group and
    // `master_bookings_filter_wiring_test.dart`.
    test('selecting every group sends at most the server cap of 5 statuses — '
        'and no longer covers NOT_COMPLETED, by construction', () {
      final Set<BookingStatus> all = <BookingStatus>{
        for (final BookingStatusFilterGroup g
            in BookingStatusFilterGroup.values)
          ...g.statuses,
      };
      expect(all.length, lessThanOrEqualTo(5));
      expect(all, <BookingStatus>{
        BookingStatus.confirmed,
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.declined,
      });
      expect(all, isNot(contains(BookingStatus.notCompleted)));
    });
  });

  group('service multi-select', () {
    // MUTATION: hard-coded the service section to render `_catalogue.first`
    // only → this test failed. Restored.
    testWidgets('rows come from the passed catalogue, keyed by service id', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, services: _catalogue);

      for (final MasterService s in _catalogue) {
        final Finder row = find.byKey(
          Key('master-bookings-filter-service-${s.id}'),
        );
        await scrollTo(tester, row);
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text(s.name)),
          findsOneWidget,
        );
      }
    });

    // MUTATION: changed `_toggleService` to add `s.serviceDefId` instead of
    // `s.id` → this test failed. Restored.
    //
    // Backend 26.4 filters on `masterService.id`, NOT the service-definition
    // id. Sending the wrong one returns an EMPTY page with a 200 — a silently
    // wrong filter with no error anywhere.
    testWidgets('selected ids are MasterService.id, not serviceDefId', (
      WidgetTester tester,
    ) async {
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        services: _catalogue,
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      for (final String id in <String>['s-1', 's-3']) {
        final Finder row = find.byKey(
          Key('master-bookings-filter-service-$id'),
        );
        await scrollTo(tester, row);
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      await apply(tester);

      expect(out!.serviceIds, <String>{'s-1', 's-3'});
      expect(out!.serviceIds, isNot(contains('def-s-1')));
    });

    // MUTATION: hid the section unconditionally (`if (false) ...`) → the first
    // expectation failed. Then made it render unconditionally → the empty-list
    // expectation failed. Restored.
    testWidgets('the section is omitted entirely when the catalogue is empty', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, services: const <MasterService>[]);
      expect(
        find.byKey(const Key('master-bookings-filter-section-service')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
      await tester.pumpAndSettle();

      await pumpSheet(tester, services: _catalogue);
      expect(
        find.byKey(const Key('master-bookings-filter-section-service')),
        findsOneWidget,
      );
      // …and the rows behind it really are there once scrolled to.
      await scrollTo(
        tester,
        find.byKey(const Key('master-bookings-filter-service-s-3')),
      );
      expect(
        find.byKey(const Key('master-bookings-filter-service-s-3')),
        findsOneWidget,
      );
    });

    // MUTATION: dropped the `_serviceIds.length < kMaxServiceFilterIds` guard
    // from `_toggleService` → this test failed (51 ids selected). Restored.
    //
    // Backend 26.4 answers >50 `serviceId` values with a 400. Preventing the
    // 51st tap is why there is no error copy for this case anywhere.
    testWidgets('cannot select more than the server cap of 50 services', (
      WidgetTester tester,
    ) async {
      final List<MasterService> many = <MasterService>[
        for (int i = 0; i < 60; i++) _service('s$i', 'Послуга $i'),
      ];
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        services: many,
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      final Finder sheetList = find.descendant(
        of: find.byKey(const Key('master-bookings-filter-sheet')),
        matching: find.byType(Scrollable),
      );
      for (int i = 0; i < 55; i++) {
        final Finder row = find.byKey(
          Key('master-bookings-filter-service-s$i'),
        );
        await tester.scrollUntilVisible(row, 80, scrollable: sheetList);
        await tester.tap(row);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await apply(tester);

      expect(out!.serviceIds.length, kMaxServiceFilterIds);
      expect(kMaxServiceFilterIds, 50);
    });
  });

  group('draft semantics — nothing escapes before «Застосувати»', () {
    // MUTATION: made every `_PickerRow.onToggle` also call `_apply()` (the
    // live-apply-per-tap design this sheet deliberately rejects) → this test
    // failed (the sheet closed on the first tap and `out` was non-null after
    // one toggle). Restored.
    //
    // Live-applying costs one page-0 fetch PER CHECKBOX. Five taps to build one
    // filter is five requests, four of them for a filter the master never asked
    // to see.
    testWidgets('toggles resolve NOTHING until apply is tapped', (
      WidgetTester tester,
    ) async {
      int pops = 0;
      await pumpSheet(
        tester,
        services: _catalogue,
        onPopped: (BookingsFilterSelection? _) => pops++,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-confirmed')),
      );
      await tester.pumpAndSettle();
      final Finder svc = find.byKey(
        const Key('master-bookings-filter-service-s-2'),
      );
      await scrollTo(tester, svc);
      await tester.tap(svc);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await tester.pumpAndSettle();

      expect(pops, 0, reason: 'the sheet must still be open');
      expect(
        find.byKey(const Key('master-bookings-filter-sheet')),
        findsOneWidget,
      );

      await apply(tester);
      expect(pops, 1, reason: 'exactly ONE resolution for the whole session');
    });

    // MUTATION: made `_resetAll` clear only `_statuses` → this test failed on
    // the serviceIds expectation. Restored.
    testWidgets('«Скинути фільтри» clears every section of the draft', (
      WidgetTester tester,
    ) async {
      BookingsFilterSelection? out;
      await pumpSheet(
        tester,
        services: _catalogue,
        initial: const BookingsFilterSelection(
          statuses: <BookingStatus>{BookingStatus.confirmed},
          serviceIds: <String>{'s-1'},
        ),
        onPopped: (BookingsFilterSelection? s) => out = s,
      );

      await tester.tap(find.byKey(const Key('master-bookings-filter-reset')));
      await tester.pumpAndSettle();
      await apply(tester);

      expect(out!.statuses, isEmpty);
      expect(out!.serviceIds, isEmpty);
      expect(out!.activeCount, 0);
    });

    // MUTATION: rendered the reset link unconditionally → this test failed.
    // Restored.
    testWidgets('the reset link is absent when nothing is active', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, services: _catalogue);
      expect(
        find.byKey(const Key('master-bookings-filter-reset')),
        findsNothing,
      );
    });
  });

  group('BookingsFilterSelection.activeCount', () {
    // MUTATION: changed `activeCount` to count VALUES
    // (`statuses.length + serviceIds.length`) → the multi-value case failed (4
    // instead of 1). Restored.
    //
    // The badge counts DECISIONS, not values: picking three statuses is one
    // active filter, however many wire values it maps to.
    test('counts filter GROUPS, not selected values', () {
      expect(const BookingsFilterSelection().activeCount, 0);

      expect(
        const BookingsFilterSelection(
          statuses: <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
            BookingStatus.cancelled,
            BookingStatus.declined,
          },
        ).activeCount,
        1,
      );

      expect(
        const BookingsFilterSelection(
          statuses: <BookingStatus>{BookingStatus.confirmed},
          serviceIds: <String>{'a', 'b', 'c'},
        ).activeCount,
        2,
      );
    });
  });

  group('BookingsFilterButton', () {
    Future<void> pumpButton(WidgetTester tester, int count) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: Center(
              child: BookingsFilterButton(activeCount: count, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // MUTATION: rendered the badge unconditionally (dropped `if (active)`) →
    // the zero case failed. Then hard-coded `active = false` → the two/three
    // cases failed. Restored.
    testWidgets('the badge appears only when filters are active', (
      WidgetTester tester,
    ) async {
      await pumpButton(tester, 0);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
      );

      await pumpButton(tester, 2);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);

      await pumpButton(tester, 3);
      expect(find.text('3'), findsOneWidget);
    });

    // MUTATION: dropped the `value:` from the button's Semantics → this test
    // failed. Restored. The badge is a visual-only cue; a screen-reader user
    // otherwise gets no signal that the list is filtered at all.
    testWidgets('announces the active count to a screen reader', (
      WidgetTester tester,
    ) async {
      await pumpButton(tester, 2);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('master-bookings-filter-button'))),
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('master-bookings-filter-button')),
            )
            .value,
        l10n.bookingFilterActiveCount(2),
      );

      await pumpButton(tester, 0);
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('master-bookings-filter-button')),
            )
            .value,
        isEmpty,
      );
    });
  });
}
