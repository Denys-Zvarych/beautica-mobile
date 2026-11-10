// E2E — phase 471: «+ ще раз» adds a second copy row of one service type to
// the SAME add-services save (acceptance 1, 2, 4).
//
// FIXTURE
// -------
// The shared fake backend seeds the master with `type-nails-classic` at 60
// min (owned durations {60}), so switching that row on seeds 90; «+ ще раз»
// then seeds the copy at the nearest free quick-pick above 90 → 120.
//
// ARMS
// ----
//   C1 (acceptance 1). «+ ще раз» → a copy row at a free duration with an
//       empty price and the name field → price it → save → ONE bulk POST with
//       two items of the type, the copy without a `name` key (blank name).
//   C2 (acceptance 2). The copy moved onto the primary's duration with a
//       blank name → inline `serviceSetupCopyCollision`, CTA disabled, nothing
//       sent; typing a name clears it → the POST carries that name.
//   C3 (acceptance 4). «Прибрати» on the copy → the POST has one item.
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
import 'support/app_harness.dart';

const String _typeId = 'type-nails-classic';
const String _copyKeyId = '${_typeId}_copy_1';

Finder _row(String keyId) => find.byKey(Key('setup_row_$keyId'));

Finder _inRow(String keyId, Key key) =>
    find.descendant(of: _row(keyId), matching: find.byKey(key));

Finder _durationOf(String keyId) =>
    _inRow(keyId, const Key('service-setup-duration'));

Finder _priceOf(String keyId) =>
    _inRow(keyId, const Key('pricing-fixed-amount'));

Finder _nameOf(String keyId) => find.descendant(
  of: find.byKey(Key('setup_row_name_$keyId')),
  matching: find.byType(EditableText),
);

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(
        of: field,
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    )
    .controller
    .text;

VoidCallback? _saveCallback(WidgetTester tester) => tester
    .widget<NeumorphicButton>(find.byKey(const Key('btn-setup-save')))
    .onPressed;

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpUntilFound(target.hitTestable());
  await tester.tap(target);
}

/// Login → /services → FAB → setup (APPEND) → NAILS → owned row ON + priced →
/// «+ ще раз». Returns the live l10n.
Future<AppLocalizations> _openWithCopyRow(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  AppHarness.expectLocation(router, RouteNames.masterProfile);

  router.go(RouteNames.services);
  final Finder fab = find.byKey(const Key('btn-create-service'));
  await tester.pumpUntilFound(fab.hitTestable());
  await tester.tap(fab);
  final Finder closeBtn = find.byKey(const Key('btn-setup-close'));
  await tester.pumpUntilFound(closeBtn);
  final AppLocalizations l10n = AppLocalizations.of(tester.element(closeBtn));

  final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
  await tester.pumpUntilFound(nailsChip.hitTestable());
  await tester.tap(nailsChip);
  await tester.pumpUntilFound(_row(_typeId));

  await _tap(tester, find.byKey(const Key('setup_row_toggle_$_typeId')));
  await tester.pumpUntilFound(_priceOf(_typeId));
  await tester.enterText(_priceOf(_typeId), '650');
  await tester.pump();
  expect(_text(tester, _durationOf(_typeId)), '90');

  final Finder addCopy = find.byKey(
    const Key('btn-setup-row-add-copy-$_typeId'),
  );
  await _tap(tester, addCopy);
  await tester.pumpUntilFound(_row(_copyKeyId));
  await tester.pumpUntilFound(_priceOf(_copyKeyId));
  return l10n;
}

Future<List<dynamic>> _saveAndCapture(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final Finder save = find.byKey(const Key('btn-setup-save'));
  await _tap(tester, save);
  await AppHarness.pumpUntilCondition(
    tester,
    () => fb.bulkCreateCalls >= 1,
    description: 'the bulk POST carrying the copy rows',
  );
  return fb.lastBulkItems!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'C1. «+ ще раз» adds a copy row at a free duration with an empty price and '
    'the name field; one save sends both items',
    (tester) async {
      final fb = FakeBackend();
      final l10n = await _openWithCopyRow(tester, fb);

      expect(
        _text(tester, _durationOf(_copyKeyId)),
        '120',
        reason: 'free of the owned 60 and the primary 90',
      );
      expect(_text(tester, _priceOf(_copyKeyId)), isEmpty);
      expect(_nameOf(_copyKeyId), findsOneWidget);
      expect(
        find.descendant(
          of: _row(_copyKeyId),
          matching: find.text(l10n.serviceSetupCopyNameHint),
        ),
        findsOneWidget,
      );

      await tester.enterText(_priceOf(_copyKeyId), '800');
      await tester.pump();
      final List<dynamic> items = await _saveAndCapture(tester, fb);

      expect(items, hasLength(2));
      final first = items[0] as Map<String, dynamic>;
      final second = items[1] as Map<String, dynamic>;
      expect(first['serviceTypeId'], _typeId);
      expect(first['durationMinutes'], 90);
      expect(second['serviceTypeId'], _typeId);
      expect(second['durationMinutes'], 120);
      expect(second['price'], 800);
      expect(
        second.containsKey('name'),
        isFalse,
        reason: 'a blank name is not sent — the copy keeps the type name',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'C2. a blank-name copy at the primary duration collides (CTA disabled, '
    'nothing sent); a name clears it and is sent',
    (tester) async {
      final fb = FakeBackend();
      final l10n = await _openWithCopyRow(tester, fb);

      await tester.enterText(_priceOf(_copyKeyId), '800');
      await tester.pump();
      await tester.enterText(_durationOf(_copyKeyId), '90');
      await tester.pump();

      final Finder collision = find.descendant(
        of: _row(_copyKeyId),
        matching: find.text(l10n.serviceSetupCopyCollision),
      );
      expect(collision, findsOneWidget);
      expect(_saveCallback(tester), isNull);
      final Finder save = find.byKey(const Key('btn-setup-save'));
      await tester.ensureVisible(save);
      await tester.tap(save, warnIfMissed: false);
      // A disabled CTA tap has no positive signal to poll for.
      await AppHarness.settle(tester);
      expect(fb.bulkCreateCalls, 0);

      await tester.ensureVisible(_nameOf(_copyKeyId));
      await tester.enterText(_nameOf(_copyKeyId), 'Френч авторський');
      await tester.pump();
      expect(collision, findsNothing);
      expect(_saveCallback(tester), isNotNull);

      final List<dynamic> items = await _saveAndCapture(tester, fb);
      expect(items, hasLength(2));
      final second = items[1] as Map<String, dynamic>;
      expect(second['durationMinutes'], 90);
      expect(second['name'], 'Френч авторський');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'C3. «Прибрати» removes the copy row; the save sends one item',
    (tester) async {
      final fb = FakeBackend();
      await _openWithCopyRow(tester, fb);

      await _tap(
        tester,
        find.byKey(const Key('btn-setup-row-remove-$_copyKeyId')),
      );
      await tester.pumpUntilGone(_row(_copyKeyId));
      expect(
        find.byKey(const Key('setup_row_name_$_typeId')),
        findsNothing,
        reason: 'a single row of the type drops back to the pre-471 row',
      );

      final List<dynamic> items = await _saveAndCapture(tester, fb);
      expect(items, hasLength(1));
      expect((items.single as Map<String, dynamic>)['durationMinutes'], 90);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
