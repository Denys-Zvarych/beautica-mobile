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
// WHAT THIS COVERS (and what it does NOT)
// ---------------------------------------
// This exercises the real repository + HTTP path: in the harness `dioProvider`
// is the FakeBackend's Dio, so `HttpServiceRepository.create` issues a real
// request, gets the fake 409 back as a `DioException`, and its
// `_mapServiceWriteException` decodes the typed envelope off the RAW response
// body — end-to-end through the screen, notifier and form, not a unit mock.
//
// It does NOT cover the interceptor chain. FakeBackend's Dio installs no
// interceptors at all (only a `DioAdapter` — see fake_backend.dart), so the
// production `ErrorMapperInterceptor` never runs here and no generic
// `ServerFailure(409)` is ever attached to the exception. The precedence
// property — that the typed duplicate decode wins over the interceptor's
// generic fallthrough, which holds because `_isDuplicateService` inspects the
// raw body BEFORE the `e.error is Failure` check — is covered only by the
// repository unit tests, not by this flow.
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
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

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
      await tester.pumpUntilFound(find.byKey(const Key('field-service-name')));
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
      await tester.tap(categoryField);
      final Finder nailsChip = find.byKey(const Key('chip-category-NAILS'));
      // `.hitTestable()` — NOT bare existence. A `showModalBottomSheet` route
      // mounts its whole subtree on frame 1 and THEN slides it up over ~300 ms,
      // so a bare `pumpUntilFound` returns while the chip is still off the
      // bottom of the 800×600 flutter-tester view. Tapping it there aims at a
      // point outside the root render tree, which `hitTestWarningShouldBeFatal`
      // (armed in AppHarness.boot) turns into a hard "would not hit test"
      // failure. Waiting for hit-testability waits out the entrance animation
      // by OBSERVING it rather than guessing a pump count.
      await tester.pumpUntilFound(nailsChip.hitTestable());
      expect(nailsChip, findsOneWidget);
      await tester.tap(nailsChip);

      // Selecting the category pops the sheet and reveals the (category-scoped)
      // service-type selector. Wait for the category sheet to be genuinely GONE
      // (its own chip unmounted ⇒ route disposed ⇒ modal barrier gone) before
      // touching the form underneath: a tap that lands on a still-mounted
      // barrier is SWALLOWED silently (a barrier hit IS a legitimate hit, so
      // the `hitTestWarningShouldBeFatal` guard armed in AppHarness.boot says
      // nothing about it). `service_crud_flow_test.dart` covers the same window
      // with a hard-coded `6 × 100 ms` loop; this is that wait, OBSERVED rather
      // than guessed (`scripts/forbid_fixed_wait.sh`).
      final Finder serviceTypeField = find.byKey(
        const Key('select-service-type-field'),
      );
      await tester.pumpUntilFound(serviceTypeField);
      await tester.pumpUntilGone(nailsChip);

      // ── Select a NAILS service type (mandatory on create) ────────────────
      //
      // THE FLAKE THIS GUARDS — DO NOT REMOVE THE "PICKER IS READY" WAIT
      // ---------------------------------------------------------------------
      // This flow was red roughly 1 run in 4 with «Found 0 widgets with key
      // chip-service-type-type-nails-classic», and the obvious reading — "the
      // picker sheet never opened" — is WRONG. Instrumented at the point of
      // failure, the sheet WAS open (2 `ModalBarrier`s), the fake backend HAD
      // served the type list exactly once for the right category
      // (`getServiceTypesCalls == 1`, `lastServiceTypesCategory == 'NAILS'`),
      // and `serviceTypesProvider('NAILS')` was already `AsyncData` holding
      // BOTH options. The sheet was nevertheless still rendering its spinner
      // with zero option rows.
      //
      // Cause: `_ServiceTypeDropdown.build` (service_form.dart) resolves
      // `options` + `fieldState` from `ref.watch(serviceTypesProvider(...))`
      // and passes them as PLAIN VALUES into `SearchableSelectField`, which
      // hands them to a `showModalBottomSheet` route. That route's content is
      // built once, from whatever was captured when the menu opened — a later
      // provider resolution rebuilds the FORM, not the already-pushed sheet. So
      // opening the picker during the (usually sub-frame, occasionally slower)
      // load window yields a sheet that is stuck on its loading state FOREVER,
      // with no way out but closing and reopening it.
      //
      // That stale-sheet behaviour is a genuine product defect and is reported
      // separately; it is NOT this flow's subject (the 409 duplicate mapping),
      // and papering over it with a retry-tap would hide it. Instead the flow
      // does what a user does: waits for the field to stop showing its loading
      // affordance before opening the picker. The closed field's trailing slot
      // renders a `CircularProgressIndicator` while `SelectFieldState.loading`
      // and `Icons.keyboard_arrow_down_rounded` once idle
      // (`searchable_select_field.dart` `_TrailingAffordance`), so that icon
      // appearing IS "the type list has loaded and the picker will open
      // populated". Waiting on the READY state — not on a pump count — is what
      // makes this deterministic.
      await tester.ensureVisible(serviceTypeField);
      await tester.pumpUntilFound(serviceTypeField.hitTestable());
      await tester.pumpUntilFound(
        find.descendant(
          of: serviceTypeField,
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
        ),
      );
      await tester.tap(serviceTypeField);
      final Finder classicTypeChip = find.byKey(
        const Key('chip-service-type-type-nails-classic'),
      );
      await tester.pumpUntilFound(classicTypeChip.hitTestable());
      expect(classicTypeChip, findsOneWidget);
      await tester.tap(classicTypeChip);
      // Sheet fully dismissed (barrier gone) before touching the form again —
      // otherwise the submit tap below is swallowed the same way.
      await tester.pumpUntilGone(classicTypeChip);

      // Arm the backend to reject the create with the 409 DUPLICATE_SERVICE
      // envelope.
      fb.createRejectDuplicate = true;

      // Save → create POST → 409 → inline service-type error (no pop).
      final Finder submitBtn = find.byKey(const Key('btn-submit-service'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpUntilFound(submitBtn.hitTestable());

      // Read localized copy off a live context (locale-invariant) before the
      // tap rebuilds the row.
      final l10n = AppLocalizations.of(tester.element(submitBtn));

      await tester.tap(submitBtn);

      // DIAGNOSE AT THE CAUSE — assert the POST fired BEFORE waiting for the
      // inline copy. Everything upstream of the network (a swallowed picker
      // tap, an unselected service type, a client-side guard bailing) shows up
      // identically at the inline-copy finder: "the duplicate error never
      // rendered", which reads as a bug in the ERROR-MAPPING code under test
      // when it is really a bug in the JOURNEY. Checking the counter first
      // splits those two failure modes apart.
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.createServiceCalls >= 1,
        description:
            'the create POST to reach the fake backend — if it never does, the '
            'form was blocked CLIENT-SIDE (most likely the service type was '
            'never actually selected because a picker tap was swallowed by a '
            "closing bottom sheet's modal barrier), so the 409 mapping under "
            'test was never exercised at all',
      );

      // Wait for the inline duplicate error to render on the service-type row.
      // pump-until (not a fixed wait): the create screen's category shimmer
      // never settles, so pumpAndSettle can't be used here.
      final Finder inlineDuplicate = find.descendant(
        of: find.byKey(const Key('error-service-type')),
        matching: find.text(l10n.serviceErrDuplicate),
      );
      await tester.pumpUntilFound(inlineDuplicate);

      // The form did NOT pop — the master stays on the create screen so they can
      // correct the choice (the anti-"stuck re-hitting the same 409" guarantee).
      AppHarness.expectLocation(router, RouteNames.serviceCreate);

      // The duplicate error is rendered INLINE on the service-type row.
      expect(
        inlineDuplicate,
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
