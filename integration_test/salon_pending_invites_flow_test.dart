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
//     .listSalonInvites`/`.cancelInvite` -> `SalonControllerApi
//     .listSalonInvites`/`.cancelInvite` -> `SalonInviteMapper` chain
//     against a real (fake) HTTP backend. A contract drift on ANY link —
//     a renamed wire field, a `role` string the mapper stops recognising, a
//     path that no longer carries `{inviteId}` — is invisible to a tier that
//     never touches a serializer;
//   • that the cancel PERSISTS. The widget tier's "the row reads «Скасовано»"
//     assertion is satisfied by a purely client-side optimistic flip: a
//     `cancelInvite` that never reached the network at all, or that addressed
//     the wrong id, still recolours a row there. Only a real DELETE followed
//     by a real REFETCH can tell the two apart — that is the headline case
//     below;
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
// .dart` drives. `FakeBackend`'s `GET /invites` + `DELETE
// /invites/{inviteId}` handlers are genuinely STATEFUL (see their own docs in
// `fake_backend.dart`): the DELETE really revokes the row IN PLACE and the
// POST really mints one, so neither assertion below can be satisfied by a
// canned response that happens to agree with the bug.
//
// FINDERS: widget Keys and fixture email addresses only — never a Cyrillic
// UI string (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/invite_staff_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_pending_invites_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_invite_row.dart';
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

/// The FOUR rows `FakeBackend.seedSalonInviteHistory()` serves — one per wire
/// status, `createdAt DESC` (newest first) exactly as the real endpoint sorts
/// them. Fixture data, not UI copy.
const List<String> _kHistoryOrder = <String>[
  'invite-hist-1', // PENDING   — the only cancellable row
  'invite-hist-2', // CANCELLED
  'invite-hist-3', // EXPIRED
  'invite-hist-4', // ACCEPTED
];
const String _kHistPending = 'invite-hist-1';

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
  FakeBackend fb, {
  String awaitRowId = _kSeedInviteA,
}) async {
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
    find.byKey(salonInviteRowKey(awaitRowId)),
  );

  AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');
  return router;
}

/// Reads the on-screen top-to-bottom order of [ids] off the LAID-OUT tree.
///
/// Position, not element order: a re-ordering that a `findsNWidgets` count
/// would happily accept is caught here.
List<String> _renderedOrder(WidgetTester tester, List<String> ids) =>
    <String>[...ids]..sort(
      (String a, String b) => tester
          .getTopLeft(find.byKey(salonInviteRowKey(a)))
          .dy
          .compareTo(tester.getTopLeft(find.byKey(salonInviteRowKey(b))).dy),
    );

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
          fb.listSalonInvitesCalls,
          1,
          reason:
              'mounting the screen must fire the REAL '
              'GET /salons/{salonId}/invites exactly once',
        );
        expect(find.byType(SalonInviteRow), findsNWidgets(2));
        // i18n-finder-ok: fixture email addresses, not UI copy.
        expect(
          find.descendant(
            of: find.byKey(salonInviteRowKey(_kSeedInviteA)),
            matching: find.text(_kSeedEmailA),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(salonInviteRowKey(_kSeedInviteB)),
            matching: find.text(_kSeedEmailB),
          ),
          findsOneWidget,
        );

        // ── Cancel the SECOND invitation ────────────────────────────────
        // The row STAYS (this is a history list); its cancel action is what
        // goes away, so that is what the wait watches for.
        await AppHarness.tapVisible(
          tester,
          find.byKey(salonInviteCancelKey(_kSeedInviteB)),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(salonInviteCancelKey(_kSeedInviteB)),
        );

        expect(fb.cancelInviteCalls, 1);
        expect(
          fb.lastCancelInviteId,
          _kSeedInviteB,
          reason:
              'the DELETE must address the TAPPED row\'s inviteId — a cancel '
              'that hit the wrong row would still drop a cancel action',
        );
        expect(find.byKey(salonInviteRowKey(_kSeedInviteA)), findsOneWidget);
        expect(find.byKey(salonInviteRowKey(_kSeedInviteB)), findsOneWidget);
        expect(find.byType(SalonInviteRow), findsNWidgets(2));
        // The sibling is untouched and still cancellable.
        expect(find.byKey(salonInviteCancelKey(_kSeedInviteA)), findsOneWidget);

        // The optimistic-transition contract, pinned at the WIRE: a
        // successful DELETE is authoritative, so the notifier must NOT
        // re-`GET`. This is unobservable at the widget tier, where the
        // "refetch" and the local flip render identically.
        expect(
          fb.listSalonInvitesCalls,
          1,
          reason:
              'a 2xx cancel flips the row locally — it must not cost a '
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
          find.byKey(salonInviteRowKey(_kSeedInviteA)),
        );
        AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');

        expect(
          fb.listSalonInvitesCalls,
          2,
          reason:
              're-entering must genuinely re-fetch — otherwise the assertion '
              'below would only be re-reading the same cached list and could '
              'not observe persistence at all',
        );
        expect(
          find.byKey(salonInviteRowKey(_kSeedInviteB)),
          findsOneWidget,
          reason:
              'the cancelled invitation is HISTORY — it must come back from '
              'the SERVER on a genuine refetch, not vanish',
        );
        expect(
          find.byKey(salonInviteCancelKey(_kSeedInviteB)),
          findsNothing,
          reason:
              'the revocation must have persisted on the SERVER, not just in '
              'the notifier — a server-side row still reading PENDING would '
              'come back offering «Скасувати» again. This is the assertion '
              'the widget tier structurally cannot make',
        );
        expect(find.byType(SalonInviteRow), findsNWidgets(2));
        expect(
          fb.pendingInvites.map((Map<String, dynamic> r) => r['status']),
          <String>['PENDING', 'CANCELLED'],
          reason:
              'backend state itself must show the second row revoked and the '
              'first untouched',
        );
      });
    },
  );

  // ── ITEM 2 — regression pin (was a deliberate red; FIXED 2026-08-30). ────
  //
  // Pins the behaviour of a bug mobile-perf found (MEDIUM):
  // `invite_staff_screen.dart`'s `_submit` popped on success WITHOUT
  // invalidating `salonInvitesProvider(salonId)`. The pending screen
  // underneath is still a live listener of that autoDispose family instance,
  // so it survived the push/pop holding the PRE-SEND list — and the invite
  // the user just watched succeed was missing from the list they landed on.
  //
  // Fixed by `ref.invalidate(salonInvitesProvider(widget.salonId))` in
  // `invite_staff_screen.dart`, placed BEFORE the `context.pop()`. That
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
        expect(find.byType(SalonInviteRow), findsNWidgets(2));

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
        // `salonInvitesProvider(salonId)`, so the screen we popped back to
        // is still rendering the two-row list it fetched before the send.
        await AppHarness.pumpUntilFound(
          tester,
          // i18n-finder-ok: a fixture email address, not UI copy.
          find.text(_kNewInviteEmail),
        );
        expect(
          find.byType(SalonInviteRow),
          findsNWidgets(3),
          reason:
              'sending an invite must refresh the pending list — a user who '
              'just saw «Запрошення надіслано» and landed on this exact '
              'screen must see the invitation they sent',
        );
      });
    },
  );

  // ── ITEM 3 — the MIXED-STATUS history journey (mobile-security MEDIUM,
  // 2026-09-02). ──────────────────────────────────────────────────────────
  //
  // Items 1 and 2 both drive an ALL-PENDING seed, so until now no tier of the
  // suite had ever run a terminal invitation through the real wire. This test
  // is the E2E half of the hostile-status gap, and it asserts three things
  // the widget tier structurally cannot:
  //
  //   * `SalonInviteMapper._statusFromWire` really parses `'ACCEPTED'`,
  //     `'EXPIRED'` and `'CANCELLED'` out of a JSON body — the widget tier
  //     constructs `SalonInvite` fixtures in Dart and never touches a
  //     serializer, so a renamed or re-cased wire value is invisible there
  //     (it would silently become `InviteStatus.unknown`: a row with no chip
  //     and no action);
  //   * the server's `createdAt DESC` order SURVIVES A REAL REFETCH, not just
  //     the first paint;
  //   * a cancel flips the row IN PLACE and the flip PERSISTS — the row comes
  //     back from the server still present and still uncancellable.
  //
  // The fixture genuinely moves every assertion: `seedSalonInviteHistory()`
  // seeds ids that ASCEND while `createdAt` DESCENDS, so a client that
  // re-sorted by id, email or status would produce a visibly different
  // sequence rather than landing on this one by luck.
  testWidgets(
    'a MIXED-status history renders newest-first with cancel offered ONLY on '
    'the pending row, and the order + the revocation both survive a genuine '
    'refetch',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        // The four-status fixture (opt-in, same tree/ledger-hygiene reason as
        // `seedPendingInvites`).
        fb.seedSalonInviteHistory();

        final GoRouter router = await _openPendingInvites(
          tester,
          fb,
          awaitRowId: _kHistPending,
        );

        expect(fb.listSalonInvitesCalls, 1);
        expect(find.byType(SalonInviteRow), findsNWidgets(4));

        // ── Server order, at the wire ──────────────────────────────────
        expect(
          _renderedOrder(tester, _kHistoryOrder),
          _kHistoryOrder,
          reason:
              'GET .../invites sorts createdAt DESC; the client must render '
              'that order verbatim, never re-sort',
        );

        // ── The hostile-status defence, end to end ─────────────────────
        // Only the PENDING row offers a cancel. Reaching this assertion
        // required `_statusFromWire` to have parsed all four wire strings —
        // an unrecognised one degrades to `unknown`, which ALSO renders no
        // cancel, so the pending row's PRESENT affordance is what proves the
        // mapper actually understood the payload rather than falling back.
        expect(find.byKey(salonInviteCancelKey(_kHistPending)), findsOneWidget);
        for (final String id in _kHistoryOrder.skip(1)) {
          expect(
            find.byKey(salonInviteCancelKey(id)),
            findsNothing,
            reason:
                'DELETE .../invites/$id 404s on the real endpoint — the row '
                'must not offer the action',
          );
        }

        // ── Cancel the one pending row ─────────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(salonInviteCancelKey(_kHistPending)),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(salonInviteCancelKey(_kHistPending)),
        );

        expect(fb.cancelInviteCalls, 1);
        expect(fb.lastCancelInviteId, _kHistPending);
        // IN PLACE: still four rows, still the same order, none removed.
        expect(find.byType(SalonInviteRow), findsNWidgets(4));
        expect(_renderedOrder(tester, _kHistoryOrder), _kHistoryOrder);
        // Nothing on the screen is cancellable any more.
        for (final String id in _kHistoryOrder) {
          expect(find.byKey(salonInviteCancelKey(id)), findsNothing);
        }
        // A 2xx cancel is authoritative — no second round trip.
        expect(fb.listSalonInvitesCalls, 1);

        // ── Leave and come back: a GENUINE refetch ─────────────────────
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
          find.byKey(salonInviteRowKey(_kHistPending)),
        );
        AppHarness.expectLocation(router, '/salons/$_kSalonId/pending-invites');

        expect(
          fb.listSalonInvitesCalls,
          2,
          reason:
              'without a real second GET the assertions below would only be '
              're-reading client state',
        );
        // Backend state FIRST, so a red below unambiguously blames the client.
        expect(
          fb.pendingInvites.map((Map<String, dynamic> r) => r['status']),
          <String>['CANCELLED', 'CANCELLED', 'EXPIRED', 'ACCEPTED'],
          reason:
              'the DELETE must have revoked the pending row on the SERVER, '
              'leaving the three terminal rows untouched',
        );
        expect(find.byType(SalonInviteRow), findsNWidgets(4));
        expect(
          _renderedOrder(tester, _kHistoryOrder),
          _kHistoryOrder,
          reason: 'the server order must survive the refetch too',
        );
        for (final String id in _kHistoryOrder) {
          expect(find.byKey(salonInviteCancelKey(id)), findsNothing);
        }
      });
    },
  );
}
