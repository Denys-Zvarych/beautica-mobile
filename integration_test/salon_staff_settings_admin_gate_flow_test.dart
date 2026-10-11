// Phase 308 LOW closure (mobile-qa, 2026-09-05) — the D3 owner-only gate on
// `StaffSettingsScreen`'s admin-remove row, proven for a GENUINELY
// AUTHENTICATED SALON_ADMIN session, not a provider override.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/staff_settings_screen_test.dart` already
// pins `canManageStaff` at the WIDGET tier by overriding the `isOwner`
// selector directly. That proves the `if (canManageStaff)` branch itself is
// wired correctly, but it structurally CANNOT prove the gate holds for a
// real signed-in SALON_ADMIN: overriding the selector IS the thing under
// test, so a regression anywhere upstream of it — `authProvider`'s emitted
// role, `isSalonOwner`'s `Authenticated` cast,
// `auth_selectors.g.dart`'s provider wiring, or the real
// `salonManageGuard`/`salonStaffMemberProfileProvider` chain that resolves
// `member` in the first place — would leave every widget-tier assertion
// green while a real admin session saw something different. Phase 308's own
// audit filed this gap as a LOW rather than building it inline, because
// closing it means widening `FakeBackend`'s shared salon-admin-1 fixture —
// this file's own header documents the isolation choice that avoided that
// ripple (see [FakeBackend.salonAdminOneStaff]'s doc).
//
// SCOPE — ONE real chain, both directions:
//   1. NEGATIVE — a real SALON_ADMIN login -> the real SHELL «Команда» nav
//      tile -> the real roster grid (own row PRESENT too, like every other
//      row — Phase 327 deleted the self-exclusion filter; co-admin card
//      PRESENT) -> a real tap on the CO-ADMIN's card -> the real settings
//      page:
//      `row-admin-remove` and its hairline must be ABSENT, while the
//      sibling rows (move-to-salon, convert-to-master) remain PRESENT AND
//      GENUINELY LIVE (not merely rendered) — the sibling-row assertion is
//      the M14 guard: if the whole page had failed to render, the "row
//      absent" assertion would pass for the wrong reason.
//   2. POSITIVE CONTROL — the SAME co-admin, the SAME settings page, but a
//      real SALON_OWNER of `salon-admin-1` instead: `row-admin-remove` and
//      the hairline must be PRESENT, and tapping the row must open the real
//      confirmation dialog (proving the row is genuinely wired, not merely
//      present-but-dead). The write itself (the DELETE) is already E2E-
//      pinned end-to-end against `salon-xyz`/`admin-zzz` in
//      `salon_staff_settings_flow_test.dart` ITEM 1 — re-proving the wire
//      round trip here would duplicate that file's own headline assertion,
//      so this positive control stops at "the dialog opens".
//
// mobile-qa gap-closure (2026-09-12), REWRITTEN Phase 327 (2026-09-13) —
// EXTENDED (not a new file, REUSE-FIRST) for the «Команда» tab. The
// self-exclusion filter this comment used to describe
// (`salon_management_profile_screen.dart`'s `viewerIsAdmin` filter,
// narrowed from "hide every admin row" to "hide only the viewer's own row")
// is DELETED, not narrowed again — user decision, 2026-09-13: "each salon
// member can see hisself". The roster now renders EVERY row, the viewer's
// own included; only the TAP DESTINATION differs for the self row (it opens
// the personal profile — see `_openStaffMember`), never the roster's
// contents. This file already drove the SALON_ADMIN branch through
// `router.go` straight at the settings route because, at the time, an
// earlier masters-only filter made the co-admin's card genuinely
// unreachable through the grid — that premise is FALSE either way, so the
// admin branch below walks the real shell -> nav tile -> card tap path
// instead, matching the owner branch and proving the grid itself, not just
// the destination route. The gate walk stays on the CO-ADMIN card
// throughout (never the self row, which now goes somewhere else entirely) —
// see [_kCoAdminId].
//
// FIXTURE — `salon-admin-1`, the SALON_ADMIN persona's OWN salon
// (`FakeBackend._adminUserJson.salonId`), and its ISOLATED
// `salonAdminOneStaff` roster: a co-admin (`admin-peer-1`), a master
// (`user-master-under-admin`, unrelated to this file), and — added
// 2026-09-12, now asserted PRESENT rather than absent — the logged-in
// admin's OWN row (`user-admin-1`, == `FakeBackend._adminUserJson.id`),
// which lets this file prove the roster is genuinely unfiltered over the
// real wire, not merely the co-admin's reachability. Never `salon-xyz`'s own
// `salonStaff` roster — widening that would ripple into the pre-existing
// exact-roster assertions three sibling integration files already carry
// (Phase 307's own precedent for exactly this ripple).
//
// NO PATROL FLOW: pure screen / route / provider / GET surface, same as
// `salon_staff_settings_flow_test.dart`'s own header states for its reason.
//
// FINDERS: widget Keys and fixture proper nouns only — never a Cyrillic UI
// string (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/move_admin_salon_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/staff_settings_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
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

const String _kSalonId = 'salon-admin-1';

/// The logged-in SALON_ADMIN persona's OWN id
/// (`FakeBackend._adminUserJson['id']`) — the row that renders on its own
/// «Команда» tab like any other (Phase 327: no client-side filter), but
/// whose tap destination is the PERSONAL profile, never this file's gate
/// walk (which stays on [_kCoAdminId] throughout).
const String _kSelfAdminId = 'user-admin-1';

/// [FakeBackend.salonAdminOneStaff]'s CO-admin row — the settings page both
/// tests below open. Never the acting admin's own id (`_kSelfAdminId`) — see
/// that fixture's own doc.
const String _kCoAdminId = 'admin-peer-1';

/// Seeds `salon-admin-1` into the SALON_OWNER persona's `mySalons` list so
/// `salonManageGuard`'s owner arm (bound to `mySalonsProvider`) admits the
/// owner test below onto a salon that is not their own default primary
/// (`salon-owner-1`) — mirrors `salon_staff_settings_flow_test.dart`'s own
/// `_seedSalonXyzIntoMySalons` precedent for the identical reason.
void _seedAdminSalonIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Салон Адміністратора',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Січових Стрільців',
    'buildingNo': '7',
    'isActive': true,
    'isPrimary': false,
  });
}

/// Logs [role] in for real and walks the REAL UI path to the co-admin's
/// [StaffSettingsScreen] for `admin-peer-1`:
///   * SALON_OWNER — `/manage` -> «Персонал» tab -> the co-admin's card ->
///     the `tune_rounded` action;
///   * SALON_ADMIN — real shell landing -> the «Команда» nav tile -> the
///     REAL roster grid -> the CO-ADMIN's card. Asserts en route that the
///     viewer's OWN row (`_kSelfAdminId`) is PRESENT in that grid — Phase
///     327 deleted the client-side filter entirely (no self-exclusion, no
///     masters-only narrowing), so every row renders and only the self
///     row's TAP DESTINATION differs (the personal profile, wired in
///     `_openStaffMember`) — this walk never taps that row, only the
///     co-admin's.
///
/// [role] must be [UserRole.salonAdmin] or [UserRole.salonOwner] — the two
/// roles `salonManageGuard` admits onto `/manage`/the shell at all.
Future<GoRouter> _openCoAdminSettingsAs(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, role);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  if (role == UserRole.salonAdmin) {
    // Real shell landing (role_home.dart routes SALON_ADMIN through the
    // same `salonHome` resolver as SALON_OWNER) -> the «Команда» nav tile.
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(SalonShellScreen),
      timeout: const Duration(seconds: 20),
    );
    final Finder teamTile = find.byKey(const Key('salon-nav-tile-2'));
    await AppHarness.pumpUntilFound(
      tester,
      teamTile.hitTestable(),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(teamTile);
    await AppHarness.settle(tester);

    // NO CLIENT-SIDE FILTER (Phase 327) — every salon member the roster
    // returns renders, the viewer's own row included, over the REAL wire
    // (`salonAdminOneStaff` seeds it — see that fixture's own 2026-09-12
    // doc). This walk still taps the CO-ADMIN's card below, never this one —
    // the self row's destination is the personal profile, proven in
    // `salon_management_profile_flow_test.dart`, not this file's gate walk.
    //
    // mobile-perf LOW fix (2026-09-13) — the roster grid is a genuinely lazy
    // `SliverGrid.builder` (`_StaffTab`), and the self row is the third of
    // three fixture members (co-admin, master-under-admin, self) — row 2 of
    // the 2-column grid, below the fold at boot. Reuses
    // [AppHarness.revealRosterCard] — the single shared way to locate a
    // roster card — rather than a second hand-rolled copy; see that helper's
    // own REUSE-FIRST doc.
    await AppHarness.revealRosterCard(
      tester,
      find.byKey(const Key('salon-manage-staff-card-$_kSelfAdminId')),
    );
    expect(
      find.byKey(const Key('salon-manage-staff-card-$_kSelfAdminId')),
      findsOneWidget,
      reason:
          'every salon member is listed, the viewer included — the roster '
          'applies no client-side filter',
    );

    final Finder coAdminCard = find.byKey(
      const Key('salon-manage-staff-card-$_kCoAdminId'),
    );
    // The co-admin is row 0, ABOVE the self card just scrolled to. Since
    // 2026-10-05 the fake's `salon-admin-1` `/staff` roster also carries the
    // public masters (a real `/staff` is a superset of `/masters` — see
    // `FakeBackend._boardSalonStaff`), so the lazy grid is long enough for
    // that scroll to have disposed row 0, and [AppHarness.revealRosterCard]
    // only scrolls DOWN. Scroll back UP first.
    if (coAdminCard.evaluate().isEmpty) {
      await tester.scrollUntilVisible(coAdminCard, -200, maxScrolls: 20);
      await tester.pump();
    }
    await AppHarness.revealRosterCard(tester, coAdminCard);
    try {
      await tester.ensureVisible(coAdminCard);
    } catch (_) {}
    await AppHarness.pumpUntilFound(
      tester,
      coAdminCard.hitTestable(),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(coAdminCard);
    await AppHarness.settle(tester);
    expect(find.byType(SalonStaffProfileScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-admin-settings')),
    );
    await AppHarness.settle(tester);
  } else {
    router.go(RouteNames.salonManage(_kSalonId));
    // fixed-wait-ok: settles the real async route-transition step.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('uk'),
    );
    await tester.tap(find.text(l10n.salonManageTabStaff));
    await tester.pumpAndSettle();

    final Finder coAdminCard = find.byKey(
      const Key('salon-manage-staff-card-$_kCoAdminId'),
    );
    // Single shared roster-card reveal — no-ops for this row-0 target.
    await AppHarness.revealRosterCard(tester, coAdminCard);
    await tester.ensureVisible(coAdminCard);
    await tester.pumpAndSettle();
    await tester.tap(coAdminCard);
    await tester.pumpAndSettle();
    expect(find.byType(SalonStaffProfileScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-admin-settings')),
    );
    await AppHarness.settle(tester);
  }

  expect(find.byType(StaffSettingsScreen), findsOneWidget);
  AppHarness.expectLocation(
    router,
    '/salons/$_kSalonId/manage/staff/$_kCoAdminId/settings',
  );
  return router;
}

/// Whether the [SettingsRow]-shaped row under [key] is genuinely absorbing
/// taps — read off its own [AbsorbPointer] (fed by `inert = loading ||
/// !enabled` inside `settings_row.dart`), never off an `enabled`/`loading`
/// PARAMETER this test passed in. Same idiom
/// `test/features/salon/presentation/staff_settings_screen_test.dart`'s own
/// `_rowPressScale` documents: observe what the row's build actually
/// COMPUTED, not what it was configured with, so a mutation that flips the
/// row's `enabled` value is caught here even though this file never
/// constructs a [SettingsRow] itself.
bool _rowAbsorbing(WidgetTester tester, Key key) => tester
    .widget<AbsorbPointer>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(AbsorbPointer))
          .first,
    )
    .absorbing;

// ── Phase 371 (+377 §1 pulled forward) — the OWNER's row, seen by an admin ──
//
// Backend 345: the salon owner's master row is owner-only; an admin gets 403
// on its services/schedule writes. The app pre-empts that — a notice, no edit
// entry, read-only deep links. Fixture: the owner's row is appended to
// `salon-admin-1`'s roster (test-local, `salonAdminOneStaff` is mutable), with
// a distinct `userId` / `masterId` so a route built off the wrong id misses.
const String _kOwnerRowUserId = 'user-owner-of-admin-salon';
const String _kOwnerRowMasterId = 'master-owner-of-admin-salon';
const String _kOwnerRowAssignId = 'owner-row-assign-1';

FakeBackend _adminWithOwnerRow() {
  final FakeBackend fb =
      FakeBackend(
          masterRowId: _kOwnerRowMasterId,
          masterSalonId: _kSalonId,
          wireOwnRowServices: true,
          ownRowServicesSeed: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': _kOwnerRowAssignId,
              'masterId': _kOwnerRowMasterId,
              'isActive': true,
              'priceType': 'FIXED',
              'priceMin': 500,
              'priceMax': null,
              'priceDisplay': '500 ₴',
              'effectiveDurationMinutes': 60,
              'serviceDefinition': <String, dynamic>{
                'id': 'owner-row-def-1',
                'name': 'Послуга власника',
                'description': null,
                'category': 'NAILS',
                'baseDurationMinutes': 60,
                'bufferMinutesAfter': 0,
                'isActive': true,
                'priceType': 'FIXED',
                'priceMin': 500,
                'priceMax': null,
                'priceDisplay': '500 ₴',
                'photoUrl': null,
              },
            },
          ],
          wireOwnRowSchedule: true,
        )
        ..currentRole = UserRole.salonAdmin
        ..ownRowWeeklySchedule = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'owner-row-schedule-seed',
            'validFrom': '2026-01-01',
            'validTo': null,
            'days': <Map<String, dynamic>>[
              for (int d = 1; d <= 5; d++)
                <String, dynamic>{
                  'dayOfWeek': d,
                  'intervals': <Map<String, dynamic>>[
                    <String, dynamic>{'startTime': '09:00', 'endTime': '17:00'},
                  ],
                },
            ],
          },
        ];
  fb.salonAdminOneStaff.add(<String, dynamic>{
    'userId': _kOwnerRowUserId,
    'masterId': _kOwnerRowMasterId,
    'role': 'SALON_OWNER',
    'firstName': 'Олена',
    'lastName': 'Власниця',
    'professionalTitle': null,
    'avatarUrl': null,
    'phoneNumber': null,
    'instagram': null,
    'bio': null,
    'avgRating': null,
    'reviewCount': 0,
    'serviceCount': 1,
  });
  return fb;
}

/// Real admin login -> shell landing, ready for deep links.
Future<GoRouter> _bootAdminSession(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonShellScreen),
    timeout: const Duration(seconds: 20),
  );
  return router;
}

Future<void> _goAndSettle(
  WidgetTester tester,
  GoRouter router,
  String route,
  Finder landed,
) async {
  router.go(route);
  await AppHarness.pumpUntilFound(
    tester,
    landed,
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a genuinely-authenticated SALON_ADMIN viewing a co-admin\'s settings '
    'sees no remove row and no terminal hairline (D3, real session)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;

        final GoRouter router = await _openCoAdminSettingsAs(
          tester,
          fb,
          UserRole.salonAdmin,
        );

        // Sanity: the page resolved a real roster entry over the real wire —
        // if this were absent, "no remove row" would be satisfied by the
        // page failing to load at all rather than by the D3 gate.
        expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);

        // THE GATE — the terminal destructive row and its hairline are both
        // absent. `canManageStaff` (`isOwner && member?.userId !=
        // currentUserId`) is false here because a SALON_ADMIN is never
        // `isOwner`, regardless of whose row this is.
        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
        expect(find.byKey(const Key('admin-settings-divider')), findsNothing);

        // M14 GUARD — the sibling rows the admin branch always draws must
        // still be present. Without this, the two `findsNothing` assertions
        // above would also pass on a page that failed to render at all.
        final Finder moveRow = find.byKey(const Key('row-admin-move-salon'));
        expect(
          moveRow,
          findsOneWidget,
          reason:
              'the admin branch\'s OTHER rows must still render — otherwise '
              'the remove-row absence could be satisfied by a blank page',
        );
        final Finder convertRow = find.byKey(
          const Key('row-admin-convert-to-master'),
        );
        expect(convertRow, findsOneWidget);

        // GENUINELY LIVE, not merely present — mirrors the POSITIVE
        // CONTROL's own "tap opens the real dialog" proof below, applied to
        // the two rows this task requires to be distinguishable states, not
        // just two keys that both happen to exist:
        //   * row-admin-move-salon must be ENABLED (`rotateAdmin`,
        //     `PATCH /salons/{salonId}/admins/{userId}/salon`, is genuinely
        //     admin-callable, no self-guard — SalonService.java:789) — a
        //     real tap must open [MoveAdminSalonScreen].
        //   * row-admin-convert-to-master must be DISABLED (Phase 21.6 — no
        //     backend endpoint for role conversion exists) — a real tap
        //     must NOT navigate anywhere.
        expect(
          _rowAbsorbing(tester, const Key('row-admin-move-salon')),
          isFalse,
          reason:
              'move-to-salon is a genuinely admin-callable action and '
              'must accept taps',
        );
        expect(
          _rowAbsorbing(tester, const Key('row-admin-convert-to-master')),
          isTrue,
          reason:
              'no backend endpoint exists for role conversion — the row '
              'must stay visibly inert, not silently do nothing',
        );

        await tester.tap(moveRow);
        await AppHarness.settle(tester);
        expect(
          find.byType(MoveAdminSalonScreen),
          findsOneWidget,
          reason:
              'row-admin-move-salon must be a REAL, live navigation, '
              'not a present-but-dead row',
        );

        // REACHABLE is not USABLE — mobile-qa gap-closure (2026-09-12).
        // `GET /salons/salon-admin-1/sibling-salons` must have genuinely
        // resolved and rendered at least one selectable destination card
        // ([FakeBackend.salonAdminOneSiblingSalons]'s seeded
        // `salon-admin-sibling-1`), not merely landed on a screen that could
        // equally be showing its `ErrorState` branch (no fake route) or its
        // `_MoveTargetsEmptyState` branch (an empty list) — either of those
        // would also satisfy "MoveAdminSalonScreen findsOneWidget" above.
        expect(
          find.byKey(const Key('move-admin-target-salon-admin-sibling-1')),
          findsOneWidget,
          reason:
              'the destination picker must show a REAL, LOADED sibling '
              'salon — a present-but-broken (error) or present-but-empty '
              'screen would also pass the bare "screen opened" assertion '
              'above',
        );
        expect(
          find.byKey(const Key('move-admin-empty')),
          findsNothing,
          reason:
              'the seeded sibling list is non-empty — this key must '
              'never render here',
        );

        // NOT driving the rotate PATCH to completion: no
        // `DELETE`/`PATCH .../admins/{userId}[/salon]` route is registered
        // for `salon-admin-1` (only `salon-xyz`'s does — see
        // `_wireAdminManagement`'s own doc), and the write itself is a
        // separate concern from the "the picker is reachable AND usable"
        // capability this task restores. Building that plumbing here would
        // duplicate `salon_staff_settings_flow_test.dart`'s own rotate-PATCH
        // coverage against `salon-xyz`/`admin-zzz` for no new signal.
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-back-move-admin')),
        );
        await AppHarness.settle(tester);
        expect(find.byType(StaffSettingsScreen), findsOneWidget);

        await tester.tap(convertRow);
        await AppHarness.settle(tester);
        expect(
          find.byType(MoveAdminSalonScreen),
          findsNothing,
          reason:
              'row-admin-convert-to-master is disabled — a tap must not '
              'navigate anywhere',
        );
        expect(find.byType(StaffSettingsScreen), findsOneWidget);

        // Still parked on the settings page — no guard bounced the viewer
        // away, which would be a different (and differently visible) way to
        // fail this test.
        expect(
          AppHarness.location(router),
          equals('/salons/$_kSalonId/manage/staff/$_kCoAdminId/settings'),
        );
      });
    },
  );

  testWidgets(
    'POSITIVE CONTROL — the same co-admin\'s settings page DOES show a live '
    'remove row for a genuine SALON_OWNER of that salon',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedAdminSalonIntoMySalons(fb);

        await _openCoAdminSettingsAs(tester, fb, UserRole.salonOwner);

        expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);
        expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
        expect(find.byKey(const Key('admin-settings-divider')), findsOneWidget);

        // Prove the row is genuinely LIVE, not present-but-dead: tapping it
        // must open the real confirmation dialog. Not confirmed any further
        // — the DELETE round trip itself is already E2E-pinned against
        // `salon-xyz`/`admin-zzz` in `salon_staff_settings_flow_test.dart`
        // ITEM 1, and `salon-admin-1` has no DELETE handler wired (this
        // fixture exists to prove the row RENDERS, not to re-prove the write
        // a sibling file already covers).
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-admin-remove')),
        );
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('remove-admin-dialog')), findsOneWidget);
      });
    },
  );

  testWidgets(
    'Phase 371 — SALON_ADMIN on the OWNER\'s row: roster card -> profile shows '
    'the read-only notice and neither management card; settings shows the '
    'notice with no tiles and no remove row',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = _adminWithOwnerRow();
        final GoRouter router = await _bootAdminSession(tester, fb);

        // Real UI path: «Команда» tile -> the owner's roster card.
        final Finder teamTile = find.byKey(const Key('salon-nav-tile-2'));
        await AppHarness.pumpUntilFound(
          tester,
          teamTile.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(teamTile);
        await AppHarness.settle(tester);
        final Finder ownerCard = find.byKey(
          const Key('salon-manage-staff-card-$_kOwnerRowUserId'),
        );
        await AppHarness.revealRosterCard(tester, ownerCard);
        await AppHarness.tapVisible(tester, ownerCard);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        // Positive: the notice. Negatives are guarded by it (M14).
        final Finder profileNotice = find.byKey(
          const Key('salon-staff-profile-owner-row-read-only'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          profileNotice,
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.byKey(const Key('salon-staff-profile-schedule-row')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-staff-profile-services-row')),
          findsNothing,
        );

        // Settings (deep link — the profile button's own target).
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffSettings(_kSalonId, _kOwnerRowUserId),
          find.byKey(const Key('staff-settings-owner-row-read-only')),
        );
        expect(find.byType(StaffSettingsScreen), findsOneWidget);
        expect(find.byKey(const Key('row-master-services')), findsNothing);
        expect(find.byKey(const Key('row-master-schedule')), findsNothing);
        expect(find.byKey(const Key('row-master-remove')), findsNothing);
        expect(
          find.byKey(const Key('staff-settings-master-owner-only')),
          findsNothing,
        );
      });
    },
  );

  testWidgets(
    'Phase 371 / 377 §1 — SALON_ADMIN deep links on the OWNER\'s row are '
    'read-only: schedule (no editor entry), services list (no FAB, no edit), '
    'edit (no delete), setup redirects to the read-only list; a normal '
    'master\'s list stays writable (control)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = _adminWithOwnerRow();
        final GoRouter router = await _bootAdminSession(tester, fb);

        // ── schedule: loaded template, no edit affordance ───────────────
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffSchedule(_kSalonId, _kOwnerRowUserId),
          find.byType(MasterScheduleScreen),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byWidgetPredicate(
            (Widget w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'schedule-weekly-pills-',
                ),
          ),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byKey(const Key('schedule-weekly-card')), findsNothing);
        expect(find.byKey(const Key('schedule-day-pencil')), findsNothing);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsNothing);
        expect(find.byKey(const Key('schedule-retry')), findsNothing);

        // ── services list: card rendered, no FAB, no edit entry ─────────
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffServices(_kSalonId, _kOwnerRowUserId),
          find.byType(ServicesListScreen),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.ownRowServicesGetCalls >= 1,
          description: 'the owner-row services GET',
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('services_count_header')),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('btn-create-service')), findsNothing);
        expect(
          tester
              .widget<ServicesListScreen>(find.byType(ServicesListScreen))
              .writable,
          isFalse,
        );
        // The widget flag alone is a configured value, not behaviour: tap the
        // real card and prove it does NOT open the edit screen.
        final Finder ownerCard = find.byKey(
          const Key('service_card_$_kOwnerRowAssignId'),
        );
        if (ownerCard.evaluate().isEmpty) {
          await AppHarness.tapVisible(
            tester,
            find.byKey(const Key('category_section_NAILS')),
          );
          await AppHarness.settle(tester);
        }
        await AppHarness.pumpUntilFound(
          tester,
          ownerCard.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(ownerCard);
        await AppHarness.settle(tester);
        expect(find.byType(ServiceEditScreen), findsNothing);
        expect(find.byType(ServicesListScreen), findsOneWidget);

        // ── edit: form shown, delete hidden ─────────────────────────────
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffServiceEdit(
            _kSalonId,
            _kOwnerRowUserId,
            _kOwnerRowAssignId,
          ),
          find.byKey(const Key('service-edit-form-$_kOwnerRowAssignId')),
        );
        expect(find.byType(ServiceEditScreen), findsOneWidget);
        expect(find.byKey(const Key('btn-delete-service')), findsNothing);
        expect(
          tester
              .widget<ServiceEditScreen>(find.byType(ServiceEditScreen))
              .writable,
          isFalse,
        );

        // ── setup: lands on the read-only list, never the form ──────────
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffServiceSetup(_kSalonId, _kOwnerRowUserId),
          find.byType(ServicesListScreen),
        );
        expect(find.byType(ServiceSetupScreen), findsNothing);
        expect(
          find.byKey(const Key('salon_manage_service_setup_redirect')),
          findsNothing,
        );
        expect(
          tester
              .widget<ServicesListScreen>(find.byType(ServicesListScreen))
              .writable,
          isFalse,
        );
        expect(find.byKey(const Key('btn-create-service')), findsNothing);
        expect(fb.ownRowBulkCreateCalls, 0);

        // ── CONTROL: same admin, a NORMAL master -> writable FAB ────────
        await _goAndSettle(
          tester,
          router,
          RouteNames.salonManageStaffServices(
            _kSalonId,
            'user-master-under-admin',
          ),
          find.byKey(const Key('btn-create-service')),
        );
        expect(
          tester
              .widget<ServicesListScreen>(find.byType(ServicesListScreen))
              .writable,
          isTrue,
        );
      });
    },
  );
}
