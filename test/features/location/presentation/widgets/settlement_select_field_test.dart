// Phase 346 — SettlementSelectField, the ONE «Населений пункт» autocomplete.
//
// Every case below is an acceptance criterion from
// `docs/mobile-phases/phase-346-settlement-autocomplete-replaces-oblast-city.md`,
// plus the two behaviours that decide whether this field is correct rather than
// merely green.
//
// ⚠ THE DEBOUNCE PUMP IS LOAD-BEARING. `pumpAndSettle` fires no `Timer`, so a
// test that types and settles measures the PRE-KEYSTROKE state — it sees
// whatever the blank-query major list happened to contain and passes against
// the wrong data. Every typing helper here pumps
// [kSettlementSearchDebounce] EXPLICITLY before settling, and
// `below the minimum, nothing is requested` proves the pump reaches the timer
// at all (it asserts a request COUNT, which a vacuous test cannot move).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures — the real shapes the backend returns, including the two ambiguity
// classes `hromadaNameUk` exists to separate.
// ---------------------------------------------------------------------------

/// A major settlement, unambiguous by oblast alone -> `hromadaName == null`.
const _lviv = Settlement(
  id: 's-lviv',
  name: 'Львів',
  oblastName: 'Львівська',
  settlementType: kSettlementTypeCity,
);

/// The SAME name in a DIFFERENT oblast. The oblast label alone separates these
/// two, which is the 76 % case.
const _lvivVillage = Settlement(
  id: 's-lviv-village',
  name: 'Львів',
  oblastName: 'Волинська',
  settlementType: kSettlementTypeVillage,
);

/// A village — the state the retired cascade could not express at all, because
/// `GET /locations/oblasts/{id}/cities` returns `settlement_type = 'CITY'` only.
const _village = Settlement(
  id: 's-village',
  name: 'Іванівка',
  oblastName: 'Полтавська',
  hromadaName: 'Шишацька',
  settlementType: kSettlementTypeVillage,
);

/// Two «Миколаївка» in the SAME oblast — «Миколаївка, Харківська» has 15 of
/// them. Oblast cannot separate these; the server populates `hromadaNameUk`
/// for exactly this class and the client branches on its nullability.
const _mykolaivkaA = Settlement(
  id: 's-myk-a',
  name: 'Миколаївка',
  oblastName: 'Харківська',
  hromadaName: 'Пісочинська',
  settlementType: kSettlementTypeVillage,
);
const _mykolaivkaB = Settlement(
  id: 's-myk-b',
  name: 'Миколаївка',
  oblastName: 'Харківська',
  hromadaName: 'Роганська',
  settlementType: kSettlementTypeVillage,
);

/// Kyiv is an oblast-EQUIVALENT: its oblast row is also named «Київ».
const _kyiv = Settlement(
  id: 's-kyiv',
  name: 'Київ',
  oblastName: 'Київ',
  settlementType: kSettlementTypeCity,
);

// ---------------------------------------------------------------------------
// Fake repository — records every query it is asked for, so a test can assert
// that a below-minimum term costs NOTHING rather than merely rendering nothing.
// ---------------------------------------------------------------------------

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.throwOnSearch = false, this.blankRows});

  /// Overrides the pre-typing major list when non-null.
  final List<Settlement>? blankRows;

  /// Mutable so a test can let a failed search recover on the next attempt.
  bool throwOnSearch;

  /// When non-null, every NON-blank search waits on this before answering —
  /// holds a query in its loading state so a test can look underneath it.
  Completer<void>? gate;

  /// Also hold the BLANK (major-list) query on [gate].
  bool gateBlank = false;

  /// Every `query` value `searchSettlements` was called with, in order.
  final List<String> queries = <String>[];

  /// Per-QUERY holds: a query with an entry here waits on its OWN completer,
  /// so a test can decide which of two in-flight queries answers first.
  final Map<String, Completer<void>> holds = <String, Completer<void>>{};

  /// When non-null, the BLANK (major-list) query fails with this — thrown
  /// ASYNCHRONOUSLY (the method is `async`), the shape a Dio-backed repository
  /// really has, so Riverpod's retry policy is consulted exactly as in
  /// production (M13).
  Object? blankError;

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async {
    queries.add(query);
    final Completer<void>? hold = gate;
    if (hold != null && (query.isNotEmpty || gateBlank)) await hold.future;
    final Completer<void>? own = holds[query];
    if (own != null) await own.future;
    final Object? blankFailure = blankError;
    if (query.isEmpty && blankFailure != null) throw blankFailure;
    if (throwOnSearch) throw const NetworkFailure();
    if (query.isEmpty) {
      // The pre-typing major list (phase-346 D6).
      return blankRows ?? const <Settlement>[_lviv, _kyiv];
    }
    final String needle = query.toLowerCase();
    return const <Settlement>[
      _lviv,
      _lvivVillage,
      _village,
      _mykolaivkaA,
      _mykolaivkaB,
      _kyiv,
    ].where((Settlement s) => s.name.toLowerCase().startsWith(needle)).toList();
  }

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError();

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError();

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Records what the field emitted, so the D3 contract («the id, and only the
/// id, is the value») is asserted rather than assumed.
class _Emitted {
  String? id;
  String? label;
  int clears = 0;
}

Widget _app({
  required _FakeLocationRepository repo,
  required _Emitted emitted,
  String? initialLabel,
  bool clearable = false,
  bool retry = true,
  Duration? Function(int retryCount, Object error)? retryPolicy,
  LocalizationsDelegate<AppLocalizations>? l10nDelegate,
}) {
  return ProviderScope(
    overrides: [locationRepositoryProvider.overrideWithValue(repo)],
    // `retry: false` pins Riverpod's automatic failed-build retry off, so a
    // test observes exactly the fetches the code under test issues.
    // [retryPolicy] wins when given — the 429 test runs the PRODUCTION policy.
    retry: retryPolicy ?? (retry ? null : (int _, Object _) => null),
    child: MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        l10nDelegate ?? AppLocalizations.delegate,
        ...AppLocalizations.localizationsDelegates.where(
          (LocalizationsDelegate<dynamic> d) => d != AppLocalizations.delegate,
        ),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: SettlementSelectField(
          initialLabel: initialLabel,
          onSelected: (String id, String label) {
            emitted.id = id;
            emitted.label = label;
          },
          onCleared: clearable ? () => emitted.clears++ : null,
        ),
      ),
    ),
  );
}

/// UA copy with exactly ONE of the four label words replaced — lets a test
/// change a single memo key term at a time.
class _UkWith extends AppLocalizationsUk {
  _UkWith({this.hromada, this.oblast, this.city, this.village});

  final String? hromada;
  final String? oblast;
  final String? city;
  final String? village;

  @override
  String get settlementHromadaWord => hromada ?? super.settlementHromadaWord;
  @override
  String get settlementOblastAbbrev => oblast ?? super.settlementOblastAbbrev;
  @override
  String get settlementCityPrefix => city ?? super.settlementCityPrefix;
  @override
  String get settlementVillagePrefix =>
      village ?? super.settlementVillagePrefix;
}

class _FixedL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _FixedL10nDelegate(this.l10n);

  final AppLocalizations l10n;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(l10n);

  @override
  bool shouldReload(_FixedL10nDelegate old) => !identical(old.l10n, l10n);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settlement_select_field')));
  await tester.pumpAndSettle();
}

/// Types [query] and lets the DEBOUNCE elapse.
///
/// The explicit `pump(kSettlementSearchDebounce)` is what makes every
/// assertion after it non-vacuous — see this file's header.
Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('select-menu-search')), query);
  await tester.pump(kSettlementSearchDebounce);
  await tester.pumpAndSettle();
}

Finder _row(Settlement s) => find.byKey(Key('settlement_option_${s.id}'));

/// The text rendered on the CLOSED field.
///
/// Read through the field's key rather than by `find.text('<Cyrillic>')`: a
/// Cyrillic text finder couples the assertion to the UA locale and becomes a
/// `findsNothing` failure the day EN ships. The settlement label is a mix of
/// locale-invariant reference data and one translated noun, so the value is
/// READ here and compared by the caller.
String _closedFieldLabel(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(const Key('settlement_select_field')),
            matching: find.byType(Text),
          )
          .first,
    )
    .data!;

String _rowLabel(WidgetTester tester, Settlement s) => tester
    .widget<Text>(find.descendant(of: _row(s), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('before any typing the sheet offers the major settlements — '
      'never a blank sheet (D6)', (WidgetTester tester) async {
    final repo = _FakeLocationRepository();
    await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
    await _openSheet(tester);

    expect(_row(_lviv), findsOneWidget);
    expect(_row(_kyiv), findsOneWidget);
    expect(find.byKey(const Key('select-menu-empty')), findsNothing);
    expect(
      repo.queries,
      equals(<String>['']),
      reason: 'the pre-typing list is the BLANK-query response, not a search',
    );
  });

  testWidgets('below the minimum the sheet shows the hint and issues NO '
      'request', (WidgetTester tester) async {
    final repo = _FakeLocationRepository();
    await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
    await _openSheet(tester);
    expect(repo.queries, equals(<String>['']));

    await _type(tester, 'ль');

    expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
    expect(_row(_lviv), findsNothing);
    expect(
      repo.queries,
      equals(<String>['']),
      reason:
          'a 1-2 character term must cost NOTHING — the server predicate is '
          'mirrored locally, so no request is issued at all. This count is '
          'also what proves the debounce pump above actually fires the timer: '
          'a vacuous test could not move it.',
    );
  });

  testWidgets('a 3-character alphanumeric RUN is required, not merely 3 '
      'characters', (WidgetTester tester) async {
    final repo = _FakeLocationRepository();
    await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
    await _openSheet(tester);

    // Three characters, but no uninterrupted alphanumeric run of three — this
    // is the padding shape that defeats a plain length floor and degrades the
    // server into a sequential scan of 25 698 rows.
    await _type(tester, '•к•');

    expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
    expect(repo.queries, equals(<String>['']));
  });

  testWidgets('typing «льв» offers Львів', (WidgetTester tester) async {
    final repo = _FakeLocationRepository();
    await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
    await _openSheet(tester);

    await _type(tester, 'льв');

    expect(_row(_lviv), findsOneWidget);
    expect(repo.queries, equals(<String>['', 'льв']));
  });

  testWidgets(
    'a VILLAGE is findable — the state the cascade could not express',
    (WidgetTester tester) async {
      final repo = _FakeLocationRepository();
      final emitted = _Emitted();
      await tester.pumpWidget(_app(repo: repo, emitted: emitted));
      await _openSheet(tester);

      await _type(tester, 'іва');
      expect(_row(_village), findsOneWidget);

      await tester.tap(_row(_village));
      await tester.pumpAndSettle();

      expect(emitted.id, _village.id);
    },
  );

  testWidgets('two settlements sharing a name in DIFFERENT oblasts are told '
      'apart by the oblast label', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(repo: _FakeLocationRepository(), emitted: _Emitted()),
    );
    await _openSheet(tester);
    await _type(tester, 'льв');

    expect(_rowLabel(tester, _lviv), 'м. Львів, Львівська обл.');
    expect(_rowLabel(tester, _lvivVillage), 'с. Львів, Волинська обл.');
  });

  testWidgets('two settlements sharing a name in the SAME oblast are told '
      'apart by the hromada segment', (WidgetTester tester) async {
    // ⚠ This case is the one that matters. The oblast-only assertion above
    // passes against the 76 % of rows that were never the problem, so on its
    // own it is VACUOUS for the defect phase 327 exists to fix: 2 234
    // name+oblast groups covering 6 103 rows collide, worst «Миколаївка,
    // Харківська» x15.
    await tester.pumpWidget(
      _app(repo: _FakeLocationRepository(), emitted: _Emitted()),
    );
    await _openSheet(tester);
    await _type(tester, 'мик');

    expect(
      _rowLabel(tester, _mykolaivkaA),
      'с. Миколаївка, Пісочинська громада, Харківська обл.',
    );
    expect(
      _rowLabel(tester, _mykolaivkaB),
      'с. Миколаївка, Роганська громада, Харківська обл.',
    );
    expect(
      _rowLabel(tester, _mykolaivkaA),
      isNot(_rowLabel(tester, _mykolaivkaB)),
    );
  });

  testWidgets('the three-part label WRAPS rather than truncating — the segment '
      'that disambiguates must never be the one ellipsised', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(repo: _FakeLocationRepository(), emitted: _Emitted()),
    );
    await _openSheet(tester);
    await _type(tester, 'мик');

    final Text text = tester.widget<Text>(
      find.descendant(of: _row(_mykolaivkaA), matching: find.byType(Text)),
    );
    expect(text.maxLines, 2);
  });

  testWidgets('Kyiv never renders as «Київ, Київ» — an oblast that IS the '
      'settlement is dropped', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(repo: _FakeLocationRepository(), emitted: _Emitted()),
    );
    await _openSheet(tester);

    expect(_rowLabel(tester, _kyiv), 'м. Київ');
    expect(_rowLabel(tester, _kyiv), isNot(contains('обл.')));
  });

  testWidgets(
    '«Мелітополь» returns nothing — the occupied-settlement exclusion '
    'is an ABSENCE in the data, and the field renders the calm empty state',
    (WidgetTester tester) async {
      final repo = _FakeLocationRepository();
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);

      await _type(tester, 'мелітополь');

      expect(find.byKey(const Key('select-menu-empty')), findsOneWidget);
      expect(repo.queries, equals(<String>['', 'мелітополь']));
    },
  );

  testWidgets('selecting a row emits the ID (D3) and closes the sheet, and the '
      'closed field then shows the composed label', (
    WidgetTester tester,
  ) async {
    final emitted = _Emitted();
    await tester.pumpWidget(
      _app(repo: _FakeLocationRepository(), emitted: emitted),
    );
    await _openSheet(tester);
    await _type(tester, 'іва');

    await tester.tap(_row(_village));
    await tester.pumpAndSettle();

    expect(emitted.id, 's-village');
    expect(find.byKey(const Key('select-menu-search')), findsNothing);

    // The label is composed, not asserted as a frozen literal: «громада» is UI
    // copy from the ARB, so pinning the whole string here would make this test
    // a locale trap the day EN ships. The settlement and oblast NAMES are
    // government reference data and locale-invariant; only the connecting words
    // («громада», «обл.», «м.», «с.») are translated, so it is pulled from `AppLocalizations`.
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('settlement_select_field'))),
    );
    final String expected = composeSettlementLabel(
      _village,
      hromadaWord: l10n.settlementHromadaWord,
      oblastWord: l10n.settlementOblastAbbrev,
      cityPrefix: l10n.settlementCityPrefix,
      villagePrefix: l10n.settlementVillagePrefix,
    );
    expect(emitted.label, expected);
    expect(_closedFieldLabel(tester), expected);
  });

  testWidgets('re-opening a SAVED address shows the previously chosen '
      'settlement without issuing any request (D7)', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository();
    await tester.pumpWidget(
      _app(repo: repo, emitted: _Emitted(), initialLabel: 'Львів, Львівська'),
    );
    await tester.pumpAndSettle();

    expect(_closedFieldLabel(tester), 'Львів, Львівська');
    expect(
      repo.queries,
      isEmpty,
      reason:
          'the saved label arrives denormalised on the profile/salon read — '
          'there is no id -> name lookup, and none is needed',
    );
  });

  testWidgets('the clear affordance is opt-in: absent without onCleared, and '
      'absent even with it while nothing is selected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        repo: _FakeLocationRepository(),
        emitted: _Emitted(),
        initialLabel: 'Львів, Львівська',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('select-field-clear')), findsNothing);

    await tester.pumpWidget(
      _app(
        repo: _FakeLocationRepository(),
        emitted: _Emitted(),
        clearable: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('select-field-clear')), findsNothing);
  });

  testWidgets(
    'a clearable field with a value clears it and reports the clear',
    (WidgetTester tester) async {
      final emitted = _Emitted();
      await tester.pumpWidget(
        _app(
          repo: _FakeLocationRepository(),
          emitted: emitted,
          initialLabel: 'Львів, Львівська',
          clearable: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('select-field-clear')));
      await tester.pumpAndSettle();

      expect(emitted.clears, 1);
      expect(_closedFieldLabel(tester), isNot('Львів, Львівська'));
    },
  );

  group('option memo (perf M2) rebuilds when ANY label word changes', () {
    // The memo is keyed on the list identity PLUS the four localised words.
    // The blank-key major list is PINNED (keepAlive), so closing the sheet,
    // swapping exactly ONE word and re-opening serves the SAME list instance —
    // precisely the case where a memo that forgot that word would keep
    // serving the stale label.
    Future<void> relabel(
      WidgetTester tester, {
      required Settlement row,
      required _UkWith swapped,
      required String expected,
    }) async {
      final repo = _FakeLocationRepository(
        blankRows: const <Settlement>[_lviv, _lvivVillage, _mykolaivkaA],
      );
      final emitted = _Emitted();
      await tester.pumpWidget(
        _app(
          repo: repo,
          emitted: emitted,
          l10nDelegate: _FixedL10nDelegate(_UkWith()),
        ),
      );
      await _openSheet(tester);
      final String before = _rowLabel(tester, row);
      await tester.tap(find.byKey(const Key('select-menu-close')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(
          repo: repo,
          emitted: emitted,
          l10nDelegate: _FixedL10nDelegate(swapped),
        ),
      );
      await tester.pumpAndSettle();
      await _openSheet(tester);

      expect(
        repo.queries,
        <String>[''],
        reason: 'the SAME pinned list must be relabelled — no refetch',
      );
      expect(_rowLabel(tester, row), isNot(before));
      expect(_rowLabel(tester, row), expected);
    }

    testWidgets('hromada word', (WidgetTester tester) async {
      await relabel(
        tester,
        row: _mykolaivkaA,
        swapped: _UkWith(hromada: 'ТГ'),
        expected: 'с. Миколаївка, Пісочинська ТГ, Харківська обл.',
      );
    });

    testWidgets('oblast word', (WidgetTester tester) async {
      await relabel(
        tester,
        row: _lviv,
        swapped: _UkWith(oblast: 'область'),
        expected: 'м. Львів, Львівська область',
      );
    });

    testWidgets('city prefix', (WidgetTester tester) async {
      await relabel(
        tester,
        row: _lviv,
        swapped: _UkWith(city: 'місто'),
        expected: 'місто Львів, Львівська обл.',
      );
    });

    testWidgets('village prefix', (WidgetTester tester) async {
      await relabel(
        tester,
        row: _lvivVillage,
        swapped: _UkWith(village: 'село'),
        expected: 'село Львів, Волинська обл.',
      );
    });
  });

  testWidgets('a failed search keeps the sheet OPEN on its error state — the '
      'typed term must survive a retry', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        repo: _FakeLocationRepository(throwOnSearch: true),
        emitted: _Emitted(),
      ),
    );
    await tester.tap(find.byKey(const Key('settlement_select_field')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
    expect(
      find.byKey(const Key('select-menu-search')),
      findsOneWidget,
      reason:
          'the query is what produces the load, so hiding the input during a '
          'failure would trap the user on a state they cannot steer out of',
    );
    expect(find.byKey(const Key('select-menu-retry')), findsOneWidget);
  });

  group('Phase 346 audit fixes', () {
    testWidgets('M1 — while the next query loads, the PREVIOUS rows stay '
        'visible under a thin progress bar; the full spinner is not shown', (
      WidgetTester tester,
    ) async {
      final repo = _FakeLocationRepository();
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);
      expect(_row(_lviv), findsOneWidget);
      expect(_row(_kyiv), findsOneWidget);

      final Completer<void> gate = Completer<void>();
      repo.gate = gate;
      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'Льв',
      );
      await tester.pump(kSettlementSearchDebounce);
      await tester.pump();

      expect(repo.queries.last, 'Льв', reason: 'the new query is in flight');
      expect(find.byKey(const Key('select-menu-loading')), findsNothing);
      expect(find.byKey(const Key('select-menu-refreshing')), findsOneWidget);
      expect(_row(_lviv), findsOneWidget);
      expect(_row(_kyiv), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-menu-refreshing')), findsNothing);
      expect(_row(_kyiv), findsNothing);
      expect(_row(_lvivVillage), findsOneWidget);
    });

    testWidgets('M1 — the FIRST load (no previous rows) still shows the full '
        'loading state', (WidgetTester tester) async {
      final repo = _FakeLocationRepository()
        ..gate = Completer<void>()
        ..gateBlank = true;
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await tester.tap(find.byKey(const Key('settlement_select_field')));
      await tester.pumpUntilFound(find.byKey(const Key('select-menu-loading')));

      expect(find.byKey(const Key('select-menu-loading')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-refreshing')), findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(_row(_lviv), findsOneWidget);
    });

    testWidgets('L2 — the search input is capped at the server maximum and '
        'the sent query is exactly the text in the box', (
      WidgetTester tester,
    ) async {
      final repo = _FakeLocationRepository();
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);

      final String long = 'Миколаївка' * 8; // 80 characters
      await _type(tester, long);

      final String boxText = tester
          .widget<TextField>(find.byKey(const Key('select-menu-search')))
          .controller!
          .text;
      expect(boxText.length, kSettlementQueryMaxLength);
      expect(repo.queries.last, boxText.trim());
      expect(repo.queries.last.length, lessThanOrEqualTo(50));
    });

    testWidgets('L5 — a seeded initialLabel is sanitised with the same rule '
        'as a picked row', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          repo: _FakeLocationRepository(),
          emitted: _Emitted(),
          initialLabel: '\u202E${_lviv.name}\u200B',
        ),
      );
      await tester.pump();
      expect(_closedFieldLabel(tester), _lviv.name);
    });

    testWidgets('N3 — a FAILED blank-key fetch is not pinned: closing and '
        're-opening the sheet refetches the major list', (
      WidgetTester tester,
    ) async {
      final repo = _FakeLocationRepository(throwOnSearch: true);
      await tester.pumpWidget(
        _app(repo: repo, emitted: _Emitted(), retry: false),
      );
      await _openSheet(tester);
      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
      expect(repo.queries, <String>['']);

      await tester.tap(find.byKey(const Key('select-menu-close')));
      await tester.pumpAndSettle();

      repo.throwOnSearch = false;
      await _openSheet(tester);

      expect(repo.queries, <String>['', '']);
      expect(find.byKey(const Key('select-menu-error')), findsNothing);
      expect(_row(_lviv), findsOneWidget);
    });
  });

  group('Phase 346 QA gate', () {
    testWidgets('five rapid keystrokes inside one debounce window issue '
        'exactly ONE request, for the final term', (WidgetTester tester) async {
      final repo = _FakeLocationRepository();
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);
      expect(repo.queries, <String>['']);

      // Each keystroke lands 100 ms after the previous one — well inside the
      // 400 ms window — so every one of them must re-arm the SAME timer.
      for (final String term in <String>['л', 'ль', 'льв', 'льві', 'львів']) {
        await tester.enterText(
          find.byKey(const Key('select-menu-search')),
          term,
        );
        // fixed-wait-ok: debounce-not-yet — a keystroke gap deliberately
        // SHORTER than kSettlementSearchDebounce is the scenario under test.
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        repo.queries,
        <String>[''],
        reason: 'the window has not elapsed since the LAST keystroke yet',
      );

      await tester.pump(kSettlementSearchDebounce);
      await tester.pumpAndSettle();

      expect(
        repo.queries,
        <String>['', 'львів'],
        reason:
            'one request per debounce window — never one per keystroke, and '
            'never an intermediate prefix («льв», «льві»)',
      );
      expect(_row(_lviv), findsOneWidget);
    });

    testWidgets('1- and 2-character terms, each allowed to settle PAST the '
        'debounce, issue zero requests', (WidgetTester tester) async {
      final repo = _FakeLocationRepository();
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);

      await _type(tester, 'л');
      expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
      await _type(tester, 'ль');
      expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);

      expect(repo.queries, <String>['']);
    });

    testWidgets('an OLDER query answering LAST never overwrites the newer '
        'query\'s rows', (WidgetTester tester) async {
      final repo = _FakeLocationRepository();
      final Completer<void> older = Completer<void>();
      final Completer<void> newer = Completer<void>();
      repo.holds['льв'] = older;
      repo.holds['мик'] = newer;
      await tester.pumpWidget(_app(repo: repo, emitted: _Emitted()));
      await _openSheet(tester);

      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'льв',
      );
      await tester.pump(kSettlementSearchDebounce);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'мик',
      );
      await tester.pump(kSettlementSearchDebounce);
      await tester.pump();
      expect(repo.queries, <String>[
        '',
        'льв',
        'мик',
      ], reason: 'both queries must genuinely be in flight at once');

      newer.complete();
      await tester.pumpAndSettle();
      expect(_row(_mykolaivkaA), findsOneWidget);

      // The stale answer lands AFTER the fresh one.
      older.complete();
      await tester.pumpAndSettle();

      expect(_row(_mykolaivkaA), findsOneWidget);
      expect(_row(_mykolaivkaB), findsOneWidget);
      expect(_row(_lviv), findsNothing);
      expect(_row(_lvivVillage), findsNothing);
    });

    testWidgets('a 429 on the blank key is NOT sticky: closing and re-opening '
        'the sheet refetches and recovers', (WidgetTester tester) async {
      final repo = _FakeLocationRepository()
        ..blankError = const SettlementSearchRateLimitedFailure(
          retryAfterSeconds: 30,
        );
      await tester.pumpWidget(
        _app(
          repo: repo,
          emitted: _Emitted(),
          // The PRODUCTION policy — it must not auto-retry a throttle.
          retryPolicy: beauticaProviderRetry,
        ),
      );
      await _openSheet(tester);

      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
      final String message = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('select-menu-error')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      expect(
        message,
        AppLocalizations.of(
          tester.element(find.byKey(const Key('select-menu-error'))),
        ).settlementSearchErrRateLimited,
        reason: 'the RATE-LIMIT branch rendered, not the generic error',
      );
      expect(
        find.byKey(const Key('select-menu-retry')),
        findsNothing,
        reason: 'no Retry while the cooldown runs',
      );
      expect(repo.queries, <String>['']);

      await tester.tap(find.byKey(const Key('select-menu-close')));
      await tester.pumpAndSettle();

      repo.blankError = null;
      await _openSheet(tester);

      expect(
        repo.queries,
        <String>['', ''],
        reason: 'the failed blank key must not be pinned — re-open refetches',
      );
      expect(find.byKey(const Key('select-menu-error')), findsNothing);
      expect(_row(_lviv), findsOneWidget);
      expect(_row(_kyiv), findsOneWidget);
    });
  });
}
