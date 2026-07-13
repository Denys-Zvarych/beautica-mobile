// Regression — pins the EXACT `scheduleDiscreteTimesWindowSummary` copy in both
// locales.
//
// `scheduleDiscreteTimesWindowSummary` is the summary line that enumerates the
// discrete bookable start times of an EXPLICIT_TIMES («Окремі години») day —
// rendered on BOTH the schedule editor (`DiscreteTimesEditor` window summary)
// and the read-only day panel (`master_schedule_screen._dayPanel`). It
// deliberately REPLACED a misleading min–max window («Вікно 09:00 - 09:00» /
// «Робочий день: 09:00–09:00») with an enumerated list. The key is a template
// with a `{times}` placeholder, so a silent revert of the ARB wording would not
// be caught by any test that keys off the identifier.
//
// This file loads `AppLocalizations` for each supported locale and pins the
// resolved template (via a sample argument) to the exact approved text. If the
// copy is intentionally changed, THIS is the single place to update.
//
// Pattern mirrors `weekly_editor_active_window_hint_copy_test.dart`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
// Resolved with a representative multi-time argument so both the fixed prefix
// and the `{times}` interpolation position are pinned.
const String _sampleTimes = '09:00, 11:00';
const String _ukSummary = 'Запис можливий в години: 09:00, 11:00';
const String _enSummary = 'Booking available at: 09:00, 11:00';

Future<AppLocalizations> _loadL10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
  return l10n;
}

void main() {
  testWidgets(
    'uk locale resolves scheduleDiscreteTimesWindowSummary to the exact '
    'approved enumerated copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.scheduleDiscreteTimesWindowSummary(_sampleTimes),
        _ukSummary,
        reason:
            'the Ukrainian discrete-hours summary is deliberate — it replaced '
            'the misleading min–max window; a silent revert must fail here',
      );
    },
  );

  testWidgets(
    'en locale resolves scheduleDiscreteTimesWindowSummary to the exact '
    'approved enumerated copy (parity-lock)',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.scheduleDiscreteTimesWindowSummary(_sampleTimes),
        _enSummary,
        reason:
            'the English discrete-hours summary must stay in parity-lock with '
            'the Ukrainian wording — a silent revert or re-word must fail here',
      );
    },
  );
}
