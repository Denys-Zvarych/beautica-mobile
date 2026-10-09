// Phase 4.5 + 4.6, rewritten Phase 351, rewritten user decision 2026-09-26 —
// E2E: INDEPENDENT_MASTER opens the «Відгуки» TAB on their own profile from
// the tab bar (the stat cards are display-only and no longer switch tabs).
// The standalone «Мої відгуки» screen this flow used to push is deleted
// (D11) — the exact same content ([MasterReviewsBody]) now renders INLINE,
// in place, on `MasterProfileScreen` itself.
//
// WHY THIS FILE EXISTS — and why it is a GENUINE guard, not coverage-theater
// --------------------------------------------------------------------------
// The reviews tab resolves the masterId it feeds to
// `GET /masters/{masterId}/reviews[/summary]`. The correctness question this
// flow pins: WHICH id? In production the `masters` table PK (`master.id`) is an
// independently generated UUID, DISTINCT from the `user_id` FK — so
// `session.user.id != master.id` for an independent master. The screen MUST
// therefore key its review endpoints on the master-row id it reads from the
// loaded profile (`GET /masters/me` → masterId), NOT on `session.user.id`.
//
// To make this flow FAIL if the wrong id is used, the fake backend is booted
// with `masterRowId` set to a value DISTINCT from the User id (`user-master-1`):
//   • the seeded reviews + summary are keyed on that master-row id;
//   • the User-id review routes are wired to return what the real backend would
//     for a non-master id — summary 404, list empty — and increment WRONG-ID
//     fingerprint counters.
// A screen that (incorrectly) queries by `session.user.id` therefore lands on
// the empty/404 routes: the seeded cards never render and this flow fails. Only
// a screen that keys on the loaded profile's master-row id renders the reviews.
//
// This flow also pins the unlabelled service-name sub-line end-to-end
// (backend `92280c3` added `serviceName` to `ReviewResponse`): the fake's
// mr-1 carries a real service name, mr-2 omits the field (wire null), and
// mr-3 sends an explicit empty string — the full round trip from JSON →
// generated DTO → mapper → domain model → `_masterReviewCard`'s null/empty
// guard → the shared `ReviewCard` widget is only exercised together here,
// not by any single unit or widget test alone.
//
// LOCAL-EMULATOR CAVEAT: like every integration_test flow, this drives the real
// VM-service websocket and may not run green headlessly from the VirtualBox VM
// without the host-only adapter UP (see MEMORY: "Integration tests need
// host-only adapter to drive"). Authored + `flutter analyze`-clean; confirm the
// green run on CI / a directly-driven emulator.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('INDEPENDENT_MASTER: tapping the reviews stat card does nothing; the '
      '«Відгуки» tab (tapped directly) renders the seeded reviews + summary '
      'INLINE (keyed on the master-row id, NOT the user id, and with NO '
      'navigation), and changing the sort reorders the list', (tester) async {
    // Master-row id DISTINCT from the User id (`user-master-1`): the crux of
    // the guard. Reviews are keyed on this id; the User-id routes are the
    // empty/404 "wrong id" fallbacks.
    final fb = FakeBackend(masterRowId: 'master-self-9')
      ..currentRole = UserRole.independentMaster;
    final router = await AppHarness.boot(tester, fb);

    // ── Log in → land on the master profile (/master/profile) ─────────────
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    // fixed-wait-ok: settles the real async login/route-transition + profile load + entrance animation; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ── ALL FOUR stat cards are DISPLAY-ONLY (user decision 2026-09-26) —
    //    «Записів місяця» / «Рейтинг» / «Послуги» / «Відгуки» must each do
    //    nothing when tapped: no tab switch, no navigation, same route. ────
    for (final String tileKey in <String>[
      'master-profile-bookings-tile',
      'master-profile-rating-tile',
      'master-profile-services-tile',
      'master-profile-reviews-tile',
    ]) {
      final Finder tile = find.byKey(Key(tileKey));
      expect(tile, findsOneWidget, reason: '$tileKey must render');
      await tester.ensureVisible(tile);
      await tester.tap(tile, warnIfMissed: false);
      // fixed-wait-ok: proving a NO-OP — there is no async work to pump
      // until; this settles any incidental animation frames only.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.byType(MasterReviewsBody),
        findsNothing,
        reason: 'tapping $tileKey must never switch the screen\'s own tab',
      );
      AppHarness.expectLocation(router, RouteNames.masterProfile);
    }

    // ── Tap the «Відгуки» TAB directly — the only way to switch. ────────
    final Finder tab = find.byKey(const Key('master-profile-tab-2'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    // fixed-wait-ok: settles the real async tab-switch + review-provider loads.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(
      find.byType(MasterReviewsBody),
      findsOneWidget,
      reason: 'the reviews render INLINE, in the tab, not on a pushed screen',
    );
    expect(find.byType(MasterProfileScreen), findsOneWidget);
    AppHarness.expectLocation(router, RouteNames.masterProfile);

    // ── The real providers hit the MASTER-ROW-id routes, never the user-id
    //    routes (the fingerprint of the session.user.id bug) ───────────────
    expect(
      fb.getMasterReviewsCalls,
      greaterThanOrEqualTo(1),
      reason: 'the list must load from GET /masters/master-self-9/reviews',
    );
    expect(
      fb.getMasterReviewSummaryCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the summary must load from '
          'GET /masters/master-self-9/reviews/summary',
    );
    expect(
      fb.getMasterReviewsWrongIdCalls,
      0,
      reason:
          'the screen must NOT query reviews by session.user.id — a non-zero '
          'value here is the fingerprint of the master.id-vs-user.id bug',
    );
    expect(
      fb.getMasterReviewSummaryWrongIdCalls,
      0,
      reason: 'the summary must NOT be queried by session.user.id',
    );
    expect(
      fb.lastGetMasterReviewsSort,
      'NEWEST',
      reason: 'the default sort wire value must reach the backend',
    );

    // ── The seeded reviews + summary render ───────────────────────────────
    expect(find.byKey(const Key('master-review-mr-1')), findsOneWidget);
    expect(find.byKey(const Key('master-review-mr-2')), findsOneWidget);
    expect(find.byKey(const Key('master-review-mr-3')), findsOneWidget);
    final Text avg = tester.widget<Text>(
      find.byKey(const Key('master-review-summary-average')),
    );
    expect(avg.data, '4.0', reason: 'the summary average must bind from data');

    // ── serviceName end-to-end: present / null / empty-string ────────────
    final Finder mr1Card = find.byKey(const Key('master-review-mr-1'));
    final Finder mr2Card = find.byKey(const Key('master-review-mr-2'));
    final Finder mr3Card = find.byKey(const Key('master-review-mr-3'));
    expect(
      find.descendant(
        of: mr1Card,
        // i18n-finder-ok: 'Манікюр' is fixture service-name data, not translated UI copy
        matching: find.text('Манікюр'),
      ),
      findsOneWidget,
      reason:
          'mr-1 has a resolved serviceName — the unlabelled «Манікюр» '
          'sub-line must render end-to-end',
    );
    expect(
      find.descendant(of: mr2Card, matching: find.byIcon(Icons.spa_outlined)),
      findsNothing,
      reason: 'mr-2 omits serviceName on the wire — no sub-line at all',
    );
    expect(
      find.descendant(of: mr3Card, matching: find.byIcon(Icons.spa_outlined)),
      findsNothing,
      reason:
          'mr-3 sends an explicit empty-string serviceName — must ALSO '
          'hide the sub-line, never a bare «послуга: »',
    );

    // Default NEWEST order → mr-1 (2026-06-10) is above mr-2 (2026-05-01).
    double topOf(String id) =>
        tester.getTopLeft(find.byKey(Key('master-review-$id'))).dy;
    expect(
      topOf('mr-1') < topOf('mr-2'),
      isTrue,
      reason: 'NEWEST must place mr-1 above mr-2',
    );

    // ── Change the sort to OLDEST → the list re-fetches AND reorders ──────
    await tester.tap(find.byKey(const Key('master-reviews-sort-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('master-review-sort-option-oldest')));
    await tester.pumpAndSettle();

    expect(
      fb.lastGetMasterReviewsSort,
      'OLDEST',
      reason: 'selecting OLDEST must re-fetch with the new sort wire value',
    );
    // OLDEST order → mr-2 (2026-05-01) now above mr-1 (2026-06-10).
    expect(
      topOf('mr-2') < topOf('mr-1'),
      isTrue,
      reason: 'OLDEST must reorder the list so mr-2 is above mr-1',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  // Phase 24.5 — the «Послуги» tab body is the shared ProfileServicesTab:
  // tapping a category card opens the owner's services list with THAT
  // category expanded (FACE only — NAILS stays collapsed).
  testWidgets('INDEPENDENT_MASTER: «Послуги» tab category card opens '
      'ServicesListScreen with that category expanded', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    // fixed-wait-ok: settles the real async login/route-transition + profile load.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final Finder tab = find.byKey(const Key('master-profile-tab-1'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    // fixed-wait-ok: settles the tab switch + services provider load.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final Finder card = find.byKey(const Key('profile-category-FACE'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    // fixed-wait-ok: settles the push transition + services list build.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ServicesListScreen), findsOneWidget);
    AppHarness.expectLocation(
      router,
      '${RouteNames.services}?expandCategory=FACE',
    );
    expect(find.byKey(const Key('service_card_assign-2')), findsOneWidget);
    expect(find.byKey(const Key('service_card_assign-1')), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
