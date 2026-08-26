// Phase 110 Part 2 — BEAUTY TIMELINE rail golden (mobile-qa gap-closure).
//
// WHY THIS FILE EXISTS
// ---------------------
// `test/golden/` had NO golden rendering [BeautyTimelineSection] before this
// file, despite this change being materially pixel-visible: tile width
// 84→100dp, rail height 108→118dp, category caption 1→2 lines, medallion SVG
// glyph 26→36dp (replacing a Material font glyph entirely). The only prior
// proof was `home_hub_overflow_test.dart`'s `takeException()==null` guard,
// which only proves the layout doesn't RenderFlex-overflow — it says nothing
// about whether the caption is legible, whether the icon is the right size,
// or whether the two-line wrap actually happens instead of coincidentally
// fitting on one line.
//
// GOLDENS ARE NOT ACCEPTANCE FOR THIS VISUAL CHANGE
// ---------------------------------------------------
// A freshly generated golden baseline is self-referential: it photographs
// whatever the widget currently draws, bug included. It cannot by itself
// prove the current output is CORRECT — only that a FUTURE regression will
// show up as a pixel diff against today's (asserted-correct-by-other-means)
// snapshot. The confidence that today's baseline is actually the intended
// Part 2 shape comes from the NON-golden, measured assertions in the first
// `testWidgets` group below (caption line count via `TextPainter`, icon size
// via the pumped `AppIcon.size` field) — not from alchemist's byte-diff, and
// not from eyeballing the PNG. Those same measured assertions are ALSO
// pinned end to end against real FakeBackend data in
// `integration_test/client_home_hub_flow_test.dart`'s two Phase 110 Part 2
// tests, so this golden's baseline is corroborated from two independent,
// non-golden angles before it is trusted as a regression guard.
//
// COVERAGE
// --------
// One 2-tile rail: a short caption («Брови») and the documented binding
// long-caption case («Ін'єкційна косметологія» — see
// `beauty_timeline_section.dart`'s `_tileWidth` doc comment for why this
// exact string is the binding constraint that drove the 84→100dp resize), at
// {1.0, 1.3} textScale — the accessibility ceiling `main.dart` clamps to,
// and the exact matrix `home_hub_overflow_test.dart`'s bug lived in.
//
// SVG ICON LAYER — GAP-CLOSURE (mobile-qa, 2026-08-26)
// -------------------------------------------------------
// A MEDIUM finding from an earlier chain read: "these goldens have zero
// pixel coverage of the SVG icon layer" — evidence was that mutating the
// medallion `AppIcon`'s `size:` to an absurd value and regenerating produced
// a byte-identical PNG. The working diagnosis at the time was that
// `SvgPicture.asset` doesn't resolve within a single `goldenTest` pump
// cycle. That diagnosis was WRONG: direct measurement showed the SVG paints
// fine under plain `pumpAndSettle` (confirmed by sampling non-background
// pixel colours in the medallion region, with and without an added
// `vg.waitForPendingDecodes()` step — identical either way).
//
// The real cause was a layout bug: the 64×64 medallion `Container` in
// `_TimelineNode` had no `alignment`, so its tight `BoxConstraints` forced
// ANY child to render at 64×64 regardless of size requested — `size: 8` and
// `size: 32` were laid out IDENTICALLY (both clobbered to 64dp), which is
// exactly what produced the byte-identical golden. Fixed with
// `alignment: Alignment.center` on that `Container` (see its comment there
// for the `tester.getSize()` proof: 64×64 → 32×32).
//
// Post-fix, the golden DOES have real, mutation-proven SVG pixel coverage:
//   HEAD (size 32, no alignment — pre-fix, clobbered to 64dp):
//     360_1x sha256 c233abb2ec501e57d19e8199acb4e7b045b9781277c911931d82f9acab9bb050
//   Fixed layout, size 32 (superseded — no longer this baseline):
//     360_1x sha256 54a497eb66d01ab4667cfc9a0c2800fde546788057125c862659079c1bc28d8a
//   Fixed layout, size 8 (mutation probe — differs from the line above):
//     360_1x sha256 dcf488c85ae1640d4b4d6559927f5c2c7c37cbdc9f0d05f535e8ac100dff59bd
//
// The `AppIcon.size` field assertion in the first `testWidgets` group below
// is ALSO vacuous in the same way the golden mutation was — it reads the
// widget's constructor field, not what actually got laid out, so it could
// not have caught this bug either. A second measured test
// ("...is actually LAID OUT at 48dp...") asserts `tester.getSize()` instead;
// removing `alignment: Alignment.center` reddens BOTH that test (medallion
// clobbered back to 64×64, not 48×48) AND both goldens below, proving both
// are load-bearing against this exact regression.
//
// SIZE RAISED 32 → 48dp (2026-08-26, same day as the alignment fix above):
// with `alignment: Alignment.center` finally making `size:` take effect,
// the user was actually looking at 64dp icons (the alignment bug's clobber)
// when asking for "a little bit smaller" — 48dp is a deliberate 25%
// reduction from that 64dp, not from the never-rendered 32dp value. This
// baseline's bytes MUST differ from the size-32 hash recorded above.
//
// `vg.waitForPendingDecodes()` stays wired into `helpers/golden_pump.dart`
// regardless — see that file's header for why it's kept as a free,
// package-documented safety net even though it wasn't the operative fix
// here.
//
// DISC-MATCH RESIZE, SAME DAY (2026-08-26, follow-up product decision):
// "just make circles same as search button circle" was a SIZE-only request
// — the medallion shrank to the search disc's exact size, 52dp (was 64dp).
// A same-day pass additionally copied the disc's gradient face, dual shadow,
// bevel sheen and cream icon tint; that colour/material copy was reverted on
// user instruction ("its mean make CYRCLE SIZE, but u changed the collor").
// The medallion is back to its own flat translucent fill + hairline border,
// with a dark `accentDeep` icon at 39dp (`48 × 52/64` — preserving the
// approved 48dp-in-64dp ratio at the new 52dp size). Both baselines below
// MUST move (52dp circle, 39dp icon) — see `beauty_timeline_section.dart`'s
// own file header for the full rationale.
//
// GAP: NOTHING PINNED THE MATERIAL ITSELF (mobile-qa, 2026-08-26)
// -------------------------------------------------------------------------
// Every non-golden assertion up to this point (and the two end-to-end ones
// in `integration_test/client_home_hub_flow_test.dart`) pins the medallion's
// SIZE — `AppIcon.size` field, `tester.getSize()`, `_medallion`/
// `_railHeight` constants (via `home_hub_overflow_test.dart`). None of them
// ever read `BoxDecoration.gradient`/`.boxShadow`/`.color`/`.border`, or
// `AppIcon.color`. That is exactly the axis the reverted colour-copy
// (`0e1fd939`) broke and the axis this golden's PNG bytes alone cannot be
// trusted to guard (see "GOLDENS ARE NOT ACCEPTANCE" above) — a byte diff
// proves SOMETHING changed, never WHAT. The
// "medallion decoration is FLAT VelvetTouch" group below closes that gap
// with measured, non-golden assertions on the decoration and icon tint,
// mutation-proven against both a re-added gradient/shadow (presence) and a
// re-added bevel/icon-size copy (geometry) — see that group's own comment.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

const String _longCaption = "Ін'єкційна косметологія";

const List<TimelineEntry> _entries = <TimelineEntry>[
  TimelineEntry(
    category: 'Брови',
    categoryKey: 'BROWS',
    dateLabel: 'пн, 18 чер',
  ),
  TimelineEntry(
    category: _longCaption,
    categoryKey: 'INJECTION_COSMETOLOGY',
    dateLabel: 'сб, 20 чер',
  ),
];

/// Hosts the rail on the brand base, matching the on-screen home-hub context.
Widget _host(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: BeautyTimelineSection(entries: _entries),
    ),
  ),
);

void main() {
  // ── Ground truth: non-golden, measured assertions ─────────────────────────
  //
  // These are the assertions this golden's confidence actually rests on (see
  // the file header). Deliberately independent of alchemist/goldenTest —
  // plain pumpWidget + TextPainter/widget-field introspection.
  group('BeautyTimelineSection — measured ground truth (not golden)', () {
    testWidgets(
      'the long caption «Ін\'єкційна косметологія» genuinely wraps to 2 '
      'lines at textScale 1.0, not merely non-overflowing',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(body: _host(360)),
          ),
        );
        await tester.pumpAndSettle();

        final Finder captionFinder = find.text(_longCaption);
        expect(captionFinder, findsOneWidget);

        final Finder tileBox = find
            .ancestor(of: captionFinder, matching: find.byType(SizedBox))
            .first;
        final double measuredTileWidth = tester.getSize(tileBox).width;

        final Text captionWidget = tester.widget<Text>(captionFinder);
        final TextPainter probe = TextPainter(
          text: TextSpan(text: _longCaption, style: captionWidget.style),
          textDirection: TextDirection.ltr,
          maxLines: captionWidget.maxLines,
        )..layout(maxWidth: measuredTileWidth);

        expect(
          probe.didExceedMaxLines,
          isFalse,
          reason:
              'the full caption must fit within maxLines at the measured '
              'tile width — a truncation regression would exceed',
        );
        expect(
          probe.computeLineMetrics().length,
          2,
          reason:
              'this is the documented binding case that NEEDS 2 lines at '
              'the current tile width (100dp) — 1 line would mean the '
              'golden below is no longer exercising the Part 2 wrap '
              'contract',
        );
      },
    );

    testWidgets('the medallion AppIcon renders at the current size (39dp), the '
        'approved 48-in-64dp ratio re-derived for the 52dp medallion — not '
        'the retired 26/36/32/48/22dp values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(body: _host(360)),
        ),
      );
      await tester.pumpAndSettle();

      final Iterable<AppIcon> icons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .where((AppIcon icon) => icon.size == 39.0);
      expect(
        icons.length,
        _entries.length,
        reason:
            'every one of the ${_entries.length} rendered tiles must '
            'carry a 39dp medallion AppIcon',
      );
    });

    testWidgets(
      'the medallion AppIcon is actually LAID OUT at 39dp, not merely '
      'configured with size: 39 (colour-copy revert, 2026-08-26)',
      (tester) async {
        // The assertion above reads `AppIcon.size` — the constructor field —
        // which is set correctly regardless of what the surrounding layout
        // does with it. It cannot catch a layout bug that silently overrides
        // the requested size. That bug was real here once already: the
        // 64×64 medallion `Container` had no `alignment`, so its tight
        // BoxConstraints forced ANY child to render at 64×64 regardless of
        // the value passed. `alignment: Alignment.center` on the Container
        // (see `beauty_timeline_section.dart`) fixed it, and the icon is now
        // a plain 39×39 `AppIcon` directly under that Container (the
        // gradient/shadow/bevel Stack+SizedBox wrapper a same-day pass added
        // was reverted). This test pins the FIX via the one signal that
        // can't be fooled the same way — the actual laid-out size — so a
        // regression (e.g. someone removing `alignment` again) fails here
        // even if `AppIcon.size` still reads 39.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(body: _host(360)),
          ),
        );
        await tester.pumpAndSettle();

        final List<Element> iconElements = find
            .byType(AppIcon)
            .evaluate()
            .toList();
        expect(iconElements.length, _entries.length);

        for (final Element element in iconElements) {
          final Size renderedSize = tester.getSize(
            find.byWidget(element.widget),
          );
          expect(
            renderedSize,
            const Size(39.0, 39.0),
            reason:
                'the medallion icon must actually PAINT at 39×39 — a '
                'different result here means the Container alignment fix '
                'regressed and the icon is silently mis-sized inside the '
                'medallion again',
          );
        }
      },
    );
  });

  // ── Regression: colour/material copy revert (0e1fd939) ─────────────────
  //
  // The bug this group exists to catch: a same-day pass matched the
  // timeline medallion's SIZE to the client bottom-nav search disc (as
  // asked) but ALSO copied that disc's MATERIAL — camel→mocha
  // `VelvetGradients.accentDiscFace` gradient, dual extruded
  // `VelvetShadows.extrudedDiscAccent` boxShadow, an `accentDiscBevel`
  // sheen layer, and flipped the icon tint dark `accentDeep` → cream
  // `BrandColors.white` so it would read against the now-dark gradient.
  // The user explicitly rejected the colour change ("its mean make CYRCLE
  // SIZE, but u changed the collor - revert it and fix as expected!") — see
  // `beauty_timeline_section.dart`'s file header for the full history.
  //
  // Every other assertion in this file (and in
  // `integration_test/client_home_hub_flow_test.dart`) only ever reads
  // SIZE — `AppIcon.size`, `tester.getSize()`. None of them would have
  // caught the colour regression, and none would catch it coming back.
  // These are the ones that would have.
  group('BeautyTimelineSection medallion decoration is FLAT VelvetTouch '
      '(colour-copy revert, 2026-08-26)', () {
    testWidgets('the medallion Container decoration carries no gradient and no '
        'boxShadow, and uses the flat translucent fill + hairline border', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(body: _host(360)),
        ),
      );
      await tester.pumpAndSettle();

      // Scoped to `shape: BoxShape.circle` decorations specifically: the
      // rejected colour-copy variant used `borderRadius: BorderRadius
      // .circular(26)` with `shape` left at its rectangle default, so this
      // predicate would find ZERO containers against that variant instead
      // of silently matching the wrong shape — see the mutation table.
      final List<Container> medallions = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (Container c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).shape == BoxShape.circle,
          )
          .toList();

      expect(
        medallions.length,
        _entries.length,
        reason:
            'every one of the ${_entries.length} rendered tiles must '
            'carry exactly one shape:BoxShape.circle medallion Container '
            '— a count below this means the decoration no longer uses '
            '`shape: BoxShape.circle` (e.g. reverted to the rejected '
            '`borderRadius` variant)',
      );

      for (final Container medallion in medallions) {
        final BoxDecoration decoration = medallion.decoration! as BoxDecoration;

        expect(
          decoration.gradient,
          isNull,
          reason:
              'the reverted colour-copy pass (0e1fd939) set `gradient: '
              'VelvetGradients.accentDiscFace` here — the flat medallion '
              'must carry NO gradient',
        );
        expect(
          decoration.boxShadow,
          isNull,
          reason:
              'the reverted pass set `boxShadow: '
              'VelvetShadows.extrudedDiscAccent` here — the flat '
              'medallion must carry NO boxShadow (also required by '
              '`impeller_circle_shadow_guard_test.dart`, since this '
              'decoration keeps `shape: BoxShape.circle`)',
        );
        expect(
          decoration.borderRadius,
          isNull,
          reason:
              'the reverted pass used `borderRadius: BorderRadius.'
              'circular(26)` (with `shape` left at its rectangle '
              'default) instead of `shape: BoxShape.circle` — the flat '
              'medallion must carry neither',
        );
        expect(
          decoration.color,
          BrandColors.white.withValues(alpha: 0.5),
          reason:
              'flat VelvetTouch fill — must not be null/transparent '
              '(the gradient-face variant carried no solid `color` at '
              'all)',
        );
        expect(
          decoration.border,
          Border.all(
            color: BrandColors.accent.withValues(alpha: 0.55),
            width: 1.4,
          ),
          reason:
              'the hairline border is the flat medallion\'s only '
              'edge treatment — the gradient-face variant had none',
        );
      }
    });

    testWidgets('the medallion AppIcon tint is the dark accentDeep, never the '
        'cream on-accent-gradient colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(body: _host(360)),
        ),
      );
      await tester.pumpAndSettle();

      final Iterable<AppIcon> icons = tester.widgetList<AppIcon>(
        find.byType(AppIcon),
      );
      expect(icons.length, _entries.length);
      for (final AppIcon icon in icons) {
        expect(
          icon.color,
          BrandColors.accentDeep,
          reason:
              'the reverted colour-copy pass set `color: BrandColors.'
              'white` (cream) here so the icon would read against the '
              'gradient face it also added — the flat medallion needs '
              'the dark tint back, since a cream icon is invisible on '
              'the flat translucent fill',
        );
      }
    });
  });

  // ── Golden ─────────────────────────────────────────────────────────────

  group('BeautyTimelineSection golden', () {
    const double width = 360;

    for (final double scale in kGoldenTextScales) {
      goldenTest(
        'beauty timeline rail ${width.toInt()}dp x$scale',
        fileName: 'beauty_timeline_rail_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 240)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _host(width),
      );
    }
  });
}
