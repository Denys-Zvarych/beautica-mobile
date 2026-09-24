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
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // -------------------------------------------------------------------------
  // Perf N2 — a keyboard-inset frame reuses the cached body: the remote
  // source's `resolve` (and so the Consumer, the option mapping, the rows) is
  // not re-run just because the modal route rebuilt the sheet.
  // -------------------------------------------------------------------------
  testWidgets('N2 — keyboard-inset frames do not rebuild the sheet body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final List<String> resolved = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
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
                options: const <SelectOption<String>>[],
                onSelected: (_) {},
                onMenuRetry: () {},
                source: SearchableSelectSource<String>(
                  debounce: const Duration(milliseconds: 100),
                  belowMinimumLabel: 'min',
                  isSearchable: (_) => true,
                  resolve: (WidgetRef ref, String query) {
                    resolved.add(query);
                    return const AsyncData<List<SelectOption<String>>>(
                      _options,
                    );
                  },
                  onRetry: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _openMenu(tester);
    expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);
    final int before = resolved.length;
    expect(before, greaterThan(0));

    // Simulate the keyboard sliding up over several frames.
    for (final double inset in <double>[80, 160, 240, 320]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
    }

    expect(resolved.length, before, reason: 'inset frames reused the body');
    expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);

    // Non-vacuous: a real query change DOES rebuild it.
    await tester.enterText(find.byKey(const Key('select-menu-search')), 'ман');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(resolved.last, 'ман');
  });

  // -------------------------------------------------------------------------
  // Phase 347 — `SearchableSelectSource.provisional` is ADDITIVE.
  // -------------------------------------------------------------------------
  group('Phase 347 provisional rows', () {
    const Duration debounce = Duration(milliseconds: 100);
    const Duration cooldown = Duration(seconds: 5);

    Future<List<String>> pumpRemote(
      WidgetTester tester, {
      required AsyncValue<List<SelectOption<String>>> Function(String query)
      answer,
      List<SelectOption<String>>? Function(WidgetRef ref, String typed)?
      provisional,
      Duration? Function(Object error)? throttleCooldownOf,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final List<String> resolved = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
                  options: const <SelectOption<String>>[],
                  onSelected: (_) {},
                  onMenuRetry: () {},
                  source: SearchableSelectSource<String>(
                    debounce: debounce,
                    belowMinimumLabel: 'min',
                    isSearchable: (String q) => q.isEmpty || q.length >= 3,
                    throttleCooldownOf: throttleCooldownOf,
                    provisional: provisional,
                    resolve: (WidgetRef ref, String query) {
                      resolved.add(query);
                      return answer(query);
                    },
                    onRetry: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('field-under-test')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return resolved;
    }

    List<SelectOption<String>>? prefixOf(WidgetRef ref, String typed) {
      final List<SelectOption<String>> rows = _options
          .where((o) => o.label.toLowerCase().startsWith(typed.toLowerCase()))
          .toList();
      return rows.isEmpty ? null : rows;
    }

    // ---- phase 347 audit (perf M1 / L2 / L1) --------------------------------
    // Thirty rows so the list genuinely scrolls inside the 1120 px sheet.
    final List<SelectOption<String>> many = List<SelectOption<String>>.generate(
      30,
      (int i) {
        final String n = i.toString().padLeft(2, '0');
        return SelectOption<String>(
          value: n,
          label: 'Опція $n',
          rowKey: Key('opt-$n'),
        );
      },
    );

    List<SelectOption<String>>? prefixOfMany(WidgetRef ref, String typed) {
      final List<SelectOption<String>> rows = many
          .where((o) => o.label.toLowerCase().startsWith(typed.toLowerCase()))
          .toList();
      return rows.isEmpty ? null : rows;
    }

    Finder listScrollable() => find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    Future<void> typeOneFrame(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('select-menu-search')), text);
      await tester.pump();
    }

    testWidgets('M1 — provisional -> server keeps the list element, its rows '
        'and its scroll offset', (tester) async {
      await pumpRemote(
        tester,
        answer: (String q) => AsyncData<List<SelectOption<String>>>(many),
        provisional: prefixOfMany,
      );

      await typeOneFrame(tester, 'опц');
      expect(
        find.byKey(const Key('select-menu-refreshing')),
        findsOneWidget,
        reason: 'the provisional rows are showing, before the debounce',
      );
      final ScrollableState scrollable = tester.state<ScrollableState>(
        listScrollable(),
      );
      scrollable.position.jumpTo(300);
      await tester.pump();
      final Element row = tester.element(find.byKey(const Key('opt-10')));

      await tester.pump(debounce);
      await tester.pump();
      expect(
        find.byKey(const Key('select-menu-refreshing')),
        findsNothing,
        reason: 'the server answer for «опц» is what renders now',
      );

      expect(
        identical(tester.state<ScrollableState>(listScrollable()), scrollable),
        isTrue,
        reason: 'the list was not remounted',
      );
      expect(scrollable.position.pixels, 300);
      expect(
        identical(tester.element(find.byKey(const Key('opt-10'))), row),
        isTrue,
        reason: 'the row element survived the swap',
      );
    });

    testWidgets('L2 — below-minimum -> provisional keeps the list element', (
      tester,
    ) async {
      await pumpRemote(
        tester,
        answer: (String q) => AsyncData<List<SelectOption<String>>>(many),
        provisional: prefixOfMany,
      );

      await typeOneFrame(tester, 'оп');
      expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
      final ScrollableState scrollable = tester.state<ScrollableState>(
        listScrollable(),
      );
      final Element row = tester.element(find.byKey(const Key('opt-01')));

      await typeOneFrame(tester, 'опц');
      expect(find.byKey(const Key('select-menu-minimum')), findsNothing);
      expect(
        identical(tester.state<ScrollableState>(listScrollable()), scrollable),
        isTrue,
      );
      expect(
        identical(tester.element(find.byKey(const Key('opt-01'))), row),
        isTrue,
      );
      await tester.pump(debounce);
      await tester.pump();
    });

    testWidgets('L1 — a keystroke that changes no provisional rows does not '
        'rebuild the body', (tester) async {
      final List<String> resolved = await pumpRemote(
        tester,
        answer: (String q) => AsyncData<List<SelectOption<String>>>(many),
        provisional: prefixOfMany,
      );

      // «xyz» prefixes nothing: the view flips from "applied" to "pending
      // with no local rows" — one rebuild, which re-reads the applied state.
      final int beforeFirst = resolved.length;
      await typeOneFrame(tester, 'xyz');
      expect(resolved.length, beforeFirst + 1);

      // «xyzw» still prefixes nothing: the same view, so no rebuild at all.
      final int beforeSecond = resolved.length;
      await typeOneFrame(tester, 'xyzw');
      expect(
        resolved.length,
        beforeSecond,
        reason: 'the body was not rebuilt for an unchanged view',
      );
      expect(find.byKey(const Key('opt-00')), findsOneWidget);

      // Non-vacuous: once the debounce applies it, the body DOES rebuild.
      await tester.pump(debounce);
      await tester.pump();
      expect(resolved.last, 'xyzw');
    });

    testWidgets('without provisional: below-min is the label ALONE and a load '
        'keeps the previous rows (unchanged default)', (tester) async {
      final List<String> resolved = await pumpRemote(
        tester,
        answer: (String q) => q.isEmpty
            ? const AsyncData<List<SelectOption<String>>>(_options)
            : const AsyncLoading<List<SelectOption<String>>>(),
      );
      expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('select-menu-search')), 'ма');
      await tester.pump(debounce);
      await tester.pump();
      expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
      expect(find.byKey(const Key('opt-MANICURE')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'пед',
      );
      await tester.pump(debounce);
      await tester.pump();
      expect(resolved.last, 'пед');
      expect(find.byKey(const Key('select-menu-refreshing')), findsOneWidget);
      // Previous rows, NOT a prefix narrowing: Манікюр is still there.
      expect(find.byKey(const Key('opt-MANICURE')), findsOneWidget);
      expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);
    });

    testWidgets('during a 429 cooldown, typing updates the provisional rows '
        'and issues NO request', (tester) async {
      final Object throttled = Exception('429');
      final List<String> resolved = await pumpRemote(
        tester,
        answer: (String q) => q.isEmpty
            ? AsyncError<List<SelectOption<String>>>(
                throttled,
                StackTrace.empty,
              )
            : const AsyncData<List<SelectOption<String>>>(_options),
        throttleCooldownOf: (Object e) =>
            identical(e, throttled) ? cooldown : null,
        provisional: prefixOf,
      );
      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'пед',
      );
      await tester.pump();
      expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);
      expect(find.byKey(const Key('opt-MANICURE')), findsNothing);
      expect(
        find.byKey(const Key('select-menu-refreshing')),
        findsNothing,
        reason: 'no request is on its way while the limiter is shut',
      );

      await tester.pump(debounce);
      await tester.pump();
      expect(
        resolved.where((String q) => q.isNotEmpty),
        isEmpty,
        reason: 'the debounce elapsed inside the cooldown — nothing sent',
      );
      expect(find.byKey(const Key('opt-PEDICURE')), findsOneWidget);

      // The cooldown ends and applies the held text exactly once.
      await tester.pump(cooldown);
      await tester.pump();
      expect(resolved.where((String q) => q.isNotEmpty).toSet(), <String>{
        'пед',
      });
    });
  });
}
