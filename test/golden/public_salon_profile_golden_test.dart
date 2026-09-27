// Phase 351 — BASELINE goldens for PublicSalonProfileScreen, captured BEFORE
// any REUSE-FIRST promotion (`SalonTabBar` → `ProfileTabBar`,
// `_SalonHeroCard`'s rating row → `RatingSummaryLine`). No golden previously
// existed for this screen at all — see the phase doc's Tests §1
// ("Before touching code, add test/golden/public_salon_profile_golden_test.dart").
//
// These baselines are the acceptance evidence the promotion is a pure file
// move: after `SalonTabBar`/the rating row are promoted and the screen is
// rewired onto the shared widgets, THESE SAME PNGs must pass unregenerated
// (mobile-backlog "goldens are not acceptance for a NEW visual result", but
// they ARE acceptance for "nothing visually changed").
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3}, two tab states:
//   • About  — default tab (index 0). Cover + hero card + tab bar + rating
//     line + description all visible.
//   • Reviews — tab index 3, reached via a `tester.tap` on `salon-tab-3`
//     before the golden is captured (mirrors `salon_master_tile_golden_
//     test.dart`'s `_wizardPump` "drive then capture" convention). Tab bar
//     + rating line stay visible above the review list, per the phase doc's
//     Tests §1 ("with the tab bar and rating line visible").
//
// Portfolio is left empty (no `mockNetworkImagesFor` needed — the rail
// renders nothing) and only ONE review is fixtured, keeping every cell short
// enough to never need scrolling within [kGoldenHeight].

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_api/beautica_api.dart'
    show SiblingSalonOption, UpdateSalonRequest;
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_portfolio_photo.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — trimmed subset of `public_salon_profile_screen_test.dart`'s.
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
  reviewCount: 1,
  distribution: <int>[0, 0, 0, 0, 1],
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

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

class _FakeFavoriteRepository implements FavoriteRepository {
  @override
  Future<void> add(FavoriteTarget target) async {}

  @override
  Future<void> remove(FavoriteTarget target) async {}

  @override
  Future<List<FavoriteItem>> getFavoriteMasters() async =>
      const <FavoriteItem>[];

  @override
  Future<List<FavoriteItem>> getFavoriteSalons() async =>
      const <FavoriteItem>[];
}

/// In-memory fake [SalonRepository] — same shape as the widget test's, only
/// the 4 client-facing reads are ever exercised by this golden; every
/// owner/admin write throws loudly if accidentally reached.
class _FakeSalonRepository implements SalonRepository {
  @override
  Future<void> create({required SalonCreateDto dto}) async {}

  @override
  Future<List<Salon>> getMySalons() async => const <Salon>[];

  @override
  Future<Salon> getSalonById(String salonId) async => _stubSalon;

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) async =>
      _stubMasters;

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async => _stubCatalog;

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) async =>
      _stubSummary;

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async => _stubReviews(sort);

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) async =>
      const <SalonPortfolioPhoto>[];

  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async => const <BookableMasterAssignment>[];

  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async =>
      throw UnimplementedError('owner/admin only');

  @override
  Future<void> deleteSalon(String salonId) async =>
      throw UnimplementedError('owner/admin only');

  @override
  Future<SalonInviteHistory> listSalonInvites(String salonId) async =>
      throw UnimplementedError('owner/admin only');

  @override
  Future<void> cancelInvite({
    required String salonId,
    required String inviteId,
  }) async => throw UnimplementedError('owner/admin only');

  @override
  Future<void> removeAdmin({
    required String salonId,
    required String userId,
  }) async => throw UnimplementedError('owner/admin only');

  @override
  Future<void> removeMaster({
    required String salonId,
    required String masterId,
  }) async => throw UnimplementedError('owner/admin only');

  @override
  Future<void> rotateAdmin({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  }) async => throw UnimplementedError('owner/admin only');

  @override
  Future<List<SiblingSalonOption>> getSiblingSalons(String salonId) async =>
      throw UnimplementedError('owner/admin only');

  @override
  Future<void> inviteStaff({
    required String salonId,
    required String email,
    required UserRole role,
  }) async => throw UnimplementedError('owner/admin only');

  @override
  Future<List<SalonStaffMember>> getSalonStaff(String salonId) async =>
      throw UnimplementedError('owner/admin only');
}

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(_FakeSalonRepository()),
  favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepository()),
];

// ---------------------------------------------------------------------------
// Custom pumpWidget — same steps as [goldenPumpWidget], plus (for the
// Reviews scenario) a tap on the Відгуки tab before the golden is captured.
// ---------------------------------------------------------------------------

PumpWidget _pumpTab({required double width, int? tapTabIndex}) {
  final PumpWidget base = goldenPumpWidget(
    overrides: _overrides(),
    width: width,
  );
  if (tapTabIndex == null) return base;
  return (WidgetTester tester, Widget alchemistWidget) async {
    await base(tester, alchemistWidget);
    await tester.tap(find.byKey(Key('salon-tab-$tapTabIndex')));
    await tester.pumpAndSettle();
  };
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'public_salon_profile About $suffix',
        fileName: 'public_salon_profile_about_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width),
        builder: () => const PublicSalonProfileScreen(salonId: _kSalonId),
      );

      goldenTest(
        'public_salon_profile Reviews $suffix',
        fileName: 'public_salon_profile_reviews_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width, tapTabIndex: 3),
        builder: () => const PublicSalonProfileScreen(salonId: _kSalonId),
      );
    }
  }
}
