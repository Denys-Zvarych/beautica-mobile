// E2E — phase 469: the copy-name hint on the owner services list (Step 2.7
// Rule 3b, acceptance 1–2).
//
// WHY THIS FLOW EXISTS
// --------------------
// Phase 468 lets a master hold one service type more than once (copies that
// differ in duration or name). Two copies named after the type render two equal
// titles, so 469 computes a client-side hint per owner list
// (`serviceNameHints`) and the list passes it to each `ServiceCard`. The unit
// matrix pins the rule and the widget tests pin the card; this flow pins the
// WIRING — repository → list provider → `_LoadedBody` memo → card — and that
// the hints are recomputed after an edit re-fetches the list.
//
// FIXTURE
// -------
// The fake backend seeds two copies of `type-nails-classic` («Класичний
// манікюр», `assign-typed` / `assign-mismatch`, both 60 min). This flow moves
// `assign-mismatch` to 90 min (`setSeededServiceDuration`) for the phase doc's
// 60 + 90 pair, and arms `typedPatchPersists` so the edit form's
// `PATCH /services/svc-typed` rename is visible to the next list GET.
//
// KEY POLICY: card + hint finders are key-based; expected hint text is built
// from `AppLocalizations` + `DurationMinutes.format`, never a re-typed literal.
// The only text finder matches the fixture's custom service NAME (user data,
// not localised copy).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/widgets/name_with_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

const Key _hintKey = Key('service-name-hint');
const Key _copySixtyCard = Key('service_card_assign-typed');
const Key _copyNinetyCard = Key('service_card_assign-mismatch');

/// A custom name that no other seeded service carries.
const String _customName = 'Манікюр авторський';

Finder _hintIn(Key card) =>
    find.descendant(of: find.byKey(card), matching: find.byKey(_hintKey));

String _hintText(WidgetTester tester, Key card) =>
    tester.widget<Text>(_hintIn(card)).data ?? '';

/// /services → NAILS section expanded → both copy cards mounted.
Future<void> _openListWithBothCopies(
  WidgetTester tester,
  GoRouter router,
) async {
  router.go(RouteNames.services);
  final Finder nails = find.byKey(const Key('category_section_NAILS'));
  await AppHarness.pumpUntilFound(tester, nails);
  final Finder first = find.byKey(_copySixtyCard);
  if (first.evaluate().isEmpty) await AppHarness.tapVisible(tester, nails);
  await AppHarness.pumpUntilFound(tester, first);
  await AppHarness.pumpUntilFound(tester, find.byKey(_copyNinetyCard));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'A1. two same-named copies (60 + 90) each show their duration hint',
    (tester) async {
      final fb = FakeBackend()..setSeededServiceDuration('assign-mismatch', 90);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await _openListWithBothCopies(tester, router);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(_copySixtyCard)),
      );

      expect(
        _hintText(tester, _copySixtyCard),
        l10n.serviceNameHintSuffix(
          NameWithHint.isolate(DurationMinutes.format(60)),
        ),
      );
      expect(
        _hintText(tester, _copyNinetyCard),
        l10n.serviceNameHintSuffix(
          NameWithHint.isolate(DurationMinutes.format(90)),
        ),
      );
      expect(
        find.byKey(_hintKey),
        findsNWidgets(2),
        reason: 'uniquely-named services in the same list get no hint',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'A2. renaming one copy to a custom name drops its hint and leaves the '
    'sibling plain',
    (tester) async {
      final fb = FakeBackend()
        ..setSeededServiceDuration('assign-mismatch', 90)
        ..typedPatchPersists = true;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await _openListWithBothCopies(tester, router);
      // CONTROL: the pair starts hinted, so the absence below is caused by
      // the rename, not by a list that never hinted at all.
      expect(find.byKey(_hintKey), findsNWidgets(2));

      // Through the card (push), so the save pops back to this list.
      await AppHarness.tapVisible(tester, find.byKey(_copySixtyCard));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('service-edit-form-assign-typed')),
      );
      final Finder name = find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(name);
      await tester.enterText(name, _customName);
      await tester.pump();

      final Finder submit = find.byKey(const Key('btn-submit-service'));
      await tester.ensureVisible(submit);
      // ensureVisible jumps (zero duration); one frame lays out the CTA.
      await tester.pump();
      await tester.tap(submit);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.patchServiceCalls >= 1,
        description: 'the edit-form PATCH for the rename',
      );
      expect(fb.lastTypedPatchBody?['name'], _customName);

      // Positive signal first: the RE-FETCHED list shows the new name on the
      // renamed card. Asserting absence before this would pass on the
      // loading frame, when no card is mounted at all.
      final Finder renamed = find.descendant(
        of: find.byKey(_copySixtyCard),
        // i18n-finder-ok: fixture service name (user data), not l10n copy
        matching: find.text(_customName),
      );
      await AppHarness.pumpUntilFound(tester, renamed);
      AppHarness.expectLocation(router, RouteNames.services);
      await AppHarness.pumpUntilFound(tester, find.byKey(_copyNinetyCard));

      expect(
        _hintIn(_copySixtyCard),
        findsNothing,
        reason: 'a custom-named copy no longer shares a name — no hint',
      );
      expect(
        _hintIn(_copyNinetyCard),
        findsNothing,
        reason: 'the sibling is now the only one with its name — plain title',
      );
      expect(find.byKey(_hintKey), findsNothing);

      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
