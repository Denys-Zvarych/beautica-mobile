// E2E — service-create 409 DUPLICATE_SERVICE surfaces INLINE, never the generic
// errServer snackbar, and the form stays put (Step 2.7 Rule 3b end-to-end
// coverage for the DUPLICATE_SERVICE catalogue fix).
//
// THE BUG THIS GUARDS
// -------------------
// Adding a service that is already in the master's menu returned a backend 409
// with the typed `{ data: { code: "DUPLICATE_SERVICE", … } }` envelope. Before
// the fix that fell through to the generic `errServer` "server error, try again"
// snackbar — the master could only re-tap Save and re-hit the same 409 forever.
// After the fix the repository decodes the envelope into [ServiceDuplicateFailure]
// and the form flags the `error-service-type` row with the localized
// `serviceErrDuplicate` copy, leaving the form on-screen so the master can pick a
// different service type instead of being stuck.
//
// Journey (INDEPENDENT_MASTER):
//   1. Login → /master/profile.
//   2. Navigate to /services/create.
//   3. Fill the form (name + duration + FIXED price + NAILS category + a NAILS
//      service type) so the client-side guards pass and the payload reaches the
//      network.
//   4. Arm the fake backend to reject the create POST with the 409
//      DUPLICATE_SERVICE envelope.
//   5. Tap Save → the create POST fires → the localized duplicate copy renders
//      INLINE on the service-type row; the generic errServer snackbar is NOT
//      shown; the route stays on /services/create (no pop / no infinite retry).
//
// This exercises the REAL HTTP path: in the harness `dioProvider` is the
// FakeBackend's Dio, so `HttpServiceRepository.create` hits the fake 409 and its
// `_mapServiceWriteException` decode runs through the real ErrorMapperInterceptor
// (which attaches a generic ServerFailure(409)) — proving the typed decode wins
// over the interceptor's fallthrough end-to-end, not just in the unit mock.
//
// KEY POLICY
// ----------
// All navigation/interaction finders are key-based (app_harness.dart policy).
// Content assertions read the localized copy off a live context (locale-
// invariant), never a hardcoded Cyrillic literal (i18n-finder gate compliant).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  Future<void> pumpFor(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      // fixed-wait-ok: the ServiceCreateScreen holds a never-settling category
      // loading animation (pumpAndSettle hangs); no single stable pump-until
      // target spans this helper's call sites — advance bounded fixed frames.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'a create 409 DUPLICATE_SERVICE shows the duplicate error INLINE on the '
    'service-type row, keeps the form open, and never shows errServer',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Navigate straight to the create form (skips the /services list, whose
      // loading skeleton runs an infinite shimmer that stalls pumpAndSettle).
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      router.go(RouteNames.serviceCreate);
      await pumpFor(tester, frames: 20);
      AppHarness.expectLocation(router, RouteNames.serviceCreate);

      // ── Fill the form (FIXED pricing) ────────────────────────────────────
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр тест',
      );
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '60',
      );
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('pricing-fixed-amount')),
          matching: find.byType(TextField),
        ),
        '400',
      );
      await tester.pump();

      // Select the NAILS category (opens a bottom sheet).
      final Finder categoryField = find.byKey(
        const Key('select-category-field'),
      );
      await tester.ensureVisible(categoryField);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(categoryField);
      await pumpFor(tester, frames: 6);
      final Finder nailsChip = find.byKey(const Key('chip-category-NAILS'));
      expect(nailsChip, findsOneWidget);
      await tester.tap(nailsChip);
      await pumpFor(tester, frames: 6);

      // Select a NAILS service type (mandatory on create).
      final Finder serviceTypeField = find.byKey(
        const Key('select-service-type-field'),
      );
      await tester.ensureVisible(serviceTypeField);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(serviceTypeField);
      await pumpFor(tester, frames: 6);
      final Finder classicTypeChip = find.byKey(
        const Key('chip-service-type-type-nails-classic'),
      );
      expect(classicTypeChip, findsOneWidget);
      await tester.tap(classicTypeChip);
      await pumpFor(tester, frames: 6);

      // Arm the backend to reject the create with the 409 DUPLICATE_SERVICE
      // envelope.
      fb.createRejectDuplicate = true;

      // Save → create POST → 409 → inline service-type error (no pop).
      final Finder submitBtn = find.byKey(const Key('btn-submit-service'));
      await tester.ensureVisible(submitBtn);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(submitBtn);
      await pumpFor(tester, frames: 20);

      // The create genuinely reached the network (not blocked client-side).
      expect(
        fb.createServiceCalls,
        greaterThanOrEqualTo(1),
        reason: 'the valid payload must POST to the create endpoint',
      );

      // The form did NOT pop — the master stays on the create screen so they can
      // correct the choice (the anti-"stuck re-hitting the same 409" guarantee).
      AppHarness.expectLocation(router, RouteNames.serviceCreate);

      // Read localized copy off a live context (locale-invariant).
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('btn-submit-service'))),
      );

      // The duplicate error is rendered INLINE on the service-type row.
      expect(
        find.descendant(
          of: find.byKey(const Key('error-service-type')),
          matching: find.text(l10n.serviceErrDuplicate),
        ),
        findsOneWidget,
        reason:
            'the 409 DUPLICATE_SERVICE must surface as the localized duplicate '
            'copy inline on the service-type row',
      );

      // The generic errServer copy / snackbar must NOT fire — the whole point of
      // the fix.
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'a duplicate 409 must NOT fall through to a snackbar',
      );
      expect(
        find.text(l10n.errServer),
        findsNothing,
        reason: 'the generic "server error, try again" copy must never show',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
