// Phase 221 (B) — widget tests for [ExpandableNote] in isolation.
//
// Phase 223 (a) — moved from `test/features/master/presentation/widgets/
// master_location_note_test.dart` alongside the widget's promotion to
// `lib/shared/widgets/expandable_note.dart` (renamed `MasterLocationNote` ->
// `ExpandableNote`). References below updated to match: the toggle's `Key`
// (`expandable-note-toggle`) and the l10n getters
// (`expandableNoteShowMore`/`expandableNoteShowLess`).
//
// WHY THIS FILE EXISTS
// --------------------
// The tap-to-expand affordance was previously only exercised through the full
// `MasterProfileScreen` (master_profile_screen_test.dart, group 12c/12d) — a
// slower, indirect path for a widget with a genuinely independent contract:
// clamp at `maxLines`, show a «більше»/«згорнути» toggle ONLY when the note
// actually overflows that budget, expand/collapse it on tap. This file pins
// that contract directly, PLUS the accessibility regression this audit found
// and fixed in the widget:
//
// `_measureOverflow` built its `TextPainter` WITHOUT passing the ambient
// `MediaQuery.textScalerOf(context)` — a bare `TextPainter` defaults to
// `TextScaler.noScaling`, so the overflow decision was always computed as if
// the system font scale were 1.0×, no matter what it actually was. The
// rendered `Text` itself DOES honour the ambient scaler (Flutter's `Text`
// widget always does), so a note that fits comfortably within 3 lines at
// 1.0× but genuinely needs MORE than 3 lines once the font is scaled up
// (e.g. a user with a large system accessibility text size) was silently
// clipped by `overflow: TextOverflow.ellipsis` with NO expand affordance
// EVER appearing for it — unreachable content precisely for the users who
// most need the escape hatch. `master_profile_screen_test.dart`'s existing
// textScaler-2.0 stress test could not catch this: its ~400-char fixture
// already overflows at 1.0× (the toggle already shows before scaling), so
// scaling it up further never proved the SCALE-AWARENESS of the
// measurement, only that a big note still shows a toggle at a big scale.
//
// The borderline fixture below was calibrated empirically (measured against
// the real `VelvetText.feedbackMutedNote` style at a 140dp column width): it
// fits within 3 lines at scale 1.0 (no toggle) but needs more than 3 lines at
// scale 2.0 (toggle must appear) — the exact scenario the fix targets.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/overflow_guard.dart';

/// Calibrated borderline note: fits within `maxLines: 3` at textScaler 1.0 on
/// a 140dp column, but overflows it at textScaler 2.0 (verified via a
/// throwaway diagnostic probe against the real production style before this
/// value was committed here).
const String _kBorderlineNote =
    "Вхід у двір з боку вулиці Хрещатик, кав'ярня на розі.";

/// A short note that fits within 3 lines at any reasonable scale — the
/// baseline "no toggle" case.
const String _kShortNote = 'кв. 3, 2 поверх';

/// A long note that overflows 3 lines even at textScaler 1.0 — the baseline
/// "toggle present" case (mirrors the screen-level fixture).
const String _kLongNote =
    'Вхід у двір з боку вулиці Хрещатик, повз кав\'ярню на розі — не '
    'плутайте з сусіднім під\'їздом, там кодовий замок не працює. Тримайтеся '
    'правої стіни, минаєте дитячий майданчик, підіймаєтесь трьома сходинками '
    'до скляних дверей із синьою наклейкою. Домофон код 45В, дзвоніть двічі '
    'коротко. Якщо домофон не відповідає — телефонуйте адміністратору, номер '
    'вказано на вивісці біля дверей. Кабінет на другому поверсі, одразу '
    'ліворуч від сходів, третій номер за рахунком.';

/// Stable key for the widget under test — pumping the SAME key at the SAME
/// tree position (via repeated `_pump` calls within one test) makes Flutter
/// reuse the existing `Element`/`State` and route the text change through
/// `didUpdateWidget`, rather than tearing down and remounting a fresh
/// `State` (which would trivially re-pass through `initState` instead and
/// prove nothing about the update path).
const Key _kNoteKey = Key('location-note-under-test');

Future<void> _pump(
  WidgetTester tester,
  String note, {
  double textScale = 1.0,
  double width = 140,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: ExpandableNote(key: _kNoteKey, text: note),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _toggle => find.byKey(const Key('expandable-note-toggle'));

void main() {
  // This file pumps via a bare `MaterialApp`/`tester.pumpWidget` (not the
  // `pumpApp` helper, which arms the guard automatically) — arm it explicitly
  // so a RenderFlex overflow at the narrow 140dp column width fails the test
  // loudly instead of merely being recorded by the suite-wide recorder
  // installed in `flutter_test_config.dart`.
  setUp(installOverflowGuard);

  group('ExpandableNote — baseline toggle visibility', () {
    testWidgets('a short note shows NO toggle', (tester) async {
      await _pump(tester, _kShortNote);

      expect(find.text(_kShortNote), findsOneWidget);
      expect(_toggle, findsNothing);
    });

    testWidgets('a long note (overflows at any reasonable scale) shows the '
        'toggle, collapsed by default', (tester) async {
      await _pump(tester, _kLongNote);

      expect(_toggle, findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(_toggle));
      expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
      expect(find.text(l10n.expandableNoteShowLess), findsNothing);
    });

    testWidgets('tapping the toggle expands the note and flips the label; '
        'tapping again re-collapses it', (tester) async {
      await _pump(tester, _kLongNote);

      final l10n = AppLocalizations.of(tester.element(_toggle));
      final Size collapsedSize = tester.getSize(find.text(_kLongNote));

      await tester.tap(_toggle);
      await tester.pumpAndSettle();

      expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
      expect(find.text(l10n.expandableNoteShowMore), findsNothing);
      final Size expandedSize = tester.getSize(find.text(_kLongNote));
      expect(expandedSize.height, greaterThan(collapsedSize.height));

      await tester.tap(_toggle);
      await tester.pumpAndSettle();

      expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
      final Size reCollapsedSize = tester.getSize(find.text(_kLongNote));
      expect(
        reCollapsedSize.height,
        moreOrLessEquals(collapsedSize.height, epsilon: 0.5),
      );
    });
  });

  // ── REGRESSION — ambient textScaler must feed the overflow measurement ────
  group('ExpandableNote — textScaler-aware overflow measurement '
      '(accessibility regression)', () {
    testWidgets(
      'the borderline note shows NO toggle at textScaler 1.0 (it genuinely '
      'fits within 3 lines at this scale)',
      (tester) async {
        await _pump(tester, _kBorderlineNote, textScale: 1.0);

        expect(find.text(_kBorderlineNote), findsOneWidget);
        expect(
          _toggle,
          findsNothing,
          reason:
              'sanity check on the calibrated fixture — it must NOT already '
              'overflow at 1.0x, or the 2.0x assertion below would prove '
              'nothing new',
        );
      },
    );

    testWidgets(
      'BUG FIX REGRESSION: the SAME borderline note shows the toggle at '
      'textScaler 2.0 — before the fix, `_measureOverflow` ignored the '
      'ambient MediaQuery.textScalerOf(context) and always measured as if '
      'unscaled, so this note was silently clipped with NO way to expand it '
      'at a large accessibility text scale',
      (tester) async {
        await _pump(tester, _kBorderlineNote, textScale: 2.0);

        expect(find.text(_kBorderlineNote), findsOneWidget);
        expect(
          _toggle,
          findsOneWidget,
          reason:
              'at 2.0x the note genuinely needs more than 3 lines — the '
              'toggle MUST appear so the full text stays reachable',
        );

        // The affordance is not just present but functional at this scale
        // too: tapping it must actually reveal the full note.
        final l10n = AppLocalizations.of(tester.element(_toggle));
        final Size collapsedSize = tester.getSize(find.text(_kBorderlineNote));
        await tester.tap(_toggle);
        await tester.pumpAndSettle();
        expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
        final Size expandedSize = tester.getSize(find.text(_kBorderlineNote));
        expect(expandedSize.height, greaterThan(collapsedSize.height));
      },
    );
  });

  // ── Phase 221 audit fix (mobile-security MEDIUM) — bidi/zero-width strip ──
  group('ExpandableNote — sanitizes provider-authored control chars', () {
    testWidgets(
      'a note containing a RLO (U+202E) override renders with the control '
      'character stripped, not the raw payload',
      (tester) async {
        // U+202E = Right-to-Left Override. Backend validation on
        // `locationNote` is `@Size(max = 1000)` only — no character-class
        // check — so a hostile master could push this into a client-facing
        // note. Built via `String.fromCharCode` (rather than a literal
        // character in this source file) so the test file itself never
        // embeds the raw control byte it exists to strip.
        final String rlo = String.fromCharCode(0x202E);
        final String rawNote = 'кв. 3$rlo, 2 поверх';
        const String sanitizedNote = 'кв. 3, 2 поверх';

        await _pump(tester, rawNote);

        expect(
          find.text(sanitizedNote),
          findsOneWidget,
          reason: 'the rendered Text must carry the SANITIZED string',
        );
        expect(
          find.text(rawNote),
          findsNothing,
          reason:
              'the raw string (with the RLO control char) must never '
              'reach the Text widget',
        );
      },
    );
  });

  // ── REGRESSION — sanitize + overflow must recompute on didUpdateWidget ────
  //
  // All groups above only ever pump a FRESH `ExpandableNote`, so they
  // exercise `initState` exclusively. `_sanitizedText` is instead recomputed
  // in TWO places (`initState` AND `didUpdateWidget`) precisely because a
  // mounted profile screen can receive a NEW note on the SAME widget instance
  // (e.g. a profile refresh after the master edits their address elsewhere).
  // Reusing `_pump` with `_kNoteKey` at the same tree position across two
  // calls in one test drives the widget through `didUpdateWidget` instead of
  // remounting — see the `_kNoteKey` doc comment above.
  group('ExpandableNote — didUpdateWidget recompute (regression guard)', () {
    const String otherShortNote = 'кв. 7, 4 поверх';

    testWidgets(
      'updating `text` on an already-mounted widget renders the NEW note, '
      'not the stale original',
      (tester) async {
        await _pump(tester, _kShortNote);
        expect(find.text(_kShortNote), findsOneWidget);

        await _pump(tester, otherShortNote);

        expect(
          find.text(otherShortNote),
          findsOneWidget,
          reason: 'the update must render the NEW note text',
        );
        expect(
          find.text(_kShortNote),
          findsNothing,
          reason: 'the stale original note must not linger after the update',
        );
      },
    );

    testWidgets('an updated note is sanitized too — an RLO delivered via '
        'didUpdateWidget is stripped, not just text set in initState', (
      tester,
    ) async {
      await _pump(tester, _kShortNote);
      expect(find.text(_kShortNote), findsOneWidget);

      // U+202E = Right-to-Left Override, built via `String.fromCharCode`
      // (never a literal control byte in source — see the earlier
      // sanitization group's comment).
      final String rlo = String.fromCharCode(0x202E);
      final String rawUpdatedNote = 'кв. 9$rlo, 5 поверх';
      const String sanitizedUpdatedNote = 'кв. 9, 5 поверх';

      await _pump(tester, rawUpdatedNote);

      expect(
        find.text(sanitizedUpdatedNote),
        findsOneWidget,
        reason:
            'didUpdateWidget must re-sanitize the new text, not reuse '
            'the initState-computed value or leak the raw control char',
      );
      expect(
        find.text(rawUpdatedNote),
        findsNothing,
        reason: 'the raw payload from the update must never reach Text',
      );
    });

    testWidgets(
      'the overflow toggle re-derives after a text update: short -> long '
      'shows the toggle; long -> short hides it again',
      (tester) async {
        await _pump(tester, _kShortNote);
        expect(
          _toggle,
          findsNothing,
          reason: 'sanity check on the starting state',
        );

        await _pump(tester, _kLongNote);
        expect(
          _toggle,
          findsOneWidget,
          reason:
              'switching to a long note must recompute overflow and show '
              'the toggle — a stale "no toggle" verdict measured for the '
              'previous short note would contradict the now-clamped text',
        );
        expect(find.text(_kLongNote), findsOneWidget);

        await _pump(tester, _kShortNote);
        expect(
          _toggle,
          findsNothing,
          reason:
              'switching back to a short note must recompute overflow too '
              '— a stale "toggle" verdict measured for the previous long '
              'note would leave an inert toggle on text that no longer '
              'overflows',
        );
      },
    );
  });
}
