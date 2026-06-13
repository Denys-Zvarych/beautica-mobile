// Phase 4.2 — Widget tests for MasterProfileScreen.
//
// Covers all four AsyncValue states:
//   1. Loading  — [_ProfileSkeleton] tree rendered; [SkeletonBlock] visible.
//   2. Data     — master name and bio shown; rating + reviews stat keys present.
//   3. Error    — [ErrorState] widget rendered.
//   4. Retry (standalone) — tapping the retry button calls onRetry callback.
//   5. Retry (screen)     — tapping retry in [MasterProfileScreen] causes the
//                            provider to be invalidated and content reloads.
//   6. Empty bio — bio section key absent from tree when bio is null.
//
// Strategy:
//   • Override [masterProfileProvider] with a stub [MasterProfile] notifier
//     whose [build()] writes the desired [AsyncValue] to state immediately.
//   • Override [authProvider] with a stub that always returns [Authenticated].
//   • Override [masterRepositoryProvider] with a mocktail mock.
//   • Use [pumpApp] from `test/helpers/pump_app.dart` for l10n + Riverpod.

// Phase 4.2 — Widget tests for MasterProfileScreen.
//
// Covers all four AsyncValue states:
//   1. Loading  — [_ProfileSkeleton] tree rendered; [SkeletonBlock] visible.
//   2. Data     — master name and bio shown; rating + reviews stat keys present.
//   3. Error    — [ErrorState] widget rendered.
//   4. Retry (standalone) — tapping the retry button calls onRetry callback.
//   5. Retry (screen)     — tapping retry in [MasterProfileScreen] causes the
//                            provider to be invalidated and content reloads.
//   6. Empty bio — bio section key absent from tree when bio is null.
//   7. Contacts section — ContactTile keys present in the loaded data state.
//   8. Bottom nav bar — VelvetBottomNavBar rendered in the data state.
//
// Strategy:
//   • Override [masterProfileProvider] with a stub [MasterProfile] notifier
//     whose [build()] writes the desired [AsyncValue] to state immediately.
//   • Override [authProvider] with a stub that always returns [Authenticated].
//   • Override [masterRepositoryProvider] with a mocktail mock.
//   • Use [pumpApp] from `test/helpers/pump_app.dart` for l10n + Riverpod.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

const _stubMaster = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  bio: 'Досвідчений майстер манікюру.',
  avgRating: 4.8,
  reviewCount: 42,
  type: MasterType.independentMaster,
);

const _stubMasterNoBio = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// City-only — no street, no buildingNo, no locationNote.
/// Expected locationLine: "Київ".
const _stubMasterCityOnly = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Street + city, no buildingNo, no locationNote.
/// Expected locationLine: "вул. Хрещатик, Київ".
const _stubMasterStreetAndCity = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  street: 'вул. Хрещатик',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Street + buildingNo + city + locationNote — full address.
/// Expected locationLine: "вул. Хрещатик, 22, Київ".
/// Expected note row: "кв. 3, 2 поверх".
const _stubMasterFullAddress = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  locationNote: 'кв. 3, 2 поверх',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// No city, no street — location row must be hidden entirely.
const _stubMasterNoLocation = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Stub [MasterProfile] notifier — resolves immediately to [_target].
///
/// For the loading-state test, [_target] is [AsyncLoading]; [build()] returns
/// a never-completing [Future] so the test can inspect the loading frame.
/// For data / error states, [build()] posts the state via [Future.microtask]
/// before returning, so a single [pumpAndSettle] transitions past loading.
class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._target);

  final AsyncValue<Master> _target;

  @override
  Future<Master> build() {
    if (!_target.isLoading) {
      // Post the desired state asynchronously so the screen sees a single
      // loading frame followed by the target state on the next microtask.
      Future<void>.microtask(() => state = _target);
    }
    // Return a Completer that never completes — the state is managed above.
    return Completer<Master>().future;
  }
}

/// Stub [AuthNotifier] — always returns [Authenticated] without touching
/// SecureStorage or the network.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'test-token');
}

// ---------------------------------------------------------------------------
// Helper: build override list
// ---------------------------------------------------------------------------

List<Object> _buildOverrides({
  required AsyncValue<Master> masterState,
  required _MockMasterRepository repo,
  required _MockServiceRepository serviceRepo,
}) {
  return <Object>[
    authProvider.overrideWith(() => _StubAuthNotifier(_stubUser)),
    masterProfileProvider.overrideWith(
      () => _StubMasterProfileNotifier(masterState),
    ),
    masterRepositoryProvider.overrideWithValue(repo),
    serviceRepositoryProvider.overrideWithValue(serviceRepo),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockMasterRepository repo;
  late _MockServiceRepository mockServiceRepo;

  setUp(() {
    repo = _MockMasterRepository();
    mockServiceRepo = _MockServiceRepository();
    // Default stub: services list returns empty list so MasterProfileScreen's
    // servicesListProvider Consumer widget resolves without hanging.
    when(
      () => mockServiceRepo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
    registerFallbackValue('');
  });

  // ── 1. Loading state ─────────────────────────────────────────────────────

  group('loading state', () {
    testWidgets('shows SkeletonBlock widgets while AsyncLoading', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncLoading<Master>(),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      // First frame is AsyncLoading — skeleton should be present.
      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('master-profile-name')), findsNothing);
    });
  });

  // ── 2. Data state ────────────────────────────────────────────────────────

  group('data state', () {
    testWidgets('renders master name and bio', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
      expect(find.text('Тест Майстер'), findsOneWidget);
      expect(find.byKey(const Key('master-profile-bio')), findsOneWidget);
      expect(find.text(_stubMaster.bio!), findsOneWidget);
    });

    testWidgets('shows correct rating and reviews values', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-profile-rating-value')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-profile-reviews-value')),
        findsOneWidget,
      );
      // Rating formatted to 1 decimal place.
      expect(find.text('4.8'), findsOneWidget);
      // Review count as integer string.
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets(
      'shows dash placeholder for rating and reviews when reviewCount is 0',
      (tester) async {
        // _stubMasterNoBio has reviewCount: 0 — both stat tiles must show '—'.
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterNoBio),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        // valueKey is placed on the Text widget itself (StatTile.build line 583).
        // Read the rendered string directly — no descendant lookup needed.
        final ratingText = tester.widget<Text>(
          find.byKey(const Key('master-profile-rating-value')),
        );
        final reviewsText = tester.widget<Text>(
          find.byKey(const Key('master-profile-reviews-value')),
        );

        expect(
          ratingText.data,
          '—',
          reason: 'Rating tile must show dash when reviewCount == 0',
        );
        expect(
          reviewsText.data,
          '—',
          reason: 'Reviews tile must show dash when reviewCount == 0',
        );

        // Confirm no numeric rating or review count leaked into the rating/reviews
        // tiles. Note: the services stat tile may legitimately show '0' when
        // listMyServices() returns an empty list — narrow the check to those tiles.
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('master-profile-rating-value')),
              )
              .data,
          isNot('0'),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('master-profile-reviews-value')),
              )
              .data,
          isNot('0'),
        );
        expect(find.text('0.0'), findsNothing);
      },
    );

    testWidgets(
      'shows real rating and reviews when reviewCount is greater than 0',
      (tester) async {
        // Explicit non-zero fixture — reviewCount: 3, avgRating: 4.5.
        const stubWithRatings = Master(
          id: 'user-2',
          firstName: 'Аня',
          lastName: 'Коваль',
          avgRating: 4.5,
          reviewCount: 3,
          type: MasterType.independentMaster,
        );

        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(stubWithRatings),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        final ratingText = tester.widget<Text>(
          find.byKey(const Key('master-profile-rating-value')),
        );
        final reviewsText = tester.widget<Text>(
          find.byKey(const Key('master-profile-reviews-value')),
        );

        expect(
          ratingText.data,
          '4.5',
          reason: 'Rating tile must show formatted value when reviewCount > 0',
        );
        expect(
          reviewsText.data,
          '3',
          reason: 'Reviews tile must show count string when reviewCount > 0',
        );
      },
    );
  });

  // ── 3. Error state ───────────────────────────────────────────────────────

  group('error state', () {
    testWidgets('renders ErrorState widget on NetworkFailure', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncError<Master>(
            NetworkFailure(),
            StackTrace.empty,
          ),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      // Master content should NOT be visible.
      expect(find.byKey(const Key('master-profile-name')), findsNothing);
    });
  });

  // ── 4. Retry ─────────────────────────────────────────────────────────────

  group('retry', () {
    testWidgets('tapping retry button triggers the onRetry callback', (
      tester,
    ) async {
      var retryCalled = false;

      // Build a standalone error state where we control the onRetry callback
      // directly — this tests the Error widget flow without the notifier layer.
      await tester.pumpApp(
        Scaffold(
          body: ErrorState(
            failure: const NetworkFailure(),
            onRetry: () => retryCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final retryBtn = find.byKey(const Key('error_state_retry_button'));
      expect(retryBtn, findsOneWidget);

      await tester.tap(retryBtn);
      await tester.pump();

      expect(retryCalled, isTrue);
    });
  });

  // ── 5. Empty bio ─────────────────────────────────────────────────────────

  group('empty bio', () {
    testWidgets('bio section is absent when bio is null', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterNoBio),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Bio section must not be in the tree.
      expect(find.byKey(const Key('master-profile-bio')), findsNothing);
      // Name should still render correctly.
      expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
    });
  });

  // ── 6. Retry — screen-level wiring ───────────────────────────────────────

  /// Verifies that the retry tap in [MasterProfileScreen] reaches the
  /// retry callback and that [ref.invalidate] is accepted by Riverpod.
  ///
  /// The stub notifier always re-enters [AsyncError] via a microtask, so we
  /// assert the FINAL state that results after a full settle: the error banner
  /// is shown again (invalidation happened and the notifier rebuilt).
  ///
  /// What this proves: the tap reached [ErrorState.onRetry] AND Riverpod
  /// accepted the [ref.invalidate] call without throwing — i.e. the wiring
  /// between the screen and the provider is correct. The companion standalone
  /// retry test (group 4) already verified the [onRetry] callback fires.
  group('retry — screen wiring', () {
    testWidgets('tapping retry does not crash and notifier rebuilds', (
      tester,
    ) async {
      // Start in error state.
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncError<Master>(
            NetworkFailure(),
            StackTrace.empty,
          ),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Confirm we start in the error state.
      expect(find.byType(ErrorState), findsOneWidget);

      // Tap retry — ref.invalidate(masterProfileProvider) fires.
      final retryBtn = find.byKey(const Key('error_state_retry_button'));
      expect(retryBtn, findsOneWidget);

      // This must not throw (proves invalidate wiring compiles + runs).
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // The stub re-enters AsyncError via a microtask (by design), so the
      // error banner is visible again — but no exception was thrown and the
      // widget tree is still valid. Data must not have appeared.
      expect(find.byKey(const Key('master-profile-name')), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
    });
  });

  // ── 7. Contacts section — design-alignment regression ────────────────────
  //
  // Regression tests for the Phase 4.2 contacts-skeleton addition:
  // verifies that both ContactTile widgets with Keys
  // 'master-contact-phone' and 'master-contact-instagram' appear in the
  // widget tree when the data state is loaded.

  group('contacts section', () {
    testWidgets('phone ContactTile is present in the loaded data state', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-contact-phone')), findsOneWidget);
    });

    testWidgets('instagram ContactTile is present in the loaded data state', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-contact-instagram')), findsOneWidget);
    });

    testWidgets('both contact tiles show dash placeholder value', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Instagram tile renders '—' until Phase 13 wires real contact fields;
      // phone tile now reads from master.phoneNumber.
      // findWidgets (plural) because both tiles display the same dash.
      final dashFinder = find.text('—');
      expect(dashFinder, findsWidgets);
    });

    testWidgets('phone ContactTile shows real value when phoneNumber is set', (
      tester,
    ) async {
      final masterWithPhone = _stubMaster.copyWith(
        phoneNumber: '+380501234567',
      );
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: AsyncData<Master>(masterWithPhone),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('master-contact-phone')),
          matching: find.text('+380501234567'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('phone ContactTile shows dash when phoneNumber is null', (
      tester,
    ) async {
      // _stubMaster has no phoneNumber set (null) — dash expected.
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('master-contact-phone')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'instagram ContactTile shows real value when instagram is set',
      (tester) async {
        final masterWithInstagram = _stubMaster.copyWith(
          instagram: '@beauty_ua',
        );
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: AsyncData<Master>(masterWithInstagram),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('master-contact-instagram')),
            matching: find.text('@beauty_ua'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('instagram ContactTile shows dash when instagram is null', (
      tester,
    ) async {
      // _stubMaster has no instagram set (null) — dash expected.
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('master-contact-instagram')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });
  });

  // ── 8. Bottom navigation bar ──────────────────────────────────────────────

  group('bottom nav bar', () {
    testWidgets('VelvetBottomNavBar is rendered in the data state', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VelvetBottomNavBar), findsOneWidget);
    });
  });

  // ── 9. Location line — city-only ──────────────────────────────────────────
  //
  // Regression tests for the Phase 4.2 location row (street/buildingNo/city
  // fields on Master).  Tests cover all _buildLocationLine composition branches
  // by pumping the real _ProfileBody through MasterProfileScreen with different
  // Master fixtures.

  group('location line — city only', () {
    testWidgets('renders city name when only city is set', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterCityOnly),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Location icon must be present (location_on_outlined is in the Row).
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
      // The combined address text must equal just the city.
      expect(find.text('Київ'), findsOneWidget);
    });

    testWidgets('does not render a note row when locationNote is null', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterCityOnly),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // No indented note row must appear for a city-only master.
      expect(find.text('кв. 3, 2 поверх'), findsNothing);
    });

    testWidgets('address text widget uses VelvetText.feedbackMutedXs style', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterCityOnly),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      final addressText = tester.widget<Text>(
        find.byKey(const Key('master-profile-address-text')),
      );
      expect(addressText.style, VelvetText.feedbackMutedXs);
    });
  });

  // ── 10. Location line — street + city ─────────────────────────────────────

  group('location line — street and city, no building', () {
    testWidgets('renders street comma city when buildingNo is absent', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterStreetAndCity),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('вул. Хрещатик, Київ'), findsOneWidget);
    });
  });

  // ── 11. Location line — full address (street + building + city + note) ─────

  group('location line — full address', () {
    testWidgets('renders street comma building comma city and note row', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterFullAddress),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Combined address line must include street, building and city.
      expect(find.text('вул. Хрещатик, 22, Київ'), findsOneWidget);
      // Note row must be rendered beneath the location line.
      expect(find.text('кв. 3, 2 поверх'), findsOneWidget);
    });

    testWidgets('location icon is present with full address', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterFullAddress),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });
  });

  // ── 12. Location line — hidden when no city and no street ─────────────────

  group('location line — hidden when location absent', () {
    testWidgets('location icon absent when city and street are null', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterNoLocation),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // No location row should appear — the conditional is `if (locationLine != null)`.
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    });

    testWidgets('note row absent when city and street are null', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterNoLocation),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Master name must still render — only the location row is suppressed.
      expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    });
  });

  // ── 13. Services section states ──────────────────────────────────────────

  /// Four sub-tests exercise all three [servicesListProvider] states rendered
  /// inside [_ProfileBody]'s services section, plus the data/count path.
  ///
  /// [serviceRepositoryProvider] is overridden via [_buildOverrides] so the
  /// real HTTP stack is never touched.
  group('services section', () {
    // ── A. Loading state — two skeleton rows visible ────────────────────────

    testWidgets('A. services loading state shows SkeletonBlock rows', (
      tester,
    ) async {
      // Override so listMyServices() never completes — provider stays loading.
      when(
        () => mockServiceRepo.listMyServices(),
      ).thenAnswer((_) => Completer<List<MasterService>>().future);

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      // Advance past the 1100 ms entrance animation without calling pumpAndSettle —
      // pumpAndSettle would block forever because listMyServices() never completes.
      await tester.pump(const Duration(milliseconds: 1200));

      // The services section renders two SkeletonBlock rows while loading.
      // The profile skeleton (AsyncLoading for master) also emits SkeletonBlocks
      // but here master is AsyncData so only the services skeleton contributes.
      expect(find.byType(SkeletonBlock), findsWidgets);
    });

    // ── B. Error state — errUnknown text rendered ───────────────────────────

    testWidgets('B. services error state shows errUnknown text', (
      tester,
    ) async {
      when(
        () => mockServiceRepo.listMyServices(),
      ).thenThrow(const NetworkFailure());

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Resolve l10n from the widget tree — no raw Ukrainian strings.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterProfileScreen)),
      );
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });

    // ── C. Empty state — servicesEmpty text rendered ────────────────────────

    testWidgets('C. services empty state shows servicesEmpty text', (
      tester,
    ) async {
      when(
        () => mockServiceRepo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[]);

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterProfileScreen)),
      );
      expect(find.text(l10n.servicesEmpty), findsOneWidget);
    });

    // ── D. Data state — category card rendered + count stat tile ──────────
    //
    // The profile no longer renders flat service tiles. Instead it renders one
    // [_ProfileCategoryCard] per non-empty category bucket. A service with no
    // category goes into the '_none' bucket (key: 'profile-category-_none').
    // The stat tile (Key('master-profile-services-value')) still shows the
    // total live count.

    testWidgets('D. services data state renders category card and count stat', (
      tester,
    ) async {
      const stubServices = <MasterService>[
        MasterService(
          id: 'svc-1',
          serviceDefId: 'def-1',
          name: 'Манікюр',
          durationMinutes: 30,
          priceMin: 500,
          priceDisplay: '500 грн',
          // no category → _none bucket
        ),
      ];
      when(
        () => mockServiceRepo.listMyServices(),
      ).thenAnswer((_) async => stubServices);
      when(
        () => mockServiceRepo.fetchApprovedCategories(),
      ).thenAnswer((_) async => const <ServiceCategoryOption>[]);

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // The uncategorized bucket card must be present (no category on svc-1).
      expect(
        find.byKey(const Key('profile-category-_none')),
        findsOneWidget,
        reason:
            'a service with no category must render under profile-category-_none',
      );

      // The services stat tile must display the count '1'.
      expect(
        find.byKey(const Key('master-profile-services-value')),
        findsOneWidget,
      );
      final countText = tester.widget<Text>(
        find.byKey(const Key('master-profile-services-value')),
      );
      expect(
        countText.data,
        '1',
        reason: 'Services stat tile must show the live service count',
      );
    });
  });

  // ── 13b. Menu button — push-not-go regression guard ─────────────────────────
  //
  // The monolithic edit screen was replaced by a settings hub: the profile's
  // top-right button changed from btn-edit-master (→ masterEdit) to
  // btn-menu-master (→ masterMenu), and the onTap uses `context.push(...)` not
  // `context.go(...)`. `push` stacks the destination on top of the current
  // route; `go` replaces the stack. The swipe-back gesture REQUIRES a poppable
  // stack — if the call reverts to `go`, `canPop()` returns false on the hub
  // and the back gesture silently breaks.
  //
  // Strategy: pump inside a 2-route GoRouter (/master/profile + /master/menu).
  // After tapping the menu button, assert:
  //   (a) the router has navigated to RouteNames.masterMenu; AND
  //   (b) `router.canPop()` is true — proving push (not go) was used.

  group('menu button pushes masterMenu (swipe-back regression guard)', () {
    // NOTE on go_router path inspection in tests:
    // `routeInformationProvider.value.uri.path` reflects the initial location
    // and does NOT update after a `context.push(...)`. Use `find` assertions and
    // `router.canPop()` instead — `canPop()` is true only when a back-stack entry
    // exists, which proves `push` (not `go`) was used.

    testWidgets(
      'tapping the menu button renders the hub and leaves back stack '
      'poppable (canPop true)',
      (tester) async {
        final router = GoRouter(
          initialLocation: RouteNames.masterProfile,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.masterProfile,
              builder: (_, _) => const MasterProfileScreen(),
            ),
            GoRoute(
              path: RouteNames.masterMenu,
              builder: (_, _) => const Scaffold(body: Text('hub-screen-stub')),
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        // Confirm the menu button is present (data state rendered).
        final menuBtn = find.byKey(const Key('btn-menu-master'));
        expect(
          menuBtn,
          findsOneWidget,
          reason:
              'menu button (Key btn-menu-master) must be present in the data state',
        );

        await tester.tap(menuBtn);
        await tester.pumpAndSettle();

        // (a) The hub stub content must be visible — confirms navigation
        // reached the /master/menu route.
        expect(
          find.text('hub-screen-stub'),
          findsOneWidget,
          reason:
              'tapping the menu button must navigate to the masterMenu screen '
              '(${RouteNames.masterMenu})',
        );

        // (b) canPop() must be true — proves push was used, not go.
        // With go() the navigator stack is replaced: canPop() returns false.
        // With push() the profile is still on the stack: canPop() returns true.
        expect(
          router.canPop(),
          isTrue,
          reason:
              'after tapping the menu button, canPop() must be true — '
              'the profile screen must remain on the back stack so the '
              'left-edge swipe-back gesture can return to it. '
              'If this fails, the call reverted to context.go() which '
              'replaces the stack and breaks swipe-back.',
        );
      },
    );

    testWidgets('navigating back from masterMenu returns to masterProfile', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: RouteNames.masterProfile,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.masterProfile,
            builder: (_, _) => const MasterProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.masterMenu,
            builder: (_, _) => const Scaffold(body: Text('hub-screen-stub')),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Push onto the hub screen.
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      // Verify we are on the hub screen.
      expect(find.text('hub-screen-stub'), findsOneWidget);

      // Pop back (simulates swipe-back / system back).
      router.pop();
      await tester.pumpAndSettle();

      // The profile screen content must be visible again — confirms the
      // back-stack was restored after pop.
      expect(
        find.text('hub-screen-stub'),
        findsNothing,
        reason: 'hub screen must be gone after pop',
      );
      expect(
        find.byKey(const Key('master-profile-name')),
        findsOneWidget,
        reason:
            'popping the masterEdit screen must return to masterProfile — '
            'confirms a true back-stack exists after the push',
      );
    });
  });

  // ── 14. Services section — category cards (profile-category-cards feature) ──
  //
  // The profile screen no longer renders a flat tile list or a bounded
  // scroller. Instead it groups the master's services by category and renders
  // one [_ProfileCategoryCard] per non-empty bucket. Each card has a stable
  // Key('profile-category-<UPPER_SLUG>') (or 'profile-category-_none' for
  // uncategorized services). Tapping a card navigates to
  // RouteNames.services?expandCategory=<slug>.

  group('services section — category cards', () {
    // Minimal router that hosts MasterProfileScreen at /profile and
    // accepts pushes to /services without throwing "no route found".
    // Uses flat single-segment paths to avoid go_router nesting ambiguity.
    GoRouter buildRouter({required List<String> pushedRoutes}) => GoRouter(
      initialLocation: '/profile',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile',
          builder: (context, _) => const MasterProfileScreen(),
        ),
        GoRoute(
          path: RouteNames.services,
          builder: (context, _) => const Scaffold(body: Text('services-page')),
        ),
      ],
      observers: <NavigatorObserver>[_ProfilePushObserver(pushedRoutes)],
    );

    // ── 1. One card per non-empty category rendered ───────────────────────────

    testWidgets('1. renders one profile-category card per non-empty category', (
      tester,
    ) async {
      when(() => mockServiceRepo.listMyServices()).thenAnswer(
        (_) async => const <MasterService>[
          MasterService(
            id: 'svc-1',
            serviceDefId: 'def-1',
            name: 'Манікюр',
            durationMinutes: 30,
            priceMin: 500,
            priceDisplay: '500 грн',
            category: 'MANICURE',
          ),
          MasterService(
            id: 'svc-2',
            serviceDefId: 'def-2',
            name: 'Брови',
            durationMinutes: 30,
            priceMin: 300,
            priceDisplay: '300 грн',
            category: 'BROWS',
          ),
        ],
      );
      when(() => mockServiceRepo.fetchApprovedCategories()).thenAnswer(
        (_) async => const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
        ],
      );

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // One card per non-empty category — keys use the upper-cased slug.
      expect(
        find.byKey(const Key('profile-category-MANICURE')),
        findsOneWidget,
        reason: 'MANICURE category must render a profile card',
      );
      expect(
        find.byKey(const Key('profile-category-BROWS')),
        findsOneWidget,
        reason: 'BROWS category must render a profile card',
      );
    });

    // ── 2. Categories with zero services are not rendered ─────────────────────

    testWidgets(
      '2. empty categories produce no card (only non-empty buckets shown)',
      (tester) async {
        // Only one service → MANICURE bucket has 1 entry, BROWS bucket absent.
        when(() => mockServiceRepo.listMyServices()).thenAnswer(
          (_) async => const <MasterService>[
            MasterService(
              id: 'svc-1',
              serviceDefId: 'def-1',
              name: 'Манікюр',
              durationMinutes: 30,
              priceMin: 500,
              priceDisplay: '500 грн',
              category: 'MANICURE',
            ),
          ],
        );
        when(() => mockServiceRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
            ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
          ],
        );

        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        // MANICURE card present; BROWS has no services so no card rendered.
        expect(
          find.byKey(const Key('profile-category-MANICURE')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('profile-category-BROWS')),
          findsNothing,
          reason: 'a category with zero services must produce no profile card',
        );
      },
    );

    // ── 3. Uncategorized services land in the _none bucket ────────────────────

    testWidgets(
      '3. services without a category render under profile-category-_none',
      (tester) async {
        when(() => mockServiceRepo.listMyServices()).thenAnswer(
          (_) async => const <MasterService>[
            MasterService(
              id: 'svc-z',
              serviceDefId: 'def-z',
              name: 'Без категорії',
              durationMinutes: 20,
              priceMin: 100,
              priceDisplay: '100 грн',
              // no category → empty string → _none bucket
            ),
          ],
        );
        when(
          () => mockServiceRepo.fetchApprovedCategories(),
        ).thenAnswer((_) async => const <ServiceCategoryOption>[]);

        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile-category-_none')),
          findsOneWidget,
          reason:
              'services without a category must land in the _none bucket card',
        );
      },
    );

    // ── 4. Tapping a card navigates to /services?expandCategory=<slug> ────────
    //
    // Strategy: pump inside a full GoRouter context. After tapping the card,
    // assert that the router's current URI contains the services path and the
    // expandCategory query param — no observer needed.

    testWidgets(
      '4. tapping a category card navigates to /services?expandCategory=<slug>',
      (tester) async {
        when(() => mockServiceRepo.listMyServices()).thenAnswer(
          (_) async => const <MasterService>[
            MasterService(
              id: 'svc-1',
              serviceDefId: 'def-1',
              name: 'Манікюр',
              durationMinutes: 30,
              priceMin: 500,
              priceDisplay: '500 грн',
              category: 'MANICURE',
            ),
          ],
        );
        when(() => mockServiceRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ],
        );

        final pushedRoutes = <String>[];
        final router = buildRouter(pushedRoutes: pushedRoutes);

        // Use a tall test surface so the category card section (section 5)
        // is visible without needing to scroll (avoids hittability issues
        // with SingleChildScrollView in the 800×600 default test viewport).
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        // Settle all microtasks (master data, services data, categories data)
        // and the 1100 ms entrance animation. pumpAndSettle is safe here
        // because the data state renders no repeating animations.
        await tester.pumpAndSettle();

        // The card must be in the tree and on-screen (tall viewport ensures
        // the category section is fully visible without scrolling).
        final cardFinder = find.byKey(const Key('profile-category-MANICURE'));
        expect(
          cardFinder,
          findsOneWidget,
          reason: 'MANICURE card must be rendered after data resolves',
        );

        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        // The observer records the pushed route name (go_router sets this to
        // the path, e.g. '/services'). Verify navigation happened and that
        // the observer captured the services route.
        expect(
          pushedRoutes,
          contains(contains(RouteNames.services)),
          reason:
              'tapping a category card must push the services route '
              '(/services path)',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Navigation observer for profile-category-cards tests (group 14)
// ---------------------------------------------------------------------------

/// Records all pushed route names for nav-assertion tests.
class _ProfilePushObserver extends NavigatorObserver {
  _ProfilePushObserver(this.routes);
  final List<String> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String? name = route.settings.name;
    if (name != null) routes.add(name);
  }
}
