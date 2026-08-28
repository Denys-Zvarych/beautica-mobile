// Phase 21.8 QA follow-up — widget tests for [SalonShellTabPlaceholder].
//
// The two shell tabs with no real host screen yet («Записи» / «Профіль»)
// render this "coming soon" body. Previously untested at all: it is a
// StatelessWidget so a text-render smoke test is enough to pin its contract
// (icon + title + blurb render, no navigation/AppBar chrome of its own —
// the shell's own bottom nav is the only navigation surface).
//
// Test fixture strings are deliberately plain ASCII, not the real ARB
// Ukrainian copy — this widget takes [title]/[blurb] as raw caller-supplied
// strings (see its own doc: it is NOT `AppLocalizations`-aware itself), so
// asserting pass-through behaviour with ANY string proves the same contract
// without a Cyrillic `find.text()` (mobile-qa M2 / `forbid_cyrillic_finder`).

import 'package:beautica_mobile/features/salon/presentation/widgets/salon_shell_tab_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('renders the icon, title, and blurb it is given', (tester) async {
    await tester.pumpApp(
      const SalonShellTabPlaceholder(
        icon: Symbols.calendar_month_rounded,
        title: 'Bookings coming soon',
        blurb: 'The salon-wide booking schedule will appear here.',
      ),
    );

    expect(find.byIcon(Symbols.calendar_month_rounded), findsOneWidget);
    expect(find.text('Bookings coming soon'), findsOneWidget);
    expect(
      find.text('The salon-wide booking schedule will appear here.'),
      findsOneWidget,
    );
    // No AppBar / Scaffold action chrome of its own — the shell's bottom nav
    // is the only navigation surface. This placeholder is meant to sit
    // INSIDE a body area, never own a Scaffold.
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('renders a DIFFERENT icon/title/blurb for a second tab '
      '(no hard-coded content)', (tester) async {
    await tester.pumpApp(
      const SalonShellTabPlaceholder(
        icon: Symbols.person_rounded,
        title: 'Profile coming soon',
        blurb: 'Your own salon profile will appear here.',
      ),
    );

    expect(find.byIcon(Symbols.person_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.calendar_month_rounded), findsNothing);
    expect(find.text('Profile coming soon'), findsOneWidget);
  });
}
