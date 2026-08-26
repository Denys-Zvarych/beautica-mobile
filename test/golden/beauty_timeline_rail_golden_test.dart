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

    testWidgets(
      'the medallion AppIcon renders at the Part 2 size (36dp), not the '
      'retired 26dp',
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

        final Iterable<AppIcon> icons = tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .where((AppIcon icon) => icon.size == 36.0);
        expect(
          icons.length,
          _entries.length,
          reason:
              'every one of the ${_entries.length} rendered tiles must '
              'carry a 36dp medallion AppIcon',
        );
      },
    );
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
