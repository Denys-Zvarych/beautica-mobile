// Phase 13.6 regression — SalonServicesAccordion price text styling.
//
// Bug: `_SalonServiceRow`'s price `Text` used `VelvetText.bodyStrong()`
// (Nunito 15 sp) instead of the compact metadata scale (12.5 sp) used by the
// reference screen — the salon's own service-management list
// (`services_list_screen.dart`'s `_MetaItem._valueStyle`,
// `VelvetText.pill().copyWith(fontSize: 12.5)`). The 15 sp price rendered
// visibly larger/bolder than the 12 sp duration label right next to it.
//
// This test pins the resolved price style's `fontSize`, `fontWeight`, and
// `color` to the compact metadata scale so none of the three can silently
// drift back to `bodyStrong()` (15 sp / w700 / `BrandColors.text` espresso)
// again — only checking `fontSize` would miss a regression that reverted the
// base style (e.g. back to `bodyStrong()`) while some other change happened
// to keep the size at/under 13 sp. It FAILS against the pre-fix style and
// PASSES against the fix (<= 13 sp / w800 / `BrandColors.accentDeep`,
// matching the 12.5 sp reference).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_services_accordion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _kCategories = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Класичний манікюр',
        durationLabel: '1 год',
        priceDisplay: '500 грн',
      ),
    ],
  ),
];

void main() {
  testWidgets(
    'price text renders at the compact metadata scale, not bodyStrong()',
    (tester) async {
      await tester.pumpApp(
        const SalonServicesAccordion(categories: _kCategories),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture price string, not UI copy
      final priceFinder = find.text('500 грн');
      expect(priceFinder, findsOneWidget);

      final Text priceText = tester.widget<Text>(priceFinder);
      final double? resolvedFontSize = priceText.style?.fontSize;

      expect(
        resolvedFontSize,
        isNotNull,
        reason: 'price Text must have an explicit style with a fontSize',
      );
      expect(
        resolvedFontSize! <= 13,
        isTrue,
        reason:
            'price text must use the compact metadata scale (12.5 sp, '
            'matching services_list_screen._MetaItem._valueStyle) — '
            'not VelvetText.bodyStrong() (15 sp), which visibly overpowers '
            'the 12 sp duration label beside it. Resolved size was '
            '$resolvedFontSize.',
      );

      // Guard the other two axes of the same regression: `bodyStrong()` is
      // not just larger, it is also a lighter weight (w700) in the plain
      // espresso text color (`BrandColors.text`) rather than the camel
      // "price emphasis" color (`BrandColors.accentDeep`) w/ w800 used by
      // the compact metadata/pill scale everywhere else in this codebase.
      // A test that only pinned `fontSize` would miss a regression that
      // reverted the base style while incidentally keeping the size <= 13.
      expect(
        priceText.style?.fontWeight,
        FontWeight.w800,
        reason:
            'price text must keep the pill/metadata emphasis weight (w800), '
            'not bodyStrong()\'s w700.',
      );
      expect(
        priceText.style?.color,
        BrandColors.accentDeep,
        reason:
            'price text must use the camel price-emphasis color '
            '(BrandColors.accentDeep), not bodyStrong()\'s plain espresso '
            'text color (BrandColors.text).',
      );
    },
  );

  testWidgets(
    'name text renders at the reference cardTitle scale (1.15 line-height), '
    'not bodyStrong() (1.5 line-height)',
    (tester) async {
      await tester.pumpApp(
        const SalonServicesAccordion(categories: _kCategories),
      );
      await tester.pumpAndSettle();

      final nameFinder = find.text('Класичний манікюр');
      expect(nameFinder, findsOneWidget);

      final Text nameText = tester.widget<Text>(nameFinder);
      final TextStyle? resolvedStyle = nameText.style;

      expect(
        resolvedStyle,
        isNotNull,
        reason: 'service name Text must have an explicit style',
      );
      expect(
        resolvedStyle!.fontSize,
        15,
        reason:
            'service name must stay at 15 sp, matching the reference '
            'screen\'s _ServiceInfo._nameStyle (services_list_screen.dart).',
      );

      // The point size alone (15 sp) coincidentally matches bodyStrong()'s
      // 15 sp, so fontSize cannot catch this regression on its own — the
      // actual bug is the 30% looser line-height (1.5 vs 1.15) plus the
      // wrong font family (Nunito vs Comfortaa), which visibly bulks up
      // each row even though the size "matches".
      expect(
        resolvedStyle.height,
        1.15,
        reason:
            'service name must use the reference screen\'s tight 1.15 '
            'line-height, not VelvetText.bodyStrong()\'s 1.5 — the looser '
            'line-height is what makes each row render visibly taller even '
            'though the fontSize alone matches.',
      );

      // Guard against the regression reappearing under a different guise:
      // the resolved style must not equal bodyStrong()'s resolved style.
      final TextStyle bodyStrongStyle = VelvetText.bodyStrong();
      expect(
        resolvedStyle,
        isNot(equals(bodyStrongStyle)),
        reason:
            'service name style must not match VelvetText.bodyStrong() — '
            'that is the pre-fix regression style (Nunito 15 sp / 1.5 '
            'line-height).',
      );
    },
  );
}
