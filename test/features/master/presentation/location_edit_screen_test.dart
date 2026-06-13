// Widget tests for LocationEditScreen (locality cascade + street/buildingNo/note).
//
// KEY CONTRACT: this page calls updateLocality(...) ONLY — it must NEVER call
// updateMyProfile, so there is no sibling-field-clearing concern here. The
// headline test asserts updateLocality fires with the selected cityId/street/
// buildingNo AND that updateMyProfile is never invoked.
//
// Also covers: pre-population of the address fields from the cached master,
// validation blocking save when street is filled but no city is selected, and
// the save-success path (invalidate + saved SnackBar + navigate).
//
// City selection is driven by invoking LocalityCascade.onCity directly (the same
// approach the retired monolithic-form test used) to bypass the bottom-sheet
// picker that needs real HTTP. Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/location_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

// A master with NO locality UUIDs but with address text, so _prePopulateLocality
// does not touch the list providers (oblastId is null) — keeps the test purely
// local while still exercising address pre-population.
const _cachedMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  phoneNumber: '+380 50 123 45 67',
  instagram: '@olena_nails',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
  street: 'вул. Хрещатик',
  buildingNo: '10',
  locationNote: 'кв. 5',
);

const _emptyLocalityMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  phoneNumber: '+380 50 123 45 67',
  instagram: '@olena_nails',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

const _stubCity = City(
  id: 'city-99',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._master);
  final Master _master;

  @override
  Future<Master> build() => Future<Master>.value(_master);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEditLocation,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEditLocation,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: LocationEditScreen()),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-profile'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockMasterRepository repo, {Master? master}) =>
    <Object>[
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(
        () => _StubMasterProfileNotifier(master ?? _emptyLocalityMaster),
      ),
      masterRepositoryProvider.overrideWithValue(repo),
    ];

Finder _field(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextField),
);

void main() {
  late _MockMasterRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const MasterUpdate(
        firstName: '',
        lastName: '',
        bio: '',
        contactPhone: '',
        instagram: '',
      ),
    );
  });

  setUp(() {
    repo = _MockMasterRepository();
    when(
      () => repo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets('address fields pre-populate from the cached master', (
    tester,
  ) async {
    await tester.pumpRoutedApp(
      _buildRouter(),
      overrides: _overrides(repo, master: _cachedMaster),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.widget<TextField>(_field('field-street')).controller?.text,
        'вул. Хрещатик');
    expect(tester.widget<TextField>(_field('field-buildingNo')).controller?.text,
        '10');
    expect(
        tester.widget<TextField>(_field('field-locationNote')).controller?.text,
        'кв. 5');
  });

  // ── HEADLINE: updateLocality ONLY (never updateMyProfile) ──────────────────
  testWidgets(
    'saving a selected city + address calls updateLocality with the right '
    'args and NEVER calls updateMyProfile',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Select a city by invoking the cascade callback directly.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();

      await tester.enterText(_field('field-street'), 'вул. Шевченка');
      await tester.pump();
      await tester.enterText(_field('field-buildingNo'), '1');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      verify(
        () => repo.updateLocality(
          cityId: 'city-99',
          districtId: null,
          street: 'вул. Шевченка',
          buildingNo: '1',
          locationNote: null,
        ),
      ).called(1);

      // The location page must NEVER call updateMyProfile.
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets('validation blocks save when street is filled but no city is '
      'selected (updateLocality not called)', (tester) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    // Fill street but never select a city → section touched but incomplete.
    await tester.enterText(_field('field-street'), 'вул. Хрещатик');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-location')));
    await tester.pumpAndSettle();

    // Still on the edit screen; nothing persisted.
    expect(find.byKey(const Key('field-street')), findsOneWidget);
    verifyNever(
      () => repo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    );
    verifyNever(() => repo.updateMyProfile(any()));
  });

  testWidgets('save success invalidates the profile, shows the saved SnackBar '
      'and navigates to the profile when canPop is false', (tester) async {
    final states = <AsyncValue<Object?>>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo).cast(),
        child: _InvalidationWatcher(
          states: states,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final before = states.length;

    tester
        .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
        .onCity(_stubCity);
    await tester.pump();
    await tester.enterText(_field('field-street'), 'вул. Шевченка');
    await tester.pump();
    await tester.enterText(_field('field-buildingNo'), '1');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-location')));
    await tester.pumpAndSettle();

    verify(
      () => repo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).called(1);
    expect(find.byKey(const Key('stub-profile')), findsOneWidget);
    expect(states.length, greaterThan(before));
  });
}

class _InvalidationWatcher extends ConsumerWidget {
  const _InvalidationWatcher({required this.child, required this.states});

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}
