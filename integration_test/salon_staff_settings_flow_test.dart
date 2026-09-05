// Phase 21.6 — E2E: the two privileged actions an owner has over ONE salon
// administrator — REMOVE (unassign) and ROTATE (move to a sibling salon).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/staff_settings_screen_test.dart` proves
// both screens in isolation with `salonRepositoryProvider` STUBBED by
// `FakeSalonRepository`, mounted by a bespoke four-route `GoRouter` with no
// `redirect:` wired. Every read and write there is an in-memory method call.
// That tier structurally cannot catch:
//
//   • the REAL `salonRepositoryProvider` -> `HttpSalonRepository
//     .removeAdmin`/`.rotateAdmin`/`.getSiblingSalons` ->
//     `SalonControllerApi` / `SiblingSalonOptionMapper` chain against a real
//     (fake) HTTP backend. `getSiblingSalons` is the sharpest case in the
//     phase: backend Phase 21.3b landed AFTER the committed
//     `tool/openapi/api-spec.json` snapshot, so there is no generated DTO and
//     the rows are hand-parsed out of raw decoded JSON — an envelope shape
//     the widget tier never touches at all;
//   • that either write PERSISTS. "The administrator is gone" at the widget
//     tier is satisfied by a pop plus a client-side provider invalidation: a
//     DELETE that never reached the network, or one that addressed the wrong
//     `userId`, produces an identical screen. Only a real write followed by a
//     real refetch separates them — that is the headline assertion below;
//   • the real UI entry path (Персонал card -> staff profile -> the
//     `tune_rounded` action -> `context.push`) and `salonManageGuard`
//     admitting a genuinely authenticated SALON_OWNER on
//     `/salons/{salonId}/manage/staff/{memberId}/settings` and `/move`;
//   • the 403 copy on a REAL wire status. The widget tier injects a
//     hand-built `UnknownFailure(cause: DioException(403))`; here the 403
//     travels through `ErrorMapperInterceptor` for real, which is the exact
//     link `StaffSettingsScreen._removeErrorMessage`'s doc says is easy to
//     get wrong (403 is NOT on the interceptor's mapped-code list, so it must
//     arrive as `UnknownFailure` with the status buried in `cause`).
//
// NO PATROL FLOW: nothing in this journey touches an OS permission dialog, a
// deep link / app link, FCM or a local notification, a WebView, or a
// biometric prompt. It is a pure screen / route / provider / GET-DELETE-PATCH
// surface, so Step 2.7 Rule 3b's `integration_test/patrol/` requirement does
// not apply. Stated explicitly (mobile-qa), not omitted.
//
// FIXTURE: `salon-xyz`, the salon `salon_management_profile_flow_test.dart`
// and `salon_pending_invites_flow_test.dart` both drive, and its seeded
// administrator `admin-zzz`. `FakeBackend`'s `GET .../sibling-salons`,
// `DELETE .../admins/{userId}` and `PATCH .../admins/{userId}/salon` handlers
// are new for this phase and are GENUINELY STATEFUL: both writes really
// remove the row from the mutable `fb.salonStaff` roster the `GET .../staff`
// handler serves, so no assertion below can be satisfied by a canned response
// that happens to agree with the bug.
//
// FINDERS: widget Keys and fixture proper nouns only — never a Cyrillic UI
// string (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/staff_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/move_admin_salon_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_hub_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-xyz';

/// The seeded ADMIN roster entry (`fake_backend.dart`'s `_salonStaff`) — the
/// subject of both actions.
const String _kAdminId = 'admin-zzz';

/// The seeded MASTER roster entry. Present only as a CONTROL: neither action
/// may touch it, and «Персонал» must still list it afterwards. Without it,
/// "the roster shrank" could be satisfied by a handler that emptied the list.
const String _kMasterId = 'master-aaa';

/// The rotate destination the journey picks. Deliberately the SECOND sibling
/// — picking the first would pass even if the picker always submitted
/// `targets.first`.
const String _kDestinationSalonId = 'salon-sibling-2';

/// `salonManageGuard`'s SALON_OWNER arm authorizes against the REAL
/// `mySalonsProvider` list (`GET /salons/mine`), which `FakeBackend` seeds
/// with only `salon-owner-1`. Without this row the guard correctly bounces
/// `salon-xyz` — fixture drift, not a guard bug. Copied verbatim from
/// `salon_pending_invites_flow_test.dart`; see that file's doc for the full
/// history (including the non-null `cityId`/`oblastId` requirement).
void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

/// Logs a SALON_OWNER in and walks the REAL UI path
/// `/manage` -> «Персонал» -> the admin's card -> the `tune_rounded` action,
/// landing on [StaffSettingsScreen].
///
/// Extracted because all three tests below open with the identical approach,
/// and a `testWidgets` body that repeats it is where the assertion under test
/// stops being legible.
Future<GoRouter> _openStaffSettings(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // No «Мої салони» hub entry reaches `salon-xyz` specifically (see the
  // sibling flows' headers) — `.go` to the manage screen, then drive REAL
  // taps from there so every `context.push` under test is exercised.
  router.go(RouteNames.salonManage(_kSalonId));
  // fixed-wait-ok: settles the real async route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final AppLocalizations l10n = await AppLocalizations.delegate.load(
    const Locale('uk'),
  );
  await tester.tap(find.text(l10n.salonManageTabStaff));
  await tester.pumpAndSettle();

  final Finder adminCard = find.byKey(
    const Key('salon-manage-staff-card-$_kAdminId'),
  );
  await tester.ensureVisible(adminCard);
  await tester.pumpAndSettle();
  await tester.tap(adminCard);
  await tester.pumpAndSettle();
  expect(find.byType(SalonStaffProfileScreen), findsOneWidget);

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('btn-admin-settings')),
  );
  await AppHarness.settle(tester);

  expect(find.byType(StaffSettingsScreen), findsOneWidget);
  AppHarness.expectLocation(
    router,
    '/salons/$_kSalonId/manage/staff/$_kAdminId/settings',
    // The settings page is reached by `context.push`, which go_router
    // excludes from `currentConfiguration.uri`/`.fullPath` — `expectLocation`
    // reads the match stack instead (`forbid_naive_router_location.sh`).
  );
  return router;
}

/// Re-enters «Персонал» from scratch so the roster below is rebuilt from the
/// BACKEND rather than from client state.
///
/// `salonManagementProfileProvider` is invalidated by both success paths
/// while the acting screen is still mounted, so the landing screen already
/// re-fetches; this walks away and back anyway, and asserts the GET count
/// moved, so "it persisted" cannot be satisfied by a stale-but-correct-looking
/// cache.
Future<void> _reenterStaffTab(
  WidgetTester tester,
  GoRouter router,
  AppLocalizations l10n,
) async {
  router.go(RouteNames.salonManage(_kSalonId));
  // fixed-wait-ok: settles the real async route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.text(l10n.salonManageTabStaff));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── ITEM 1 — REMOVE, end to end. ────────────────────────────────────────
  testWidgets(
    'SALON_OWNER opens an administrator\'s settings, confirms the removal via '
    'the REAL DELETE, and the administrator stays gone across a genuine '
    'roster refetch',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);

        final GoRouter router = await _openStaffSettings(tester, fb);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(StaffSettingsScreen)),
        );

        // The page names WHICH administrator is being managed — read off the
        // roster that came over the real wire.
        expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-admin-remove')),
        );
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('remove-admin-dialog')), findsOneWidget);

        // Captured BEFORE the write: `_returnToStaffTab` invalidates
        // `salonManagementProfileProvider` while the settings page is still
        // mounted, so the roster is re-read over the REAL wire on the way
        // out. That count moving is the invalidation proof; nothing at the
        // widget tier can observe it (there, the pop alone hides the row).
        final int staffCallsBeforeWrite = fb.getSalonStaffCalls;

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('remove-admin-confirm')),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byType(StaffSettingsScreen),
        );

        // ── The WIRE ────────────────────────────────────────────────────
        expect(fb.removeAdminCalls, 1);
        expect(
          fb.lastRemoveAdminUserId,
          _kAdminId,
          reason:
              'the DELETE must address the administrator whose page this '
              'was — a removal that unassigned the wrong user would still '
              'make this row disappear from the screen',
        );
        expect(
          fb.salonStaff.map((Map<String, dynamic> r) => r['userId']),
          <String>[_kMasterId],
          reason:
              'backend state itself must show the admin gone and the master '
              'untouched',
        );

        // ── The DESTINATION ─────────────────────────────────────────────
        // Both the settings page and the now-stale staff profile are
        // unwound; the viewer lands on the salon management profile.
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage');
        expect(find.byType(SalonStaffProfileScreen), findsNothing);
        expect(find.text(l10n.adminSettingsRemoveSuccess), findsOneWidget);

        // NOT ASSERTED HERE — the sub-tab / bottom-nav reconciliation.
        //
        // An assertion on the landed tab body
        // (`salon-manage-tab-body-staff`) was written here and then REMOVED
        // because it was measured VACUOUS: mutating `kSalonStaffSubTab` from
        // 1 to 0 left this flow fully GREEN. This journey reaches the
        // settings page THROUGH the «Персонал» tab, so the tab is already
        // selected when the reconciliation runs and the write is
        // unobservable — exactly the M14 "passes for the wrong reason" shape,
        // and shipping it would have looked identical to a real pin. Do not
        // re-add it.
        //
        // The MEDIUM this raised to mobile-dev is now CLOSED (2026-08-31).
        // The tab order gained a semantic source of truth — the promoted
        // `kSalonManageTabKeys`/`salonManageTabLabels`
        // (`salon_management_profile_screen.dart`) and `kSalonTeamNavTab`
        // declared beside `SalonBottomNav.ownerAdminItems` — and both
        // constants are pinned against those lists at the UNIT tier, in
        // `test/features/salon/presentation/staff_settings_screen_test.dart`
        // group "salon tab-index constants are pinned to their owning
        // lists". That is where a re-order goes red; it cannot go red here.

        // ── PERSISTENCE against a SERVER-derived roster ─────────────────
        expect(
          fb.getSalonStaffCalls,
          greaterThan(staffCallsBeforeWrite),
          reason:
              'the roster must be RE-FETCHED after the removal — without '
              'that invalidation the viewer lands on «Персонал» still '
              'listing the administrator they just watched disappear',
        );
        await _reenterStaffTab(tester, router, l10n);
        expect(
          find.byKey(const Key('salon-manage-staff-card-$_kAdminId')),
          findsNothing,
          reason:
              'the removal must be gone on the SERVER, not just in the '
              'notifier — the list rendered here came from the post-write '
              'GET asserted above, which is the assertion the widget tier '
              'structurally cannot make',
        );
        expect(
          find.byKey(const Key('salon-manage-staff-card-$_kMasterId')),
          findsOneWidget,
          reason: 'the CONTROL: removing an admin must not empty the roster',
        );
      });
    },
  );

  // ── ITEM 2 — ROTATE, end to end. ────────────────────────────────────────
  testWidgets(
    'SALON_OWNER moves an administrator to a sibling salon via the REAL '
    'PATCH, and the source roster loses them across a genuine refetch',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);

        final GoRouter router = await _openStaffSettings(tester, fb);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(StaffSettingsScreen)),
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-admin-move-salon')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MoveAdminSalonScreen),
        );
        // The list, not merely the route: `MoveAdminSalonScreen` mounts with
        // its sibling fetch still in flight and renders the shimmer
        // skeleton, so waiting on the screen type alone would assert the
        // card inventory one frame too early.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(
            const ValueKey<String>('move-admin-target-salon-sibling-1'),
          ),
        );
        AppHarness.expectLocation(
          router,
          '/salons/$_kSalonId/manage/staff/$_kAdminId/move',
        );

        // The picker's list came over the REAL wire and through
        // `SiblingSalonOptionMapper` — the one mapper in this phase with no
        // generated DTO behind it. Two DISTINCT cards, each keyed by its own
        // salon id: a mapper that dropped rows, or one that mis-read `id`,
        // fails here rather than three screens later.
        expect(fb.siblingSalonsCalls, 1);
        expect(find.byType(SalonHubCard), findsNWidgets(2));
        expect(
          find.byKey(
            const ValueKey<String>('move-admin-target-salon-sibling-1'),
          ),
          findsOneWidget,
        );
        final Finder destination = find.byKey(
          const ValueKey<String>('move-admin-target-$_kDestinationSalonId'),
        );
        expect(destination, findsOneWidget);

        await AppHarness.tapVisible(tester, destination);
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('move-admin-dialog')), findsOneWidget);

        // See ITEM 1's note — captured before the write for the same reason.
        final int staffCallsBeforeWrite = fb.getSalonStaffCalls;

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('move-admin-confirm')),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byType(MoveAdminSalonScreen),
        );

        // ── The WIRE ────────────────────────────────────────────────────
        expect(fb.rotateAdminCalls, 1);
        expect(
          fb.lastRemoveAdminUserId,
          isNull,
          reason: 'rotate is not remove',
        );
        expect(fb.lastRotateAdminUserId, _kAdminId);
        expect(
          fb.lastRotateAdminBody?['destinationSalonId'],
          _kDestinationSalonId,
          reason:
              'the PATCH body must carry the TAPPED card\'s salon id — the '
              'second one, so a picker that always submitted `targets.first` '
              'fails here',
        );
        expect(
          fb.salonStaff.map((Map<String, dynamic> r) => r['userId']),
          <String>[_kMasterId],
        );

        // ── The DESTINATION ─────────────────────────────────────────────
        // Three pops: picker, settings page, stale staff profile.
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage');
        expect(find.byType(StaffSettingsScreen), findsNothing);
        expect(find.byType(SalonStaffProfileScreen), findsNothing);
        expect(find.text(l10n.moveAdminSalonSuccess), findsOneWidget);

        // ── PERSISTENCE against a SERVER-derived roster ─────────────────
        expect(
          fb.getSalonStaffCalls,
          greaterThan(staffCallsBeforeWrite),
          reason: 'the SOURCE salon roster must be re-fetched after the move',
        );
        await _reenterStaffTab(tester, router, l10n);
        expect(
          find.byKey(const Key('salon-manage-staff-card-$_kAdminId')),
          findsNothing,
          reason:
              'the administrator now belongs to the destination salon, so '
              'the SOURCE roster must no longer list them',
        );
        expect(
          find.byKey(const Key('salon-manage-staff-card-$_kMasterId')),
          findsOneWidget,
        );
      });
    },
  );

  // ── ITEM 3 — a REAL 403, rendered as readable Ukrainian. ────────────────
  //
  // 403 is deliberately NOT on `ErrorMapperInterceptor`'s mapped-code list,
  // so it reaches the screen as `UnknownFailure` with the status buried in
  // `Failure.cause`. Both screens read it back out of there specifically to
  // say something the viewer can act on. The widget tier hand-builds that
  // shape; this is the only tier that produces it for real, which is the
  // whole point — if the interceptor ever started mapping 403, the widget
  // tier's fixture would silently stop matching production and keep passing.
  testWidgets(
    'a server-rejected removal (403) shows the distinct forbidden sentence '
    'and leaves the administrator on the roster',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        // A real 403 on the real endpoint — e.g. a self-removal, or a viewer
        // without management access.
        fb.forceRemoveAdminFailure(403);

        final GoRouter router = await _openStaffSettings(tester, fb);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(StaffSettingsScreen)),
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-admin-remove')),
        );
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('remove-admin-confirm')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.text(l10n.adminSettingsRemoveErrorForbidden),
        );

        expect(fb.removeAdminCalls, 1);
        expect(
          find.text(l10n.adminSettingsRemoveErrorGeneric),
          findsNothing,
          reason:
              'a 403 must NOT collapse into the generic server-error '
              'sentence — it is the one failure the viewer can act on',
        );

        // Still on the page, nothing unwound, nothing removed anywhere.
        expect(find.byType(StaffSettingsScreen), findsOneWidget);
        AppHarness.expectLocation(
          router,
          '/salons/$_kSalonId/manage/staff/$_kAdminId/settings',
        );
        expect(
          fb.salonStaff.map((Map<String, dynamic> r) => r['userId']),
          <String>[_kMasterId, _kAdminId],
          reason: 'a rejected removal must leave the backend roster intact',
        );
      });
    },
  );
}
