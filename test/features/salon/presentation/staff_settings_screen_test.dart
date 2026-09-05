// Phase 21.6 — Widget tests for [StaffSettingsScreen] and
// [MoveAdminSalonScreen].
//
// Covers, in order:
//   1. The settings page's row inventory: the two navigational rows, the
//      hairline, and the terminal destructive row — plus the context
//      subheading naming WHICH administrator is being managed.
//   2. «Перевести в майстри» is rendered but NOT wired: `Semantics(enabled:
//      false)` and a tap that issues nothing. This is the headline assertion
//      of the "do not fake success" decision — a row that quietly did
//      nothing would look identical on screen and must not pass here.
//   3. Remove — happy path: the dialog appears, confirming issues DELETE with
//      THIS `(salonId, userId)`, the roster is refetched, and the flow lands
//      back on the salon profile.
//   4. Remove — backing out of the dialog issues NOTHING.
//   5. Remove — 403 (self-removal / no management access) surfaces the
//      DISTINCT forbidden copy, not the generic one, and stays on the page.
//      A 403 arrives as `UnknownFailure` with the `DioException` in `cause`
//      (ErrorMapperInterceptor maps only an explicit code list — see
//      `InviteStaffScreen._errorMessage`'s doc), so the fixture injects that
//      exact shape rather than a `ServerFailure(statusCode: 403)` the real
//      stack never produces.
//   6. Remove — a non-403 failure surfaces the GENERIC copy.
//   7. The move row pushes the picker route for THIS `(salonId, memberId)`.
//   8. Picker — one card per sibling salon, each carrying its own salon's
//      name (a mis-keyed list rendering three copies of one salon would
//      still "show three cards").
//   9. Picker — confirming a destination PATCHes with THAT card's salon id,
//      not the first one in the list.
//  10. Picker — 403 (cross-owner destination) surfaces the distinct copy.
//  11. Picker — empty sibling list renders the empty state, no cards.
//  12. Picker — a failed read renders the shared [ErrorState]; retry
//      re-fetches.
//  13. The `SettingsRow(enabled: false)` addition leaves an ENABLED row
//      untouched — the additive-parameter proof, asserted on this screen's
//      own «Перемістити до іншого салону» row.
//  14. TAB-INDEX PINS (audit follow-up) — `kSalonStaffSubTab` and
//      `kSalonTeamNavTab` asserted against the lists that OWN their
//      positions, so a re-order of either list goes red here instead of
//      silently landing the viewer on the wrong tab after a write. This is
//      the pin `staff_settings_screen.dart`'s doc comment used to claim
//      existed; it did not.
//  15. ROLE GUARD (audit follow-up) — the page renders a notice, not the
//      admin-only DELETE/PATCH rows, when the route is reached for a MASTER
//      entry; plus the admin control and the unknown-role degradation case.
//
// Finders use widget Keys and l10n-resolved strings — never Cyrillic
// literals (`forbid_cyrillic_finder.sh`). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_api/beautica_api.dart'
    show SiblingSalonOption, SiblingSalonOptionBuilder;
import 'package:beautica_mobile/features/salon/presentation/staff_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/move_admin_salon_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart'
    show kSalonManageTabKeys, kSalonStaffSubTab, salonManageTabLabels;
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_hub_card.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/fakes/fake_service_repository.dart';
import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';
const String _kAdminId = 'user-admin-1';
const Salon _kSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

/// This screen's own route — the location every "we did not navigate"
/// assertion compares against.
final String _kSettingsPath = RouteNames.salonManageStaffSettings(
  _kSalonId,
  _kAdminId,
);

const SalonStaffMember _kAdmin = SalonStaffMember(
  userId: _kAdminId,
  role: SalonStaffRole.admin,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

// ─── Phase 307 — remove master fixtures ─────────────────────────────────────

/// The roster's `userId` — also the route's `memberId`.
const String _kMasterUserId = 'user-master-1';

/// The `Master`-row id — DELIBERATELY DIFFERENT from [_kMasterUserId]. D2's
/// whole point is that `removeMaster` must be called with THIS id, never the
/// route's `memberId`; identical fixtures would let a swapped-id bug pass.
const String _kMasterRowId = 'master-row-1';

const SalonStaffMember _kMaster = SalonStaffMember(
  userId: _kMasterUserId,
  masterId: _kMasterRowId,
  role: SalonStaffRole.master,
  firstName: 'Марина',
  lastName: 'Литвин',
);

/// This screen's own route for the MASTER fixture — the location every
/// "we did not navigate" assertion in the remove-master group compares
/// against.
final String _kMasterSettingsPath = RouteNames.salonManageStaffSettings(
  _kSalonId,
  _kMasterUserId,
);

const User _kOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

/// A SALON_ADMIN viewer — reaches the route (e.g. a stale deep link) but is
/// not the salon owner, so backend Phase 297's owner-only gate would 403
/// them. D3's control case.
const User _kAdminViewer = User(
  id: 'admin-viewer-1',
  email: 'admin-viewer@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Бойко',
);

/// The owner, but ALSO the master roster entry under test («де я працюю»
/// self-enrolment) — D4's case. Same id as [_kMasterUserId].
const User _kOwnerAsMaster = User(
  id: _kMasterUserId,
  email: 'owner-master@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Марина',
  lastName: 'Литвин',
);

/// The owner, but ALSO the co-admin roster entry under test — Phase 308's
/// admin-branch mirror of [_kOwnerAsMaster]. Same id as [_kAdminId], so
/// `canManageStaff`'s `member?.userId != currentUserId` term is exercised
/// for real rather than vacuously (self-removal is a 403 on the backend and
/// always was; D3 carries the `!= currentUserId` term specifically so the
/// row an admin is most likely to mis-tap — their own — never renders).
const User _kOwnerAsAdmin = User(
  id: _kAdminId,
  email: 'owner-admin@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'tok');
}

/// Overrides for a [_pump] call that needs a specific signed-in [user] —
/// promoted (Phase 308) out of [_masterViewerOverrides] so an ADMIN-branch
/// test that only needs to control `isSalonOwnerProvider`/`currentUserProvider`
/// (D3's `canManageStaff` gate) does not also drag in a master-only service
/// stub that means nothing for an admin roster entry.
List<Object> _authOverrides(User user) => <Object>[
  authProvider.overrideWith(() => _StubAuthNotifier(user)),
];

/// Overrides for a [_pump] call that needs a specific signed-in [user] AND a
/// resolvable MASTER roster entry (the services fetch [FakeServiceRepository]
/// stub every master-role test in this file already needs).
List<Object> _masterViewerOverrides(User user) => <Object>[
  ..._authOverrides(user),
  publicServiceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
];

List<SiblingSalonOption> _siblings() => <SiblingSalonOption>[
  SiblingSalonOption(
    (SiblingSalonOptionBuilder b) => b
      ..id = 'salon-2'
      ..name = 'Студія «Камелія»'
      ..street = 'Хрещатик'
      ..buildingNo = '12',
  ),
  SiblingSalonOption(
    (SiblingSalonOptionBuilder b) => b
      ..id = 'salon-3'
      ..name = 'Барбершоп «Дуб»'
      ..street = 'Січових Стрільців'
      ..buildingNo = '4',
  ),
];

/// A bare 403 as the REAL stack delivers it.
///
/// `ErrorMapperInterceptor` maps only an explicit list of status codes to
/// [ServerFailure] (401/404/409/5xx, plus 400/429 on two unrelated paths) —
/// 403 is NOT on it, so it reaches the screen as [UnknownFailure] carrying
/// the [DioException]. Injecting `ServerFailure(statusCode: 403)` instead
/// would test a shape production never produces and would pass even if the
/// screen only ever read `ServerFailure.statusCode`.
Failure _forbidden() => UnknownFailure(
  cause: DioException(
    requestOptions: RequestOptions(path: '/api/v1/salons'),
    response: Response<void>(
      requestOptions: RequestOptions(path: '/api/v1/salons'),
      statusCode: 403,
    ),
    type: DioExceptionType.badResponse,
  ),
);

GoRouter _router({String initial = ''}) => GoRouter(
  initialLocation: initial.isEmpty
      ? RouteNames.salonManageStaffSettings(_kSalonId, _kAdminId)
      : initial,
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-manage-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/staff/:memberId',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-staff-${state.pathParameters['memberId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/staff/:memberId/settings',
      builder: (context, state) => StaffSettingsScreen(
        salonId: state.pathParameters['salonId']!,
        memberId: state.pathParameters['memberId']!,
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/staff/:memberId/move',
      builder: (context, state) => MoveAdminSalonScreen(
        salonId: state.pathParameters['salonId']!,
        memberId: state.pathParameters['memberId']!,
      ),
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSalonRepository repo, {
  String initial = '',
  // ADDITIVE (Phase 21.6 audit follow-up): a MASTER roster entry makes
  // `salonStaffMemberProfileProvider` reach for that master's services, which
  // an admin-only fixture never triggers. Empty for every pre-existing
  // caller, so none of them change.
  List<Object> extraOverrides = const <Object>[],
}) async {
  final GoRouter router = _router(initial: initial);
  addTearDown(router.dispose);
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      salonRepositoryProvider.overrideWithValue(repo),
      ...extraOverrides,
    ],
    // Pinned: several tests assert an EXACT call count, and the production
    // retry policy would re-issue a NetworkFailure/5xx non-deterministically
    // mid-`pumpAndSettle`.
    retry: (_, _) => null,
  );
  await tester.pumpAndSettle();
  return router;
}

FakeSalonRepository _repo({
  List<SiblingSalonOption>? siblings,
  Failure? removeError,
  Failure? rotateError,
  Failure? siblingsError,
  // ADDITIVE (Phase 21.6 audit follow-up): the role-guard group needs a
  // roster whose `_kAdminId` entry is a MASTER. Defaults to the single-admin
  // roster every pre-existing caller already got, so none of them change.
  List<SalonStaffMember>? staff,
  // ADDITIVE (Phase 307): mirrors [removeError] for the master endpoint.
  Failure? removeMasterError,
}) {
  final repo = FakeSalonRepository(
    salon: _kSalon,
    staff: staff ?? const <SalonStaffMember>[_kAdmin],
    siblingSalons: siblings,
  );
  repo.removeAdminError = removeError;
  repo.rotateAdminError = rotateError;
  repo.siblingSalonsError = siblingsError;
  repo.removeMasterError = removeMasterError;
  return repo;
}

/// The location of the route the router LAST matched.
///
/// Deliberately NOT `currentConfiguration.uri`/`.fullPath`: go_router excludes
/// the `ImperativeRouteMatch` a `context.push` produces from both, so a raw
/// read after a push keeps reporting the PRE-push location forever
/// (`forbid_naive_router_location.sh`). `AppHarness.location` is the
/// integration-test helper for the same trap; this is its one-line widget-test
/// equivalent, kept local because importing that harness would drag in the
/// whole `FakeBackend` boot path a widget test has no use for.
String _lastMatchedLocation(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

AppLocalizations _settingsL10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(StaffSettingsScreen)));

AppLocalizations _moveL10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MoveAdminSalonScreen)));

/// The rendered `Semantics.enabled` flag of the [SettingsRow] under [key].
///
/// Read off the widget tree's own semantics node — NOT off the widget's
/// `enabled` field, which would be a vacuous assertion that reads back the
/// value the test just passed in. Same `flagsCollection.isEnabled
/// .toBoolOrNull()` shape `locality_tap_row_test.dart` already uses.
bool? _rowSemanticsEnabled(WidgetTester tester, Key key) {
  final data = tester
      .getSemantics(
        find
            .descendant(
              of: find.byKey(key),
              matching: find.byType(Semantics),
              matchRoot: true,
            )
            .first,
      )
      .getSemanticsData();
  return data.flagsCollection.isEnabled.toBoolOrNull();
}

/// The rendered press-scale of the [SettingsRow] under [key].
///
/// Read off the [AnimatedScale] the row's own `_pressed` STATE drives — not
/// off any parameter this test passed in. With a pointer held down, an
/// interactive row reports the pressed scale and an `AbsorbPointer`-shielded
/// one reports rest, so this observes whether the gesture reached the widget
/// at all rather than merely restating its configuration.
double _rowPressScale(WidgetTester tester, Key key) => tester
    .widget<AnimatedScale>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(AnimatedScale))
          .first,
    )
    .scale;

/// Pumps the picker WITHOUT settling.
///
/// `pumpAndSettle` cannot be used while `siblingSalonsGate` is open: the
/// loading branch renders [SkeletonShimmerScope], whose controller
/// `..repeat(reverse: true)` keeps `hasScheduledFrame` permanently true, so
/// the settle would time out on the shimmer rather than on the fetch. Same
/// trap `salon_pending_invites_flow_test.dart` records for the E2E tier.
Future<GoRouter> _pumpUnsettled(
  WidgetTester tester,
  FakeSalonRepository repo, {
  required String initial,
}) async {
  final GoRouter router = _router(initial: initial);
  addTearDown(router.dispose);
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
    retry: (_, _) => null,
  );
  // Pump-until-condition, never a fixed frame count: the shimmer appears as
  // soon as the (gated) fetch is dispatched, and that is the state the
  // caller is waiting for.
  await tester.pumpUntilFound(find.byType(SkeletonShimmerScope));
  return router;
}

void main() {
  group('admin settings — layout', () {
    testWidgets('renders both nav rows, the hairline and the destructive row', (
      tester,
    ) async {
      // Phase 308 (D3) — the terminal row is now owner-gated, so this
      // "everything renders" baseline needs an OWNER viewer to still see
      // it; see the dedicated 'remove administrator — gating (D3/D4)' group
      // below for the non-owner/self-row denial cases this gate exists for.
      await _pump(tester, _repo(), extraOverrides: _authOverrides(_kOwner));

      expect(find.byKey(const Key('row-admin-move-salon')), findsOneWidget);
      expect(
        find.byKey(const Key('row-admin-convert-to-master')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-settings-divider')), findsOneWidget);
      expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
      // No self-service rows: this manages ANOTHER person, so «Вийти»
      // (which would log the VIEWER out) must never be here.
      expect(find.byKey(const Key('row-logout')), findsNothing);
    });

    testWidgets('context subheading names the administrator being managed', (
      tester,
    ) async {
      await _pump(tester, _repo());

      expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('admin-settings-context-name')))
            .data,
        'Олена Ковальчук',
      );
    });
  });

  group('«Перевести в майстри» is disabled, not faked', () {
    testWidgets('renders with the "coming soon" value and reads as disabled', (
      tester,
    ) async {
      await _pump(tester, _repo());
      final AppLocalizations l10n = _settingsL10n(tester);

      const Key rowKey = Key('row-admin-convert-to-master');
      expect(find.byKey(rowKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(rowKey),
          matching: find.text(l10n.adminSettingsConvertToMasterSoon),
        ),
        findsOneWidget,
      );
      expect(_rowSemanticsEnabled(tester, rowKey), isFalse);
    });

    testWidgets('tapping it navigates nowhere and calls nothing', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo();
      final GoRouter router = await _pump(tester, repo);

      await tester.tap(
        find.byKey(const Key('row-admin-convert-to-master')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Still on the settings page, and nothing was pushed on top of it:
      // asserted on the RENDERED tree and the match stack rather than
      // `currentConfiguration.uri`, which go_router never updates for an
      // imperative push (`forbid_naive_router_location.sh`).
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
      expect(_lastMatchedLocation(router), _kSettingsPath);
      expect(repo.removeAdminRequests, isEmpty);
      expect(repo.rotateAdminRequests, isEmpty);
    });

    testWidgets('an ENABLED sibling row is unaffected by the new parameter', (
      tester,
    ) async {
      await _pump(tester, _repo());
      // The additive-default proof: the move row passes no `enabled` at all
      // and still reads as enabled.
      expect(
        _rowSemanticsEnabled(tester, const Key('row-admin-move-salon')),
        isTrue,
      );
    });
  });

  group('remove administrator', () {
    testWidgets('confirming DELETEs this (salonId, userId) and leaves', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo();
      final GoRouter router = await _pump(
        tester,
        repo,
        extraOverrides: _authOverrides(_kOwner),
      );

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove-admin-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(repo.removeAdminRequests, <({String salonId, String userId})>[
        (salonId: _kSalonId, userId: _kAdminId),
      ]);
      // Unwound past BOTH the settings page and the (now stale) staff
      // profile, onto the salon management profile — asserted on the
      // RENDERED destination, which is what the viewer actually sees.
      expect(find.byKey(const Key('stub-manage-$_kSalonId')), findsOneWidget);
      expect(find.byType(StaffSettingsScreen), findsNothing);
      expect(_lastMatchedLocation(router), RouteNames.salonManage(_kSalonId));
    });

    // Phase 308 (D2/test case 17) — the success snack's exact literal, HARD-
    // CODED here rather than compared against `l10n.adminSettingsRemoveSuccess`
    // itself: pinning a getter against itself passes for every possible
    // value (the Phase 291 CRITICAL finding this file's own header note
    // warns about), and would stay green if the verb regressed to
    // «вилучено».
    testWidgets('a successful remove shows the exact success snack literal', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo();
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));
      final AppLocalizations l10n = _settingsL10n(tester);
      // i18n-finder-ok: this is the copy PIN itself (test case 17) — the
      // hard-coded literal is the assertion, not a locale-coupled finder.
      // Pinning against `l10n.adminSettingsRemoveSuccess` would compare the
      // getter to itself and pass for any value, including the pre-308
      // «вилучено» regression this test exists to catch.
      expect(
        l10n.adminSettingsRemoveSuccess,
        'Адміністратора видалено із салону.',
      );

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pump();

      expect(find.text(l10n.adminSettingsRemoveSuccess), findsOneWidget);
    });

    testWidgets('backing out of the dialog issues nothing', (tester) async {
      final FakeSalonRepository repo = _repo();
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remove-admin-dialog')), findsNothing);
      expect(repo.removeAdminRequests, isEmpty);
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
    });

    testWidgets('403 shows the forbidden copy and stays on the page', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(removeError: _forbidden());
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));
      final AppLocalizations l10n = _settingsL10n(tester);

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorForbidden), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsNothing);
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
    });

    testWidgets('a non-403/409/404 failure shows the generic copy', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        removeError: const ServerFailure(statusCode: 500),
      );
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));
      final AppLocalizations l10n = _settingsL10n(tester);

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorForbidden), findsNothing);
    });

    // Phase 308 (D6/test case 15) — the 409 backend Phase 299 introduced
    // gets its OWN copy, not the generic fallback.
    testWidgets('409 shows the conflict copy, not the generic one', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        removeError: const ServerFailure(statusCode: 409),
      );
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));
      final AppLocalizations l10n = _settingsL10n(tester);
      // i18n-finder-ok: copy pin (test case 15) — see the success-snack
      // test above for why the literal, not the getter, is the assertion.
      expect(
        l10n.adminSettingsRemoveErrorConflict,
        "Цього адміністратора зараз не можна видалити — з ним пов'язані "
        'записи, де він виступає клієнтом.',
      );

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorConflict), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsNothing);
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
    });

    // Phase 308 (D6/test case 16) — 404 (already gone / second DELETE) gets
    // its own copy too.
    testWidgets('404 shows the not-found copy, not the generic one', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        removeError: const ServerFailure(statusCode: 404),
      );
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));
      final AppLocalizations l10n = _settingsL10n(tester);
      // i18n-finder-ok: copy pin (test case 16) — see the success-snack
      // test above for why the literal, not the getter, is the assertion.
      expect(
        l10n.adminSettingsRemoveErrorNotFound,
        'Адміністратора не знайдено — можливо, його вже видалили.',
      );

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorNotFound), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsNothing);
    });
  });

  // -------------------------------------------------------------------
  // Phase 308 (D3/D4) — the LIVE 403-on-tap bug: the admin remove row was
  // never owner-gated. `canManageStaff` fixes that; these are its pins.
  // -------------------------------------------------------------------
  group('remove administrator — gating (D3/D4)', () {
    testWidgets(
      'an OWNER viewing a co-admin sees the remove row (test case 10)',
      (tester) async {
        await _pump(tester, _repo(), extraOverrides: _authOverrides(_kOwner));

        expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
      },
    );

    testWidgets(
      'a NON-OWNER admin viewing a co-admin does NOT see the remove row, '
      'but the rest of the branch renders (test case 11 — the 403-on-tap '
      'regression pin)',
      (tester) async {
        await _pump(
          tester,
          _repo(),
          extraOverrides: _authOverrides(_kAdminViewer),
        );

        // Absence, not a field read (`SettingsRow.enabled`/`destructive`
        // would be vacuous here) — the row must not exist in the tree at
        // all, which is also what makes it untappable.
        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
        // M8 — the row is omitted, NOT the whole admin branch: the
        // navigational rows above it must still be there.
        expect(find.byKey(const Key('row-admin-move-salon')), findsOneWidget);
        expect(
          find.byKey(const Key('row-admin-convert-to-master')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      "an OWNER viewing THEIR OWN admin row does NOT see the remove row "
      '(test case 12)',
      (tester) async {
        await _pump(
          tester,
          _repo(),
          extraOverrides: _authOverrides(_kOwnerAsAdmin),
        );

        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
      },
    );

    testWidgets('the hairline is absent together with the row for a non-owner '
        '(test case 13)', (tester) async {
      await _pump(
        tester,
        _repo(),
        extraOverrides: _authOverrides(_kAdminViewer),
      );

      expect(find.byKey(const Key('admin-settings-divider')), findsNothing);
    });

    testWidgets(
      'the hairline is absent together with the row for the owner\'s own '
      'row (test case 13)',
      (tester) async {
        await _pump(
          tester,
          _repo(),
          extraOverrides: _authOverrides(_kOwnerAsAdmin),
        );

        expect(find.byKey(const Key('admin-settings-divider')), findsNothing);
      },
    );
  });

  group('move to another salon', () {
    testWidgets('the row pushes the picker for this (salonId, memberId)', (
      tester,
    ) async {
      final GoRouter router = await _pump(tester, _repo(siblings: _siblings()));

      await tester.tap(find.byKey(const Key('row-admin-move-salon')));
      await tester.pumpAndSettle();

      expect(
        _lastMatchedLocation(router),
        RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );
      // And the screen really mounted with THESE ids — a route that matched
      // but built with the wrong path params would still "navigate".
      expect(find.byType(MoveAdminSalonScreen), findsOneWidget);
      final MoveAdminSalonScreen screen = tester.widget<MoveAdminSalonScreen>(
        find.byType(MoveAdminSalonScreen),
      );
      expect(screen.salonId, _kSalonId);
      expect(screen.memberId, _kAdminId);
    });

    testWidgets('renders one card per sibling, each with its own name', (
      tester,
    ) async {
      await _pump(
        tester,
        _repo(siblings: _siblings()),
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      expect(find.byType(SalonHubCard), findsNWidgets(2));
      // Per-card identity: two copies of one salon would still be "two
      // cards", so assert each name is present exactly once.
      // i18n-finder-ok: a salon NAME is user-entered data echoed back by the
      // backend, not UI copy — byte-identical in every locale. Both values
      // are this test's own fixtures (see `_siblings`).
      expect(find.text('Студія «Камелія»'), findsOneWidget);
      // i18n-finder-ok: same — a fixture salon name, not translatable copy.
      expect(find.text('Барбершоп «Дуб»'), findsOneWidget);
    });

    testWidgets('confirming PATCHes with THAT card\'s destination id', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(siblings: _siblings());
      final GoRouter router = await _pump(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      // The SECOND card — picking the first would pass even if the screen
      // always submitted `targets.first`.
      await tester.tap(
        find.byKey(const ValueKey<String>('move-admin-target-salon-3')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('move-admin-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('move-admin-confirm')));
      await tester.pumpAndSettle();

      expect(
        repo.rotateAdminRequests,
        <({String salonId, String userId, String destinationSalonId})>[
          (
            salonId: _kSalonId,
            userId: _kAdminId,
            destinationSalonId: 'salon-3',
          ),
        ],
      );
      expect(find.byKey(const Key('stub-manage-$_kSalonId')), findsOneWidget);
      expect(find.byType(MoveAdminSalonScreen), findsNothing);
      expect(_lastMatchedLocation(router), RouteNames.salonManage(_kSalonId));
    });

    testWidgets('a cross-owner 403 shows the forbidden copy', (tester) async {
      final FakeSalonRepository repo = _repo(
        siblings: _siblings(),
        rotateError: _forbidden(),
      );
      await _pump(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );
      final AppLocalizations l10n = _moveL10n(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('move-admin-target-salon-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.moveAdminSalonErrorForbidden), findsOneWidget);
      expect(find.text(l10n.moveAdminSalonErrorGeneric), findsNothing);
      expect(find.byType(MoveAdminSalonScreen), findsOneWidget);
    });

    testWidgets('no siblings → the empty state, no cards', (tester) async {
      await _pump(
        tester,
        _repo(),
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      expect(find.byKey(const Key('move-admin-empty')), findsOneWidget);
      expect(find.byType(SalonHubCard), findsNothing);
    });

    testWidgets('a failed read renders ErrorState; retry re-fetches', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        siblings: _siblings(),
        siblingsError: const ServerFailure(statusCode: 500),
      );
      await _pump(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      expect(find.byType(ErrorState), findsOneWidget);
      expect(repo.siblingSalonsCalls, 1);

      repo.siblingSalonsError = null;
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(repo.siblingSalonsCalls, 2);
      expect(find.byType(SalonHubCard), findsNWidgets(2));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 21.6 mobile-qa gap-closure.
  //
  // M14 — «tapping it navigates nowhere and calls nothing» above is VACUOUS
  // with respect to `enabled: false`: the row's `onTap` is `() {}`, so that
  // test passes identically whether the tap is ABSORBED or merely handled by
  // a no-op. Measured — mutating `staff_settings_screen.dart:337`
  // `enabled: false` -> `enabled: true` left it GREEN while the sibling
  // semantics assertion went red. The absorption it claims to prove is
  // pinned here instead, against the ONE production line that implements it.
  // ─────────────────────────────────────────────────────────────────────────
  group('the disabled row absorbs pointers, it does not merely no-op', () {
    testWidgets('a held pointer never reaches the disabled row', (
      tester,
    ) async {
      await _pump(tester, _repo());

      const Key disabled = Key('row-admin-convert-to-master');
      const Key enabled = Key('row-admin-move-salon');

      // Both gestures are CANCELLED rather than lifted: an `up()` on the
      // enabled control would fire its `onTap`, push the picker, and unmount
      // the very screen the second half of this test measures.
      final TestGesture onDisabled = await tester.startGesture(
        tester.getCenter(find.byKey(disabled)),
      );
      await tester.pump();
      expect(
        _rowPressScale(tester, disabled),
        1.0,
        reason:
            'AbsorbPointer(absorbing: true) must swallow the pointer before '
            'the row\'s GestureDetector sees onTapDown',
      );
      await onDisabled.cancel();
      await tester.pumpAndSettle();

      // CONTROL — an identical gesture on the ENABLED sibling MUST register,
      // otherwise "the disabled row did not react" would be satisfied by a
      // gesture that reached nothing at all (M14).
      final TestGesture onEnabled = await tester.startGesture(
        tester.getCenter(find.byKey(enabled)),
      );
      await tester.pump();
      expect(
        _rowPressScale(tester, enabled),
        lessThan(1.0),
        reason:
            'the control row must visibly depress — if it does not, the '
            'assertion above proves nothing about absorption',
      );
      await onEnabled.cancel();
      await tester.pumpAndSettle();
    });
  });

  group('remove administrator — in-flight and roster refresh', () {
    // mobile-perf LOW fix (2026-09-05) — admin-path sibling of the master
    // path's same test below; see that test's doc for why this calls the
    // row's OWN `onTap` twice directly rather than driving two
    // `tester.tap()` gestures.
    testWidgets(
      'a double-tap before the confirm dialog mounts opens only one dialog, '
      'and confirming issues only one removeAdmin call',
      (tester) async {
        final FakeSalonRepository repo = _repo();
        await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));

        final SettingsRow row = tester.widget<SettingsRow>(
          find.byKey(const Key('row-admin-remove')),
        );
        // Two SYNCHRONOUS invocations of the exact callback a real tap
        // fires — the row's own `onTap`. This is the fast-double-tap race
        // itself: the first call suspends at `await
        // showRemoveAdminDialog(...)` and returns control (its Future is
        // never awaited by the gesture layer either — `onTap` is a fired-
        // and-forgotten `VoidCallback`), so the second call runs while the
        // first is still mid-dialog. Measured — two `tester.tap()` gestures
        // fired back-to-back with NO `pump()` between them does NOT
        // reproduce this: by the time the first call's `Future` resolves,
        // `Navigator.push`'s synchronous portion (inside `showDialog`) has
        // already run and the new route already occupies that hit-test
        // position, so the second gesture silently misses the row instead
        // of re-entering `onTap` — which would make this test pass
        // regardless of whether the guard exists, defeating the whole
        // point. Calling `onTap` directly sidesteps hit-testing entirely
        // and exercises the guard at the exact seam it protects.
        row.onTap();
        row.onTap();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('remove-admin-dialog')),
          findsOneWidget,
          reason: 'the second call must not raise a second confirm dialog',
        );

        await tester.tap(find.byKey(const Key('remove-admin-confirm')));
        await tester.pumpAndSettle();

        expect(repo.removeAdminRequests, <({String salonId, String userId})>[
          (salonId: _kSalonId, userId: _kAdminId),
        ]);
      },
    );

    testWidgets(
      'while the DELETE is in flight the row spins and a second tap issues '
      'nothing',
      (tester) async {
        final FakeSalonRepository repo = _repo();
        repo.removeAdminGate = Completer<void>();
        await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));

        await tester.tap(find.byKey(const Key('row-admin-remove')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('remove-admin-confirm')));
        // NOT pumpAndSettle: the request is parked on the gate and the row
        // now renders a perpetual CircularProgressIndicator, so nothing ever
        // quiesces. Pump UNTIL the spinner exists — the dialog's own exit
        // transition has to elapse first and guessing its length is exactly
        // what `scripts/forbid_fixed_wait.sh` exists to stop.
        await tester.pumpUntilFound(
          find.byKey(const ValueKey<String>('settings_row_loading')),
        );

        expect(
          find.byKey(const ValueKey<String>('settings_row_loading')),
          findsOneWidget,
          reason:
              'a slow network must show the spinner, not swallow the tap '
              'silently',
        );
        expect(repo.removeAdminRequests, hasLength(1));

        // The second tap: absorbed by `SettingsRow(loading: true)` AND by the
        // `_removing` guard. Either alone would be enough; both are the
        // double-tap contract.
        await tester.tap(
          find.byKey(const Key('row-admin-remove')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(
          repo.removeAdminRequests,
          hasLength(1),
          reason: 'a second tap must not issue a second DELETE',
        );

        repo.removeAdminGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a successful remove REFETCHES the staff roster', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo();
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));

      final int before = repo.getSalonStaffCalls;
      expect(
        before,
        greaterThan(0),
        reason: 'the screen reads the roster for the administrator name',
      );

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      // `_returnToStaffTab` invalidates `salonManagementProfileProvider`
      // BEFORE popping, while this element is still mounted. Without that
      // call the viewer lands on «Персонал» still listing the administrator
      // they just watched disappear — and every other assertion in this file
      // (the pop, the DELETE tuple) is satisfied either way.
      expect(
        repo.getSalonStaffCalls,
        greaterThan(before),
        reason:
            'the roster must be re-read after the removal — the destination '
            'screen renders that list',
      );
    });
  });

  group('move to another salon — in-flight, skeleton and roster refresh', () {
    testWidgets('the picker renders skeleton cards while the list loads', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(siblings: _siblings());
      repo.siblingSalonsGate = Completer<void>();

      await _pumpUnsettled(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      expect(find.byType(SkeletonShimmerScope), findsOneWidget);
      expect(find.byType(SalonHubCard), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('move-admin-empty')), findsNothing);

      repo.siblingSalonsGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonShimmerScope), findsNothing);
      expect(find.byType(SalonHubCard), findsNWidgets(2));
    });

    testWidgets('a second destination cannot be submitted mid-rotate', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(siblings: _siblings());
      repo.rotateAdminGate = Completer<void>();
      await _pump(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('move-admin-target-salon-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move-admin-confirm')));
      // Pump UNTIL the dialog is gone — that is when the gated PATCH has been
      // dispatched and `_moving` is set. No fixed wait: the dialog's exit
      // transition is the thing being waited on, not a guessed duration.
      await tester.pumpUntilGone(find.byKey(const Key('move-admin-dialog')));

      expect(repo.rotateAdminRequests, hasLength(1));

      // The second card is still on screen and still tappable — the guard is
      // `_moving`, not a disabled widget, so this genuinely exercises it.
      await tester.tap(
        find.byKey(const ValueKey<String>('move-admin-target-salon-3')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('move-admin-dialog')),
        findsNothing,
        reason:
            'the `_moving` guard returns before the confirmation is even '
            'raised',
      );
      expect(
        repo.rotateAdminRequests,
        hasLength(1),
        reason: 'a rotate in flight must not be joined by a second one',
      );

      repo.rotateAdminGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a successful rotate REFETCHES the source salon roster', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(siblings: _siblings());
      await _pump(
        tester,
        repo,
        initial: RouteNames.salonManageAdminMove(_kSalonId, _kAdminId),
      );

      final int before = repo.getSalonStaffCalls;
      expect(before, greaterThan(0));

      await tester.tap(
        find.byKey(const ValueKey<String>('move-admin-target-salon-3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move-admin-confirm')));
      await tester.pumpAndSettle();

      expect(
        repo.getSalonStaffCalls,
        greaterThan(before),
        reason:
            'the administrator now belongs to the DESTINATION salon, so the '
            'source roster must be re-read before the viewer lands on it',
      );
    });
  });

  group('leaving the settings page without acting', () {
    testWidgets('the close control returns to the staff profile', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo();
      final GoRouter router = await _pump(
        tester,
        repo,
        // Pushed FROM the staff profile, which is the only real entry path —
        // starting on the settings route directly would exercise the
        // `context.go` fallback instead of the pop.
        initial: RouteNames.salonManageStaffMember(_kSalonId, _kAdminId),
      );
      expect(find.byKey(const Key('stub-staff-$_kAdminId')), findsOneWidget);

      // `push`, not `go`: this test's whole subject is the POP path, and only
      // an imperative push leaves the staff profile on the stack beneath.
      // The returned Future completes when the pushed route pops with its
      // result, which is exactly what the taps below cause — awaiting it here
      // would deadlock the test body.
      unawaited(
        router.push<void>(
          RouteNames.salonManageStaffSettings(_kSalonId, _kAdminId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StaffSettingsScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-close-admin-settings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-staff-$_kAdminId')), findsOneWidget);
      expect(find.byType(StaffSettingsScreen), findsNothing);
      expect(
        repo.removeAdminRequests,
        isEmpty,
        reason: 'closing must never be mistaken for confirming',
      );
      expect(repo.rotateAdminRequests, isEmpty);
    });
  });

  // -------------------------------------------------------------------
  // 14. TAB-INDEX PINS — `kSalonStaffSubTab` / `kSalonTeamNavTab`
  // -------------------------------------------------------------------
  //
  // Both constants are consumed as bare positions inside lists declared in
  // OTHER files: `kSalonManageTabKeys` / `salonManageTabLabels`
  // (`salon_management_profile_screen.dart`) and
  // `SalonBottomNav.ownerAdminItems` (`shared/widgets/salon_bottom_nav.dart`).
  // Nothing about a `const int = 1` fails when someone re-orders one of those
  // lists — the viewer just silently lands on the wrong tab after a removal
  // or a move.
  //
  // These are UNIT pins on purpose. `salon_admin_settings_flow_test.dart`
  // measured the E2E version VACUOUS: that journey reaches the settings page
  // THROUGH the «Персонал» tab, so the tab is already selected when the
  // reconciliation runs and mutating the constant left the flow fully green.
  // Asserting against the owning lists directly is the only shape that can
  // actually go red.
  group('salon tab-index constants are pinned to their owning lists', () {
    final AppLocalizations l10n = AppLocalizationsUk();

    test(
      'kSalonStaffSubTab indexes the STAFF tab of the management profile',
      () {
        expect(
          kSalonManageTabKeys[kSalonStaffSubTab],
          'staff',
          reason:
              'kSalonStaffSubTab is the position StaffSettingsScreen and '
              'MoveAdminSalonScreen select after a write, and the position '
              "SalonShellScreen's «Команда» destination maps to. Re-ordering "
              'kSalonManageTabKeys without moving this constant lands the '
              'viewer on a different tab entirely.',
        );
        expect(
          salonManageTabLabels(l10n)[kSalonStaffSubTab],
          l10n.salonManageTabStaff,
          reason:
              'the VISIBLE label order is a second list that must agree — the '
              'key list and the label list are declared separately and could '
              'drift apart on their own.',
        );
      },
    );

    test('kSalonTeamNavTab indexes the «Команда» bottom-nav destination', () {
      final List<SalonNavItem> items = SalonBottomNav.ownerAdminItems(l10n);
      expect(
        items[kSalonTeamNavTab].label,
        l10n.salonShellTabTeam,
        reason:
            'kSalonTeamNavTab is the bottom-nav highlight both Phase 21.6 '
            'screens set after a successful write. Re-ordering '
            'ownerAdminItems without moving it highlights «Записи» while the '
            'staff tab is what renders.',
      );
    });
  });

  // -------------------------------------------------------------------
  // 15. ROLE GUARD — the settings page refuses a NON-admin member
  // -------------------------------------------------------------------
  //
  // Every row on this page acts on `/salons/{salonId}/admins/{userId}`,
  // which only exists for an ADMIN entry. `SalonStaffProfileScreen` only
  // offers the entry point for an admin, but the ROUTE is reachable without
  // it (back stack, in-app `go`, cold deep link). The server refuses a
  // master's userId — that is and stays the gate — so this is a
  // UI-correctness fix: a destructive row that cannot work must not render.
  group('role guard', () {
    testWidgets(
      'a MASTER member, viewed by the OWNER, renders the remove row, not '
      'the admin rows',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );

        expect(find.byKey(const Key('row-master-remove')), findsOneWidget);

        // The admin-only rows, the hairline, the admin context subheading
        // and the owner-only notice are all gone — not merely disabled.
        expect(
          find.byKey(const Key('staff-settings-master-owner-only')),
          findsNothing,
        );
        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
        expect(find.byKey(const Key('row-admin-move-salon')), findsNothing);
        expect(
          find.byKey(const Key('row-admin-convert-to-master')),
          findsNothing,
        );
        expect(find.byKey(const Key('admin-settings-divider')), findsNothing);
      },
    );

    testWidgets('an ADMIN member is untouched by the guard', (tester) async {
      // The CONTROL. Without it the guard could be inverted (or always on)
      // and the assertions above would still pass. OWNER viewer (Phase 308
      // D3) since the terminal row is now additionally owner-gated.
      await _pump(tester, _repo(), extraOverrides: _authOverrides(_kOwner));

      expect(
        find.byKey(const Key('admin-settings-not-an-admin')),
        findsNothing,
      );
      expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
      expect(find.byKey(const Key('row-admin-move-salon')), findsOneWidget);
    });

    testWidgets('an UNRESOLVED role renders the rows, never the notice', (
      tester,
    ) async {
      // Degradation rule: the guard fires only on a RESOLVED non-admin. A
      // roster that failed to load leaves the role unknown, and the page
      // must not flash "not an administrator" over it — the same
      // `orElse: () => false` default `SalonStaffProfileScreen` uses for
      // its own trailing control. OWNER viewer (Phase 308 D3): with `member`
      // unresolved (null), `canManageStaff`'s `member?.userId` reads null,
      // and `null != currentUserId` is `true` for any signed-in viewer, so
      // ownership alone decides whether the row renders here.
      final FakeSalonRepository repo = _repo(staff: const <SalonStaffMember>[]);
      await _pump(tester, repo, extraOverrides: _authOverrides(_kOwner));

      expect(
        find.byKey(const Key('admin-settings-not-an-admin')),
        findsNothing,
      );
      expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
    });

    // Phase 308 QA gap-fill — the sibling of "an UNRESOLVED role renders the
    // rows" above, but for a NON-OWNER viewer. That test only pins the
    // isOwner==true reduction of `canManageStaff` (`isOwner && member?.userId
    // != currentUserId` reduces to `isOwner` when `member` is null); it says
    // nothing about isOwner==false during the same loading window, and
    // `isOwner` is the ONLY conjunct standing between a non-owner and the
    // row here. A defensive-coding mistake of the shape "show the row
    // whenever the role is still unresolved, sort the real gate out once it
    // loads" would slip past every other Phase 308 test: the null-member
    // tests all use an owner viewer, and the non-owner tests all use a
    // resolved member. This exercises the one combination neither covers.
    testWidgets(
      'a NON-OWNER viewer sees no remove row while the roster is still '
      'UNRESOLVED (member null) either',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[],
        );
        await _pump(
          tester,
          repo,
          extraOverrides: _authOverrides(_kAdminViewer),
        );

        expect(
          find.byKey(const Key('admin-settings-not-an-admin')),
          findsNothing,
        );
        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------
  // 16. REMOVE MASTER (Phase 307) — D2 id trap, D3/D4 gating, D5 four-way
  //     error mapping, D6 unwind + invalidation.
  // -------------------------------------------------------------------
  group('remove master — gating (D3/D4)', () {
    testWidgets(
      'a non-owner (ADMIN) viewer sees the owner-only notice, no remove row',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kAdminViewer),
        );
        final AppLocalizations l10n = _settingsL10n(tester);

        expect(
          find.byKey(const Key('staff-settings-master-owner-only')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.staffSettingsMasterOwnerOnlyTitle),
          findsOneWidget,
        );
        expect(find.byKey(const Key('row-master-remove')), findsNothing);
      },
    );

    testWidgets(
      'the owner viewing their OWN master row sees the notice card, no '
      'remove row',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwnerAsMaster),
        );

        expect(
          find.byKey(const Key('staff-settings-master-owner-only')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('row-master-remove')), findsNothing);
      },
    );

    // mobile-security LOW fix (2026-09-05) — the notice card above renders
    // for TWO distinct reasons (a non-owner viewer; the owner's own row),
    // and the "ask the owner" copy is factually wrong for the second one —
    // there is nobody else for the owner to ask. This proves the copy
    // actually DIFFERS between the two cases, not merely that the same card
    // renders for both. Asserted against literal l10n getters (never one
    // getter compared to itself, which was the CRITICAL shape flagged on
    // Phase 291) so a regression that collapses both cases back onto one
    // string goes red here.
    testWidgets("the owner's own-row copy is the SELF variant, never the "
        '"ask the owner" one', (tester) async {
      final FakeSalonRepository repo = _repo(
        staff: const <SalonStaffMember>[_kMaster],
      );
      await _pump(
        tester,
        repo,
        initial: _kMasterSettingsPath,
        extraOverrides: _masterViewerOverrides(_kOwnerAsMaster),
      );
      final AppLocalizations l10n = _settingsL10n(tester);

      expect(find.text(l10n.staffSettingsMasterSelfTitle), findsOneWidget);
      expect(find.text(l10n.staffSettingsMasterSelfBody), findsOneWidget);
      expect(
        find.text(l10n.staffSettingsMasterOwnerOnlyTitle),
        findsNothing,
        reason:
            'the "ask the owner" title must not appear when the viewer IS '
            'the owner — there is nobody else to ask',
      );
      expect(find.text(l10n.staffSettingsMasterOwnerOnlyBody), findsNothing);
    });

    testWidgets(
      'a genuinely non-owner viewer gets the "ask the owner" copy, never '
      'the self-row one',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kAdminViewer),
        );
        final AppLocalizations l10n = _settingsL10n(tester);

        expect(
          find.text(l10n.staffSettingsMasterOwnerOnlyTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.staffSettingsMasterSelfTitle),
          findsNothing,
          reason:
              'a genuinely non-owner viewer must never see the self-row copy',
        );
      },
    );

    testWidgets(
      'a resolved master with a null masterId keeps the row DISABLED',
      (tester) async {
        const SalonStaffMember masterWithNoRowId = SalonStaffMember(
          userId: _kMasterUserId,
          role: SalonStaffRole.master,
          firstName: 'Марина',
          lastName: 'Литвин',
        );
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[masterWithNoRowId],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );

        const Key rowKey = Key('row-master-remove');
        expect(find.byKey(rowKey), findsOneWidget);
        expect(_rowSemanticsEnabled(tester, rowKey), isFalse);

        // Proven by TAPPING and asserting nothing happened, not by reading
        // the widget's own `enabled` field back (vacuous).
        await tester.tap(find.byKey(rowKey), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog-remove-master')), findsNothing);
        expect(repo.removeMasterRequests, isEmpty);
      },
    );
  });

  group('remove master — the D2 id trap', () {
    testWidgets(
      'confirming calls removeMaster with the MASTER id, never the route '
      "memberId — and the fixture's two ids are DIFFERENT",
      (tester) async {
        expect(
          _kMasterRowId,
          isNot(_kMasterUserId),
          reason:
              'identical fixtures would let a userId/masterId swap pass '
              'silently — the whole point of this test',
        );

        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );

        await tester.tap(find.byKey(const Key('row-master-remove')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog-remove-master')), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
        await tester.pumpAndSettle();

        expect(repo.removeMasterRequests, <({String salonId, String masterId})>[
          (salonId: _kSalonId, masterId: _kMasterRowId),
        ]);
      },
    );

    testWidgets('dismissing the dialog calls nothing', (tester) async {
      final FakeSalonRepository repo = _repo(
        staff: const <SalonStaffMember>[_kMaster],
      );
      await _pump(
        tester,
        repo,
        initial: _kMasterSettingsPath,
        extraOverrides: _masterViewerOverrides(_kOwner),
      );

      await tester.tap(find.byKey(const Key('row-master-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-cancel-remove-master')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog-remove-master')), findsNothing);
      expect(repo.removeMasterRequests, isEmpty);
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
    });
  });

  group('remove master — D5 four-way error mapping', () {
    Future<void> confirmOnce(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('row-master-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
      await tester.pumpAndSettle();
    }

    testWidgets('403 shows the forbidden copy and stays on the page', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        staff: const <SalonStaffMember>[_kMaster],
        removeMasterError: _forbidden(),
      );
      await _pump(
        tester,
        repo,
        initial: _kMasterSettingsPath,
        extraOverrides: _masterViewerOverrides(_kOwner),
      );
      final AppLocalizations l10n = _settingsL10n(tester);

      await confirmOnce(tester);

      expect(find.text(l10n.removeMasterErrorForbidden), findsOneWidget);
      expect(find.byType(StaffSettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('row-master-remove')), findsOneWidget);
    });

    testWidgets(
      '409 shows the conflict copy, stays on the page, and invalidates the '
      'roster',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
          removeMasterError: const ServerFailure(statusCode: 409),
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );
        final AppLocalizations l10n = _settingsL10n(tester);

        final int before = repo.getSalonStaffCalls;
        await confirmOnce(tester);

        expect(find.text(l10n.removeMasterErrorConflict), findsOneWidget);
        expect(find.byType(StaffSettingsScreen), findsOneWidget);
        expect(
          repo.getSalonStaffCalls,
          greaterThan(before),
          reason:
              'every 409 cause means this page\'s picture of the roster is '
              'stale',
        );
      },
    );

    testWidgets('404 shows the not-found copy and unwinds', (tester) async {
      final FakeSalonRepository repo = _repo(
        staff: const <SalonStaffMember>[_kMaster],
        removeMasterError: const ServerFailure(statusCode: 404),
      );
      final GoRouter router = await _pump(
        tester,
        repo,
        initial: _kMasterSettingsPath,
        extraOverrides: _masterViewerOverrides(_kOwner),
      );
      final AppLocalizations l10n = _settingsL10n(tester);

      await confirmOnce(tester);

      expect(find.text(l10n.removeMasterErrorNotFound), findsOneWidget);
      expect(find.byType(StaffSettingsScreen), findsNothing);
      expect(find.byKey(const Key('stub-manage-$_kSalonId')), findsOneWidget);
      expect(_lastMatchedLocation(router), RouteNames.salonManage(_kSalonId));
    });

    testWidgets('a non-403/409/404 failure shows the generic copy', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        staff: const <SalonStaffMember>[_kMaster],
        removeMasterError: const ServerFailure(statusCode: 500),
      );
      await _pump(
        tester,
        repo,
        initial: _kMasterSettingsPath,
        extraOverrides: _masterViewerOverrides(_kOwner),
      );
      final AppLocalizations l10n = _settingsL10n(tester);

      await confirmOnce(tester);

      expect(find.text(l10n.removeMasterErrorGeneric), findsOneWidget);
      expect(find.text(l10n.removeMasterErrorForbidden), findsNothing);
      expect(find.text(l10n.removeMasterErrorConflict), findsNothing);
      expect(find.text(l10n.removeMasterErrorNotFound), findsNothing);
    });
  });

  group('remove master — in-flight, success unwind and roster refresh', () {
    // mobile-perf LOW fix (2026-09-05) — calls the row's OWN `onTap` twice,
    // SYNCHRONOUSLY, rather than driving two `tester.tap()` gestures.
    //
    // `onTap` is a fired-and-forgotten `VoidCallback` — nothing awaits the
    // `Future` `_confirmRemoveMaster` returns — so the first call runs
    // synchronously up to its own `await showRemoveMasterDialog(...)` and
    // returns control immediately; the second call then re-enters
    // `_confirmRemoveMaster` while the first is still mid-dialog. That is
    // exactly the fast-double-tap race this fix closes.
    //
    // Measured — two `tester.tap()` gestures fired back-to-back with no
    // `pump()` between them does NOT reproduce this race here: by the time
    // the FIRST `tester.tap()` call's `Future` resolves,
    // `showRemoveMasterDialog`'s `Navigator.push` has already run its
    // synchronous portion and the new dialog route already occupies that
    // screen position for hit-testing, so the second gesture silently
    // misses the row (`warnIfMissed: false` swallows exactly that) instead
    // of re-entering `onTap` at all — a shape that would pass this test
    // whether or not the guard existed. Calling `onTap` directly sidesteps
    // hit-testing and exercises the guard at the exact seam it protects.
    testWidgets(
      'a double-tap before the confirm dialog mounts opens only one dialog, '
      'and confirming issues only one removeMaster call',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );

        final SettingsRow row = tester.widget<SettingsRow>(
          find.byKey(const Key('row-master-remove')),
        );
        row.onTap();
        row.onTap();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('dialog-remove-master')),
          findsOneWidget,
          reason: 'the second call must not raise a second confirm dialog',
        );

        await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
        await tester.pumpAndSettle();

        expect(repo.removeMasterRequests, <({String salonId, String masterId})>[
          (salonId: _kSalonId, masterId: _kMasterRowId),
        ]);
      },
    );

    testWidgets(
      'while the DELETE is in flight the row spins and a second tap issues '
      'nothing',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        repo.removeMasterGate = Completer<void>();
        await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );

        await tester.tap(find.byKey(const Key('row-master-remove')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
        await tester.pumpUntilFound(
          find.byKey(const ValueKey<String>('settings_row_loading')),
        );

        expect(
          find.byKey(const ValueKey<String>('settings_row_loading')),
          findsOneWidget,
        );
        expect(repo.removeMasterRequests, hasLength(1));

        await tester.tap(
          find.byKey(const Key('row-master-remove')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(
          repo.removeMasterRequests,
          hasLength(1),
          reason: 'a second tap must not issue a second DELETE',
        );

        repo.removeMasterGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a successful remove shows the success snack, unwinds to «Персонал», '
      'and REFETCHES the staff roster',
      (tester) async {
        final FakeSalonRepository repo = _repo(
          staff: const <SalonStaffMember>[_kMaster],
        );
        final GoRouter router = await _pump(
          tester,
          repo,
          initial: _kMasterSettingsPath,
          extraOverrides: _masterViewerOverrides(_kOwner),
        );
        final AppLocalizations l10n = _settingsL10n(tester);

        final int before = repo.getSalonStaffCalls;
        expect(before, greaterThan(0));

        await tester.tap(find.byKey(const Key('row-master-remove')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
        await tester.pumpAndSettle();

        expect(repo.removeMasterRequests, <({String salonId, String masterId})>[
          (salonId: _kSalonId, masterId: _kMasterRowId),
        ]);
        expect(find.text(l10n.removeMasterSuccess), findsOneWidget);
        expect(find.byType(StaffSettingsScreen), findsNothing);
        expect(find.byKey(const Key('stub-manage-$_kSalonId')), findsOneWidget);
        expect(_lastMatchedLocation(router), RouteNames.salonManage(_kSalonId));
        expect(
          repo.getSalonStaffCalls,
          greaterThan(before),
          reason:
              'the roster must be re-read after the removal — the '
              'destination screen renders that list',
        );
      },
    );
  });
}
