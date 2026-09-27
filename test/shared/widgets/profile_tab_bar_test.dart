// Widget tests for `ProfileTabBar` (lib/shared/widgets/profile_tab_bar.dart).
//
// Phase 351 (mobile-qa gap-fix, 2026-09-25) — `ProfileTabBar` was PROMOTED
// from the private `SalonTabBar` and picked up a second, differently-keyed
// consumer (the public/own master profiles, `keyPrefix: 'public-master-
// profile'` etc.) with ZERO direct widget tests of its own. Every guarantee
// about it was inherited transitively through screen-level key lookups on
// `public_salon_profile_screen_test.dart` / the master profile screen tests.
// This file proves what those screen tests structurally cannot in one place:
//   1. `keyPrefix` actually drives each tab's `Key` (`$keyPrefix-tab-$i`) —
//      the whole reason a second caller can coexist with the salon's without
//      key collisions.
//   2. `selected` renders exactly one tab as the active `Semantics.selected`
//      node, with the right label — not just "the widget exists".
//   3. Tapping an INACTIVE tab calls `onSelect` with that tab's index exactly
//      once; tapping the ALREADY-active tab still fires `onSelect` (the
//      widget does not suppress the callback — that's the caller's choice).
//   4. Tap target — `Semantics(button: true)` per tab, not just the row.

import 'package:beautica_mobile/shared/widgets/profile_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('ProfileTabBar — keys', () {
    testWidgets('keyPrefix drives each tab Key (<keyPrefix>-tab-<i>)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ProfileTabBar(
            tabs: const <String>['About', 'Services', 'Reviews'],
            selected: 0,
            onSelect: (_) {},
            keyPrefix: 'public-master-profile',
          ),
        ),
      );

      expect(
        find.byKey(const Key('public-master-profile-tab-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('public-master-profile-tab-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('public-master-profile-tab-2')),
        findsOneWidget,
      );
      // Default prefix ('salon') keys must NOT also be present — proves the
      // prefix is actually threaded through, not hard-coded.
      expect(find.byKey(const Key('salon-tab-0')), findsNothing);
    });

    testWidgets('default keyPrefix is "salon" — existing salon callers keep '
        'their exact Key values unchanged', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProfileTabBar(
            tabs: const <String>['Про салон', 'Майстри'],
            selected: 0,
            onSelect: (_) {},
          ),
        ),
      );

      expect(find.byKey(const Key('salon-tab-0')), findsOneWidget);
      expect(find.byKey(const Key('salon-tab-1')), findsOneWidget);
    });
  });

  group('ProfileTabBar — selection rendering', () {
    testWidgets('selected renders exactly one Semantics(selected: true) tab, '
        'the others selected: false', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            ProfileTabBar(
              tabs: const <String>['A', 'B', 'C'],
              selected: 1,
              onSelect: (_) {},
              keyPrefix: 'p',
            ),
          ),
        );

        SemanticsData semanticsOf(Key key) =>
            tester.getSemantics(find.byKey(key)).getSemanticsData();

        expect(
          semanticsOf(
            const Key('p-tab-1'),
          ).flagsCollection.isSelected.toBoolOrNull(),
          isTrue,
        );
        expect(
          semanticsOf(
            const Key('p-tab-0'),
          ).flagsCollection.isSelected.toBoolOrNull(),
          isFalse,
        );
        expect(
          semanticsOf(
            const Key('p-tab-2'),
          ).flagsCollection.isSelected.toBoolOrNull(),
          isFalse,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('renders every tab label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProfileTabBar(
            tabs: const <String>['Про майстра', 'Послуги', 'Відгуки'],
            selected: 0,
            onSelect: (_) {},
            keyPrefix: 'p',
          ),
        ),
      );

      // i18n-finder-ok: asserting the exact label strings passed in by the
      // caller are rendered verbatim, not translating UI copy ourselves.
      expect(find.text('Про майстра'), findsOneWidget);
      // i18n-finder-ok: same rationale — caller-supplied label, not UI copy.
      expect(find.text('Послуги'), findsOneWidget);
      // i18n-finder-ok: same rationale — caller-supplied label, not UI copy.
      expect(find.text('Відгуки'), findsOneWidget);
    });
  });

  group('ProfileTabBar — tap behaviour', () {
    testWidgets('tapping an inactive tab calls onSelect with its index '
        'exactly once', (tester) async {
      final List<int> calls = <int>[];
      await tester.pumpWidget(
        _wrap(
          ProfileTabBar(
            tabs: const <String>['A', 'B'],
            selected: 0,
            onSelect: calls.add,
            keyPrefix: 'p',
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('p-tab-1')));
      await tester.pump();

      expect(calls, <int>[1]);
    });

    testWidgets('tapping the ALREADY-active tab still fires onSelect — the '
        'widget does not suppress a same-tab tap', (tester) async {
      final List<int> calls = <int>[];
      await tester.pumpWidget(
        _wrap(
          ProfileTabBar(
            tabs: const <String>['A', 'B'],
            selected: 0,
            onSelect: calls.add,
            keyPrefix: 'p',
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('p-tab-0')));
      await tester.pump();

      expect(calls, <int>[0]);
    });

    testWidgets('every tab is a Semantics(button: true) node', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            ProfileTabBar(
              tabs: const <String>['A', 'B'],
              selected: 0,
              onSelect: (_) {},
              keyPrefix: 'p',
            ),
          ),
        );

        for (final Key k in const <Key>[Key('p-tab-0'), Key('p-tab-1')]) {
          final SemanticsData data = tester
              .getSemantics(find.byKey(k))
              .getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue, reason: '$k');
        }
      } finally {
        handle.dispose();
      }
    });
  });
}
