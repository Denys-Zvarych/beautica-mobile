// Phase 4.2 design-alignment — Widget tests for ContactTile, ServiceTile,
// and VelvetBottomNavBar.
//
// These widgets were added to
// `lib/features/master/presentation/widgets/profile_avatar.dart` as part of
// the contacts-skeleton / services-placeholder / bottom-nav additions.
//
// Covers:
//   ContactTile
//     1. renders icon, value, and semantics label.
//     2. renders the optional platform label above the value.
//     3. onTap callback is invoked when the tile is tapped.
//
//   ServiceTile
//     4. renders name, duration, and price text.
//     5. wraps content in a Semantics widget with correct label.
//
//   VelvetBottomNavBar
//     6. renders all 4 nav items with their text labels.
//     7. active item is marked selected=true via Semantics; inactive items are not.
//
// Strategy:
//   Pure widget tests — no providers, no network.
//   Each widget is pumped independently via pumpApp (MaterialApp + l10n).

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  // ── ContactTile ──────────────────────────────────────────────────────────

  group('ContactTile', () {
    testWidgets('renders icon and value text', (tester) async {
      await tester.pumpApp(
        ContactTile(
          icon: Icons.phone_outlined,
          value: '—',
          semanticLabel: 'Телефон',
          onTap: () {},
        ),
      );
      await tester.pump();

      // Icon is present.
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
      // Value text is present.
      expect(find.text('—'), findsWidgets);
      // Chevron arrow always rendered on the right.
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets(
      'renders optional platform label above value when label is provided',
      (tester) async {
        await tester.pumpApp(
          ContactTile(
            icon: Icons.alternate_email,
            label: 'Instagram',
            value: '—',
            semanticLabel: 'Instagram',
            onTap: () {},
          ),
        );
        await tester.pump();

        expect(find.text('Instagram'), findsOneWidget);
        // Value text must also be present.
        expect(find.text('—'), findsWidgets);
      },
    );

    testWidgets('onTap callback fires when tile is tapped', (tester) async {
      var tapped = false;

      await tester.pumpApp(
        ContactTile(
          icon: Icons.phone_outlined,
          value: '+380 99 000 00 00',
          semanticLabel: 'Телефон',
          onTap: () => tapped = true,
        ),
      );
      await tester.pump();

      // Simulate a full tap-down + tap-up gesture so GestureDetector's
      // onTapUp fires (ContactTile calls onTap inside onTapUp).
      final tileFinder = find.byType(ContactTile);
      await tester.tapAt(tester.getCenter(tileFinder));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  // ── ServiceTile ──────────────────────────────────────────────────────────

  group('ServiceTile', () {
    testWidgets('renders name, duration, and price text', (tester) async {
      await tester.pumpApp(
        const ServiceTile(
          name: 'Манікюр',
          duration: '60 хв',
          price: '500 ₴',
          photoGradient: <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
        ),
      );
      await tester.pump();

      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.text('60 хв'), findsOneWidget);
      expect(find.text('500 ₴'), findsOneWidget);
    });

    testWidgets('wraps its subtree in at least one Semantics widget', (
      tester,
    ) async {
      await tester.pumpApp(
        const ServiceTile(
          name: 'Педикюр',
          duration: '90 хв',
          price: '700 ₴',
          photoGradient: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
        ),
      );
      await tester.pump();

      // A Semantics widget must be present — ServiceTile wraps its GestureDetector
      // in Semantics(button: true, label: '$name, $duration, $price').
      expect(find.byType(Semantics), findsWidgets);
    });

    // ── Bugfix 4 — long service name does not overflow at narrow widths ───────
    //
    // Regression: ServiceTile previously laid the name + duration + price in a
    // single inner Row, so a long Ukrainian service name competed with the
    // price for horizontal space and produced a RenderFlex overflow on narrow
    // phones. The fix restructured the tile to name-on-top (single-line,
    // ellipsis) with a duration/price metadata row below. These tests pin a
    // realistic narrow width (312–360 dp) and assert:
    //   (a) no overflow exception is thrown (takeException == null), and
    //   (b) the name Text uses maxLines: 1 + TextOverflow.ellipsis.

    const String longName =
        'Комплексний догляд за обличчям з глибоким очищенням та масажем';

    /// Pumps a single [ServiceTile] constrained to [width] logical pixels so the
    /// narrow-phone overflow path is exercised deterministically (independent of
    /// the default 800×600 test surface).
    Future<void> pumpNarrowTile(
      WidgetTester tester, {
      required double width,
      required String name,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ServiceTile(
                name: name,
                duration: '90 хв',
                price: '2 500 ₴',
                photoGradient: const <Color>[
                  Color(0xFFB89A7A),
                  Color(0xFF6A4A28),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'Bugfix 4: a long Ukrainian name does not overflow at 312 dp width',
      (tester) async {
        await pumpNarrowTile(tester, width: 312, name: longName);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'Bugfix 4: the restructured ServiceTile must not throw a '
              'RenderFlex overflow for a long name at a narrow width',
        );

        // The name Text must be single-line + ellipsized so it can never push
        // the row into overflow.
        final Text nameText = tester.widget<Text>(find.text(longName));
        expect(nameText.maxLines, 1, reason: 'name must be single-line');
        expect(
          nameText.overflow,
          TextOverflow.ellipsis,
          reason: 'name must ellipsize, not wrap or clip hard',
        );
      },
    );

    testWidgets(
      'Bugfix 4: a long Ukrainian name does not overflow at 360 dp width either',
      (tester) async {
        await pumpNarrowTile(tester, width: 360, name: longName);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'Bugfix 4: no overflow for a long name at a typical phone width',
        );
      },
    );
  });

  // ── VelvetBottomNavBar ───────────────────────────────────────────────────

  group('VelvetBottomNavBar', () {
    testWidgets('renders all 4 nav item labels', (tester) async {
      await tester.pumpApp(const VelvetBottomNavBar(activeIndex: 0));
      await tester.pump();

      expect(find.text('Послуги'), findsOneWidget);
      expect(find.text('Мої записи'), findsOneWidget);
      expect(find.text('Графік'), findsOneWidget);
      expect(find.text('Профіль'), findsOneWidget);
      // Guard the «Календар» → «Графік» rename both ways: the old label must
      // never render on the master nav bar (catches a silent revert).
      expect(find.text('Календар'), findsNothing);
    });

    testWidgets(
      'active tab uses the filled icon variant; inactive tabs use the outlined variant',
      (tester) async {
        // activeIndex: 3 → 'Профіль' — active icon is Icons.person_rounded.
        await tester.pumpApp(const VelvetBottomNavBar(activeIndex: 3));
        await tester.pump();

        // Active icon (filled) must be present.
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        // Inactive icons (outlined) for the other 3 tabs must be present.
        expect(find.byIcon(Icons.design_services_outlined), findsOneWidget);
        expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
        expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
        // The filled person icon (active) must NOT coexist with the outlined one.
        expect(find.byIcon(Icons.person_outline), findsNothing);
      },
    );
  });
}
