// mobile-qa gap-closure (2026-08-26) — widget-level coverage for
// `CategorySection`'s [CategorySection.slug] → leading-icon wiring
// (`lib/features/services/presentation/widgets/service_category_list.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// The slug→icon wiring shipped alongside 6 `services_list_*` +
// 12 `walk_in_chain_*` regenerated golden baselines, but:
//   • `walk_in_chain_golden_test.dart`'s fixture has NO uncategorized
//     service (both fixture services are `NAILS`), so the `slug == null`
//     "empty same-size slot, never the cosmetology fallback" branch —
//     the field doc's own stated invariant — has zero pixel coverage on
//     that screen.
//   • `services_list_screen_test.dart` mounts an uncategorized bucket (a
//     service with no `category`) for OTHER reasons (bucket-ordering,
//     collapse-toggle), but never asserts anything about the header's
//     leading-icon slot — no `AppIcon` finder anywhere in that file.
//   • `categoryIconFor` itself (the resolver `CategorySection` delegates
//     to) is thoroughly unit-tested in `test/core/icons/category_icons_test.dart`
//     — but NEVER never returns null (documented on the resolver and
//     `CategorySection.slug`'s own field doc), so a widget-level test is the
//     only place that can prove `CategorySection` special-cases `slug ==
//     null` BEFORE calling the resolver, rather than calling it and hoping
//     it doesn't mislabel "Без категорії" with the cosmetology fallback
//     glyph.
//
// So the resolver logic is covered, and the two screens' PIXELS are
// covered — but the actual `slug == null → empty SizedBox, never
// AppIcon` WIDGET BRANCH was untested at every layer. This file closes
// that gap directly, isolated from both consumer screens.
//
// Isolation: `CategorySection` takes no providers — plain `pumpApp` with a
// bare instance, no repository/notifier overrides needed.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  group('CategorySection — leading icon slot (slug wiring)', () {
    testWidgets(
      'slug == null renders NO AppIcon — an empty same-size slot, never the '
      'categoryIconFor cosmetology fallback glyph',
      (tester) async {
        await tester.pumpApp(
          const CategorySection(
            key: Key('cs_uncategorized'),
            title: 'Без категорії',
            count: 1,
            slug: null,
            children: <Widget>[SizedBox()],
          ),
        );
        await tester.pump();

        expect(
          find.byType(AppIcon),
          findsNothing,
          reason:
              'slug == null (uncategorized) must render no AppIcon at all — '
              'categoryIconFor() NEVER returns null, so calling it here would '
              'mislabel "Без категорії" with the cosmetology fallback glyph '
              'instead of leaving the header icon-less. This is the exact '
              'branch neither services_list_screen_test.dart nor '
              'walk_in_chain_golden_test.dart exercises (the latter\'s '
              'fixture has no uncategorized service).',
        );
        // The section still renders — this is an empty icon SLOT, not a
        // missing section. Found by Key, not find.text(<Cyrillic>) (M2 /
        // forbid_cyrillic_finder.sh — the title is UI copy, not
        // locale-invariant data).
        expect(find.byKey(const Key('cs_uncategorized')), findsOneWidget);
      },
    );

    testWidgets(
      'slug != null renders exactly one AppIcon, actually laid out at 20×20 '
      'in accentDeep — matching ServiceCategoryCard\'s sibling treatment',
      (tester) async {
        await tester.pumpApp(
          const CategorySection(
            key: Key('cs_brows'),
            title: 'Брови',
            count: 2,
            slug: 'BROWS',
            children: <Widget>[SizedBox()],
          ),
        );
        await tester.pump();

        final Finder iconFinder = find.byType(AppIcon);
        expect(
          iconFinder,
          findsOneWidget,
          reason: 'a non-null slug must resolve exactly one leading glyph',
        );

        final AppIcon icon = tester.widget<AppIcon>(iconFinder);
        expect(icon.color, BrandColors.accentDeep);
        expect(
          icon.size,
          20.0,
          reason:
              'CategorySection._iconSize must stay 20dp — the constructor '
              'field value',
        );

        // Constructor-field assertions alone are vacuous against a layout bug
        // that silently clobbers the requested size (exactly the failure mode
        // documented on the timeline medallion's own `alignment` fix) — so
        // also pin the actually-PAINTED size.
        final Size renderedSize = tester.getSize(iconFinder);
        expect(
          renderedSize,
          const Size(20.0, 20.0),
          reason:
              'the leading glyph must actually PAINT at 20×20, not merely be '
              'configured with size: 20',
        );
      },
    );
  });
}
