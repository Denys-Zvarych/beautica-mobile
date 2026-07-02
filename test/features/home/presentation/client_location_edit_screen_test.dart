// Widget tests for ClientLocationEditScreen (optional locality cascade only).
//
// For a CLIENT only the locality (oblast → city → district) is meaningful, so
// the free-text address fields (street / buildingNo / locationNote) are NOT
// shown, collected, validated, or sent. Save goes through
// updateMyProfile(touchesLocation: true) on PATCH /users/me. Coverage:
//   • the three address fields are NO LONGER rendered.
//   • saving with NO city selected SUCCEEDS (no "city required" error) and sends
//     a ClientProfileUpdate with touchesLocation true + null cityId.
//   • selecting a city (without districts) persists with that cityId.
//   • selecting a city WITH districts but no district chosen blocks save.
//
// City selection is driven by invoking LocalityCascade.onCity directly to bypass
// the bottom-sheet picker that needs real HTTP. The cached User has cityId null,
// so _prePopulateLocality never touches the list providers (no network). Finders
// use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_location_edit_screen.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

// A CLIENT with NO locality UUIDs, so _prePopulateLocality never touches the
// list providers (cityId is null) — keeps the test purely local.
const _stubUser = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
);

const _oblast = Oblast(
  id: 'oblast-01',
  name: 'Київська',
  katotthCode: 'UA32000000000000000',
);

const _cityNoDistricts = City(
  id: 'city-99',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

const _cityWithDistricts = City(
  id: 'city-77',
  oblastId: 'oblast-01',
  name: 'Львів',
  katotthCode: 'UA46060000000000000',
  hasDistricts: true,
);

class _StubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() => Future<User>.value(_stubUser);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

// ---------------------------------------------------------------------------
// Regression fixtures — Search-tab re-sync on save (bug: after a client saves
// a NEW locality here, `_save()` used to `ref.invalidate(...)` the Search
// tab's keepAlive filter controllers directly. Because the Search tab lives
// inside `ClientShell`'s `StatefulShellRoute.indexedStack`, its State is never
// disposed on a tab switch, so `prefillFromProfileIfNeeded()` — the ONLY call
// site that can re-seed those controllers — never re-fires from
// `initState()`. The invalidate blanked both controllers to their empty
// default with nothing left to re-seed them: the Search tab came back
// EMPTY, not merely stale. The fix replaces the invalidate with an explicit
// `prefillFromProfileIfNeeded()` call so the same locality save that updates
// this screen also re-seeds Search inline.
//
// Both cities sit in the SAME oblast (Київська) and neither has districts, so
// the district-selection path stays out of the way of this regression.
// ---------------------------------------------------------------------------

const _cityStale = City(
  id: 'city-stale-kyiv',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

const _cityNew = City(
  id: 'city-new-odesa',
  oblastId: 'oblast-01',
  name: 'Одеса',
  katotthCode: 'UA51000000000090473',
  hasDistricts: false,
);

// The CLIENT's saved profile locality BEFORE the save under test — what
// [SearchFiltersController.prefillFromProfileIfNeeded] seeds the Search tab
// with on the FIRST (pre-save) call, mirroring the Search tab having already
// been opened once earlier in the session.
const _userAtStaleCity = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
  oblastId: 'oblast-01',
  cityId: 'city-stale-kyiv',
  oblastName: 'Київська',
  cityName: 'Київ',
);

// The same CLIENT profile AFTER the save under test persists — what a real
// `GET /users/me` would return once the PATCH has landed.
const _userAtNewCity = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
  oblastId: 'oblast-01',
  cityId: 'city-new-odesa',
  oblastName: 'Київська',
  cityName: 'Одеса',
);

// Module-level "server state" the fake repository mutates on a successful
// PATCH — mirrors how a real /users/me re-fetch reflects the just-saved
// locality. Reset at the top of the regression test below.
User _mutableProfileAfterPatch = _userAtStaleCity;

class _MutableStubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => _mutableProfileAfterPatch;
}

List<Object> _overridesWithSearchSync(_MockClientProfileRepository repo) =>
    <Object>[
      authProvider.overrideWith(_StubAuthNotifier.new),
      clientEditProfileProvider.overrideWith(_MutableStubClientEditProfile.new),
      clientProfileRepositoryProvider.overrideWithValue(repo),
      oblastListProvider.overrideWith((ref) async => const <Oblast>[_oblast]),
      cityListProvider(
        'oblast-01',
      ).overrideWith((ref) async => const <City>[_cityStale, _cityNew]),
    ];

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.clientEditLocation,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditLocation,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientLocationEditScreen()),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockClientProfileRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  clientEditProfileProvider.overrideWith(_StubClientEditProfile.new),
  clientProfileRepositoryProvider.overrideWithValue(repo),
];

void main() {
  late _MockClientProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
  });

  setUp(() {
    repo = _MockClientProfileRepository();
    when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});
  });

  testWidgets(
    'the free-text address fields (street / buildingNo / locationNote) are NOT '
    'rendered for a CLIENT',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // The locality cascade still renders…
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);
      // …but the three address fields are gone.
      expect(find.byKey(const Key('field-street')), findsNothing);
      expect(find.byKey(const Key('field-buildingNo')), findsNothing);
      expect(find.byKey(const Key('field-locationNote')), findsNothing);
      // Structural guard: with the address fields removed, the loaded Location
      // screen owns NO free-text input at all — the cascade rows are tap-rows
      // (GestureDetector), not TextFields. A surviving TextField here would mean
      // an address field slipped back in.
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'the CLIENT Location screen must render no free-text input',
      );
    },
  );

  testWidgets(
    'renders the CLIENT location subheading copy above the locality cascade',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Read the expected copy through the l10n getter (NOT a hardcoded literal)
      // so the assertion survives copy revisions to [locationSubheading] — it
      // guards that the CLIENT screen wires the key, not a specific wording.
      final BuildContext ctx = tester.element(
        find.byKey(const Key('location-cascade')),
      );
      final String expected = AppLocalizations.of(ctx).locationSubheading;
      expect(find.text(expected), findsOneWidget);
    },
  );

  testWidgets(
    'saving with NO city selected SUCCEEDS (no "city required" error) and sends '
    'touchesLocation true with a null cityId and no address keys',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Pick an oblast (only) to make the form dirty — but never select a city.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onOblast(_oblast);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // It must SAVE (no city-required block) — the screen navigated home.
      expect(captured, isNotNull);
      expect(captured!.touchesLocation, isTrue);
      expect(
        captured!.cityId,
        isNull,
        reason: 'CLIENT location is optional — a null cityId is valid',
      );
      expect(captured!.districtId, isNull);
      expect(find.byKey(const Key('stub-home')), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a city (no districts) persists that cityId and sends no address '
    'keys',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_cityNoDistricts);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.touchesLocation, isTrue);
      expect(captured!.cityId, 'city-99');
      expect(captured!.districtId, isNull);
    },
  );

  testWidgets(
    'selecting a city WITH districts but no district chosen blocks save',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_cityWithDistricts);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // Still on the edit screen; nothing persisted (district required).
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);
      expect(find.byKey(const Key('stub-home')), findsNothing);
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets(
    'a ServerFailure on save surfaces an error snackbar and does NOT navigate '
    'away',
    (tester) async {
      when(
        () => repo.updateMyProfile(any()),
      ).thenThrow(const ServerFailure(statusCode: 500));

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Make the form dirty (pick an oblast only — city stays optional/null) so
      // the Save CTA is enabled and validation passes.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onOblast(_oblast);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pump(); // run the save future + showSnackBar
      await tester.pump(); // let the SnackBar animate in

      // The screen stays put — no navigation to the stub home occurred.
      expect(find.byKey(const Key('stub-home')), findsNothing);
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);

      // The localized ServerFailure message renders inside a SnackBar.
      final BuildContext ctx = tester.element(
        find.byKey(const Key('location-cascade')),
      );
      final String expected = AppLocalizations.of(ctx).errServer;
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(expected),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'saving a NEW locality re-seeds SearchFiltersController with the NEW city '
    '— NOT blank, NOT the stale one (the ref.invalidate(...)-blanks-Search '
    'regression)',
    (tester) async {
      _mutableProfileAfterPatch = _userAtStaleCity;

      final searchRepo = _MockClientProfileRepository();
      ClientProfileUpdate? captured;
      when(() => searchRepo.updateMyProfile(any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
        // Mirrors the backend persisting the PATCH: the very next /users/me
        // read (triggered by this screen's post-save re-fetch) reflects the
        // NEW locality.
        _mutableProfileAfterPatch = _userAtNewCity;
      });

      await tester.pumpRoutedApp(
        _buildRouter(),
        overrides: _overridesWithSearchSync(searchRepo),
      );
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('location-cascade'))),
      );

      // ARRANGE: the Search tab was already opened once earlier this session
      // and seeded with the STALE locality — exactly the precondition this
      // regression depends on (a prior seed that must now be UPDATED, not
      // wiped).
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-stale-kyiv',
        reason:
            'precondition: the Search filter starts seeded with the OLD '
            'locality, as if the Search tab had been opened earlier this '
            'session',
      );

      // ACT: pick the NEW city on the Location screen and save.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_cityNew);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // The save itself persisted the new city and navigated home.
      expect(captured, isNotNull);
      expect(captured!.cityId, 'city-new-odesa');
      expect(find.byKey(const Key('stub-home')), findsOneWidget);

      // THE REGRESSION ASSERTION — pre-fix, `_save()` called
      // `ref.invalidate(searchFiltersControllerProvider)` /
      // `ref.invalidate(searchFilterLabelsControllerProvider)`, which reset
      // both keepAlive controllers to their empty `build()` default (cityId
      // null) with nothing left to re-seed them — since Search's State is
      // never disposed inside `ClientShell`'s `StatefulShellRoute.indexedStack`,
      // nothing re-triggers `prefillFromProfileIfNeeded()` afterwards. That
      // would leave `cityId` at `null` here — worse than the ORIGINAL
      // staleness bug (which would instead leave it stuck at
      // 'city-stale-kyiv'). Only the actual fix — calling
      // `prefillFromProfileIfNeeded()` directly from `_save()` — lands on the
      // NEW city.
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-new-odesa',
        reason:
            'the fix re-seeds the Search filter locality inline via '
            'prefillFromProfileIfNeeded() instead of blanking it with a bare '
            'invalidate',
      );
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Одеса',
        reason: 'the sibling label controller must be re-seeded too',
      );
    },
  );
}
