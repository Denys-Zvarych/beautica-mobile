// Phase 21.11 — E2E: the SALON_OWNER «Надіслані запрошення» journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/salon_pending_invites_screen_test.dart`
// proves the screen and the per-row cancel machine in isolation with
// [salonRepositoryProvider] STUBBED by `FakeSalonRepository` — every read and
// write is an in-memory fake, never an HTTP round trip, and the screen is
// mounted by a bespoke two-route `GoRouter` with no `redirect:` wired. That
// tier cannot catch:
//
//   • the REAL `salonRepositoryProvider` -> `HttpSalonRepository
//     .listPendingInvites`/`.cancelInvite` -> `SalonControllerApi
//     .listPendingInvites`/`.cancelInvite` -> `PendingInviteMapper` chain
//     against a real (fake) HTTP backend. A contract drift on ANY link —
//     a renamed wire field, a `role` string the mapper stops recognising, a
//     path that no longer carries `{inviteId}` — is invisible to a tier that
//     never touches a serializer;
//   • that the cancel PERSISTS. The widget tier's "the row disappears"
//     assertion is satisfied by a purely client-side optimistic removal: a
//     `cancelInvite` that never reached the network at all, or that addressed
//     the wrong id, still makes a row vanish there. Only a real DELETE
//     followed by a real REFETCH can tell the two apart — that is the
//     headline case below;
//   • the real UI entry path (settings hub row -> `context.push`) and
//     `salonManageGuard` admitting a genuinely authenticated SALON_OWNER on
//     the standalone `/salons/{salonId}/pending-invites` route.
//
// NO PATROL FLOW: nothing in this journey touches an OS permission dialog,
// deep link / app link, FCM or local notification, WebView, or biometric —
// it is a pure screen/route/provider/GET-DELETE-POST surface. Step 2.7
// Rule 3b's `integration_test/patrol/` requirement therefore does not apply
// (mobile-qa explicit statement, not an omission).
//
// FIXTURE: `salon-xyz`, the same salon `salon_management_profile_flow_test
// .dart` drives. `FakeBackend`'s `GET /invites/pending` + `DELETE
// /invites/{inviteId}` handlers are new for this phase and are genuinely
// STATEFUL (see their own docs in `fake_backend.dart`): the DELETE really
// removes the row and the POST really mints one, so neither assertion below
// can be satisfied by a canned response that happens to agree with the bug.
//
// FINDERS: widget Keys and fixture email addresses only — never a Cyrillic
// UI string (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/invite_staff_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_pending_invites_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/pending_invite_row.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-xyz';

/// The two rows `FakeBackend.pendingInvites` seeds. Fixture data, not UI copy
/// — safe (and necessary) to match literally.
const String _kSeedInviteA = 'invite-seed-a';
const String _kSeedInviteB = 'invite-seed-b';
const String _kSeedEmailA = 'anna.master@beautica.ua';
const String _kSeedEmailB = 'borys.admin@beautica.ua';

/// The address typed into the invite form by the CTA journey — deliberately
/// absent from the seeded rows, so "it appeared" cannot be satisfied by a row
/// that was already there.
const String _kNewInviteEmail = 'nova.majstrynia@beautica.ua';

/// `salonManageGuard`'s SALON_OWNER arm authorizes against the REAL
/// `mySalonsProvider` list (`GET /salons/mine`), which `FakeBackend` seeds
/// with only `salon-owner-1`. Without this row the guard correctly bounces
/// `salon-xyz` — fixture drift, not a guard bug. Same seed (and the same
/// `cityId`/`oblastId` non-null requirement) as
/// `salon_management_profile_flow_test.dart`'s own copy; see that file's doc
/// for the full history.
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
/// `/manage` -> «Налаштування» -> «Надіслані запрошення», landing on
/// [SalonPendingInvitesScreen] with its list resolved.
///
/// Extracted because BOTH tests below need the identical seven-step approach
/// and a `testWidgets` body that opens with it twice is where the assertion
/// under test stops being legible.
Future<GoRouter> _openPendingInvites(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // No «Мої салони» hub entry reaches `salon-xyz` specifically (see the
  // sibling flow's header) — `.go` to the manage screen, then drive the REAL
  // taps from there so the settings row's own `context.push` is exercised.
  router.go(RouteNames.salonManage(_kSalonId));
  // fixed-wait-ok: settles the real async route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('salon-manage-settings')),
  );
  await AppHarness.settle(tester);
  expect(find.byType(SalonSettingsScreen), findsOneWidget);

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('row-salon-sent-invites')),
  );
  // NOT `pumpAndSettle`: the pending list's LOADING branch renders
  // `SkeletonShimmerScope`, a `..repeat(reverse: true)` controller that keeps
  // `hasScheduledFrame` permanently true — `pumpAndSettle` can hang on it.
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonPendingInvitesScreen),
  );
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(pendingInviteRowKey(_kSeedInviteA)),
  );

  AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');
  return router;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── ITEM 1 — the core journey. Expected GREEN. ───────────────────────────
  testWidgets(
    'SALON_OWNER opens the settings hub, reaches «Надіслані запрошення», '
    'cancels one invitation via the REAL DELETE, and it stays gone across a '
    'genuine refetch',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        // Opt in explicitly — `FakeBackend.pendingInvites` is empty by
        // default so a shared fake never injects rows into an unrelated
        // flow's tree (see its own doc). Seeding here also keeps the fixture
        // this test asserts on visible in this test.
        fb.seedPendingInvites();

        final GoRouter router = await _openPendingInvites(tester, fb);

        // The REAL GET fired exactly once and both seeded rows deserialized
        // through PendingInviteMapper into their OWN rows.
        expect(
          fb.listPendingInvitesCalls,
          1,
          reason:
              'mounting the screen must fire the REAL '
              'GET /salons/{salonId}/invites/pending exactly once',
        );
        expect(find.byType(PendingInviteRow), findsNWidgets(2));
        // i18n-finder-ok: fixture email addresses, not UI copy.
        expect(
          find.descendant(
            of: find.byKey(pendingInviteRowKey(_kSeedInviteA)),
            matching: find.text(_kSeedEmailA),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(pendingInviteRowKey(_kSeedInviteB)),
            matching: find.text(_kSeedEmailB),
          ),
          findsOneWidget,
        );

        // ── Cancel the SECOND invitation ────────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(pendingInviteCancelKey(_kSeedInviteB)),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(pendingInviteRowKey(_kSeedInviteB)),
        );

        expect(fb.cancelInviteCalls, 1);
        expect(
          fb.lastCancelInviteId,
          _kSeedInviteB,
          reason:
              'the DELETE must address the TAPPED row\'s inviteId — a cancel '
              'that removed the wrong row would still make a row disappear',
        );
        expect(find.byKey(pendingInviteRowKey(_kSeedInviteA)), findsOneWidget);
        expect(find.byType(PendingInviteRow), findsOneWidget);

        // The optimistic-removal contract, pinned at the WIRE: a successful
        // DELETE is authoritative, so the notifier must NOT re-`GET`. This is
        // unobservable at the widget tier, where the "refetch" and the local
        // removal render identically.
        expect(
          fb.listPendingInvitesCalls,
          1,
          reason:
              'a 2xx cancel removes the row locally — it must not cost a '
              'second round trip',
        );

        // ── Leave and come back: a GENUINE refetch ──────────────────────
        // `pendingInvitesProvider` is autoDispose and nothing on the settings
        // hub watches it, so popping back disposes the family instance; the
        // list below is rebuilt from the BACKEND, not from client state.
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-back-pending-invites')),
        );
        await AppHarness.settle(tester);
        expect(find.byType(SalonSettingsScreen), findsOneWidget);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-salon-sent-invites')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(pendingInviteRowKey(_kSeedInviteA)),
        );
        AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');

        expect(
          fb.listPendingInvitesCalls,
          2,
          reason:
              're-entering must genuinely re-fetch — otherwise the assertion '
              'below would only be re-reading the same cached list and could '
              'not observe persistence at all',
        );
        expect(
          find.byKey(pendingInviteRowKey(_kSeedInviteB)),
          findsNothing,
          reason:
              'the cancelled invitation must be gone on the SERVER, not just '
              'in the notifier — this is the assertion the widget tier '
              'structurally cannot make',
        );
        expect(find.byType(PendingInviteRow), findsOneWidget);
        expect(
          fb.pendingInvites.map((Map<String, dynamic> r) => r['inviteId']),
          <String>[_kSeedInviteA],
          reason: 'backend state itself must show exactly one row left',
        );
      });
    },
  );

  // ── ITEM 2 — regression pin (was a deliberate red; FIXED 2026-08-30). ────
  //
  // Pins the behaviour of a bug mobile-perf found (MEDIUM):
  // `invite_staff_screen.dart`'s `_submit` popped on success WITHOUT
  // invalidating `pendingInvitesProvider(salonId)`. The pending screen
  // underneath is still a live listener of that autoDispose family instance,
  // so it survived the push/pop holding the PRE-SEND list — and the invite
  // the user just watched succeed was missing from the list they landed on.
  //
  // Fixed by `ref.invalidate(pendingInvitesProvider(widget.salonId))` at
  // `invite_staff_screen.dart:198`, placed BEFORE the `context.pop()`. That
  // order is load-bearing, not stylistic: after the pop, the only remaining
  // listener is the offstage/paused pending screen, and invalidating an
  // autoDispose provider whose listeners are all paused DISPOSES it instead
  // of refetching. Moving the call below the pop reintroduces the bug.
  //
  // The fixture genuinely MOVES the assertion: `FakeBackend`'s POST handler
  // really mints a pending row, and the `fb.pendingInvites` assertion below
  // runs FIRST — so a failure here can only mean the UI did not re-read a
  // backend that demonstrably has the new invitation.
  testWidgets(
    'an invite sent from the pending screen\'s CTA appears in the list on '
    'return (regression: provider invalidated before the pop)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        // Opt in explicitly — `FakeBackend.pendingInvites` is empty by
        // default so a shared fake never injects rows into an unrelated
        // flow's tree (see its own doc). Seeding here also keeps the fixture
        // this test asserts on visible in this test.
        fb.seedPendingInvites();

        final GoRouter router = await _openPendingInvites(tester, fb);
        expect(find.byType(PendingInviteRow), findsNWidgets(2));

        // ── The pinned CTA -> the invite form ───────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('pending-invites-invite-cta')),
        );
        await AppHarness.pumpUntilFound(tester, find.byType(InviteStaffScreen));
        AppHarness.expectLocation(router, '/salons/$_kSalonId/manage/invite');

        await tester.enterText(
          find.byKey(const ValueKey<String>('invite_email')),
          _kNewInviteEmail,
        );
        await tester.pump();

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('send_invite')),
        );
        // The REAL POST + the success-snack/pop sequence.
        await AppHarness.pumpUntilGone(tester, find.byType(InviteStaffScreen));

        expect(fb.inviteStaffCalls, 1);
        AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');
        expect(find.byType(SalonPendingInvitesScreen), findsOneWidget);

        // The BACKEND now holds three invitations — asserted BEFORE the UI so
        // a red below unambiguously blames the client cache, never the seed.
        expect(
          fb.pendingInvites.map(
            (Map<String, dynamic> r) => r['recipientEmail'],
          ),
          containsAll(<String>[_kSeedEmailA, _kSeedEmailB, _kNewInviteEmail]),
          reason:
              'the fake POST mints a real pending row — if this fails the '
              'FIXTURE is broken, not the app',
        );

        // THE PIN. Currently RED: nothing invalidated
        // `pendingInvitesProvider(salonId)`, so the screen we popped back to
        // is still rendering the two-row list it fetched before the send.
        await AppHarness.pumpUntilFound(
          tester,
          // i18n-finder-ok: a fixture email address, not UI copy.
          find.text(_kNewInviteEmail),
        );
        expect(
          find.byType(PendingInviteRow),
          findsNWidgets(3),
          reason:
              'sending an invite must refresh the pending list — a user who '
              'just saw «Запрошення надіслано» and landed on this exact '
              'screen must see the invitation they sent',
        );
      });
    },
  );
}
