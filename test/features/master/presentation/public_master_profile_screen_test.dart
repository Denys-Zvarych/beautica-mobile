// Phase 13.5 — Widget tests for PublicMasterProfileScreen.
//
// Covers the three AsyncValue states plus the client-facing affordances that
// distinguish this screen from the master's own profile:
//   1. Loading  — skeleton blocks present, name absent.
//   2. Data     — master name shown; favourite heart + «Записатись» CTA present;
//                 NO edit/menu button (Key('btn-menu-master')) anywhere.
//   3. Error    — ErrorState widget rendered.
//   4. Booking  — tapping the «Записатись» CTA navigates to RouteNames.bookingNew.
//
// Strategy: override the [publicMasterProfileProvider] family for the target id
// with the desired AsyncValue, and stub [authProvider] as an authenticated
// CLIENT so the favourite heart's notifier resolves without touching storage.
// mobile-qa deepens this suite after the screen ships.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_reviews_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/service_category_cards.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/pump_app.dart';

/// Mock [UrlLauncherPlatform] — `url_launcher` 6.x routes every
/// `launchUrl(uri, mode: ...)` through `UrlLauncherPlatform.instance.launchUrl`,
/// so swapping the platform instance lets us assert the EXACT (canonicalised)
/// URL the screen handed to the launcher without firing a real intent.
/// [MockPlatformInterfaceMixin] satisfies the `PlatformInterface.verify` token.
class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

// Multi-category + uncategorized fixture for the service-categories section
// tests below — distinct from `_stubServices` (used by the pre-existing
// suite) so those tests' single-service assumptions are untouched.
const List<MasterService> _multiCategoryServices = <MasterService>[
  MasterService(
    id: 'svc-cat-1',
    serviceDefId: 'def-cat-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'MANICURE',
  ),
  MasterService(
    id: 'svc-cat-2',
    serviceDefId: 'def-cat-2',
    name: 'Ще манікюр',
    durationMinutes: 60,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'MANICURE',
  ),
  MasterService(
    id: 'svc-cat-3',
    serviceDefId: 'def-cat-3',
    name: 'Корекція брів',
    durationMinutes: 30,
    priceMin: 250,
    priceDisplay: '250 ₴',
    category: 'BROWS',
  ),
];

const List<MasterService> _uncategorizedOnlyServices = <MasterService>[
  MasterService(
    id: 'svc-none-1',
    serviceDefId: 'def-none-1',
    name: 'Без категорії',
    durationMinutes: 20,
    priceMin: 100,
    priceDisplay: '100 ₴',
    // category deliberately absent → "_none" bucket.
  ),
];

const _stubUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Клієнт',
  lastName: 'Тест',
);

const _stubMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  bio: 'Майстер манікюру з 7-річним досвідом.',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
  instagram: '@olena_nails',
);

const _stubServices = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'MANICURE',
  ),
];

PublicMasterProfileData get _stubData => (_stubMaster, _stubServices);

/// Stub [AuthNotifier] — always an authenticated CLIENT, no storage/network.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Object> _overrides(
  FutureOr<PublicMasterProfileData> Function(Ref ref) create,
) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  publicMasterProfileProvider(_kMasterId).overrideWith(create),
  // The read-only service-categories section (ServiceCategoryCardList) watches
  // approvedCategoriesProvider for category-label resolution. Left
  // unoverridden it falls through to the real HTTP-backed provider and hangs
  // pumpAndSettle() on a real Dio call — see the approvedCategoriesProvider
  // override footgun noted for ServiceForm/SearchableSelectField tests. An
  // empty list is fine here: label resolution falls back to
  // humanizeCategorySlug, and none of these tests assert on category labels.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('loading state', () {
    testWidgets('shows skeleton blocks while loading', (tester) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Completer<PublicMasterProfileData>().future,
        ),
      );

      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('public-master-profile-name')), findsNothing);
    });
  });

  group('data state', () {
    testWidgets('renders the master name + favourite heart + booking CTA, '
        'and NO edit button', (tester) async {
      // Tall surface so the pinned booking shelf + body all lay out.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('public-master-profile-name')),
        findsOneWidget,
      );
      // i18n-finder-ok: master's display name is fixture data, not UI copy
      expect(find.text('Олена Ковальчук'), findsOneWidget);

      // Client affordances present.
      expect(
        find.byKey(const Key('public-master-favorite-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('public-master-book-cta')), findsOneWidget);

      // This is the read-only client view — the master's edit/menu button must
      // NOT appear anywhere.
      expect(find.byKey(const Key('btn-menu-master')), findsNothing);
    });

    testWidgets('shows the services count in the stats row', (tester) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      final Text servicesValue = tester.widget<Text>(
        find.byKey(const Key('public-master-profile-services-value')),
      );
      expect(servicesValue.data, '${_stubServices.length}');
    });
  });

  group('error state', () {
    testWidgets('renders ErrorState on failure', (tester) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Future<PublicMasterProfileData>.error(
            const NetworkFailure(),
            StackTrace.empty,
          ),
        ),
        // Disable Riverpod's retry so the AsyncError settles (no pending Timer).
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('public-master-profile-name')), findsNothing);

      // The typed NetworkFailure must surface its NETWORK-SPECIFIC copy — NOT
      // the generic UnknownFailure copy. This pins the end-to-end chain the
      // notifier's `.wait`-unwrap fix exists for (mobile-qa MEDIUM): a backend
      // error reaches the screen as a typed Failure, so the screen renders the
      // precise message instead of a catch-all. l10n is resolved from the pumped
      // tree (never a hardcoded UA string).
      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      expect(find.text(l10n.errNetwork), findsOneWidget);
      expect(
        find.text(l10n.errUnknown),
        findsNothing,
        reason:
            'a typed NetworkFailure must NOT degrade to the generic '
            'UnknownFailure copy — the regression the unwrap fix guards.',
      );
      // Error state offers a retry affordance.
      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
    });
  });

  group('booking navigation', () {
    testWidgets('tapping «Записатись» pushes the booking route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/masters/$_kMasterId',
        routes: <RouteBase>[
          GoRoute(
            path: '/masters/:masterId',
            builder: (context, state) => PublicMasterProfileScreen(
              masterId: state.pathParameters['masterId']!,
            ),
          ),
          GoRoute(
            path: RouteNames.bookingNew,
            builder: (_, _) => const Scaffold(body: Text('booking-stub')),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      final cta = find.byKey(const Key('public-master-book-cta'));
      expect(cta, findsOneWidget);

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('booking-stub'), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // REGRESSION — the reviews stat tile used to render with NO GestureDetector
  // at all: tapping it was a silent no-op (the user-reported bug). The fix
  // wraps the tile in a GestureDetector whose onTap calls
  // `context.push(RouteNames.masterPublicReviews(masterId))`.
  //
  // NAV-DETECTION TRAP (do not "simplify"): this MUST drive the real
  // `context.push` code path by tapping the actual rendered
  // GestureDetector — a test that instead called `router.go(...)` directly
  // would pass even if the shipped tile still had no tap handler at all,
  // because it would never exercise the widget under test's onTap callback.
  // Tapping the real key is what makes this a genuine regression guard.
  //
  // TRUST-BOUNDARY PIN (mobile-security LOW, public_master_profile_screen.dart
  // ~410) — the fixture deliberately makes `master.id` (a value round-tripped
  // through the `GET /masters/{masterId}` response and mapped by
  // [MasterMapper]) DIFFERENT from `_kMasterId` (the trusted route param /
  // `widget.masterId`), mirroring what a future mapper bug or a backend
  // response that doesn't echo the requested id would look like. The tile
  // must push using `widget.masterId`, never `master.id`. Only the
  // `_kMasterId`-keyed review providers are overridden — if the tile ever
  // regresses to navigating via the echoed `master.id`, the pushed screen
  // looks up providers keyed by that (unoverridden) id and the assertions
  // below go red instead of silently passing either way.
  // ──────────────────────────────────────────────────────────────────────────
  group('reviews tile navigation (regression — was a silent no-op)', () {
    testWidgets(
      'tapping the «Відгуки» stat tile pushes /masters/:masterId/reviews '
      'using the ROUTE masterId, not the master.id echoed back by the '
      'profile response, and PublicMasterReviewsScreen renders this '
      "masterId's reviews",
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Deliberately mismatched: the network-echoed `master.id` must never
        // be the value navigation keys off of.
        final Master mismatchedMaster = _stubMaster.copyWith(
          id: 'server-echoed-mismatched-id',
        );
        final PublicMasterProfileData mismatchedData = (
          mismatchedMaster,
          _stubServices,
        );

        final router = GoRouter(
          initialLocation: '/masters/$_kMasterId',
          routes: <RouteBase>[
            GoRoute(
              path: '/masters/:masterId',
              builder: (context, state) => PublicMasterProfileScreen(
                masterId: state.pathParameters['masterId']!,
              ),
            ),
            GoRoute(
              path: '/masters/:masterId/reviews',
              builder: (context, state) => PublicMasterReviewsScreen(
                masterId: state.pathParameters['masterId']!,
              ),
            ),
          ],
        );

        const MasterReviewSummary summary = MasterReviewSummary(
          avgRating: 4.8,
          reviewCount: 1,
          distribution: <int>[1, 0, 0, 0, 0],
        );
        final MasterReviewItem review = MasterReviewItem(
          id: 'rev-1',
          clientDisplayName: 'Client A',
          rating: 5,
          comment: 'Great!',
          createdAt: DateTime.utc(2026, 6, 1),
        );

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._overrides((ref) => mismatchedData),
            // Keyed by the TRUSTED route id (_kMasterId), NOT by
            // `mismatchedMaster.id`. A push that (wrongly) used `master.id`
            // would land on an unoverridden provider instance for that id.
            masterReviewSummaryProvider(
              _kMasterId,
            ).overrideWith((ref) => summary),
            masterReviewsProvider(
              _kMasterId,
              MasterReviewSort.newest,
            ).overrideWith((ref) => <MasterReviewItem>[review]),
          ],
        );
        await tester.pumpAndSettle();

        final Finder tile = find.byKey(
          const Key('public-master-profile-reviews-tile'),
        );
        expect(tile, findsOneWidget);

        // The real tap drives the widget's own onTap → context.push.
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);

        final PublicMasterReviewsScreen pushedScreen = tester.widget(
          find.byType(PublicMasterReviewsScreen),
        );
        expect(
          pushedScreen.masterId,
          _kMasterId,
          reason:
              'navigation must carry the ROUTE masterId (widget.masterId), '
              'never the master.id echoed back in the profile response',
        );

        expect(
          find.byKey(const Key('master-review-rev-1')),
          findsOneWidget,
          reason:
              'the pushed screen must render THIS masterId\'s review, proving '
              'the id travelled through the push, not just that SOME screen '
              'mounted',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Stats-row order — Rating → Services → Reviews → Experience. Pinned so a
  // future refactor can't silently reshuffle it back.
  // ──────────────────────────────────────────────────────────────────────────
  group('stats row order', () {
    testWidgets('renders Rating, Services, Reviews, Experience in that order', (
      tester,
    ) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      final List<StatTile> tiles = tester
          .widgetList<StatTile>(find.byType(StatTile))
          .toList();

      expect(tiles, hasLength(4));
      expect(tiles[0].caption, l10n.masterRatingLabel);
      expect(tiles[1].caption, l10n.masterServicesLabel);
      expect(tiles[2].caption, l10n.masterStatsReviewsLabel);
      expect(tiles[3].caption, l10n.publicMasterExperienceLabel);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Identity-card inline rating REMOVED — the stats-row rating StatTile
  // (`public-master-profile-rating-value`) is the ONLY rating affordance on
  // the screen; the identity card itself must carry no RatingStar/rating row.
  // ──────────────────────────────────────────────────────────────────────────
  group('identity-card inline rating removed', () {
    testWidgets(
      'the identity card has no RatingStar descendant; the stats-row rating '
      'value remains the single RatingStar on the screen',
      (tester) async {
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => _stubData),
        );
        await tester.pumpAndSettle();

        final Finder identityCard = find.ancestor(
          of: find.byKey(const Key('public-master-profile-name')),
          matching: find.byType(NeumorphicCard),
        );
        expect(identityCard, findsOneWidget);
        expect(
          find.descendant(of: identityCard, matching: find.byType(RatingStar)),
          findsNothing,
          reason: 'the identity card must not render its own inline rating',
        );

        // The stats-row rating value tile is still present — the rating
        // affordance moved, it was not deleted outright.
        expect(
          find.byKey(const Key('public-master-profile-rating-value')),
          findsOneWidget,
        );
        expect(
          find.byType(RatingStar),
          findsOneWidget,
          reason: 'exactly one RatingStar — the stats-row tile\'s',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Loading-skeleton structure (M3) — the loading frame shows the shimmer scope
  // and the favourite toggle (a top-bar action, always present), but NOT the
  // resolved body name nor the booking shelf (gated on data via maybeWhen).
  // ──────────────────────────────────────────────────────────────────────────
  group('loading skeleton structure', () {
    testWidgets('shimmer scope + favourite toggle present, name + booking shelf '
        'absent while loading', (tester) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Completer<PublicMasterProfileData>().future,
        ),
      );
      await tester.pump();

      // The shimmer skeleton wraps the loading body.
      expect(find.byType(SkeletonShimmerScope), findsOneWidget);
      expect(find.byType(SkeletonBlock), findsWidgets);

      // Top-bar favourite action renders even before data resolves.
      expect(
        find.byKey(const Key('public-master-favorite-toggle')),
        findsOneWidget,
      );

      // The resolved identity name and the data-gated booking shelf are absent.
      expect(find.byKey(const Key('public-master-profile-name')), findsNothing);
      expect(find.byKey(const Key('public-master-book-cta')), findsNothing);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Booking-shelf empty state — the pinned camel-wash shelf renders the
  // «Послуги та ціни» section label above the «Записатись до майстра» CTA once
  // the master resolves. The «Оберіть послугу» empty prompt was removed from
  // THIS screen (it still renders on the service-selector sheet reached after
  // tapping the CTA).
  // ──────────────────────────────────────────────────────────────────────────
  group('booking shelf empty state', () {
    testWidgets('renders the «Послуги та ціни» label and the CTA once data '
        'resolves, without the empty prompt', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      // Section label is a content assertion resolved via l10n (never raw
      // literals — M2/M11), so an l10n rename moves it in lockstep.
      expect(find.text(l10n.publicMasterBookingSectionLabel), findsOneWidget);

      // The empty prompt no longer renders on THIS screen — it moved
      // exclusively to the service-selector sheet reached after tapping the
      // CTA. Regression pin: never let it silently reappear here.
      expect(find.text(l10n.publicMasterBookingEmptyPrompt), findsNothing);

      // The CTA is keyed (M2) — its label resolves via l10n on the live tree.
      expect(find.byKey(const Key('public-master-book-cta')), findsOneWidget);
      expect(find.text(l10n.publicMasterBookingCta), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Instagram contact tile — tapping it hands the VALIDATED canonical URL to the
  // launcher (the canonicalInstagramUri gate ran). The platform launcher is
  // mocked so no real intent fires and the exact URL string is asserted (M5-ish:
  // an external-launch side effect must be observed, not assumed).
  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────
  // Salon-affiliation gating — Instagram + portfolio are an INDEPENDENT_MASTER
  // -only affordance. Salon-affiliated masters (salonMaster / salonOwner) must
  // NOT show either, even when the underlying data (instagram handle) is
  // populated; independent masters keep the existing behaviour.
  // ──────────────────────────────────────────────────────────────────────────
  group('salon affiliation gating — instagram + portfolio', () {
    Future<void> pumpFor(WidgetTester tester, MasterType type) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Master master = _stubMaster.copyWith(type: type);
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => (master, _stubServices)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'salonMaster with instagram set — Instagram tile does NOT render',
      (tester) async {
        await pumpFor(tester, MasterType.salonMaster);

        expect(
          find.byKey(const Key('public-master-contact-instagram')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'salonOwner with instagram set — Instagram tile does NOT render',
      (tester) async {
        await pumpFor(tester, MasterType.salonOwner);

        expect(
          find.byKey(const Key('public-master-contact-instagram')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'independentMaster with instagram set — Instagram tile DOES render',
      (tester) async {
        await pumpFor(tester, MasterType.independentMaster);

        expect(
          find.byKey(const Key('public-master-contact-instagram')),
          findsOneWidget,
        );
      },
    );

    testWidgets('salonMaster — portfolio section does NOT render', (
      tester,
    ) async {
      await pumpFor(tester, MasterType.salonMaster);

      expect(
        find.byKey(const Key('public-master-profile-portfolio')),
        findsNothing,
      );
    });

    testWidgets('salonOwner — portfolio section does NOT render', (
      tester,
    ) async {
      await pumpFor(tester, MasterType.salonOwner);

      expect(
        find.byKey(const Key('public-master-profile-portfolio')),
        findsNothing,
      );
    });

    testWidgets('independentMaster — portfolio section DOES render', (
      tester,
    ) async {
      await pumpFor(tester, MasterType.independentMaster);

      expect(
        find.byKey(const Key('public-master-profile-portfolio')),
        findsOneWidget,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Skeleton portfolio placeholder — regression. The skeleton renders BEFORE
  // `master.type` is known, so it must never show a portfolio placeholder: for
  // a salon-affiliated master (whose real body correctly hides the portfolio,
  // see the salon-affiliation-gating group above) a skeleton placeholder would
  // "pop out" the instant real data lands. This group pins: the key is absent
  // during loading regardless of eventual type, stays absent for salon types
  // (no pop-out), and only appears once independent-master data resolves (the
  // normal pop-in, unaffected by this fix).
  // ──────────────────────────────────────────────────────────────────────────
  group('skeleton portfolio placeholder — no pop-in/pop-out (regression)', () {
    testWidgets('portfolio key absent during loading (type not yet known)', (
      tester,
    ) async {
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Completer<PublicMasterProfileData>().future,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('public-master-profile-portfolio')),
        findsNothing,
      );
    });

    testWidgets(
      'salonMaster — portfolio key absent while loading AND stays absent '
      'after data resolves (no pop-out)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final completer = Completer<PublicMasterProfileData>();
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => completer.future),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('public-master-profile-portfolio')),
          findsNothing,
          reason: 'the skeleton never renders a portfolio placeholder',
        );

        completer.complete((
          _stubMaster.copyWith(type: MasterType.salonMaster),
          _stubServices,
        ));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-portfolio')),
          findsNothing,
          reason: 'salon-affiliated masters never show a portfolio section',
        );
      },
    );

    testWidgets(
      'independentMaster — portfolio key absent while loading, PRESENT '
      'after data resolves (normal pop-in preserved)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final completer = Completer<PublicMasterProfileData>();
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => completer.future),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('public-master-profile-portfolio')),
          findsNothing,
        );

        completer.complete((
          _stubMaster.copyWith(type: MasterType.independentMaster),
          _stubServices,
        ));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-portfolio')),
          findsOneWidget,
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // professionalTitle display — rendered only when the field is non-null and
  // non-empty; absent when null. Regression pin for the new headline field.
  // ──────────────────────────────────────────────────────────────────────────
  group('professionalTitle display', () {
    testWidgets(
      'renders the professionalTitle below the master name when set',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final Master masterWithTitle = _stubMaster.copyWith(
          professionalTitle: 'Колорист-стиліст',
        );

        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => (masterWithTitle, _stubServices)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-professional-title')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'does NOT render the professional-title widget when professionalTitle is null',
      (tester) async {
        // _stubMaster has no professionalTitle (null by default).
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => _stubData),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-professional-title')),
          findsNothing,
        );
      },
    );
  });

  group('instagram contact tile — launch behaviour', () {
    late _MockUrlLauncher launcher;
    late UrlLauncherPlatform originalPlatform;

    setUp(() {
      originalPlatform = UrlLauncherPlatform.instance;
      launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      registerFallbackValue(const LaunchOptions());
    });

    tearDown(() {
      UrlLauncherPlatform.instance = originalPlatform;
    });

    testWidgets('tapping the tile launches the canonical '
        'https://instagram.com/<handle> URL', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);

      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      // _stubMaster.instagram == '@olena_nails' → the contacts section renders.
      final tile = find.byKey(const Key('public-master-contact-instagram'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      // launchUrl invoked exactly once with the canonical URL — the leading "@"
      // stripped and the canonical host composed (the validation gate ran).
      final captured = verify(
        () => launcher.launchUrl(captureAny(), any()),
      ).captured;
      expect(captured, hasLength(1));
      expect(captured.single, 'https://instagram.com/olena_nails');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // RoleChip label-switching — the chip is now unconditional. When
  // professionalTitle is set it carries the key and shows the title as its
  // label; when null/empty the key is absent and it shows the role label.
  // ──────────────────────────────────────────────────────────────────────────
  group(
    'RoleChip visibility — label switches between professionalTitle and role label',
    () {
      testWidgets(
        'shows professionalTitle text inside RoleChip when professionalTitle is set',
        (tester) async {
          final Master masterWithTitle = _stubMaster.copyWith(
            professionalTitle: 'Стиліст',
          );

          await tester.pumpApp(
            const PublicMasterProfileScreen(masterId: _kMasterId),
            overrides: _overrides((ref) => (masterWithTitle, _stubServices)),
          );
          await tester.pumpAndSettle();

          // The chip carries the professional-title key when professionalTitle is set.
          expect(
            find.byKey(const Key('public-master-profile-professional-title')),
            findsOneWidget,
          );
          // The chip is always present (unconditional).
          expect(find.byType(RoleChip), findsOneWidget);
          // The title text is rendered inside the chip, not as a standalone Text.
          expect(
            find.descendant(
              of: find.byType(RoleChip),
              // i18n-finder-ok: professionalTitle is user-entered data, not localised UI copy — identical in every locale
              matching: find.text('Стиліст'),
            ),
            findsOneWidget,
            reason:
                'professionalTitle text must be shown inside RoleChip as its label, '
                'not as a separate Text widget outside the chip',
          );
        },
      );

      testWidgets('shows the RoleChip when professionalTitle is null', (
        tester,
      ) async {
        // _stubMaster has no professionalTitle (null) — RoleChip shows the role label.
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => _stubData),
        );
        await tester.pumpAndSettle();

        // The title key is null when showing the role label — so absent from the tree.
        expect(
          find.byKey(const Key('public-master-profile-professional-title')),
          findsNothing,
        );
        // The RoleChip is always present (unconditional).
        expect(
          find.byType(RoleChip),
          findsOneWidget,
          reason:
              'RoleChip is always rendered — when professionalTitle is null it shows '
              'the master-type role label instead',
        );
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Service-categories section — read-only client view. Mirrors the master's
  // own profile section (master_profile_screen_test.dart group 14), minus the
  // owner-only navigation, PLUS the mobile-security LOW fail-open guard: this
  // screen's call site (public_master_profile_screen.dart) passes
  // `interactive: false` to `ServiceCategoryCardList`. `interactive` is now a
  // REQUIRED named param (no more `= true` default) so the compiler blocks a
  // call site that forgets it entirely — but a future edit could still flip
  // an explicit `false` to `true` by mistake, so this group keeps testing
  // against the REAL screen.
  //
  // service_category_cards_test.dart pins the SAME contract at the shared-
  // widget level (in isolation); THIS group pins it at the actual production
  // call site, which is what would actually go red if someone deleted
  // `interactive: false` from public_master_profile_screen.dart.
  // ──────────────────────────────────────────────────────────────────────────
  group('service categories section (read-only)', () {
    testWidgets(
      'renders one card per category grouped from the services list, with '
      'the correct counts',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides((ref) => (_stubMaster, _multiCategoryServices)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-service-categories')),
          findsOneWidget,
        );

        final Finder manicureCard = find.byKey(
          const Key('public-master-profile-category-MANICURE'),
        );
        final Finder browsCard = find.byKey(
          const Key('public-master-profile-category-BROWS'),
        );
        expect(
          manicureCard,
          findsOneWidget,
          reason: 'MANICURE bucket (svc-cat-1 + svc-cat-2) must render a card',
        );
        expect(
          browsCard,
          findsOneWidget,
          reason: 'BROWS bucket (svc-cat-3) must render a card',
        );

        final ServiceCategoryCard manicure = tester.widget(manicureCard);
        final ServiceCategoryCard brows = tester.widget(browsCard);
        expect(manicure.count, 2, reason: 'MANICURE has 2 services');
        expect(brows.count, 1, reason: 'BROWS has 1 service');
      },
    );

    testWidgets('services with no category are grouped under the uncategorized '
        '(_none) bucket', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => (_stubMaster, _uncategorizedOnlyServices),
        ),
      );
      await tester.pumpAndSettle();

      final Finder noneCard = find.byKey(
        const Key('public-master-profile-category-_none'),
      );
      expect(noneCard, findsOneWidget);
      final ServiceCategoryCard card = tester.widget(noneCard);
      expect(card.count, 1);
    });

    testWidgets(
      'a master with zero active services renders NO service-categories '
      'section at all',
      (tester) async {
        await tester.pumpApp(
          const PublicMasterProfileScreen(masterId: _kMasterId),
          overrides: _overrides(
            (ref) => (_stubMaster, const <MasterService>[]),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('public-master-profile-service-categories')),
          findsNothing,
          reason:
              'the section must be omitted entirely for zero services — '
              'matching how Bio/Contacts are omitted when empty',
        );
        expect(find.byType(ServiceCategoryCard), findsNothing);

        // The services stat tile still shows 0, not a hidden/blank value.
        final Text servicesValue = tester.widget<Text>(
          find.byKey(const Key('public-master-profile-services-value')),
        );
        expect(servicesValue.data, '0');
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // SECURITY REGRESSION GUARD (mobile-security LOW, closed) — `interactive`
    // used to default to `true` on both ServiceCategoryCardList and
    // ServiceCategoryCard; it is now a REQUIRED named param with no default,
    // so the compiler rejects a call site that omits it. This screen's real
    // call site passes `interactive: false` explicitly; this test exercises
    // the REAL production widget tree (not a hand-built
    // ServiceCategoryCardList) so it goes RED if that argument is ever
    // silently changed to `true`: the chevron + GestureDetector would
    // reappear, and a tap would start pushing
    // `/services?expandCategory=<slug>` — the AUTHENTICATED master's own
    // service-management screen — to an unauthenticated-for-that-resource
    // CLIENT.
    // ────────────────────────────────────────────────────────────────────────
    testWidgets(
      'card renders NO chevron, NO GestureDetector, and tapping it does NOT '
      'navigate to /services (SECURITY REGRESSION GUARD)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: '/masters/$_kMasterId',
          routes: <RouteBase>[
            GoRoute(
              path: '/masters/:masterId',
              builder: (context, state) => PublicMasterProfileScreen(
                masterId: state.pathParameters['masterId']!,
              ),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (_, _) => const Scaffold(body: Text('services-page')),
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((ref) => (_stubMaster, _multiCategoryServices)),
        );
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const Key('public-master-profile-category-MANICURE'),
        );
        expect(card, findsOneWidget);

        expect(
          find.descendant(
            of: card,
            matching: find.byIcon(Icons.arrow_forward_ios_rounded),
          ),
          findsNothing,
          reason:
              'a CLIENT-facing category card must never show the owner-only '
              'disclosure chevron',
        );
        expect(
          find.descendant(of: card, matching: find.byType(GestureDetector)),
          findsNothing,
          reason:
              'a CLIENT-facing category card must have NO tap handler — '
              '/services is scoped to the AUTHENTICATED master',
        );

        // Force a tap at the card's location — there is (by design) no
        // hit-testable gesture target here, hence warnIfMissed: false.
        await tester.tap(card, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(
          find.text('services-page'),
          findsNothing,
          reason:
              'tapping a read-only public-profile category card must NEVER '
              'navigate to /services',
        );
        expect(
          find.byType(PublicMasterProfileScreen),
          findsOneWidget,
          reason:
              'the screen must still be the public profile — no navigation happened',
        );
      },
    );
  });
}
