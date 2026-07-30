// Phase 13.x / sec LOW-1 — Widget suite for [SearchQueryField].
//
// The shared pill search field is hosted by BOTH the filters screen and the
// results screen (live search), so every guard it carries protects two call
// sites at once. It had no test at all.
//
// WHAT IS ACTUALLY BEING PINNED
// -----------------------------
//  1. INPUT BOUNDS the backend enforces with a hard 400:
//     `@Size(max = 100)` + `^[^\p{Cntrl}]*$` on both search DTOs. A term that
//     violates either reaches the wire, 400s into the results screen's error
//     state, and the Retry button can then only re-issue the identical doomed
//     request forever.
//  2. The CONTROL-CHARACTER SUPERSET. The formatter denies `[\x00-\x1F\x7F]`,
//     which is Java's `\p{Cntrl}` verbatim. That is deliberately WIDER than
//     `FilteringTextInputFormatter.singleLineFormatter`, which denies only
//     `\n` — a pasted interior TAB would sail straight through it and 400.
//     `an interior TAB is stripped` is the test that stops anyone
//     "simplifying" this back to singleLineFormatter.
//  3. The MIN-LENGTH ERROR's visibility window (1 … kSearchMinQueryLength-1)
//     and the fact that it tracks PROGRAMMATIC controller writes, not just
//     keystrokes («Скинути фільтри» clearing the box).
//  4. The ERROR TREATMENT itself. The window used to render as an 11 sp muted
//     `discCaptionMuted` line with no ring — it read as a hint while the
//     keystroke was being silently swallowed upstream. It is now the canonical
//     `MessageArea` error: a red `NeumorphicInset` ring, an `Icons.error_outline`
//     glyph, `BrandColors.error` copy, and a `Semantics(liveRegion: true)` so a
//     screen reader announces it. Asserting the TONE (not just the presence) is
//     what stops a future refactor from quietly demoting it back to a hint.
//  5. LISTENER HYGIENE — removed on dispose, and swapped when the parent hands
//     down a different controller instance (`didUpdateWidget`). A leaked
//     listener on a disposed State calls setState after unmount.
//
// House rules: finders are Key-based; the error line is asserted through its
// `Key('search_query_min_length_hint')`, never through its UA copy.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/search_query_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _fieldKey = Key('test_query_field');
const Key _hintKey = Key('search_query_min_length_hint');

const String _hintText = 'Пошук майстра або послуги';
const String _minLengthError = 'Введіть щонайменше 3 символи для пошуку';

/// A [TextEditingController] that exposes whether anything is subscribed to it.
///
/// `ChangeNotifier.hasListeners` is `@protected`, so it can only be read from a
/// subclass — reading it from a test body is an analyzer warning. Subscription
/// state is the ONLY direct signal available for the dispose contract: the
/// widget's `_onTextChanged` already short-circuits on `!mounted`, so a LEAKED
/// listener would be silently harmless in a widget test and no behavioural
/// assertion could tell the two apart.
class _ProbeController extends TextEditingController {
  _ProbeController({super.text});

  bool get isSubscribed => hasListeners;
}

void main() {
  /// Pumps the field around [controller]. Returns nothing — tests read the
  /// controller they own.
  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchQueryField(
            fieldKey: _fieldKey,
            controller: controller,
            hintText: _hintText,
            minLengthError: _minLengthError,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  _ProbeController makeController([String text = '']) {
    final _ProbeController c = _ProbeController(text: text);
    addTearDown(c.dispose);
    return c;
  }

  // ── control characters ────────────────────────────────────────────────────

  group('control-character filtering', () {
    testWidgets('an interior TAB is stripped', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма\tнікюр');

      expect(
        c.text,
        'манікюр',
        reason:
            'the backend rejects \\p{Cntrl}; singleLineFormatter denies ONLY '
            '\\n and would let this tab through into a hard 400',
      );
    });

    testWidgets('an interior NEWLINE is stripped', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма\nнікюр');

      expect(c.text, 'манікюр');
    });

    testWidgets('a DEL (\\x7F) is stripped', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма\u007Fнікюр');

      expect(
        c.text,
        'манікюр',
        reason: 'Java \\p{Cntrl} is ASCII C0 PLUS DEL — the top of the range',
      );
    });

    testWidgets('a NUL (\\x00) and other C0 codes are stripped', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'a\u0000b\u001Fc');

      expect(c.text, 'abc');
    });

    testWidgets('the deny pattern is a strict SUPERSET of singleLineFormatter', (
      tester,
    ) async {
      // Property assertion, not a re-test of the widget: this is the exact
      // claim that justifies NOT using the stock formatter. If someone swaps
      // the custom RegExp for singleLineFormatter, the tab test above breaks —
      // this one explains why by pinning the discrepancy at its source.
      const TextEditingValue tabbed = TextEditingValue(text: 'a\tb');
      final TextEditingValue viaSingleLine = FilteringTextInputFormatter
          .singleLineFormatter
          .formatEditUpdate(TextEditingValue.empty, tabbed);

      expect(
        viaSingleLine.text,
        'a\tb',
        reason:
            'singleLineFormatter passes an interior tab UNCHANGED — proof it '
            'is insufficient for the backend guard',
      );

      final _ProbeController c = makeController();
      await pumpField(tester, c);
      await tester.enterText(find.byKey(_fieldKey), 'a\tb');
      expect(c.text, 'ab', reason: 'the field must be stricter than that');
    });

    testWidgets('Cyrillic and emoji survive intact', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), "В'ячеслав 💅 манікюр");

      expect(
        c.text,
        "В'ячеслав 💅 манікюр",
        reason:
            'the filter targets control characters ONLY — apostrophes are '
            'explicitly legal on the backend and astral emoji must not be '
            'mangled into lone surrogates',
      );
    });
  });

  // ── length cap ────────────────────────────────────────────────────────────

  group('maxLength', () {
    testWidgets('input is capped at kSearchMaxQueryLength characters', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'a' * 250);

      expect(
        c.text.length,
        kSearchMaxQueryLength,
        reason:
            'backend @Size(max = 100): an over-long term 400s and the Retry '
            'button can only reproduce it',
      );
    });

    testWidgets('a term at exactly the cap is untouched', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(
        find.byKey(_fieldKey),
        'a' * kSearchMaxQueryLength,
      );

      expect(c.text.length, kSearchMaxQueryLength);
    });

    testWidgets('the Material character counter is suppressed', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'манікюр');
      await tester.pump();

      expect(
        find.textContaining('/$kSearchMaxQueryLength'),
        findsNothing,
        reason:
            'buildCounter must return null — a counter line would add a second '
            'row inside the fixed-height VelvetTouch pill and break it',
      );
    });
  });

  // ── min-length error ──────────────────────────────────────────────────────

  group('min-length error', () {
    testWidgets('absent when the field is empty', (tester) async {
      await pumpField(tester, makeController());

      expect(find.byKey(_hintKey), findsNothing);
    });

    testWidgets('shown at 1 character', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'м');
      await tester.pump();

      expect(find.byKey(_hintKey), findsOneWidget);
    });

    testWidgets('shown at kSearchMinQueryLength - 1 characters', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма');
      await tester.pump();

      expect(find.byKey(_hintKey), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(_hintKey)).data,
        _minLengthError,
        reason: 'the error line renders the localised copy it was handed',
      );
    });

    testWidgets('gone at kSearchMinQueryLength characters', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ман');
      await tester.pump();

      expect(find.byKey(_hintKey), findsNothing);
    });

    testWidgets('gone again after the field is cleared', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма');
      await tester.pump();
      expect(find.byKey(_hintKey), findsOneWidget);

      await tester.enterText(find.byKey(_fieldKey), '');
      await tester.pump();

      expect(find.byKey(_hintKey), findsNothing);
    });

    testWidgets('whitespace-only text is treated as empty', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), '   ');
      await tester.pump();

      expect(
        find.byKey(_hintKey),
        findsNothing,
        reason: 'the helper measures the TRIMMED length',
      );
    });

    testWidgets('padded 2-character text still shows the helper', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), '  ма  ');
      await tester.pump();

      expect(find.byKey(_hintKey), findsOneWidget);
    });

    testWidgets('tracks PROGRAMMATIC controller writes, not just keystrokes', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      // «Скинути фільтри» / an applied query write straight to the controller.
      c.text = 'ма';
      await tester.pump();
      expect(
        find.byKey(_hintKey),
        findsOneWidget,
        reason:
            'the widget listens to the controller precisely so a programmatic '
            'write updates the helper too',
      );

      c.clear();
      await tester.pump();
      expect(find.byKey(_hintKey), findsNothing);
    });

    testWidgets('seeded below-minimum text shows the error on first frame', (
      tester,
    ) async {
      await pumpField(tester, makeController('ма'));

      expect(
        find.byKey(_hintKey),
        findsOneWidget,
        reason: 'initState must seed _belowMinimum from the incoming text',
      );
    });
  });

  // ── error TONE ────────────────────────────────────────────────────────────
  //
  // A 1–2 character term is rejected outright: the applied query is cleared,
  // the results area is blocked and the «Показати майстрів» CTA is disabled.
  // The field must therefore look and sound like an error, not like a hint.
  // These assertions pin the tone, so demoting it back to `discCaptionMuted`
  // (which is what shipped, and what made the whole rejection invisible) fails
  // here rather than in review.

  group('below-minimum error treatment', () {
    NeumorphicInset insetOf(WidgetTester tester) =>
        tester.widget<NeumorphicInset>(
          find
              .ancestor(
                of: find.byKey(_fieldKey),
                matching: find.byType(NeumorphicInset),
              )
              .first,
        );

    testWidgets('the inset ring goes to hasError below the minimum', (
      tester,
    ) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);
      expect(insetOf(tester).hasError, isFalse);

      await tester.enterText(find.byKey(_fieldKey), 'ма');
      await tester.pump();

      expect(
        insetOf(tester).hasError,
        isTrue,
        reason:
            'NeumorphicInset paints the 2 dp BrandColors.error ring off this '
            'flag — the field passed only `radius` before, so the well looked '
            'identical whether or not the term was rejected',
      );
    });

    testWidgets('the ring clears once the term reaches the minimum', (
      tester,
    ) async {
      final _ProbeController c = makeController('ма');
      await pumpField(tester, c);
      expect(insetOf(tester).hasError, isTrue);

      await tester.enterText(find.byKey(_fieldKey), 'ман');
      await tester.pump();

      expect(insetOf(tester).hasError, isFalse);
    });

    testWidgets('an EMPTY box is not an error', (tester) async {
      final _ProbeController c = makeController('ма');
      await pumpField(tester, c);
      expect(insetOf(tester).hasError, isTrue);

      await tester.enterText(find.byKey(_fieldKey), '');
      await tester.pump();

      expect(
        insetOf(tester).hasError,
        isFalse,
        reason:
            'searching on the locality / category / price facets alone is '
            'legitimate — only 1–2 characters is an error',
      );
      expect(find.byKey(_hintKey), findsNothing);
    });

    testWidgets('the error line renders in BrandColors.error, not muted', (
      tester,
    ) async {
      final _ProbeController c = makeController('ма');
      await pumpField(tester, c);

      expect(
        tester.widget<Text>(find.byKey(_hintKey)).style?.color,
        BrandColors.error,
        reason:
            'the copy shipped in BrandColors.muted (#9A8367) at 11 sp and read '
            'as a hint',
      );
    });

    testWidgets('the error line carries an error icon', (tester) async {
      final _ProbeController c = makeController('ма');
      await pumpField(tester, c);

      final Finder icon = find.byIcon(Icons.error_outline);
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).color, BrandColors.error);
    });

    testWidgets('the error line is announced as a live region', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);

      await tester.enterText(find.byKey(_fieldKey), 'ма');
      await tester.pump();

      final Finder live = find.ancestor(
        of: find.byKey(_hintKey),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.liveRegion == true,
        ),
      );
      expect(
        live,
        findsOneWidget,
        reason:
            'a blocking error that only exists visually is invisible to a '
            'screen-reader user mid-typing (message_area.dart:150-167)',
      );
    });
  });

  // ── listener hygiene ──────────────────────────────────────────────────────

  group('controller listener lifecycle', () {
    testWidgets('the listener is removed on dispose', (tester) async {
      final _ProbeController c = makeController();
      await pumpField(tester, c);
      expect(c.isSubscribed, isTrue);

      // Unmount the field but keep the controller alive (the host screen owns
      // it and disposes it separately).
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      expect(
        c.isSubscribed,
        isFalse,
        reason:
            'a listener surviving dispose calls setState on an unmounted State',
      );

      // And mutating it afterwards must be inert, not an exception.
      c.text = 'манікюр';
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('didUpdateWidget swaps the listener on controller identity '
        'change', (tester) async {
      final _ProbeController first = makeController();
      final _ProbeController second = makeController();

      await pumpField(tester, first);
      expect(first.isSubscribed, isTrue);
      expect(second.isSubscribed, isFalse);

      await pumpField(tester, second);

      expect(
        first.isSubscribed,
        isFalse,
        reason: 'the OUTGOING controller must be unsubscribed',
      );
      expect(
        second.isSubscribed,
        isTrue,
        reason: 'the INCOMING controller must be subscribed',
      );

      // The helper must now track the NEW controller…
      second.text = 'ма';
      await tester.pump();
      expect(find.byKey(_hintKey), findsOneWidget);

      // …and be completely deaf to the old one.
      second.clear();
      await tester.pump();
      first.text = 'ма';
      await tester.pump();
      expect(
        find.byKey(_hintKey),
        findsNothing,
        reason: 'a stale subscription would resurrect the helper here',
      );
    });

    testWidgets('a controller swap re-seeds the helper from the NEW text', (
      tester,
    ) async {
      final _ProbeController empty = makeController();
      final _ProbeController partial = makeController('ма');

      await pumpField(tester, empty);
      expect(find.byKey(_hintKey), findsNothing);

      await pumpField(tester, partial);

      expect(
        find.byKey(_hintKey),
        findsOneWidget,
        reason:
            'didUpdateWidget must recompute _belowMinimum — otherwise the '
            'helper reflects the OLD controller until the next keystroke',
      );
    });
  });
}
