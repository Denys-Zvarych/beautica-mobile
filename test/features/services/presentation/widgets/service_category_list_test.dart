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
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _stubService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Стрижка',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 ₴',
);

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

  // ---------------------------------------------------------------------------
  // Phase 320 (D3) — ServiceCard.onEdit becomes nullable.
  //
  // The pair is what makes the nullable change honest: `null` must make the
  // card genuinely NON-tappable (no GestureDetector attached at all — the
  // structural proof mutation check 3 exercises), not "tappable, does
  // nothing" (a GestureDetector present whose handlers silently no-op). A
  // non-null onEdit must render and behave exactly as before this phase.
  // ---------------------------------------------------------------------------

  group('ServiceCard — nullable onEdit (Phase 320 D3)', () {
    testWidgets(
      'onEdit: null — card still renders (values visible), but carries NO '
      'GestureDetector and reports no button semantics',
      (tester) async {
        await tester.pumpApp(
          const ServiceCard(
            key: Key('service_card_svc-001'),
            service: _stubService,
            onEdit: null,
          ),
        );
        // fixed-wait-ok: draining ServiceCard's own 460ms staggered-entrance
        // AnimationController (appearDelay: Duration.zero here, so it starts
        // immediately) — there is no discrete "entrance complete" signal to
        // pump-until.
        await tester.pump(const Duration(milliseconds: 500));

        final Finder cardFinder = find.byKey(const Key('service_card_svc-001'));
        expect(cardFinder, findsOneWidget);
        // Positive half — the card's values are still visible. An
        // absence-only test here would pass on a blank tree.
        // i18n-finder-ok: _stubService.name is user-entered service data
        // (not translated UI copy) — the master's own free-text name.
        expect(find.text('Стрижка'), findsOneWidget);
        expect(find.text('750 ₴'), findsOneWidget);
        // i18n-finder-ok: DurationMinutes.format's "хв" suffix is business
        // formatting (mirrors the grandfathered assertion in
        // services_list_screen_test.dart), not AppLocalizations UI copy.
        expect(find.text('45 хв'), findsOneWidget);

        // Structural proof of "not tappable": no GestureDetector wraps the
        // card's content at all. Flipping `onEdit: null` to `onEdit: () {}`
        // (mutation check 3) attaches one and turns this RED.
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'a null onEdit must mean no gesture recognition at all, not a '
              'GestureDetector whose handlers no-op — the disabled-not-hidden '
              'failure D3 forbids',
        );

        // Rendered semantics (not a widget field) agree: not a button.
        // `getSemantics` walks UPWARD from the found render object, so it
        // must be pointed at the card's own `Semantics` widget directly —
        // not at the `ServiceCard` key several layers above it — or it
        // silently resolves an ancestor's (unrelated) node instead.
        final SemanticsNode semantics = tester.getSemantics(
          find
              .descendant(of: cardFinder, matching: find.byType(Semantics))
              .first,
        );
        expect(semantics.getSemanticsData().flagsCollection.isButton, isFalse);

        // The edit-pencil pillow is itself a write affordance — leaving it
        // visible on a non-tappable card would "invite a tap that goes
        // nowhere" exactly like a disabled FAB. It must be gone too, not
        // merely non-functional underneath it.
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byIcon(Icons.edit_outlined),
          ),
          findsNothing,
          reason: 'a null onEdit must hide the edit-pencil pillow too',
        );

        // Attempting the tap is harmless and produces no crash; there is
        // simply nothing there to receive it.
        await tester.tap(cardFinder, warnIfMissed: false);
        await tester.pump();
      },
    );

    testWidgets(
      'onEdit: non-null — unchanged: GestureDetector present, tap fires the '
      'callback, button semantics reported',
      (tester) async {
        int taps = 0;
        await tester.pumpApp(
          ServiceCard(
            key: const Key('service_card_svc-001'),
            service: _stubService,
            onEdit: () => taps++,
          ),
        );
        // fixed-wait-ok: draining ServiceCard's own 460ms staggered-entrance
        // AnimationController — see the sibling test above.
        await tester.pump(const Duration(milliseconds: 500));

        final Finder cardFinder = find.byKey(const Key('service_card_svc-001'));
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byType(GestureDetector),
          ),
          findsOneWidget,
        );
        // Unchanged — the edit-pencil pillow still renders for a tappable
        // card, exactly as before this phase.
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byIcon(Icons.edit_outlined),
          ),
          findsOneWidget,
        );

        final SemanticsNode semantics = tester.getSemantics(
          find
              .descendant(of: cardFinder, matching: find.byType(Semantics))
              .first,
        );
        expect(semantics.getSemanticsData().flagsCollection.isButton, isTrue);

        await tester.tap(cardFinder);
        await tester.pump();
        expect(taps, 1, reason: 'a non-null onEdit must still fire on tap');
      },
    );
  });
}
