// Phase 220 (C) — unit tests for the pure address-line composition helpers.
//
// Phase 223 (a) — moved from `test/features/master/presentation/widgets/
// master_address_lines_test.dart` alongside the helpers' promotion to
// `lib/shared/formatters/address_lines.dart` (renamed
// `buildMasterLocalityLine`/`buildMasterStreetLine` -> `buildLocalityLine`/
// `buildStreetLine`, re-typed from a `Master` parameter to plain `String?`
// fields). The fixtures below now pass city/street/buildingNo directly
// instead of building a `Master` — the whole point of the rename was to stop
// this shared formatter depending on one feature's domain entity, so a test
// that still routed through `Master` would silently reintroduce that
// coupling.
//
// WHY THIS FILE EXISTS (mobile-qa gap-fill)
// ------------------------------------------
// `buildLocalityLine` / `buildStreetLine` are pure Dart (no Flutter import) —
// the cheapest, fastest layer to exhaustively cover the full city × street ×
// buildingNo presence/absence matrix, rather than re-deriving every
// combination through a widget pump. The widget-tier coverage in
// `master_profile_screen_test.dart` / `public_master_profile_screen_test.dart`
// / `public_salon_profile_screen_test.dart` proves a REPRESENTATIVE subset of
// these combinations render correctly through the real `Text`/`Row` tree;
// this file proves the underlying decision logic is correct for EVERY
// combination, including three the widget tier did not previously exercise
// at all:
//   - city + buildingNo, NO street        (building must be dropped, not
//                                           dangling, no leak beside the city)
//   - street + buildingNo, NO city         (promotion path WITH a building
//                                           number attached)
//   - buildingNo ALONE (no city, no street) (must never render on its own —
//                                           both helpers return null)
//
// Every case also asserts NO leading/trailing/dangling comma and NO empty
// line ever comes back — the two visual defects a partial-field regression
// would produce (e.g. "вул. Хрещатик, " or ", 22").

import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails if [value] contains an empty "line" (adjacent commas / leading or
/// trailing comma) — the dangling-comma defect the promotion/omission logic
/// must never produce.
void _expectNoDanglingComma(String? value) {
  if (value == null) return;
  expect(value.trim(), isNot(startsWith(',')), reason: 'leading comma: $value');
  expect(value.trim(), isNot(endsWith(',')), reason: 'trailing comma: $value');
  expect(value, isNot(contains(',,')), reason: 'doubled comma: $value');
  expect(value, isNot(contains(', ,')), reason: 'empty-segment comma: $value');
}

void main() {
  group('buildLocalityLine', () {
    test('returns the city when city is set', () {
      expect(buildLocalityLine('Київ'), 'Київ');
    });

    test('returns null when city is null', () {
      expect(buildLocalityLine(null), isNull);
    });

    test('returns null when city is an empty string (blank, not absent)', () {
      expect(buildLocalityLine(''), isNull);
    });
  });

  group('buildStreetLine — full 2×2 street × buildingNo matrix', () {
    test('street + buildingNo → "street, building"', () {
      final String? line = buildStreetLine('вул. Хрещатик', '22');
      expect(line, 'вул. Хрещатик, 22');
      _expectNoDanglingComma(line);
    });

    test('street only, no buildingNo → bare street, no comma appended', () {
      final String? line = buildStreetLine('вул. Хрещатик');
      expect(line, 'вул. Хрещатик');
      _expectNoDanglingComma(line);
    });

    test('buildingNo present but street ABSENT → null (a building number '
        'with no street is never rendered as its own line)', () {
      expect(buildStreetLine(null, '22'), isNull);
    });

    test('neither street nor buildingNo → null', () {
      expect(buildStreetLine(null), isNull);
    });

    test('buildingNo is a blank string (not null) with a street set → '
        'building treated as absent, no dangling comma', () {
      final String? line = buildStreetLine('вул. Хрещатик', '');
      expect(line, 'вул. Хрещатик');
      _expectNoDanglingComma(line);
    });

    test('street is a blank string (not null) → treated as absent → null', () {
      expect(buildStreetLine('', '22'), isNull);
    });
  });

  // ── Full city × street × buildingNo presence matrix (8 combinations) ──────
  //
  // Exercises BOTH helpers together exactly as every call site composes them
  // (`buildLocalityLine(city)` for line 1, `buildStreetLine(street,
  // buildingNo)` for line 2), asserting the caller-visible contract: which
  // line(s) render, and that neither ever contains a dangling comma or
  // resolves to an empty (non-null) string.
  group('combined city × street × buildingNo matrix', () {
    test('1. city + street + buildingNo — full address', () {
      expect(buildLocalityLine('Київ'), 'Київ');
      expect(buildStreetLine('вул. Хрещатик', '22'), 'вул. Хрещатик, 22');
    });

    test('2. city + street, no buildingNo', () {
      expect(buildLocalityLine('Київ'), 'Київ');
      expect(buildStreetLine('вул. Хрещатик'), 'вул. Хрещатик');
    });

    test('3. city + buildingNo, NO street — building must be dropped '
        'entirely, never leaked beside the city with a dangling comma', () {
      expect(buildLocalityLine('Київ'), 'Київ');
      expect(
        buildStreetLine(null, '22'),
        isNull,
        reason:
            'a building number with no street must never render its own '
            'line, even when a city IS present',
      );
    });

    test('4. city only', () {
      expect(buildLocalityLine('Київ'), 'Київ');
      expect(buildStreetLine(null), isNull);
    });

    test('5. street + buildingNo, NO city — the PROMOTION path: the street '
        'line (with its building number attached) is what the caller '
        'promotes to the primary icon-bearing row', () {
      expect(buildLocalityLine(null), isNull);
      expect(buildStreetLine('вул. Хрещатик', '22'), 'вул. Хрещатик, 22');
    });

    test('6. street only, no city, no buildingNo — promotion, bare street', () {
      expect(buildLocalityLine(null), isNull);
      expect(buildStreetLine('вул. Хрещатик'), 'вул. Хрещатик');
    });

    test('7. buildingNo ALONE (no city, no street) — both helpers return '
        'null; the caller\'s `if (localityLine != null || streetLine != '
        'null)` gate must hide the WHOLE location row rather than orphaning '
        'the building number', () {
      expect(buildLocalityLine(null), isNull);
      expect(buildStreetLine(null, '22'), isNull);
    });

    test('8. nothing set — both null, row hidden', () {
      expect(buildLocalityLine(null), isNull);
      expect(buildStreetLine(null), isNull);
    });
  });
}
