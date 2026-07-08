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
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
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
    priceDisplay: '500 грн',
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
  // RoleChip visibility regression — the chip was rendered unconditionally
  // even when master.professionalTitle was set. The fix wraps the chip + its
  // SizedBox spacer in:
  //   if (master.professionalTitle == null || master.professionalTitle!.isEmpty)
  //
  // These tests would have FAILED before the fix. They guard against the chip
  // reappearing alongside a set title in future refactors of the identity card.
  // ──────────────────────────────────────────────────────────────────────────
  group('RoleChip visibility — hides when professionalTitle is set', () {
    testWidgets('hides the RoleChip when professionalTitle is set', (
      tester,
    ) async {
      final Master masterWithTitle = _stubMaster.copyWith(
        professionalTitle: 'Стиліст',
      );

      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => (masterWithTitle, _stubServices)),
      );
      await tester.pumpAndSettle();

      // The professional-title widget is rendered in place of the chip.
      expect(
        find.byKey(const Key('public-master-profile-professional-title')),
        findsOneWidget,
      );
      // RoleChip must NOT co-exist with a non-empty professionalTitle.
      expect(
        find.byType(RoleChip),
        findsNothing,
        reason:
            'RoleChip must be absent when master.professionalTitle is non-null '
            'and non-empty — regression pin for the unconditional-chip bug',
      );
    });

    testWidgets('shows the RoleChip when professionalTitle is null', (
      tester,
    ) async {
      // _stubMaster has no professionalTitle (null) — RoleChip is the fallback.
      await tester.pumpApp(
        const PublicMasterProfileScreen(masterId: _kMasterId),
        overrides: _overrides((ref) => _stubData),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('public-master-profile-professional-title')),
        findsNothing,
      );
      // RoleChip must appear as the role indicator when no title is set.
      expect(
        find.byType(RoleChip),
        findsOneWidget,
        reason:
            'RoleChip must be present when master.professionalTitle is null — '
            'it is the fallback role indicator shown when no title is set',
      );
    });
  });
}
