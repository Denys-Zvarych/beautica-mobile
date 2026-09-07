// Phase 21.2 — Widget tests for SalonManagementProfileScreen.
//
// The inline edit-mode form (settings row popping `true` to flip this
// screen into an edit form) was removed once the settings screen was
// rebuilt to the design — editing now lives in three dedicated screens
// (`SalonProfileEditScreen`, `SalonContactsEditScreen`,
// `SalonAddressEditScreen`) reached from `SalonSettingsScreen`. The 7 tests
// that drove that dead path (top-right-cover-control round-trip, edit mode
// round-trip ×2, edit-form validation ×4) were deleted alongside the
// screen's inline-edit code — see `salon_management_profile_screen.dart`'s
// own file-header EDIT note.
//
// Covers:
//   1. Notification bell + settings gear (top-right cover control row).
//   2. Команда tab: staff grid renders master cards + the trailing add tile.
//   3. Hero card geometry/rating, loading/error states, ownership bounce,
//      resolved-locality address line.
//
// Strategy: a real GoRouter (via `pumpRoutedApp`) registering both
// `/salons/:salonId/manage` and `/salons/:salonId/manage/settings`, mirroring
// `app_router.dart`'s own registration, with `salonRepositoryProvider`
// overridden by an in-memory fake — mirrors
// `public_salon_profile_screen_test.dart`'s harness shape.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_master_card.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/overflow_guard.dart';
import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  avgRating: 4.9,
  reviewCount: 128,
);

const _stubStaff = <SalonStaffMember>[
  SalonStaffMember(
    userId: 'master-1',
    masterId: 'master-1',
    role: SalonStaffRole.master,
    firstName: 'Олена',
    lastName: 'Ковальчук',
    avgRating: 4.9,
    reviewCount: 12,
  ),
  // mobile-qa gap-closure (Phase 21.5) — the «Команда» tab now renders
  // admins too (`_StaFfTab` no longer masters-only), but before this fixture
  // gained an admin entry, EVERY test in this file exercised the master-only
  // branch — the admin card path (Key('salon-manage-staff-card-...') for a
  // SalonStaffRole.admin entry, and its DIFFERENT role label) had zero
  // coverage anywhere in the widget tier.
  SalonStaffMember(
    userId: 'admin-1',
    role: SalonStaffRole.admin,
    firstName: 'Ірина',
    lastName: 'Ковальська',
  ),
];

// ---------------------------------------------------------------------------
// Phase 283 — roster audience-matrix fixtures (staff-side rows, D2/D4/D6).
//
// Each person-type is a SEPARATE const, distinguishable by shape (masterId
// present/absent, `role`), mirroring `SalonStaffMemberResponse`'s own wire
// contract rather than a hand-picked domain shortcut (D6). Distinct ids from
// [_stubStaff] above so a mixed-up fixture would surface as a visibly wrong
// key, not a coincidental pass.
// ---------------------------------------------------------------------------

/// The owner's own staff-roster row — `role` is [SalonStaffRole.master] (the
/// staff wire's `SALON_OWNER` value maps there, same fail-safe direction
/// `SalonStaffMemberMapper._staffRoleFromDto` takes for anything that is not
/// `SALON_ADMIN`), WITH an active master row (`masterId` set). D2's "toggle
/// ON" staff-side cell.
const _matrixOwner = SalonStaffMember(
  userId: 'matrix-owner-1',
  masterId: 'matrix-owner-master-1',
  role: SalonStaffRole.master,
  firstName: 'Оксана',
  lastName: 'Швець',
);

/// D4's edge case — a person with `role = SALON_ADMIN` on the wire (so the
/// mapper resolves [SalonStaffRole.admin]) who ALSO carries an active
/// `masterId` (a master later promoted to admin). The staff roster shows
/// them exactly like [_matrixAdminOnly] below (role-labelled as admin) —
/// their master row only matters on the CLIENT side (see the public screen
/// test's counterpart fixture).
const _matrixDualRole = SalonStaffMember(
  userId: 'matrix-dual-1',
  masterId: 'matrix-dual-master-1',
  role: SalonStaffRole.admin,
  firstName: 'Марта',
  lastName: 'Дворак',
);

/// A plain admin — no master row at all (`masterId` null), structurally
/// unable to reach the client-side `/masters` endpoint (D3).
const _matrixAdminOnly = SalonStaffMember(
  userId: 'matrix-admin-1',
  role: SalonStaffRole.admin,
  firstName: 'Наталя',
  lastName: 'Сидоренко',
);

/// A plain active master — the "always shown, both sides" baseline row.
const _matrixMaster = SalonStaffMember(
  userId: 'matrix-master-1',
  masterId: 'matrix-master-1',
  role: SalonStaffRole.master,
  firstName: 'Софія',
  lastName: 'Бондаренко',
);

/// All four person-types together — the fixture case 7 (D1, no client-side
/// role filter) needs: the staff tab must render exactly these four cards,
/// neither adding nor dropping an entry regardless of `role`.
const _matrixFullRoster = <SalonStaffMember>[
  _matrixOwner,
  _matrixDualRole,
  _matrixAdminOnly,
  _matrixMaster,
];

// ---------------------------------------------------------------------------
// mobile-qa gap-closure (2026-08-29) — resolved-locality fixtures.
//
// `_stubSalon` above carries no oblastId/cityId/districtId and no
// locationNote, so the ENTIRE Phase 21.14 hero-card extension (resolved
// oblast/city/district names + the location-note row) had zero coverage —
// the existing "hero card logo vertical centering" group only ever exercised
// the pre-existing street/buildingNo path. These fixtures give the hero card
// a full triple to resolve AND a note, so the new rows actually render.
// ---------------------------------------------------------------------------

const _heroOblast = Oblast(
  id: 'ob-1',
  name: 'Львівська область',
  katotthCode: 'A',
);
const _heroCity = City(
  id: 'ct-1',
  oblastId: 'ob-1',
  name: 'Львів',
  katotthCode: 'B',
  hasDistricts: true,
);
const _heroDistrict = CityDistrict(
  id: 'd-1',
  cityId: 'ct-1',
  name: 'Галицький',
  katotthCode: 'C',
);

/// Full resolved address, hierarchy-ordered, exactly as
/// `buildFullAddressLine` composes it — the expected on-screen string for
/// [_stubSalonWithTaxonomy]. The oblast (`_heroOblast`) is resolved by
/// [_FakeLocationRepository] to drive the city cascade but deliberately does
/// NOT appear here — product decision 2026-08-29: a salon's oblast never
/// renders to the client.
const String _expectedResolvedAddress =
    'Львів, Галицький, вул. Велика Васильківська, 44';

const _stubSalonWithTaxonomy = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  oblastId: 'ob-1',
  cityId: 'ct-1',
  districtId: 'd-1',
  locationNote: 'Вхід через двір, домофон 42',
  avgRating: 4.9,
  reviewCount: 128,
);

/// Same taxonomy triple, but no [Salon.address] and no street — so the
/// hero card has NOTHING synchronous to fall back on and the address line
/// depends entirely on the resolved names arriving.
const _stubSalonTaxonomyOnly = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  oblastId: 'ob-1',
  cityId: 'ct-1',
  avgRating: 4.9,
  reviewCount: 128,
);

/// A genuinely pre-Phase-10.6 salon: no taxonomy ids, no street — only the
/// legacy composed `address` string is left.
const _stubSalonLegacyAddressOnly = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  address: 'м. Одеса, вул. Дерибасівська, 1',
  avgRating: 4.9,
  reviewCount: 128,
);

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.oblastsCompleter});

  /// When set, `fetchOblasts` awaits this instead of resolving immediately —
  /// used to hold the resolution cascade open indefinitely.
  final Completer<List<Oblast>>? oblastsCompleter;

  @override
  Future<List<Oblast>> fetchOblasts() =>
      oblastsCompleter?.future ??
      Future<List<Oblast>>.value(const <Oblast>[_heroOblast]);

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[
    _heroCity,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      const <CityDistrict>[_heroDistrict];
}

/// Always throws on `fetchOblasts` — proves a resolution FAILURE (caught
/// internally by `resolvedLocalityProvider`, never rethrown) still renders
/// the synchronous street/building line, never a spinner or error box.
class _ThrowingLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => throw const NetworkFailure();

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      const <CityDistrict>[];
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

/// [SalonManagementProfile] stub whose `build()` delegates to [_onBuild] —
/// lets the loading/error test drive the family provider's attempt count
/// directly, sidestepping the `ref.watch(authProvider)` eviction-watch
/// rebuild race routing the same failure through the repository fake would
/// hit (see the error-state test's own doc for the full rationale).
class _AttemptCountingSalonManagementProfile extends SalonManagementProfile {
  _AttemptCountingSalonManagementProfile(this._onBuild);

  final SalonManagementProfileData Function() _onBuild;

  @override
  Future<SalonManagementProfileData> build(String salonId) async => _onBuild();
}

GoRouter _router(FakeSalonRepository repo) => GoRouter(
  initialLocation: RouteNames.salonManage(_kSalonId),
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage',
      builder: (context, state) => SalonManagementProfileScreen(
        salonId: state.pathParameters['salonId']!,
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings',
      builder: (context, state) =>
          SalonSettingsScreen(salonId: state.pathParameters['salonId']!),
    ),
    // The `_bounceIfNotOwned` bounce target (`roleHomePath(salonOwner)`).
    // Only reached by the "does not trust a stale .value" group below — a
    // trivial marker is enough since that group asserts on whether a
    // navigation happened, not on what the destination renders.
    GoRoute(
      path: RouteNames.salonHome,
      builder: (context, state) =>
          const Scaffold(key: Key('salon-home-bounce-target')),
    ),
    // Phase 21.4 — the «+» staff tile's real destination
    // (`RouteNames.salonInviteStaff`). A trivial marker, same pattern as the
    // salonHome bounce target above: the «Команда» tab group below only
    // asserts THAT the add-staff tile navigates, not what InviteStaffScreen
    // itself renders — that screen's own form/role-toggle/error/re-entry-
    // guard coverage lives in
    // `invite_staff_screen_test.dart` (mobile-qa follow-up, 2026-08-29),
    // NOT inline here.
    GoRoute(
      path: '/salons/:salonId/manage/invite',
      builder: (context, state) =>
          const Scaffold(key: Key('invite-staff-marker')),
    ),
    // mobile-qa gap-closure (Phase 21.5) — the staff-card tap's real
    // destination (`RouteNames.salonManageStaffMember`, wired via
    // `_openStaffMember`'s `context.push`). A trivial marker, same pattern
    // as the invite-staff marker above: this file only asserts THAT tapping
    // a staff card navigates (and to the RIGHT memberId), not what
    // `SalonStaffProfileScreen` itself renders — that screen's own
    // master/admin body coverage lives in
    // `salon_staff_profile_screen_test.dart`, NOT inline here. The key
    // embeds `memberId` so the tap test can distinguish "navigated to the
    // TAPPED card's member" from "navigated to A staff member".
    GoRoute(
      path: '/salons/:salonId/manage/staff/:memberId',
      builder: (context, state) => Scaffold(
        key: Key('staff-profile-marker-${state.pathParameters['memberId']}'),
      ),
    ),
    // Destinations of the «Про салон» tab's two owner-only "add" links. Same
    // trivial-marker pattern as the routes above — this file asserts THAT
    // each link navigates to the right edit form; those forms' own coverage
    // lives in `salon_edit_forms_test.dart`.
    GoRoute(
      path: '/salons/:salonId/manage/settings/profile-edit',
      builder: (context, state) =>
          const Scaffold(key: Key('profile-edit-marker')),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/contacts-edit',
      builder: (context, state) =>
          const Scaffold(key: Key('contacts-edit-marker')),
    ),
  ],
);

const _stubAdmin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністратор',
  salonId: _kSalonId,
);

/// SALON_ADMIN session — this screen renders identically for an admin except
/// that the owner-only "add" links must NOT appear (their destinations are
/// gated by `salonManageOwnerOnlyGuard`).
class _AdminAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubAdmin, accessToken: 'tok');
}

List<Object> _adminOverrides(FakeSalonRepository repo) => <Object>[
  authProvider.overrideWith(_AdminAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
];

List<Object> _overrides(FakeSalonRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
];

/// Same as [_overrides], plus a [locationRepositoryProvider] override —
/// needed by every test that exercises `resolvedLocalityProvider`'s actual
/// resolve path rather than its null-id short-circuit.
List<Object> _overridesWithLocation(
  FakeSalonRepository repo,
  LocationRepository locationRepo,
) => <Object>[
  ..._overrides(repo),
  locationRepositoryProvider.overrideWith((_) => locationRepo),
];

void main() {
  // mobile-qa gap-closure (salon-cover work, 2026-08-29) — the notification
  // bell shipped on this cover's top-right control row (ported verbatim
  // from `docs/signup-designs/SalonManagementDesign/lib/screens/
  // salon_profile_screen.dart:369-425`) with zero coverage anywhere: no
  // golden renders this screen's cover, and no widget test asserted the
  // bell's key, its wired asset, its position relative to the settings
  // gear, or its accessible name's deliberately-plain wording (the control
  // is inert — `onTap: () {}` — so its label must not claim an unread
  // state a screen-reader user could not act on or dismiss).
  group('notification bell (cover redesign)', () {
    testWidgets(
      'renders before the settings button in the top-right row, wired to '
      'the notificationUnread asset',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final Finder bellFinder = find.byKey(
          const Key('salon-manage-notifications'),
        );
        final Finder settingsFinder = find.byKey(
          const Key('salon-manage-settings'),
        );
        expect(bellFinder, findsOneWidget);
        expect(settingsFinder, findsOneWidget);

        final CoverIconButton bell = tester.widget<CoverIconButton>(bellFinder);
        expect(
          bell.svgIcon,
          BeauticaAssetIcons.notificationUnread,
          reason:
              'the bell must render the baked-in-unread-dot asset per the '
              'approved design',
        );
        expect(
          bell.icon,
          isNull,
          reason: 'icon/svgIcon are mutually exclusive on CoverIconButton',
        );

        final CoverIconButton settings = tester.widget<CoverIconButton>(
          settingsFinder,
        );
        expect(settings.icon, Icons.tune_rounded);
        expect(settings.svgIcon, isNull);

        // Order is real: the design places notifications LEFT of settings
        // in the row. A geometric proof (rendered x-offset), not a
        // source-order read — a change that kept the Row's child order but
        // flipped the visual result would still be caught here.
        final double bellX = tester.getTopLeft(bellFinder).dx;
        final double settingsX = tester.getTopLeft(settingsFinder).dx;
        expect(
          bellX,
          lessThan(settingsX),
          reason:
              'the bell must render to the LEFT of the settings gear — '
              'matching the approved design\'s top-right control row order',
        );
      },
    );

    testWidgets(
      'accessible name stays plain — must NOT claim an unread state the '
      'inert control cannot dismiss',
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final String label = tester
            .getSemantics(find.byKey(const Key('salon-manage-notifications')))
            .getSemanticsData()
            .label;

        final ukL10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(
          label,
          ukL10n.salonManageNotificationsSemanticLabel,
          reason:
              'pins the exact accessible name to the ARB key — a future '
              'edit concatenating an unread claim onto this label must '
              'fail here',
        );
        expect(
          label.toLowerCase(),
          isNot(contains('непрочит')),
          reason:
              'onTap is a no-op — a screen-reader user must never be told '
              'about unread notifications they cannot act on or dismiss',
        );

        final enL10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(
          enL10n.salonManageNotificationsSemanticLabel.toLowerCase(),
          isNot(contains('unread')),
          reason: 'same contract, English locale — ARB parity',
        );

        handle.dispose();
      },
    );

    testWidgets('tapping the bell neither navigates nor throws', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-manage-notifications')));
      await tester.pumpAndSettle();

      // Still on the management screen — no crash, no navigation away.
      expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
    });
  });

  group('Команда tab', () {
    testWidgets('renders staff cards plus the trailing add-staff tile', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon, staff: _stubStaff);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-manage-staff-card-master-1')),
        findsOneWidget,
      );
      // mobile-qa gap-closure (Phase 21.5) — the roster now includes admins;
      // the admin card must render too, with the admin-specific role label
      // (not the master's), proving the tab actually branches on role and
      // does not merely render every entry as a master card.
      final Finder adminCard = find.byKey(
        const Key('salon-manage-staff-card-admin-1'),
      );
      expect(adminCard, findsOneWidget);
      expect(
        tester.widget<SalonMasterCard>(adminCard).role,
        l10n.salonStaffRoleAdmin,
      );
      expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-staff-empty')), findsNothing);

      // Phase 21.4 — the add-staff tile navigates to InviteStaffScreen
      // (`RouteNames.salonInviteStaff`). mobile-qa gap-closure (Phase 21.5) —
      // with the admin fixture added above, the grid now spans 2 rows at the
      // default test surface, pushing the add-staff tile below the fold;
      // scroll it into view before tapping (mirrors the integration flow's
      // own `ensureVisible` precedent for this exact tile).
      final Finder addStaffTile = find.byKey(
        const Key('salon-manage-add-staff'),
      );
      await tester.ensureVisible(addStaffTile);
      await tester.pumpAndSettle();
      await tester.tap(addStaffTile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invite-staff-marker')), findsOneWidget);
    });

    // mobile-qa gap-closure (Phase 21.5, build-verifier FAIL) — before this
    // test, the staff-card tap's `context.push(RouteNames
    // .salonManageStaffMember(...))` wiring (`_openStaffMember`,
    // `salon_management_profile_screen.dart`) had NO test asserting it was
    // ever actually invoked. Uses `context.push` (via the real
    // `_openStaffMember` callback) — never `router.go` — matching this
    // codebase's documented go_router trap: a pushed leaf's fullPath is
    // excluded from a naive location comparison, so a `router.go`-based
    // assertion here would falsely pass even if the tap wired nothing at
    // all. Asserting on the mounted marker widget (keyed by memberId) sides
    // steps that trap entirely.
    testWidgets(
      'tapping a staff card navigates to that member\'s staff profile route',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon, staff: _stubStaff);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('salon-manage-staff-card-master-1')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('staff-profile-marker-master-1')),
          findsOneWidget,
          reason:
              'must navigate to THIS card\'s own memberId, not some other '
              'staff member',
        );
      },
    );

    testWidgets('shows the empty-state message when the salon has no masters', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        staff: const <SalonStaffMember>[],
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-manage-staff-empty')), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
    });

    // mobile-qa LOW closure (2026-08-29) — previously reported "accepted,
    // not fixed" on the claim that no widget-tier hook could pin
    // `salonManageTabStaff`'s rendered value without tripping
    // `forbid_cyrillic_finder.sh`. That claim was wrong on both counts: the
    // guard only forbids a Cyrillic literal INSIDE a `find.text(...)` call
    // (`scripts/forbid_cyrillic_finder.sh:53`), and an agent cannot
    // self-accept its own finding regardless. This LOCATES the tab by its
    // stable `Key('salon-tab-1')` (never by text) and compares the rendered
    // `Text.data` against the literal — proving the string a user actually
    // sees, not merely restating the ARB file back at itself (an
    // `l10n.salonManageTabStaff == 'Команда'` assertion would do that and
    // catch nothing).
    testWidgets(
      'staff tab renders the current «Команда» label, not the retired '
      '«Персонал» one',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon, staff: _stubStaff);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final Finder staffTabLabel = find.descendant(
          of: find.byKey(const Key('salon-tab-1')),
          matching: find.byType(Text),
        );
        expect(staffTabLabel, findsOneWidget);
        expect(
          tester.widget<Text>(staffTabLabel).data,
          'Команда',
          reason:
              'salonManageTabStaff was renamed from «Персонал» to «Команда» '
              '2026-08-29 (see app_uk.arb); this must go red if that value '
              'regresses, independent of the getter under test.',
        );
      },
    );
  });

  // mobile-qa gap-closure (feat/salon-master-schedule-read-only) — the
  // `viewerIsAdmin` filter at `salon_management_profile_screen.dart:287-306`
  // (an admin's «Команда» tab shows masters only, never themselves; the
  // owner sees masters AND admins — there is deliberately no owner-side
  // filter, since the roster is already built from master + SALON_ADMIN
  // queries that never include the owner) shipped with 149 passing tests in
  // this file and ZERO of them exercising a mixed roster under an admin
  // viewer — every existing `_adminOverrides` pump in this file uses an
  // empty staff list (see the «Про салон» `pumpAs` helper above), which
  // cannot distinguish "filtered" from "nothing to filter".
  group('Команда tab admin filter (mobile-qa gap-closure)', () {
    testWidgets(
      'admin viewer + mixed roster (master + admin) — only the master card '
      'renders',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon, staff: _stubStaff);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _adminOverrides(repo),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-manage-staff-card-master-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-manage-staff-card-admin-1')),
          findsNothing,
        );
        // Exactly one rendered card — proves the GRID itself was rebuilt on
        // a shrunk list (itemCount == staff.length + 1), not merely that
        // the admin's specific key was hidden by some other means while the
        // grid still allocated a slot for it.
        expect(find.byType(SalonMasterCard), findsOneWidget);
        expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
        expect(find.byKey(const Key('salon-manage-staff-empty')), findsNothing);
      },
    );

    testWidgets(
      'owner viewer + the same mixed roster — the admin card still renders',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon, staff: _stubStaff);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-manage-staff-card-master-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-manage-staff-card-admin-1')),
          findsOneWidget,
          reason:
              'without this, a mutation that filters admin rows for EVERY '
              'viewer (not just an admin one) stays green.',
        );
        expect(find.byType(SalonMasterCard), findsNWidgets(2));
      },
    );

    testWidgets(
      'admin viewer + an admins-ONLY roster lands in the empty state, not a '
      'roster of invisible cards',
      (tester) async {
        final repo = FakeSalonRepository(
          salon: _stubSalon,
          staff: const <SalonStaffMember>[
            SalonStaffMember(
              userId: 'admin-only-1',
              role: SalonStaffRole.admin,
              firstName: 'Ірина',
              lastName: 'Ковальська',
            ),
            SalonStaffMember(
              userId: 'admin-only-2',
              role: SalonStaffRole.admin,
              firstName: 'Наталя',
              lastName: 'Бондар',
            ),
          ],
        );
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _adminOverrides(repo),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        // Filtered to zero — the empty-state message must show and the
        // grid must hold zero master cards, not two admin cards rendered
        // invisibly (that shape would mean the filter was applied inside
        // `itemBuilder`, e.g. returning an empty SizedBox per admin entry,
        // instead of at the source list — itemCount would then still be
        // wrong even though no admin key is findable).
        expect(
          find.byKey(const Key('salon-manage-staff-empty')),
          findsOneWidget,
        );
        expect(find.byType(SalonMasterCard), findsNothing);
        expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
      },
    );
  });

  // The logo used to centre against the name+rating row only, leaving it
  // above the card's true midpoint whenever an address line added a second
  // band below (root-caused 2026-08-29: the address row reserved an empty
  // gutter under the logo instead of extending the height the logo centres
  // against). Fixed by folding the address into the same right-hand column
  // as name+rating, so the outer Row's `center` alignment spans the whole
  // stack. `_stubSalon` carries street/buildingNo, so `addressLine` is
  // non-null here — exactly the case that was broken.
  group('hero card logo vertical centering', () {
    testWidgets(
      'logo centre coincides with the card centre when an address line is '
      'present',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-manage-address')), findsOneWidget);

        final Offset logoCenter = tester.getCenter(find.byType(SalonLogo));
        final Offset cardCenter = tester.getCenter(
          find.byKey(const Key('salon-manage-hero-card')),
        );

        expect(
          logoCenter.dy,
          closeTo(cardCenter.dy, 2),
          reason:
              'logo must centre against the FULL card content (name + '
              'rating + address), not just the top row',
        );
      },
    );

    testWidgets('no-address salon still renders the hero card without '
        'overflow (single-row case unaffected by the restructure)', (
      tester,
    ) async {
      const noAddressSalon = Salon(
        id: _kSalonId,
        name: 'Салон без адреси',
        avgRating: 4.5,
        reviewCount: 3,
      );
      final repo = FakeSalonRepository(salon: noAddressSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-address')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long address respects maxLines 2 + ellipsis at 320dp with no overflow',
      (tester) async {
        const longAddressSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          street:
              'вулиця Дуже-Дуже Довга Назва Вулиці Яка Точно Не Поміститься',
          buildingNo: '144-Б, корпус 12, офіс 305',
          avgRating: 4.9,
          reviewCount: 128,
        );
        final repo = FakeSalonRepository(salon: longAddressSalon);
        tester.view.physicalSize = const Size(320, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-manage-address')), findsOneWidget);
        final Text addressWidget = tester.widget<Text>(
          find.byKey(const Key('salon-manage-address')),
        );
        expect(addressWidget.maxLines, 2);
        expect(addressWidget.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('hero card rating star (mobile-qa gap-closure — Icon→RatingStar '
      'swap)', () {
    // Phase 21.2 follow-up (2026-08-29) — the hero card swapped a decorative
    // `Icon(Icons.star_rounded)` for `RatingStar(rating: salon.avgRating,
    // size: 16, showLabel: false)`, matching salon_staff_profile_screen.dart.
    // Every existing test in this file only asserted the SIBLING
    // `Text(ratingLabel)` (the '4.9' / '—' string), which renders identically
    // either way — so nothing here pinned the widget swap or the fractional
    // fill it exists to provide. These three close that gap.

    Finder heroRatingStar() => find.descendant(
      of: find.byKey(const Key('salon-manage-hero-card')),
      matching: find.byType(RatingStar),
    );

    testWidgets(
      'hero card renders a RatingStar (not a Material star Icon) wired to '
      "the salon's own avgRating",
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon); // avgRating 4.9
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        expect(
          heroRatingStar(),
          findsOneWidget,
          reason:
              'a revert to Icon(Icons.star_rounded) inside the hero card '
              'must fail here',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('salon-manage-hero-card')),
            matching: find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.star_rounded,
            ),
          ),
          findsNothing,
          reason:
              'the Material star Icon must be fully gone, not merely '
              'joined by RatingStar',
        );

        final RatingStar star = tester.widget<RatingStar>(heroRatingStar());
        expect(
          star.rating,
          _stubSalon.avgRating,
          reason:
              "RatingStar.rating must reach the screen's real "
              'salon.avgRating, not a hardcoded/default value',
        );
        expect(star.showLabel, isFalse);
      },
    );

    testWidgets(
      "RatingStar's rating tracks salon.avgRating, not a fixed constant "
      '(a hardcoded rating would pass the 4.9 fixture above but fail here)',
      (tester) async {
        const distinctRatingSalon = Salon(
          id: _kSalonId,
          name: 'Салон «Вельвет»',
          avgRating: 2.3,
          reviewCount: 5,
        );
        final repo = FakeSalonRepository(salon: distinctRatingSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final RatingStar star = tester.widget<RatingStar>(heroRatingStar());
        expect(star.rating, 2.3);
        expect(
          RatingStar.fillFor(star.rating),
          closeTo(RatingStar.fillFor(2.3), 0.0001),
          reason:
              'the fractional fill this widget exists to provide must '
              'actually derive from the passed-through rating',
        );
        // Sanity: 2.3 and 4.9 must not coincidentally fill the same amount —
        // otherwise the fill assertion above would be unable to distinguish
        // a correct wiring from a hardcoded one.
        expect(
          RatingStar.fillFor(2.3),
          isNot(closeTo(RatingStar.fillFor(4.9), 0.0001)),
        );
      },
    );

    testWidgets(
      'null avgRating renders an empty RatingStar and the "—" label, never '
      'a numeric or default-filled star',
      (tester) async {
        const noRatingSalon = Salon(
          id: _kSalonId,
          name: 'Салон без рейтингу',
          // avgRating omitted — defaults to null (0 reviews).
        );
        final repo = FakeSalonRepository(salon: noRatingSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final RatingStar star = tester.widget<RatingStar>(heroRatingStar());
        expect(star.rating, isNull);
        expect(RatingStar.fillFor(star.rating), 0.0);
        expect(find.text('—'), findsOneWidget);
      },
    );
  });

  group('loading / error states (mobile-qa M3)', () {
    testWidgets('shows a spinner while the initial load is in flight', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      // ONE frame only — before the fake repo's Future settles.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-hero-card')), findsNothing);
    });

    testWidgets(
      'a repository Failure renders ErrorState, and tapping retry reloads',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        var attempt = 0;
        // Overrides [salonManagementProfileProvider] directly (bypassing
        // [salonRepositoryProvider]) — mirrors
        // `public_salon_profile_screen_test.dart`'s identical error-state
        // test. Routing the failure through the repository fake instead races
        // `authProvider`'s own async `build()` (Loading -> Data), which
        // rebuilds this family provider mid-flight and inflates the observed
        // attempt count non-deterministically (a `ref.watch(authProvider)`
        // eviction watch is what causes the rebuild — see this notifier's own
        // `build()` doc).
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: <Object>[
            ..._overrides(repo),
            salonManagementProfileProvider(_kSalonId).overrideWith(() {
              return _AttemptCountingSalonManagementProfile(() {
                attempt++;
                if (attempt == 1) throw const ServerFailure(statusCode: 500);
                return (_stubSalon, _stubStaff);
              });
            }),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('salon-manage-hero-card')), findsNothing);

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsNothing);
        expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------
  // mobile-qa gap-closure (2026-08-28) — `_bounceIfNotOwned`'s
  // `next is! AsyncData<List<Salon>>` concrete-subtype gate had ZERO direct
  // coverage on the (non-embedded) screen itself before this group — this
  // was a live MEDIUM defect (the screen used to trust a bare `.value` read)
  // until this chain added the gate, mirroring `salonManageGuard`'s own gate
  // in `app_router.dart` (see that guard's mutation-verified coverage in
  // `salon_manage_route_guard_test.dart`).
  //
  // DEVIATION FROM THE LITERAL "stale value CONTAINS the salonId" framing —
  // documented, not silent (mobile-qa M14: an assertion must be provable by
  // mutation, never merely plausible):
  //
  // A stale `.value` that CONTAINS the route's salonId is indistinguishable
  // from the fix under the exact regression this group guards against
  // (`final salons = next.value; if (salons == null) return;`): both the
  // weakened code and the fixed code read "contains -> no bounce" / "not
  // AsyncData -> no bounce" — SAME observable outcome, so that shape cannot
  // mutation-prove anything (confirmed by hand before writing this group).
  // The shape that DOES distinguish them is a stale value that does NOT
  // contain the salonId — mirroring `salon_manage_route_guard_test.dart`'s
  // OWN already-proven "stale .value that does NOT contain the route
  // salonId" group for the router guard's identical gate — because only
  // there do the two readings diverge: weakened code sees "not owned",
  // bounces the legitimate owner away on stale/wrong data; fixed code sees
  // "not genuinely resolved", stays put.
  //
  // The listener must never be exposed to a genuinely-resolved MISMATCHED
  // `AsyncData` frame first (that case correctly bounces under BOTH old and
  // new code — a real, if less interesting, bug class already covered by
  // `salon_manage_route_guard_test.dart`'s `_bounceIfNotOwned` group). So the
  // AsyncError-with-stale-mismatched-value is driven directly via the
  // notifier's own `state` setter — bypassing `build()` entirely — rather
  // than through two natural rebuilds, which would necessarily pass through
  // that uninteresting intermediate frame first.
  //
  // MUTATION-VERIFIED (mobile-qa, 2026-08-28) — replacing this screen's
  // `_bounceIfNotOwned` gate (`if (next is! AsyncData<List<Salon>>) return;`)
  // with `final salons = next.value; if (salons == null) return;` turns the
  // test below RED (it bounces to RouteNames.salonHome instead of staying);
  // restoring the gate turns it back GREEN with a clean `git diff`. See the
  // QA report for the exact commands run.
  group('_bounceIfNotOwned does not trust a stale .value '
      '(mobile-security MEDIUM follow-up gap-closure)', () {
    testWidgets('AsyncError with a previous .value that does NOT contain the '
        'mounted salonId is treated as UNRESOLVED -> stays mounted, never '
        'bounced on stale/wrong data', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_StubAuthNotifier.new),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _router(repo),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: mounted normally (mySalonsProvider's own real build,
      // via `repo.getMySalons()`, resolves to `[_stubSalon]` — the
      // owner genuinely owns this salon, so no bounce yet).
      expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);

      // Drive mySalonsProvider DIRECTLY into an AsyncError carrying a
      // stale, MISMATCHED .value via copyWithPrevious — the shape a
      // genuine cross-account refresh failure leaves behind (per this
      // group's own doc, constructed this way specifically to avoid an
      // intermediate genuinely-resolved mismatched AsyncData frame).
      // `copyWithPrevious` is `@internal` to the riverpod package — this
      // is the ONLY public-API-reachable way to construct this EXACT
      // state shape without first passing the listener through a
      // genuinely-resolved mismatched AsyncData frame (which would
      // correctly bounce under BOTH the buggy and fixed gate, proving
      // nothing — see this group's own doc).
      final AsyncError<List<Salon>> staleError = AsyncError<List<Salon>>(
        const NetworkFailure(),
        StackTrace.current,
      );
      const AsyncData<List<Salon>> stalePrevious = AsyncData<List<Salon>>(
        <Salon>[Salon(id: 'a-different-salon-entirely', name: 'Different')],
      );
      // ignore: invalid_use_of_internal_member
      container.read(mySalonsProvider.notifier).state = staleError
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(stalePrevious);
      await tester.pumpAndSettle();
      expect(
        container.read(mySalonsProvider),
        isA<AsyncError<List<Salon>>>(),
        reason:
            'the state must actually BE an AsyncError for this test to '
            'exercise the concrete-subtype gate at all',
      );
      expect(
        container.read(mySalonsProvider).value,
        isNotNull,
        reason:
            'copyWithPrevious must retain the stale list on .value — '
            'this IS the exploitable shape the fix guards against',
      );
      expect(
        find.byKey(const Key('salon-manage-hero-card')),
        findsOneWidget,
        reason:
            'an AsyncError state — even one carrying a stale, '
            'non-owning .value — must be treated as UNRESOLVED and '
            'never bounce the screen away',
      );
    });
  });

  // mobile-qa gap-closure (2026-08-29) — `_stubSalon` (used by every test
  // above, including the existing "hero card logo vertical centering"
  // group) carries no oblastId/cityId/districtId and no locationNote, so
  // the resolved-name address AND the location-note row had zero coverage
  // — the logo-centering guard "passed" only because those rows were
  // ABSENT, proving the OLD layout, not the new one.
  group('resolved locality + location note (mobile-qa gap-closure)', () {
    testWidgets('a salon with a full city/district pair renders the '
        'RESOLVED names, hierarchy-ordered ahead of street/building — the '
        'oblast is resolved for the cascade but never rendered', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalonWithTaxonomy);
      await tester.pumpRoutedApp(
        _router(repo),
        overrides: _overridesWithLocation(repo, _FakeLocationRepository()),
      );
      await tester.pumpAndSettle();

      final Finder addressFinder = find.byKey(
        const Key('salon-manage-address'),
      );
      expect(addressFinder, findsOneWidget);
      final Text addressWidget = tester.widget<Text>(addressFinder);
      expect(
        addressWidget.data,
        _expectedResolvedAddress,
        reason:
            'city -> district -> street -> building, exactly the '
            'hierarchy order buildFullAddressLine composes — a reordered '
            'or dropped segment fails this exact-match; the oblast name '
            '("Львівська область") must NOT appear anywhere in this string',
      );
      expect(
        addressWidget.data,
        isNot(contains('Львівська область')),
        reason:
            'even if hierarchy order drifted, the oblast text must never '
            'leak into the rendered address line',
      );
    });

    testWidgets(
      'a salon with locationNote renders the note row beneath the address',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonWithTaxonomy);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _overridesWithLocation(repo, _FakeLocationRepository()),
        );
        await tester.pumpAndSettle();

        final Finder noteFinder = find.byKey(
          const Key('salon-manage-location-note'),
        );
        expect(noteFinder, findsOneWidget);
        expect(
          tester.widget<ExpandableNote>(noteFinder).text,
          _stubSalonWithTaxonomy.locationNote,
        );
      },
    );

    testWidgets(
      'logo centre still coincides with the card centre when BOTH the '
      'resolved multi-part address AND the location note are present',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonWithTaxonomy);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _overridesWithLocation(repo, _FakeLocationRepository()),
        );
        await tester.pumpAndSettle();

        // Sanity: both new rows are actually present — otherwise this test
        // would silently degrade back into the OLD (already-covered)
        // address-only shape the pre-existing centering group checks.
        expect(find.byKey(const Key('salon-manage-address')), findsOneWidget);
        expect(
          find.byKey(const Key('salon-manage-location-note')),
          findsOneWidget,
        );

        final Offset logoCenter = tester.getCenter(find.byType(SalonLogo));
        final Offset cardCenter = tester.getCenter(
          find.byKey(const Key('salon-manage-hero-card')),
        );

        expect(
          logoCenter.dy,
          closeTo(cardCenter.dy, 2),
          reason:
              'logo must still centre against the FULL card content (name '
              '+ rating + resolved address + note), not just the rows the '
              'pre-existing address-only guard happened to cover',
        );
      },
    );

    testWidgets('while resolution is still pending, the hero card renders '
        'street/building immediately — never a spinner or error box', (
      tester,
    ) async {
      final oblastsCompleter = Completer<List<Oblast>>();
      final repo = FakeSalonRepository(salon: _stubSalonWithTaxonomy);
      await tester.pumpRoutedApp(
        _router(repo),
        overrides: _overridesWithLocation(
          repo,
          _FakeLocationRepository(oblastsCompleter: oblastsCompleter),
        ),
      );
      // Bounded pumps only — the resolution cascade is deliberately held
      // open (oblastsCompleter never completes in this test), so
      // pumpAndSettle would hang.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
      final Finder addressFinder = find.byKey(
        const Key('salon-manage-address'),
      );
      expect(addressFinder, findsOneWidget);
      expect(
        tester.widget<Text>(addressFinder).data,
        contains('вул. Велика Васильківська'),
        reason:
            'street/buildingNo are plain salon fields — must render on '
            'the FIRST frame, never waiting on the async lookup',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a resolution FAILURE (repository throws) is swallowed — the hero '
      'card still renders street/building, no error box',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonWithTaxonomy);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _overridesWithLocation(
            repo,
            _ThrowingLocationRepository(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder addressFinder = find.byKey(
          const Key('salon-manage-address'),
        );
        expect(addressFinder, findsOneWidget);
        expect(
          tester.widget<Text>(addressFinder).data,
          contains('вул. Велика Васильківська'),
        );
        expect(find.byType(ErrorState), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a genuinely pre-taxonomy salon (no oblastId/cityId, no street) still '
      'falls back to the legacy composed salon.address',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonLegacyAddressOnly);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _overridesWithLocation(repo, _FakeLocationRepository()),
        );
        await tester.pumpAndSettle();

        final Finder addressFinder = find.byKey(
          const Key('salon-manage-address'),
        );
        expect(addressFinder, findsOneWidget);
        expect(
          tester.widget<Text>(addressFinder).data,
          _stubSalonLegacyAddressOnly.address,
          reason:
              'no taxonomy ids and no street/buildingNo -> the legacy '
              'salon.address is the only thing left to fall back to',
        );
      },
    );

    testWidgets(
      'a salon with ONLY taxonomy ids (no street, no legacy address) shows '
      'nothing until resolution completes, then shows the resolved city',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalonTaxonomyOnly);
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: _overridesWithLocation(repo, _FakeLocationRepository()),
        );
        await tester.pumpAndSettle();

        final Finder addressFinder = find.byKey(
          const Key('salon-manage-address'),
        );
        expect(addressFinder, findsOneWidget);
        expect(tester.widget<Text>(addressFinder).data, contains('Львів'));
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------
  // «Про салон» tab — contacts block + the two owner-only "add" links
  // ---------------------------------------------------------------------
  group('«Про салон» tab — contacts + add links', () {
    Future<void> pumpAs(
      WidgetTester tester,
      Salon salon, {
      bool owner = true,
    }) async {
      final repo = FakeSalonRepository(salon: salon);
      await tester.pumpRoutedApp(
        _router(repo),
        overrides: owner ? _overrides(repo) : _adminOverrides(repo),
      );
      await tester.pumpAndSettle();
    }

    final Finder phoneRow = find.byKey(const Key('salon-manage-contact-phone'));
    final Finder instagramRow = find.byKey(
      const Key('salon-manage-contact-instagram'),
    );
    final Finder addDescription = find.byKey(
      const Key('salon-manage-add-description'),
    );
    final Finder addInstagram = find.byKey(
      const Key('salon-manage-add-instagram'),
    );
    // Every string finder below is l10n-sourced, never a Cyrillic literal
    // (scripts/forbid_cyrillic_finder.sh).
    AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(
      tester.element(find.byType(SalonManagementProfileScreen)),
    );
    Finder contactsHeadingOf(WidgetTester tester) =>
        find.text(l10nOf(tester).masterContactsLabel);

    // The public read path now carries `phone`, so these four combinations
    // are reachable on a first load rather than only after a PATCH.
    testWidgets('phone only — phone row renders, no Instagram row', (
      tester,
    ) async {
      await pumpAs(
        tester,
        _stubSalon.copyWith(phone: '+380671112233'),
        owner: false,
      );
      expect(phoneRow, findsOneWidget);
      expect(instagramRow, findsNothing);
      expect(contactsHeadingOf(tester), findsOneWidget);
    });

    testWidgets('instagram only — Instagram row renders, no phone row', (
      tester,
    ) async {
      await pumpAs(
        tester,
        _stubSalon.copyWith(instagramUrl: '@velvet'),
        owner: false,
      );
      expect(phoneRow, findsNothing);
      expect(instagramRow, findsOneWidget);
    });

    testWidgets('both — both rows render', (tester) async {
      await pumpAs(
        tester,
        _stubSalon.copyWith(phone: '+380671112233', instagramUrl: '@velvet'),
        owner: false,
      );
      expect(phoneRow, findsOneWidget);
      expect(instagramRow, findsOneWidget);
    });

    testWidgets(
      'neither, NON-owner — the whole «Контакти» section is hidden (the '
      'add-link is owner-only, so there is nothing to host)',
      (tester) async {
        await pumpAs(tester, _stubSalon, owner: false);
        expect(phoneRow, findsNothing);
        expect(instagramRow, findsNothing);
        expect(addInstagram, findsNothing);
        expect(contactsHeadingOf(tester), findsNothing);
      },
    );

    testWidgets(
      'neither, OWNER — the section renders with the «Додати посилання» link '
      'as its only row',
      (tester) async {
        await pumpAs(tester, _stubSalon);
        expect(contactsHeadingOf(tester), findsOneWidget);
        expect(addInstagram, findsOneWidget);
        expect(
          find.text(l10nOf(tester).salonManageAddInstagramLink),
          findsOneWidget,
        );
        expect(phoneRow, findsNothing);
        expect(instagramRow, findsNothing);
      },
    );

    testWidgets(
      'neither, OWNER — the add-link node is a ContactTile (not the old '
      '_AddLink) carrying the placeholder field contract',
      (tester) async {
        // mobile-qa (2026-08-31): the key-only assertion above passed
        // UNCHANGED across the _AddLink -> ContactTile swap — a plain
        // GestureDetector+Text and a StatefulWidget with a glyph well, a
        // two-line label/value column and a chevron both satisfy
        // `find.byKey(...), findsOneWidget`. This test pins the RESOLVED
        // TYPE, which the key alone cannot distinguish.
        await pumpAs(tester, _stubSalon);

        // 1. Resolved widget TYPE — the assertion the key-only test above
        // could never make.
        expect(tester.widget(addInstagram), isA<ContactTile>());

        // 2. Field contract. NOTE: these are constructor-field reads, not
        // render/behaviour assertions — they prove the SCREEN wired the
        // right values into ContactTile, not that ContactTile renders them
        // correctly (that half is covered by contact_tile_test.dart, which
        // tests ContactTile in isolation against the actual rendered
        // Text/TextStyle).
        final ContactTile tile = tester.widget<ContactTile>(addInstagram);
        expect(tile.valueIsPlaceholder, isTrue);
        expect(tile.value, l10nOf(tester).salonManageAddInstagramLink);
        expect(tile.label, l10nOf(tester).masterInstagramLabel);
        expect(tile.icon, Icons.alternate_email);
        expect(tile.semanticLabel, l10nOf(tester).salonManageAddInstagramLink);
      },
    );

    testWidgets(
      'phone on file but no Instagram, OWNER — phone row AND the add-link',
      (tester) async {
        await pumpAs(tester, _stubSalon.copyWith(phone: '+380671112233'));
        expect(phoneRow, findsOneWidget);
        expect(addInstagram, findsOneWidget);
        expect(instagramRow, findsNothing);
      },
    );

    testWidgets('an Instagram on file replaces the add-link with the tile', (
      tester,
    ) async {
      await pumpAs(tester, _stubSalon.copyWith(instagramUrl: '@velvet'));
      expect(instagramRow, findsOneWidget);
      expect(addInstagram, findsNothing);
    });

    testWidgets(
      'a populated Instagram tile renders the value in bodyStrong, NOT the '
      'placeholder link style — the two branches are visibly different on '
      'the real screen render',
      (tester) async {
        // This is the one assertion in this group that would catch
        // `valueIsPlaceholder` being silently dropped or hard-coded true/
        // false at the CALL SITE (the screen), reading the actually
        // rendered TextStyle rather than a constructor field.
        await pumpAs(tester, _stubSalon.copyWith(instagramUrl: '@velvet'));

        final Text valueText = tester.widget<Text>(
          find
              .descendant(of: instagramRow, matching: find.text('@velvet'))
              .last,
        );
        expect(valueText.style, VelvetText.bodyStrong());
        expect(valueText.style, isNot(VelvetText.link()));
      },
    );

    testWidgets(
      'empty description, OWNER — the «Додати опис» link replaces the dead '
      'muted placeholder',
      (tester) async {
        await pumpAs(tester, _stubSalon.copyWith(description: null));
        expect(addDescription, findsOneWidget);
        expect(
          find.text(l10nOf(tester).salonManageAddDescriptionLink),
          findsOneWidget,
        );
        expect(find.text(l10nOf(tester).salonAboutEmpty), findsNothing);
      },
    );

    testWidgets(
      'empty description, NON-owner — the muted placeholder stays, no link',
      (tester) async {
        await pumpAs(
          tester,
          _stubSalon.copyWith(description: null),
          owner: false,
        );
        expect(addDescription, findsNothing);
        expect(find.text(l10nOf(tester).salonAboutEmpty), findsOneWidget);
      },
    );

    testWidgets('a description on file renders it, never the link', (
      tester,
    ) async {
      await pumpAs(tester, _stubSalon);
      expect(addDescription, findsNothing);
      expect(find.byKey(const Key('salon-manage-about-text')), findsOneWidget);
    });

    testWidgets('«Додати опис» pushes the profile-edit screen', (tester) async {
      await pumpAs(tester, _stubSalon.copyWith(description: null));
      await tester.tap(addDescription);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-edit-marker')), findsOneWidget);
    });

    testWidgets('«Додати посилання» pushes the contacts-edit screen', (
      tester,
    ) async {
      await pumpAs(tester, _stubSalon);
      // The new «Портфоліо» placeholder rail (PortfolioRail, promoted from
      // the independent master's profile screen) pushes this link below the
      // fold at the default test surface — scroll it into view before
      // tapping (mirrors the `salon-manage-add-staff` ensureVisible
      // precedent above).
      await tester.ensureVisible(addInstagram);
      await tester.pumpAndSettle();
      await tester.tap(addInstagram);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contacts-edit-marker')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // «Про салон» tab — PortfolioRail (mobile-qa gap-closure, promotion
  // regression — the third PortfolioRail consumer had zero assertions).
  // ---------------------------------------------------------------------
  group('«Про салон» tab — portfolio rail (mobile-qa gap-closure)', () {
    final Finder portfolioRail = find.byKey(
      const Key('salon-manage-portfolio'),
    );
    final Finder aboutText = find.byKey(const Key('salon-manage-about-text'));

    testWidgets('PortfolioRail renders on the tab, positioned BETWEEN the '
        'description and the «Контакти» heading', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      expect(portfolioRail, findsOneWidget);
      // `railKey` is applied to PortfolioRail's inner Column, not to the
      // PortfolioRail widget node itself — so resolve the TYPE via the
      // shared widget's own type finder (there is exactly one on this
      // screen) rather than reading the type off the keyed Column.
      expect(
        find.byType(PortfolioRail),
        findsOneWidget,
        reason: 'proves the SHARED widget was wired in, not a copy',
      );

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonManagementProfileScreen)),
      );
      final Finder contactsHeading = find.text(l10n.masterContactsLabel);
      expect(aboutText, findsOneWidget);
      expect(contactsHeading, findsOneWidget);

      final double descriptionY = tester.getTopLeft(aboutText).dy;
      final double portfolioY = tester.getTopLeft(portfolioRail).dy;
      final double contactsY = tester.getTopLeft(contactsHeading).dy;

      expect(
        portfolioY,
        greaterThan(descriptionY),
        reason: 'the rail must sit BELOW the salon description',
      );
      expect(
        contactsY,
        greaterThan(portfolioY),
        reason:
            'the rail must sit ABOVE the «Контакти» heading — this is the '
            'exact position the design specifies '
            '(salon_management_profile_screen.dart:849)',
      );
    });

    testWidgets(
      'no RenderFlex overflow at 320dp width and 1.3x text scale — the '
      'rail is a horizontal scroller nested inside the tab\'s vertical '
      'scroller, the classic overflow shape',
      (tester) async {
        installOverflowGuard();
        final repo = FakeSalonRepository(salon: _stubSalon);

        tester.view.physicalSize = const Size(320, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides(repo).cast(),
            retry: beauticaProviderRetry,
            child: MaterialApp.router(
              routerConfig: _router(repo),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
              builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(portfolioRail, findsOneWidget);
        // installOverflowGuard's tearDown fails the test if any RenderFlex
        // overflow was recorded during the pump above; this is a belt-and-
        // braces check that nothing else threw either.
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── Phase 283 — roster audience-matrix pins (staff-side rows) ───────────
  //
  // Pins the STAFF-SIDE half of the D2 matrix: `GET /salons/{id}/staff`
  // (owner/admin-gated) applies no role filter of its own — the tab renders
  // exactly what `getSalonStaff` returned. The two "owner toggle OFF" cells
  // are gated on Phase 21.15 and are pinned at the notifier/repository layer
  // instead (`salon_management_profile_notifier_test.dart`), never here.
  group('roster audience matrix (Phase 283)', () {
    testWidgets('should_showAdminInStaffRoster_when_viewedByOwner', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        staff: const <SalonStaffMember>[_matrixAdminOnly],
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      final Finder adminCard = find.byKey(
        const Key('salon-manage-staff-card-matrix-admin-1'),
      );
      expect(adminCard, findsOneWidget);
      expect(
        tester.widget<SalonMasterCard>(adminCard).role,
        l10n.salonStaffRoleAdmin,
        reason:
            'an admin (no master row at all) must still render — the '
            'owner-gated staff endpoint is the ONE place admins are visible',
      );
    });

    testWidgets('should_showOwnerInBothRosters_when_ownerMasterRowIsActive', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        staff: const <SalonStaffMember>[_matrixOwner],
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-manage-staff-card-matrix-owner-1')),
        findsOneWidget,
        reason: 'D2: an owner with an ACTIVE master row is staff-side visible',
      );
    });

    testWidgets(
      'should_showDualRolePersonInBothRosters_when_adminAlsoHasAMasterRow',
      (tester) async {
        final repo = FakeSalonRepository(
          salon: _stubSalon,
          staff: const <SalonStaffMember>[_matrixDualRole],
        );
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const Key('salon-manage-staff-card-matrix-dual-1'),
        );
        expect(card, findsOneWidget);
        // D4 — the staff wire reports SALON_ADMIN for this person REGARDLESS
        // of their active master row, so the card must carry the ADMIN role
        // label here, not a master one. This is the cell a role-based "fix"
        // (filtering by role instead of master-row presence, see the
        // mutation check) would get right on the staff side but wrong on the
        // client side — see the public screen's counterpart test.
        expect(
          tester.widget<SalonMasterCard>(card).role,
          l10n.salonStaffRoleAdmin,
        );
      },
    );

    testWidgets('should_showMasterInBothRosters_when_masterIsActive', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        staff: const <SalonStaffMember>[_matrixMaster],
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-manage-staff-card-matrix-master-1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'should_notApplyAnyRoleFilterClientSide_when_rostersAreRendered',
      (tester) async {
        // D1 — pins the STAFF half: all four person-types the endpoint
        // returned render, unfiltered, none added or dropped. ("ClientSide"
        // in the case name refers to the mobile CLIENT app, not the
        // client/customer audience — the same case name is pinned again in
        // `public_salon_profile_screen_test.dart` for the customer-facing
        // half of the very same D1 no-filter guarantee.)
        final repo = FakeSalonRepository(
          salon: _stubSalon,
          staff: _matrixFullRoster,
        );
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        expect(find.byType(SalonMasterCard), findsNWidgets(4));
        for (final SalonStaffMember member in _matrixFullRoster) {
          expect(
            find.byKey(Key('salon-manage-staff-card-${member.userId}')),
            findsOneWidget,
            reason: '${member.userId} must render — no role filter exists',
          );
        }
      },
    );
  });
}
