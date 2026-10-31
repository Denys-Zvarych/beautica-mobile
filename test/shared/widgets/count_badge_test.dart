import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/shared/widgets/count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: w)),
  ),
);

const Key _k = Key('master-bookings-filter-badge');

void main() {
  testWidgets('renders nothing when the count is 0', (t) async {
    await _pump(t, const CountBadge(count: 0));
    expect(find.byKey(_k), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders the digit when the count is 1', (t) async {
    await _pump(t, const CountBadge(count: 1));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('keeps 99 as 99 when the cap is 99', (t) async {
    await _pump(t, const CountBadge(count: 99, maxCount: 99));
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('renders 99+ when 100 exceeds the cap of 99', (t) async {
    await _pump(t, const CountBadge(count: 100, maxCount: 99));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('renders 150 verbatim when no cap is set', (t) async {
    await _pump(t, const CountBadge(count: 150));
    expect(find.text('150'), findsOneWidget);
  });

  testWidgets('fills with accentDeep when no colour is passed', (t) async {
    await _pump(t, const CountBadge(count: 2));
    final Container c = t.widget<Container>(find.byKey(_k));
    expect((c.decoration! as BoxDecoration).color, BrandColors.accentDeep);
  });

  testWidgets('applies a custom colour to the pill decoration', (t) async {
    await _pump(
      t,
      const CountBadge(count: 2, color: BrandColors.notificationBadge),
    );
    final Container c = t.widget<Container>(find.byKey(_k));
    expect(
      (c.decoration! as BoxDecoration).color,
      BrandColors.notificationBadge,
    );
  });

  testWidgets('excludes the pill from semantics', (t) async {
    await _pump(t, const CountBadge(count: 5));
    expect(
      find.descendant(
        of: find.byType(CountBadge),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'anchor hides the pill at 0 and shows it under the custom key at 3',
    (t) async {
      await _pump(
        t,
        const CountBadgeAnchor(
          count: 0,
          badgeKey: Key('x'),
          child: SizedBox(width: 40, height: 40),
        ),
      );
      expect(find.byKey(const Key('x')), findsNothing);
      await _pump(
        t,
        const CountBadgeAnchor(
          count: 3,
          badgeKey: Key('x'),
          child: SizedBox(width: 40, height: 40),
        ),
      );
      expect(find.byKey(const Key('x')), findsOneWidget);
    },
  );

  testWidgets('anchor renders 99+ when the count exceeds the cap', (t) async {
    await _pump(
      t,
      const CountBadgeAnchor(
        count: 100,
        maxCount: 99,
        badgeKey: Key('x'),
        child: SizedBox(width: 40, height: 40),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });

  // ── CountBadge.dot (2026-10-30, master-nav setup hints) ──────────────────
  group('CountBadge.dot', () {
    const Key dotKey = Key('count-badge-dot');

    testWidgets('renders an 8 dp mocha dot with no digit', (t) async {
      await _pump(t, const CountBadge.dot());
      expect(find.byKey(dotKey), findsOneWidget);
      expect(t.getSize(find.byKey(dotKey)), const Size(8, 8));
      expect(CountBadge.dotSize, 8);
      expect(find.byType(Text), findsNothing);
      final Container c = t.widget<Container>(find.byKey(dotKey));
      final BoxDecoration d = c.decoration! as BoxDecoration;
      expect(d.color, BrandColors.accentDeep, reason: 'mocha, never red');
      expect((d.border! as Border).top.color, BrandColors.base);
    });

    testWidgets('applies a custom colour and routes a custom key', (t) async {
      await _pump(
        t,
        const CountBadge.dot(color: BrandColors.muted, key: Key('d')),
      );
      expect(find.byKey(dotKey), findsNothing);
      final Container c = t.widget<Container>(find.byKey(const Key('d')));
      expect((c.decoration! as BoxDecoration).color, BrandColors.muted);
    });

    testWidgets('excludes the dot from semantics', (t) async {
      await _pump(t, const CountBadge.dot());
      expect(
        find.descendant(
          of: find.byType(CountBadge),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets('anchor dot: shown at count 0, replaces the pill at count 3, '
        'tucked at -1 dp on the corner', (t) async {
      await _pump(
        t,
        const CountBadgeAnchor(
          count: 0,
          dot: true,
          badgeKey: Key('x'),
          child: SizedBox(width: 40, height: 40),
        ),
      );
      expect(find.byKey(const Key('x')), findsOneWidget);
      final Positioned p = t.widget<Positioned>(
        find.ancestor(
          of: find.byKey(const Key('x')),
          matching: find.byType(Positioned),
        ),
      );
      expect((p.top, p.right), (-1.0, -1.0));

      await _pump(
        t,
        const CountBadgeAnchor(
          count: 3,
          dot: true,
          badgeKey: Key('x'),
          child: SizedBox(width: 40, height: 40),
        ),
      );
      expect(find.byKey(const Key('x')), findsOneWidget);
      expect(find.text('3'), findsNothing, reason: 'dot wins over the pill');
    });
  });
}
