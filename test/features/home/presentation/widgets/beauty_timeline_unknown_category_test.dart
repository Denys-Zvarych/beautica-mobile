// mobile-qa gap-closure (2026-08-27) — MEDIUM finding: the BEAUTY TIMELINE
// rail painted the cosmetology icon on genuinely-uncategorised entries.
//
// ROOT CAUSE
// ----------
// `_TimelineNode.build` (`beauty_timeline_section.dart`) called
// `categoryIconFor` — the never-null variant — which falls through to the
// cosmetology fallback for any slug/name it doesn't recognise. The timeline
// endpoint (`GET /clients/me/timeline`) uses the literal string `"UNKNOWN"`
// as its no-category sentinel (see `timeline_mapper.dart`'s drop-policy
// header), not null or empty, so `TimelineMapper`'s drop rule keeps the row
// and `categoryIconFor('UNKNOWN', 'UNKNOWN')` matched neither the slug
// switch nor any Ukrainian substring — landing on the cosmetology fallback.
//
// FIX
// ---
// The call site now uses `categoryIconOrNullFor` and renders no `AppIcon`
// child when it returns null, while the medallion `Container` keeps its
// explicit 52×52 size (`height`/`width: BeautyTimelineSection._medallion`)
// regardless of whether it has a child — so the rail's geometry never
// shifts. `"UNKNOWN"` is normalised to null at the call site (a private
// `_undoUnknownSentinel` helper in `beauty_timeline_section.dart`), NOT
// inside the shared `categoryIconOrNullFor` resolver — see that helper's
// doc comment for why: `"UNKNOWN"` is this one endpoint's convention, and
// the resolver is shared by callers (`search_filters_screen.dart`,
// `booking_card.dart`, the service-category pickers) that don't speak it.
//
// This test is deliberately NOT a golden: it measures, per the project's
// "goldens are not acceptance for a visual bug" rule and the documented
// `AnimatedScale`/`Container.alignment` trap where a `size:` field read
// stayed green while the actual layout was clobbered. Every assertion here
// reads `tester.getSize()`, never a constructor field.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One genuinely-uncategorised entry (the backend's literal `"UNKNOWN"`
/// sentinel on both fields — the shape `TimelineMapper` actually produces
/// when `categoryName` is absent and `categoryKey` is `"UNKNOWN"`, since
/// `TimelineMapper.fromDtoList` falls back to `categoryKey` for the caption
/// when `categoryName` is null/empty) and one genuinely-categorised entry,
/// so the same pump proves both "no wrong icon" and "a real category still
/// resolves".
const List<TimelineEntry> _entries = <TimelineEntry>[
  TimelineEntry(
    category: 'UNKNOWN',
    categoryKey: 'UNKNOWN',
    dateLabel: 'сб, 20 чер',
  ),
  TimelineEntry(
    category: 'Брови',
    categoryKey: 'BROWS',
    dateLabel: 'пн, 18 чер',
  ),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('uk'),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: BeautyTimelineSection(entries: _entries),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The medallion `Container`s — identified the same way the rail's golden
/// test does (`shape: BoxShape.circle`), so this stays a real regression
/// guard against the rejected `borderRadius` variant too, not a
/// `find.byType(Container)` count that would also catch unrelated
/// Containers elsewhere in the tree.
List<Container> _medallions(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where(
      (Container c) =>
          c.decoration is BoxDecoration &&
          (c.decoration! as BoxDecoration).shape == BoxShape.circle,
    )
    .toList();

void main() {
  testWidgets('an "UNKNOWN" entry renders NO icon, while the medallion still '
      'reserves its exact 52dp footprint', (tester) async {
    await _pump(tester);

    final List<Container> medallions = _medallions(tester);
    expect(
      medallions.length,
      _entries.length,
      reason:
          'both tiles — the UNKNOWN one and the real one — must still '
          'render a medallion Container; the null-icon fix must not '
          'drop the medallion itself',
    );

    for (final Container medallion in medallions) {
      final Size measured = tester.getSize(find.byWidget(medallion));
      expect(
        measured,
        const Size(52.0, 52.0),
        reason:
            'the medallion must keep its exact 52dp footprint whether '
            'or not it has an icon child, so the rail layout never '
            'shifts for an uncategorised entry',
      );
    }

    // Exactly ONE AppIcon in the whole rail — the real "Брови" tile's.
    // The "UNKNOWN" tile must contribute zero.
    final List<Element> iconElements = find.byType(AppIcon).evaluate().toList();
    expect(
      iconElements.length,
      1,
      reason:
          'the UNKNOWN entry must render no AppIcon at all (previously '
          'fell through to the cosmetology glyph); the real BROWS '
          'entry must still render exactly one',
    );

    final Size iconSize = tester.getSize(
      find.byWidget(iconElements.single.widget),
    );
    expect(
      iconSize,
      const Size(39.0, 39.0),
      reason:
          'the real category icon must still be laid out at its '
          'documented 39dp size — proves the fix did not also swallow '
          'genuine categories',
    );
  });
}
