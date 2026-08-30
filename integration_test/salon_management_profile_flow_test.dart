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
// No UI entry point reaches `/salons/:salonId/manage` itself yet (Phase
// 21.1's "Мої салони" hub is unbuilt — see `salon_settings_screen.dart`'s own
// header doc), so this flow drives the router directly via `router.go(...)`
// after a REAL login, exactly like `edit_profile_flow_test.dart`'s
// `professionalTitle` case does for `RouteNames.masterEditPersonal`. From
// `/manage` onward, both the phone-edit and delete journeys below now drive
// the REAL Phase 21.9/21.10/21.13 UI path (settings hub -> dedicated edit
// screen / -> «Загальне» -> account page), not a synthetic key — the old
// inline «Редагувати профіль» edit mode and the old 2-row settings hub with
// its own «Видалити салон» row (`row-salon-edit-profile` / `field-salon-phone`
// / `btn-salon-save-edit` / `row-salon-delete`) were replaced by commit
// `209cea0`'s Phase 21.10/21.13 rebuild; see `salon_settings_screen.dart`'s
// own header doc for the full shape of that rebuild.
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
import 'package:beautica_mobile/features/salon/presentation/salon_contacts_edit_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
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
///
/// mobile-qa fixture-drift fix (2026-08-30, discovered while re-authoring
/// this file's phone-edit journey onto the Phase 21.10 dedicated edit
/// screens) — this row used to omit `cityId`/`oblastId`. `SalonResponse
/// .cityId`/`.oblastId` are non-null on the wire as of backend `ec22d91`
/// (`salons.city_id` DB-level `NOT NULL`), so `GET /salons/mine`
/// deserializing THIS row throws `BuiltValueNullFieldError` inside
/// `mySalonsProvider.build()` — invisible to the OLDER `/manage` and
/// `/manage/invite` routes this file already exercised, since
/// `salonManageGuard`'s SALON_OWNER arm ADMITS while `mySalonsProvider` has
/// not resolved (its documented cold-deep-link fallback), but FATAL to
/// `salonManageOwnerOnlyGuard` — the guard on the three Phase 21.10 dedicated
/// edit routes (`profile-edit`/`address-edit`/`contacts-edit`) — which
/// deliberately does NOT inherit that tolerance and fails closed, bouncing
/// to `roleHomePath` (`/salons/home`) whenever `mySalonsProvider` is not a
/// genuinely resolved `AsyncData`. `salon_edit_forms_flow_test.dart` hit and
/// fixed this identical gap first; seeded here to the SAME `city-kyiv`/
/// `oblast-kyiv` pair for consistency.
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

        // The REAL repository fired the salon-detail + staff-roster reads.
        // Phase 21.5 — the management profile now reads the staff roster
        // (`getSalonStaff`, masters + admins), not the public masters rail
        // (`getSalonMasters`) — see `salon_management_profile_notifier.dart`.
        expect(fb.getSalonByIdCalls, greaterThanOrEqualTo(1));
        expect(fb.lastGetSalonId, _kSalonId);
        expect(fb.getSalonStaffCalls, greaterThanOrEqualTo(1));

        // Hero card renders the real fixture name.
        // i18n-finder-ok: fixture data, not UI copy.
        expect(find.text('Студія Краси «Камелія»'), findsOneWidget);

        // ── Cover control -> settings -> «Контакти» -> dedicated edit screen
        // Phase 21.10 replaced the old single «Редагувати профіль» inline
        // edit mode with three dedicated edit screens — «Контакти»
        // (`SalonContactsEditScreen`) is the one that owns phone + Instagram,
        // exactly the fields the old inline form used to combine with
        // name/description (see `salon_settings_screen.dart`'s header doc).
        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(SalonSettingsScreen), findsOneWidget);

        final Finder contactsRow = find.byKey(const Key('row-salon-contacts'));
        await tester.ensureVisible(contactsRow);
        await tester.pumpAndSettle();
        await tester.tap(contactsRow);
        await tester.pumpAndSettle();
        expect(find.byType(SalonContactsEditScreen), findsOneWidget);

        expect(find.byKey(const Key('salon_phone')), findsOneWidget);
        // Phone starts BLANK — the real Phase 21.2 gap (GET never returns
        // it) — even against a REAL wire response, not just the widget-tier
        // fake.
        final phoneField = tester.widget<TextField>(
          find.byKey(const Key('salon_phone')),
        );
        expect(phoneField.controller!.text, isEmpty);

        // Edit ONLY the phone — name/description/instagram stay untouched.
        // [UaPhoneInputFormatter] masks as-typed (proven by
        // `ua_phone_input_formatter_test.dart`); the wire value is the
        // masked text verbatim (no strip step), same as every other
        // masked-phone flow (`client_profile_settings_flow_test.dart`).
        await tester.enterText(
          find.byKey(const Key('salon_phone')),
          '+380 67 111 22 33',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('save_salon_contacts')));
        await tester.pumpAndSettle();
        // fixed-wait-ok: settles the real async PATCH round-trip + the
        // notifier's state-merge/pop sequence before the next assertion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // ── MANDATE 3, proven against a REAL serialized wire body ──────────
        expect(fb.updateSalonCalls, 1);
        expect(fb.lastUpdateSalonBody, isNotNull);
        final body = fb.lastUpdateSalonBody!;
        expect(
          body['phone'],
          '+380 67 111 22 33',
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

        // A successful save pops back to the settings hub — not the manage
        // screen directly (`SalonContactsEditScreen._save` calls
        // `context.pop()`, mirroring every other Phase 21.10 edit screen).
        expect(find.byKey(const Key('salon_phone')), findsNothing);
        expect(find.byType(SalonSettingsScreen), findsOneWidget);

        // Close the settings hub and confirm the read view now shows the
        // saved phone — proves the notifier's merged state actually reached
        // the still-mounted (offstage) [SalonManagementProfileScreen], not
        // just the edit screen's own local form state.
        await tester.tap(find.byKey(const Key('btn-close-salon-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
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

        // Phase 21.13 moved «Видалити салон» OFF the settings hub and onto
        // the bottom of the shared account page («Загальне» ->
        // [SettingsScreen], `showDeleteSalon: isOwner`) — see
        // `salon_settings_screen.dart`'s own header doc. Drive the REAL
        // «Загальне» tap (not `router.go`) so the settings hub's own
        // `context.push(RouteNames.settings, extra: AccountSettingsExtras(...))`
        // wiring — the thing that actually threads `showDeleteSalon: true`
        // through — is exercised end to end, not bypassed.
        await tester.tap(find.byKey(const Key('row-salon-general')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('row-delete-salon')), findsOneWidget);
        await tester.tap(find.byKey(const Key('row-delete-salon')));
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

  // ── mobile-qa gap-closure (Phase 21.5, Step 2.7 Rule 3b) ─────────────────
  //
  // `salon_staff_profile_screen_test.dart` (widget tier) proves the MASTER-
  // vs-ADMIN render contract against a mocked `salonStaffMemberProfileProvider`
  // directly. It CANNOT catch:
  //   • the real Персонал-tab card tap -> `context.push(RouteNames
  //     .salonManageStaffMember(...))` -> `salonManageGuard` -> the REAL
  //     `SalonRepository.getSalonStaff` -> `SalonStaffMemberMapper` chain
  //     deserializing a REAL (fake) wire envelope end to end;
  //   • that `salonStaffMemberProfileProvider` genuinely reads the
  //     ALREADY-CACHED roster (`salonManagementProfileProvider`) instead of
  //     re-fetching — the mobile-perf INFO follow-up this test pins: a
  //     future refactor could silently reintroduce a redundant
  //     `GET /salons/{salonId}/staff` per staff-profile navigation, and
  //     nothing at the widget tier (which stubs the provider directly)
  //     would ever observe that regression.
  //
  // Drills into BOTH roster roles from the fixture's real staff list
  // (`master-aaa` + `admin-zzz`, `fake_backend.dart`'s `_salonStaff`), via
  // the REAL "Персонал" tab -> card tap path, not `router.go`.
  testWidgets(
    'SALON_OWNER opens the Персонал tab and drills into a MASTER and an '
    'ADMIN staff profile via the REAL roster — no redundant GET /staff '
    '(mobile-perf INFO follow-up)',
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

        expect(fb.getSalonStaffCalls, 1);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        await tester.tap(find.text(l10n.salonManageTabStaff));
        await tester.pumpAndSettle();

        // ── MASTER branch: master-aaa ──────────────────────────────────────
        final Finder masterCard = find.byKey(
          const Key('salon-manage-staff-card-master-aaa'),
        );
        await tester.ensureVisible(masterCard);
        await tester.pumpAndSettle();
        await tester.tap(masterCard);
        await tester.pumpAndSettle();

        AppHarness.expectLocation(
          router,
          '/salons/$_kSalonId/manage/staff/master-aaa',
        );
        expect(
          find.byType(SalonStaffProfileScreen),
          findsOneWidget,
          reason: 'salonManageGuard must ADMIT a real SALON_OWNER session',
        );
        expect(find.text(l10n.salonStaffProfileMasterTitle), findsOneWidget);
        // i18n-finder-ok: fixture name, not UI copy.
        expect(find.text('Софія Бондар'), findsOneWidget);
        expect(
          find.byKey(const Key('salon-staff-profile-contact-phone')),
          findsOneWidget,
        );
        // The read-only ServiceCategoryCardList section renders from the
        // REAL `GET /masters/master-aaa/services` fetch — the fixture's
        // master-aaa carries two active NAILS-category services.
        expect(
          find.byKey(const Key('salon-staff-profile-service-categories')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('staff-profile-category-NAILS')),
          findsOneWidget,
        );

        // mobile-perf INFO follow-up — reaching a MASTER's profile from the
        // ALREADY-cached «Персонал» roster must NOT re-fetch GET /staff.
        expect(
          fb.getSalonStaffCalls,
          1,
          reason:
              'salonStaffMemberProfileProvider watches the already-cached '
              'salonManagementProfileProvider roster, not a fresh '
              'GET /staff round trip',
        );
        expect(
          fb.getPublicMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason: 'a MASTER entry additionally fetches its active services',
        );

        router.pop();
        await tester.pumpAndSettle();
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage');

        // ── ADMIN branch: admin-zzz ─────────────────────────────────────────
        final Finder adminCard = find.byKey(
          const Key('salon-manage-staff-card-admin-zzz'),
        );
        await tester.ensureVisible(adminCard);
        await tester.pumpAndSettle();
        await tester.tap(adminCard);
        await tester.pumpAndSettle();

        AppHarness.expectLocation(
          router,
          '/salons/$_kSalonId/manage/staff/admin-zzz',
        );
        expect(find.byType(SalonStaffProfileScreen), findsOneWidget);
        expect(find.text(l10n.salonStaffProfileAdminTitle), findsOneWidget);
        // i18n-finder-ok: fixture name, not UI copy.
        expect(find.text('Ірина Ковальська'), findsOneWidget);
        expect(
          find.byKey(const Key('salon-staff-profile-contact-phone')),
          findsOneWidget,
        );
        // The admin contract is largely ABSENCE — no stats, no bio, no
        // service categories — asserted explicitly, not inferred from the
        // master branch above.
        expect(
          find.byKey(const Key('salon-staff-profile-rating-value')),
          findsNothing,
        );
        expect(find.byKey(const Key('salon-staff-profile-bio')), findsNothing);
        expect(
          find.byKey(const Key('salon-staff-profile-service-categories')),
          findsNothing,
        );

        // Still no second GET /staff, and the admin branch never calls
        // getMasterServices — so master-aaa's own services call count is
        // unchanged from the master branch above.
        expect(fb.getSalonStaffCalls, 1);
      });
    },
  );
}
