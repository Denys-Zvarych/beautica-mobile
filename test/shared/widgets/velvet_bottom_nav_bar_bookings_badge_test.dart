// 2026-11-05 — master nav «Записи» (tile 1) red pending-actions badge.
//
// Real `pendingBookingActionsCountProvider` over a mocktail
// `BookingRepository` (only `getPendingActionsCount` is stubbed), so every
// test can count the requests the bar issues.
//
// Coverage:
//   • INDEPENDENT_MASTER → `.me(asMaster: false)` count on tile 1, hidden at 0;
//   • owner master mode (SALON_OWNER + `bookingsBadgeAsOwnerMaster`) →
//     `.me(asMaster: true)`;
//   • SALON_MASTER / SALON_OWNER without the owner flag / `showBookingsBadge`
//     off → no badge AND no request (`verifyNever`);
//   • 120 caps at «99+»; semantics hint carries the count;
//   • tab switch bookings → services → schedule → profile issues ONE request
//     (perf suggestion);
//   • the archive-action invalidation entry point refreshes the nav badge.
//
// `pendingActionsScopeForRole` unit tests live in
// test/features/booking/application/pending_booking_actions_count_test.dart.
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

const Key _badge = Key('master-nav-bookings-badge');
const Key _bookingsTile = Key('master-nav-tile-1');
const Key _invalidateButton = Key('test-invalidate-pending-actions');

const PendingActionsScope _meScope = PendingActionsScope.me(asMaster: false);
const PendingActionsScope _ownerScope = PendingActionsScope.me(asMaster: true);

/// Shared expected copy — the UK ARB value, never a re-typed literal.
final AppLocalizations _uk = lookupAppLocalizations(const Locale('uk'));

void main() {
  late _MockBookingRepository repo;
  late int count;

  setUpAll(() {
    registerFallbackValue(_meScope);
  });

  setUp(() {
    repo = _MockBookingRepository();
    count = 3;
    when(
      () => repo.getPendingActionsCount(
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => count);
  });

  List<Object> overridesFor(UserRole role) => <Object>[
    authProvider.overrideWith(() => FixedRoleAuth(role)),
    bookingRepositoryProvider.overrideWithValue(repo),
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    UserRole role = UserRole.independentMaster,
    bool showBookingsBadge = true,
    bool asOwnerMaster = false,
    int activeIndex = 3,
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) =>
              ElevatedButton(
                key: _invalidateButton,
                onPressed: () => invalidatePendingBookingActionsCount(ref),
                child: const SizedBox.shrink(),
              ),
        ),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: activeIndex,
          showBookingsBadge: showBookingsBadge,
          bookingsBadgeAsOwnerMaster: asOwnerMaster,
        ),
      ),
      retry: (_, _) => null,
      overrides: overridesFor(role),
    );
    await tester.pumpAndSettle();
  }

  Finder badgeText(String text) =>
      find.descendant(of: find.byKey(_badge), matching: find.text(text));

  void verifyNoCountRequest() => verifyNever(
    () => repo.getPendingActionsCount(
      any(),
      cancelToken: any(named: 'cancelToken'),
    ),
  );

  group('INDEPENDENT_MASTER', () {
    testWidgets('count 3 → badge «3» on «Записи», read with .me(false)', (
      tester,
    ) async {
      await pumpBar(tester);

      expect(
        find.descendant(
          of: find.byKey(_bookingsTile),
          matching: find.byKey(_badge),
        ),
        findsOneWidget,
      );
      expect(badgeText('3'), findsOneWidget);
      verify(
        () => repo.getPendingActionsCount(
          _meScope,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    });

    testWidgets('count 0 → no badge', (tester) async {
      count = 0;
      await pumpBar(tester);
      expect(find.byKey(_badge), findsNothing);
    });

    testWidgets('count 120 → caps at «99+»', (tester) async {
      count = 120;
      await pumpBar(tester);
      expect(badgeText('99+'), findsOneWidget);
    });

    testWidgets('semantics hint announces the count', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpBar(tester);
      expect(
        tester.getSemantics(find.byKey(_bookingsTile)).hint,
        _uk.navBookingsPendingHint(3),
      );
      semantics.dispose();
    });

    testWidgets('semantics hint is empty at count 0', (tester) async {
      count = 0;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpBar(tester);
      expect(tester.getSemantics(find.byKey(_bookingsTile)).hint, isEmpty);
      semantics.dispose();
    });

    testWidgets('showBookingsBadge off (default) → no badge, no request', (
      tester,
    ) async {
      await pumpBar(tester, showBookingsBadge: false);
      expect(find.byKey(_badge), findsNothing);
      verifyNoCountRequest();
    });

    testWidgets('archive-action invalidation refreshes the nav badge', (
      tester,
    ) async {
      await pumpBar(tester);
      expect(badgeText('3'), findsOneWidget);

      count = 0; // the close resolved the last pending booking
      await tester.tap(find.byKey(_invalidateButton));
      await tester.pumpAndSettle();

      expect(find.byKey(_badge), findsNothing);
      verify(
        () => repo.getPendingActionsCount(
          _meScope,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2);
    });
  });

  group('owner master mode', () {
    testWidgets('SALON_OWNER + asOwnerMaster → badge from .me(true)', (
      tester,
    ) async {
      count = 5;
      await pumpBar(tester, role: UserRole.salonOwner, asOwnerMaster: true);

      expect(badgeText('5'), findsOneWidget);
      verify(
        () => repo.getPendingActionsCount(
          _ownerScope,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verifyNever(
        () => repo.getPendingActionsCount(
          _meScope,
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    });

    testWidgets('SALON_OWNER without asOwnerMaster → no badge, no request', (
      tester,
    ) async {
      await pumpBar(tester, role: UserRole.salonOwner);
      expect(find.byKey(_badge), findsNothing);
      verifyNoCountRequest();
    });
  });

  group('SALON_MASTER', () {
    testWidgets('SALON_MASTER bar (badge off) → no badge, no request', (
      tester,
    ) async {
      await pumpBar(
        tester,
        role: UserRole.salonMaster,
        showBookingsBadge: false,
      );
      expect(find.byKey(_badge), findsNothing);
      verifyNoCountRequest();
    });

    testWidgets('role gate: even with showBookingsBadge on → no request', (
      tester,
    ) async {
      await pumpBar(tester, role: UserRole.salonMaster);
      expect(find.byKey(_badge), findsNothing);
      verifyNoCountRequest();
    });
  });

  group('tab switching', () {
    GoRoute tab(String path, int index) => GoRoute(
      path: path,
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        key: Key('test-tab-$index'),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: index,
          showBookingsBadge: true,
        ),
      ),
    );

    testWidgets('bookings → services → schedule → profile issues ONE count '
        'request', (tester) async {
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.masterBookings,
        routes: <RouteBase>[
          tab(RouteNames.services, 0),
          tab(RouteNames.masterBookings, 1),
          tab(RouteNames.masterSchedule, 2),
          tab(RouteNames.masterProfile, 3),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        retry: (_, _) => null,
        overrides: overridesFor(UserRole.independentMaster),
      );
      await tester.pumpAndSettle();
      expect(badgeText('3'), findsOneWidget);

      for (final int i in <int>[0, 2, 3]) {
        await tester.tap(find.byKey(Key('master-nav-tile-$i')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('test-tab-$i')), findsOneWidget);
        expect(badgeText('3'), findsOneWidget);
      }

      verify(
        () => repo.getPendingActionsCount(
          _meScope,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    });
  });
}
