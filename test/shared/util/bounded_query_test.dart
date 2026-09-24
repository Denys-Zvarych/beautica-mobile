// Phase 346 L2 — `boundSearchQuery`: the one bound shared by the settlement
// sheet (family key) and the repository (wire text).

import 'package:beautica_mobile/shared/util/bounded_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a term within the limit is only trimmed', () {
    expect(boundSearchQuery('  Львів  ', 50), 'Львів');
  });

  test('a longer term is cut to the limit in UTF-16 units', () {
    final String out = boundSearchQuery('а' * 80, 50);
    expect(out.length, 50);
  });

  test(
    'never splits a surrogate pair — a straddling emoji is dropped whole',
    () {
      // 49 BMP units + one 2-unit emoji = 51 units.
      final String input = '${'а' * 49}\u{1F600}';
      final String out = boundSearchQuery(input, 50);
      expect(out, 'а' * 49);
      expect(out.runes.every((int r) => r < 0xD800 || r > 0xDFFF), isTrue);
    },
  );

  test('a cut landing after a space leaves no trailing space', () {
    final String input = '${'а' * 49} б';
    expect(boundSearchQuery(input, 50), 'а' * 49);
  });

  test('is idempotent, so the repository re-bounding the sheet key is a '
      'no-op', () {
    for (final String raw in <String>[
      'Кам’янка',
      '${'а' * 49}\u{1F600}',
      '${'а' * 49} б',
      'а' * 120,
    ]) {
      final String once = boundSearchQuery(raw, 50);
      expect(boundSearchQuery(once, 50), once);
    }
  });
}
