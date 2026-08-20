// mobile-qa Phase 247 audit — pins the RESOLVED screen TYPE for
// `/master/bookings/new` and `/master/bookings/archive`, not merely that
// SOME `GoRoute` in the tree happens to carry a matching `path` string.
//
// ## Why this test exists, and why it is NOT in `app_router_page_type_test.dart`
//
// `app_router.dart` registers three siblings under `/master/bookings`:
//   • `archive`      (literal)
//   • `new`          (literal)
//   • `:bookingId`   (dynamic)
// go_router resolves literal-before-dynamic segments ONLY by declaration
// order among siblings — both literals are (correctly, today) declared
// before `:bookingId`, with an inline comment on each warning that this must
// never change. Nothing besides that comment enforces it.
//
// `app_router_page_type_test.dart`'s `_findRoute` helper walks the route
// tree and returns the first `GoRoute` whose OWN `path` field equals the
// target string. That is a structural property of the `GoRoute` object, not
// of go_router's resolution — reordering the three siblings does not change
// any node's `path` field, so `_findRoute(routes, 'new')` still finds the
// `new` node regardless of where it sits in the list. FALSIFIED directly:
// commenting out the ENTIRE `/master/bookings/new` `GoRoute` (not just
// reordering it) left `test/routing/` green, because `:bookingId` silently
// absorbed the path as `bookingId == "new"` — proving the existing routing
// suite only asserts "the path resolves to *something*", never "to the
// RIGHT something". That gap is what this file closes, for both `new` and
// its structurally-identical sibling `archive`.
//
// Catching an order regression requires running go_router's own matcher —
// i.e. pumping the REAL `appRouterProvider`, calling `router.go(path)`, and
// asserting on the WIDGET TYPE that actually mounts. That is a widget-tier
// test, unlike `app_router_page_type_test.dart`'s deliberately pump-free
// "Layer: Unit" convention (see that file's own header) — so it lives here
// instead of diluting that file's stated scope. The plumbing (a
// `ProviderContainer` reading the real `appRouterProvider`, `_RouterApp`,
// `_FixedAuthNotifier`, the authenticated INDEPENDENT_MASTER session, the
// settled `MasterProfileScreen` overrides) mirrors `app_router_test.dart`'s
// "appRouter real redirect wiring" group verbatim — that is the file's own
// precedent for pumping the production router end-to-end.
//
// MUTATION-VERIFIED (see PR discussion / audit notes): swapping the
// `:bookingId` `GoRoute` ahead of `archive`/`new` in `app_router.dart` turns
// both tests below RED (they resolve `BookingDetailScreen` instead), and
// restoring the original order turns them back GREEN. A pin that would not
// fail on that reorder would be worthless — this one does.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_create_booking_screen.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirrors app_router_test.dart's authenticated-redirect fixtures.
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'master@example.com',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'token'),
);

class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'u1',
    firstName: 'Тест',
    lastName: 'Майстер',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// Never touched by either route under test — `/master/bookings/new` only
/// reaches its `client` step (no repository call), and the archive fetch
/// below is answered by `getMyBookings` alone. Every other method throws so
/// an unexpected call fails loudly rather than silently hitting real Dio.
class _FakeBookingRepository implements BookingRepository {
  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async => const PageResponse<Booking>(
    items: <Booking>[],
    page: 0,
    totalPages: 1,
    totalElements: 0,
  );

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError();

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

/// [MaterialApp.router] wrapper for the real [appRouter] — byte-identical to
/// `app_router_test.dart`'s own `_RouterApp`.
class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  group('app_router — /master/bookings literal siblings resolve to their OWN '
      'screen, not the :bookingId shadow', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // The splash→authenticated redirect lands on MasterProfileScreen
          // before either explicit `router.go` below — settle its data so
          // it resolves without a real Dio request (mirrors
          // app_router_test.dart's `makeContainer`).
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          masterServiceCatalogProvider.overrideWith(
            (ref) async => const <MasterService>[],
          ),
          bookingRepositoryProvider.overrideWith(
            (_) => _FakeBookingRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets(
      '/master/bookings/new resolves MasterCreateBookingScreen, never '
      'BookingDetailScreen',
      (tester) async {
        final container = makeContainer();
        final router = container.read(appRouterProvider);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _RouterApp(router: router),
          ),
        );
        await tester.pump();

        router.go(RouteNames.masterBookingNew);
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(MasterCreateBookingScreen),
          findsOneWidget,
          reason:
              'If :bookingId (declared AFTER new/archive) ever moves ahead '
              'of them, go_router absorbs "new" as bookingId and the '
              'wizard becomes unreachable — this must catch that.',
        );
        expect(find.byType(BookingDetailScreen), findsNothing);
      },
    );

    testWidgets('/master/bookings/archive resolves MasterArchiveScreen, never '
        'BookingDetailScreen', (tester) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.masterBookingsArchive);
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(MasterArchiveScreen),
        findsOneWidget,
        reason:
            'Same shadowing risk as /master/bookings/new — archive is '
            'the pre-existing literal sibling this gap already applied '
            'to before Phase 247 added a second one.',
      );
      expect(find.byType(BookingDetailScreen), findsNothing);
    });
  });
}
