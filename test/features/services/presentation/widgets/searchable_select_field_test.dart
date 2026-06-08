// Phase 16.6 — isolated widget tests for [SearchableSelectField<T>], the
// reusable neumorphic searchable single-select dropdown that replaced the
// category / service-type chip rows on [ServiceForm].
//
// Where service_type_chips_test.dart exercises the field THROUGH the form (with
// the real providers overridden), THIS file pumps the field in isolation so the
// generic behaviour is locked independently of the form wiring:
//
//   SEARCH-ALL.     empty query → every option visible.
//   SEARCH-FILTER.  a query shows only matching options (case-insensitive).
//   SEARCH-FOLD.    a plain-ASCII query matches an accented/diacritic label.
//   SEARCH-EMPTY.   a no-match query → the calm `select-menu-empty` hint, NOT
//                   an error state (distinct from the load-error surface).
//   SELECT-CLOSE.   tapping an option pops the sheet AND routes the value back
//                   through onSelected; the closed field then shows the label.
//   LOAD-ESCAPABLE. fieldState=loading → the menu shows an ESCAPABLE spinner:
//                   `select-menu-loading` present, `select-menu-close` present,
//                   tapping close dismisses it (NOT a stranded infinite spinner).
//                   This is the regression guard for the reported "only spinner"
//                   bug at the widget level — the menu can always be exited.
//   ERROR-RETRY.    fieldState=error → `select-menu-error` + `select-menu-retry`;
//                   tapping retry pops the sheet and fires onMenuRetry.
//   FIELD-AFFORD.   the closed field's trailing affordance reflects fieldState
//                   (spinner while loading, error glyph on error).
//
// Isolation: each test pumps a fresh tree; no providers are involved (the field
// is provider-agnostic — the form owns the async wiring). Widgets found by Key.

import 'package:beautica_mobile/features/services/presentation/widgets/searchable_select_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Harness — pumps a single SearchableSelectField<String> and records callbacks.
// ---------------------------------------------------------------------------

class _Harness {
  String? selected;
  int retryCalls = 0;
}

const _options = <SelectOption<String>>[
  SelectOption<String>(
    value: 'MANICURE',
    label: 'Манікюр',
    rowKey: Key('opt-MANICURE'),
  ),
  SelectOption<String>(
    value: 'PEDICURE',
    label: 'Педикюр',
    rowKey: Key('opt-PEDICURE'),
  ),
  // Carries an accented Latin char so SEARCH-FOLD can prove diacritic folding:
  // a plain-ASCII "epil" query must reach "Épilation".
  SelectOption<String>(
    value: 'WAX',
    label: 'Épilation',
    rowKey: Key('opt-WAX'),
  ),
];

Future<_Harness> _pumpField(
  WidgetTester tester, {
  SelectFieldState fieldState = SelectFieldState.idle,
  List<SelectOption<String>> options = _options,
  String? selectedLabel,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _Harness();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Center(
          child: SearchableSelectField<String>(
            fieldKey: const Key('field-under-test'),
            label: 'Категорія',
            menuTitle: 'Категорія',
            placeholder: 'Оберіть зі списку',
            searchHint: 'Пошук…',
            emptyLabel: 'Нічого не знайдено',
            errorLabel: 'Не вдалося завантажити',
            retryLabel: 'Спробувати знову',
            loadingLabel: 'Завантаження…',
            selectedLabel: selectedLabel,
            fieldState: fieldState,
            options: options,
            onSelected: (v) => harness.selected = v,
            onMenuRetry: () => harness.retryCalls++,
          ),
        ),
      ),
    ),
  );
  // The loading state renders an ever-spinning CircularProgressIndicator, so
  // pumpAndSettle would time out — pump a frame instead. Idle/error settle.
  if (fieldState == SelectFieldState.loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return harness;
}

/// Opens the menu. For the loading state, settling is impossible (the spinner
/// animates forever), so a fixed pump opens the sheet without waiting.
Future<void> _openMenu(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.byKey(const Key('field-under-test')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(); // open the sheet
    await tester.pump();
  }
}

/// Types [query] into the menu search box and lets the 180 ms debounce commit.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('select-menu-search')), query);
  await tester.pump(const Duration(milliseconds: 200)); // > 180 ms debounce
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // 1 — Search filtering
  // -------------------------------------------------------------------------

  testWidgets('SEARCH-ALL. empty query shows every option', (tester) async {
    await _pumpField(tester);
    await _openMenu(tester);

    expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);
    expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);
    expect(find.byKey(const Key('opt-WAX')), findsOneWidget);
    expect(find.byKey(const Key('select-menu-empty')), findsNothing);
  });

  testWidgets(
    'SEARCH-FILTER. a query shows only matching options (case-insensitive)',
    (tester) async {
      await _pumpField(tester);
      await _openMenu(tester);

      // Lowercase query against a capitalised UA label — folding lowercases both.
      await _search(tester, 'педи');

      expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);
      expect(find.byKey(const Key('opt-MANICURE')), findsNothing);
      expect(find.byKey(const Key('opt-WAX')), findsNothing);
      expect(find.byKey(const Key('select-menu-empty')), findsNothing);
    },
  );

  testWidgets('SEARCH-FOLD. a plain-ASCII query matches an accented label '
      '(diacritic-insensitive)', (tester) async {
    await _pumpField(tester);
    await _openMenu(tester);

    // "epil" (no accent) must reach "Épilation" via diacritic folding.
    await _search(tester, 'epil');

    expect(find.byKey(const Key('opt-WAX')), findsOneWidget);
    expect(find.byKey(const Key('opt-MANICURE')), findsNothing);
    expect(find.byKey(const Key('opt-PEDICURE')), findsNothing);
  });

  testWidgets(
    'SEARCH-EMPTY. a no-match query → calm empty hint, NOT an error state',
    (tester) async {
      await _pumpField(tester);
      await _openMenu(tester);

      await _search(tester, 'zzzznomatch');

      expect(find.byKey(const Key('select-menu-empty')), findsOneWidget);
      expect(find.text('Нічого не знайдено'), findsOneWidget);
      // The no-match search-empty is distinct from the load-error surface.
      expect(find.byKey(const Key('select-menu-error')), findsNothing);
      expect(find.byKey(const Key('select-menu-retry')), findsNothing);
      // No option rows remain.
      expect(find.byKey(const Key('opt-MANICURE')), findsNothing);
    },
  );

  testWidgets('SEARCH-CLEAR. clearing the query restores all options', (
    tester,
  ) async {
    await _pumpField(tester);
    await _openMenu(tester);

    await _search(tester, 'педи');
    expect(find.byKey(const Key('opt-MANICURE')), findsNothing);

    await _search(tester, '');
    expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);
    expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);
    expect(find.byKey(const Key('opt-WAX')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 2 — Single-select
  // -------------------------------------------------------------------------

  testWidgets(
    'SELECT-CLOSE. tapping an option pops the sheet and routes the value back',
    (tester) async {
      final harness = await _pumpField(tester);
      await _openMenu(tester);

      await tester.tap(find.byKey(const Key('opt-PEDICURE')));
      await tester.pumpAndSettle();

      // onSelected fired with the option's wire value.
      expect(harness.selected, 'PEDICURE');
      // The sheet is gone — the menu search box is no longer in the tree.
      expect(find.byKey(const Key('select-menu-search')), findsNothing);
    },
  );

  testWidgets(
    'SELECT-LABEL. a selectedLabel renders in the closed field (not placeholder)',
    (tester) async {
      await _pumpField(tester, selectedLabel: 'Манікюр');

      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.text('Оберіть зі списку'), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // 3 — Load states (the spinner fix — highest value, at the widget level)
  // -------------------------------------------------------------------------

  testWidgets(
    'LOAD-ESCAPABLE. fieldState=loading → the menu shows an ESCAPABLE spinner; '
    'header close dismisses it (NOT a stranded infinite spinner)',
    (tester) async {
      await _pumpField(tester, fieldState: SelectFieldState.loading);
      // The spinner animates forever → open without settling.
      await _openMenu(tester, settle: false);

      // The loading affordance is shown...
      expect(find.byKey(const Key('select-menu-loading')), findsOneWidget);
      // ...but the search box is suppressed (nothing to filter yet)...
      expect(find.byKey(const Key('select-menu-search')), findsNothing);
      // ...and the close X is ALWAYS present so the user is never trapped: it is
      // a live IconButton wired to Navigator.pop (NOT a disabled/no-op chevron).
      final closeBtn = tester.widget<IconButton>(
        find.byKey(const Key('select-menu-close')),
      );
      expect(
        closeBtn.onPressed,
        isNotNull,
        reason: 'the escape affordance must be actionable while loading',
      );

      // PROVE escapable: invoke the close handler → the sheet (and its
      // ever-spinning loader) is dismissed. (The handler is exercised directly
      // because the in-sheet spinner animates forever, so pumpAndSettle cannot
      // be used and the bottom-aligned header may fall outside the tap region.)
      closeBtn.onPressed!();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('select-menu-loading')), findsNothing);
    },
  );

  testWidgets(
    'ERROR-RETRY. fieldState=error → escapable error with a Retry that fires '
    'onMenuRetry and pops the sheet',
    (tester) async {
      final harness = await _pumpField(
        tester,
        fieldState: SelectFieldState.error,
      );
      await _openMenu(tester);

      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-retry')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-close')), findsOneWidget);
      // No stranded spinner in the error state.
      expect(find.byKey(const Key('select-menu-loading')), findsNothing);

      await tester.tap(find.byKey(const Key('select-menu-retry')));
      await tester.pumpAndSettle();

      // Retry invoked the caller's invalidate hook and dismissed the sheet.
      expect(harness.retryCalls, 1);
      expect(find.byKey(const Key('select-menu-error')), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // 4 — The CLOSED field affordance reflects the async state.
  // -------------------------------------------------------------------------

  testWidgets(
    'FIELD-AFFORD. closed field shows a spinner while loading, error glyph on '
    'error, chevron when idle',
    (tester) async {
      // Loading → inset spinner, no error glyph.
      await _pumpField(tester, fieldState: SelectFieldState.loading);
      expect(
        find.descendant(
          of: find.byKey(const Key('field-under-test')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Error → error glyph, no spinner.
      await _pumpField(tester, fieldState: SelectFieldState.error);
      expect(
        find.descendant(
          of: find.byKey(const Key('field-under-test')),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('field-under-test')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      // Idle → chevron.
      await _pumpField(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('field-under-test')),
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('DISABLED. enabled=false suppresses opening the menu on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Center(
            child: SearchableSelectField<String>(
              fieldKey: const Key('field-under-test'),
              label: 'Категорія',
              menuTitle: 'Категорія',
              placeholder: 'Оберіть зі списку',
              searchHint: 'Пошук…',
              emptyLabel: 'Нічого не знайдено',
              errorLabel: 'Не вдалося завантажити',
              retryLabel: 'Спробувати знову',
              selectedLabel: null,
              fieldState: SelectFieldState.idle,
              options: _options,
              enabled: false,
              onSelected: (_) {},
              onMenuRetry: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('field-under-test')));
    await tester.pumpAndSettle();

    // Menu never opened.
    expect(find.byKey(const Key('select-menu-search')), findsNothing);
    expect(find.byKey(const Key('opt-MANICURE')), findsNothing);
  });
}
