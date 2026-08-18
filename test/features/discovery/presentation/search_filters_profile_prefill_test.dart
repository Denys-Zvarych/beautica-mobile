// Widget tests for the saved-profile locality PREFILL on [ClientSearchScreen].
//
// Feature: when a CLIENT who has a saved location opens Пошук, the locality
// filter (oblast → city → district) is pre-filled from their profile. They can
// still change it; a client with NO saved location sees an empty filter.
//
// The prefill is a ONE-TIME, per-session seed owned by
// [SearchFiltersController.prefillFromProfileIfNeeded] (triggered by the
// screen's initState), guarded so it (a) runs at most once per session and
// (b) never clobbers a manual change. These tests pin all three behaviours:
//   a. saved location → filter (ids) + labels (names + cityHasDistricts) seeded;
//   b. no saved location → filter stays empty;
//   c. manual change after prefill survives a navigate-away-and-back (NO re-seed)
//      — the explicit anti-clobber / seamless-reload-footgun regression.
//
// All finders are key/predicate-based (locale-invariant); city/oblast NAMES are
// backend data, asserted as content only. approvedCategoriesProvider is
// overridden directly (it bypasses serviceRepositoryProvider and would otherwise
// hit the real Dio — the recorded fixture footgun).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Locality taxonomy fixtures (drive the prefill's oblast → city → district
// resolution). Київ subdivides (hasDistricts: true) so the District level is
// resolvable; Львів does not.
// ---------------------------------------------------------------------------

const _kOblastId = 'oblast-kyiv';
const _kOblast = Oblast(
  id: _kOblastId,
  name: 'Київська',
  katotthCode: 'UA32000000000000000',
);

const _kCityWithDistrictsId = 'city-kyiv';
const _kCityWithDistricts = City(
  id: _kCityWithDistrictsId,
  oblastId: _kOblastId,
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: true,
);

const _kCityNoDistrictsId = 'city-lviv';
const _kCityNoDistricts = City(
  id: _kCityNoDistrictsId,
  oblastId: _kOblastId,
  name: 'Львів',
  katotthCode: 'UA46000000000026870',
  hasDistricts: false,
);

const _kDistrictId = 'dist-pechersk';
const _kDistrict = CityDistrict(
  id: _kDistrictId,
  cityId: _kCityWithDistrictsId,
  name: 'Печерський',
  katotthCode: 'UA80000000001000000',
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
];

// ── Users ──────────────────────────────────────────────────────────────────

// A CLIENT whose profile carries a full saved locality (Київ / Печерський).
const _userWithLocation = User(
  id: 'u-client-loc',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
  oblastId: _kOblastId,
  cityId: _kCityWithDistrictsId,
  districtId: _kDistrictId,
  oblastName: 'Київська',
  cityName: 'Київ',
  districtName: 'Печерський',
);

// A CLIENT with NO saved location at all.
const _userNoLocation = User(
  id: 'u-client-noloc',
  email: 'client2@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Клієнт',
);

// A SECOND CLIENT whose profile carries a DIFFERENT saved locality (Львів, no
// district — within the same overridden taxonomy so the cascade resolves). Used
// by the cross-session re-seed regression: after a session flip from
// [_userWithLocation] (Київ) to this user, the prefill must seed Львів and the
// prior session's Київ must NEVER persist.
const _userWithLocationLviv = User(
  id: 'u-client-lviv',
  email: 'client3@beautica.ua',
  role: UserRole.client,
  firstName: 'Оксана',
  lastName: 'Клієнт',
  oblastId: _kOblastId,
  cityId: _kCityNoDistrictsId,
  oblastName: 'Київська',
  cityName: 'Львів',
);

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

User _seededUser = _userWithLocation;

class _StubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async {
    // Mirror production (the real ClientEditProfile.build ref.watch(authProvider)s
    // and re-fetches /users/me on a session flip): derive the profile from the
    // ACTIVE session's user so that flipping the auth session yields the NEW
    // user's saved location. The stub auth notifier carries the full location on
    // its [User], so reading session.user is equivalent to a re-fetch.
    final AuthSession? session = ref.watch(authProvider).value;
    if (session is Authenticated) return session.user;
    return _seededUser;
  }
}

// Mutable pointer read by [_MutableStubClientEditProfile.build] — lets a test
// simulate a profile locality change reaching `GET /users/me` WITHOUT a
// session flip (unlike [_StubClientEditProfile], which derives the profile
// from the watched auth session and is only useful for the cross-session-leak
// test). Reset per test.
User _mutableProfile = _userWithLocation;

/// Mirrors production exactly: [ClientEditProfile.build] does NOT watch any
/// session-carried locality fields — it re-reads the repository
/// (`ClientProfileRepository.getMyProfile()`) fresh on every rebuild. So
/// invalidating this provider (as `client_location_edit_screen.dart` does
/// after a successful save) surfaces whatever [_mutableProfile] currently
/// holds. Used by the mid-session-profile-change regression tests below —
/// they flip [_mutableProfile] and call `container.invalidate(...)` to force a
/// re-read, exactly like a real profile save elsewhere in the app.
class _MutableStubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => _mutableProfile;
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final session = AuthSession.authenticated(
      user: _seededUser,
      accessToken: 'tok',
    );
    state = AsyncData<AuthSession>(session);
    return session;
  }

  /// Flips the active session to a DIFFERENT user — the login-after-logout
  /// transition within a single test. Re-emitting a fresh [Authenticated]
  /// re-runs every auth-watching provider's `build()`: the
  /// [SearchFiltersController] (re-arms its one-shot + resets to an empty filter
  /// set) and [ClientEditProfile] (re-fetches the new user's profile). This is
  /// exactly the self-clearing path the production keepAlive providers rely on.
  void flipTo(User user) {
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(user: user, accessToken: 'tok-${user.id}'),
    );
  }
}

// ProviderScope / ProviderContainer overrides expect List<Override>; that name
// is not exported by this Riverpod version, so the list is built as
// List<Object> and `.cast()`-ed at the call sites (the house pattern — see
// test/helpers/pump_app.dart).
List<Object> _overrides({
  ClientEditProfile Function()? profileFactory,
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
  secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
  serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
  clientEditProfileProvider.overrideWith(
    profileFactory ?? _StubClientEditProfile.new,
  ),
  // approvedCategoriesProvider bypasses serviceRepositoryProvider — override it
  // directly so the category rail never reaches the real Dio (fixture footgun).
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[..._categories],
  ),
  // Taxonomy the prefill resolves the saved ids against.
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_kOblast]),
  cityListProvider(_kOblastId).overrideWith(
    (ref) async => const <City>[_kCityWithDistricts, _kCityNoDistricts],
  ),
  districtListProvider(
    _kCityWithDistrictsId,
  ).overrideWith((ref) async => const <CityDistrict>[_kDistrict]),
];

Widget _app() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('uk'),
  home: ClientSearchScreen(),
);

void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SearchFilters _filters(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFiltersControllerProvider);

SearchFilterLabels _labels(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFilterLabelsControllerProvider);

void main() {
  setUp(() {
    _seededUser = _userWithLocation;
    _mutableProfile = _userWithLocation;
  });

  group('ClientSearchScreen — saved-location prefill', () {
    testWidgets(
      'a CLIENT with a saved location → the locality filter is pre-filled '
      '(ids + labels incl. cityHasDistricts)',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation;

        await tester.pumpWidget(
          ProviderScope(
            retry: beauticaProviderRetry,
            overrides: _overrides().cast(),
            child: _app(),
          ),
        );
        await tester.pumpAndSettle();

        // Wire-facing ids seeded from the profile.
        final SearchFilters f = _filters(tester);
        expect(f.oblastId, _kOblastId);
        expect(f.cityId, _kCityWithDistrictsId);
        expect(f.districtId, _kDistrictId);

        // Display labels seeded — cityHasDistricts resolved from the taxonomy
        // (not hardcoded), so the District row gates open correctly.
        final SearchFilterLabels labels = _labels(tester);
        expect(labels.oblastName, 'Київська');
        expect(labels.cityName, 'Київ');
        expect(labels.cityHasDistricts, isTrue);
        expect(labels.districtName, 'Печерський');

        // The city row renders the seeded name (content assertion on the keyed
        // value Text).
        final Text cityText = tester.widget<Text>(
          find.byKey(const Key('search_city_value')),
        );
        expect(cityText.data, 'Київ');
      },
    );

    testWidgets('a CLIENT with NO saved location → the filter stays empty', (
      tester,
    ) async {
      installOverflowGuard();
      _sizeView(tester);
      _seededUser = _userNoLocation;

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
          child: _app(),
        ),
      );
      await tester.pumpAndSettle();

      final SearchFilters f = _filters(tester);
      expect(f.oblastId, isNull);
      expect(f.cityId, isNull);
      expect(f.districtId, isNull);

      final SearchFilterLabels labels = _labels(tester);
      expect(labels.oblastName, isNull);
      expect(labels.cityName, isNull);
      expect(labels.districtName, isNull);

      // The city row shows its placeholder, not a seeded name.
      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('uk'),
      );
      final Text cityText = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityText.data, l10n.searchCityPlaceholder);
    });

    testWidgets('a manual change after prefill SURVIVES a navigate-away-and-back '
        '(same session → NO re-seed)', (tester) async {
      installOverflowGuard();
      _sizeView(tester);
      _seededUser = _userWithLocation;

      // A single container survives the away-and-back so the keepAlive
      // controllers (and the one-shot guard) persist — exactly as a real
      // in-session navigation would.
      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      // 1. Open Пошук → prefill seeds Київ.
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
      );

      // 2. The user manually switches to Львів (a different city in the same
      //    region), mirroring a real pick (filter + labels).
      container.read(searchFiltersControllerProvider.notifier)
        ..selectOblast(oblastId: _kOblastId)
        ..selectCity(cityId: _kCityNoDistrictsId);
      container.read(searchFilterLabelsControllerProvider.notifier)
        ..setOblastName('Київська')
        ..setCityName('Львів')
        ..setCityHasDistricts(false)
        ..setDistrictName(null);
      await tester.pump();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
      );

      // 3. Navigate AWAY (unmounts the screen) ...
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox(key: Key('away'))),
        ),
      );
      await tester.pumpAndSettle();

      // 4. ... and BACK (a fresh ClientSearchScreen → initState re-fires the
      //    prefill trigger).
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      await tester.pumpAndSettle();

      // The manual choice is intact — the prefill did NOT re-seed back to the
      // profile's Київ (this is the anti-clobber / seamless-reload regression).
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
        reason:
            'a re-entry in the same session must not overwrite a manual '
            'locality change with the saved-profile seed',
      );
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Львів',
      );
    });

    testWidgets(
      'a session FLIP (user A → user B) re-arms the one-shot and re-seeds with '
      "B's saved location — A's locality NEVER leaks into B's session "
      '(cross-session-leak guard)',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        // User A signs in with the Київ profile.
        _seededUser = _userWithLocation;

        // One container survives the whole flow (the keepAlive controllers + the
        // session flip live in it) — exactly as the real app's single root
        // ProviderScope does across a logout→login within one process.
        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
        );
        addTearDown(container.dispose);

        // 1. User A opens Пошук → prefill seeds Київ (the city WITH districts).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason: "user A's saved Київ must seed on first open",
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Київ',
        );

        // 2. The session FLIPS to user B (saved location Львів). Re-emitting a
        //    fresh Authenticated re-runs SearchFiltersController.build (watches
        //    authProvider) → it resets to an EMPTY filter set and re-arms the
        //    one-shot. This is the moment A's locality must be shed.
        final _StubAuthNotifier auth =
            container.read(authProvider.notifier) as _StubAuthNotifier;
        auth.flipTo(_userWithLocationLviv);
        await tester.pump();

        // Immediately after the flip — BEFORE any re-seed — A's Київ is already
        // gone: the auth-watched build() cleared the keepAlive filter + labels.
        // This is the core leak assertion: a stale per-user filter cannot
        // survive the session boundary.
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          isNull,
          reason:
              "the session flip must clear user A's seeded locality before B "
              'is seeded (no cross-session leak)',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          isNull,
        );

        // 3. User B navigates AWAY (unmount) ...
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SizedBox(key: Key('away'))),
          ),
        );
        await tester.pumpAndSettle();

        // 4. ... and BACK into Пошук (a fresh ClientSearchScreen → initState
        //    re-fires the prefill against the NEW session).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();

        // 5. The prefill re-armed and seeded B's Львів — NOT A's Київ.
        final SearchFilters f = container.read(searchFiltersControllerProvider);
        expect(
          f.cityId,
          _kCityNoDistrictsId,
          reason: "user B's saved Львів must seed in the new session",
        );
        expect(
          f.cityId,
          isNot(_kCityWithDistrictsId),
          reason: "user A's Київ must never appear in user B's session",
        );
        expect(f.districtId, isNull, reason: 'Львів has no district');

        final SearchFilterLabels labels = container.read(
          searchFilterLabelsControllerProvider,
        );
        expect(labels.cityName, 'Львів');
        expect(
          labels.cityHasDistricts,
          isFalse,
          reason: 'the District row gates closed for the no-districts Львів',
        );

        // And the rendered city row shows B's city — never A's.
        final Text cityText = tester.widget<Text>(
          find.byKey(const Key('search_city_value')),
        );
        expect(cityText.data, 'Львів');
      },
    );

    // -------------------------------------------------------------------------
    // Regression — mid-session PROFILE locality change (NO session flip, NO
    // logout). This is the exact reported bug: the CLIENT changes their saved
    // locality (e.g. via the Location edit screen elsewhere in the app) while
    // staying signed in as the SAME user. The old one-shot `_seededFromProfile`
    // latch seeded at most once per session and never re-checked the profile
    // again, so Пошук kept showing the STALE locality until a full app restart.
    //
    // Unlike the session-FLIP test above (which changes the AUTHENTICATED
    // USER), this exercises the profile-only mismatch path: same user, same
    // session, [clientEditProfileProvider] invalidated + re-read (mirroring
    // `client_location_edit_screen.dart`'s post-save invalidate) between two
    // `prefillFromProfileIfNeeded()` calls.
    // -------------------------------------------------------------------------
    testWidgets(
      'a mid-session PROFILE locality change (no logout) reaches the filter on '
      'the very next prefillFromProfileIfNeeded() call — the reported bug: the '
      'old one-shot latch never re-armed and kept showing the OLD locality '
      'until a restart',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation; // auth session stays fixed — NO flip
        _mutableProfile = _userWithLocation; // profile starts at Київ

        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides(
            profileFactory: _MutableStubClientEditProfile.new,
          ).cast(),
        );
        addTearDown(container.dispose);

        // 1. First Пошук open → prefill seeds Київ (+ Печерський) from the
        //    profile.
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason: 'the first open must seed the saved Київ',
        );
        expect(
          container.read(searchFiltersControllerProvider).districtId,
          _kDistrictId,
        );

        // 2. The CLIENT edits their locality elsewhere in the app (the real
        //    Location edit screen): the PATCH succeeds and the repository now
        //    reports Львів. The screen invalidates clientEditProfileProvider —
        //    forcing the NEXT read to hit the repository again. Crucially, NO
        //    auth/session change happens.
        _mutableProfile = _userWithLocationLviv;
        container.invalidate(clientEditProfileProvider);

        // 3. Re-entering Пошук re-fires prefillFromProfileIfNeeded() (the
        //    screen's initState trigger) — simulated directly here.
        await container
            .read(searchFiltersControllerProvider.notifier)
            .prefillFromProfileIfNeeded();
        await tester.pumpAndSettle();

        // THE REGRESSION ASSERTION — this fails on the pre-fix one-shot latch
        // (`_seededFromProfile == true` forever after the first seed means this
        // second call would no-op, leaving cityId at Київ).
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityNoDistrictsId,
          reason:
              'a mid-session profile locality change must reach the filter on '
              'the very next prefill call — no app restart required',
        );
        expect(
          container.read(searchFiltersControllerProvider).districtId,
          isNull,
          reason:
              'Львів has no district — the stale Печерський must be dropped',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Львів',
        );
      },
    );

    testWidgets(
      'prefillFromProfileIfNeeded (the PASSIVE path): a manual pick BEFORE a '
      'mid-session profile change still wins — the passive profile-driven '
      'reseed must never clobber a genuine user choice, regardless of which '
      'direction the profile itself later changes. This guard is scoped to '
      'prefillFromProfileIfNeeded ONLY — the AUTHORITATIVE '
      'applyProfileLocationSave path (called from '
      'ClientLocationEditScreen._save on an explicit profile-location save) '
      'intentionally bypasses it; see the _userTouchedLocality doc on '
      'SearchFiltersController for why the two are split.',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation;
        _mutableProfile = _userWithLocation; // Київ

        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides(
            profileFactory: _MutableStubClientEditProfile.new,
          ).cast(),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
        );

        // The user manually overrides the seeded locality to Львів through
        // Пошук's own picker — marks _userTouchedLocality.
        container.read(searchFiltersControllerProvider.notifier)
          ..selectOblast(oblastId: _kOblastId)
          ..selectCity(cityId: _kCityNoDistrictsId);
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityNoDistrictsId,
        );

        // Meanwhile (elsewhere) the profile changes AGAIN — back to Київ. This
        // must NOT win over the manual pick, even though it is a genuinely
        // DIFFERENT locality from what was last seeded.
        _mutableProfile = _userWithLocation;
        container.invalidate(clientEditProfileProvider);
        await container
            .read(searchFiltersControllerProvider.notifier)
            .prefillFromProfileIfNeeded();
        await tester.pumpAndSettle();

        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityNoDistrictsId,
          reason:
              'a manual pick must survive ANY subsequent profile-derived seed '
              'attempt, no matter which direction the profile changes',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SAME-USER SESSION REFRESH — the `.select(user.id)` narrowing regression.
  //
  // THE REPORTED BUG: a CLIENT edits their name+surname. The save calls
  // `authProvider.notifier.refreshUser()`, which emits a NEW `Authenticated`
  // session — SAME user id, changed `firstName`/`lastName`, unchanged locality.
  // Before the fix, the three search controllers `ref.watch(authProvider)`ed the
  // WHOLE provider, so that same-user emission re-ran `build()` and reset state
  // to `const SearchFilters()` / empty labels / empty set — WIPING the seeded
  // search locality. Because the Пошук screen is kept alive in the shell's
  // IndexedStack, its one-shot `initState` prefill never re-fired, so the
  // location field stayed empty.
  //
  // The fix narrows the watch to `authProvider.select((s) => settled user id)`
  // so `build()` re-runs ONLY when the SETTLED user id changes (login / logout /
  // account swap) — a same-user re-emission (name/phone edit) no longer resets.
  //
  // These tests emit the SAME-USER refresh directly on the keepAlive controllers
  // WITHOUT re-mounting/re-seeding the screen (mirroring the alive-in-IndexedStack
  // repro) and assert the seed SURVIVES — while a genuine different-user flip
  // still resets (cross-user isolation preserved).
  // ═══════════════════════════════════════════════════════════════════════════
  group('same-user session refresh (refreshUser after a name/phone edit)', () {
    testWidgets(
      'a same-user refreshUser() emission (changed name, SAME id, unchanged '
      'locality) does NOT reset the prefilled locality — filter ids + labels '
      'survive (THE .select(user.id) regression)',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation;

        // A single container survives the emission so the keepAlive controllers
        // persist — exactly as the real root ProviderScope does across a
        // refreshUser() while the Пошук branch stays alive in the IndexedStack.
        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
        );
        addTearDown(container.dispose);

        // 1. Open Пошук → the initState prefill seeds Київ (+ Печерський).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason: 'the saved Київ must seed on first open',
        );
        expect(
          container.read(searchFiltersControllerProvider).districtId,
          _kDistrictId,
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Київ',
        );

        // 2. Simulate `refreshUser()` after a name PATCH: emit a NEW
        //    `Authenticated` value for the SAME user id (u-client-loc) with a
        //    CHANGED name but the SAME locality — WITHOUT navigating away or
        //    re-seeding (the Пошук screen stays mounted, so its one-shot
        //    initState prefill does NOT re-fire). The changed name makes the new
        //    AsyncData value UNEQUAL to the prior one, so the pre-fix
        //    whole-provider watch WOULD re-run build() and wipe the seed here.
        final _StubAuthNotifier auth =
            container.read(authProvider.notifier) as _StubAuthNotifier;
        auth.flipTo(
          _userWithLocation.copyWith(
            firstName: 'Оновлене',
            lastName: 'Прізвище',
          ),
        );
        await tester.pump();

        // THE REGRESSION ASSERTION — on the pre-fix `ref.watch(authProvider)`
        // (whole provider) this same-user emission re-ran build() and reset the
        // keepAlive filter to `const SearchFilters()` (cityId → null); the city
        // row would fall back to its placeholder. The `.select(user.id)` narrow
        // keeps the SETTLED id (u-client-loc) unchanged, so build() does NOT
        // re-run and the seeded locality survives.
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason:
              'a same-user refreshUser() (name edit) must NOT wipe the seeded '
              'locality — only a settled user-id change may reset it',
        );
        expect(
          container.read(searchFiltersControllerProvider).oblastId,
          _kOblastId,
        );
        expect(
          container.read(searchFiltersControllerProvider).districtId,
          _kDistrictId,
          reason: 'the seeded district must survive the same-user refresh too',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Київ',
          reason: 'the display labels must survive the same-user refresh',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityHasDistricts,
          isTrue,
          reason: 'the resolved cityHasDistricts flag must survive too',
        );

        // The rendered city row still shows the seeded name — never wiped to the
        // placeholder (the user-visible symptom of the reported bug).
        final Text cityText = tester.widget<Text>(
          find.byKey(const Key('search_city_value')),
        );
        expect(cityText.data, 'Київ');
      },
    );

    testWidgets(
      'a DIFFERENT-user emission (settled id changes) STILL resets the filter + '
      'labels — the fix preserves cross-user isolation',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation;

        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
        );
        addTearDown(container.dispose);

        // Open Пошук → seed Київ for user A (u-client-loc).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
        );

        // A genuine account swap: emit user B (u-client-lviv) — a DIFFERENT
        // settled id. The `.select(user.id)` now yields a NEW value, so build()
        // re-runs and the per-user filter + labels are shed BEFORE B is seeded.
        // This is the isolation the narrowing must NOT break.
        final _StubAuthNotifier auth =
            container.read(authProvider.notifier) as _StubAuthNotifier;
        auth.flipTo(_userWithLocationLviv);
        await tester.pump();

        expect(
          container.read(searchFiltersControllerProvider).cityId,
          isNull,
          reason:
              "a different settled user id must clear user A's seeded locality "
              '(no cross-account leak)',
        );
        expect(
          container.read(searchFiltersControllerProvider).oblastId,
          isNull,
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          isNull,
          reason: 'the labels reset on a genuine user swap',
        );
      },
    );

    test('SearchServiceSelectionController: a same-user refresh KEEPS an in-progress '
        'service selection, but a different user id still resets it', () {
      _seededUser = _userWithLocation;
      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      // Settle the auth session (the stub sets AsyncData(Authenticated) during
      // build) so the service controller's `.select(user.id)` reads u-client-loc.
      container.read(authProvider);

      // Seed an in-progress second-level service selection.
      container
          .read(searchServiceSelectionControllerProvider.notifier)
          .toggle('CLASSIC_MANICURE');
      expect(container.read(searchServiceSelectionControllerProvider), <String>{
        'CLASSIC_MANICURE',
      });

      // Same-user refresh (name edit) → the selection must NOT be dropped.
      final _StubAuthNotifier auth =
          container.read(authProvider.notifier) as _StubAuthNotifier;
      auth.flipTo(_userWithLocation.copyWith(firstName: 'Оновлене'));
      expect(
        container.read(searchServiceSelectionControllerProvider),
        <String>{'CLASSIC_MANICURE'},
        reason:
            'a same-user refreshUser() must not drop the in-progress service '
            'selection (the third narrowed controller)',
      );

      // A genuine account swap (different settled id) still resets it.
      auth.flipTo(_userWithLocationLviv);
      expect(
        container.read(searchServiceSelectionControllerProvider),
        isEmpty,
        reason:
            'a different settled user id must clear the service selection — '
            'cross-user isolation preserved',
      );
    });

    test('a MANUAL locality pick survives a same-user refreshUser() — the '
        '_userTouchedLocality guard is NOT re-armed by a same-id emission, so '
        'a later prefill still respects the manual choice', () async {
      _seededUser = _userWithLocation;
      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      // Settle the session, then seed Київ from the profile.
      container.read(authProvider);
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
      );

      // The user manually overrides to Львів (marks _userTouchedLocality).
      container.read(searchFiltersControllerProvider.notifier)
        ..selectOblast(oblastId: _kOblastId)
        ..selectCity(cityId: _kCityNoDistrictsId);
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
      );

      // Same-user refresh (name edit): SAME id, so build() must NOT re-run —
      // the manual pick AND its _userTouchedLocality guard both survive.
      final _StubAuthNotifier auth =
          container.read(authProvider.notifier) as _StubAuthNotifier;
      auth.flipTo(_userWithLocation.copyWith(firstName: 'Оновлене'));
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
        reason:
            'a same-user refresh must not reset the manual pick back to empty '
            '(nor reseed it from the profile)',
      );

      // Proof the guard itself survived: a subsequent profile-driven prefill
      // is a no-op against the manual choice (had build() re-run, the guard
      // would be false and this would reseed to the profile Київ).
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
        reason:
            '_userTouchedLocality must remain latched across the same-user '
            'refresh — the profile Київ must never clobber the manual Львів',
      );
    });

    testWidgets('a PHONE-only edit (refreshUser with SAME id, changed '
        'phoneNumber, unchanged name+locality) keeps the prefilled locality — '
        'phone edits ride the same refreshUser() path as name edits', (
      tester,
    ) async {
      installOverflowGuard();
      _sizeView(tester);
      _seededUser = _userWithLocation;

      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
      );

      // refreshUser() after a phone-number PATCH — nothing but phoneNumber
      // changes; the settled user id is unchanged.
      final _StubAuthNotifier auth =
          container.read(authProvider.notifier) as _StubAuthNotifier;
      auth.flipTo(_userWithLocation.copyWith(phoneNumber: '+380671112233'));
      await tester.pump();

      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
        reason:
            'a phone-only refresh must not wipe the seeded locality any more '
            'than a name edit does — both emit a same-id Authenticated value',
      );
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Київ',
      );
    });

    test('two BACK-TO-BACK same-user refreshUser() emissions keep the seeded '
        'locality — the narrowed watch is idempotent across rapid '
        're-emissions', () async {
      _seededUser = _userWithLocation;
      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      container.read(authProvider);
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
      );

      // Two same-user emissions in a row (e.g. a debounce miss firing
      // refreshUser twice) — the settled id never changes, so neither may
      // reset the seed.
      final _StubAuthNotifier auth =
          container.read(authProvider.notifier) as _StubAuthNotifier;
      auth.flipTo(_userWithLocation.copyWith(firstName: 'Раз'));
      auth.flipTo(_userWithLocation.copyWith(firstName: 'Два'));

      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
        reason:
            'rapid same-user re-emissions must be idempotent — the seed '
            'survives all of them',
      );
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Київ',
      );
    });

    testWidgets(
      'cross-user round trip A(Київ) → B(no locality) → back to A: B never sees '
      "A's locality, and returning to A re-seeds Київ on the next screen entry",
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation; // A signs in first (Київ)

        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides().cast(),
        );
        addTearDown(container.dispose);

        // 1. A opens Пошук → Київ seeded.
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
        );

        final _StubAuthNotifier auth =
            container.read(authProvider.notifier) as _StubAuthNotifier;

        // 2. Swap to B (no saved locality). The settled id changes → build()
        //    re-runs and A's Київ is shed immediately.
        auth.flipTo(_userNoLocation);
        await tester.pump();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          isNull,
          reason: "A's locality must not leak into B's session",
        );

        // 3. B navigates away + back → prefill runs against B's empty profile
        //    → the filter stays empty (B has no saved locality, and no A leak).
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SizedBox(key: Key('away'))),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          isNull,
          reason:
              "B's Пошук must show an empty locality — never a stale Київ from A",
        );

        // 4. Swap BACK to A → build() re-runs (id changes again) → cleared.
        auth.flipTo(_userWithLocation);
        await tester.pump();

        // 5. A navigates away + back → prefill re-seeds A's Київ (no stale B
        //    emptiness sticking, no stale A state either — a clean re-seed).
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SizedBox(key: Key('away'))),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason:
              'returning to A must re-seed Київ on the next screen entry — the '
              'per-session guards re-armed cleanly on each id change',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Київ',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // applyProfileLocationSave — the identical-value ("unchanged") short-circuit.
  //
  // A perf fix added `if (unchanged) return;` to applyProfileLocationSave to
  // skip the redundant state/label write when a profile-location save doesn't
  // actually change the locality (the user opened the location editor and
  // saved without picking anything different). The guard reset
  // (`_userTouchedLocality = false`) MUST still run before that early return —
  // it is the entire reason this method exists (see its doc: patched five
  // times before the authoritative/passive split). These tests pin that
  // ordering directly, independent of the emission-count optimisation itself.
  // ═══════════════════════════════════════════════════════════════════════════
  group(
    'applyProfileLocationSave — identical-value save (unchanged branch)',
    () {
      test(
        'a same-locality save still clears _userTouchedLocality — a later '
        'passive prefill is NOT permanently suppressed by the earlier manual '
        'pick, and the no-op save leaves the locality exactly as it was',
        () async {
          _seededUser = _userWithLocation;
          _mutableProfile = _userWithLocation; // Київ / Печерський
          final ProviderContainer container = ProviderContainer(
            retry: beauticaProviderRetry,
            overrides: _overrides(
              profileFactory: _MutableStubClientEditProfile.new,
            ).cast(),
          );
          addTearDown(container.dispose);

          // Known harness trap: authProvider MUST be force-settled before the
          // FIRST read of searchFiltersControllerProvider — an unsettled auth
          // future races the controller's lazy build() and silently re-arms
          // _userTouchedLocality out from under the test, independent of
          // production behaviour.
          await container.read(authProvider.future);

          final controller = container.read(
            searchFiltersControllerProvider.notifier,
          );

          // The user manually picks — through Search's own picker — exactly
          // the locality that will shortly be "saved" from the profile
          // screen, so the `unchanged` branch below is guaranteed to fire.
          controller
            ..selectOblast(oblastId: _kOblastId)
            ..selectCity(cityId: _kCityWithDistrictsId)
            ..selectDistrict(districtId: _kDistrictId);
          expect(
            container.read(searchFiltersControllerProvider).cityId,
            _kCityWithDistrictsId,
          );

          // The identical-value save — the previously untested branch.
          controller.applyProfileLocationSave(
            oblast: _kOblast,
            city: _kCityWithDistricts,
            district: _kDistrict,
          );

          // Property 2 — the early return must not leave state half-written
          // or stale: the locality is still exactly what was there before.
          final SearchFilters afterSave = container.read(
            searchFiltersControllerProvider,
          );
          expect(afterSave.oblastId, _kOblastId);
          expect(afterSave.cityId, _kCityWithDistrictsId);
          expect(afterSave.districtId, _kDistrictId);

          // Property 1 — the guard was cleared DESPITE the early return.
          // Proven observably: swap the profile to a DIFFERENT locality and
          // invoke the PASSIVE prefill. If _userTouchedLocality were still
          // true (the exact bug shape this test exists to catch — the
          // short-circuit reordered above the guard reset),
          // prefillFromProfileIfNeeded would return on its own first line and
          // the filter would stay stuck at Київ forever.
          _mutableProfile = _userWithLocationLviv; // Львів, no district
          await controller.prefillFromProfileIfNeeded();

          final SearchFilters afterPrefill = container.read(
            searchFiltersControllerProvider,
          );
          expect(
            afterPrefill.cityId,
            _kCityNoDistrictsId,
            reason:
                'an identical-value applyProfileLocationSave must still '
                'clear _userTouchedLocality — otherwise the earlier manual '
                'pick would permanently suppress every later profile-driven '
                'prefill, defeating the very method whose job is to make a '
                'profile save win',
          );
          expect(afterPrefill.oblastId, _kOblastId);
          expect(
            afterPrefill.districtId,
            isNull,
            reason: 'Львів has no district',
          );
        },
      );

      test('a null/cleared locality save when the filter is already empty '
          'computes `unchanged == true` correctly (no null-handling comparison '
          'bug) and still clears the guard', () async {
        _seededUser = _userWithLocation;
        _mutableProfile = _userWithLocation; // Київ / Печерський — used
        // later, once the guard has (correctly) cleared.
        final ProviderContainer container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: _overrides(
            profileFactory: _MutableStubClientEditProfile.new,
          ).cast(),
        );
        addTearDown(container.dispose);

        await container.read(authProvider.future);

        final controller = container.read(
          searchFiltersControllerProvider.notifier,
        );

        // Arm the guard with a manual CLEAR (not a pick) — state.oblastId/
        // cityId/districtId are already null on a fresh build(), so this is
        // a no-op on `state` but still marks _userTouchedLocality, exactly
        // like a real "opened the picker and backed out" interaction.
        controller.selectOblast(oblastId: null);
        expect(
          container.read(searchFiltersControllerProvider).oblastId,
          isNull,
        );

        // The null-handling edge: oblast/city/district are all null, and
        // state is already all null — `unchanged` must resolve true via
        // `null == null?.id`, not throw or mis-match.
        controller.applyProfileLocationSave(
          oblast: null,
          city: null,
          district: null,
        );

        final SearchFilters afterSave = container.read(
          searchFiltersControllerProvider,
        );
        expect(afterSave.oblastId, isNull);
        expect(afterSave.cityId, isNull);
        expect(afterSave.districtId, isNull);

        // The guard must still have cleared on this null/null comparison —
        // proven the same way: a subsequent passive prefill against a
        // profile that HAS a saved locality must actually seed it.
        await controller.prefillFromProfileIfNeeded();

        final SearchFilters afterPrefill = container.read(
          searchFiltersControllerProvider,
        );
        expect(
          afterPrefill.cityId,
          _kCityWithDistrictsId,
          reason:
              'a null-locality save must clear _userTouchedLocality just '
              'like a same-value save does — otherwise a manual CLEAR '
              'followed by an unrelated profile save with no locality '
              'would permanently lock Search out of ever seeding a '
              'locality again this session',
        );
        expect(afterPrefill.oblastId, _kOblastId);
        expect(afterPrefill.districtId, _kDistrictId);
      });
    },
  );
}
