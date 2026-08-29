// Phase 21.2 QA follow-up — E2E: SALON_OWNER editable salon-profile journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `salon_management_profile_screen_test.dart` /
// `salon_settings_screen_test.dart` prove the screens in isolation with
// [salonRepositoryProvider] STUBBED — every read/write is an in-memory fake,
// never a real HTTP round trip. That cannot catch:
//   • the real [salonRepositoryProvider] -> [HttpSalonRepository] ->
//     `SalonControllerApi.updateSalon`/`.deactivateSalon` wired against a real
//     (fake) HTTP backend — a contract drift on either would be invisible to
//     the widget tier, which never touches a real (de)serializer;
//   • the notifier's dirty-field diff surviving an ACTUAL wire round-trip —
//     the mobile-qa MANDATE 3 pin (an untouched `phone` field must never
//     PATCH over a real phone number) proven only at the unit tier so far,
//     never against a real serialized request body;
//   • `salonManageGuard` admitting a REAL, fully-authenticated SALON_OWNER
//     session (not a stubbed `AuthNotifier`) end to end.
//
// No UI entry point reaches `/salons/:salonId/manage` yet (Phase 21.1's "Мої
// салони" hub is unbuilt — see `salon_settings_screen.dart`'s own header
// doc), so this flow drives the router directly via `router.go(...)` after a
// REAL login, exactly like `edit_profile_flow_test.dart`'s
// `professionalTitle` case does for `RouteNames.masterEditPersonal`.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric — this is a pure screen/route/
// provider/PATCH-DELETE surface, so Step 2.7 Rule 3b's `integration_test/
// patrol/` requirement does not apply (mobile-qa explicit statement).
//
// Fixture: `salon-xyz`, the SAME salon `public_salon_profile_flow_test.dart`
// already exercises — `FakeBackend`'s PATCH/DELETE handlers for
// `/api/v1/salons/salon-xyz` are new (Phase 21.2 QA follow-up; the GET was
// already wired for the public-profile flow).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/invite_staff_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
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

/// mobile-qa fixture-drift fix (2026-08-28) — `salonManageGuard`'s owner arm
/// (`app_router.dart`) now authorizes `SALON_OWNER` against the REAL
/// `mySalonsProvider` list (`GET /salons/mine`, keepAlive, resolved during
/// [AppHarness.loginAs]'s post-login landing on `SalonHomeResolverScreen`),
/// bouncing any `:salonId` absent from it — the exact ownership check Phase
/// 21.2 left as a TODO. `FakeBackend.mySalons` defaults to ONLY
/// `salon-owner-1` (see its own doc), while this flow drives `router.go`
/// straight at `salon-xyz` (the public-detail fixture this file's PATCH/
/// DELETE handlers target — see the file header). Without this seed the
/// guard correctly (per its own contract) bounces `salon-xyz` to
/// `/salons/salon-owner-1/shell` — this is fixture drift, not a guard bug;
/// the guard is doing real authorization work and must keep bouncing salons
/// the owner does not own. `isPrimary: false` deliberately — `salon-owner-1`
/// stays the primary so widening the list doesn't shift any unrelated
/// "primary salon" behaviour.
void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER logs in, opens the management profile, edits ONLY the '
    'phone, and the PATCH omits every untouched field',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // No UI entry point yet — navigate directly (see file header).
        router.go(RouteNames.salonManage(_kSalonId));
        // fixed-wait-ok: settles the real async route-push step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage');
        expect(
          find.byType(SalonManagementProfileScreen),
          findsOneWidget,
          reason: 'salonManageGuard must ADMIT a real SALON_OWNER session',
        );

        // The REAL repository fired the salon-detail + masters-rail reads.
        expect(fb.getSalonByIdCalls, greaterThanOrEqualTo(1));
        expect(fb.lastGetSalonId, _kSalonId);
        expect(fb.getSalonMastersCalls, greaterThanOrEqualTo(1));

        // Hero card renders the real fixture name.
        // i18n-finder-ok: fixture data, not UI copy.
        expect(find.text('Студія Краси «Камелія»'), findsOneWidget);

        // ── Cover control -> settings -> «Редагувати профіль» -> edit mode ──
        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(SalonSettingsScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('field-salon-phone')), findsOneWidget);
        // Phone starts BLANK — the real Phase 21.2 gap (GET never returns
        // it) — even against a REAL wire response, not just the widget-tier
        // fake.
        final phoneField = tester.widget<TextField>(
          find.byKey(const Key('field-salon-phone')),
        );
        expect(phoneField.controller!.text, isEmpty);

        // Edit ONLY the phone — name/description/instagram stay untouched.
        await tester.enterText(
          find.byKey(const Key('field-salon-phone')),
          '+380671112233',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();
        // fixed-wait-ok: settles the real async PATCH round-trip + the
        // notifier's state-merge/edit-mode-close before the next assertion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // ── MANDATE 3, proven against a REAL serialized wire body ──────────
        expect(fb.updateSalonCalls, 1);
        expect(fb.lastUpdateSalonBody, isNotNull);
        final body = fb.lastUpdateSalonBody!;
        expect(
          body['phone'],
          '+380671112233',
          reason: 'the EDITED field must reach the wire',
        );
        expect(
          body['name'],
          isNull,
          reason:
              'an UNTOUCHED name must be OMITTED from the real PATCH body — '
              'not re-sent verbatim',
        );
        expect(body['description'], isNull, reason: 'untouched — omitted');
        expect(body['instagramUrl'], isNull, reason: 'untouched — omitted');
        // street/buildingNo are backend-required on every partial update —
        // always threaded through, even on the real wire body.
        expect(body['street'], isNotNull);
        expect(body['buildingNo'], isNotNull);

        // Edit mode closed and the read view now shows the saved phone.
        expect(find.byKey(const Key('field-salon-phone')), findsNothing);
        expect(
          find.byKey(const Key('salon-manage-contact-phone')),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets(
    'SALON_OWNER deletes the salon via the REAL DELETE endpoint and is '
    'navigated away',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Go to the manage screen FIRST, then PUSH settings on top — mirrors
        // the real navigation `salon_management_profile_screen.dart:269`
        // uses (`context.push`, not `.go`). This keeps
        // `SalonManagementProfileScreen` mounted (offstage) underneath, so
        // `salonManagementProfileProvider(salonId)` — an autoDispose family
        // with NO other watcher in this fixture-only flow — stays alive
        // across the `deleteSalon()` await. A single `router.go` straight to
        // `.../manage/settings` (the original shape of this test) never
        // mounts the manage screen, so the provider is watcher-less and gets
        // torn down mid-flight, throwing `UnmountedRefException` out of
        // `deleteSalon()`'s `ref.invalidate(mySalonsProvider)` — a TEST
        // fixture bug (this file skipping the real push-based navigation),
        // not a production one.
        router.go(RouteNames.salonManage(_kSalonId));
        // fixed-wait-ok: settles the real async route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        unawaited(router.push(RouteNames.salonManageSettings(_kSalonId)));
        // fixed-wait-ok: settles the real async route-push step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byKey(const Key('row-salon-delete')), findsOneWidget);
        await tester.tap(find.byKey(const Key('row-salon-delete')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('delete-salon-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
        await tester.pumpAndSettle();
        // fixed-wait-ok: settles the real async DELETE round-trip + the
        // success-snackbar/navigate-away sequence before the next assertion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          fb.deleteSalonCalls,
          1,
          reason: 'confirming must fire the REAL DELETE /salons/{salonId}',
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.deleteSalonSuccess), findsOneWidget);
        // Owner lands on '/' (no "Мої салони" hub yet — see
        // salon_settings_screen.dart's own header doc). Not via
        // `AppHarness.expectLocation` — it deliberately refuses `'/'` as a
        // target (every location satisfies that prefix, so the assertion
        // could never fail); the concrete equality check below is the real
        // assertion.
        expect(AppHarness.location(router), equals(RouteNames.home));
      });
    },
  );

  // ── Phase 21.4 QA follow-up (2026-08-29) — Invite Staff (Step 2.7 Rule 3b)
  //
  // The widget tier (`invite_staff_screen_test.dart`) proves the form/role-
  // toggle/error-copy/re-entry-guard/PopScope contract against a mocked
  // `salonRepositoryProvider`. It CANNOT catch a contract drift between
  // `HttpSalonRepository.inviteStaff` -> `SalonControllerApi.inviteMaster`
  // and a real (fake) HTTP round trip, nor that `salonManageGuard` admits a
  // REAL authenticated SALON_OWNER on `/salons/{salonId}/manage/invite`
  // specifically (a standalone top-level route, not nested under `/manage`
  // — see `app_router.dart`'s own Phase 21.4 doc on why). This flow drives
  // the REAL UI path (Персонал tab -> add-staff tile), not `router.go`, so
  // the tile's own `context.push(RouteNames.salonInviteStaff(...))` wiring
  // is exercised end to end too.
  testWidgets(
    'SALON_OWNER opens the Персонал tab, invites a new admin via the REAL '
    'POST endpoint, and pops back to the management profile',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        router.go(RouteNames.salonManage(_kSalonId));
        // fixed-wait-ok: settles the real async route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        // The add-staff tile sits below the fold on the default flutter_test
        // surface (below the master cards) — scroll it into view before
        // tapping, mirroring `TapCalendarDay`'s own reasoning
        // (`test/helpers/pump_app.dart`): a blind tap at an off-screen offset
        // does not fail loudly, it silently mis-hits.
        final Finder addStaffTile = find.byKey(
          const Key('salon-manage-add-staff'),
        );
        await tester.ensureVisible(addStaffTile);
        await tester.pumpAndSettle();
        await tester.tap(addStaffTile);
        await tester.pumpAndSettle();

        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage/invite');
        expect(
          find.byType(InviteStaffScreen),
          findsOneWidget,
          reason:
              'salonManageGuard must ADMIT a real SALON_OWNER session on '
              'the standalone /invite route too',
        );

        // Switch to Адміністратор — proves the SELECTED role (not just the
        // default) reaches the real wire body.
        await tester.tap(find.byIcon(Icons.admin_panel_settings_outlined));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_email')),
          'new.admin@beautica.ua',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('send_invite')));
        await tester.pumpAndSettle();
        // fixed-wait-ok: settles the real async POST round-trip + the
        // success-snack/pop sequence before the next assertion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          fb.inviteStaffCalls,
          1,
          reason: 'submit must fire the REAL POST /salons/{salonId}/invite',
        );
        final body = fb.lastInviteStaffBody!;
        expect(body['email'], 'new.admin@beautica.ua');
        expect(body['role'], 'SALON_ADMIN');

        expect(find.text(l10n.inviteStaffSuccess), findsOneWidget);
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage');
        expect(find.byType(InviteStaffScreen), findsNothing);
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
      });
    },
  );

  testWidgets(
    'a REAL 403 from POST /invite surfaces the forbidden-specific copy and '
    'does NOT pop',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        fb.forceInviteStaffFailure(403);
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // `.go` to the manage screen FIRST, then PUSH the invite route on
        // top — mirrors the delete-salon test's own reasoning above: a bare
        // `router.go` straight to `.../invite` leaves NOTHING on the stack
        // beneath it, so if this test's own premise (submit must NOT pop on
        // failure) were ever violated, `context.pop()` would crash the
        // harness with a `GoError` instead of just failing this test's own
        // assertions — this is also the realistic path (the tile always
        // pushes on top of the manage screen).
        router.go(RouteNames.salonManage(_kSalonId));
        // fixed-wait-ok: settles the real async route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        unawaited(router.push(RouteNames.salonInviteStaff(_kSalonId)));
        // fixed-wait-ok: settles the real async route-push step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_email')),
          'blocked@beautica.ua',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('send_invite')));
        await tester.pumpAndSettle();
        // fixed-wait-ok: settles the real async POST round-trip before the
        // next assertion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(fb.inviteStaffCalls, 1);
        expect(find.text(l10n.inviteStaffErrorForbidden), findsOneWidget);
        // A failed submit must NOT pop the form.
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage/invite');
      });
    },
  );
}
