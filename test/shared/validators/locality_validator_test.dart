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

/// Matcher helper — asserts a [LocalityValidationError] with the given level
/// and message (Defect 7: the validator now returns BOTH so the screen can
/// attach the message to the matching row).
Matcher _isError(LocalityLevel level, String message) =>
    isA<LocalityValidationError>()
        .having((e) => e.level, 'level', level)
        .having((e) => e.message, 'message', message);

void main() {
  final l10n = _FakeL10n();

  group('validateProviderLocality — oblast (most-specific-node ordering)', () {
    test('null oblast → oblast-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: null,
          cityId: 'c1',
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        _isError(LocalityLevel.oblast, 'oblast_required'),
      );
    });

    test('empty oblast → oblast-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: '',
          cityId: 'c1',
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        _isError(LocalityLevel.oblast, 'oblast_required'),
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
        _isError(LocalityLevel.oblast, 'oblast_required'),
      );
    });
  });

  group('validateProviderLocality — city', () {
    test('oblast set, null city → city-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: null,
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        _isError(LocalityLevel.city, 'city_required'),
      );
    });

    test('oblast set, empty city → city-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: '',
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        _isError(LocalityLevel.city, 'city_required'),
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

    test('non-leaf city, null district → district-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: null,
          cityHasDistricts: true,
          l10n: l10n,
        ),
        _isError(LocalityLevel.district, 'district_required'),
      );
    });

    test('non-leaf city, empty district → district-level error', () {
      expect(
        validateProviderLocality(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: '',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        _isError(LocalityLevel.district, 'district_required'),
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
