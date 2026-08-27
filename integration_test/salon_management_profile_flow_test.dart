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

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        router.go(RouteNames.salonManageSettings(_kSalonId));
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
}
