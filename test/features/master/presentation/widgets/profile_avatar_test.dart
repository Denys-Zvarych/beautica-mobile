// Phase 4.4 — Widget tests for ProfileAvatar, RoleChip, and StatTile.
//
// Covers:
//   1. ProfileAvatar — renders with Key('master-profile-avatar').
//   2. ProfileAvatar — custom diameter is respected (SizedBox dimensions).
//   3. ProfileAvatar — Semantics label is present and accessible.
//   4. RoleChip — renders the label text inside the pill.
//   5. RoleChip — renders the icon when provided.
//   6. RoleChip — renders without icon when icon is null.
//   7. StatTile — renders value and caption text.
//   8. StatTile — valueKey is set on the value Text widget.
//
// Strategy:
//   Pure widget tests — no providers, no network.
//   Each widget is pumped independently in a MaterialApp with BrandColors
//   scaffolding so NeumorphicInset and NeumorphicCard can resolve Theme.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  // ── ProfileAvatar ─────────────────────────────────────────────────────────

  group('ProfileAvatar', () {
    testWidgets('renders with the correct key', (tester) async {
      await tester.pumpApp(const ProfileAvatar());
      await tester.pump();

      expect(find.byKey(const Key('master-profile-avatar')), findsOneWidget);
    });

    testWidgets('defaults to kDiameter and accepts custom diameter', (
      tester,
    ) async {
      const customDiameter = 64.0;

      await tester.pumpApp(const ProfileAvatar(diameter: customDiameter));
      await tester.pump();

      final sizedBox = tester.widget<SizedBox>(
        find.byKey(const Key('master-profile-avatar')),
      );
      expect(sizedBox.width, customDiameter);
      expect(sizedBox.height, customDiameter);
    });

    testWidgets('default diameter equals ProfileAvatar.kDiameter', (
      tester,
    ) async {
      await tester.pumpApp(const ProfileAvatar());
      await tester.pump();

      final sizedBox = tester.widget<SizedBox>(
        find.byKey(const Key('master-profile-avatar')),
      );
      expect(sizedBox.width, ProfileAvatar.kDiameter);
      expect(sizedBox.height, ProfileAvatar.kDiameter);
    });

    testWidgets('has Semantics label for accessibility', (tester) async {
      await tester.pumpApp(const ProfileAvatar());
      await tester.pump();

      // The Semantics widget wraps the SizedBox, so we verify the ancestor.
      expect(find.bySemanticsLabel('Фото профілю'), findsOneWidget);
    });
  });

  // ── RoleChip ──────────────────────────────────────────────────────────────

  group('RoleChip', () {
    testWidgets('renders the label text', (tester) async {
      await tester.pumpApp(const RoleChip(label: 'Незалежний майстер'));
      await tester.pump();

      expect(find.text('Незалежний майстер'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpApp(
        const RoleChip(
          label: 'Власник салону',
          icon: Icons.auto_awesome_rounded,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.text('Власник салону'), findsOneWidget);
    });

    testWidgets('renders without icon when icon is null', (tester) async {
      await tester.pumpApp(const RoleChip(label: 'Майстер салону'));
      await tester.pump();

      // No Icon widget should be present.
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Майстер салону'), findsOneWidget);
    });

    testWidgets('renders NeumorphicInset as the container', (tester) async {
      await tester.pumpApp(const RoleChip(label: 'Тест'));
      await tester.pump();

      expect(find.byType(NeumorphicInset), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // RoleChip overflow — Flexible wrapper regression guard [HIGH]
    //
    // Regression: without the Flexible wrapper the chip's Text overflows the
    // Row when the label is longer than the chip's available width. This test
    // constrains the chip to 60 dp — deliberately narrower than any real label
    // — so overflow is guaranteed unless Flexible is present. Asserts:
    //   a. No layout overflow exception (tester.takeException() is null).
    //   b. At least one Flexible widget is present in the chip's subtree.
    // -----------------------------------------------------------------------
    testWidgets('overflow — Flexible wrapper regression guard: '
        'no overflow in a 60 dp constrained SizedBox and Flexible is present', (
      tester,
    ) async {
      await tester.pumpApp(
        const SizedBox(
          width: 60,
          child: RoleChip(
            label: 'Дуже довга назва ролі яка точно переповниться',
            icon: Icons.auto_awesome_rounded,
          ),
        ),
      );
      await tester.pump();

      // a. No overflow exception must be thrown.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'RoleChip must not throw a layout overflow exception in a '
            '60 dp SizedBox — the Flexible wrapper must prevent it',
      );

      // b. At least one Flexible must exist inside the RoleChip subtree,
      //    confirming the fix is in place.
      expect(
        find.descendant(
          of: find.byType(RoleChip),
          matching: find.byType(Flexible),
        ),
        findsAtLeastNWidgets(1),
        reason:
            'RoleChip.build() must wrap the label Text in a Flexible '
            'widget — regression guard for the fix in '
            'lib/features/master/presentation/widgets/profile_avatar.dart',
      );
    });
  });

  // ── StatTile ──────────────────────────────────────────────────────────────

  group('StatTile', () {
    testWidgets('renders value and caption', (tester) async {
      await tester.pumpApp(
        const StatTile(
          icon: Icons.star_rounded,
          value: '4.8',
          caption: 'Рейтинг',
        ),
      );
      await tester.pump();

      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('Рейтинг'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpApp(
        const StatTile(
          icon: Icons.reviews_outlined,
          value: '42',
          caption: 'Відгуки',
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.reviews_outlined), findsOneWidget);
    });

    testWidgets('valueKey is set on the value Text widget', (tester) async {
      const valueKey = Key('stat-tile-value');

      await tester.pumpApp(
        const StatTile(
          icon: Icons.star_rounded,
          value: '5.0',
          caption: 'Рейтинг',
          valueKey: valueKey,
        ),
      );
      await tester.pump();

      expect(find.byKey(valueKey), findsOneWidget);
      final textWidget = tester.widget<Text>(find.byKey(valueKey));
      expect(textWidget.data, '5.0');
    });

    testWidgets('wraps content in a Semantics widget', (tester) async {
      await tester.pumpApp(
        const StatTile(
          icon: Icons.star_rounded,
          value: '3.9',
          caption: 'Рейтинг',
        ),
      );
      await tester.pump();

      // StatTile wraps its content in Semantics(label: '$value $caption').
      // We verify this by checking the Semantics node exists and value/caption
      // text nodes are both present in the tree.
      expect(find.text('3.9'), findsOneWidget);
      expect(find.text('Рейтинг'), findsOneWidget);
      // Semantics widget must be present in the tree.
      expect(find.byType(Semantics), findsWidgets);
    });

    // ── Default (onTap == null) is display-only ─────────────────────────────
    // Every own-profile caller omits `onTap` (user decision 2026-09-26): no
    // `InkWell`, no gesture, no button semantics, and a tap is a no-op.
    group('display-only when onTap is null (default)', () {
      testWidgets('no InkWell, no button semantics', (tester) async {
        // Disposed explicitly at the END of the body, not via addTearDown:
        // `_verifySemanticsHandlesWereDisposed` runs BEFORE tear-downs.
        final SemanticsHandle handle = tester.ensureSemantics();

        await tester.pumpApp(
          const StatTile(
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
          ),
        );
        await tester.pump();

        expect(find.byType(InkWell), findsNothing);
        expect(
          tester.getSemantics(find.byType(StatTile)),
          isNot(isSemantics(isButton: true)),
        );

        handle.dispose();
      });

      testWidgets('a tap on the tile does nothing observable', (tester) async {
        await tester.pumpApp(
          const StatTile(
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
          ),
        );
        await tester.pump();

        // No InkWell / GestureDetector to hit — warnIfMissed would flag a
        // real interactive target the tap failed to land on.
        await tester.tap(find.byType(StatTile), warnIfMissed: false);
        await tester.pump();

        expect(find.byType(StatTile), findsOneWidget);
        expect(find.text('4.8'), findsOneWidget);
      });

      testWidgets('no GestureDetector or AnimatedScale in the tree', (
        tester,
      ) async {
        await tester.pumpApp(
          const StatTile(
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
          ),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(StatTile),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(StatTile),
            matching: find.byType(AnimatedScale),
          ),
          findsNothing,
        );
      });
    });

    // ── onTap set (client-view master profile, user decision 2026-11-17) ───
    group('tappable when onTap is set', () {
      testWidgets('a tap by the tile Key fires onTap exactly once', (
        tester,
      ) async {
        int taps = 0;
        await tester.pumpApp(
          StatTile(
            key: const Key('tile'),
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
            onTap: () => taps++,
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('tile')));
        await tester.pumpAndSettle();

        expect(taps, 1);
      });

      testWidgets('button semantics, composed label and tap hint', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpApp(
          StatTile(
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
            onTap: () {},
            tapHint: 'Відкрити вкладку «Відгуки»',
          ),
        );
        await tester.pump();

        expect(
          tester.getSemantics(find.byType(StatTile)),
          isSemantics(
            isButton: true,
            hasTapAction: true,
            label: '4.8 Рейтинг',
            onTapHint: 'Відкрити вкладку «Відгуки»',
          ),
        );
        expect(find.byType(InkWell), findsNothing, reason: 'no ripple');

        handle.dispose();
      });

      testWidgets('press depresses to 0.97 and releases back to 1', (
        tester,
      ) async {
        await tester.pumpApp(
          StatTile(
            icon: Icons.star_rounded,
            value: '4.8',
            caption: 'Рейтинг',
            onTap: () {},
          ),
        );
        await tester.pump();

        double scale() => tester
            .widget<AnimatedScale>(
              find.descendant(
                of: find.byType(StatTile),
                matching: find.byType(AnimatedScale),
              ),
            )
            .scale;

        expect(scale(), 1);
        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byType(StatTile)),
        );
        await tester.pump();
        expect(scale(), 0.97);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(scale(), 1);
      });
    });
  });
}
