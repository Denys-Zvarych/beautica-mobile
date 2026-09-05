// Phase 13.6 — Widget tests for PublicSalonProfileScreen.
//
// Covers:
//   1. Loading  — skeleton blocks + back/favourite controls present, name absent.
//   2. Data     — hero name/rating render; 4-tab bar present; About tab default.
//   3. Error    — ErrorState renders with a working retry.
//   4. Favourite toggle — idempotent tap (favorite → unfavorite → favorite).
//   5. Master card navigation — tapping a rail card pushes /masters/:masterId.
//   6. Tab switching — Масtери / Послуги / Відгуки tabs render their content.
//   7. Reviews sort sheet — opening + picking an option re-fetches with the new
//      sort (asserted via the fake repository's call log).
//   8. Empty states — no masters / no services / no reviews.
//
// Strategy: override [salonRepositoryProvider] with an in-memory fake (covers
// all 4 independent loaders in one place) and [favoriteRepositoryProvider]
// with a fake that always succeeds, plus a CLIENT-authenticated [authProvider]
// stub (mirrors PublicMasterProfileScreen's test harness).

import 'dart:async';

import 'package:beautica_api/beautica_api.dart'
    show SiblingSalonOption, UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_portfolio_photo.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_master_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

const _stubUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Клієнт',
  lastName: 'Тест',
);

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  city: 'Київ',
  address: 'вул. Велика Васильківська, 44',
  avgRating: 4.9,
  reviewCount: 128,
);

const _stubMasters = <SalonMasterSummary>[
  SalonMasterSummary(
    masterId: 'master-1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    avgRating: 4.9,
    reviewCount: 12,
    type: MasterType.independentMaster,
  ),
];

// ---------------------------------------------------------------------------
// Phase 283 — roster audience-matrix fixtures (client-side rows, D2/D4/D6).
//
// [SalonMasterSummary] structurally cannot carry an admin — no `role` field
// exists on this wire shape at all (D3's whole point: an admin has no master
// row, so it cannot reach `/masters`). These fixtures mirror the STAFF-SIDE
// counterparts in `salon_management_profile_screen_test.dart` by NAME/id
// prefix only (`matrix-owner-1`/`matrix-dual-1`/`matrix-master-1`) — the two
// files never share a repository instance, so matching masterId strings are
// for readability across the pair, not a wired invariant.
// ---------------------------------------------------------------------------

/// D2's "toggle ON" client-side cell — the owner's active master row.
const _matrixClientOwner = SalonMasterSummary(
  masterId: 'matrix-owner-master-1',
  firstName: 'Оксана',
  lastName: 'Швець',
  type: MasterType.salonOwner,
);

/// D4's edge case, client half: this person is `SALON_ADMIN` on the staff
/// wire (see the staff-side `_matrixDualRole` counterpart) but their master
/// row is an ordinary `SALON_MASTER` — `/masters` has no way to know (or
/// care) that they are also an admin; it returns them like any other active
/// master, which is CORRECT (D4).
const _matrixClientDualRole = SalonMasterSummary(
  masterId: 'matrix-dual-master-1',
  firstName: 'Марта',
  lastName: 'Дворак',
  type: MasterType.salonMaster,
);

/// A plain active master — the baseline "always shown, both sides" row.
const _matrixClientMaster = SalonMasterSummary(
  masterId: 'matrix-master-1',
  firstName: 'Софія',
  lastName: 'Бондаренко',
  type: MasterType.salonMaster,
);

/// The full client-side roster a well-formed `/masters` response can ever
/// contain for this matrix — deliberately THREE entries, never four: there
/// is no admin-shaped row to add (D3), so "all of them, unfiltered" (D1) and
/// "never an admin" (D3) collapse to the same assertion at this layer — the
/// wire-level tests in `salon_management_profile_notifier_test.dart` are
/// what actually exercise a MUTATED wire response that unions an admin in.
const _matrixClientFullRoster = <SalonMasterSummary>[
  _matrixClientOwner,
  _matrixClientDualRole,
  _matrixClientMaster,
];

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'Манікюр',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр з покриттям',
        durationLabel: '1 год 30 хв',
        priceDisplay: '500 ₴',
      ),
    ],
  ),
];

const _stubSummary = SalonReviewSummary(
  avgRating: 4.9,
  reviewCount: 2,
  distribution: <int>[1, 1, 0, 0, 0],
);

final DateTime _fixedNow = DateTime(2026, 7, 1);

List<SalonReviewItem> _stubReviews(SalonReviewSort sort) => <SalonReviewItem>[
  SalonReviewItem(
    id: 'review-1',
    masterId: 'master-1',
    masterName: 'Олена Ковальчук',
    clientDisplayName: 'Олена К.',
    serviceName: 'Манікюр з покриттям',
    rating: 5,
    comment: 'Найкращий салон!',
    createdAt: _fixedNow.subtract(const Duration(days: 3)),
  ),
];

/// Stub [AuthNotifier] — always an authenticated CLIENT, no storage/network.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

/// Always-succeeding fake [FavoriteRepository].
class _FakeFavoriteRepository implements FavoriteRepository {
  final List<String> calls = <String>[];

  @override
  Future<void> add(FavoriteTarget target) async =>
      calls.add('add:${target.id}');

  @override
  Future<void> remove(FavoriteTarget target) async =>
      calls.add('remove:${target.id}');

  // Phase 111 — this screen never lists favourites; empty keeps the contract
  // satisfied without inventing rows the assertions would then have to ignore.
  @override
  Future<List<FavoriteItem>> getFavoriteMasters() async =>
      const <FavoriteItem>[];

  @override
  Future<List<FavoriteItem>> getFavoriteSalons() async =>
      const <FavoriteItem>[];
}

/// In-memory fake [SalonRepository] covering all 4 independent tab loaders.
/// Each field is a factory closure so individual tests can swap in a
/// never-completing [Completer] (loading) or a throwing closure (error).
class _FakeSalonRepository implements SalonRepository {
  _FakeSalonRepository({
    Future<Salon> Function()? salon,
    Future<List<SalonMasterSummary>> Function()? masters,
    Future<List<SalonServiceCategoryEntry>> Function()? catalog,
    Future<SalonReviewSummary> Function()? summary,
    Future<List<SalonReviewItem>> Function(SalonReviewSort sort)? reviews,
    Future<List<SalonPortfolioPhoto>> Function()? portfolio,
  }) : _salon = salon ?? (() async => _stubSalon),
       _masters = masters ?? (() async => _stubMasters),
       _catalog = catalog ?? (() async => _stubCatalog),
       _summary = summary ?? (() async => _stubSummary),
       _reviews =
           reviews ?? ((SalonReviewSort sort) async => _stubReviews(sort)),
       // Empty by default so the existing (non-portfolio) tests never trigger
       // a real Image.network round trip — only the portfolio-specific tests
       // below opt in with a non-empty fixture (wrapped in
       // mockNetworkImagesFor).
       _portfolio = portfolio ?? (() async => const <SalonPortfolioPhoto>[]);

  final Future<Salon> Function() _salon;
  final Future<List<SalonMasterSummary>> Function() _masters;
  final Future<List<SalonServiceCategoryEntry>> Function() _catalog;
  final Future<SalonReviewSummary> Function() _summary;
  final Future<List<SalonReviewItem>> Function(SalonReviewSort sort) _reviews;
  final Future<List<SalonPortfolioPhoto>> Function() _portfolio;

  /// Sort values passed to [getSalonReviews], in call order — asserted by the
  /// sort-sheet test.
  final List<SalonReviewSort> reviewSortCalls = <SalonReviewSort>[];

  @override
  Future<void> create({required SalonCreateDto dto}) async {}

  // Phase 21.1 — this screen (the PUBLIC/client profile) never calls the
  // owner-scoped `GET /salons/mine`; empty keeps the contract satisfied.
  @override
  Future<List<Salon>> getMySalons() async => const <Salon>[];

  @override
  Future<Salon> getSalonById(String salonId) => _salon();

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) =>
      _masters();

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) => _catalog();

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) =>
      _summary();

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async {
    reviewSortCalls.add(sort);
    return _reviews(sort);
  }

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) =>
      _portfolio();

  // `salonMasterServiceCoverageProvider` (the salon-service → masters filter
  // path) is always overridden DIRECTLY in the tests that exercise it (see
  // the `coverage` param on [_overrides] below) rather than routed through
  // this fake repository, so no test here actually calls this method — it
  // exists purely to satisfy [SalonRepository]'s abstract interface. Throws
  // loudly rather than returning a silent empty list so an accidental real
  // call (a test that forgets to stub `coverage`) fails fast instead of
  // masking a bug as "zero bookable masters".
  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.getBookableMasters is not stubbed — override '
    'salonMasterServiceCoverageProvider directly via _overrides(coverage: …) '
    'instead of routing through this fake repository.',
  );

  // Phase 21.2 — owner/admin write paths. This screen is the CLIENT-facing
  // read-only profile, so neither is ever called here.
  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async =>
      throw UnimplementedError(
        '_FakeSalonRepository.updateSalon is not stubbed — this fake backs '
        'the CLIENT-facing read-only profile screen.',
      );

  @override
  Future<void> deleteSalon(String salonId) async => throw UnimplementedError(
    '_FakeSalonRepository.deleteSalon is not stubbed — this fake backs the '
    'CLIENT-facing read-only profile screen.',
  );

  // Owner/admin-only invite management; unreachable from this
  // CLIENT-facing surface, so the same UnimplementedError guard as
  // [deleteSalon] above rather than a silent empty stub.
  @override
  Future<SalonInviteHistory> listSalonInvites(
    String salonId,
  ) async => throw UnimplementedError(
    '_FakeSalonRepository.listSalonInvites is not stubbed — owner/admin only.',
  );

  @override
  Future<void> cancelInvite({
    required String salonId,
    required String inviteId,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.cancelInvite is not stubbed — owner/admin only.',
  );

  // Phase 21.6 — owner/admin admin-management surface. Same rationale as
  // [listSalonInvites]/[cancelInvite] above: this fake backs the
  // CLIENT-facing read-only salon profile, which can never reach any of
  // these three calls.
  @override
  Future<void> removeAdmin({
    required String salonId,
    required String userId,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.removeAdmin is not stubbed — owner/admin only.',
  );

  @override
  Future<void> removeMaster({
    required String salonId,
    required String masterId,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.removeMaster is not stubbed — owner/admin only.',
  );

  @override
  Future<void> rotateAdmin({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.rotateAdmin is not stubbed — owner/admin only.',
  );

  @override
  Future<List<SiblingSalonOption>> getSiblingSalons(
    String salonId,
  ) async => throw UnimplementedError(
    '_FakeSalonRepository.getSiblingSalons is not stubbed — owner/admin only.',
  );

  // Phase 21.4 — owner/admin write path (Invite Staff). Same rationale as
  // [updateSalon]/[deleteSalon] immediately above: this fake backs the
  // CLIENT-facing read-only profile screen, which never invites staff.
  @override
  Future<void> inviteStaff({
    required String salonId,
    required String email,
    required UserRole role,
  }) async => throw UnimplementedError(
    '_FakeSalonRepository.inviteStaff is not stubbed — this fake backs the '
    'CLIENT-facing read-only profile screen.',
  );

  // Phase 21.5 — owner/admin read path (staff roster). Same rationale as
  // [inviteStaff] immediately above.
  @override
  Future<List<SalonStaffMember>> getSalonStaff(String salonId) async =>
      throw UnimplementedError(
        '_FakeSalonRepository.getSalonStaff is not stubbed — this fake backs '
        'the CLIENT-facing read-only profile screen.',
      );
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Object> _overrides({
  _FakeSalonRepository? repo,
  _FakeFavoriteRepository? fav,
  // Optional override for the per-master service-coverage fan-out
  // (salonMasterServiceCoverageProvider). Only the salon-service→masters
  // filter path watches it (see _MastersTab); every other test leaves it out,
  // so the coverage provider is never even constructed on the unfiltered path.
  Object? coverage,
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo ?? _FakeSalonRepository()),
  favoriteRepositoryProvider.overrideWithValue(
    fav ?? _FakeFavoriteRepository(),
  ),
  ?coverage,
];

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('loading state', () {
    testWidgets('shows skeleton + back/favourite controls, name absent', (
      tester,
    ) async {
      await _pumpTall(tester);
      final Completer<Salon> never = Completer<Salon>();
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(salon: () => never.future),
        ),
      );
      await tester.pump();

      // The loading skeleton renders several independent shimmer regions
      // (hero card / tab bar / tab body placeholders) — assert at least one,
      // not exactly one.
      expect(find.byType(SkeletonShimmerScope), findsWidgets);
      expect(find.byKey(const Key('salon-profile-back')), findsOneWidget);
      expect(find.byKey(const Key('salon-favorite-toggle')), findsOneWidget);
      expect(find.byKey(const Key('salon-profile-name')), findsNothing);
    });
  });

  group('data state', () {
    testWidgets('renders hero name/rating, tab bar, and the About tab body', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);
      // i18n-finder-ok: salon name is fixture data, not UI copy
      expect(find.text('Салон «Вельвет»'), findsOneWidget);
      expect(find.byKey(const Key('salon-profile-rating')), findsOneWidget);
      expect(find.byKey(const Key('salon-book-cta')), findsOneWidget);

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(find.text(l10n.salonBookingCta), findsOneWidget);
      expect(find.text(l10n.salonTabAbout), findsOneWidget);
      expect(find.text(l10n.salonTabMasters), findsOneWidget);
      expect(find.text(l10n.salonTabServices), findsOneWidget);
      expect(find.text(l10n.salonTabReviews), findsOneWidget);

      // About tab default body — the salon description.
      expect(find.byKey(const Key('salon-about-text')), findsOneWidget);
    });

    // Regression (Phase 14.12) — closes the reported bug: this CTA used to
    // `context.push(RouteNames.bookingNew, extra: salon.id)`, pushing the
    // CLIENT into the *independent-master* `ServiceSelectorSheet` with
    // `salon.id` misused as a `masterId` — 404ing server-side
    // (`NotFoundException: Master not found`) because a salon is not a
    // master row. It must now push the dedicated salon booking flow's
    // service-selection step instead, carrying the SAME `salon.id` value
    // but as the correct extra shape for that route.
    testWidgets(
      '"Записатись на послугу" CTA pushes RouteNames.salonBookingServices '
      'with extra: salon.id — NOT RouteNames.bookingNew (closes the salon '
      'booking 404 bug)',
      (tester) async {
        await _pumpTall(tester);
        final router = GoRouter(
          initialLocation: '/salons/$_kSalonId',
          routes: <RouteBase>[
            GoRoute(
              path: '/salons/:salonId',
              builder: (context, state) => PublicSalonProfileScreen(
                salonId: state.pathParameters['salonId']!,
              ),
            ),
            GoRoute(
              path: RouteNames.salonBookingServices,
              builder: (_, state) =>
                  Scaffold(body: Text('salon-services-${state.extra}')),
            ),
            // A trap route: if the CTA regresses back to pushing
            // RouteNames.bookingNew, THIS route renders instead and the
            // assertion below fails loudly rather than the test just not
            // finding either screen.
            GoRoute(
              path: RouteNames.bookingNew,
              builder: (_, state) =>
                  Scaffold(body: Text('master-booking-${state.extra}')),
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: _overrides());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-book-cta')));
        await tester.pumpAndSettle();

        expect(find.text('salon-services-$_kSalonId'), findsOneWidget);
        expect(find.textContaining('master-booking-'), findsNothing);
      },
    );

    // Regression: the hero name was hard-capped to `maxLines: 1` with
    // ellipsis, silently truncating any salon name too long to fit — unlike
    // the independent master profile's hero name, which wraps to 2 lines
    // (public_master_profile_screen.dart:287-294). Guards against the cap
    // being reintroduced.
    testWidgets(
      'long salon name wraps to 2 lines instead of being ellipsis-truncated',
      (tester) async {
        await _pumpTall(tester);
        const String longName =
            'Салон краси «Незабутня Досконалість Стилю та Гармонії»';
        const longNameSalon = Salon(
          id: _kSalonId,
          name: longName,
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => longNameSalon),
          ),
        );
        await tester.pumpAndSettle();

        final nameFinder = find.byKey(const Key('salon-profile-name'));
        expect(nameFinder, findsOneWidget);

        final Text nameWidget = tester.widget<Text>(nameFinder);
        expect(
          nameWidget.maxLines,
          2,
          reason:
              'the hero name must allow 2 lines, matching the master '
              'profile hero card, instead of hard-capping at 1',
        );
        expect(
          nameWidget.data,
          longName,
          reason: 'the full name must render, not be silently truncated',
        );
      },
    );
  });

  // Regression: the About tab used to carry only the description + optional
  // Instagram contact — the real portfolio photo rail (previously an unwired
  // backend endpoint, `GET /salons/{salonId}/portfolio`) now renders between
  // them. Asserts both the N-photo case (structural ordering + one Image per
  // fixture photo) and the zero-photo case (section renders nothing at all,
  // matching how every other optional section on this screen behaves).
  group('portfolio rail', () {
    // The portfolio tiles now go through the shared RemoteImage loader, which
    // renders an Image only for an https URL on an allowed host. Open the
    // allowlist to the fixture host and route fetches through a fake so the
    // tiles build their Image widgets without a real network round-trip.
    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{'cdn.beautica.ua'};
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
    });
    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    const List<SalonPortfolioPhoto> threePhotos = <SalonPortfolioPhoto>[
      SalonPortfolioPhoto(
        id: 'photo-1',
        url: 'https://cdn.beautica.ua/portfolio/salon-1/1.jpg',
      ),
      SalonPortfolioPhoto(
        id: 'photo-2',
        url: 'https://cdn.beautica.ua/portfolio/salon-1/2.jpg',
      ),
      SalonPortfolioPhoto(
        id: 'photo-3',
        url: 'https://cdn.beautica.ua/portfolio/salon-1/3.jpg',
      ),
    ];

    // [_stubSalon] carries no `instagramUrl`, so the Instagram contact tile
    // never renders by default — this test needs it present to prove the
    // rail's structural ordering relative to it.
    final Salon salonWithInstagram = _stubSalon.copyWith(
      instagramUrl: '@kamelia_salon',
    );

    testWidgets('N photos render as N images between the description and the '
        'Instagram contact tile', (tester) async {
      await mockNetworkImagesFor(() async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              salon: () async => salonWithInstagram,
              portfolio: () async => threePhotos,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder railFinder = find.byKey(
          const Key('salon-about-portfolio'),
        );
        expect(railFinder, findsOneWidget);

        // Exactly one Image per fixture photo, all inside the rail.
        expect(
          find.descendant(of: railFinder, matching: find.byType(Image)),
          findsNWidgets(threePhotos.length),
        );
        for (final SalonPortfolioPhoto photo in threePhotos) {
          expect(
            find.byKey(Key('salon-portfolio-photo-${photo.id}')),
            findsOneWidget,
          );
        }

        // Structural ordering: description → portfolio rail → Instagram
        // contact tile, top to bottom. Uses the first TILE's rect (not the
        // rail Column's own outer bounds) for the description comparison —
        // the Column's top edge sits flush against the description's
        // bottom edge (its leading section-label gap is internal to the
        // Column), so comparing against the Column itself would assert a
        // non-overlapping-but-not-strictly-greater boundary.
        final Rect descriptionRect = tester.getRect(
          find.byKey(const Key('salon-about-text')),
        );
        final Rect firstTileRect = tester.getRect(
          find.byKey(Key('salon-portfolio-photo-${threePhotos.first.id}')),
        );
        final Rect railRect = tester.getRect(railFinder);
        final Rect instagramRect = tester.getRect(
          find.byKey(const Key('salon-contact-instagram')),
        );

        expect(
          firstTileRect.top,
          greaterThan(descriptionRect.bottom),
          reason: 'the portfolio rail must render BELOW the description',
        );
        expect(
          instagramRect.top,
          greaterThan(railRect.bottom),
          reason:
              'the Instagram contact tile must render BELOW the '
              'portfolio rail',
        );
      });
    });

    testWidgets('zero photos renders nothing — no heading, no empty rail', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(
            salon: () async => salonWithInstagram,
            portfolio: () async => const <SalonPortfolioPhoto>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-about-portfolio')),
        findsNothing,
        reason:
            'a salon with no portfolio photos must render no rail '
            'section at all — matches how the other optional sections '
            'on this screen behave',
      );
      // The description + (when present) Instagram contact must still
      // render normally — the empty portfolio must not blank the tab.
      expect(find.byKey(const Key('salon-about-text')), findsOneWidget);
      expect(find.byKey(const Key('salon-contact-instagram')), findsOneWidget);
    });

    // SEC (mobile-security LOW follow-up): pins the `isHttps` guard in
    // [_SalonPortfolioTile.build] — `Image.network` uses its own
    // `HttpClient`, not the pinned Dio, so a plaintext `http://` photo URL
    // would leak the request over an unencrypted connection if ever allowed
    // through. No [mockNetworkImagesFor] wrapper needed here: a correctly
    // guarded build never attempts a network image load for this fixture in
    // the first place.
    testWidgets(
      'a non-https photo URL renders the fallback tile, never Image.network',
      (tester) async {
        const List<SalonPortfolioPhoto> insecurePhoto = <SalonPortfolioPhoto>[
          SalonPortfolioPhoto(
            id: 'photo-insecure',
            url: 'http://insecure.example/x.jpg',
          ),
        ];
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(portfolio: () async => insecurePhoto),
          ),
        );
        await tester.pumpAndSettle();

        final Finder tileFinder = find.byKey(
          const Key('salon-portfolio-photo-photo-insecure'),
        );
        expect(tileFinder, findsOneWidget);

        expect(
          find.descendant(of: tileFinder, matching: find.byType(Image)),
          findsNothing,
          reason: 'a non-https photo URL must never construct Image.network',
        );
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.byIcon(Icons.broken_image_outlined),
          ),
          findsOneWidget,
          reason:
              'the fallback error tile must render instead of attempting '
              'to load the insecure URL',
        );
      },
    );

    // Eager-build cap regression (mirrors the masters-tab precedent above,
    // `'more than 6 masters renders only the first 6 plus a show-all
    // button...'`) — the rail is a plain `Row` inside a horizontal
    // `SingleChildScrollView`, not a lazily-built viewport, so with more
    // fixture photos than `kSalonPortfolioInitialCount` (8) this pins that
    // only the first 8 tiles build up front, a "show all" tile appears with
    // the correct remaining count, and tapping it reveals the rest while the
    // affordance itself disappears.
    testWidgets(
      'more than 8 photos renders only the first 8 plus a show-all tile, '
      'which reveals the rest on tap',
      (tester) async {
        final List<SalonPortfolioPhoto> tenPhotos = List.generate(
          10,
          (i) => SalonPortfolioPhoto(
            id: 'photo-${i + 1}',
            url: 'https://cdn.beautica.ua/portfolio/salon-1/${i + 1}.jpg',
          ),
        );

        await mockNetworkImagesFor(() async {
          await _pumpTall(tester);
          await tester.pumpApp(
            const PublicSalonProfileScreen(salonId: _kSalonId),
            overrides: _overrides(
              repo: _FakeSalonRepository(portfolio: () async => tenPhotos),
            ),
          );
          await tester.pumpAndSettle();

          for (int i = 1; i <= 8; i++) {
            expect(
              find.byKey(Key('salon-portfolio-photo-photo-$i')),
              findsOneWidget,
              reason: 'the first 8 photos must render up front',
            );
          }
          for (int i = 9; i <= 10; i++) {
            expect(
              find.byKey(Key('salon-portfolio-photo-photo-$i')),
              findsNothing,
              reason:
                  'photos beyond the initial batch of 8 must NOT be built '
                  'until the user explicitly reveals them',
            );
          }

          final Finder showAll = find.byKey(
            const Key('salon-portfolio-show-all'),
          );
          expect(
            showAll,
            findsOneWidget,
            reason:
                'a show-all affordance must appear when the gallery '
                'exceeds the initial batch',
          );
          expect(
            find.descendant(of: showAll, matching: find.text('+2')),
            findsOneWidget,
            reason: 'the show-all tile must report the remaining count',
          );

          await tester.tap(showAll);
          await tester.pumpAndSettle();

          for (int i = 1; i <= 10; i++) {
            expect(
              find.byKey(Key('salon-portfolio-photo-photo-$i')),
              findsOneWidget,
              reason: 'all 10 photos must render after tapping show-all',
            );
          }
          expect(
            showAll,
            findsNothing,
            reason:
                'the show-all tile must disappear once everything is '
                'revealed',
          );
        });
      },
    );
  });

  // Regression: the top-left back control and the top-right favourite heart
  // used to be full circles (`CoverCircleButton`, `BoxShape.circle`). They
  // now match the app-wide rounded-square icon-button shape (see
  // `NeumorphicIconButton`/`VelvetRadii.field`) used everywhere else in the
  // app, including the sibling PublicMasterProfileScreen's own favourite
  // toggle — renamed to `CoverIconButton` to match.
  group('cover controls shape', () {
    testWidgets('back + favourite controls are rounded-square, not circular', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      for (final Key key in <Key>[
        const Key('salon-profile-back'),
        const Key('salon-favorite-toggle'),
      ]) {
        final Finder buttonFinder = find.byKey(key);
        expect(buttonFinder, findsOneWidget);
        expect(
          tester.widget<CoverIconButton>(buttonFinder),
          isA<CoverIconButton>(),
        );

        final Finder containerFinder = find.descendant(
          of: buttonFinder,
          matching: find.byType(Container),
        );
        expect(containerFinder, findsOneWidget);
        final Container container = tester.widget<Container>(containerFinder);
        final BoxDecoration decoration = container.decoration! as BoxDecoration;

        expect(
          decoration.shape,
          isNot(BoxShape.circle),
          reason: '$key must no longer be a full circle',
        );
        expect(
          decoration.borderRadius,
          BorderRadius.circular(VelvetRadii.field),
          reason:
              '$key must use the app-wide rounded-square radius '
              '(VelvetRadii.field)',
        );
      }
    });
  });

  // Regression: `PublicSalonResponse` gained taxonomy locality fields
  // (backend commit ef96845) alongside the pre-existing legacy `city`/
  // `address` pair. Every salon created/edited since Phase 10.6 has null
  // legacy fields, so the address row must render from the taxonomy fields
  // too — not just the legacy ones — while still supporting salons that
  // never re-saved location and only ever had the legacy pair.
  group('location line', () {
    testWidgets(
      'taxonomy-only salon (street set, no legacy city/address) renders '
      'a non-empty location line',
      (tester) async {
        await _pumpTall(tester);
        const taxonomySalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          cityId: 'city-uuid-1',
          street: 'вул. Хрещатик',
          buildingNo: '22',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => taxonomySalon),
          ),
        );
        await tester.pumpAndSettle();

        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(addressWidget.data, isNotNull);
        expect(addressWidget.data, isNotEmpty);
        expect(addressWidget.data, contains('вул. Хрещатик'));
      },
    );

    testWidgets(
      'legacy-only salon (city/address set, no taxonomy fields) renders '
      'the city on its own locality line and the address on its own '
      'street line (backward compat, Phase 223 (b) two-line split)',
      (tester) async {
        await _pumpTall(tester);
        const legacySalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => legacySalon),
          ),
        );
        await tester.pumpAndSettle();

        final localityFinder = find.byKey(
          const Key('salon-profile-locality-text'),
        );
        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(localityFinder, findsOneWidget);
        expect(addressFinder, findsOneWidget);
        final Text localityWidget = tester.widget<Text>(localityFinder);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(localityWidget.data, 'Київ');
        expect(addressWidget.data, isNotNull);
        expect(addressWidget.data, isNotEmpty);
        expect(addressWidget.data, contains('вул. Велика Васильківська, 44'));
      },
    );

    testWidgets(
      'salon with BOTH taxonomy and legacy fields set prefers the taxonomy '
      'street over the legacy city/address (a pre-10.6 salon re-saved after '
      'Phase 10.3+ keeps stale legacy fields the mapper never clears)',
      (tester) async {
        await _pumpTall(tester);
        const bothSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Львів',
          address: 'вул. Стара, 1',
          cityId: 'city-uuid-1',
          street: 'вул. Хрещатик',
          buildingNo: '22',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => bothSalon),
          ),
        );
        await tester.pumpAndSettle();

        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(
          addressWidget.data,
          contains('вул. Хрещатик'),
          reason: 'the taxonomy street must win over the legacy pair',
        );
        expect(
          addressWidget.data,
          isNot(contains('Львів')),
          reason: 'the stale legacy city must NOT leak into the rendered line',
        );
        expect(
          addressWidget.data,
          isNot(contains('вул. Стара')),
          reason:
              'the stale legacy address must NOT leak into the rendered line',
        );
      },
    );

    testWidgets(
      'salon with neither taxonomy nor legacy location fields hides the '
      'address row entirely (no icon, no empty text)',
      (tester) async {
        await _pumpTall(tester);
        const locationlessSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => locationlessSalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-profile-address-text')),
          findsNothing,
        );
        expect(
          find.byIcon(Icons.location_on_outlined),
          findsNothing,
          reason: 'the location pin icon must not render with no data either',
        );
      },
    );
  });

  // ── Phase 224 (mobile-qa gap-fill) — INVISIBLE address fields ─────────────
  //
  // WHY THIS GROUP EXISTS
  // ---------------------
  // Phase 224 rewrote `buildLocalityLine` / `buildStreetLine` (shared/
  // formatters/address_lines.dart) to sanitize-then-trim-then-test via a
  // private `_visibleOrNull`, instead of testing emptiness on the RAW field.
  // That is a behaviour change to two builders this salon screen consumes —
  // but every salon fixture in the `location line` group above carries clean,
  // fully-visible strings, so the whole group passes identically before and
  // after the refactor. 98/98 green was therefore NOT evidence the salon path
  // survived it; it was evidence the salon path never exercised it.
  //
  // These fields are provider-authored free text with `@Size`-only backend
  // validation (no character-class constraint), so a whitespace-only or
  // zero-width-only value is reachable, not hypothetical — the same premise
  // the Phase 221 sanitization audit acted on for `locationNote`.
  //
  // The third case below is a REGRESSION test for a real defect this group
  // found: `_localityLine`/`_streetLine` gated the taxonomy-vs-legacy choice
  // on a raw `salon.street?.isNotEmpty`, a DIFFERENT notion of "present" from
  // the formatters'. A whitespace-only `street` satisfied the raw gate
  // (suppressing the city as "this salon uses taxonomy fields") while the
  // formatter correctly reported the street absent — so BOTH lines came back
  // null and the entire address row, pin included, vanished for a salon with
  // a perfectly good city on file.
  group('location line — fields with no VISIBLE content', () {
    /// U+200B ZERO WIDTH SPACE, built via `String.fromCharCode` so this file
    /// never embeds the raw character it exists to test.
    final String zwsp = String.fromCharCode(0x200B);

    testWidgets(
      'a whitespace-only legacy city is treated as ABSENT: no locality row of '
      'literal spaces, and the legacy address is promoted to the primary row',
      (tester) async {
        await _pumpTall(tester);
        const whitespaceCitySalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: '   ',
          address: 'вул. Велика Васильківська, 44',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => whitespaceCitySalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-profile-locality-text')),
          findsNothing,
          reason:
              'a city of three spaces used to occupy a whole row and render '
              'nothing — it must now be absent, not blank',
        );

        // The address is promoted to the primary (icon-bearing) row, exactly
        // as it is for a null city.
        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(addressWidget.data, 'вул. Велика Васильківська, 44');
      },
    );

    testWidgets(
      'a zero-width-only legacy address is treated as ABSENT: the city keeps '
      'the primary row and no second, empty street row is emitted',
      (tester) async {
        await _pumpTall(tester);
        final invisibleAddressSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: zwsp,
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              salon: () async => invisibleAddressSalon,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final localityFinder = find.byKey(
          const Key('salon-profile-locality-text'),
        );
        expect(localityFinder, findsOneWidget);
        // i18n-finder-ok: salon.city fixture value, not localised UI copy.
        expect(tester.widget<Text>(localityFinder).data, 'Київ');
        expect(
          find.byKey(const Key('salon-profile-address-text')),
          findsNothing,
          reason:
              'a zero-width-only address must not claim a second row that '
              'renders as nothing',
        );
      },
    );

    testWidgets(
      'REGRESSION — a whitespace-only TAXONOMY street must not suppress the '
      'city: the address row (and its pin) still renders, falling back to the '
      'legacy address rather than disappearing entirely',
      (tester) async {
        await _pumpTall(tester);
        const blankStreetSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          cityId: 'city-uuid-1',
          street: '   ',
          buildingNo: '22',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => blankStreetSalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byIcon(Icons.location_on_outlined),
          findsOneWidget,
          reason:
              'the whole location row (pin included) was being dropped: the '
              'raw isNotEmpty gate read the blank street as "taxonomy salon" '
              'and suppressed the city, while the formatter read the same '
              'street as absent and returned null for the street line too',
        );

        final localityFinder = find.byKey(
          const Key('salon-profile-locality-text'),
        );
        expect(localityFinder, findsOneWidget);
        // i18n-finder-ok: salon.city fixture value, not localised UI copy.
        expect(tester.widget<Text>(localityFinder).data, 'Київ');

        // With no visible taxonomy street, the legacy address is the salon's
        // only street data and must be used rather than silently dropped.
        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(addressWidget.data, 'вул. Велика Васильківська, 44');
        // The orphaned building number must never appear on its own — it had
        // no visible street to attach to.
        expect(addressWidget.data, isNot(contains('22')));
      },
    );

    testWidgets(
      'every address field invisible → the whole location row is hidden, and '
      'no rendered line is blank, untrimmed, or comma-orphaned',
      (tester) async {
        await _pumpTall(tester);
        final allInvisibleSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: '  ',
          address: zwsp,
          cityId: 'city-uuid-1',
          street: '\t\n ',
          buildingNo: '  ',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => allInvisibleSalon),
          ),
        );
        await tester.pumpAndSettle();

        // POSITIVE ANCHOR — mobile-security INFO fix.
        //
        // Every other assertion in this test is a `findsNothing`, and three
        // `findsNothing`s also pass on a screen that rendered NOTHING: a
        // fixture that stopped deserializing, a repository fake that never
        // completed, a route that silently landed on the error state. This
        // test would then go quietly, permanently vacuous while staying green
        // — which is exactly the failure mode this group's header calls out as
        // how the taxonomy-street bug hid behind "98/98 green". Guarding
        // against it inside a group written to catch it is the whole point.
        //
        // `salon-profile-name` is the anchor rather than the
        // `salon-profile-hero-card` shell key because it is strictly stronger:
        // the card mounts as a container, but the NAME only paints once the
        // repository resolved, the notifier delivered data, and the hero card
        // read fields off that salon. Asserting its rendered `data` (not just
        // the key's presence) is what proves the PAYLOAD arrived — a hero card
        // built from a different or empty salon would still satisfy the key
        // alone. Same widget, same build path, same `salon` object the address
        // lines below are derived from, so if the name is on screen the
        // absence of the address rows is a real result and not an artefact.
        final nameFinder = find.byKey(const Key('salon-profile-name'));
        expect(
          nameFinder,
          findsOneWidget,
          reason:
              'the hero card never rendered — the three findsNothing '
              'assertions below would pass vacuously',
        );
        // i18n-finder-ok: salon.name fixture value, not localised UI copy.
        expect(tester.widget<Text>(nameFinder).data, 'Салон «Вельвет»');

        expect(
          find.byKey(const Key('salon-profile-locality-text')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-profile-address-text')),
          findsNothing,
        );
        expect(
          find.byIcon(Icons.location_on_outlined),
          findsNothing,
          reason:
              'no visible address data anywhere — the pin must not render on '
              'its own',
        );
      },
    );

    testWidgets(
      'surrounding whitespace is trimmed off the rendered lines, so a '
      'padded city never reads as «Київ » beside its street row',
      (tester) async {
        await _pumpTall(tester);
        const paddedSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          cityId: 'city-uuid-1',
          street: '  вул. Хрещатик ',
          buildingNo: ' 22 ',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => paddedSalon),
          ),
        );
        await tester.pumpAndSettle();

        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final String? rendered = tester.widget<Text>(addressFinder).data;
        expect(rendered, 'вул. Хрещатик, 22');
        expect(rendered, isNot(contains('  ')));
        expect(rendered?.trim(), rendered);
      },
    );
  });

  // Regression (user-reported): the location line used to start flush at
  // the hero card's left edge, directly under the [SalonLogo] avatar —
  // reading as "under the image" instead of a continuation of the identity
  // block. It now carries a leading `SizedBox(width: _logoDiameter +
  // VelvetSpacing.md)` so its icon lines up with the rating row's icon,
  // both of which sit in the `Expanded` column to the right of the logo.
  // The two rows (outer name/rating Row and the location Row) are direct
  // siblings in the same `crossAxisAlignment: CrossAxisAlignment.start`
  // Column, so their content starts at the same local x — this asserts
  // that shared coordinate space actually lines up in the rendered tree,
  // not just that the indentation constant matches the logo diameter on
  // paper.
  group('location line horizontal alignment', () {
    testWidgets(
      'address row icon aligns with the rating row icon, clear of the logo',
      (tester) async {
        await _pumpTall(tester);
        const salonWithLocation = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          cityId: 'city-uuid-1',
          street: 'вул. Хрещатик',
          buildingNo: '22',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => salonWithLocation),
          ),
        );
        await tester.pumpAndSettle();

        final Finder heroCard = find.byKey(
          const Key('salon-profile-hero-card'),
        );
        final Finder logoFinder = find.byType(SalonLogo);
        final Finder ratingIcon = find.descendant(
          of: heroCard,
          matching: find.byIcon(Icons.star_rounded),
        );
        final Finder locationIcon = find.descendant(
          of: heroCard,
          matching: find.byIcon(Icons.location_on_outlined),
        );
        expect(logoFinder, findsOneWidget);
        expect(ratingIcon, findsOneWidget);
        expect(locationIcon, findsOneWidget);

        final double logoLeft = tester.getTopLeft(logoFinder).dx;
        final double ratingIconLeft = tester.getTopLeft(ratingIcon).dx;
        final double locationIconLeft = tester.getTopLeft(locationIcon).dx;

        expect(
          locationIconLeft,
          closeTo(ratingIconLeft, 0.5),
          reason:
              'the location icon must land at the SAME horizontal offset '
              'as the rating row\'s star icon — both rows are indented by '
              'exactly `_logoDiameter + VelvetSpacing.md` from the hero '
              'card\'s content edge, so their icons must line up pixel-for'
              '-pixel in the rendered tree.',
        );
        expect(
          locationIconLeft - logoLeft,
          greaterThan(60),
          reason:
              'the location icon must be clearly indented past the logo '
              '(regression guard: it used to start flush at the logo\'s '
              'left edge, i.e. locationIconLeft ≈ logoLeft, reading as '
              '"under the image" instead of "under the rating").',
        );
      },
    );
  });

  // Regression: the location line briefly shared the rating row as a
  // `Flexible` sibling (commit 74e2e16), which removed an entire content
  // block from the hero card and shrank its natural height below
  // `_heroProtrusion` (116px) — flipping the hero card from *overlapping*
  // the cover's bottom border to sitting in a *gap* underneath it. Restored:
  // the location renders on its own row, tightly stacked under the rating
  // row (see the `location line` group above for its content/visibility
  // assertions).
  //
  // This group asserts the actual geometric property that silently flipped
  // sign in 74e2e16 — real pixel overlap between the hero card's top edge
  // and the cover photo's bottom edge — rather than a structural "shares a
  // Row" check (which is exactly what let the regression ship unnoticed:
  // the merged layout could satisfy a structural check while still being
  // too short to protrude).
  group('hero card protrudes into the cover', () {
    testWidgets(
      'hero card top edge overlaps the cover photo bottom edge (real pixel '
      'overlap, not just proximity)',
      (tester) async {
        await _pumpTall(tester);
        const salonWithLocation = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          cityId: 'city-uuid-1',
          street: 'вул. Хрещатик',
          buildingNo: '22',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => salonWithLocation),
          ),
        );
        await tester.pumpAndSettle();

        final Finder coverFinder = find.byType(SalonCover);
        final Finder heroFinder = find.byKey(
          const Key('salon-profile-hero-card'),
        );
        expect(coverFinder, findsOneWidget);
        expect(heroFinder, findsOneWidget);

        final double coverBottomY = tester.getBottomLeft(coverFinder).dy;
        final double heroTopY = tester.getTopLeft(heroFinder).dy;

        expect(
          heroTopY,
          lessThan(coverBottomY),
          reason:
              'the hero card must protrude into the cover photo — its top '
              'edge must sit ABOVE the cover\'s bottom edge (strict pixel '
              'overlap). If this fails, the hero card content shrank below '
              'the `_heroProtrusion` (116px) budget again, the way it did '
              'when the location line was merged into the rating row '
              '(commit 74e2e16) and removed an entire content row from the '
              'card.',
        );
      },
    );
  });

  // ── mobile-qa gap fill: the exact `_cardCoverOverlap` (25px) invariant ────
  //
  // The group above only asserts SOME overlap exists (`heroTopY <
  // coverBottomY`) — it would pass even if the overlap magnitude drifted
  // with content height, which is precisely the bug Phase 224 fixed (the
  // OLD content-driven formula grew the overlap itself as the card grew,
  // eventually pushing the card over the back/favourite buttons). This
  // group pins the actual invariant described in `_CoverAndHero`'s class
  // doc: the overlap is a FIXED constant, byte-for-byte identical
  // regardless of how tall the card's content makes it — from a bare
  // minimal card up through a 2-line name + full address + an EXPANDED
  // 1000-char locationNote.
  group('hero card overlap is a fixed constant, independent of content '
      'height', () {
    /// Cover bottom edge Y minus hero card top edge Y, in logical pixels —
    /// the actual protrusion depth, not just "is there some overlap".
    double overlapPx(WidgetTester tester) {
      final double coverBottomY = tester
          .getBottomLeft(find.byType(SalonCover))
          .dy;
      final double heroTopY = tester
          .getTopLeft(find.byKey(const Key('salon-profile-hero-card')))
          .dy;
      return coverBottomY - heroTopY;
    }

    testWidgets(
      'a minimal-content salon (no address, no note) overlaps by exactly '
      '25px',
      (tester) async {
        await _pumpTall(tester);
        const minimalSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => minimalSalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          overlapPx(tester),
          moreOrLessEquals(25, epsilon: 0.5),
          reason:
              'the hero card must protrude into the cover by exactly the '
              '`_CoverAndHero._cardCoverOverlap` constant (25px), not some '
              'content-derived amount',
        );
      },
    );

    testWidgets(
      'worst-case collapsed content (2-line name + 2-line address + a '
      'locationNote) overlaps by the SAME exact 25px as the minimal card',
      (tester) async {
        const String longName =
            'Салон краси «Незабутня Досконалість Стилю та Гармонії»';
        const worstCaseSalon = Salon(
          id: _kSalonId,
          name: longName,
          description: 'Затишний салон краси в серці Печерська.',
          cityId: 'city-uuid-1',
          street: 'вул. Велика Васильківська',
          buildingNo: '44/2',
          locationNote: 'вхід з двору, 2 поверх, домофон 12',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => worstCaseSalon),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        expect(
          overlapPx(tester),
          moreOrLessEquals(25, epsilon: 0.5),
          reason:
              'the overlap must stay pinned at exactly 25px even though '
              "this card's content is far taller than the minimal case — "
              'if this drifts, the old content-driven overlap formula (or '
              'something equivalent) has crept back in',
        );
      },
    );

    testWidgets(
      'the overlap stays exactly 25px even with a 1000-char locationNote '
      'EXPANDED — the tallest the card can ever get',
      (tester) async {
        await _pumpTall(tester);
        final String longNote = ('Вхід у двір з боку вулиці Хрещатик. ' * 30)
            .substring(0, 1000);
        final Salon salon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          locationNote: longNote,
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => salon),
          ),
        );
        await tester.pumpAndSettle();

        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(
          overlapPx(tester),
          moreOrLessEquals(25, epsilon: 0.5),
          reason:
              'expanding the note grows the card by several hundred px — '
              'the overlap must remain exactly 25px regardless, because the '
              'cover is `Positioned` to its own fixed `coverHeight` '
              "independent of the card's size (see `_CoverAndHero`'s class "
              'doc)',
        );
      },
    );
  });

  // Regression pin: the "Обкладинка" cover-edit pill (the small camel pill
  // that used to float over the cover's top control row) was removed
  // outright — the cover is read-only chrome with no owner-edit affordance
  // yet. This asserts the pill never renders, so a future change can't
  // silently reintroduce it.
  group('cover edit pill removal', () {
    testWidgets('cover edit pill no longer renders', (tester) async {
      const String longName =
          'Салон краси «Незабутня Досконалість Стилю та Гармонії»';
      const worstCaseSalon = Salon(
        id: _kSalonId,
        name: longName,
        description: 'Затишний салон краси в серці Печерська.',
        cityId: 'city-uuid-1',
        street: 'вул. Велика Васильківська',
        buildingNo: '44/2',
        locationNote: 'вхід з двору, 2 поверх, домофон 12',
        avgRating: 4.9,
        reviewCount: 128,
      );

      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(salon: () async => worstCaseSalon),
        ),
        width: 390,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-cover-edit-pill')), findsNothing);
      expect(find.byKey(const Key('salon-profile-hero-card')), findsOneWidget);
    });
  });

  // ── mobile-qa regression pin: the actual bug Phase 223 (b) fixed, still
  // relevant now that Phase 224 moved `locationNote` back onto the hero
  // card ────────────────────────────────────────────────────────────────
  //
  // Pre-223(b), `_buildLocationLine` joined street + buildingNo + locationNote
  // into ONE string clamped to `maxLines: 2`, so a long note could push the
  // street address itself out of the visible budget — losing the address, not
  // just the note. Phase 224 re-introduces `locationNote` on the hero card,
  // but as its OWN `ExpandableNote` below the address lines — never
  // concatenated onto them (see `_SalonHeroCard._streetLine`'s doc) — so the
  // same failure mode can no longer recur. This directly pins that at the
  // widget tier (the integration tier's `public_salon_profile_flow_test.dart`
  // pins the same regression through a REAL wire response): with a
  // 1000-char locationNote set, the hero must still show BOTH the locality
  // line and the street line, AND the (collapsed, clamped) note itself.
  group('locationNote never evicts the hero address (Phase 223 (b) / 224 '
      'regression pin)', () {
    testWidgets(
      'a 1000-char locationNote still leaves BOTH the locality line and the '
      'street/building line visible, alongside the (collapsed) note',
      (tester) async {
        await _pumpTall(tester);
        final String longNote = ('Вхід у двір з боку вулиці Хрещатик. ' * 30)
            .substring(0, 1000);
        final Salon salon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          locationNote: longNote,
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => salon),
          ),
        );
        await tester.pumpAndSettle();

        final Finder localityFinder = find.byKey(
          const Key('salon-profile-locality-text'),
        );
        final Finder addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(
          localityFinder,
          findsOneWidget,
          reason: 'a 1000-char locationNote must not evict the locality line',
        );
        expect(
          addressFinder,
          findsOneWidget,
          reason: 'a 1000-char locationNote must not evict the street line',
        );
        final Text localityWidget = tester.widget<Text>(localityFinder);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(localityWidget.data, 'Київ');
        expect(addressWidget.data, contains('вул. Велика Васильківська, 44'));
        // Phase 224 — the note now DOES render on the hero card, as its own
        // `ExpandableNote` (clamped to 3 lines when collapsed), never merged
        // into the address lines above.
        final Finder heroCard = find.byKey(
          const Key('salon-profile-hero-card'),
        );
        expect(
          find.descendant(
            of: heroCard,
            matching: find.byKey(const Key('salon-profile-location-note')),
          ),
          findsOneWidget,
          reason:
              'a locationNote must render on the hero card as its own '
              'ExpandableNote, alongside (never instead of) the address '
              'lines',
        );
      },
    );
  });

  // ── mobile-security LOW fix: hero card — locationNote / ExpandableNote ────
  //
  // Phase 223 (b) moved `locationNote` off the hero card onto the About
  // tab's «Як дістатись» section; Phase 224 moved it back onto the hero
  // card (per user feedback — the About tab's separate section was
  // confusing, and the note reads better as part of the salon's full
  // location, right under the street line). This group covers that render
  // site directly: presence/absence of the note by `locationNote` state
  // (including a note with NO street/locality at all — the hero card must
  // still show it), the expand/collapse interaction, and the bidi/RLO
  // sanitize contract at this specific call site (a second, distinct
  // consumer of `ExpandableNote`/`sanitizeDisplayText` from the master
  // profile's — see `expandable_note_test.dart` /
  // `sanitize_display_text_test.dart` for the widget/util-level exhaustive
  // coverage this pins the WIRING of, on THIS screen's actual Row/Column
  // tree).
  group('hero card — location note', () {
    testWidgets(
      'a non-empty locationNote renders as an ExpandableNote on the hero '
      'card (sanitized text), even with no street/locality on file',
      (tester) async {
        await _pumpTall(tester);
        const noteSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          locationNote: 'кв. 3, 2 поверх',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => noteSalon),
          ),
        );
        await tester.pumpAndSettle();

        final Finder heroCard = find.byKey(
          const Key('salon-profile-hero-card'),
        );
        expect(
          find.descendant(
            of: heroCard,
            matching: find.byKey(const Key('salon-profile-location-note')),
          ),
          findsOneWidget,
          reason:
              'a locationNote must render on the hero card even for a '
              'salon with no street/locality at all — it must never be '
              'silently dropped for lack of an address to sit under',
        );
        // i18n-finder-ok: locationNote fixture data, not UI copy.
        expect(find.text('кв. 3, 2 поверх'), findsOneWidget);
      },
    );

    // ── mobile-qa gap fill: explicit relocation guard ──────────────────────
    //
    // Phase 224 DELETED the About tab's «Як дістатись» section rather than
    // merely hiding it, so today this can't literally render in both
    // places — but a naive future edit (e.g. a partial revert, or someone
    // re-adding an About-tab summary of "salon info" that innocently
    // includes the note again) would only be caught if some test actually
    // asserts the ABSENCE, not just the presence, on the new site. The
    // other tests in this group use unscoped `find.text(note)` /
    // `find.byKey(locationNoteKey)` calls that would incidentally also
    // catch a duplicate (Keys only need to be unique among siblings, not
    // globally, so a stray second widget with the same key would not throw
    // — it would just make `findsOneWidget` fail with 2 matches) — but that
    // guard is accidental, not documented anywhere, and a future author
    // scoping those finders down to `find.descendant(of: heroCard, ...)`
    // (as several neighbouring tests already do) would silently lose it.
    // This test makes the invariant explicit and permanent, and proves the
    // About tab is genuinely on-screen (not skipped) while checking it.
    testWidgets(
      'a locationNote renders on the hero card and NOWHERE else on screen '
      '— specifically not duplicated onto the About tab',
      (tester) async {
        await _pumpTall(tester);
        const noteSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          locationNote: 'кв. 3, 2 поверх',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => noteSalon),
          ),
        );
        await tester.pumpAndSettle();

        // The default tab is «Про салон» (About) — confirm it's genuinely
        // rendered alongside the hero card, so the absence check below
        // means something (it isn't vacuously true because the tab body
        // never mounted).
        expect(
          find.byKey(const Key('salon-about-text')),
          findsOneWidget,
          reason:
              'the About tab must be on-screen for the absence check below '
              'to be meaningful',
        );

        // Exactly ONE widget anywhere in the tree carries the note's key —
        // not one inside the hero card plus a second, differently-scoped
        // one elsewhere.
        expect(
          find.byKey(const Key('salon-profile-location-note')),
          findsOneWidget,
          reason:
              'the locationNote key must appear exactly once in the whole '
              'tree, not once on the hero card and again on the About tab',
        );
        // Exactly ONE occurrence of the note's own text anywhere on screen
        // — a duplicate render under a DIFFERENT key/widget (e.g. a plain
        // Text instead of ExpandableNote) would slip past the key check
        // above but not this one.
        // i18n-finder-ok: locationNote fixture data, not UI copy.
        expect(find.text('кв. 3, 2 поверх'), findsOneWidget);
      },
    );

    testWidgets('locationNote null → no note row renders', (tester) async {
      await _pumpTall(tester);
      const noNoteSalon = Salon(
        id: _kSalonId,
        name: 'Салон «Вельвет»',
        description: 'Затишний салон краси в серці Печерська.',
        avgRating: 4.9,
        reviewCount: 128,
      );
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(salon: () async => noNoteSalon),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-profile-location-note')),
        findsNothing,
      );
    });

    testWidgets('locationNote blank ("") → no note row renders', (
      tester,
    ) async {
      await _pumpTall(tester);
      const blankNoteSalon = Salon(
        id: _kSalonId,
        name: 'Салон «Вельвет»',
        description: 'Затишний салон краси в серці Печерська.',
        locationNote: '',
        avgRating: 4.9,
        reviewCount: 128,
      );
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(salon: () async => blankNoteSalon),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-profile-location-note')),
        findsNothing,
      );
    });

    testWidgets(
      'a SHORT locationNote (fits within maxLines: 3) shows NO expand '
      'affordance',
      (tester) async {
        await _pumpTall(tester);
        const shortNoteSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          locationNote: 'кв. 3, 2 поверх',
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => shortNoteSalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('expandable-note-toggle')),
          findsNothing,
          reason:
              'an inert toggle on a note that already fits is a small lie — '
              'it must not render at all',
        );
      },
    );

    testWidgets(
      'a LONG locationNote (overflows maxLines: 3) shows the affordance; '
      'tapping it reveals the full text and flips the label; tapping again '
      're-collapses it',
      (tester) async {
        const String longNote =
            'Вхід у двір з боку вулиці Хрещатик, повз кав\'ярню на розі — не '
            'плутайте з сусіднім під\'їздом, там кодовий замок не працює. '
            'Тримайтеся правої стіни, минаєте дитячий майданчик, підіймаєтесь '
            'трьома сходинками до скляних дверей із синьою наклейкою. '
            'Домофон код 45В, дзвоніть двічі коротко. Якщо домофон не '
            'відповідає — телефонуйте адміністратору, номер вказано на '
            'вивісці біля дверей.';
        const longNoteSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          locationNote: longNote,
          avgRating: 4.9,
          reviewCount: 128,
        );
        // Constrained to a narrow phone width (unlike the sibling `_pumpTall`
        // tests above): the About tab's note column spans nearly the FULL
        // screen width, so this ~430-char fixture (calibrated to overflow a
        // narrow 140dp identity-card column in `expandable_note_test.dart`)
        // needs a narrow surface here too to genuinely exceed the 3-line
        // clamp — at the default 800dp width it comfortably fits in 3 lines.
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => longNoteSalon),
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        expect(toggle, findsOneWidget);
        expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);

        final Size collapsedSize = tester.getSize(find.text(longNote));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
        final Size expandedSize = tester.getSize(find.text(longNote));
        expect(
          expandedSize.height,
          greaterThan(collapsedSize.height),
          reason: 'expanding must grow the note to its FULL untruncated height',
        );

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
        final Size reCollapsedSize = tester.getSize(find.text(longNote));
        expect(
          reCollapsedSize.height,
          moreOrLessEquals(collapsedSize.height, epsilon: 0.5),
        );
      },
    );

    testWidgets(
      'a locationNote containing a RLO (U+202E) override renders with the '
      'control character stripped, not the raw payload',
      (tester) async {
        await _pumpTall(tester);
        // U+202E = Right-to-Left Override. Backend validation on
        // `locationNote` is `@Size(max = 1000)` only — no character-class
        // check — so a hostile salon owner could push this into a
        // client-facing note. Built via `String.fromCharCode` (rather than a
        // literal character in this source file) so this test file never
        // embeds the raw control byte it exists to strip.
        final String rlo = String.fromCharCode(0x202E);
        final String rawNote = 'кв. 3$rlo, 2 поверх';
        const String sanitizedNote = 'кв. 3, 2 поверх';
        final Salon rloSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          locationNote: rawNote,
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => rloSalon),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(sanitizedNote),
          findsOneWidget,
          reason: 'the rendered Text must carry the SANITIZED string',
        );
        expect(
          find.text(rawNote),
          findsNothing,
          reason:
              'the raw string (with the RLO control char) must never reach '
              'the Text widget',
        );
      },
    );
  });

  group('error state', () {
    testWidgets('renders ErrorState with a working retry', (tester) async {
      await _pumpTall(tester);
      var attempt = 0;
      // Overrides [publicSalonProfileProvider] directly (bypassing
      // [salonRepositoryProvider]) — mirrors PublicMasterProfileScreen's error-
      // state test. Routing the failure through the repository fake instead
      // races [authProvider]'s own async `build()` (Loading → Data), which
      // rebuilds this family provider mid-flight and disposes the in-flight
      // read before the widget observes the error.
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: <Object>[
          authProvider.overrideWith(_StubAuthNotifier.new),
          favoriteRepositoryProvider.overrideWithValue(
            _FakeFavoriteRepository(),
          ),
          publicSalonProfileProvider(_kSalonId).overrideWith((ref) async {
            attempt++;
            if (attempt == 1) throw const NetworkFailure();
            return (_stubSalon, _stubMasters);
          }),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('salon-profile-name')), findsNothing);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);
    });
  });

  group('favourite toggle', () {
    testWidgets('idempotent tap: favorite → unfavorite', (tester) async {
      await _pumpTall(tester);
      final fav = _FakeFavoriteRepository();
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(fav: fav),
      );
      await tester.pumpAndSettle();

      final heart = find.byKey(const Key('salon-favorite-toggle'));
      expect(heart, findsOneWidget);

      await tester.tap(heart);
      await tester.pumpAndSettle();
      expect(fav.calls, <String>['add:$_kSalonId']);

      await tester.tap(heart);
      await tester.pumpAndSettle();
      expect(fav.calls, <String>['add:$_kSalonId', 'remove:$_kSalonId']);
    });
  });

  group('masters tab', () {
    // Regression: the tab used to render a "Майстри салону" heading + a
    // "(N)" count above the grid. Both were removed — the grid now starts
    // directly, no label above it.
    testWidgets('renders no "Майстри салону" heading or count above the grid', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      // Regression guard: pinning the exact removed literal is the point of
      // this assertion (the heading was deleted from the tab).
      // i18n-finder-ok: pinning the exact removed literal is the point.
      expect(find.text('Майстри салону'), findsNothing);
      expect(
        find.text('${_stubMasters.length}'),
        findsNothing,
        reason:
            'the roster count that used to sit beside the heading '
            'must also be gone',
      );
      expect(
        find.byKey(const Key('salon-master-card-master-1')),
        findsOneWidget,
        reason: 'the grid itself must still render',
      );
    });

    testWidgets('master card navigates to /masters/:masterId', (tester) async {
      await _pumpTall(tester);
      final router = GoRouter(
        initialLocation: '/salons/$_kSalonId',
        routes: <RouteBase>[
          GoRoute(
            path: '/salons/:salonId',
            builder: (context, state) => PublicSalonProfileScreen(
              salonId: state.pathParameters['salonId']!,
            ),
          ),
          GoRoute(
            path: '/masters/:masterId',
            builder: (_, state) => Scaffold(
              body: Text('master-${state.pathParameters['masterId']}'),
            ),
          ),
        ],
      );

      await tester.pumpRoutedApp(router, overrides: _overrides());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('salon-master-card-master-1'));
      expect(card, findsOneWidget);

      // Regression guard: the salon master card's corner «book» affordance
      // (key `salon-master-card-book-<id>`, `Icons.event_available_rounded`)
      // was intentionally removed — masters are booked via card→profile→book
      // or the salon-wide CTA. Pin its ABSENCE so an accidental re-introduction
      // of the deleted icon fails here rather than silently returning.
      expect(
        find.byKey(const Key('salon-master-card-book-master-1')),
        findsNothing,
      );

      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.text('master-master-1'), findsOneWidget);
    });

    testWidgets('empty masters list shows the empty state', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(masters: () async => const []),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-masters-empty')), findsOneWidget);
    });

    // ── Card-shrink regression (mobile-backlog INFO) ───────────────────────
    //
    // The rail card was shrunk (width 148->132, height 214->190, avatar
    // 64->56) alongside the tab-bar font fix. [_stubMasters] only ever
    // exercised a short name + [MasterType.independentMaster] (whose role
    // label, "Незалежний майстер", already wraps to 2 lines — the worst case
    // [kSalonMasterCardHeight]'s doc comment budgets for), never together
    // with a long name that forces the name's own ellipsis path. This test
    // stresses both at once against the new, tighter height and asserts:
    //   (a) no RenderFlex overflow is thrown (takeException == null), and
    //   (b) the name still renders single-line + ellipsized rather than
    //       silently wrapping into the role's vertical budget.
    //
    // Pumped at a narrow 320dp width (below the ~360-430dp typical-phone
    // range) rather than [_pumpTall]'s 800dp: since the masters tab became a
    // 2-column grid, each card's column width is now derived from the
    // available screen width (no more fixed 132dp rail card), so a wide test
    // viewport would give each card a much ROOMIER column than the original
    // rail ever had — silently defeating this test's "worst case" (long name
    // + role wrapped to 2 lines) by giving the role enough room to fit on one
    // line. 320dp keeps the column at least as tight as the original 132dp
    // rail card, preserving (and slightly exceeding) the original stress.
    //
    // The salon master card now renders the FIRST NAME ONLY (surname omitted —
    // see `_MastersTab`'s itemBuilder). To keep exercising the name's own
    // ellipsis path, the stress lives in a long single GIVEN name here
    // (`longName` == the fixture's `firstName`); `lastName` stays a real
    // surname that must never reach the rendered card.
    testWidgets(
      'long first name + 2-line-wrapped role does not overflow the shrunk card',
      (tester) async {
        const String longName = 'Олександрина-Емілія';
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => const <SalonMasterSummary>[
                SalonMasterSummary(
                  masterId: 'master-long',
                  firstName: longName,
                  lastName: 'Верещагіна-Задорожня',
                  avgRating: 4.8,
                  reviewCount: 5,
                  type: MasterType.independentMaster,
                ),
              ],
            ),
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the shrunk SalonMasterCard must not overflow for a long name '
              'combined with the worst-case wrapped role label',
        );

        final card = find.byKey(const Key('salon-master-card-master-long'));
        expect(card, findsOneWidget);

        final Text nameText = tester.widget<Text>(find.text(longName));
        expect(nameText.maxLines, 1, reason: 'name must be single-line');
        expect(
          nameText.overflow,
          TextOverflow.ellipsis,
          reason: 'name must ellipsize, not wrap into the role\'s budget',
        );
      },
    );

    // ── Surname-omission regression (the guard) ─────────────────────────────
    //
    // The salon master card was changed to render the FIRST NAME ONLY —
    // `_MastersTab`'s itemBuilder now passes `name: master.firstName` rather
    // than the old `'${master.firstName} ${master.lastName}'.trim()`. This
    // guards that contract directly: given a master with a distinct first name
    // AND a distinct surname, the card shows the first name and NEVER the
    // surname (neither alone nor as part of a combined "first last" label).
    // Re-adding the surname to the card would fail this test.
    testWidgets('master card shows first name only, never the surname', (
      tester,
    ) async {
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(
            masters: () async => const <SalonMasterSummary>[
              SalonMasterSummary(
                masterId: 'master-name',
                firstName: 'Тарас',
                lastName: 'Шевченко',
                avgRating: 4.9,
                reviewCount: 7,
                type: MasterType.independentMaster,
              ),
            ],
          ),
        ),
        width: 390,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      final Finder card = find.byKey(
        const Key('salon-master-card-master-name'),
      );
      expect(card, findsOneWidget);

      expect(
        // i18n-finder-ok: 'Тарас' is fixture data, not UI copy.
        find.descendant(of: card, matching: find.text('Тарас')),
        findsOneWidget,
        reason: 'the card must render the master first name',
      );
      expect(
        find.textContaining('Шевченко'),
        findsNothing,
        reason: 'the surname must never reach the salon master card',
      );
      expect(
        // i18n-finder-ok: fixture master's first+last name, not UI copy.
        find.text('Тарас Шевченко'),
        findsNothing,
        reason: 'the old combined "first last" label must not reappear',
      );
    });

    // ── Vertical 2-column grid regression ───────────────────────────────
    //
    // The masters tab used to be a single horizontally-scrolling rail (one
    // row, N columns, scrollDirection: Axis.horizontal). It is now a
    // vertically-scrolling 2-column grid. Pumped at 390dp — a typical modern
    // phone width — with 4 fixture masters (2 full rows), this asserts BOTH:
    //   (a) the grid delegate is genuinely configured for 2 columns, and
    //   (b) the rendered cards actually land 2-per-row (same top edge for
    //       A/B, C starting a new row strictly below rather than scrolled
    //       out to the right, which is what a leftover horizontal rail would
    //       still produce).
    testWidgets('masters render as a vertical 2-column grid', (tester) async {
      const List<SalonMasterSummary> fourMasters = <SalonMasterSummary>[
        SalonMasterSummary(
          masterId: 'master-a',
          firstName: 'Анна',
          lastName: 'А.',
          avgRating: 4.9,
          reviewCount: 3,
          type: MasterType.independentMaster,
        ),
        SalonMasterSummary(
          masterId: 'master-b',
          firstName: 'Богдан',
          lastName: 'Б.',
          avgRating: 4.8,
          reviewCount: 5,
          type: MasterType.independentMaster,
        ),
        SalonMasterSummary(
          masterId: 'master-c',
          firstName: 'Віра',
          lastName: 'В.',
          avgRating: 4.7,
          reviewCount: 2,
          type: MasterType.independentMaster,
        ),
        SalonMasterSummary(
          masterId: 'master-d',
          firstName: 'Дмитро',
          lastName: 'Д.',
          avgRating: 4.6,
          reviewCount: 1,
          type: MasterType.independentMaster,
        ),
      ];

      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(masters: () async => fourMasters),
        ),
        width: 390,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      final GridView grid = tester.widget<GridView>(find.byType(GridView));
      final SliverGridDelegateWithFixedCrossAxisCount delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        2,
        reason:
            'the grid must be configured for 2 columns, not 1 (which '
            'would just be a vertical single-column list) or an unbounded '
            'row count',
      );

      final Offset topLeftA = tester.getTopLeft(
        find.byKey(const Key('salon-master-card-master-a')),
      );
      final Offset topLeftB = tester.getTopLeft(
        find.byKey(const Key('salon-master-card-master-b')),
      );
      final Offset topLeftC = tester.getTopLeft(
        find.byKey(const Key('salon-master-card-master-c')),
      );
      final Offset topLeftD = tester.getTopLeft(
        find.byKey(const Key('salon-master-card-master-d')),
      );

      expect(
        topLeftA.dy,
        topLeftB.dy,
        reason: 'first-row cards A and B must share a top edge',
      );
      expect(
        topLeftA.dx,
        lessThan(topLeftB.dx),
        reason: 'B must sit to the right of A in the first row',
      );
      expect(
        topLeftC.dy,
        greaterThan(topLeftA.dy),
        reason:
            'C must start a NEW row strictly below A/B — a leftover '
            'horizontal rail would instead place C further to the right on '
            'the same row',
      );
      expect(
        topLeftC.dy,
        topLeftD.dy,
        reason: 'second-row cards C and D must share a top edge',
      );
      expect(
        topLeftC.dx,
        topLeftA.dx,
        reason: 'the second row must left-align with the first row',
      );
    });

    // ── Eager-build cap regression (mobile-perf LOW fix) ────────────────────
    //
    // The grid is `shrinkWrap: true` + `NeverScrollableScrollPhysics`
    // (required to embed a grid inside the screen's outer
    // `SingleChildScrollView`), which forces Flutter to eagerly build every
    // child up front to measure the shrink-wrapped height — unlike a lazy
    // viewport-backed sliver. With 8 fixture masters (over
    // `kSalonMastersInitialCount`, 6), this asserts the tab renders only the
    // first 6 cards on first paint plus a "show all" affordance, and that
    // tapping it reveals the rest.
    testWidgets(
      'more than 6 masters renders only the first 6 plus a show-all button, '
      'which reveals the rest on tap',
      (tester) async {
        final List<SalonMasterSummary> eightMasters = List.generate(
          8,
          (i) => SalonMasterSummary(
            masterId: 'master-${i + 1}',
            firstName: 'Майстер',
            lastName: '${i + 1}',
            avgRating: 4.5,
            reviewCount: 1,
            type: MasterType.independentMaster,
          ),
        );

        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => eightMasters),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        for (int i = 1; i <= 6; i++) {
          expect(
            find.byKey(Key('salon-master-card-master-$i')),
            findsOneWidget,
            reason: 'the first 6 masters must render up front',
          );
        }
        for (int i = 7; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-master-$i')),
            findsNothing,
            reason:
                'masters beyond the initial batch of 6 must NOT be built '
                'until the user explicitly reveals them',
          );
        }

        final Finder showAll = find.byKey(const Key('salon-masters-show-all'));
        expect(
          showAll,
          findsOneWidget,
          reason:
              'a show-all affordance must appear when the roster '
              'exceeds the initial batch',
        );

        await tester.tap(showAll);
        await tester.pumpAndSettle();

        for (int i = 1; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-master-$i')),
            findsOneWidget,
            reason: 'all 8 masters must render after tapping show-all',
          );
        }
        expect(
          showAll,
          findsNothing,
          reason:
              'the show-all button must disappear once everything is '
              'revealed',
        );
      },
    );
  });

  // ── Role label: own professionalTitle vs default type role (the guard) ──
  //
  // `_MastersTab`'s itemBuilder derives the card's role line as:
  //   final ownTitle = master.professionalTitle?.trim();
  //   role = (ownTitle != null && ownTitle.isNotEmpty)
  //       ? ownTitle
  //       : _roleLabel(master.type, l10n);
  // i.e. the master's OWN professional title wins when set, falling back to
  // the generic per-type label ("Майстер салону" for a SALON_MASTER) only
  // when it is null or blank. These two tests pin BOTH branches. The role is
  // asserted via `find.descendant(of: card, matching: find.text(...))` so the
  // match is scoped to the specific card's role Text and can never be
  // satisfied by the tab bar, the semantics label, or a sibling card.
  group('master role label', () {
    testWidgets(
      'card renders the master own professionalTitle when set, not the '
      'default type role',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => const <SalonMasterSummary>[
                SalonMasterSummary(
                  masterId: 'master-titled',
                  firstName: 'Ірина',
                  lastName: 'Мороз',
                  professionalTitle: 'Топ-стиліст',
                  avgRating: 4.9,
                  reviewCount: 8,
                  // A SALON_MASTER — whose default label would be
                  // "Майстер салону"; the own title must override it.
                  type: MasterType.salonMaster,
                ),
              ],
            ),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const Key('salon-master-card-master-titled'),
        );
        expect(card, findsOneWidget);

        expect(
          // i18n-finder-ok: 'Топ-стиліст' is fixture data, not UI copy.
          find.descendant(of: card, matching: find.text('Топ-стиліст')),
          findsOneWidget,
          reason:
              'the role line must show the master own professionalTitle '
              'when one is set',
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.masterRoleSalonMaster),
          ),
          findsNothing,
          reason:
              'the generic per-type role ("Майстер салону") must NOT render '
              'once the master has set an own professionalTitle',
        );
      },
    );

    testWidgets(
      'card falls back to the default type role when professionalTitle is '
      'null or blank/whitespace',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => const <SalonMasterSummary>[
                SalonMasterSummary(
                  masterId: 'master-null-title',
                  firstName: 'Оксана',
                  lastName: 'Левченко',
                  // professionalTitle omitted → null.
                  avgRating: 4.7,
                  reviewCount: 4,
                  type: MasterType.salonMaster,
                ),
                SalonMasterSummary(
                  masterId: 'master-blank-title',
                  firstName: 'Наталя',
                  lastName: 'Гриценко',
                  // Whitespace-only → exercises the `.trim()` branch: after
                  // trimming it is empty, so it must still fall back.
                  professionalTitle: '   ',
                  avgRating: 4.6,
                  reviewCount: 2,
                  type: MasterType.salonMaster,
                ),
              ],
            ),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        final Finder nullCard = find.byKey(
          const Key('salon-master-card-master-null-title'),
        );
        final Finder blankCard = find.byKey(
          const Key('salon-master-card-master-blank-title'),
        );
        expect(nullCard, findsOneWidget);
        expect(blankCard, findsOneWidget);

        expect(
          find.descendant(
            of: nullCard,
            matching: find.text(l10n.masterRoleSalonMaster),
          ),
          findsOneWidget,
          reason:
              'a null professionalTitle must fall back to the generic '
              'per-type role label',
        );
        expect(
          find.descendant(
            of: blankCard,
            matching: find.text(l10n.masterRoleSalonMaster),
          ),
          findsOneWidget,
          reason:
              'a whitespace-only professionalTitle must trim to empty and '
              'fall back to the generic per-type role label',
        );
      },
    );
  });

  group('services tab', () {
    testWidgets('renders the category accordion', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-2')));
      await tester.pumpAndSettle();

      // i18n-finder-ok: category label is fixture data, not UI copy
      expect(find.text('Манікюр'), findsOneWidget);
    });

    testWidgets('empty catalogue shows the empty state', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(catalog: () async => const []),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-services-empty')), findsOneWidget);
    });
  });

  group('reviews tab', () {
    testWidgets('renders the rating summary + review card, and the sort sheet '
        're-fetches on a new selection', (tester) async {
      await _pumpTall(tester);
      final repo = _FakeSalonRepository();
      // The sort sheet dismisses itself via `context.pop(option)` (go_router),
      // which resolves `GoRouter.of(context)` — a real router ancestor is
      // required, unlike the plain-`MaterialApp` `pumpApp` used elsewhere in
      // this file. Mirrors the `pumpRoutedApp` precedent above (master card →
      // /masters/:masterId).
      final router = GoRouter(
        initialLocation: '/salons/$_kSalonId',
        routes: <RouteBase>[
          GoRoute(
            path: '/salons/:salonId',
            builder: (context, state) => PublicSalonProfileScreen(
              salonId: state.pathParameters['salonId']!,
            ),
          ),
        ],
      );
      await tester.pumpRoutedApp(router, overrides: _overrides(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-3')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-review-summary-average')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('salon-review-review-1')), findsOneWidget);
      expect(repo.reviewSortCalls, <SalonReviewSort>[SalonReviewSort.newest]);

      await tester.tap(find.byKey(const Key('salon-reviews-sort-button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          Key('salon-review-sort-option-${SalonReviewSort.highest.name}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.reviewSortCalls, <SalonReviewSort>[
        SalonReviewSort.newest,
        SalonReviewSort.highest,
      ]);
    });

    testWidgets('empty reviews shows the empty state', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(
            summary: () async => const SalonReviewSummary(),
            reviews: (_) async => const <SalonReviewItem>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-reviews-empty')), findsOneWidget);
    });

    group('service sub-line (backend serviceName)', () {
      // Mirrors the master screen's `_masterReviewCard` coverage
      // (master_received_reviews_screen_test.dart): one item per branch of
      // `_salonReviewCard`'s `service != null && service.isNotEmpty` guard —
      // present, null, empty. The label («послуга:») was dropped from BOTH
      // surfaces in the same change; this pins the salon side renders the
      // bare name with no label and that null/empty never leave a stray
      // `Icons.spa_outlined` row.
      final List<SalonReviewItem> serviceItems = <SalonReviewItem>[
        SalonReviewItem(
          id: 'review-svc-present',
          masterId: 'master-1',
          masterName: 'Олена Ковальчук',
          clientDisplayName: 'Марта Л.',
          serviceName: 'Манікюр',
          rating: 5,
          comment: 'Чудово!',
          createdAt: _fixedNow.subtract(const Duration(days: 1)),
        ),
        SalonReviewItem(
          id: 'review-svc-null',
          masterId: 'master-1',
          masterName: 'Олена Ковальчук',
          clientDisplayName: 'Дарʼя П.',
          rating: 4,
          comment: 'Добре.',
          createdAt: _fixedNow.subtract(const Duration(days: 2)),
        ),
        SalonReviewItem(
          id: 'review-svc-empty',
          masterId: 'master-1',
          masterName: 'Олена Ковальчук',
          clientDisplayName: 'Софія Н.',
          serviceName: '',
          rating: 3,
          comment: 'Норм.',
          createdAt: _fixedNow.subtract(const Duration(days: 3)),
        ),
      ];

      Future<void> pumpServiceItems(WidgetTester tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(reviews: (_) async => serviceItems),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-3')));
        await tester.pumpAndSettle();
      }

      testWidgets('renders the service-name sub-line, unlabelled, when '
          'serviceName is present', (tester) async {
        await pumpServiceItems(tester);

        final Finder card = find.byKey(
          const Key('salon-review-review-svc-present'),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            // i18n-finder-ok: 'Манікюр' is fixture service-name data, not translated UI copy
            matching: find.text('Манікюр'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.byIcon(Icons.spa_outlined)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('послуга')),
          findsNothing,
        );
      });

      testWidgets('omits the sub-line entirely when serviceName is null', (
        tester,
      ) async {
        await pumpServiceItems(tester);

        final Finder card = find.byKey(
          const Key('salon-review-review-svc-null'),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.byIcon(Icons.spa_outlined)),
          findsNothing,
        );
      });

      testWidgets(
        'omits the sub-line when serviceName is an empty string (guards '
        'non-null AND non-empty — never a stray icon/row with no name)',
        (tester) async {
          await pumpServiceItems(tester);

          final Finder card = find.byKey(
            const Key('salon-review-review-svc-empty'),
          );
          expect(card, findsOneWidget);
          expect(
            find.descendant(
              of: card,
              matching: find.byIcon(Icons.spa_outlined),
            ),
            findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.textContaining('послуга')),
            findsNothing,
          );
        },
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Salon-service → masters FILTER (the feature under test).
  //
  // Tapping a service row in the "Послуги" tab selects it as the active
  // filter and jumps to "Майстри", where the grid is narrowed to only the
  // masters whose coverage map contains that service's catalog id. The
  // coverage itself comes from `salonMasterServiceCoverageProvider` (the Phase
  // 14.13 fan-out) — overridden DIRECTLY here with a fake map so these tests
  // never touch the real per-master `GET /masters/{id}/services` fan-out (the
  // real wire path is proven end-to-end by the integration flow).
  //
  // Fixture: three masters + a one-service catalogue (`svc-1`). The coverage
  // map deliberately covers master-1 and master-3 for `svc-1` but NOT
  // master-2 (it carries a different service id), so filtering by `svc-1`
  // must HIDE master-2.
  // ─────────────────────────────────────────────────────────────────────────
  group('salon-service → masters filter', () {
    const List<SalonMasterSummary> filterMasters = <SalonMasterSummary>[
      SalonMasterSummary(
        masterId: 'master-1',
        firstName: 'Олена',
        lastName: 'Ковальчук',
        avgRating: 4.9,
        reviewCount: 12,
        type: MasterType.salonMaster,
      ),
      SalonMasterSummary(
        masterId: 'master-2',
        firstName: 'Богдан',
        lastName: 'Мороз',
        avgRating: 4.7,
        reviewCount: 4,
        type: MasterType.salonMaster,
      ),
      SalonMasterSummary(
        masterId: 'master-3',
        firstName: 'Віра',
        lastName: 'Литвин',
        avgRating: 4.8,
        reviewCount: 8,
        type: MasterType.salonMaster,
      ),
    ];

    // Coverage: master-1 + master-3 perform svc-1; master-2 performs a
    // DIFFERENT service only (present in the map but not covering svc-1) — so
    // `coverage[master-2]?.containsKey('svc-1')` is false and it is filtered
    // out.
    Object coverageOverride(Map<String, Map<String, String>> map) =>
        salonMasterServiceCoverageProvider(
          const SalonBookingMasterSelectionArgs(
            salonId: _kSalonId,
            selectedServiceIds: <String>['svc-1'],
          ),
        ).overrideWith((ref) async => map);

    const Map<String, Map<String, String>> svc1Coverage =
        <String, Map<String, String>>{
          'master-1': <String, String>{'svc-1': 'assign-1'},
          'master-2': <String, String>{'svc-other': 'assign-2'},
          'master-3': <String, String>{'svc-1': 'assign-3'},
        };

    // Drives the shared "open Послуги → tap svc-1 row → land on the filtered
    // Майстри tab" preamble every test below shares. Leaves the tree settled
    // on the Майстри tab with the filter active.
    Future<void> selectSvc1(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('salon-tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('salon-service-row-svc-1')));
      await tester.pumpAndSettle();
    }

    // Builds [n] salon masters (masterId perf-1..perf-n) that ALL perform
    // svc-1, plus the matching coverage map. Shared by the show-all cap-leak
    // regression tests below so their bodies stay focused on the interaction.
    (List<SalonMasterSummary>, Map<String, Map<String, String>>) svc1Performers(
      int n,
    ) {
      final List<SalonMasterSummary> performers = List.generate(
        n,
        (i) => SalonMasterSummary(
          masterId: 'perf-${i + 1}',
          firstName: 'Майстер',
          lastName: '${i + 1}',
          avgRating: 4.5,
          reviewCount: 1,
          type: MasterType.salonMaster,
        ),
      );
      final Map<String, Map<String, String>> cover =
          <String, Map<String, String>>{
            for (final SalonMasterSummary m in performers)
              m.masterId: <String, String>{'svc-1': 'a-${m.masterId}'},
          };
      return (performers, cover);
    }

    testWidgets(
      'selecting a service filters the grid to ONLY the masters who perform '
      'it — non-performing masters are hidden',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => filterMasters),
            coverage: coverageOverride(svc1Coverage),
          ),
        );
        await tester.pumpAndSettle();

        await selectSvc1(tester);

        // svc-1 performers survive; the non-performer is gone.
        expect(
          find.byKey(const Key('salon-master-card-master-1')),
          findsOneWidget,
          reason: 'master-1 performs svc-1 → must remain visible',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-3')),
          findsOneWidget,
          reason: 'master-3 performs svc-1 → must remain visible',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-2')),
          findsNothing,
          reason:
              'master-2 does NOT perform svc-1 (covers a different service) '
              '→ must be filtered out of the grid',
        );
      },
    );

    testWidgets(
      'the active-filter chip appears with the service name; tapping its clear '
      'button restores the full roster',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => filterMasters),
            coverage: coverageOverride(svc1Coverage),
          ),
        );
        await tester.pumpAndSettle();

        await selectSvc1(tester);

        final Finder chip = find.byKey(const Key('salon-masters-filter-chip'));
        expect(chip, findsOneWidget);
        // The chip label embeds the selected service's display name. The name
        // is fixture data (from _stubCatalog's svc-1), not UI copy — matching
        // by the substring stays robust across the l10n label template.
        // i18n-finder-ok: service name is fixture data, not UI copy.
        expect(
          find.descendant(
            of: chip,
            matching: find.textContaining('Манікюр з покриттям'),
          ),
          findsOneWidget,
          reason: 'the chip must name the service the grid is filtered by',
        );

        // master-2 is hidden while the filter is active.
        expect(
          find.byKey(const Key('salon-master-card-master-2')),
          findsNothing,
        );

        // Tap the chip's ✕ → clear → full roster returns.
        await tester.tap(find.byKey(const Key('salon-masters-filter-clear')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsNothing,
          reason: 'clearing the filter removes the chip',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-2')),
          findsOneWidget,
          reason:
              'the previously-hidden master-2 returns once the filter '
              'is cleared',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-card-master-3')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'when NO master performs the selected service the for-service empty '
      'state renders (chip still present so the filter can be dismissed)',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => filterMasters),
            // Every master present in the map but NONE covering svc-1.
            coverage: coverageOverride(const <String, Map<String, String>>{
              'master-1': <String, String>{'svc-other': 'a1'},
              'master-2': <String, String>{'svc-other': 'a2'},
              'master-3': <String, String>{'svc-other': 'a3'},
            }),
          ),
        );
        await tester.pumpAndSettle();

        await selectSvc1(tester);

        expect(
          find.byKey(const Key('salon-masters-for-service-empty')),
          findsOneWidget,
          reason:
              'a filter that matches no master must render the dedicated '
              'for-service empty state, not a blank grid',
        );
        // No master card renders.
        for (final String id in <String>['master-1', 'master-2', 'master-3']) {
          expect(find.byKey(Key('salon-master-card-$id')), findsNothing);
        }
        // The chip stays so the client can always dismiss the filter.
        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'while coverage is loading the grid shows a skeleton (chip already '
      'present so the filter is dismissible mid-load)',
      (tester) async {
        await _pumpTall(tester);
        // A never-completing coverage future keeps the tab in its loading
        // sub-state for the duration of the test.
        final Completer<Map<String, Map<String, String>>> never =
            Completer<Map<String, Map<String, String>>>();
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => filterMasters),
            coverage: salonMasterServiceCoverageProvider(
              const SalonBookingMasterSelectionArgs(
                salonId: _kSalonId,
                selectedServiceIds: <String>['svc-1'],
              ),
            ).overrideWith((ref) => never.future),
          ),
        );
        await tester.pumpAndSettle();

        // Reach the Майстри tab with the filter active. The catalogue load
        // still settles; only the coverage future hangs.
        await tester.tap(find.byKey(const Key('salon-tab-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-service-row-svc-1')));
        await tester.pump(); // one frame: filter set, coverage still pending

        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsOneWidget,
          reason: 'the chip renders even while coverage is still loading',
        );
        expect(
          find.byType(SkeletonShimmerScope),
          findsWidgets,
          reason: 'the coverage-loading sub-state shows a skeleton block',
        );
        // No master card and no empty state until coverage resolves.
        expect(
          find.byKey(const Key('salon-master-card-master-1')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-masters-for-service-empty')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a coverage load failure renders ErrorState with a working retry that '
      'reloads the filtered grid',
      (tester) async {
        await _pumpTall(tester);
        var attempt = 0;
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => filterMasters),
            coverage:
                salonMasterServiceCoverageProvider(
                  const SalonBookingMasterSelectionArgs(
                    salonId: _kSalonId,
                    selectedServiceIds: <String>['svc-1'],
                  ),
                ).overrideWith((ref) async {
                  attempt++;
                  if (attempt == 1) throw const NetworkFailure();
                  return svc1Coverage;
                }),
          ),
          // Disable Riverpod's default backoff retry so the AsyncError stays
          // put through pumpAndSettle (and leaves no pending backoff Timer).
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        await selectSvc1(tester);

        expect(
          find.byType(ErrorState),
          findsOneWidget,
          reason: 'a failed coverage load must surface an ErrorState',
        );
        // The chip is still there so the filter can be dismissed even on error.
        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsOneWidget,
        );

        // Retry → second attempt succeeds → the filtered grid renders.
        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsNothing);
        expect(
          find.byKey(const Key('salon-master-card-master-1')),
          findsOneWidget,
          reason: 'retry must reload the coverage and render the filtered grid',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-2')),
          findsNothing,
          reason: 'the reloaded grid must still exclude the non-performer',
        );
      },
    );

    testWidgets(
      'the kSalonMastersInitialCount cap applies to the FILTERED set: 8 '
      'performers render only the first 6 plus a show-all affordance',
      (tester) async {
        await _pumpTall(tester);
        final List<SalonMasterSummary> eightPerformers = List.generate(
          8,
          (i) => SalonMasterSummary(
            masterId: 'perf-${i + 1}',
            firstName: 'Майстер',
            lastName: '${i + 1}',
            avgRating: 4.5,
            reviewCount: 1,
            type: MasterType.salonMaster,
          ),
        );
        // Every one of the 8 performs svc-1 → the FILTERED set is all 8, so the
        // cap must apply to the filtered list (not the raw roster).
        final Map<String, Map<String, String>> allCover =
            <String, Map<String, String>>{
              for (final SalonMasterSummary m in eightPerformers)
                m.masterId: <String, String>{'svc-1': 'a-${m.masterId}'},
            };

        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => eightPerformers),
            coverage: coverageOverride(allCover),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        await selectSvc1(tester);

        for (int i = 1; i <= 6; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsOneWidget,
            reason: 'the first 6 filtered performers must render up front',
          );
        }
        for (int i = 7; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsNothing,
            reason:
                'filtered performers beyond the cap must stay unbuilt until '
                'show-all is tapped',
          );
        }

        final Finder showAll = find.byKey(const Key('salon-masters-show-all'));
        expect(
          showAll,
          findsOneWidget,
          reason: 'a filtered set over the cap must offer the reveal',
        );

        await tester.tap(showAll);
        await tester.pumpAndSettle();

        for (int i = 1; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsOneWidget,
            reason: 'all filtered performers render after show-all',
          );
        }
        expect(showAll, findsNothing);
      },
    );

    testWidgets(
      'show_all_on_filtered_set_then_clear_filter_reapplies_the_6_card_cap',
      (tester) async {
        await _pumpTall(tester);
        final (
          List<SalonMasterSummary> eight,
          Map<String, Map<String, String>> cover,
        ) = svc1Performers(
          8,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => eight),
            coverage: coverageOverride(cover),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        // Filter to the 8 performers, then reveal the full FILTERED set.
        await selectSvc1(tester);
        await tester.tap(find.byKey(const Key('salon-masters-show-all')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('salon-master-card-perf-8')),
          findsOneWidget,
          reason: 'show-all must expose the last filtered performer first',
        );

        // Clear the filter — this stays on the Майстри tab (same _MastersTab
        // State), so the cap must RE-ARM instead of the leaked show-all
        // eagerly rendering the whole unfiltered roster.
        await tester.tap(find.byKey(const Key('salon-masters-filter-clear')));
        await tester.pumpAndSettle();

        for (int i = 1; i <= 6; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsOneWidget,
            reason: 'the unfiltered roster re-caps to the first 6',
          );
        }
        for (int i = 7; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsNothing,
            reason:
                'a leaked show-all would eagerly build perf-$i after the '
                'filter is cleared — the cap must re-apply',
          );
        }
        expect(
          find.byKey(const Key('salon-masters-show-all')),
          findsOneWidget,
          reason: 'the re-capped roster offers the reveal again',
        );
      },
    );

    testWidgets(
      'show_all_on_full_roster_then_apply_filter_does_not_leak_show_all',
      (tester) async {
        await _pumpTall(tester);
        final (
          List<SalonMasterSummary> eight,
          Map<String, Map<String, String>> cover,
        ) = svc1Performers(
          8,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(masters: () async => eight),
            coverage: coverageOverride(cover),
          ),
          width: 390,
        );
        await tester.pumpAndSettle();

        // Unfiltered Майстри tab (index 1) — reveal the full roster.
        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-masters-show-all')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('salon-master-card-perf-8')),
          findsOneWidget,
          reason: 'show-all must expose the last roster master first',
        );

        // Apply the svc-1 filter (all 8 still qualify) — the filtered view
        // must start capped, never inherit the prior show-all expansion.
        await selectSvc1(tester);

        for (int i = 1; i <= 6; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsOneWidget,
            reason: 'the filtered view renders the first 6 up front',
          );
        }
        for (int i = 7; i <= 8; i++) {
          expect(
            find.byKey(Key('salon-master-card-perf-$i')),
            findsNothing,
            reason:
                'a leaked show-all would eagerly build perf-$i in the '
                'freshly-filtered view — the cap must hold',
          );
        }
        expect(
          find.byKey(const Key('salon-masters-show-all')),
          findsOneWidget,
          reason: 'the filtered set over the cap still offers the reveal',
        );
      },
    );
  });

  // ── mobile-build-verifier regression: hero card overlap-band hit test ────
  //
  // Phase 224's `_CoverAndHero` used to pin the hero card's overlap into the
  // cover with a hand-written `RenderShiftedBox` subclass that reported a
  // `size` SHORTER than the card's painted footprint (painting the card at
  // a negative offset relative to that shrunk box). `RenderBox.hitTest()`
  // gates on `_size.contains(position)` BEFORE it ever calls
  // `hitTestChildren()`, and a negative paint offset always lands the
  // "overhang" at negative *local* coordinates, which `Size.contains()` can
  // never treat as inside the box — so the top `_cardCoverOverlap` (25px)
  // of the card were never hit-testable; taps there silently fell through
  // to the cover photo underneath. This group pins the fix: a tap in that
  // exact band must resolve into the card itself.
  group('hero card overlap band hit-testing', () {
    testWidgets("a tap inside the hero card's top overlap band (the region "
        'overlapping the cover) resolves into the hero card, not the cover '
        'photo behind it', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      final Finder heroFinder = find.byKey(
        const Key('salon-profile-hero-card'),
      );
      final Rect heroRect = tester.getRect(heroFinder);
      // 2px below the card's own top edge — well within the fixed 25px
      // band that protrudes into (overlaps) the cover photo above it, and
      // still comfortably inside the card's own painted bounds.
      final Offset probe = Offset(heroRect.center.dx, heroRect.top + 2);

      final RenderObject heroRenderObject = tester.renderObject(heroFinder);
      final HitTestResult result = tester.hitTestOnBinding(probe);

      expect(
        _hitPathReaches(result, heroRenderObject),
        isTrue,
        reason:
            "a tap in the hero card's top overlap band must resolve "
            'into the card itself. If the card is wrapped in anything '
            'whose reported box does not cover its whole painted '
            'footprint (a shrunk custom RenderObject, or an ordinary '
            'shifted box sitting between a Transform and the parent '
            'that positions it), RenderBox.hitTest() rejects the '
            'position before it ever reaches the card, and the tap '
            'silently falls through to the cover photo behind it.',
      );
    });

    testWidgets(
      'the back button stays tappable and unobscured even at worst-case '
      'hero card height (a 1000-char locationNote, expanded)',
      (tester) async {
        await _pumpTall(tester);
        final String longNote = ('Вхід у двір з боку вулиці Хрещатик. ' * 30)
            .substring(0, 1000);
        final Salon salon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          description: 'Затишний салон краси в серці Печерська.',
          city: 'Київ',
          address: 'вул. Велика Васильківська, 44',
          locationNote: longNote,
          avgRating: 4.9,
          reviewCount: 128,
        );
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(salon: () async => salon),
          ),
        );
        await tester.pumpAndSettle();

        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        expect(toggle, findsOneWidget);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        final Finder backFinder = find.byKey(const Key('salon-profile-back'));
        final RenderObject backRenderObject = tester.renderObject(backFinder);
        final Offset backCenter = tester.getCenter(backFinder);
        final HitTestResult result = tester.hitTestOnBinding(backCenter);

        expect(
          _hitPathReaches(result, backRenderObject),
          isTrue,
          reason:
              "the back button must remain tappable regardless of the "
              "hero card's content height — the cover (and everything "
              'positioned on it) is now independent of the card, so an '
              'expanded note growing the card downward must never affect '
              'the back button.',
        );
      },
    );
  });

  // The «Контакти» block used to gate its ENTIRE section (heading included) on
  // `instagram != null` and had no phone row at all, so a phone-only salon
  // showed no contacts whatsoever. Both rows are now gated independently and
  // the heading on "either present" — the same structure the owner/admin
  // management screen already used.
  group('«Контакти» block — four combinations', () {
    Future<void> pumpWith(WidgetTester tester, Salon salon) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(salon: () async => salon),
        ),
      );
      await tester.pumpAndSettle();
    }

    final Finder phoneRow = find.byKey(const Key('salon-contact-phone'));
    final Finder instagramRow = find.byKey(
      const Key('salon-contact-instagram'),
    );
    // l10n-sourced, never a Cyrillic literal (scripts/forbid_cyrillic_finder).
    Finder heading(WidgetTester tester) => find.text(
      AppLocalizations.of(
        tester.element(find.byType(PublicSalonProfileScreen)),
      ).masterContactsLabel,
    );

    testWidgets('phone only — phone row and the section heading render', (
      tester,
    ) async {
      await pumpWith(tester, _stubSalon.copyWith(phone: '+380671112233'));
      expect(phoneRow, findsOneWidget);
      expect(instagramRow, findsNothing);
      expect(heading(tester), findsOneWidget);
      expect(find.text('+380671112233'), findsOneWidget);
    });

    testWidgets('instagram only — instagram row renders, no phone row', (
      tester,
    ) async {
      await pumpWith(tester, _stubSalon.copyWith(instagramUrl: '@velvet'));
      expect(phoneRow, findsNothing);
      expect(instagramRow, findsOneWidget);
      expect(heading(tester), findsOneWidget);
    });

    testWidgets('both — both rows render, phone above Instagram', (
      tester,
    ) async {
      await pumpWith(
        tester,
        _stubSalon.copyWith(phone: '+380671112233', instagramUrl: '@velvet'),
      );
      expect(phoneRow, findsOneWidget);
      expect(instagramRow, findsOneWidget);
      expect(
        tester.getRect(phoneRow).bottom,
        lessThanOrEqualTo(tester.getRect(instagramRow).top),
      );
    });

    testWidgets('neither — the whole section is hidden', (tester) async {
      await pumpWith(tester, _stubSalon);
      expect(phoneRow, findsNothing);
      expect(instagramRow, findsNothing);
      expect(heading(tester), findsNothing);
    });

    testWidgets(
      'a BLANK phone from the wire is treated as absent, not as an empty row '
      '(the backend serves "" verbatim for a cleared field)',
      (tester) async {
        await pumpWith(tester, _stubSalon.copyWith(phone: '   '));
        expect(phoneRow, findsNothing);
        expect(heading(tester), findsNothing);
      },
    );
  });

  // ── Phase 283 — roster audience-matrix pins (client-side rows) ──────────
  //
  // Pins the CLIENT-SIDE half of the D2 matrix: `GET /salons/{id}/masters`
  // (permitAll) applies no role filter of its own — the tab renders exactly
  // what `getSalonMasters` returned. The two "owner toggle OFF" cells are
  // gated on Phase 21.15 and pinned at the notifier/repository layer instead
  // (`salon_management_profile_notifier_test.dart`), never here.
  group('roster audience matrix (Phase 283)', () {
    testWidgets(
      'should_omitAdminFromClientRoster_when_salonProfileIsViewedPublicly',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => _matrixClientFullRoster,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        // D3 — the wire this screen reads has NO shape for an admin entry at
        // all (an admin has no master row), so a well-formed `/masters`
        // response for this salon carries exactly the three non-admin
        // identities below and never a fourth "admin" card — proving the
        // screen renders exactly the endpoint's payload, never inventing one.
        expect(find.byType(SalonMasterCard), findsNWidgets(3));
        expect(
          find.byKey(const Key('salon-master-card-matrix-owner-master-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-card-matrix-dual-master-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-card-matrix-master-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('should_showOwnerInBothRosters_when_ownerMasterRowIsActive', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(
            masters: () async => const <SalonMasterSummary>[_matrixClientOwner],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-card-matrix-owner-master-1')),
        findsOneWidget,
        reason: 'D2: an owner with an ACTIVE master row is client-visible',
      );
    });

    testWidgets(
      'should_showDualRolePersonInBothRosters_when_adminAlsoHasAMasterRow',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => const <SalonMasterSummary>[
                _matrixClientDualRole,
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        // D4 — this person is SALON_ADMIN on the staff wire (see the
        // staff-side counterpart test), but `/masters` knows nothing about
        // roles: it serves their active master row like anyone else's, and
        // clients must be able to book them.
        expect(
          find.byKey(const Key('salon-master-card-matrix-dual-master-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('should_showMasterInBothRosters_when_masterIsActive', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(
          repo: _FakeSalonRepository(
            masters: () async => const <SalonMasterSummary>[
              _matrixClientMaster,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-card-matrix-master-1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'should_notApplyAnyRoleFilterClientSide_when_rostersAreRendered',
      (tester) async {
        // D1 — pins the CLIENT half: every master-typed entry the endpoint
        // returned renders, unfiltered, whatever its [MasterType] (owner
        // included) — no client-side role filter narrows this list. The
        // staff-side counterpart of this exact case name lives in
        // `salon_management_profile_screen_test.dart`.
        await _pumpTall(tester);
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => _matrixClientFullRoster,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        expect(find.byType(SalonMasterCard), findsNWidgets(3));
        for (final SalonMasterSummary m in _matrixClientFullRoster) {
          expect(
            find.byKey(Key('salon-master-card-${m.masterId}')),
            findsOneWidget,
            reason: '${m.masterId} must render — no role filter exists',
          );
        }
      },
    );
  });
}

/// True when [result]'s hit-test path passes through [target] itself, or
/// through any render object that is a descendant of [target] — i.e. the
/// simulated tap actually reached into [target]'s own subtree, rather than
/// merely landing on an unrelated render object that happens to share
/// screen space with it.
bool _hitPathReaches(HitTestResult result, RenderObject target) {
  for (final HitTestEntry entry in result.path) {
    RenderObject? node = entry.target is RenderObject
        ? entry.target as RenderObject
        : null;
    while (node != null) {
      if (identical(node, target)) return true;
      node = node.parent;
    }
  }
  return false;
}
