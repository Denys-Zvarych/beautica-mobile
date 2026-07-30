// Phase 220 (C) — unit tests for the pure address-line composition helpers.
//
// WHY THIS FILE EXISTS (mobile-qa gap-fill)
// ------------------------------------------
// `buildMasterLocalityLine` / `buildMasterStreetLine` are pure Dart (no
// Flutter import) — the cheapest, fastest layer to exhaustively cover the
// full city × street × buildingNo presence/absence matrix, rather than
// re-deriving every combination through a widget pump. The widget-tier
// coverage in `master_profile_screen_test.dart` / `public_master_profile_
// screen_test.dart` proves a REPRESENTATIVE subset of these combinations
// render correctly through the real `Text`/`Row` tree; this file proves the
// underlying decision logic is correct for EVERY combination, including three
// the widget tier did not previously exercise at all:
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

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_address_lines.dart';
import 'package:flutter_test/flutter_test.dart';

Master _master({String? city, String? street, String? buildingNo}) => Master(
  id: 'm-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  city: city,
  street: street,
  buildingNo: buildingNo,
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

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
  group('buildMasterLocalityLine', () {
    test('returns the city when city is set (street/building irrelevant)', () {
      expect(buildMasterLocalityLine(_master(city: 'Київ')), 'Київ');
      expect(
        buildMasterLocalityLine(
          _master(city: 'Київ', street: 'вул. Хрещатик', buildingNo: '22'),
        ),
        'Київ',
      );
    });

    test('returns null when city is null', () {
      expect(buildMasterLocalityLine(_master()), isNull);
      expect(buildMasterLocalityLine(_master(street: 'вул. Хрещатик')), isNull);
    });

    test('returns null when city is an empty string (blank, not absent)', () {
      expect(buildMasterLocalityLine(_master(city: '')), isNull);
    });
  });

  group('buildMasterStreetLine — full 2×2 street × buildingNo matrix, with '
      'and without a locality present (locality has NO bearing on this '
      "helper's output — it only composes street + buildingNo)", () {
    test('street + buildingNo → "street, building"', () {
      final String? line = buildMasterStreetLine(
        _master(street: 'вул. Хрещатик', buildingNo: '22'),
      );
      expect(line, 'вул. Хрещатик, 22');
      _expectNoDanglingComma(line);
    });

    test('street only, no buildingNo → bare street, no comma appended', () {
      final String? line = buildMasterStreetLine(
        _master(street: 'вул. Хрещатик'),
      );
      expect(line, 'вул. Хрещатик');
      _expectNoDanglingComma(line);
    });

    test('buildingNo present but street ABSENT → null (a building number with '
        'no street is never rendered as its own line)', () {
      expect(buildMasterStreetLine(_master(buildingNo: '22')), isNull);
    });

    test('neither street nor buildingNo → null', () {
      expect(buildMasterStreetLine(_master()), isNull);
    });

    test('buildingNo is a blank string (not null) with a street set → '
        'building treated as absent, no dangling comma', () {
      final String? line = buildMasterStreetLine(
        _master(street: 'вул. Хрещатик', buildingNo: ''),
      );
      expect(line, 'вул. Хрещатик');
      _expectNoDanglingComma(line);
    });

    test('street is a blank string (not null) → treated as absent → null', () {
      expect(
        buildMasterStreetLine(_master(street: '', buildingNo: '22')),
        isNull,
      );
    });
  });

  // ── Full city × street × buildingNo presence matrix (8 combinations) ──────
  //
  // Exercises BOTH helpers together exactly as every call site composes them
  // (`buildMasterLocalityLine(master)` for line 1,
  // `buildMasterStreetLine(master)` for line 2), asserting the caller-visible
  // contract: which line(s) render, and that neither ever contains a dangling
  // comma or resolves to an empty (non-null) string.
  group('combined city × street × buildingNo matrix', () {
    test('1. city + street + buildingNo — full address', () {
      final Master m = _master(
        city: 'Київ',
        street: 'вул. Хрещатик',
        buildingNo: '22',
      );
      expect(buildMasterLocalityLine(m), 'Київ');
      expect(buildMasterStreetLine(m), 'вул. Хрещатик, 22');
    });

    test('2. city + street, no buildingNo', () {
      final Master m = _master(city: 'Київ', street: 'вул. Хрещатик');
      expect(buildMasterLocalityLine(m), 'Київ');
      expect(buildMasterStreetLine(m), 'вул. Хрещатик');
    });

    test('3. city + buildingNo, NO street — building must be dropped entirely, '
        'never leaked beside the city with a dangling comma', () {
      final Master m = _master(city: 'Київ', buildingNo: '22');
      expect(buildMasterLocalityLine(m), 'Київ');
      expect(
        buildMasterStreetLine(m),
        isNull,
        reason:
            'a building number with no street must never render its own '
            'line, even when a city IS present',
      );
    });

    test('4. city only', () {
      final Master m = _master(city: 'Київ');
      expect(buildMasterLocalityLine(m), 'Київ');
      expect(buildMasterStreetLine(m), isNull);
    });

    test('5. street + buildingNo, NO city — the PROMOTION path: the street '
        'line (with its building number attached) is what the caller promotes '
        'to the primary icon-bearing row', () {
      final Master m = _master(street: 'вул. Хрещатик', buildingNo: '22');
      expect(buildMasterLocalityLine(m), isNull);
      expect(buildMasterStreetLine(m), 'вул. Хрещатик, 22');
    });

    test('6. street only, no city, no buildingNo — promotion, bare street', () {
      final Master m = _master(street: 'вул. Хрещатик');
      expect(buildMasterLocalityLine(m), isNull);
      expect(buildMasterStreetLine(m), 'вул. Хрещатик');
    });

    test('7. buildingNo ALONE (no city, no street) — both helpers return null; '
        'the caller\'s `if (localityLine != null || streetLine != null)` gate '
        'must hide the WHOLE location row rather than orphaning the building '
        'number', () {
      final Master m = _master(buildingNo: '22');
      expect(buildMasterLocalityLine(m), isNull);
      expect(buildMasterStreetLine(m), isNull);
    });

    test('8. nothing set — both null, row hidden', () {
      final Master m = _master();
      expect(buildMasterLocalityLine(m), isNull);
      expect(buildMasterStreetLine(m), isNull);
    });
  });
}
