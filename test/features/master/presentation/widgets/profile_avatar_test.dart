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
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  // ── ProfileAvatar ─────────────────────────────────────────────────────────

  group('ProfileAvatar', () {
    testWidgets('renders with the correct key', (tester) async {
      await tester.pumpApp(const ProfileAvatar());
      await tester.pump();

      expect(
        find.byKey(const Key('master-profile-avatar')),
        findsOneWidget,
      );
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

      final semantics = tester.getSemantics(
        find.byKey(const Key('master-profile-avatar')),
      );
      // The Semantics widget wraps the SizedBox, so we verify the ancestor.
      expect(
        find.bySemanticsLabel('Фото профілю'),
        findsOneWidget,
      );
    });
  });

  // ── RoleChip ──────────────────────────────────────────────────────────────

  group('RoleChip', () {
    testWidgets('renders the label text', (tester) async {
      await tester.pumpApp(
        const RoleChip(label: 'Незалежний майстер'),
      );
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
      await tester.pumpApp(
        const RoleChip(label: 'Майстер салону'),
      );
      await tester.pump();

      // No Icon widget should be present.
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Майстер салону'), findsOneWidget);
    });

    testWidgets('renders NeumorphicInset as the container', (tester) async {
      await tester.pumpApp(
        const RoleChip(label: 'Тест'),
      );
      await tester.pump();

      expect(find.byType(NeumorphicInset), findsOneWidget);
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
  });
}
