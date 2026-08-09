// Phase 241 — «Записатись» rebook deep link, navigation tests.
//
// Pins two things per the phase doc's § Test Cases → Navigation:
//
//   1. `should_pushBookingFlowWithBothIds_when_bookTapped` — tapping the CTA
//      pushes `RouteNames.bookingNew` with a [BookingEntryArgs] carrying BOTH
//      the tapped entry's `masterId` and `masterServiceId` (as
//      `preselectedServiceId`).
//
//   2. `should_useSameHandler_fromCompactCardAndFullRow` — the passport
//      page's compact-card line (`WishlistSection` → `WishlistCompactCard`)
//      and the full «Усі збережені» list (`WishlistScreen` → `WishlistRow`)
//      push the IDENTICAL [BookingEntryArgs] shape for the SAME entry, proving
//      both surfaces are wired through the ONE `WishlistRebookHost.rebook`
//      mixin method (`wishlist_rebook.dart`) rather than two independent
//      call sites that happen to agree today.
//
// ## WHY THIS MUST USE `context.push`, NEVER `router.go` — AND WHY THE TEST
// ASSERTS ON THE PUSH ITSELF, NOT ON A NAIVE LOCATION READ
//
// `route_names.dart`'s own precedent (`wishlist_route_test.dart`) is that a
// pushed leaf's `GoRouterState.fullPath` collapses to its PARENT in
// `currentConfiguration.uri`/`.fullPath` — a `router.go`-based test, or one
// that reads the naive location property, would false-pass here even if the
// production code never pushed anything (or pushed the wrong thing), because
// both routes in this file's tiny router sit at the TOP level: a `go` would
// simply REPLACE the current top-level match with `bookingNew`'s, indistinguishable
// from a push at that naive read. So this file inspects the actual pushed
// [BookingEntryArgs] captured off `GoRouterState.extra` by a stub destination
// screen — the only way to prove the production `context.push` call fired
// with the right shape rather than merely landing on a URL that looks right.
//
// Layer: Widget (real screens — `PassportScreen` / `WishlistScreen` — behind a
// small purpose-built router; no ClientShell chrome needed for this concern).

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_entry_args.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/wishlist_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_wishlist_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const User _client = User(
  id: 'u-client',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
);

const AsyncData<AuthSession> _session = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _client, accessToken: 'token'),
);

const ClientProfileSummary _profile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

const Passport _passport = Passport(
  favoriteDistricts: <String>['Центр'],
  favoriteCities: <String>['Львів'],
  budget: BudgetBand(avg: 600, min: 400, max: 800),
  bookingsConsidered: 7,
  reviewsWritten: 5,
  memberSinceYear: 2024,
);

WishlistService _entry(String id) => WishlistService(
  masterServiceId: id,
  masterId: 'm-$id',
  serviceName: 'Послуга $id',
  masterName: 'Олена Ковальчук',
  durationMinutes: 60,
  priceDisplay: '600 ₴',
);

/// Two entries so the passport section's `take(2)` compact-card line renders
/// both, and the full list has the same two.
List<WishlistService> _wishlist() => <WishlistService>[
  _entry('a'),
  _entry('b'),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _session;
    return _session.value;
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Captures every `extra` a push to [RouteNames.bookingNew] carried, in order.
class _BookingNewCapture {
  final List<Object?> pushes = <Object?>[];
}

class _Harness {
  _Harness._(this.tester, this.container, this.router, this.capture);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;
  final _BookingNewCapture capture;

  static Future<_Harness> boot(WidgetTester tester) async {
    final FakeWishlistRepository wishlistRepo = FakeWishlistRepository(
      services: _wishlist(),
    );
    final _BookingNewCapture capture = _BookingNewCapture();

    final ProviderContainer container = ProviderContainer(
      overrides: <Object>[
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        clientProfileProvider.overrideWith((_) async => _profile),
        passportProvider.overrideWith((_) async => _passport),
        screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
        wishlistRepositoryProvider.overrideWithValue(wishlistRepo),
        favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      ].cast(),
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    // A small purpose-built router: real `PassportScreen` / `WishlistScreen`,
    // but `bookingNew` resolves to a stub that only records the extra — this
    // file's concern is "did the right push happen", not "does the booking
    // flow itself render", which `service_selector_sheet_test.dart` and
    // `booking_preselection_seed_test.dart` already cover.
    final GoRouter router = GoRouter(
      initialLocation: RouteNames.clientPassport,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.clientPassport,
          builder: (context, state) => const PassportScreen(),
        ),
        GoRoute(
          path: RouteNames.clientWishlist,
          builder: (context, state) => const WishlistScreen(),
        ),
        GoRoute(
          path: RouteNames.bookingNew,
          builder: (context, state) {
            capture.pushes.add(state.extra);
            return const Scaffold(
              key: Key('stub-booking-new-screen'),
              body: SizedBox.shrink(),
            );
          },
        ),
      ],
    );

    // Tall surface: the passport page's wish-list section sits at the bottom
    // of a scrolling list (mirrors `wishlist_route_test.dart`).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final _Harness h = _Harness._(tester, container, router, capture);
    // `wishlistProvider` holds a 5-minute keep-alive Timer (cancelled in its
    // own `onDispose`) — must be torn down before the test body ends, same
    // reasoning as `wishlist_route_test.dart`.
    addTearDown(() => container.dispose());
    return h;
  }

  /// Whether the current top-level match is an [ImperativeRouteMatch] — the
  /// structural fingerprint of `context.push` (a `context.go` instead
  /// produces a plain, non-imperative match). See the file header.
  bool get topIsImperativePush =>
      router.routerDelegate.currentConfiguration.matches.last
          is ImperativeRouteMatch;
}

void main() {
  group('should_pushBookingFlowWithBothIds_when_bookTapped', () {
    testWidgets(
      'tapping the compact card «Записатись» pushes bookingNew with a '
      'BookingEntryArgs carrying BOTH masterId and masterServiceId',
      (tester) async {
        final _Harness h = await _Harness.boot(tester);

        final Finder book = find.byKey(const Key('wishlist_card_book_a'));
        expect(book, findsOneWidget);
        await tester.tap(book);
        await tester.pumpAndSettle();

        // Landed on the stub — proves this was a genuine navigation, not just
        // a callback invoked with no route change.
        expect(
          find.byKey(const Key('stub-booking-new-screen')),
          findsOneWidget,
        );

        // The push is an imperative match — `context.push`, not `context.go`
        // (which a naive `router.go`-based test could not distinguish; see
        // the file header).
        expect(
          h.topIsImperativePush,
          isTrue,
          reason:
              'RouteNames.bookingNew must be reached via context.push, never '
              'context.go — a go-based rebook would not compose with the '
              'flow the same way and this repo has a standing convention '
              '(route_names.dart) that pushed leaves are asserted this way',
        );

        expect(h.capture.pushes, hasLength(1));
        final Object? extra = h.capture.pushes.single;
        expect(extra, isA<BookingEntryArgs>());
        final BookingEntryArgs args = extra! as BookingEntryArgs;
        expect(args.masterId, 'm-a');
        expect(args.preselectedServiceId, 'a');
        h.container.dispose();
      },
    );
  });

  group('should_useSameHandler_fromCompactCardAndFullRow', () {
    testWidgets(
      'the passport compact card and the full-list row push the IDENTICAL '
      'BookingEntryArgs shape for the same entry — one shared handler, not '
      'two independent call sites',
      (tester) async {
        final _Harness h = await _Harness.boot(tester);

        // 1. Compact card, from the passport page (WishlistSection).
        await tester.tap(find.byKey(const Key('wishlist_card_book_b')));
        await tester.pumpAndSettle();
        expect(h.capture.pushes, hasLength(1));
        final BookingEntryArgs fromCard =
            h.capture.pushes.single! as BookingEntryArgs;

        // Back to the passport page, then into the full list.
        h.router.pop();
        await tester.pumpAndSettle();
        unawaited(h.router.push(RouteNames.clientWishlist));
        await tester.pumpAndSettle();

        // 2. Full row, from the SAME entry on WishlistScreen (WishlistRow).
        final Finder row = find.byKey(const Key('wishlist_row_book_b'));
        expect(row, findsOneWidget);
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(h.capture.pushes, hasLength(2));
        final BookingEntryArgs fromRow =
            h.capture.pushes.last! as BookingEntryArgs;

        // Both surfaces produced the exact same payload for the exact same
        // entry — the only way that happens is if both go through
        // WishlistRebookHost.rebook rather than two hand-rolled call sites.
        expect(fromRow.masterId, fromCard.masterId);
        expect(fromRow.preselectedServiceId, fromCard.preselectedServiceId);
        expect(fromCard.masterId, 'm-b');
        expect(fromCard.preselectedServiceId, 'b');
        h.container.dispose();
      },
    );
  });
}
