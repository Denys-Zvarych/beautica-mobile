// E2E — phase 471: «+ додати ще» adds a second copy row of one service type
// to the SAME add-services save (acceptance 1, 2, 4); phase 472: the tap jumps
// to the new card (on screen, duration focused), and (decision D3) every
// switched-on card — owned or not, primary or copy — shows its name with a
// pencil that opens THAT card's name well; the name rides the bulk add.
//
// FIXTURE
// -------
// The shared fake backend seeds the master with `type-nails-classic` at 60
// min (owned durations {60}). Since phase 472 switching that row on leaves the
// duration EMPTY (no autofill), so the flow types 90; «+ додати ще» then seeds
// the copy at the nearest free quick-pick above 90 → 120.
//
// ARMS
// ----
//   C1 (acceptance 1). «+ додати ще» → a copy row at a free duration with an
//       empty price and a name pencil → price it → save → ONE bulk POST with
//       two items of the type, the copy without a `name` key (blank name).
//   C2 (acceptance 2). The copy moved onto the primary's duration with a
//       blank name → inline `serviceSetupCopyCollision`, CTA disabled, nothing
//       sent; its pencil → a typed name clears it → the POST carries it.
//   C3 (acceptance 4). «Прибрати» on the copy → the POST has one item.
//   C4 (phase 472). The copy card is fully on screen with its duration focused.
//   C5 (phase 472, D3). `type-nails-classic` is owned TWICE (`assign-typed`,
//       `assign-mismatch`): the switched-on owned card shows its own pencil
//       and none of those existing services; the owned card's and the copy
//       card's pencils each open that card's name well; both names ride the
//       bulk POST and no existing service is PATCHed.
//   C7 (phase 472, D3). The name pencil of a not-yet-owned switched-on row
//       (`type-nails-gel`) opens its name well; the typed name rides the
//       bulk POST item.
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

const String _typeId = 'type-nails-classic';
const String _copyKeyId = '${_typeId}_copy_1';

/// The fake catalogue's `nameUk` for [_typeId] — the D4 pencil pre-fill.
// i18n-finder-ok: fake-backend catalogue fixture, not l10n copy
const String _nailsTypeName = 'Класичний манікюр';

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

Finder _namePencil(String keyId) =>
    _inRow(keyId, Key('btn-setup-row-name-$keyId'));

/// D3 — the card's pencil → its name well, mounted.
Future<void> _openName(WidgetTester tester, String keyId) async {
  await _tap(tester, _namePencil(keyId));
  await tester.pumpUntilFound(_nameOf(keyId));
  await tester.ensureVisible(_nameOf(keyId));
}

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

bool _durationFocused(WidgetTester tester, String keyId) => tester
    .widget<EditableText>(
      find.descendant(
        of: _durationOf(keyId),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

VoidCallback? _saveCallback(WidgetTester tester) => tester
    .widget<NeumorphicButton>(find.byKey(const Key('btn-setup-save')))
    .onPressed;

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpUntilFound(target.hitTestable());
  await tester.tap(target);
}

/// Login → /services → FAB → setup (APPEND) → NAILS → owned row ON + priced →
/// «+ додати ще». Returns the live l10n.
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
  expect(
    _text(tester, _durationOf(_typeId)),
    isEmpty,
    reason: 'phase 472: no duration autofill on an owned row',
  );
  await tester.enterText(_durationOf(_typeId), '90');
  await tester.pump();

  final Finder addCopy = find.byKey(
    const Key('btn-setup-row-add-copy-$_typeId'),
  );
  await _tap(tester, addCopy);
  await tester.pumpUntilFound(_row(_copyKeyId));
  await tester.pumpUntilFound(_priceOf(_copyKeyId));
  // Phase 472: the jump focuses the copy's duration well.
  await AppHarness.pumpUntilCondition(
    tester,
    () => _durationFocused(tester, _copyKeyId),
    description: 'the «+ додати ще» jump focusing the copy duration',
  );
  return l10n;
}

/// Login → /services → FAB → setup (APPEND) → NAILS expanded. Returns the
/// router and the live l10n.
Future<(GoRouter, AppLocalizations)> _openSetupOnNails(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  AppHarness.expectLocation(router, RouteNames.masterProfile);
  router.go(RouteNames.services);
  final AppLocalizations l10n = await _reopenSetupOnNails(tester);
  return (router, l10n);
}

/// From /services: FAB → setup → NAILS chip → the owned row mounted.
Future<AppLocalizations> _reopenSetupOnNails(WidgetTester tester) async {
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
    'C1. «+ додати ще» adds a copy row with an EMPTY duration (D4), an empty '
    'price and a name pencil; a pre-filled, unchanged name is not sent; one '
    'save sends both items',
    (tester) async {
      final fb = FakeBackend();
      final l10n = await _openWithCopyRow(tester, fb);

      expect(
        _text(tester, _durationOf(_copyKeyId)),
        isEmpty,
        reason: 'D4: no nearest-free duration seed on a new copy',
      );
      expect(_text(tester, _priceOf(_copyKeyId)), isEmpty);
      // D3: the copy card shows its name with a pencil; the well opens on tap.
      expect(_namePencil(_copyKeyId), findsOneWidget);
      expect(_nameOf(_copyKeyId), findsNothing);
      expect(
        find.descendant(
          of: _row(_copyKeyId),
          matching: find.text(l10n.serviceSetupCopyNameHint),
        ),
        findsNothing,
      );

      // D4: the pencil pre-fills the type name; left unchanged it is not sent.
      // D4.3: the field replaces the title IN PLACE — the card keeps its size.
      final double rowHeight = tester.getSize(_row(_copyKeyId)).height;
      await _openName(tester, _copyKeyId);
      expect(_text(tester, _nameOf(_copyKeyId)), _nailsTypeName);
      expect(_namePencil(_copyKeyId), findsNothing, reason: 'field in place');
      // The duration well's focus ring animates out as the name takes focus;
      // compare settled geometry, not a mid-animation frame.
      await AppHarness.settle(tester);
      expect(
        tester.getSize(_row(_copyKeyId)).height,
        moreOrLessEquals(rowHeight, epsilon: 0.5),
        reason: 'D4.3: the pencil never resizes the card',
      );
      await tester.enterText(_durationOf(_copyKeyId), '120');
      await tester.pump();
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
        reason: 'an unchanged pre-filled name is not sent — the type name',
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

      await _openName(tester, _copyKeyId);
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

  testWidgets(
    'C4. «+ додати ще» brings the new copy card fully on screen and focuses '
    'its duration well',
    (tester) async {
      final fb = FakeBackend();
      await _openWithCopyRow(tester, fb);
      await tester.pumpUntilFound(_durationOf(_copyKeyId).hitTestable());
      await AppHarness.settle(tester);

      final Rect card = tester.getRect(_row(_copyKeyId));
      final Rect viewport = tester.getRect(find.byType(CustomScrollView));
      expect(card.top, greaterThanOrEqualTo(viewport.top));
      expect(card.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(_durationFocused(tester, _copyKeyId), isTrue);
      expect(_durationFocused(tester, _typeId), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'C5. the owned card and its copy card each show a pencil (no list of the '
    'existing services); each name rides its own bulk item, nothing is PATCHed',
    (tester) async {
      // i18n-finder-ok: user-typed service name fixtures, not l10n copy
      const String ownedName = 'Манікюр авторський';
      // i18n-finder-ok: user-typed service name fixtures, not l10n copy
      const String copyName = 'Манікюр експрес';
      final fb = FakeBackend();
      await _openWithCopyRow(tester, fb);
      // Let the «+ додати ще» reveal finish before scrolling back up to the
      // owned card's pencil (a live reveal pass would scroll it away again).
      await AppHarness.pumpUntilRevealSettled(
        tester,
        card: find.byKey(
          const Key('setup_row_$_copyKeyId'),
          skipOffstage: false,
        ),
        durationField: find.descendant(
          of: find.byKey(
            const Key('setup_row_$_copyKeyId'),
            skipOffstage: false,
          ),
          matching: find.byKey(
            const Key('service-setup-duration'),
            skipOffstage: false,
          ),
          skipOffstage: false,
        ),
      );

      expect(_namePencil(_typeId), findsOneWidget);
      expect(_namePencil(_copyKeyId), findsOneWidget);
      for (final String id in <String>['assign-typed', 'assign-mismatch']) {
        expect(find.byKey(Key('setup_row_owned_$id')), findsNothing);
        expect(find.byKey(Key('btn-setup-row-rename-$id')), findsNothing);
      }
      // Key-free check too (a re-added list without those keys must fail):
      // both owned services run 60 min, so no «60 хв» line in the card.
      final l10n = AppLocalizations.of(tester.element(_row(_typeId)));
      expect(
        find.descendant(
          of: _row(_typeId),
          matching: find.text('60 ${l10n.serviceSetupDurationSuffix}'),
        ),
        findsNothing,
        reason: 'D3: the owned card lists none of the existing services',
      );

      await tester.enterText(_durationOf(_copyKeyId), '120');
      await tester.pump();
      await tester.enterText(_priceOf(_copyKeyId), '800');
      await tester.pump();
      await _openName(tester, _typeId);
      await tester.enterText(_nameOf(_typeId), ownedName);
      await tester.pump();
      await _openName(tester, _copyKeyId);
      await tester.enterText(_nameOf(_copyKeyId), copyName);
      await tester.pump();

      final List<dynamic> items = await _saveAndCapture(tester, fb);
      expect(items, hasLength(2));
      final first = items[0] as Map<String, dynamic>;
      final second = items[1] as Map<String, dynamic>;
      expect((first['durationMinutes'], first['name']), (90, ownedName));
      expect((second['durationMinutes'], second['name']), (120, copyName));
      expect(fb.patchServiceCalls, 0, reason: 'D3: no rename of an existing');
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'C7. the name pencil on a not-yet-owned switched-on row sends its custom '
    'name with the add',
    (tester) async {
      const String gelTypeId = 'type-nails-gel';
      // i18n-finder-ok: user-typed service name fixture, not l10n copy
      const String custom = 'Гель авторський';
      final fb = FakeBackend();
      await _openSetupOnNails(tester, fb);

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
      await _tap(tester, gelToggle);
      final Finder namePencil = find.byKey(
        const Key('btn-setup-row-name-$gelTypeId'),
      );
      await tester.pumpUntilFound(namePencil);
      await _tap(tester, namePencil);
      final Finder well = _nameOf(gelTypeId);
      await tester.pumpUntilFound(well);
      await tester.enterText(well, custom);
      await tester.enterText(_durationOf(gelTypeId), '60');
      await tester.enterText(_priceOf(gelTypeId), '500');
      await tester.pump();

      final List<dynamic> items = await _saveAndCapture(tester, fb);
      expect(items, hasLength(1));
      final Map<String, dynamic> item = items.single as Map<String, dynamic>;
      expect(item['serviceTypeId'], gelTypeId);
      expect(item['durationMinutes'], 60);
      expect(item['name'], custom);
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
