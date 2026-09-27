// mobile-qa gap-closure (salon-cover work, 2026-08-29) — `salon_cover_widgets.dart`
// had zero dedicated test file despite being SHARED render code consumed by
// both `PublicSalonProfileScreen` and `SalonManagementProfileScreen` (see
// `mobile-build-verifier`'s finding: no golden or widget test anywhere
// exercises `CoverIconButton`, `SalonCover`, or either cover-consuming
// screen — 280 golden tests passed unchanged through a new icon appearing
// on the cover AND a pill being deleted from it).
//
// This file covers the ONE new API surface that shipped here:
// `CoverIconButton.icon`/`svgIcon` — relaxed from a required `IconData` to
// two mutually-exclusive optional fields, guarded by
// `assert((icon == null) != (svgIcon == null))`. Without a test, that
// invariant is decoration — nothing proves the assert actually fires, and
// nothing proves each valid branch renders the widget type it claims to.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  group('CoverIconButton icon/svgIcon invariant', () {
    test('throws AssertionError when NEITHER icon nor svgIcon is provided', () {
      expect(
        () => CoverIconButton(
          onTap: () {},
          semanticLabel: 'x',
          // icon and svgIcon both default to null — assertion fires here.
        ),
        throwsAssertionError,
      );
    });

    test('throws AssertionError when BOTH icon and svgIcon are provided', () {
      expect(
        () => CoverIconButton(
          icon: Icons.tune_rounded,
          svgIcon: BeauticaAssetIcons.notificationUnread,
          onTap: () {},
          semanticLabel: 'x',
        ),
        throwsAssertionError,
      );
    });

    testWidgets('icon-only renders a Material Icon, never AppIcon', (
      tester,
    ) async {
      await tester.pumpApp(
        CoverIconButton(
          key: const Key('under-test'),
          icon: Icons.tune_rounded,
          onTap: () {},
          semanticLabel: 'x',
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
        reason: 'the icon-only branch must render Material\'s Icon',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(AppIcon),
        ),
        findsNothing,
        reason: 'the icon-only branch must NOT also render AppIcon',
      );
    });

    testWidgets('svgIcon-only renders AppIcon, never a Material Icon', (
      tester,
    ) async {
      await tester.pumpApp(
        CoverIconButton(
          key: const Key('under-test'),
          svgIcon: BeauticaAssetIcons.notificationUnread,
          onTap: () {},
          semanticLabel: 'x',
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(AppIcon),
        ),
        findsOneWidget,
        reason:
            'the svgIcon-only branch must render AppIcon, matching '
            'the notification bell\'s multicolour asset',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(Icon),
        ),
        findsNothing,
        reason:
            'the svgIcon-only branch must NOT also render a Material '
            'Icon',
      );
    });
  });
}
