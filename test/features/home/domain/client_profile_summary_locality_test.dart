// Audit (2026-09-24, security LOW) — `ClientProfileSummary.localityLabel`
// appends server strings (the district, and the bare-city fallback) to the
// profile line. Both must go through the same sanitise rule the composed
// settlement label already gets, so a bidi override or zero-width character
// cannot reorder or hide part of the line.

import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:flutter_test/flutter_test.dart';

ClientProfileSummary _summary({required String city, String? district}) =>
    ClientProfileSummary(
      firstName: 'Олена',
      lastName: 'Коваль',
      city: city,
      phone: '',
      clientRating: null,
      memberSinceYear: 2024,
      districtName: district,
    );

void main() {
  group('ClientProfileSummary.localityLabel sanitises what it appends', () {
    test(
      'a district with bidi/zero-width characters and a newline renders cleaned',
      () {
        final String label = _summary(
          city: 'Львів',
          district: '\u202EСихів\u200Bський\nрайон\u202C',
        ).localityLabel('м. Львів, Львівська обл.');

        expect(label, 'м. Львів, Львівська обл., Сихівський район');
      },
    );

    test('a district that reduces to nothing is dropped with its comma', () {
      expect(
        _summary(
          city: 'Львів',
          district: '\u200B \u202E',
        ).localityLabel('м. Львів, Львівська обл.'),
        'м. Львів, Львівська обл.',
      );
    });

    test('the bare-city fallback is sanitised too', () {
      expect(
        _summary(city: ' Льв\u200Bів\u202E ').localityLabel(null),
        'Львів',
      );
      expect(_summary(city: '\u200B').localityLabel(null), '');
    });
  });
}
