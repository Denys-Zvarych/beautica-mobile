// E2E — phase 468: a master adds a service type they ALREADY offer again, as a
// COPY at a different duration (Step 2.7 Rule 3b, acceptance 1–3).
//
// WHY THIS FLOW EXISTS
// --------------------
// Backend 464/465 relaxed the uniqueness rule: a master may hold one service
// type more than once, provided every active copy differs in duration OR name.
// Phase 468 opened the add-services row for an owned type (it used to be
// inert) and taught the edit form's 409 to point at name + duration. Nothing at
// the E2E tier drove an owned row ON before this file — `service_append_flow`
// only asserts the owned row now HAS a switch, and saves the NON-owned sibling.
//
// FIXTURE
// -------
// The fake backend seeds the master with two copies of `type-nails-classic`
// (`assign-typed` / `assign-mismatch`, both 60 min, both named after the type).
// That is the phase doc's «Класичний масаж 60» case on the type the shared
// fixture already owns: owned durations = {60}. Since phase 472 the owned row
// is NOT autofilled on toggle — its duration starts empty and the master types
// a free one (90 here).
//
// ARMS
// ----
//   A1. Owned row switched on → «Вже додано» + an EMPTY duration (phase 472,
//       no autofill) → typed 90, no error → save → the bulk POST carries the
//       second copy at 90.
//   A2. Owned row at the OWNED duration 60 → inline
//       `serviceSetupDurationTaken`, the CTA is disabled and a tap sends
//       nothing; moving back to a free duration clears it and re-enables save.
//   A3. Edit form: copy 2 renamed onto copy 1's name at the same duration →
//       server 409 DUPLICATE_SERVICE → `serviceErrDuplicateCopy` on BOTH the
//       name and duration fields; the screen stays. Editing the duration clears
//       the pair (the rule is "duration OR name").
//   A4. Phase 472 (B6) client pre-check, canonical name: the master also owns
//       a RENAMED copy «Авторський манікюр» at 90 (`seedOwnedNamedCopy`). A
//       new copy row named « авторський   МАНІКЮР » at 90 is now caught on the
//       client — the pre-check compares (duration, `serviceNameKey`) of every
//       owned copy, like backend 464 — so the row shows
//       `serviceSetupCopyCollision`, the CTA is disabled and nothing is sent;
//       a distinct name clears it and ONE bulk POST carries both rows.
//   A5. Server-only duplicate → post-409 reconcile end to end: after the
//       screen snapshots owned {60}, a type-name copy at 90 lands on the
//       server (`seedOwnedNamedCopy` after boot — the list GET is live). The
//       owned row at 90 + a gel row pass the client check, the bulk POST 409s
//       (`bulkRejectDuplicate`), and the reconcile switches off ONLY the
//       claimed row (emphasised «Вже додано»); the re-save sends the gel row.
//
// A3's 409 comes from the shared fake's `typedPatchRejectDuplicate` switch
// (PATCH `/api/v1/services/svc-typed` → the backend's typed DUPLICATE_SERVICE
// envelope), so the repository's `_mapServiceWriteException` decodes it exactly
// as in production. Off by default — other flows keep the 200.
//
// KEY POLICY: interaction finders are key-based; copy assertions read
// `AppLocalizations` off a live context, never a re-typed literal.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// Seeded twice in the master's catalogue at 60 min (see header).
const String _ownedTypeId = 'type-nails-classic';

class _SetupHandles {
  const _SetupHandles({
    required this.l10n,
    required this.row,
    required this.duration,
    required this.price,
    required this.save,
  });

  final AppLocalizations l10n;
  final Finder row;
  final Finder duration;
  final Finder price;
  final Finder save;
}

/// Login → /services → FAB → setup (APPEND) → NAILS → switch the OWNED row on.
Future<_SetupHandles> _openSetupAndIncludeOwnedRow(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  AppHarness.expectLocation(router, RouteNames.masterProfile);

  // Through the list, so `servicesListProvider` (the owned-durations source)
  // is warm when the setup screen's initState snapshots it.
  router.go(RouteNames.services);
  final Finder fab = find.byKey(const Key('btn-create-service'));
  await tester.pumpUntilFound(fab.hitTestable());
  await tester.tap(fab);
  final Finder closeBtn = find.byKey(const Key('btn-setup-close'));
  await tester.pumpUntilFound(closeBtn);
  final AppLocalizations l10n = AppLocalizations.of(tester.element(closeBtn));
  expect(
    find.text(l10n.serviceSetupTitleAppend),
    findsOneWidget,
    reason: 'APPEND framing proves the owned-durations snapshot was warm',
  );

  final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
  await tester.pumpUntilFound(nailsChip.hitTestable());
  await tester.tap(nailsChip);

  final Finder row = find.byKey(const Key('setup_row_$_ownedTypeId'));
  await tester.pumpUntilFound(row);
  expect(
    find.descendant(
      of: row,
      matching: find.text(l10n.serviceSetupRowAlreadyAdded),
    ),
    findsOneWidget,
    reason: 'precondition: this row is the OWNED type',
  );

  final Finder toggle = find.byKey(const Key('setup_row_toggle_$_ownedTypeId'));
  await tester.ensureVisible(toggle);
  await tester.pumpUntilFound(toggle.hitTestable());
  await tester.tap(toggle);

  final Finder duration = find.descendant(
    of: row,
    matching: find.byKey(const Key('service-setup-duration')),
  );
  final Finder price = find.descendant(
    of: row,
    matching: find.byKey(const Key('pricing-fixed-amount')),
  );
  await tester.pumpUntilFound(duration);
  await tester.pumpUntilFound(price);

  return _SetupHandles(
    l10n: l10n,
    row: row,
    duration: duration,
    price: price,
    save: find.byKey(const Key('btn-setup-save')),
  );
}

String _durationText(WidgetTester tester, Finder durationField) => tester
    .widget<EditableText>(
      find.descendant(of: durationField, matching: find.byType(EditableText)),
    )
    .controller
    .text;

VoidCallback? _saveCallback(WidgetTester tester, Finder save) =>
    tester.widget<NeumorphicButton>(save).onPressed;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'A1. an owned type switched on again starts with an EMPTY duration (phase '
    '472); a typed free 90 saves the second copy',
    (tester) async {
      final fb = FakeBackend();
      final h = await _openSetupAndIncludeOwnedRow(tester, fb);

      expect(
        _durationText(tester, h.duration),
        isEmpty,
        reason: 'phase 472: an owned row is not autofilled on reopen/toggle',
      );
      await tester.enterText(h.duration, '90');
      await tester.pump();
      expect(
        find.descendant(
          of: h.row,
          matching: find.text(h.l10n.serviceSetupDurationTaken),
        ),
        findsNothing,
        reason: 'a free duration carries no duplicate error',
      );

      await tester.enterText(h.price, '650');
      await tester.pump();

      await tester.pumpUntilFound(h.save.hitTestable());
      expect(_saveCallback(tester, h.save), isNotNull);
      await tester.tap(h.save);

      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description:
            'the bulk POST for the copy — if it never fires the owned row was '
            'blocked client-side (CTA disabled or row not included)',
      );
      final List<dynamic> items = fb.lastBulkItems!;
      expect(items, hasLength(1));
      final Map<String, dynamic> item = items.single as Map<String, dynamic>;
      expect(
        item['serviceTypeId'],
        _ownedTypeId,
        reason: 'phase 468: the OWNED type ships again, as a second copy',
      );
      expect(item['durationMinutes'], 90);
      expect(item['price'], 650);

      await tester.pumpUntilGone(find.byKey(const Key('btn-setup-close')));
      expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'A2. picking the owned duration shows serviceSetupDurationTaken, disables '
    'save and sends nothing; a free duration clears it',
    (tester) async {
      final fb = FakeBackend();
      final h = await _openSetupAndIncludeOwnedRow(tester, fb);

      await tester.enterText(h.price, '650');
      await tester.pump();
      // CONTROL: the CTA is live before the owned duration is chosen, so the
      // disabled assertion below is about the duration, not an unfilled row.
      expect(_saveCallback(tester, h.save), isNotNull);

      await tester.enterText(h.duration, '60');
      await tester.pump();

      expect(
        find.descendant(
          of: h.row,
          matching: find.text(h.l10n.serviceSetupDurationTaken),
        ),
        findsOneWidget,
        reason: '60 is an existing copy of this type — the inline error shows',
      );
      expect(
        _saveCallback(tester, h.save),
        isNull,
        reason: 'an exact duplicate must keep the CTA disabled',
      );
      await tester.ensureVisible(h.save);
      await tester.tap(h.save, warnIfMissed: false);
      // A disabled CTA tap has no positive signal to poll for (the assertion is
      // that NOTHING happens), so drain every frame/microtask instead.
      await AppHarness.settle(tester);
      expect(
        fb.bulkCreateCalls,
        0,
        reason: 'a known duplicate must never reach the network',
      );

      await tester.enterText(h.duration, '120');
      await tester.pump();
      expect(
        find.descendant(
          of: h.row,
          matching: find.text(h.l10n.serviceSetupDurationTaken),
        ),
        findsNothing,
      );
      expect(_saveCallback(tester, h.save), isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('A3. edit form: a 409 DUPLICATE_SERVICE on rename shows '
      'serviceErrDuplicateCopy on name AND duration, keeps the screen, and a '
      'duration edit clears both', (tester) async {
    final fb = FakeBackend()..typedPatchRejectDuplicate = true;

    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    router.go(RouteNames.serviceEdit('assign-typed'));

    final Finder submit = find.byKey(const Key('btn-submit-service'));
    await tester.pumpUntilFound(submit);
    final AppLocalizations l10n = AppLocalizations.of(tester.element(submit));

    Finder inputOf(Key wrapper) => find.descendant(
      of: find.byKey(wrapper),
      matching: find.byType(EditableText),
    );
    final Finder name = inputOf(const Key('field-service-name'));
    final Finder duration = inputOf(const Key('field-service-duration'));

    // Copy 2 takes copy 1's name (`assign-mismatch`'s definition name) at
    // copy 1's duration — the exact-duplicate pair the backend refuses.
    const String copyOneName = 'Класичний манікюр';
    await tester.ensureVisible(name);
    await tester.enterText(name, copyOneName);
    await tester.pump();
    await tester.ensureVisible(duration);
    await tester.enterText(duration, '60');
    await tester.pump();

    await tester.ensureVisible(submit);
    // ensureVisible jumps (zero duration); one frame lays out the scrolled CTA.
    await tester.pump();
    await tester.tap(submit);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.patchServiceCalls >= 1,
      description: 'the edit-form PATCH reaching the (409) network seam',
    );
    final Finder copyError = find.text(l10n.serviceErrDuplicateCopy);
    await tester.pumpUntilFound(copyError);

    expect(
      copyError,
      findsNWidgets(2),
      reason: 'the 409 flags exactly the two fields that resolve it',
    );
    final Finder durationError = find.descendant(
      of: find.byKey(const Key('pricing-field')),
      matching: copyError,
    );
    expect(durationError, findsOneWidget, reason: 'one sits on duration');
    expect(
      find.descendant(
        of: find.byKey(const Key('error-service-name')),
        matching: copyError,
        matchRoot: true,
      ),
      findsOneWidget,
      reason: 'the other copy belongs to the NAME field',
    );
    expect(find.text(l10n.errServer), findsNothing);
    expect(
      find.byKey(const Key('error-service-type')),
      findsNothing,
      reason: 'phase 468 moved the 409 off the service-type field',
    );
    AppHarness.expectLocation(router, '/services/assign-typed/edit');

    // Changing EITHER half resolves the rule, so one edit clears the pair.
    await tester.enterText(duration, '75');
    await tester.pump();
    expect(copyError, findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'A4. a copy whose name differs from an owned renamed copy only by space '
    'runs / case is blocked on the client (B6); a distinct name saves',
    (tester) async {
      const String copyId = '${_ownedTypeId}_copy_1';
      final fb = FakeBackend()
        ..seedOwnedNamedCopy(name: 'Авторський манікюр', durationMinutes: 90);
      final h = await _openSetupAndIncludeOwnedRow(tester, fb);
      await tester.enterText(h.price, '650');
      await tester.pump();
      // Phase 472: no autofill — the type-name primary needs a free duration
      // (owned {60, 90}).
      await tester.enterText(h.duration, '120');
      await tester.pump();

      final Finder addCopy = find.byKey(
        const Key('btn-setup-row-add-copy-$_ownedTypeId'),
      );
      await tester.ensureVisible(addCopy);
      await tester.pumpUntilFound(addCopy.hitTestable());
      await tester.tap(addCopy);
      final Finder copyRow = find.byKey(const Key('setup_row_$copyId'));
      await tester.pumpUntilFound(copyRow);

      Finder inCopy(Key key) =>
          find.descendant(of: copyRow, matching: find.byKey(key));
      final Finder copyName = find.descendant(
        of: find.byKey(const Key('setup_row_name_$copyId')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(copyName);
      await tester.enterText(copyName, ' авторський   МАНІКЮР ');
      await tester.pump();
      await tester.enterText(inCopy(const Key('service-setup-duration')), '90');
      await tester.pump();
      await tester.enterText(inCopy(const Key('pricing-fixed-amount')), '700');
      await tester.pump();

      // B6: the owned renamed copy's canonical name is known on the client.
      final Finder clash = find.descendant(
        of: copyRow,
        matching: find.text(h.l10n.serviceSetupCopyCollision),
      );
      await tester.pumpUntilFound(clash);
      await tester.ensureVisible(h.save);
      await tester.pump();
      expect(
        _saveCallback(tester, h.save),
        isNull,
        reason:
            'same type + duration + canonical name as the owned renamed copy '
            '— a client-known duplicate since phase 472',
      );
      await tester.tap(h.save, warnIfMissed: false);
      await tester.pump();
      expect(fb.bulkCreateCalls, 0, reason: 'a blocked save sends nothing');

      await tester.ensureVisible(copyName);
      await tester.enterText(copyName, 'Авторський манікюр 2');
      await tester.pump();
      await tester.pumpUntilGone(clash);
      await tester.ensureVisible(h.save);
      await tester.pumpUntilFound(h.save.hitTestable());
      expect(_saveCallback(tester, h.save), isNotNull);
      expect(find.text(h.l10n.serviceSetupCtaAdd(2)), findsOneWidget);
      await tester.tap(h.save);

      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the bulk POST carrying the primary and the named copy',
      );
      final List<dynamic> items = fb.lastBulkItems!;
      expect(items, hasLength(2));
      final Map<String, dynamic> sent = items
          .cast<Map<String, dynamic>>()
          .singleWhere((Map<String, dynamic> i) => i['name'] != null);
      expect(sent['durationMinutes'], 90);
      expect(sent['name'], 'Авторський манікюр 2');
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'A5. a server-only duplicate (added elsewhere after the screen opened) '
    'reaches the bulk 409; the reconcile switches off exactly that row and '
    'the re-save sends the rest',
    (tester) async {
      const String gelTypeId = 'type-nails-gel';
      final fb = FakeBackend();
      final h = await _openSetupAndIncludeOwnedRow(tester, fb);
      await tester.enterText(h.price, '650');
      await tester.enterText(h.duration, '90');
      await tester.pump();

      // A second, unrelated row rides the same save.
      final Finder gelRow = find.byKey(const Key('setup_row_$gelTypeId'));
      final Finder gelToggle = find.byKey(
        const Key('setup_row_toggle_$gelTypeId'),
      );
      // The row sits below the fold of the lazy list — scroll it in.
      await tester.scrollUntilVisible(
        gelToggle,
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpUntilFound(gelToggle.hitTestable());
      await tester.tap(gelToggle);
      Finder inGel(Key key) =>
          find.descendant(of: gelRow, matching: find.byKey(key));
      await tester.pumpUntilFound(inGel(const Key('pricing-fixed-amount')));
      await tester.enterText(inGel(const Key('service-setup-duration')), '60');
      await tester.enterText(inGel(const Key('pricing-fixed-amount')), '500');
      await tester.pump();

      // The client snapshot owns {60} only, so 90 passes the pre-check. The
      // clash exists only on the server: the same type-name copy at 90 lands
      // (another device) after the screen took its snapshot. The list GET
      // reads the fake's live catalogue, so the post-409 refresh sees it.
      expect(
        find.descendant(
          of: h.row,
          matching: find.text(h.l10n.serviceSetupDurationTaken),
        ),
        findsNothing,
        reason: 'precondition: the client cannot see this clash',
      );
      fb
        // i18n-finder-ok: fixture service name (user data), not l10n copy
        ..seedOwnedNamedCopy(name: 'Класичний манікюр', durationMinutes: 90)
        ..bulkRejectDuplicate = true;

      await tester.ensureVisible(h.save);
      await tester.pumpUntilFound(h.save.hitTestable());
      expect(find.text(h.l10n.serviceSetupCtaAdd(2)), findsOneWidget);
      await tester.tap(h.save);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the bulk POST reaching the (409) server backstop',
      );
      expect(fb.lastBulkItems, hasLength(2));

      // Reconcile: the claimed row collapses (switched off) and its owned
      // label turns emphasised — the alreadyInMenu flag.
      await tester.pumpUntilGone(h.duration);
      final Text label = tester.widget<Text>(
        find.descendant(
          of: h.row,
          matching: find.text(h.l10n.serviceSetupRowAlreadyAdded),
        ),
      );
      expect(label.style?.fontWeight, FontWeight.w800);
      expect(
        find.text(h.l10n.serviceSetupCtaAdd(1)),
        findsOneWidget,
        reason: 'only the server-claimed row was switched off',
      );
      expect(inGel(const Key('service-setup-duration')), findsOneWidget);
      expect(find.byKey(const Key('btn-setup-close')), findsOneWidget);

      fb.bulkRejectDuplicate = false;
      await pumpPastVelvetSnack(tester);
      await tester.ensureVisible(h.save);
      await tester.pumpUntilFound(h.save.hitTestable());
      await tester.tap(h.save);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 2,
        description: 'the re-save without the reconciled row',
      );
      final List<dynamic> items = fb.lastBulkItems!;
      expect(items, hasLength(1));
      expect(
        (items.single as Map<String, dynamic>)['serviceTypeId'],
        gelTypeId,
      );
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
