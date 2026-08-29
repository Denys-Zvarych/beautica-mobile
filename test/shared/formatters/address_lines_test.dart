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

  // ── Phase 224 — the COLLAPSED one-line form ───────────────────────────────
  //
  // `buildCombinedAddressLine` is what `MasterAddressBlock` renders when the
  // whole address fits on a single line. It must agree with the two split
  // builders about what the address IS — same blank handling, same
  // building-number-needs-a-street rule — so the collapsed and split
  // renderings can never disagree, only differ in how many rows they use.
  group('buildCombinedAddressLine', () {
    test('1. city + street + buildingNo — city-first, comma-joined', () {
      final String? combined = buildCombinedAddressLine(
        'Київ',
        'вул. Хрещатик',
        '22',
      );
      expect(combined, 'Київ, вул. Хрещатик, 22');
      _expectNoDanglingComma(combined);
    });

    test('2. the pre-220 STREET-FIRST order must never come back', () {
      expect(
        buildCombinedAddressLine('Київ', 'вул. Хрещатик', '22'),
        isNot('вул. Хрещатик, 22, Київ'),
      );
    });

    test('3. city + street, no buildingNo — no trailing comma', () {
      final String? combined = buildCombinedAddressLine(
        'Київ',
        'вул. Хрещатик',
      );
      expect(combined, 'Київ, вул. Хрещатик');
      _expectNoDanglingComma(combined);
    });

    test('4. city only — renders alone, exactly buildLocalityLine', () {
      final String? combined = buildCombinedAddressLine('Київ', null);
      expect(combined, 'Київ');
      expect(combined, buildLocalityLine('Київ'));
      _expectNoDanglingComma(combined);
    });

    test('5. city + buildingNo, NO street — the building is DROPPED, never '
        'left dangling beside the city', () {
      final String? combined = buildCombinedAddressLine('Київ', null, '22');
      expect(combined, 'Київ');
      expect(combined, isNot(contains('22')));
      _expectNoDanglingComma(combined);
    });

    test('6. street + buildingNo, NO city — no leading comma; identical to '
        'the promoted street line', () {
      final String? combined = buildCombinedAddressLine(
        null,
        'вул. Хрещатик',
        '22',
      );
      expect(combined, 'вул. Хрещатик, 22');
      expect(combined, buildStreetLine('вул. Хрещатик', '22'));
      _expectNoDanglingComma(combined);
    });

    test('7. street only — bare street, no commas at all', () {
      final String? combined = buildCombinedAddressLine(null, 'вул. Хрещатик');
      expect(combined, 'вул. Хрещатик');
      _expectNoDanglingComma(combined);
    });

    test('8. buildingNo ALONE — null, so the caller hides the whole row', () {
      expect(buildCombinedAddressLine(null, null, '22'), isNull);
    });

    test('9. nothing set — null', () {
      expect(buildCombinedAddressLine(null, null), isNull);
    });

    test('10. blank (empty-string) fields are treated exactly like null — no '
        'empty segments, no doubled commas', () {
      expect(buildCombinedAddressLine('', '', ''), isNull);
      _expectNoDanglingComma(buildCombinedAddressLine('', 'вул. Хрещатик', ''));
      expect(
        buildCombinedAddressLine('', 'вул. Хрещатик', ''),
        'вул. Хрещатик',
      );
      expect(buildCombinedAddressLine('Київ', '', '22'), 'Київ');
    });

    test('11. is null EXACTLY when both split builders are null — the call '
        'sites gate the whole block on this equivalence', () {
      for (final (String? city, String? street, String? building)
          in <(String?, String?, String?)>[
            ('Київ', 'вул. Хрещатик', '22'),
            ('Київ', 'вул. Хрещатик', null),
            ('Київ', null, '22'),
            ('Київ', null, null),
            (null, 'вул. Хрещатик', '22'),
            (null, 'вул. Хрещатик', null),
            (null, null, '22'),
            (null, null, null),
          ]) {
        final bool splitHasContent =
            buildLocalityLine(city) != null ||
            buildStreetLine(street, building) != null;
        expect(
          buildCombinedAddressLine(city, street, building) != null,
          splitHasContent,
          reason: 'gate disagreement for ($city, $street, $building)',
        );
      }
    });

    test('12. is routed through sanitizeDisplayText like its siblings — a '
        'bidi override in any field is stripped, not passed through', () {
      // U+202E = Right-to-Left Override. Built via `String.fromCharCode` so
      // this source file never embeds the raw control byte it exists to
      // strip. Backend validation on these fields is `@Size`-only.
      final String rlo = String.fromCharCode(0x202E);
      final String? combined = buildCombinedAddressLine(
        'Київ$rlo',
        'вул. Хрещатик',
        '22',
      );
      expect(combined, 'Київ, вул. Хрещатик, 22');
      expect(combined, isNot(contains(rlo)));
    });
  });

  // ── Phase 224 audit fix — SANITIZE-THEN-TEST ORDERING ─────────────────────
  //
  // Every builder used to test emptiness on the RAW field and sanitize only
  // afterwards. A field made entirely of characters `sanitizeDisplayText`
  // strips is `isNotEmpty` before sanitization and empty after it, so it
  // passed the presence test, CLAIMED A SEPARATOR, and then rendered as
  // nothing — leaving the separator orphaned. Whitespace-only fields had the
  // same shape (`buildLocalityLine` named its local `trimmed` while never
  // calling `trim()`).
  //
  // All three builders now sanitize FIRST, trim, and drop a segment that
  // reduces to nothing — so the segment takes its separator with it. These
  // cases are grouped together because the whole point is that the three
  // builders agree: a field invisible to one must be invisible to all, or the
  // collapsed and split renderings of the SAME address disagree inside the
  // same widget.
  group('invisible fields take their separator with them', () {
    // U+200B ZERO WIDTH SPACE — built via `String.fromCharCode` so this file
    // never embeds the raw character it exists to test.
    final String zwsp = String.fromCharCode(0x200B);

    test('buildCombinedAddressLine: a zero-width-only CITY produces no '
        'leading comma (the split path never produced one)', () {
      final String? combined = buildCombinedAddressLine(
        zwsp,
        'вул. Хрещатик',
        '22',
      );
      expect(combined, 'вул. Хрещатик, 22');
      _expectNoDanglingComma(combined);
    });

    test('buildCombinedAddressLine: a zero-width-only BUILDING produces no '
        'trailing comma', () {
      final String? combined = buildCombinedAddressLine(
        'Київ',
        'вул. Хрещатик',
        zwsp,
      );
      expect(combined, 'Київ, вул. Хрещатик');
      _expectNoDanglingComma(combined);
    });

    test('buildCombinedAddressLine: a zero-width-only STREET drops the '
        'building with it, exactly like a null street', () {
      final String? combined = buildCombinedAddressLine('Київ', zwsp, '22');
      expect(combined, 'Київ');
      expect(combined, isNot(contains('22')));
      _expectNoDanglingComma(combined);
    });

    test('buildStreetLine: a zero-width-only BUILDING produces no trailing '
        'comma', () {
      final String? line = buildStreetLine('вул. Хрещатик', zwsp);
      expect(line, 'вул. Хрещатик');
      _expectNoDanglingComma(line);
    });

    test('buildStreetLine: a zero-width-only STREET is absent → null', () {
      expect(buildStreetLine(zwsp, '22'), isNull);
    });

    test('buildLocalityLine: a zero-width-only city is absent → null, not an '
        'empty string that still occupies a row', () {
      expect(buildLocalityLine(zwsp), isNull);
    });

    test('buildLocalityLine: a WHITESPACE-only city is absent → null (it used '
        'to render as literal spaces)', () {
      expect(buildLocalityLine('   '), isNull);
      expect(buildLocalityLine('\t\n '), isNull);
    });

    test('buildStreetLine / buildCombinedAddressLine: whitespace-only fields '
        'are absent everywhere', () {
      expect(buildStreetLine('  ', '22'), isNull);
      expect(buildStreetLine('вул. Хрещатик', '  '), 'вул. Хрещатик');
      expect(buildCombinedAddressLine('  ', '  ', '  '), isNull);
      expect(
        buildCombinedAddressLine('  ', 'вул. Хрещатик', '22'),
        'вул. Хрещатик, 22',
      );
    });

    test('surrounding whitespace is trimmed, so a comma-joined line never '
        'shows "Київ , вул. X"', () {
      expect(buildLocalityLine('  Київ  '), 'Київ');
      expect(buildStreetLine('  вул. Хрещатик ', ' 22 '), 'вул. Хрещатик, 22');
      expect(
        buildCombinedAddressLine(' Київ ', ' вул. Хрещатик ', ' 22 '),
        'Київ, вул. Хрещатик, 22',
      );
    });

    test('the collapsed and split builders agree on EVERY invisible-field '
        'combination — a field hidden by one must be hidden by all', () {
      final List<String?> variants = <String?>[
        null,
        '',
        '   ',
        zwsp,
        '$zwsp  ',
        'Київ',
      ];
      for (final String? city in variants) {
        for (final String? street in variants) {
          for (final String? building in variants) {
            final String? locality = buildLocalityLine(city);
            final String? road = buildStreetLine(street, building);
            final String? combined = buildCombinedAddressLine(
              city,
              street,
              building,
            );
            final String label = '($city, $street, $building)';

            // Gate equivalence — both master screens render the whole address
            // block on `combined != null` and the split rows on the other two.
            expect(
              combined != null,
              locality != null || road != null,
              reason: 'gate disagreement for $label',
            );
            // Content equivalence — the collapsed line IS the split lines,
            // joined. If these ever diverge the two paths show different
            // addresses for the same master.
            expect(
              combined,
              <String>[?locality, ?road].isEmpty
                  ? isNull
                  : <String>[?locality, ?road].join(', '),
              reason: 'content disagreement for $label',
            );
            // No builder ever emits an orphaned separator or a blank line.
            _expectNoDanglingComma(locality);
            _expectNoDanglingComma(road);
            _expectNoDanglingComma(combined);
            for (final String? line in <String?>[locality, road, combined]) {
              expect(
                line,
                anyOf(isNull, isNot(isEmpty)),
                reason: 'empty (non-null) line for $label',
              );
              if (line != null) {
                expect(
                  line.trim(),
                  line,
                  reason: 'untrimmed line "$line" for $label',
                );
              }
            }
          }
        }
      }
    });
  });

  // mobile-qa gap-closure (2026-08-29) — `buildFullAddressLine` shipped
  // (Phase 21.14) with zero unit coverage in this file: the salon
  // management/hub widget tests exercise it only THROUGH a full provider +
  // widget pump, which cannot cheaply enumerate the oblast × city × district
  // × street × buildingNo presence matrix the way a pure-Dart unit test can.
  group('buildFullAddressLine', () {
    test('all five segments present — hierarchy order: oblast, city, '
        'district, street, building', () {
      expect(
        buildFullAddressLine(
          oblastName: 'Львівська область',
          cityName: 'Львів',
          districtName: 'Галицький',
          street: 'вул. Личаківська',
          buildingNo: '20',
        ),
        'Львівська область, Львів, Галицький, вул. Личаківська, 20',
      );
    });

    test('district omitted — the remaining segments stay in order with no '
        'dangling comma', () {
      final String? result = buildFullAddressLine(
        oblastName: 'Львівська область',
        cityName: 'Львів',
        street: 'вул. Личаківська',
        buildingNo: '20',
      );
      expect(result, 'Львівська область, Львів, вул. Личаківська, 20');
      _expectNoDanglingComma(result);
    });

    test('oblast + city only, no street/building/district', () {
      expect(
        buildFullAddressLine(
          oblastName: 'Львівська область',
          cityName: 'Львів',
        ),
        'Львівська область, Львів',
      );
    });

    test('street + buildingNo only, no oblast/city/district — the promotion '
        'path a pre-taxonomy salon\'s fallback relies on', () {
      expect(
        buildFullAddressLine(street: 'вул. Личаківська', buildingNo: '20'),
        'вул. Личаківська, 20',
      );
    });

    test('buildingNo with NO street is dropped — never dangles alone or '
        'beside oblast/city', () {
      final String? result = buildFullAddressLine(
        oblastName: 'Львівська область',
        cityName: 'Львів',
        buildingNo: '20',
      );
      expect(result, 'Львівська область, Львів');
      _expectNoDanglingComma(result);
    });

    test('nothing set at all — null, so the caller can fall back to the '
        'legacy salon.address', () {
      expect(buildFullAddressLine(), isNull);
    });

    test('every field blank/whitespace-only — null, exactly like every '
        'field being absent', () {
      expect(
        buildFullAddressLine(
          oblastName: '   ',
          cityName: '',
          districtName: '   ',
          street: '',
          buildingNo: '   ',
        ),
        isNull,
      );
    });

    test('a zero-width-only district is treated as absent — no doubled '
        'comma between city and street', () {
      final String? result = buildFullAddressLine(
        oblastName: 'Львівська область',
        cityName: 'Львів',
        districtName: '​',
        street: 'вул. Личаківська',
      );
      expect(result, 'Львівська область, Львів, вул. Личаківська');
      _expectNoDanglingComma(result);
    });

    test('routed through sanitizeDisplayText like the other three builders '
        '— surrounding whitespace is trimmed on every segment', () {
      expect(
        buildFullAddressLine(
          oblastName: '  Львівська область  ',
          cityName: '  Львів  ',
          street: '  вул. Личаківська  ',
        ),
        'Львівська область, Львів, вул. Личаківська',
      );
    });
  });
}
