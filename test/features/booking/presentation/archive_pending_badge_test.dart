// Phase 395 (24.7c) — the red pending-actions badge on the «Записи» «Архів»
// icon: the shared header's rendering contract and the per-role scope picked
// by `MasterBookingsScreen`.
//
// Layer: Widget (real BookingsDiscoveryView + real providers, mocked repo).
// The salon board's twin lives in `salon_bookings_screen_test.dart`.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);
  final AuthSession _session;
  @override
  Future<AuthSession> build() async => _session;
}

User _user(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Олена',
  lastName: 'Тест',
);

const Key _kBadge = Key('master-bookings-archive-badge');
const Key _kArchive = Key('master-bookings-open-archive');

void main() {
  setUpAll(() {
    registerFallbackValue(const PendingActionsScope.me(asMaster: false));
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        partition: any(named: 'partition'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer(
      (_) async => const PageResponse<Booking>(
        items: <Booking>[],
        page: 0,
        totalPages: 1,
        totalElements: 0,
      ),
    );
  });

  List<Object> overrides() => <Object>[
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    bookingRepositoryProvider.overrideWithValue(repo),
    bookedDaysProvider.overrideWith((ref) async => const <DateTime>{}),
    ownerMasterBookedDaysProvider.overrideWith(
      (ref) async => const <DateTime>{},
    ),
    masterServiceCatalogProvider.overrideWith(
      (ref) async => const <MasterService>[],
    ),
  ];

  Finder badgeText(String text) =>
      find.descendant(of: find.byKey(_kBadge), matching: find.text(text));

  group('BookingsDiscoveryView.archiveBadgeCount', () {
    Future<void> pumpView(WidgetTester tester, {int? count}) async {
      await tester.pumpApp(
        BookingsDiscoveryView(
          query: BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
          title: 'T',
          onBookingTap: (Booking _) {},
          onOpenArchive: () {},
          archiveBadgeCount: count,
        ),
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
    }

    for (final int? hidden in <int?>[null, 0]) {
      testWidgets('$hidden renders no badge', (tester) async {
        await pumpView(tester, count: hidden);
        expect(find.byKey(_kArchive), findsOneWidget);
        expect(find.byKey(_kBadge), findsNothing);
      });
    }

    testWidgets('5 shows «5» and the semantics label announces it', (
      tester,
    ) async {
      await pumpView(tester, count: 5);
      expect(badgeText('5'), findsOneWidget);
      final BuildContext ctx = tester.element(find.byKey(_kArchive));
      expect(
        find.bySemanticsLabel(
          AppLocalizations.of(ctx).masterArchiveOpenSemanticsPending(5),
        ),
        findsOneWidget,
      );
    });

    testWidgets('120 caps at «99+»', (tester) async {
      await pumpView(tester, count: 120);
      expect(badgeText('99+'), findsOneWidget);
    });

    testWidgets('without a count the label stays the plain one', (
      tester,
    ) async {
      await pumpView(tester);
      final BuildContext ctx = tester.element(find.byKey(_kArchive));
      expect(
        find.bySemanticsLabel(
          AppLocalizations.of(ctx).masterArchiveOpenSemantics,
        ),
        findsOneWidget,
      );
    });
  });

  group('MasterBookingsScreen scope', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      UserRole role, {
      bool asOwnerMaster = false,
    }) async {
      await tester.pumpRoutedApp(
        GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext c, GoRouterState s) =>
                  MasterBookingsScreen(asOwnerMaster: asOwnerMaster),
            ),
          ],
        ),
        overrides: <Object>[
          ...overrides(),
          authProvider.overrideWith(
            () => _StubAuth(
              AuthSession.authenticated(user: _user(role), accessToken: 't'),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
    }

    void stubCount(int n) => when(
      () => repo.getPendingActionsCount(
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => n);

    testWidgets('INDEPENDENT_MASTER asks .me(asMaster: false) and shows it', (
      tester,
    ) async {
      stubCount(2);
      await pumpScreen(tester, UserRole.independentMaster);
      verify(
        () => repo.getPendingActionsCount(
          const PendingActionsScope.me(asMaster: false),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(badgeText('2'), findsOneWidget);
    });

    testWidgets('asOwnerMaster asks .me(asMaster: true)', (tester) async {
      stubCount(1);
      await pumpScreen(tester, UserRole.salonOwner, asOwnerMaster: true);
      verify(
        () => repo.getPendingActionsCount(
          const PendingActionsScope.me(asMaster: true),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(badgeText('1'), findsOneWidget);
    });

    // FALSIFY: dropping the `bookingTransitionsEnabledProvider` gate makes
    // this go red (the 403 endpoint gets called and a badge renders).
    testWidgets('SALON_MASTER: repository never called, no badge', (
      tester,
    ) async {
      stubCount(7);
      await pumpScreen(tester, UserRole.salonMaster);
      verifyNever(
        () => repo.getPendingActionsCount(
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      expect(find.byKey(_kArchive), findsOneWidget);
      expect(find.byKey(_kBadge), findsNothing);
    });

    // FALSIFY: watching the whole AsyncValue (no `.select`) makes the
    // loading/data transitions rebuild the screen -> counter > 0.
    testWidgets('an invalidate returning the SAME count does not rebuild the '
        'screen', (tester) async {
      stubCount(2);
      await pumpScreen(tester, UserRole.independentMaster);
      expect(badgeText('2'), findsOneWidget);

      int rebuilds = 0;
      final void Function(Element, bool)? prev = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool first) {
        if (e.widget is MasterBookingsScreen) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = prev);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      container.invalidate(pendingBookingActionsCountProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      verify(
        () => repo.getPendingActionsCount(
          const PendingActionsScope.me(asMaster: false),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2);
      expect(badgeText('2'), findsOneWidget);
      expect(rebuilds, 0);
    });

    // FALSIFY: gating on `bookingTransitionsEnabledProvider` (true for
    // SALON_ADMIN) makes the repo get called -> red.
    for (final (UserRole role, bool own) in <(UserRole, bool)>[
      (UserRole.salonAdmin, false),
      (UserRole.salonAdmin, true),
      (UserRole.salonOwner, false),
    ]) {
      testWidgets('$role (asOwnerMaster: $own): no badge, no request', (
        tester,
      ) async {
        stubCount(7);
        await pumpScreen(tester, role, asOwnerMaster: own);
        verifyNever(
          () => repo.getPendingActionsCount(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        expect(find.byKey(_kBadge), findsNothing);
      });
    }

    // FALSIFY: dropping the `.then(invalidate...)` on the archive push leaves
    // the stale «2» on screen after the pop -> this goes red. The archive
    // screen is a stub here, so ONLY the return-path invalidation can refresh.
    testWidgets('returning from the archive refetches the count and clears '
        'the badge', (tester) async {
      int server = 2;
      when(
        () => repo.getPendingActionsCount(
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => server);

      await tester.pumpRoutedApp(
        GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext c, GoRouterState s) =>
                  const MasterBookingsScreen(),
            ),
            GoRoute(
              path: RouteNames.masterBookingsArchive,
              builder: (BuildContext c, GoRouterState s) => Scaffold(
                body: TextButton(
                  key: const Key('stub-archive-back'),
                  onPressed: () => c.pop(),
                  child: const SizedBox(width: 48, height: 48),
                ),
              ),
            ),
          ],
        ),
        overrides: <Object>[
          ...overrides(),
          authProvider.overrideWith(
            () => _StubAuth(
              AuthSession.authenticated(
                user: _user(UserRole.independentMaster),
                accessToken: 't',
              ),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(badgeText('2'), findsOneWidget);

      await tester.tap(find.byKey(_kArchive));
      await tester.pumpAndSettle();
      server = 0; // everything was closed/rated "inside" the archive
      await tester.tap(find.byKey(const Key('stub-archive-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(_kBadge), findsNothing);
    });

    testWidgets('a failed count shows no badge', (tester) async {
      when(
        () => repo.getPendingActionsCount(
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => throw Exception('boom'));
      await pumpScreen(tester, UserRole.independentMaster);
      expect(find.byKey(_kBadge), findsNothing);
    });
  });
}
