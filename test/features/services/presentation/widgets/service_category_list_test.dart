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
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

  // ---------------------------------------------------------------------------
  // ServiceCard.showPhoto — the additive leading-well opt-out.
  //
  // The pair is what makes the additive change honest. [ServiceCard] is
  // SHARED (the services management page and the master booking wizard's
  // service picker both render it), so the parameter's DEFAULT is the whole
  // contract: a caller that says nothing must keep the 40 dp well it always
  // had. Only `showPhoto: false` may drop it — together with the gap that
  // follows it, which is the other half of the 50 dp the management page
  // reclaims. A default flipped to `false` turns the first test RED; a
  // half-applied opt-out that drops the well but keeps its 10 dp gap turns
  // the width assertion in the second RED.
  // ---------------------------------------------------------------------------

  group('ServiceCard — showPhoto (leading well opt-out)', () {
    /// Lays the card out at a fixed width so the two cases are directly
    /// comparable: the name column's width is the ONLY thing under test.
    Future<double> pumpAndMeasureInfoWidth(
      WidgetTester tester, {
      required bool showPhoto,
    }) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 312,
            child: ServiceCard(
              key: const Key('service_card_svc-001'),
              service: _stubService,
              onEdit: () {},
              showPhoto: showPhoto,
            ),
          ),
        ),
      );
      // fixed-wait-ok: draining ServiceCard's own 460ms staggered-entrance
      // AnimationController — see the sibling group above.
      await tester.pump(const Duration(milliseconds: 500));
      return tester
          .renderObject<RenderBox>(
            find.descendant(
              of: find.byKey(const Key('service_card_svc-001')),
              matching: find.byType(ServiceInfo),
            ),
          )
          .size
          .width;
    }

    testWidgets(
      'DEFAULT (parameter omitted) still renders the leading PhotoThumbnail — '
      'every caller that predates showPhoto is unaffected',
      (tester) async {
        await tester.pumpApp(
          ServiceCard(
            key: const Key('service_card_svc-001'),
            service: _stubService,
            onEdit: () {},
          ),
        );
        // fixed-wait-ok: see above.
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.descendant(
            of: find.byKey(const Key('service_card_svc-001')),
            matching: find.byType(PhotoThumbnail),
          ),
          findsOneWidget,
          reason:
              'showPhoto must default to true: the booking-wizard picker '
              'passes nothing and must keep its leading well',
        );
      },
    );

    testWidgets(
      'showPhoto: false drops the well AND its gap — the name column gains '
      'exactly 50 dp (40 well + 10 gap)',
      (tester) async {
        final double withWell = await pumpAndMeasureInfoWidth(
          tester,
          showPhoto: true,
        );
        final double withoutWell = await pumpAndMeasureInfoWidth(
          tester,
          showPhoto: false,
        );

        expect(
          find.descendant(
            of: find.byKey(const Key('service_card_svc-001')),
            matching: find.byType(PhotoThumbnail),
          ),
          findsNothing,
        );
        // Measured from the laid-out render tree, not from widget fields: a
        // `PhotoThumbnail` removed while its SizedBox gap stayed behind would
        // satisfy the finder above and still fail here.
        expect(
          withoutWell - withWell,
          50.0,
          reason:
              'the opt-out must reclaim the 40 dp well AND the 10 dp gap that '
              'followed it, not just the well',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // ServiceCard — the edit action verb inside the accessibility label.
  //
  // The verb used to be the raw literal `'Редагувати'` interpolated straight
  // into `Semantics(label:)`. `scripts/forbid_raw_ui_strings.sh` cannot see
  // that shape (a literal inside a conditional expression inside an
  // interpolation), so all 26 guards stayed green while an EN screen-reader
  // user heard a Ukrainian verb — `app_en.arb` is live.
  //
  // ASSERTION SHAPE MATTERS. Pinning the label against the Ukrainian string
  // would pass identically before and after the fix, because UK is the default
  // test locale AND the old hard-coded value. So:
  //   • the UK case resolves `l10n.servicesCardEditSemanticVerb` from the
  //     PUMPED locale rather than restating a literal, and
  //   • the EN case — the one that is actually broken today — pins the English
  //     verb and asserts the Ukrainian one is ABSENT.
  // Both read the rendered SemanticsNode, never a widget field.
  // ---------------------------------------------------------------------------

  group('ServiceCard — localized edit verb in the semantics label', () {
    /// Pumps a tappable card at [locale] and returns
    /// `(renderedSemanticsLabel, resolvedVerbForThatLocale)`.
    Future<(String, String)> pumpAndReadLabel(
      WidgetTester tester, {
      required Locale locale,
    }) async {
      await tester.pumpApp(
        ServiceCard(
          key: const Key('service_card_svc-001'),
          service: _stubService,
          onEdit: () {},
        ),
        locale: locale,
      );
      // fixed-wait-ok: draining ServiceCard's own 460ms staggered-entrance
      // AnimationController — see the sibling tests above.
      await tester.pump(const Duration(milliseconds: 500));

      final Finder cardFinder = find.byKey(const Key('service_card_svc-001'));
      // Same targeting rule as the sibling tests: `getSemantics` walks UPWARD,
      // so it must be pointed at the card's own `Semantics` widget.
      final SemanticsNode node = tester.getSemantics(
        find.descendant(of: cardFinder, matching: find.byType(Semantics)).first,
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(cardFinder),
      );
      // The resolved node MERGES its descendants, so `node.label` is the
      // card's own announcement followed by newline-separated child labels
      // ("Стрижка", "45 хв", "750 ₴" — the Text widgets inside it). The first
      // line is exactly the string `ServiceCard` passes to `Semantics(label:)`,
      // which is what is under test.
      return (node.label.split('\n').first, l10n.servicesCardEditSemanticVerb);
    }

    testWidgets('uk — the verb comes from AppLocalizations, not a literal', (
      tester,
    ) async {
      final (String label, String verb) = await pumpAndReadLabel(
        tester,
        locale: const Locale('uk'),
      );

      expect(
        label,
        endsWith(verb),
        reason:
            'the tappable card must append the ARB-sourced edit verb resolved '
            'from the pumped locale',
      );
      // Positive half: the label is the full announcement, not just the verb.
      expect(label, startsWith('Стрижка. 45 хв, 750 ₴.'));
    });

    testWidgets(
      'en — an English screen reader hears an English verb (the bug this '
      'closes), with no Ukrainian left in the label',
      (tester) async {
        final (String label, String verb) = await pumpAndReadLabel(
          tester,
          locale: const Locale('en'),
        );

        // Guards against a regression that swaps the hard-coded Ukrainian verb
        // for a hard-coded English one: the expected value is read from the EN
        // locale's own AppLocalizations, and separately pinned to 'Edit' so a
        // blanked-out ARB value cannot make `endsWith` vacuously true.
        expect(verb, 'Edit');
        expect(
          label,
          endsWith('Edit'),
          reason:
              'under Locale("en") the edit affordance must be announced in '
              'English — the raw literal made this say "Редагувати"',
        );
        expect(
          label.contains('Редагувати'),
          isFalse,
          reason:
              'no Ukrainian verb may survive into an English semantics label',
        );
      },
    );
  });
}
