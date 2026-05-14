// Phase 1.3 — Ukrainian plural correctness check.
//
// Validates that the ICU plural in `app_uk.arb#calendarBookingsForDay`
// resolves to the right cyrillic word-form for each count category:
//   =0   → "Немає записів"
//   =1   → "1 запис"
//   few  → "{count} записи"   (count ∈ {2, 3, 4, 22, 23, 24, …})
//   many → "{count} записів"  (count ∈ {0, 5..20, 25..30, …})
//   other→ "{count} записів"
//
// Pumps a bare `MaterialApp` forced to `uk_UA`, grabs the generated
// `AppLocalizations` instance via a `Builder`, then asserts the strings.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ukrainian plural picks the right form for each count', (
    WidgetTester tester,
  ) async {
    late AppLocalizations l10n;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uk', 'UA'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            l10n = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // =0 explicit case.
    expect(l10n.calendarBookingsForDay(0), 'Немає записів');
    // =1 explicit case.
    expect(l10n.calendarBookingsForDay(1), '1 запис');
    // `few` — 2/3/4 → "записи".
    expect(l10n.calendarBookingsForDay(3), '3 записи');
    // `many` — 5..20 → "записів".
    expect(l10n.calendarBookingsForDay(5), '5 записів');
  });
}
