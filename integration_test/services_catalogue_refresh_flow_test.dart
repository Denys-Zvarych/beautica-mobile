// fix/services-catalogue-refresh — E2E (Step 2.7 Rule 3b): a category an admin
// approves mid-session reaches «Мої послуги» and the add-service picker WITHOUT
// an app restart.
//
// THE BUG
// -------
// `approvedCategoriesProvider` is a root-scoped keepAlive cache. It was
// re-fetched only on a 5-minute throttle from the services list, and never on
// setup / edit open — so a freshly approved category stayed invisible until a
// cold restart.
//
// JOURNEY (INDEPENDENT_MASTER, real HTTP path through FakeBackend)
// ---------------------------------------------------------------
//   1. Login → «Мої послуги». The seeded `assign-2` service is in category
//      `FACE`, which the backend does NOT list as approved yet, so its section
//      header renders the humanized slug fallback.
//   2. The backend starts listing FACE as approved (admin approval simulated by
//      appending to `fb.approvedCategories`). Nothing re-fetches on its own —
//      asserted, so the pull below is the thing that moves the label.
//   3. Pull-to-refresh → the section header shows FACE's display name.
//   4. The backend approves a SECOND category (LASHES).
//      a. Open add-service inside the 30 s floor → NO re-fetch, LASHES absent
//         (proves the clock seam is what gates step b, not chance).
//      b. Close, advance the injected clock 31 s, open add-service again →
//         the setup-open refresh fetches, the LASHES chip appears, and tapping
//         it expands its group (selectable).
//
// WHY A SECOND CATEGORY IN STEP 4
// -------------------------------
// The pull in step 3 already re-fetched the keepAlive cache, so FACE would show
// on the picker even if the setup-open refresh were deleted. LASHES is approved
// AFTER the pull, so only the setup-open refresh can surface it — the flow is
// red without it (mutation-verified: comment out the post-frame
// `refreshCategoryCataloguesIfOlderThan` in `service_setup_screen.dart`).
//
// CLOCK
// -----
// One clock: the harness's injected `clockProvider`, driven through
// `AppHarness.boot(clock:)` from a mutable instant anchored on `kFixedNow`.
// No host-clock reads (playbook M15).
//
// KEY POLICY
// ----------
// Finders are key-based. The two category labels are FIXTURE DATA served by the
// fake backend, not localized UI copy, so they are matched by value via
// constants (no Cyrillic finder literal — `forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// Display names served by the fake backend once each category is approved.
const String _faceLabel = 'Обличчя';
const String _lashesLabel = 'Вії';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a category approved mid-session appears on «Мої послуги» after a pull, '
    'and in the add-service picker once the 30 s open floor has passed',
    (tester) async {
      DateTime now = kFixedNow;
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        clock: () => now,
      );
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── 1. «Мої послуги», FACE not yet approved ─────────────────────────
      router.go(RouteNames.services);
      final Finder faceSection = find.byKey(const Key('category_section_FACE'));
      await tester.pumpUntilFound(faceSection);
      final Finder faceTitle = find.descendant(
        of: faceSection,
        matching: find.text(_faceLabel),
      );
      expect(faceTitle, findsNothing, reason: 'FACE is not approved yet');

      // ── 2. Admin approves FACE; nothing refreshes on its own ─────────────
      fb.approvedCategories.add(<String, dynamic>{
        'name': 'FACE',
        'displayName': _faceLabel,
      });
      final int callsBeforePull = fb.getApprovedCategoriesCalls;
      await tester.pumpAndSettle();
      expect(
        faceTitle,
        findsNothing,
        reason:
            'no refresh path fired yet — if FACE shows here, the pull below '
            'proves nothing',
      );

      // ── 3. Pull-to-refresh surfaces it ───────────────────────────────────
      await tester.fling(
        find.byKey(const Key('services-list-scroll')),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpUntilFound(faceTitle);
      expect(faceTitle, findsOneWidget);
      expect(
        fb.getApprovedCategoriesCalls,
        greaterThan(callsBeforePull),
        reason: 'the pull must re-fetch the approved categories',
      );
      await tester.pumpUntilGone(find.byType(RefreshProgressIndicator));

      // ── 4. Admin approves LASHES after the pull ──────────────────────────
      fb.approvedCategories.add(<String, dynamic>{
        'name': 'LASHES',
        'displayName': _lashesLabel,
      });
      final Finder fab = find.byKey(const Key('btn-create-service'));
      final Finder closeBtn = find.byKey(const Key('btn-setup-close'));
      final Finder lashesChip = find.byKey(
        const ValueKey<String>('cat_LASHES'),
      );
      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));

      // 4a. Inside the 30 s floor: no re-fetch, so LASHES is not offered.
      final int callsBeforeFloorOpen = fb.getApprovedCategoriesCalls;
      await tester.pumpUntilFound(fab.hitTestable());
      await tester.tap(fab);
      await tester.pumpUntilFound(nailsChip.hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('cat_FACE')),
        findsOneWidget,
        reason: 'the picker reads the cache the pull refreshed',
      );
      expect(
        fb.getApprovedCategoriesCalls,
        callsBeforeFloorOpen,
        reason: 'opening setup inside the 30 s floor must not re-fetch',
      );
      expect(lashesChip, findsNothing);

      await tester.tap(closeBtn);
      await tester.pumpUntilFound(fab.hitTestable());
      await tester.pumpAndSettle();

      // 4b. Past the floor: the setup-open refresh fetches LASHES.
      now = kFixedNow.add(const Duration(seconds: 31));
      final int callsBeforeLateOpen = fb.getApprovedCategoriesCalls;
      await tester.tap(fab);
      await tester.pumpUntilFound(closeBtn);
      await tester.pumpUntilFound(lashesChip.hitTestable());
      expect(
        fb.getApprovedCategoriesCalls,
        callsBeforeLateOpen + 1,
        reason: 'setup open past the floor re-fetches exactly once',
      );

      // Selectable: tapping the chip expands its group.
      await tester.tap(lashesChip);
      await tester.pumpUntilFound(
        find.byKey(const ValueKey<String>('group_LASHES')),
      );
      expect(tester.widget<CategoryChip>(lashesChip).selected, isTrue);
      expect(tester.widget<CategoryChip>(lashesChip).label, _lashesLabel);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
