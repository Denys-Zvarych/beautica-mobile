// Phase 21.6 — Widget tests for [AdminSettingsScreen] and
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
//      the pin `admin_settings_screen.dart`'s doc comment used to claim
//      existed; it did not.
//  15. ROLE GUARD (audit follow-up) — the page renders a notice, not the
//      admin-only DELETE/PATCH rows, when the route is reached for a MASTER
//      entry; plus the admin control and the unknown-role degradation case.
//
// Finders use widget Keys and l10n-resolved strings — never Cyrillic
// literals (`forbid_cyrillic_finder.sh`). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/domain/sibling_salon_option.dart';
import 'package:beautica_mobile/features/salon/presentation/admin_settings_screen.dart';
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
final String _kSettingsPath = RouteNames.salonManageAdminSettings(
  _kSalonId,
  _kAdminId,
);

const SalonStaffMember _kAdmin = SalonStaffMember(
  userId: _kAdminId,
  role: SalonStaffRole.admin,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

List<SiblingSalonOption> _siblings() => const <SiblingSalonOption>[
  SiblingSalonOption(
    id: 'salon-2',
    name: 'Студія «Камелія»',
    street: 'Хрещатик',
    buildingNo: '12',
  ),
  SiblingSalonOption(
    id: 'salon-3',
    name: 'Барбершоп «Дуб»',
    street: 'Січових Стрільців',
    buildingNo: '4',
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
      ? RouteNames.salonManageAdminSettings(_kSalonId, _kAdminId)
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
      builder: (context, state) => AdminSettingsScreen(
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
}) {
  final repo = FakeSalonRepository(
    salon: _kSalon,
    staff: staff ?? const <SalonStaffMember>[_kAdmin],
    siblingSalons: siblings,
  );
  repo.removeAdminError = removeError;
  repo.rotateAdminError = rotateError;
  repo.siblingSalonsError = siblingsError;
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
    AppLocalizations.of(tester.element(find.byType(AdminSettingsScreen)));

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
      await _pump(tester, _repo());

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
      expect(find.byType(AdminSettingsScreen), findsOneWidget);
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
      final GoRouter router = await _pump(tester, repo);

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
      expect(find.byType(AdminSettingsScreen), findsNothing);
      expect(_lastMatchedLocation(router), RouteNames.salonManage(_kSalonId));
    });

    testWidgets('backing out of the dialog issues nothing', (tester) async {
      final FakeSalonRepository repo = _repo();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remove-admin-dialog')), findsNothing);
      expect(repo.removeAdminRequests, isEmpty);
      expect(find.byType(AdminSettingsScreen), findsOneWidget);
    });

    testWidgets('403 shows the forbidden copy and stays on the page', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(removeError: _forbidden());
      await _pump(tester, repo);
      final AppLocalizations l10n = _settingsL10n(tester);

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorForbidden), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsNothing);
      expect(find.byType(AdminSettingsScreen), findsOneWidget);
    });

    testWidgets('a non-403 failure shows the generic copy', (tester) async {
      final FakeSalonRepository repo = _repo(
        removeError: const ServerFailure(statusCode: 500),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _settingsL10n(tester);

      await tester.tap(find.byKey(const Key('row-admin-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-admin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminSettingsRemoveErrorGeneric), findsOneWidget);
      expect(find.text(l10n.adminSettingsRemoveErrorForbidden), findsNothing);
    });
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
  // a no-op. Measured — mutating `admin_settings_screen.dart:337`
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
    testWidgets(
      'while the DELETE is in flight the row spins and a second tap issues '
      'nothing',
      (tester) async {
        final FakeSalonRepository repo = _repo();
        repo.removeAdminGate = Completer<void>();
        await _pump(tester, repo);

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
      await _pump(tester, repo);

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
          RouteNames.salonManageAdminSettings(_kSalonId, _kAdminId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminSettingsScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-close-admin-settings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-staff-$_kAdminId')), findsOneWidget);
      expect(find.byType(AdminSettingsScreen), findsNothing);
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
              'kSalonStaffSubTab is the position AdminSettingsScreen and '
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
    testWidgets('a MASTER member renders the notice, not the action rows', (
      tester,
    ) async {
      final FakeSalonRepository repo = _repo(
        // Same userId the route carries — only the ROLE differs from the
        // fixture every other test in this file uses.
        staff: const <SalonStaffMember>[
          SalonStaffMember(
            userId: _kAdminId,
            masterId: 'master-1',
            role: SalonStaffRole.master,
            firstName: 'Олена',
            lastName: 'Ковальчук',
          ),
        ],
      );
      await _pump(
        tester,
        repo,
        // A master entry makes the profile provider load that master's
        // services; without this the read hits the real Dio stack and the
        // whole tuple never resolves, so the role would stay unknown and
        // this test would pass/fail for the wrong reason.
        extraOverrides: <Object>[
          publicServiceRepositoryProvider.overrideWithValue(
            FakeServiceRepository(),
          ),
        ],
      );
      final AppLocalizations l10n = _settingsL10n(tester);

      expect(
        find.byKey(const Key('admin-settings-not-an-admin')),
        findsOneWidget,
      );
      expect(find.text(l10n.adminSettingsNotAnAdminTitle), findsOneWidget);

      // The three admin-only rows, the hairline and the context subheading
      // are all gone — not merely disabled.
      expect(find.byKey(const Key('row-admin-remove')), findsNothing);
      expect(find.byKey(const Key('row-admin-move-salon')), findsNothing);
      expect(
        find.byKey(const Key('row-admin-convert-to-master')),
        findsNothing,
      );
      expect(find.byKey(const Key('admin-settings-divider')), findsNothing);
      expect(find.byType(SettingsRow), findsNothing);
    });

    testWidgets('an ADMIN member is untouched by the guard', (tester) async {
      // The CONTROL. Without it the guard could be inverted (or always on)
      // and the assertions above would still pass.
      await _pump(tester, _repo());

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
      // its own trailing control.
      final FakeSalonRepository repo = _repo(staff: const <SalonStaffMember>[]);
      await _pump(tester, repo);

      expect(
        find.byKey(const Key('admin-settings-not-an-admin')),
        findsNothing,
      );
      expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
    });
  });
}
