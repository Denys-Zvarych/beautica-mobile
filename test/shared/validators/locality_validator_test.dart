// Phase 2.19 — Pure-Dart unit tests for validateProviderLocality().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Mirrors the backend Phase 10.6 locality matrix:
//   CLIENT             → never blocking (the screen never calls this for
//                        CLIENT; validator is only ever invoked for providers).
//   INDEPENDENT_MASTER → oblast + city required; district required ONLY when
//   / SALON_OWNER        the chosen city has districts (most-specific-node
//                        ordering: oblast → city → district).
//
// Covered scenarios:
//   1. null oblast                       → errLocalityOblastRequired
//   2. empty oblast                      → errLocalityOblastRequired
//   3. oblast set, null city             → errLocalityCityRequired
//   4. oblast set, empty city            → errLocalityCityRequired
//   5. leaf city (hasDistricts=false), null district → null (district must be
//      null OK)
//   6. non-leaf city (hasDistricts=true), null district → errLocalityDistrict
//   7. non-leaf city, empty district     → errLocalityDistrict
//   8. non-leaf city, district set       → null
//   9. leaf city with district set       → null (district tolerated, not
//      required)
//  10. ordering — oblast error wins when both oblast and city are missing.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/locality_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errLocalityOblastRequired => 'oblast_required';

  @override
  String get errLocalityCityRequired => 'city_required';

  @override
  String get errLocalityDistrictRequired => 'district_required';
}

void main() {
  final l10n = _FakeL10n();

  group('validateProviderLocality — oblast (most-specific-node ordering)', () {
    test('null oblast → errLocalityOblastRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: null,
          cityId: 'c1',
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        equals('oblast_required'),
      );
    });

    test('empty oblast → errLocalityOblastRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: '',
          cityId: 'c1',
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        equals('oblast_required'),
      );
    });

    test('oblast error wins when both oblast and city are missing', () {
      expect(
        validateProviderLocality(
          oblastCode: null,
          cityId: null,
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        equals('oblast_required'),
      );
    });
  });

  group('validateProviderLocality — city', () {
    test('oblast set, null city → errLocalityCityRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: null,
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        equals('city_required'),
      );
    });

    test('oblast set, empty city → errLocalityCityRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: '',
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        equals('city_required'),
      );
    });
  });

  group('validateProviderLocality — district (leaf vs non-leaf)', () {
    test('leaf city (no districts), null district → null', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c2',
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        isNull,
      );
    });

    test('leaf city with a district set → null (district tolerated)', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c2',
          districtId: 'd1',
          cityHasDistricts: false,
          l10n: l10n,
        ),
        isNull,
      );
    });

    test('non-leaf city, null district → errLocalityDistrictRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: null,
          cityHasDistricts: true,
          l10n: l10n,
        ),
        equals('district_required'),
      );
    });

    test('non-leaf city, empty district → errLocalityDistrictRequired', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: '',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        equals('district_required'),
      );
    });

    test('non-leaf city, district set → null (fully valid)', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        isNull,
      );
    });
  });
}
