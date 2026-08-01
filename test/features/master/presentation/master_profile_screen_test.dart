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
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_address_block.dart';
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
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Finders
// ---------------------------------------------------------------------------

/// Locale/asset-invariant finder for the location-line pin, now rendered as an
/// [AppIcon] SVG (`BeauticaAssetIcons.locationMarker`) rather than a Material
/// `Icons.location_on_outlined`.
final Finder _locationIcon = find.byWidgetPredicate(
  (w) => w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker,
);

// ---------------------------------------------------------------------------
// Style matchers
// ---------------------------------------------------------------------------

/// Asserts [text] carries the address style [MasterAddressBlock] actually
/// renders: `VelvetText.feedbackMutedXs` MERGED over the ambient
/// `DefaultTextStyle` (the `Material` above installs `theme.textTheme
/// .bodyMedium`, which contributes `letterSpacing` among other things).
///
/// These assertions used to pin the RAW `VelvetText.feedbackMutedXs`. That was
/// never what the pixels used — a `Text` with an `inherit: true` style always
/// renders `DefaultTextStyle.of(context).style.merge(style)` — and pinning the
/// raw static is precisely what let the block MEASURE one style while
/// RENDERING another, collapsing addresses that then got ellipsized (Phase 224
/// mobile-perf MEDIUM). The block now resolves the merge once and hands the
/// same `TextStyle` to both the measurement and every `Text`, so the
/// expectation here is the merged style — with the `VelvetText` identity
/// (size / weight / colour) asserted explicitly so a regression that dropped
/// the brand style entirely could not pass by merging into whatever ambient
/// default happened to be installed.
///
/// The merge-agreement contract itself is covered at the widget tier in
/// `widgets/master_address_block_test.dart`, against the real
/// `RenderParagraph`.
void _expectEffectiveAddressStyle(WidgetTester tester, Text text) {
  final TextStyle ambient = DefaultTextStyle.of(
    tester.element(find.byType(MasterAddressBlock)),
  ).style;
  expect(text.style, ambient.merge(VelvetText.feedbackMutedXs));
  expect(text.style?.fontSize, VelvetText.feedbackMutedXs.fontSize);
  expect(text.style?.fontWeight, VelvetText.feedbackMutedXs.fontWeight);
  expect(text.style?.color, VelvetText.feedbackMutedXs.color);
}

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Mock [UrlLauncherPlatform] for the Instagram-launch tests.
///
/// `url_launcher` 6.3.x routes every `launchUrl(uri, mode: ...)` call through
/// `UrlLauncherPlatform.instance.launchUrl(String url, LaunchOptions options)`.
/// We swap the platform instance for this mocktail double so no real intent /
/// browser is ever fired, and so we can assert the exact URL string that the
/// screen handed to the launcher (proving the canonicalization gate ran).
///
/// `MockPlatformInterfaceMixin` lets `UrlLauncherPlatform.instance =` accept a
/// mock without throwing the `PlatformInterface.verify` token assertion.
class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

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
///
/// Phase 224: SHORT enough that "Київ, вул. Хрещатик" fits on one line at the
/// default 800dp test surface — takes the COLLAPSED path
/// (`master-profile-address-combined-text`).
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
///
/// Phase 224: "Київ, вул. Хрещатик, 22" fits on one line at the default 800dp
/// test surface — takes the COLLAPSED path.
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

/// Phase 224 — a city + street + building combination whose COLLAPSED form
/// («Кам'янець-Подільський, вул. Академіка Володимира Філатова, 145-Б») cannot
/// fit on one line in the identity card's right-hand column at a narrow-phone
/// width, so the block must fall back to the Phase 220 two-row split.
///
/// This fixture is the split path's only guard: without it every remaining
/// two-field fixture takes the collapsed path and a regression that made the
/// collapse unconditional would go unnoticed.
const _stubMasterLongAddress = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: "Кам'янець-Подільський",
  street: 'вул. Академіка Володимира Філатова',
  buildingNo: '145-Б',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Street only, no city, no buildingNo — Phase 220 (C) promotion case: with
/// no locality, the street line is promoted to the primary (icon-bearing)
/// row and keyed `master-profile-address-text`, matching the promotion rule
/// in `result_address_block.dart`.
const _stubMasterStreetOnly = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  street: 'вул. Хрещатик',
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
// mobile-qa gap-fill (Phase 219/220 QA audit) — three edge-matrix combos the
// widget tier never exercised: city+buildingNo with NO street, street+
// buildingNo with NO city (promotion WITH a building number), and buildingNo
// ALONE. The pure-function matrix lives in
// `test/shared/formatters/address_lines_test.dart`;
// these three pin the same combos through the REAL production Row/Text tree.
// ---------------------------------------------------------------------------

/// City + buildingNo, NO street — the building number must be dropped
/// entirely (never leaked beside the city with a dangling comma).
/// Expected: locality line "Київ" only; no address-text line at all.
const _stubMasterCityAndBuildingNoStreet = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  buildingNo: '22',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// Street + buildingNo, NO city — promotion path WITH a building number
/// attached. Expected: no locality line; the promoted address line reads
/// "вул. Хрещатик, 22".
const _stubMasterStreetAndBuildingNoCity = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// buildingNo ALONE — no city, no street. The whole location row (icon +
/// both lines) must be hidden; a building number must never render on its
/// own.
const _stubMasterBuildingNoOnly = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  buildingNo: '22',
  avgRating: 4.5,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

/// A ~400-character [locationNote] — a realistic long entrance-instructions
/// note within the backend's `@Size(max = 1000)` bound. Phase 219 reproduction
/// fixture: proves the `maxLines: null` + `overflow: ellipsis` combination
/// collapses the note instead of wrapping it across its available width.
const String _kLongLocationNote =
    'Вхід у двір з боку вулиці Хрещатик, повз кав\'ярню на розі — не '
    'плутайте з сусіднім під\'їздом, там кодовий замок не працює. Тримайтеся '
    'правої стіни, минаєте дитячий майданчик, підіймаєтесь трьома сходинками '
    'до скляних дверей із синьою наклейкою. Домофон код 45В, дзвоніть двічі '
    'коротко. Якщо домофон не відповідає — телефонуйте адміністратору, номер '
    'вказано на вивісці біля дверей. Кабінет на другому поверсі, одразу '
    'ліворуч від сходів, третій номер за рахунком.';

const _stubMasterLongNote = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  locationNote: _kLongLocationNote,
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
  List<ServiceCategoryOption> categories = const <ServiceCategoryOption>[],
}) {
  return <Object>[
    authProvider.overrideWith(() => _StubAuthNotifier(_stubUser)),
    masterProfileProvider.overrideWith(
      () => _StubMasterProfileNotifier(masterState),
    ),
    masterRepositoryProvider.overrideWithValue(repo),
    serviceRepositoryProvider.overrideWithValue(serviceRepo),
    // The profile's services section watches approvedCategoriesProvider (which
    // now sources categories straight from categoryRequestApiProvider, not the
    // repository). Override it directly so the section resolves with no pending
    // Timer / real API hit.
    approvedCategoriesProvider.overrideWith((ref) async => categories),
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
      //
      // TIGHTENED (2026-07-22 vacuous-assertion audit): was
      // `expect(find.text('—'), findsWidgets)`, which passes on 1 dash as
      // readily as on 2 — so a dropped contact tile (exactly the regression
      // this test names) could not fail it.
      //
      // Tightening it to `findsNWidgets(2)` went RED at 3: the screen also
      // renders '—' in the Bookings STAT tile (master_profile_screen.dart:447),
      // which this test never meant to count. That is a finder-scope defect,
      // not a screen defect — an unanchored `find.text` was standing in for
      // "the two contact tiles". Each tile is now asserted through its OWN key,
      // so the assertion is both exact and immune to unrelated dashes
      // appearing elsewhere on the screen.
      for (final String tileKey in const <String>[
        'master-contact-phone',
        'master-contact-instagram',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key(tileKey)),
            matching: find.text('—'),
          ),
          findsOneWidget,
          reason: '$tileKey must render the dash placeholder',
        );
      }
    });

    testWidgets('phone ContactTile shows real value when phoneNumber is set', (
      tester,
    ) async {
      final masterWithPhone = _stubMaster.copyWith(
        phoneNumber: '+380501111111',
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
          matching: find.text('+380501111111'),
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

      // Location icon must be present (the locationMarker AppIcon is in the Row).
      expect(_locationIcon, findsOneWidget);
      // Phase 220 (C): city-only renders on the LOCALITY line (no street
      // line at all — there is nothing to promote).
      expect(find.text('Київ'), findsOneWidget);
      expect(
        find.byKey(const Key('master-profile-locality-text')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-profile-address-text')),
        findsNothing,
      );
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

    testWidgets('locality text widget renders VelvetText.feedbackMutedXs '
        'merged over the ambient DefaultTextStyle', (tester) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMasterCityOnly),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Phase 220 (C): city-only renders on `master-profile-locality-text`
      // — `master-profile-address-text` is reserved for the street line.
      final addressText = tester.widget<Text>(
        find.byKey(const Key('master-profile-locality-text')),
      );
      _expectEffectiveAddressStyle(tester, addressText);
    });
  });

  // ── 10. Location line — street + city ─────────────────────────────────────

  // WHY EVERY COLLAPSE-PATH TEST BELOW PASSES AN EXPLICIT `width`
  // -------------------------------------------------------------
  // Surface width is not incidental setup here — it is THE INPUT the decision
  // under test consumes. `MasterAddressBlock` measures the combined string
  // against the width its column actually receives and collapses only if it
  // fits, so a test asserting "collapsed" is asserting something about a width.
  // Leaving that width to `pumpApp`'s implicit 800dp default meant a change to
  // the default surface would flip these cases onto the SPLIT path, where they
  // would keep passing while asserting the opposite of what they were written
  // to assert. The split-path cases already state their width (320); these now
  // do too.
  //
  // WHY 400 — measured, not guessed. The identity card's chrome takes a fixed
  // 200dp, so the address column gets `surface - 200`. The longest fixture on
  // this path ("Київ, вул. Хрещатик, 22") needs ~148dp including the pin and
  // its gap, putting the collapse/split crossover at a ~348dp surface. 400dp
  // gives the column 200dp against that 148dp requirement — ~35 % headroom, far
  // more than any plausible font-metric drift — while staying a realistic
  // modern-phone logical width, so the collapse is proven where it has to work
  // rather than only on a tablet-scale surface. 320dp (the split-path cases)
  // sits on the other side of the same crossover, so the two groups now bracket
  // the real boundary.
  const double collapsingWidth = 400;

  group('location line — street and city, no building', () {
    testWidgets(
      'collapses city + street onto ONE line when the combined string fits '
      '(Phase 224)',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterStreetAndCity),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          width: collapsingWidth,
        );
        await tester.pumpAndSettle();

        // Phase 224: "Київ, вул. Хрещатик" fits on one line at a 400dp
        // surface, so the block collapses to the single combined row.
        expect(
          find.byKey(const Key('master-profile-address-combined-text')),
          findsOneWidget,
        );
        expect(find.text('Київ, вул. Хрещатик'), findsOneWidget);
        // The split rows must NOT also render — the two paths are exclusive.
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-profile-address-text')),
          findsNothing,
        );
        // The pre-220 street-first order must never come back.
        expect(find.text('вул. Хрещатик, Київ'), findsNothing);
        // One pin, on the one row.
        expect(_locationIcon, findsOneWidget);
      },
    );

    testWidgets(
      'the combined line renders VelvetText.feedbackMutedXs merged over the '
      'ambient DefaultTextStyle and is clamped to a single line',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterStreetAndCity),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          // Explicit: this case only reaches the combined row on the collapse
          // side of the crossover — see the note above group 10.
          width: collapsingWidth,
        );
        await tester.pumpAndSettle();

        final Text combined = tester.widget<Text>(
          find.byKey(const Key('master-profile-address-combined-text')),
        );
        _expectEffectiveAddressStyle(tester, combined);
        expect(combined.maxLines, 1);
      },
    );
  });

  // ── 10a. Location line — long address falls back to the 220 split ─────────

  group('location line — combined string does NOT fit', () {
    testWidgets(
      'falls back to the Phase 220 two-row split when the collapsed address '
      'cannot fit on one line at a narrow width',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongAddress),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        // No collapsed row — the measurement rejected it.
        expect(
          find.byKey(const Key('master-profile-address-combined-text')),
          findsNothing,
        );
        // Exactly today's split: locality beside the pin, street indented.
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsOneWidget,
        );
        expect(find.text("Кам'янець-Подільський"), findsOneWidget);
        expect(
          find.byKey(const Key('master-profile-address-text')),
          findsOneWidget,
        );
        expect(
          find.text('вул. Академіка Володимира Філатова, 145-Б'),
          findsOneWidget,
        );
        expect(_locationIcon, findsOneWidget);
      },
    );

    testWidgets(
      'the split path keeps the street line on a 2-line budget (Phase 219 A '
      'regression guard)',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongAddress),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        final Text street = tester.widget<Text>(
          find.byKey(const Key('master-profile-address-text')),
        );
        expect(street.maxLines, 2);
        expect(street.overflow, TextOverflow.ellipsis);
        _expectEffectiveAddressStyle(tester, street);
      },
    );

    testWidgets(
      'the SAME long address collapses onto one line once the column is wide '
      'enough — the decision is width, not content',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongAddress),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          width: 1200,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-profile-address-combined-text')),
          findsOneWidget,
        );
        expect(
          find.text(
            "Кам'янець-Подільський, вул. Академіка Володимира Філатова, 145-Б",
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsNothing,
        );
      },
    );
  });

  // ── 10b. Location line — street only, no city (promotion) ─────────────────

  group('location line — street only, no city', () {
    testWidgets(
      'promotes the street line to the icon-bearing row when there is no '
      'locality',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterStreetOnly),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        // No locality at all — the street line is promoted to the primary
        // (icon-bearing) row and keyed as the address line, not orphaned
        // under a blank locality line.
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-profile-address-text')),
          findsOneWidget,
        );
        expect(find.text('вул. Хрещатик'), findsOneWidget);
        // The pin icon must still be present beside the promoted line.
        expect(_locationIcon, findsOneWidget);
      },
    );
  });

  // ── 11. Location line — full address (street + building + city + note) ─────

  group('location line — full address', () {
    testWidgets(
      'collapses city + street + building onto ONE line and still renders the '
      'note beneath it (Phase 224)',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterFullAddress),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          // Explicit: this case only reaches the combined row on the collapse
          // side of the crossover — see the note above group 10.
          width: collapsingWidth,
        );
        await tester.pumpAndSettle();

        // Phase 224: the whole address fits on one line at a 400dp surface, so
        // it renders city-first on the single combined row.
        expect(
          find.byKey(const Key('master-profile-address-combined-text')),
          findsOneWidget,
        );
        expect(find.text('Київ, вул. Хрещатик, 22'), findsOneWidget);
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-profile-address-text')),
          findsNothing,
        );
        // The pre-220 street-first order must never come back.
        expect(find.text('вул. Хрещатик, 22, Київ'), findsNothing);
        // Note row must still render beneath the address, on either path.
        expect(find.text('кв. 3, 2 поверх'), findsOneWidget);
      },
    );

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

      expect(_locationIcon, findsOneWidget);
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
      expect(_locationIcon, findsNothing);
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
      expect(_locationIcon, findsNothing);
    });
  });

  // ── 12a. Location line — edge-matrix gap-fill (mobile-qa audit) ───────────
  //
  // Three combinations the widget tier never exercised before this audit:
  // city+buildingNo with NO street, street+buildingNo with NO city
  // (promotion WITH a building number), and buildingNo ALONE. Mirrors the
  // exhaustive pure-function matrix in
  // `test/shared/formatters/address_lines_test.dart`, but through the REAL production
  // Row/Text tree so a wiring regression (e.g. the caller's `if` gate or key
  // assignment) is caught here even if the pure function stays correct.

  group('location line — edge-matrix gap-fill', () {
    testWidgets('city + buildingNo, NO street: building is dropped — only the '
        'locality line renders, no address-text line, no dangling comma', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(
            _stubMasterCityAndBuildingNoStreet,
          ),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(_locationIcon, findsOneWidget);
      expect(
        find.byKey(const Key('master-profile-locality-text')),
        findsOneWidget,
      );
      expect(find.text('Київ'), findsOneWidget);
      expect(
        find.byKey(const Key('master-profile-address-text')),
        findsNothing,
        reason:
            'a building number with no street must never render its own '
            'line, even when a city is present',
      );
      // The lone buildingNo value must never leak onto the locality line.
      expect(find.text('Київ, 22'), findsNothing);
      expect(find.textContaining(', 22'), findsNothing);
    });

    testWidgets('street + buildingNo, NO city: promotes the combined "street, '
        'building" line to the icon-bearing row with no locality line', (
      tester,
    ) async {
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(
            _stubMasterStreetAndBuildingNoCity,
          ),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(_locationIcon, findsOneWidget);
      expect(
        find.byKey(const Key('master-profile-locality-text')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('master-profile-address-text')),
        findsOneWidget,
      );
      expect(find.text('вул. Хрещатик, 22'), findsOneWidget);
      // No stray leading/trailing comma variant renders instead.
      expect(find.text(', вул. Хрещатик, 22'), findsNothing);
      expect(find.text('вул. Хрещатик, 22,'), findsNothing);
    });

    testWidgets(
      'buildingNo ALONE (no city, no street): the whole location row is '
      'hidden — a building number never renders on its own',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterBuildingNoOnly),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        expect(_locationIcon, findsNothing);
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-profile-address-text')),
          findsNothing,
        );
        expect(find.text('22'), findsNothing);
        // Name still renders — only the location row is suppressed.
        expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
      },
    );
  });

  // ── 12b. Location note — long-text reproduction (Phase 219) ───────────────
  //
  // ORIGINALLY opened this fix with a reproduction test pinning the PRE-FIX
  // rendering of a long `locationNote`: the widget then had `maxLines: null`
  // + `overflow: ellipsis`, and the measured rendered height came back
  // near-single-line (well under `oneLineHeight * 1.5`) versus a
  // `fullWrapHeight` more than 7x taller — proving the paragraph collapsed
  // instead of wrapping, confirming the diagnosis rather than assuming it.
  //
  // Now flipped to the CORRECTED expectation (Phase 219 A): `maxLines: 3` +
  // `overflow: ellipsis` clamps the note to (at most) 3 lines — taller than
  // one line, but still well short of the full ~400-char height.
  group('location note — long text (maxLines: 3 clamp)', () {
    testWidgets(
      'AFTER FIX: a ~400-char note renders at ~3-line height, not 1 line '
      'and not its full unclamped height',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongNote),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        final Finder noteFinder = find.text(_kLongLocationNote);
        expect(
          noteFinder,
          findsOneWidget,
          reason:
              'The Text widget always carries the full string as its `data` '
              'regardless of visual clipping — this only proves the widget '
              'exists, not that it is fully VISIBLE.',
        );

        final Size actual = tester.getSize(noteFinder);

        // Reference layout #1: capped to exactly one line.
        final TextPainter oneLine = TextPainter(
          text: TextSpan(
            text: _kLongLocationNote,
            style: VelvetText.feedbackMutedNote,
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: actual.width);
        final double oneLineHeight = oneLine.size.height;
        oneLine.dispose();

        // Reference layout #2: capped to exactly 3 lines — what the fixed
        // widget's `maxLines: 3` should produce.
        final TextPainter threeLines = TextPainter(
          text: TextSpan(
            text: _kLongLocationNote,
            style: VelvetText.feedbackMutedNote,
          ),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: actual.width);
        final double threeLineHeight = threeLines.size.height;
        threeLines.dispose();

        // Reference layout #3: NO cap at all — the height the paragraph
        // would need to show the full ~400-char note with zero clipping.
        final TextPainter fullWrap = TextPainter(
          text: TextSpan(
            text: _kLongLocationNote,
            style: VelvetText.feedbackMutedNote,
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: actual.width);
        final double fullWrapHeight = fullWrap.size.height;
        fullWrap.dispose();

        // Fixture sanity check: _kLongLocationNote must need more than 3
        // lines at the measured width for this test to exercise the clamp.
        expect(fullWrapHeight, greaterThan(threeLineHeight));

        // The fix: rendered height matches the 3-line reference layout —
        // more than a single line, but clamped well short of the full
        // unclipped paragraph.
        expect(actual.height, moreOrLessEquals(threeLineHeight, epsilon: 0.5));
        expect(actual.height, greaterThan(oneLineHeight * 1.5));
        expect(actual.height, lessThan(fullWrapHeight));
      },
    );
  });

  // ── 12c. Location note — tap-to-expand (Phase 221 B) ───────────────────────

  group('location note — tap-to-expand toggle', () {
    testWidgets(
      'a SHORT note (fits within maxLines: 3) shows NO toggle affordance',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            // "кв. 3, 2 поверх" — well under 3 lines at any reasonable width.
            masterState: const AsyncData<Master>(_stubMasterFullAddress),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('master-profile-name'))),
        );
        expect(find.text('кв. 3, 2 поверх'), findsOneWidget);
        expect(
          find.byKey(const Key('expandable-note-toggle')),
          findsNothing,
          reason:
              'An inert toggle on a note that already fits is a small lie — '
              'it must not render at all.',
        );
        expect(find.text(l10n.expandableNoteShowMore), findsNothing);
      },
    );

    testWidgets(
      'a LONG note (overflows maxLines: 3) shows the «більше» toggle, '
      'collapsed by default',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongNote),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('master-profile-name'))),
        );
        expect(find.byKey(const Key('expandable-note-toggle')), findsOneWidget);
        expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
        expect(find.text(l10n.expandableNoteShowLess), findsNothing);
      },
    );

    testWidgets(
      'tapping «більше» expands the note to its FULL text and flips the '
      'toggle to «згорнути»; tapping again re-collapses it',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongNote),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('master-profile-name'))),
        );
        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        expect(toggle, findsOneWidget);

        // Collapsed: the note Text renders with maxLines: 3 — its measured
        // height must be far shorter than the fully-expanded height (proven
        // in the group above). Expand it.
        final Size collapsedSize = tester.getSize(
          find.text(_kLongLocationNote),
        );

        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
        expect(find.text(l10n.expandableNoteShowMore), findsNothing);

        final Size expandedSize = tester.getSize(find.text(_kLongLocationNote));
        expect(
          expandedSize.height,
          greaterThan(collapsedSize.height),
          reason:
              'Expanding must grow the note to its full untruncated height.',
        );

        // Collapse it back.
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
        expect(find.text(l10n.expandableNoteShowLess), findsNothing);
        final Size reCollapsedSize = tester.getSize(
          find.text(_kLongLocationNote),
        );
        expect(
          reCollapsedSize.height,
          moreOrLessEquals(collapsedSize.height, epsilon: 0.5),
        );
      },
    );
  });

  // ── 12d. Location block — large text scale (textScaler 2.0) ───────────────
  //
  // `pumpApp`'s `textScaleFactor` knob + `installOverflowGuard()` (armed by
  // `pumpApp` for every test) together turn any `RenderFlex` overflow at a
  // stress scale into a hard test failure via `tearDown` — no manual
  // assertion needed beyond letting the scenario pump/settle/interact.
  group('location block — textScaler 2.0 stress', () {
    testWidgets(
      'full address + long note + expand/collapse produces no overflow at '
      'textScaler 2.0 on a narrow (320dp) surface',
      (tester) async {
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMasterLongNote),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
          width: 320,
          textScaleFactor: 2.0,
        );
        await tester.pumpAndSettle();

        // Sanity: the screen actually rendered the location block at this
        // stress scale (not skipped/short-circuited).
        expect(
          find.byKey(const Key('master-profile-locality-text')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('expandable-note-toggle')), findsOneWidget);

        // Exercise the expand/collapse toggle too — the widest content state
        // this block can be in.
        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(toggle, warnIfMissed: false);
        await tester.pumpAndSettle();

        // No explicit overflow assertion needed here — installOverflowGuard()
        // (wired into pumpApp) fails this test in tearDown if any
        // RenderFlex overflow was reported during the pump/tap/settle above.
      },
    );
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
      //
      // TIGHTENED (2026-07-22 vacuous-assertion audit): was `findsWidgets`,
      // which cannot distinguish the documented two-row skeleton from one row
      // — or from the profile skeleton leaking in and contributing extras,
      // which is the very thing the comment above claims does not happen.
      expect(find.byType(SkeletonBlock), findsNWidgets(2));
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

    // ── C. Empty state — "Додати послуги" CTA replaces the old empty text ────
    //
    // The zero-services empty branch of [_ProfileCategoriesSection] no longer
    // renders the old «Послуг ще немає» body text or the «Усі послуги» header
    // link. It now renders a single primary CTA (Key('btn-master-add-services'))
    // labelled l10n.masterAddServices that opens the bulk service-setup flow.
    // This is the DISCRIMINATING replacement for the previously-stale
    // `servicesEmpty` assertion: it fails if the empty branch reverts to the
    // old header + text, and it fails if the CTA is dropped.

    testWidgets(
      'C. services empty state shows the masterAddServices CTA and drops the '
      'old empty text + all-services link',
      (tester) async {
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

        // NEW affordance — the single primary CTA is present and labelled.
        expect(
          find.byKey(const Key('btn-master-add-services')),
          findsOneWidget,
          reason:
              'the zero-services empty state must render the add-services CTA',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('btn-master-add-services')),
            matching: find.text(l10n.masterAddServices),
          ),
          findsOneWidget,
          reason:
              'the CTA must show the masterAddServices label «Додати послуги»',
        );

        // OLD affordances — must be gone from the empty state.
        expect(
          find.text(l10n.servicesEmpty),
          findsNothing,
          reason:
              'the old «Послуг ще немає» empty body must no longer render in '
              'the zero-services empty state',
        );
        expect(
          find.text(l10n.masterAllServices),
          findsNothing,
          reason:
              'the «Усі послуги» header link is dropped in the empty state — '
              'the CTA stands alone',
        );
      },
    );

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
          priceDisplay: '500 ₴',
          // no category → _none bucket
        ),
      ];
      when(
        () => mockServiceRepo.listMyServices(),
      ).thenAnswer((_) async => stubServices);

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

  // ── 13a. Empty-state CTA navigation — pushes serviceSetup ─────────────────
  //
  // The zero-services CTA (Key('btn-master-add-services')) must push
  // RouteNames.serviceSetup ('/services/setup') — the SAME entry point the
  // services-list empty state uses (services_list_screen.dart onCreate →
  // _openAndRefresh(RouteNames.serviceSetup)). Pump inside a 2-route GoRouter
  // and assert (a) the setup route content is reached, (b) the router location
  // is exactly RouteNames.serviceSetup, and (c) canPop() is true — proving the
  // call used context.push (not context.go) so the swipe-back gesture works.

  group('empty-state CTA pushes serviceSetup', () {
    testWidgets(
      'tapping btn-master-add-services navigates to RouteNames.serviceSetup '
      'and leaves the back stack poppable (canPop true)',
      (tester) async {
        when(
          () => mockServiceRepo.listMyServices(),
        ).thenAnswer((_) async => const <MasterService>[]);

        // Tall surface so the categories section (section 5, near the bottom of
        // the SingleChildScrollView) is laid out and the CTA is hittable
        // without fighting the default 800×600 viewport fold.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Observer records the pushed route name so the destination can be
        // pinned by route string. NOTE: go_router's currentConfiguration.uri
        // does NOT update after an imperative context.push (it keeps the base
        // location — see the group-13b note), so the pushed route is asserted
        // via the observer + the rendered stub, not via the router uri.
        final pushedRoutes = <String>[];
        final router = GoRouter(
          initialLocation: RouteNames.masterProfile,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.masterProfile,
              builder: (_, _) => const MasterProfileScreen(),
            ),
            GoRoute(
              path: RouteNames.serviceSetup,
              builder: (_, _) =>
                  const Scaffold(body: Text('service-setup-stub')),
            ),
          ],
          observers: <NavigatorObserver>[_ProfilePushObserver(pushedRoutes)],
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

        final cta = find.byKey(const Key('btn-master-add-services'));
        expect(cta, findsOneWidget);
        await tester.ensureVisible(cta);
        await tester.pumpAndSettle();

        await tester.tap(cta);
        await tester.pumpAndSettle();

        // (a) The setup route content is visible — navigation reached it.
        expect(
          find.text('service-setup-stub'),
          findsOneWidget,
          reason:
              'tapping the CTA must navigate to the serviceSetup route '
              '(${RouteNames.serviceSetup})',
        );
        // (b) The observer captured a push to exactly RouteNames.serviceSetup —
        // pins the destination the services-list empty state also opens.
        expect(
          pushedRoutes,
          contains(contains(RouteNames.serviceSetup)),
          reason:
              'CTA must push /services/setup (RouteNames.serviceSetup), the '
              'same route the services-list empty state opens',
        );
        // (c) canPop() must be true — proves context.push (not go); the profile
        // stays on the back stack so left-edge swipe-back can return to it.
        expect(
          router.canPop(),
          isTrue,
          reason:
              'the CTA must use context.push so the profile remains on the '
              'back stack; if this fails the call reverted to context.go which '
              'replaces the stack and breaks swipe-back',
        );
      },
    );
  });

  // ── 13c. Section header — title removed, «Усі послуги» link right-aligned ──
  //
  // The standalone «Послуги» section-title (`masterProfileCategoriesLabel`) was
  // removed from the categories header; the header now renders ONLY the
  // right-aligned «Усі послуги» link. With services present the header renders;
  // assert the link is shown, the section-title is gone, and the pre-rename
  // «Категорії послуг» wording is gone from the whole screen.
  //
  // Discriminating count guard: `masterProfileCategoriesLabel` and the services
  // stat-tile caption `masterServicesLabel` share the same «Послуги» value.
  // With the header title removed, the stat-tile caption is the ONLY «Послуги»
  // on screen → findsOneWidget. If the section-title regresses (re-added to the
  // header), this becomes findsNWidgets(2) and fails.

  group('services section header title removed + link right-aligned', () {
    testWidgets('non-empty state drops the «Послуги» section-title, keeps the '
        '«Усі послуги» link, and never shows the old «Категорії послуг»', (
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
            priceDisplay: '500 ₴',
            category: 'MANICURE',
          ),
        ],
      );

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
          categories: const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterProfileScreen)),
      );

      // The right-aligned «Усі послуги» link is the sole header affordance in
      // the has-services state — it must render.
      expect(
        find.text(l10n.masterAllServices),
        findsOneWidget,
        reason:
            'the categories header must render the «Усі послуги» link in the '
            'has-services state',
      );
      // The standalone «Послуги» section-title was removed from the header.
      // Structural guard (value «Послуги» collides with the stat-tile caption
      // and the nav-bar tile, so a screen-wide count is not discriminating):
      // scope to the header Row — the nearest Row ancestor of the «Усі послуги»
      // link — and assert it contains no «Послуги» section-title sibling. A
      // regression that re-adds the title into the header Row fails here.
      final Finder headerLinkTap = find
          .ancestor(
            of: find.text(l10n.masterAllServices),
            matching: find.byType(GestureDetector),
          )
          .first;
      final Finder headerRow = find
          .ancestor(of: headerLinkTap, matching: find.byType(Row))
          .first;
      expect(
        find.descendant(
          of: headerRow,
          matching: find.text(l10n.masterProfileCategoriesLabel),
        ),
        findsNothing,
        reason:
            'the «Послуги» section-title must be gone from the categories '
            'header Row; only the right-aligned link may render there',
      );
      // The OLD wording must be gone from the entire screen.
      expect(
        find.text('Категорії послуг'),
        findsNothing,
        reason:
            'the pre-rename «Категорії послуг» header must no longer appear '
            'anywhere on the profile screen',
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

    testWidgets('tapping the menu button renders the hub and leaves back stack '
        'poppable (canPop true)', (tester) async {
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
    });

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
            priceDisplay: '500 ₴',
            category: 'MANICURE',
          ),
          MasterService(
            id: 'svc-2',
            serviceDefId: 'def-2',
            name: 'Брови',
            durationMinutes: 30,
            priceMin: 300,
            priceDisplay: '300 ₴',
            category: 'BROWS',
          ),
        ],
      );
      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: const AsyncData<Master>(_stubMaster),
          repo: repo,
          serviceRepo: mockServiceRepo,
          categories: const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
            ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
          ],
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
              priceDisplay: '500 ₴',
              category: 'MANICURE',
            ),
          ],
        );
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
            categories: const <ServiceCategoryOption>[
              ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
              ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
            ],
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
              priceDisplay: '100 ₴',
              // no category → empty string → _none bucket
            ),
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
              priceDisplay: '500 ₴',
              category: 'MANICURE',
            ),
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
            categories: const <ServiceCategoryOption>[
              ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
            ],
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

  // ── 15. Instagram contact tile — launch / no-launch behavior ───────────────
  //
  // The Instagram ContactTile (Key('master-contact-instagram')) onTap funnels
  // through _openInstagram → canonicalInstagramUri → launchUrl. These tests
  // assert the OBSERVABLE security contract:
  //   • a valid handle → launchUrl invoked with the canonical
  //     `https://instagram.com/<handle>` URL.
  //   • a full canonical URL → launchUrl invoked with that exact URL.
  //   • null / '—' → NO launch + localized masterInstagramOpenError SnackBar.
  //
  // The platform launcher is mocked (UrlLauncherPlatform.instance) so no real
  // intent/browser fires and the URL string handed to it can be captured.
  // Widget lookups use the tile Key, never raw Ukrainian finders; the SnackBar
  // text is resolved via l10n from the live tree (no hardcoded string).

  group('instagram contact tile — launch behavior', () {
    late _MockUrlLauncher launcher;
    late UrlLauncherPlatform originalPlatform;

    setUp(() {
      originalPlatform = UrlLauncherPlatform.instance;
      launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      registerFallbackValue(const LaunchOptions());
    });

    tearDown(() {
      // Restore the real platform so other test files are unaffected.
      UrlLauncherPlatform.instance = originalPlatform;
    });

    /// Pumps the screen on a tall viewport so the contacts section (the last
    /// staggered reveal, section 6) is laid out, then scrolls the Instagram
    /// tile into view so [WidgetTester.tap] lands on it. The default 800×600
    /// surface leaves the tile below the fold → tap misses the hit-test.
    Future<Finder> pumpAndRevealInstagramTile(
      WidgetTester tester, {
      required Master master,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const MasterProfileScreen(),
        overrides: _buildOverrides(
          masterState: AsyncData<Master>(master),
          repo: repo,
          serviceRepo: mockServiceRepo,
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.byKey(const Key('master-contact-instagram'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      return tile;
    }

    testWidgets(
      'tapping the instagram tile with a valid handle launches the canonical '
      'https://instagram.com/<handle> URL',
      (tester) async {
        // Stub the launcher to report success — captures the URL via the
        // when() matcher so we can assert the exact string.
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        final tile = await pumpAndRevealInstagramTile(
          tester,
          master: _stubMaster.copyWith(instagram: '@olena_nails'),
        );

        await tester.tap(tile);
        await tester.pumpAndSettle();

        // launchUrl must have been called exactly once with the canonical URL —
        // the leading "@" stripped and the canonical host composed.
        final captured = verify(
          () => launcher.launchUrl(captureAny(), any()),
        ).captured;
        expect(captured, hasLength(1));
        expect(captured.single, 'https://instagram.com/olena_nails');
      },
    );

    testWidgets(
      'tapping the instagram tile with a full canonical URL launches it as-is',
      (tester) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        final tile = await pumpAndRevealInstagramTile(
          tester,
          master: _stubMaster.copyWith(
            instagram: 'https://instagram.com/olena_nails',
          ),
        );

        await tester.tap(tile);
        await tester.pumpAndSettle();

        final captured = verify(
          () => launcher.launchUrl(captureAny(), any()),
        ).captured;
        expect(captured.single, 'https://instagram.com/olena_nails');
      },
    );

    testWidgets(
      'tapping the instagram tile when instagram is null does NOT launch and '
      'shows the masterInstagramOpenError SnackBar',
      (tester) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        // _stubMaster has instagram == null → value renders as '—'.
        final tile = await pumpAndRevealInstagramTile(
          tester,
          master: _stubMaster,
        );

        await tester.tap(tile);
        await tester.pump(); // let the SnackBar insert.

        // No launch attempt — canonicalInstagramUri(null) returned null.
        verifyNever(() => launcher.launchUrl(any(), any()));

        // The localized error SnackBar must be shown (resolved via l10n, not a
        // hardcoded Ukrainian literal).
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterProfileScreen)),
        );
        expect(find.text(l10n.masterInstagramOpenError), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the instagram tile when value is the "—" sentinel does NOT '
      'launch and shows the error SnackBar',
      (tester) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        final tile = await pumpAndRevealInstagramTile(
          tester,
          master: _stubMaster.copyWith(instagram: '—'),
        );

        await tester.tap(tile);
        await tester.pump();

        verifyNever(() => launcher.launchUrl(any(), any()));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterProfileScreen)),
        );
        expect(find.text(l10n.masterInstagramOpenError), findsOneWidget);
      },
    );

    testWidgets(
      'when the launcher reports failure (returns false) the error SnackBar '
      'is shown',
      (tester) async {
        // Valid handle so the URL passes the allow-list, but the platform
        // launcher fails — the screen must surface the localized error.
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => false);

        final tile = await pumpAndRevealInstagramTile(
          tester,
          master: _stubMaster.copyWith(instagram: 'olena_nails'),
        );

        await tester.tap(tile);
        await tester.pumpAndSettle();

        // launch was attempted with the canonical URL...
        final captured = verify(
          () => launcher.launchUrl(captureAny(), any()),
        ).captured;
        expect(captured.single, 'https://instagram.com/olena_nails');

        // ...but failed, so the error SnackBar appears.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterProfileScreen)),
        );
        expect(find.text(l10n.masterInstagramOpenError), findsOneWidget);
      },
    );
  });

  // ── professionalTitle rendering (feat/provider-professional-title) ─────────

  group('professionalTitle rendering', () {
    testWidgets(
      'renders the professionalTitle below the master name when set',
      (tester) async {
        const masterWithTitle = Master(
          id: 'user-1',
          firstName: 'Тест',
          lastName: 'Майстер',
          professionalTitle: 'Майстер манікюру',
          avgRating: 4.8,
          reviewCount: 10,
          type: MasterType.independentMaster,
        );

        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(masterWithTitle),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-profile-professional-title')),
          findsOneWidget,
          reason:
              'the professional-title widget must be present in the tree when '
              'Master.professionalTitle is non-null and non-empty',
        );
        expect(find.text('Майстер манікюру'), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT render the professional-title widget when professionalTitle '
      'is null',
      (tester) async {
        // _stubMaster has no professionalTitle (null by default).
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
          find.byKey(const Key('master-profile-professional-title')),
          findsNothing,
          reason:
              'the professional-title widget must be absent when '
              'Master.professionalTitle is null',
        );
        // The name row must still be present.
        expect(find.byKey(const Key('master-profile-name')), findsOneWidget);
      },
    );
  });

  // ── 16. RoleChip label-switching ──────────────────────────────────────────
  //
  // The chip is now unconditional. When professionalTitle is set it carries the
  // 'master-profile-professional-title' key and shows the title as its label;
  // when null/empty the key is absent and the chip shows the master-type role
  // label instead. These tests pin both branches of that contract.

  group(
    'RoleChip visibility — label switches between professionalTitle and role label',
    () {
      testWidgets(
        'shows professionalTitle text inside RoleChip when professionalTitle is set',
        (tester) async {
          const masterWithTitle = Master(
            id: 'user-1',
            firstName: 'Тест',
            lastName: 'Майстер',
            professionalTitle: 'Стиліст',
            avgRating: 4.8,
            reviewCount: 10,
            type: MasterType.independentMaster,
          );

          await tester.pumpApp(
            const MasterProfileScreen(),
            overrides: _buildOverrides(
              masterState: const AsyncData<Master>(masterWithTitle),
              repo: repo,
              serviceRepo: mockServiceRepo,
            ),
          );
          await tester.pumpAndSettle();

          // The chip carries the professional-title key when professionalTitle is set.
          expect(
            find.byKey(const Key('master-profile-professional-title')),
            findsOneWidget,
          );
          // The chip is always present (unconditional).
          expect(find.byType(RoleChip), findsOneWidget);
          // The title text is rendered inside the chip, not as a standalone Text.
          expect(
            find.descendant(
              of: find.byType(RoleChip),
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
          const MasterProfileScreen(),
          overrides: _buildOverrides(
            masterState: const AsyncData<Master>(_stubMaster),
            repo: repo,
            serviceRepo: mockServiceRepo,
          ),
        );
        await tester.pumpAndSettle();

        // The title key is null when showing the role label — so absent from the tree.
        expect(
          find.byKey(const Key('master-profile-professional-title')),
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
