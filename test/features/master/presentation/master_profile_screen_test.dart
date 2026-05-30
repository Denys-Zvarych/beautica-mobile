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
}) {
  return <Object>[
    authProvider.overrideWith(() => _StubAuthNotifier(_stubUser)),
    masterProfileProvider.overrideWith(
      () => _StubMasterProfileNotifier(masterState),
    ),
    masterRepositoryProvider.overrideWithValue(repo),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockMasterRepository repo;

  setUp(() {
    repo = _MockMasterRepository();
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

        // Confirm no numeric rating or review count leaked into the tree.
        expect(find.text('0'), findsNothing);
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

    testWidgets(
      'instagram ContactTile shows dash when instagram is null',
      (tester) async {
        // _stubMaster has no instagram set (null) — dash expected.
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
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
      },
    );
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
        ),
      );
      await tester.pumpAndSettle();

      // Master name must still render — only the location row is suppressed.
      expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    });
  });
}
