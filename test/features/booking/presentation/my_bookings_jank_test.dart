// Phase 076 (10.2 jank audit) — pinning tests for finding #4 (My Bookings
// rebuilds every mounted card on an `isLoadingMore` flip) and #5 (the
// BookingCard press `setState` rebuilt the whole card).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking(int i) {
  final DateTime start = futureBookingStart().add(Duration(days: i));
  return Booking(
    id: 'b$i',
    masterId: 'master-$i',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 'service-$i',
    serviceName: 'Манікюр $i',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: 60,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: BookingStatus.confirmed,
    canReview: false,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
  );
}

PageResponse<Booking> _page(List<Booking> items, {int totalPages = 1}) =>
    PageResponse<Booking>(
      items: items,
      page: 0,
      totalPages: totalPages,
      totalElements: items.length,
    );

void _stub(_MockBookingRepository repo, PageResponse<Booking> upcoming) {
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.upcoming.statuses,
      partition: BookingPartition.upcoming,
      sort: BookingSort.oldest,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => upcoming);
  for (final (BookingTab tab, BookingPartition part)
      in <(BookingTab, BookingPartition)>[
        (BookingTab.past, BookingPartition.past),
        (BookingTab.cancelled, BookingPartition.cancelled),
      ]) {
    when(
      () => repo.getMyBookings(
        statuses: tab.statuses,
        partition: part,
        sort: BookingSort.newest,
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => _page(const <Booking>[]));
  }
}

Future<void> _pump(WidgetTester tester, _MockBookingRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object?>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: <Locale>[Locale('uk'), Locale('en')],
        locale: Locale('uk'),
        home: MyBookingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('#4 — an isLoadingMore flip rebuilds no mounted BookingCard', (
    tester,
  ) async {
    final repo = _MockBookingRepository();
    _stub(
      repo,
      _page(<Booking>[for (int i = 0; i < 8; i++) _booking(i)], totalPages: 2),
    );
    final Completer<PageResponse<Booking>> next =
        Completer<PageResponse<Booking>>();
    when(
      () => repo.getMyBookings(
        statuses: BookingTab.upcoming.statuses,
        partition: BookingPartition.upcoming,
        sort: BookingSort.oldest,
        page: 1,
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) => next.future);
    await _pump(tester, repo);
    expect(find.byType(BookingCard), findsWidgets);

    int cardBuilds = 0;
    int badgeBuilds = 0;
    final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      if (e.widget is BookingCard) cardBuilds++;
      if (e.widget is BookingStatusBadge) badgeBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = old);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MyBookingsScreen)),
    );
    unawaited(
      container
          .read(myBookingsProvider(BookingTab.upcoming).notifier)
          .loadMore(),
    );
    await tester.pump();
    await tester.pump();
    expect(
      container
          .read(myBookingsProvider(BookingTab.upcoming))
          .value
          ?.isLoadingMore,
      isTrue,
      reason: 'the flip must have happened or this pin is vacuous',
    );

    expect(cardBuilds, 0, reason: 'unchanged bookings must not rebuild');
    expect(badgeBuilds, 0);
    next.complete(_page(const <Booking>[]));
    await tester.pumpAndSettle();
  });

  testWidgets('#5 — tap-down + cancel rebuilds no card content, shell reacts', (
    tester,
  ) async {
    final repo = _MockBookingRepository();
    _stub(repo, _page(<Booking>[_booking(0)]));
    await _pump(tester, repo);

    int badgeBuilds = 0;
    final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      if (e.widget is BookingStatusBadge) badgeBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = old);

    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.byType(BookingCard)),
    );
    // fixed-wait-ok: lets the 120-160 ms press/release shell animation run.
    await tester.pump(const Duration(milliseconds: 300));
    final AnimatedScale scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(BookingCard),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 0.985, reason: 'the press shell must still react');
    await g.cancel();
    // fixed-wait-ok: lets the 120-160 ms press/release shell animation run.
    await tester.pump(const Duration(milliseconds: 300));
    expect(badgeBuilds, 0);
  });

  testWidgets(
    'a booking status change re-renders the cached card and its memoised '
    'a11y label',
    (tester) async {
      final repo = _MockBookingRepository();
      PageResponse<Booking> upcoming = _page(<Booking>[_booking(0)]);
      _stub(repo, upcoming);
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          partition: BookingPartition.upcoming,
          sort: BookingSort.oldest,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => upcoming);
      await _pump(tester, repo);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MyBookingsScreen)),
      );
      String labelOf() => tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(BookingCard),
                  matching: find.byWidgetPredicate(
                    (Widget w) => w is Semantics && w.properties.button == true,
                  ),
                )
                .first,
          )
          .properties
          .label!;

      final Booking before = _booking(0);
      final String confirmed = BookingStatusVisual.of(before, l10n).label;
      expect(labelOf(), contains(confirmed));

      final Booking after = before.copyWith(status: BookingStatus.completed);
      final String completed = BookingStatusVisual.of(after, l10n).label;
      expect(completed, isNot(confirmed), reason: 'anti-vacuity');
      upcoming = _page(<Booking>[after]);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MyBookingsScreen)),
      );
      await container
          .read(myBookingsProvider(BookingTab.upcoming).notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(labelOf(), contains(completed));
      expect(labelOf(), isNot(contains(confirmed)));
    },
  );
}
