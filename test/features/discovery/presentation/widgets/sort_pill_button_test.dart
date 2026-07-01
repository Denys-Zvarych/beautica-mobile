// Search-page change (item 1) — widget tests for [SortPillButton].
//
// The sort control was made ICON-ONLY (the active sort label was moved out of
// the top bar into the sheet's checked row) so the «Результати» top bar never
// wraps to a second line when the active sort label is long. This pins:
//   • the control renders a single icon (swap_vert) and NO inline sort-label
//     Text — so the bar layout can never reflow on a long label;
//   • the active sort is still exposed to assistive tech via the Semantics
//     `value` (so a screen reader announces «Сортування: За рейтингом») —
//     the a11y affordance must NOT regress when the visible label is removed.
//
// Finders are key/type-based; the sort label is asserted only as the Semantics
// VALUE (resolved via the l10n getter), never as on-screen body text.

import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/sort_options_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SortPillButton)));

void main() {
  testWidgets('renders icon-only — a swap_vert icon and NO inline sort label', (
    tester,
  ) async {
    await tester.pumpApp(
      Scaffold(
        body: SortPillButton(
          activeSort: SearchSort.ratingDesc,
          onSelected: (_) {},
        ),
      ),
    );

    final l10n = _l10n(tester);

    // The control is keyed and present.
    expect(find.byKey(const Key('results_sort_button')), findsOneWidget);
    // It renders the swap-vert icon …
    expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
    // … and does NOT render the active sort label as inline body Text (the
    // label lives in the sheet, not the bar — item 1).
    expect(
      find.text(l10n.searchSortRatingDesc),
      findsNothing,
      reason:
          'the active sort label must NOT render inline in the icon-only '
          'control — only inside the sort sheet.',
    );
  });

  testWidgets('exposes the active sort via the Semantics value', (
    tester,
  ) async {
    await tester.pumpApp(
      Scaffold(
        body: SortPillButton(
          activeSort: SearchSort.priceAsc,
          onSelected: (_) {},
        ),
      ),
    );

    final l10n = _l10n(tester);

    // The Semantics node carries the active sort label as its accessible value
    // (button label + value «Сортування: Спочатку дешевші»), so a screen reader
    // still announces the ordering even though it is not drawn inline.
    final SemanticsNode node = tester.getSemantics(
      find.byKey(const Key('results_sort_button')),
    );
    expect(node.value, equals(l10n.searchSortPriceAsc));
    expect(
      node.label,
      equals(l10n.searchSortButtonLabel),
      reason: 'the control keeps its accessible button label',
    );
  });
}
