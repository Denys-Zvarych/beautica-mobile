// Widget tests for `AddLink` (lib/shared/widgets/add_link.dart).
//
// Phase 351 (mobile-qa gap-fix, 2026-09-25) — `AddLink` was PROMOTED from the
// private `_AddLink` in `salon_management_profile_screen.dart` and picked up
// two NEW consumers (the independent master's «Додати опис»
// `master-profile-add-bio` and the salon master's
// `salon-master-profile-add-bio`) with ZERO direct widget tests. Every
// guarantee about it was inherited transitively through screen-level key
// lookups. This file proves what those screen tests structurally cannot:
//   1. The label text renders verbatim (caller-supplied, e.g. «Додати опис»).
//   2. The leading `+` glyph renders.
//   3. Tapping ANYWHERE on the row (not just the text) fires `onTap` exactly
//      once — the whole `Row` is wrapped in one opaque `GestureDetector`.
//   4. It is a `Semantics(button: true)` node carrying the label — assistive
//      tech announces it as a tappable control, not inert text.

import 'package:beautica_mobile/shared/widgets/add_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AddLink — rendering', () {
    testWidgets('renders the caller-supplied label verbatim', (tester) async {
      await tester.pumpWidget(
        _wrap(AddLink(label: 'Додати опис', onTap: () {})),
      );

      // i18n-finder-ok: asserting the exact label string passed in by the
      // caller renders verbatim, not translating UI copy ourselves.
      expect(find.text('Додати опис'), findsOneWidget);
    });

    testWidgets('renders the leading add glyph', (tester) async {
      await tester.pumpWidget(_wrap(AddLink(label: 'Додати', onTap: () {})));

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('a different label swaps the rendered text', (tester) async {
      await tester.pumpWidget(
        _wrap(AddLink(label: 'Додати посилання', onTap: () {})),
      );

      // i18n-finder-ok: asserting the exact caller-supplied label string
      // renders verbatim, not translating UI copy ourselves.
      expect(find.text('Додати посилання'), findsOneWidget);
      // i18n-finder-ok: negative check that the OTHER caller-supplied label
      // is absent — same rationale as above.
      expect(find.text('Додати опис'), findsNothing);
    });
  });

  group('AddLink — tap behaviour', () {
    testWidgets('tapping the label text fires onTap exactly once', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(AddLink(label: 'Додати опис', onTap: () => taps++)),
      );

      // i18n-finder-ok: locating the tile by its own caller-supplied label —
      // the label IS the literal passed to the constructor above, not
      // translated UI copy.
      await tester.tap(find.text('Додати опис'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets(
      'tapping the leading glyph (not the text) still fires onTap — the '
      'whole row is one opaque hit target',
      (tester) async {
        int taps = 0;
        await tester.pumpWidget(
          _wrap(AddLink(label: 'Додати опис', onTap: () => taps++)),
        );

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();

        expect(taps, 1);
      },
    );

    testWidgets('two taps fire onTap twice, not once (no debounce)', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(AddLink(label: 'Додати опис', onTap: () => taps++)),
      );

      // i18n-finder-ok: locating the tile by its own caller-supplied label.
      await tester.tap(find.text('Додати опис'));
      await tester.pump();
      // i18n-finder-ok: same tile, second tap.
      await tester.tap(find.text('Додати опис'));
      await tester.pump();

      expect(taps, 2);
    });
  });

  group('AddLink — semantics', () {
    testWidgets('is a Semantics(button: true) node carrying the label', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(AddLink(label: 'Додати опис', onTap: () {})),
        );

        // i18n-finder-ok: locating the tile by its own caller-supplied label.
        final Finder addLinkFinder = find.text('Додати опис');
        final SemanticsData data = tester
            .getSemantics(addLinkFinder)
            .getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.label, contains('Додати опис'));
      } finally {
        handle.dispose();
      }
    });
  });
}
