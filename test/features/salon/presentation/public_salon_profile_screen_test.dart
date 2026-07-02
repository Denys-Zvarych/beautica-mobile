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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр з покриттям',
        durationLabel: '1 год 30 хв',
        priceDisplay: '500 грн',
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
  }) : _salon = salon ?? (() async => _stubSalon),
       _masters = masters ?? (() async => _stubMasters),
       _catalog = catalog ?? (() async => _stubCatalog),
       _summary = summary ?? (() async => _stubSummary),
       _reviews =
           reviews ?? ((SalonReviewSort sort) async => _stubReviews(sort));

  final Future<Salon> Function() _salon;
  final Future<List<SalonMasterSummary>> Function() _masters;
  final Future<List<SalonServiceCategoryEntry>> Function() _catalog;
  final Future<SalonReviewSummary> Function() _summary;
  final Future<List<SalonReviewItem>> Function(SalonReviewSort sort) _reviews;

  /// Sort values passed to [getSalonReviews], in call order — asserted by the
  /// sort-sheet test.
  final List<SalonReviewSort> reviewSortCalls = <SalonReviewSort>[];

  @override
  Future<void> create({required SalonCreateDto dto}) async {}

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
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Object> _overrides({
  _FakeSalonRepository? repo,
  _FakeFavoriteRepository? fav,
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo ?? _FakeSalonRepository()),
  favoriteRepositoryProvider.overrideWithValue(
    fav ?? _FakeFavoriteRepository(),
  ),
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
      'legacy-only salon (city/address set, no taxonomy fields) still '
      'renders a location line (backward compat)',
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

        final addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(addressFinder, findsOneWidget);
        final Text addressWidget = tester.widget<Text>(addressFinder);
        expect(addressWidget.data, isNotNull);
        expect(addressWidget.data, isNotEmpty);
        expect(addressWidget.data, contains('Київ'));
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
    testWidgets(
      'long name + 2-line-wrapped role does not overflow the shrunk card',
      (tester) async {
        await _pumpTall(tester);
        const String longName = 'Олександра Верещагіна-Задорожня';
        await tester.pumpApp(
          const PublicSalonProfileScreen(salonId: _kSalonId),
          overrides: _overrides(
            repo: _FakeSalonRepository(
              masters: () async => const <SalonMasterSummary>[
                SalonMasterSummary(
                  masterId: 'master-long',
                  firstName: 'Олександра',
                  lastName: 'Верещагіна-Задорожня',
                  avgRating: 4.8,
                  reviewCount: 5,
                  type: MasterType.independentMaster,
                ),
              ],
            ),
          ),
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
      await tester.pumpApp(
        const PublicSalonProfileScreen(salonId: _kSalonId),
        overrides: _overrides(repo: repo),
      );
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
  });
}
