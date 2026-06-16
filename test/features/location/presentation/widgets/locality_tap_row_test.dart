// Phase 2.18 — Widget tests for [LocalityTapRow], the tap-to-open row that
// replaces a native <select> in the locality cascade.
//
// Closes a LOW QA-audit gap: the row had no dedicated widget tests, so its
// filled/empty/disabled/error rendering, onTap wiring, and semantics were only
// exercised indirectly through the cascade tests.
//
// Strategy: pump the bare [LocalityTapRow] inside a MaterialApp and assert
// ACTUAL rendered output — the displayed string, the leading-pin colour
// (muted when empty / accent when filled), chevron presence, IgnorePointer
// gating, Opacity dimming, the error/helper precedence rule, and the exposed
// Semantics (button/enabled/label/value). Tapping is verified through both the
// callback fired and the callback suppressed when disabled.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps a single [LocalityTapRow] inside a minimal Material scaffold.
Future<void> _pumpRow(
  WidgetTester tester, {
  String label = 'Область',
  String placeholder = 'Оберіть область',
  String? value,
  bool enabled = true,
  String? helper,
  String? errorText,
  Widget? labelSuffix,
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LocalityTapRow(
          label: label,
          placeholder: placeholder,
          value: value,
          enabled: enabled,
          helper: helper,
          errorText: errorText,
          labelSuffix: labelSuffix,
          onTap: onTap ?? () {},
        ),
      ),
    ),
  );
}

/// Returns the leading place-pin [Icon] (the only `Icons.place_outlined`).
Icon _pinIcon(WidgetTester tester) =>
    tester.widget<Icon>(find.byIcon(Icons.place_outlined));

/// Resolves the row's own [Semantics] wrapper (the one enclosing the tappable
/// [GestureDetector]) — NOT the separate label-text node. The widget renders a
/// [Column] whose children do not merge, so finding by type/label is ambiguous;
/// anchoring on the GestureDetector pins us to the interactive node.
Finder _rowSemantics() => find
    .ancestor(
      of: find.byType(GestureDetector),
      matching: find.byType(Semantics),
    )
    .first;

/// The row's own [IgnorePointer] (scoped under the widget — Material wraps the
/// tree in others). The redesign gates touches via `ignoring: !enabled`.
Finder _rowIgnorePointer() => find.descendant(
  of: find.byType(LocalityTapRow),
  matching: find.byType(IgnorePointer),
);

/// The row's own [Opacity] (45% when disabled, 100% when enabled).
Finder _rowOpacity() => find.descendant(
  of: find.byType(LocalityTapRow),
  matching: find.byType(Opacity),
);

void main() {
  group('LocalityTapRow rendering', () {
    testWidgets('renders the label and the placeholder when value is null', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        label: 'Область',
        placeholder: 'Оберіть область',
        value: null,
      );

      expect(find.text('Область'), findsOneWidget);
      expect(find.text('Оберіть область'), findsOneWidget);
    });

    testWidgets('renders the value instead of the placeholder when filled', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        placeholder: 'Оберіть область',
        value: 'Львівська',
      );

      expect(find.text('Львівська'), findsOneWidget);
      expect(find.text('Оберіть область'), findsNothing);
    });

    testWidgets(
      'treats an empty-string value as not filled (shows placeholder)',
      (tester) async {
        await _pumpRow(tester, placeholder: 'Оберіть область', value: '');

        expect(find.text('Оберіть область'), findsOneWidget);
      },
    );

    testWidgets('paints the pin muted when empty and accent when filled', (
      tester,
    ) async {
      await _pumpRow(tester, value: null);
      expect(_pinIcon(tester).color, BrandColors.muted);

      await _pumpRow(tester, value: 'Львівська');
      expect(_pinIcon(tester).color, BrandColors.accent);
    });

    testWidgets('renders a chevron when enabled', (tester) async {
      await _pumpRow(tester, enabled: true);

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('hides the chevron when disabled', (tester) async {
      await _pumpRow(tester, enabled: false);

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('renders the optional labelSuffix beside the label', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        label: 'Область',
        labelSuffix: const Text('— необов\'язково'),
      );

      expect(find.text('Область'), findsOneWidget);
      expect(find.text('— необов\'язково'), findsOneWidget);
    });
  });

  group('LocalityTapRow tap behaviour', () {
    testWidgets('fires onTap when the row is tapped while enabled', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRow(tester, enabled: true, onTap: () => taps++);

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('does not fire onTap when disabled', (tester) async {
      var taps = 0;
      await _pumpRow(tester, enabled: false, onTap: () => taps++);

      await tester.tap(find.byType(GestureDetector), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('blocks touches via IgnorePointer when disabled', (
      tester,
    ) async {
      await _pumpRow(tester, enabled: false);

      final ignore = tester.widget<IgnorePointer>(_rowIgnorePointer());
      expect(ignore.ignoring, isTrue);
    });

    testWidgets('keeps the row interactive (IgnorePointer off) when enabled', (
      tester,
    ) async {
      await _pumpRow(tester, enabled: true);

      final ignore = tester.widget<IgnorePointer>(_rowIgnorePointer());
      expect(ignore.ignoring, isFalse);
    });

    testWidgets('dims the row to 45% opacity when disabled', (tester) async {
      await _pumpRow(tester, enabled: false);

      final opacity = tester.widget<Opacity>(_rowOpacity());
      expect(opacity.opacity, 0.45);
    });

    testWidgets('renders the row fully opaque when enabled', (tester) async {
      await _pumpRow(tester, enabled: true);

      final opacity = tester.widget<Opacity>(_rowOpacity());
      expect(opacity.opacity, 1.0);
    });
  });

  group('LocalityTapRow error / helper line', () {
    testWidgets('renders the helper line below the row when provided', (
      tester,
    ) async {
      await _pumpRow(tester, helper: 'Це місто не має районів');

      expect(find.text('Це місто не має районів'), findsOneWidget);
    });

    testWidgets('renders the error text keyed for assertion when provided', (
      tester,
    ) async {
      await _pumpRow(tester, value: 'Львівська', errorText: 'Обовʼязкове поле');

      final errorFinder = find.byKey(
        const ValueKey<String>('locality_tap_row_error'),
      );
      expect(errorFinder, findsOneWidget);
      expect(tester.widget<Text>(errorFinder).data, 'Обовʼязкове поле');
    });

    testWidgets('error text takes precedence over the helper line', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        // Distinct placeholder so the error string is the only match.
        placeholder: 'Оберіть район',
        helper: 'Це місто не має районів',
        errorText: 'Обовʼязкове поле',
      );

      expect(find.text('Обовʼязкове поле'), findsOneWidget);
      expect(find.text('Це місто не має районів'), findsNothing);
    });

    testWidgets('renders neither helper nor error by default', (tester) async {
      await _pumpRow(tester);

      expect(
        find.byKey(const ValueKey<String>('locality_tap_row_error')),
        findsNothing,
      );
    });
  });

  group('LocalityTapRow semantics', () {
    testWidgets(
      'exposes button + enabled + tap action and the value when interactive',
      (tester) async {
        await _pumpRow(
          tester,
          label: 'Область',
          value: 'Львівська',
          enabled: true,
        );

        final data = tester.getSemantics(_rowSemantics()).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.value, 'Львівська');
      },
    );

    testWidgets('exposes the placeholder as the semantic value when empty', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        label: 'Область',
        placeholder: 'Оберіть область',
        value: null,
      );

      final data = tester.getSemantics(_rowSemantics()).getSemanticsData();
      expect(data.value, 'Оберіть область');
      expect(data.flagsCollection.isButton, isTrue);
    });

    testWidgets('drops the button trait and the tap action when disabled', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        label: 'Місто',
        placeholder: 'Оберіть місто',
        value: null,
        enabled: false,
      );

      final data = tester.getSemantics(_rowSemantics()).getSemanticsData();
      // Disabled: the Semantics wrapper sets button:false / enabled:false, so
      // the node must NOT advertise the button trait, must read as disabled,
      // and must expose no tap action — screen readers should not offer it as
      // a tappable control.
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      // The value (placeholder) is still exposed for screen readers.
      expect(data.value, 'Оберіть місто');
    });
  });
}
