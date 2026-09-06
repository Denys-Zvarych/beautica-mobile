// mobile-qa (2026-09-06) — E2E regression for the invite-accept → salon-home
// landing, the exact path a real user walked and hit a dead end on.
//
// THE INCIDENT
// ------------
// An owner invited an admin; the invitee opened the emailed link, saw the
// invite screen with their own address on it, typed name + surname + phone,
// pressed the CTA — and got a blank screen carrying «Щось пішло не так.
// Спробуйте ще раз.» with no way forward.
//
// Cause: `UserMapper.fromAuthResponse` did not carry `salonId`, which the
// backend DOES return on `POST /api/v1/auth/invite/accept` (verified live:
// HTTP 201 with a populated `salonId`). The session therefore reached
// `roleHomePath(salonAdmin)` → `/salons/home` with `user.salonId == null`, and
// `SalonHomeResolverScreen` fell into its "admin with no bound salon" arm.
//
// WHY ONLY THIS PATH BROKE — and why only an E2E can hold it
// -----------------------------------------------------------
// `acceptInvite` is the ONLY session-establishing flow that never follows with
// `repo.me()`. `login`, `verifyEmail` and the cold-start `build()` all do, and
// the `GET /users/me` profile DTO carries `salonId` — so all three REPAIRED the
// dropped binding and none of them can express the defect. The accept path
// cannot repair it by contract: the 2xx is its documented point of no return
// (`http_auth_repository.dart:583`), so nothing may go back to the network
// after it. That makes the `AuthResponse` envelope the session's ONLY source
// for the binding, and the mapper the only thing carrying it.
//
// What the two existing tiers can and cannot say:
//   • `test/features/auth/data/user_mapper_test.dart` pins the mapper against a
//     Dart-constructed DTO. It cannot testify that the field survives the
//     built_value DECODE of the real `ApiResponse<AuthResponse>` wire shape, and
//     it says nothing about where the value then goes.
//   • `test/features/salon/presentation/salon_home_resolver_screen_test.dart`
//     pins the resolver's incomplete-session arm and its retry — by HANDING the
//     screen a session with a null `salonId`. It is the arm the user should
//     never have reached; it cannot say which flows reach it.
//   Neither tier joins them. This file is the only place where an invite
//   accepted over the wire has to produce a session that actually lands.
//
// NO PATROL FLOW IS WARRANTED (explicit mobile-qa verdict)
// --------------------------------------------------------
// Step 2.7 Rule 3b calls for an `integration_test/patrol/` flow only when a
// NATIVE interaction is involved — an OS permission dialog, a platform-handed
// deep link, FCM / a local notification, a WebView, or biometrics. The DEFECT
// here has none: it is a pure Dart JSON→domain mapping fault whose blast radius
// is a go_router redirect, and it reproduces identically however the screen was
// reached. The platform hand-off half of the invite link (Android App Link →
// `/invite/accept?token=…` mounting the screen) IS native, and it is ALREADY
// covered by `integration_test/patrol/deep_link_patrol_test.dart`, which asserts
// the `accept_invite_screen` key the instant go_router mounts it. Duplicating
// that here in patrol would re-run a covered native hand-off to reach a
// non-native bug: coverage theatre, and slower.
//
// FAKE-BACKEND ADDITIONS THIS FILE NEEDED
// ---------------------------------------
// `GET /api/v1/auth/invite/validate` did not exist in `fake_backend.dart` at
// all, so the screen's `acceptInviteProvider(token)` resolved to an AsyncError
// and rendered the invalid-invite banner — the form was UNREACHABLE from
// `integration_test/`, which is why this whole flow had never been testable.
// The route (plus `lastAcceptInviteBody` / `lastValidateInviteToken`) is added
// in that file, branching on `currentRole` like login/accept already do.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/accept_invite_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/user_role_l10n.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_home_resolver_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// `_adminUserJson.salonId` — the salon the invite binds the new admin to, and
/// deliberately NOT the owner fixture's `salon-owner-1`: the admin landing must
/// resolve off the session alone, never off `mySalonsProvider`.
const String _kAdminSalonId = 'salon-admin-1';

/// `_adminUserJson.email` — the address the fake reports as the INVITEE and the
/// address the accept envelope signs in as. Asserted on-screen by value so a
/// preview wired to the wrong `InvitePreviewResponse` key cannot pass.
const String _kInvitedEmail = 'admin@beautica.ua';

/// The single-use token the deep link carries. Asserted to have reached the
/// wire — a screen reading the wrong query key would still render a normal form
/// off an empty token.
const String _kToken = 'invite-token-e2e';

const String _kPassword = 'StrongPassword12';
const String _kFirstName = 'Ірина';
const String _kLastName = 'Адміністратор';

/// Typed raw; `UaPhoneInputFormatter` rewrites it in the field, so the value
/// asserted on the wire below is the FORMATTED one — that difference is what
/// makes the wire assertion prove the real field was driven.
const String _kPhoneTyped = '0663334455';
const String _kPhoneOnWire = '+380 66 333 44 55';

Future<void> _fill(WidgetTester tester, String fieldKey, String value) async {
  final Finder field = find.byKey(ValueKey<String>(fieldKey));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'an invited SALON_ADMIN accepting the invite lands on their salon shell, '
    'with the invited salonId carried by the accept envelope alone',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        final GoRouter router = await AppHarness.boot(tester, fb);

        // 1 ── Unauthenticated cold start, exactly as the invitee arrives:
        //      they had logged OUT of the salon before opening the link.
        expect(
          find.byKey(const ValueKey<String>('login_email')),
          findsOneWidget,
          reason: 'cold start with no stored token must show the login form',
        );

        // 2 ── Open the invite link. `go`, not `push`: an emailed App Link
        //      REPLACES the stack, and `/invite/accept` is an unauth-only route
        //      (`auth_redirect.dart:103`) which a push from /login would leave
        //      underneath.
        router.go('${RouteNames.acceptInvite}?token=$_kToken');
        await AppHarness.settle(tester);

        expect(
          find.byType(AcceptInviteScreen),
          findsOneWidget,
          reason:
              'the resolved PAGE TYPE, not a location string — `/invite/accept` '
              'is a literal sibling of `/invite/...` paths and go_router '
              'declaration order alone can hand the URI to another builder '
              'while the location keeps reporting it verbatim.',
        );

        // The preview is rendered from `GET /auth/invite/validate`. Asserting
        // the values proves the decode, not merely that a card appeared.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(
          find.text(_kInvitedEmail),
          findsOneWidget,
          reason: 'the invited address the user reported seeing, by VALUE',
        );
        expect(
          find.text(UserRole.salonAdmin.label(l10n)),
          findsOneWidget,
          reason:
              'the wire role must decode to SALON_ADMIN — the whole defect is '
              'role-specific, and a preview that silently fell back to another '
              'role would make the landing assertion below prove nothing.',
        );
        expect(
          find.text(l10n.inviteExpiresValue(48)),
          findsOneWidget,
          reason:
              'expiry is computed against the INJECTED clock (kFixedNow), and '
              'the fixture is anchored to the same one — M15 clock coherence, '
              'asserted rather than assumed.',
        );
        expect(
          fb.lastValidateInviteToken,
          _kToken,
          reason:
              'the deep link\'s `token` query param must reach the network '
              'call; an empty token would still render a normal-looking form.',
        );

        // Copy captured BEFORE submitting: if the regression returns, the
        // resolver replaces this screen and there is no element left to read
        // AppLocalizations from.
        final String incompleteCopy = l10n.errSessionIncomplete;
        final String genericCopy = l10n.errUnknown;

        // 3 ── Fill the form the user filled, and submit.
        await _fill(tester, 'invite_password', _kPassword);
        await _fill(tester, 'invite_first_name', _kFirstName);
        await _fill(tester, 'invite_last_name', _kLastName);
        await _fill(tester, 'invite_phone', _kPhoneTyped);

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));
        await AppHarness.settle(tester);

        // 4 ── The form's own values reached the wire. Without this the tap
        //      could have been swallowed by a route barrier and the fake would
        //      still have been asked nothing.
        expect(fb.acceptInviteCalls, 1);
        final Map<String, dynamic> sent = fb.lastAcceptInviteBody!;
        expect(sent['token'], _kToken);
        expect(sent['firstName'], _kFirstName);
        expect(sent['lastName'], _kLastName);
        expect(
          sent['phoneNumber'],
          _kPhoneOnWire,
          reason:
              'the FORMATTED value — proves the real field (with its '
              'UaPhoneInputFormatter) was driven, not a controller poked '
              'directly',
        );

        // 5 ── The reported symptom is GONE. Both strings: the generic copy the
        //      user actually saw, and the specific one that replaced it.
        expect(
          find.byType(ErrorState),
          findsNothing,
          reason:
              'THE BUG: the invitee got an error screen with no way forward '
              'right after a successful HTTP 201.',
        );
        expect(find.text(incompleteCopy), findsNothing);
        expect(
          find.text(genericCopy),
          findsNothing,
          reason: 'the literal «Щось пішло не так…» the user reported',
        );
        expect(
          find.byType(SalonHomeResolverScreen),
          findsNothing,
          reason:
              'the resolver is a stopover, never a destination — still being '
              'on it after settle means it never resolved',
        );

        // 6 ── It landed, and it landed on the INVITED salon.
        expect(
          find.byType(SalonShellScreen),
          findsOneWidget,
          reason: 'the resolved PAGE TYPE of the destination',
        );
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonShell(_kAdminSalonId)),
          reason:
              'exact equality, not a prefix: the salonId is IN the path, so a '
              'session that resolved to another salon would still satisfy a '
              'startsWith(\'/salons\') match.',
        );

        // 7 ── The wire value itself, off the live session — the assertion the
        //      screen-presence checks above cannot make. `Authenticated` is
        //      pinned as a concrete type so a `copyWithPrevious` stale value
        //      cannot stand in for a resolved one.
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonShellScreen)),
        );
        final AsyncValue<AuthSession> auth = container.read(authProvider);
        expect(auth, isA<AsyncData<AuthSession>>());
        final AuthSession session = auth.value!;
        expect(session, isA<Authenticated>());
        expect(
          (session as Authenticated).user.salonId,
          _kAdminSalonId,
          reason:
              'THE REGRESSION ASSERTION: `UserMapper.fromAuthResponse` must '
              'carry `salonId` off the accept envelope. Nothing else can put '
              'it here on this path.',
        );
        expect(
          session.user.role,
          UserRole.salonAdmin,
          reason:
              'same envelope, same decode — a role that fell back would route '
              'somewhere else entirely and defang the landing assertions.',
        );

        // 8 ── …and it came from the ENVELOPE, not from a repair read. This is
        //      the discriminator that makes the whole file load-bearing: every
        //      OTHER session-establishing flow hides this defect precisely by
        //      calling `GET /users/me` afterwards.
        expect(
          fb.getMeCalls,
          0,
          reason:
              'the accept path must not call GET /users/me — its 2xx is the '
              'point of no return. If this ever becomes non-zero, the profile '
              'read would REPAIR a dropped salonId and every assertion above '
              'would pass with the mapper binding deleted.',
        );
      });
    },
  );
}
