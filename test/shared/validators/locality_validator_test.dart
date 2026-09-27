// Phase 2.19 — Pure-Dart unit tests for validateProviderLocality().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Phase 346 — the «Область» step (and `oblastCode`/`LocalityLevel.oblast` with
// it) is GONE. The validator now only ever routes to `LocalityLevel.city` (the
// settlement, still the `cityId` field) or `LocalityLevel.district`. Mirrors
// the backend Phase 10.6 locality matrix, minus the retired oblast node:
//
//   CLIENT             → never blocking (the screen never calls this for
//                        CLIENT; validator is only ever invoked for providers).
//   INDEPENDENT_MASTER → cityId (the settlement) required; district required
//   / SALON_OWNER        ONLY when the chosen settlement has districts.
//
// Covered scenarios:
//   1. null cityId                        → errSettlementRequired
//   2. empty cityId                       → errSettlementRequired
//   3. leaf city (hasDistricts=false), null district → null (district must be
//      null OK)
//   4. non-leaf city (hasDistricts=true), null district → errLocalityDistrict
//   5. non-leaf city, empty district      → errLocalityDistrict
//   6. non-leaf city, district set        → null
//   7. leaf city with district set        → null (district tolerated, not
//      required)
//
// Deleted vs the pre-346 suite (concepts no longer exist, not weakened):
//   - "null oblast → oblast-level error" / "empty oblast → oblast-level
//     error" — `oblastCode` is gone from the signature and `LocalityLevel
//     .oblast` no longer exists; there is nothing left to assert.
//   - "oblast error wins when both oblast and city are missing" — this pinned
//     the ORDERING between the (now-removed) oblast level and the city level.
//     With only two levels left (city, district) there is no such ordering
//     question: a missing cityId always resolves to `LocalityLevel.city`,
//     already covered by cases 1-2 above.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/locality_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errSettlementRequired => 'settlement_required';

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

  group('validateProviderLocality — settlement (cityId)', () {
    test('null cityId → settlement-level error', () {
      expect(
        validateProviderLocality(
          cityId: null,
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        _isError(LocalityLevel.city, 'settlement_required'),
      );
    });

    test('empty cityId → settlement-level error', () {
      expect(
        validateProviderLocality(
          cityId: '',
          districtId: null,
          cityHasDistricts: false,
          l10n: l10n,
        ),
        _isError(LocalityLevel.city, 'settlement_required'),
      );
    });

    test('null cityId → settlement-level error even when cityHasDistricts is '
        'true and a district is supplied (settlement check runs first)', () {
      expect(
        validateProviderLocality(
          cityId: null,
          districtId: 'd1',
          cityHasDistricts: true,
          l10n: l10n,
        ),
        _isError(LocalityLevel.city, 'settlement_required'),
      );
    });
  });

  group('validateProviderLocality — district (leaf vs non-leaf)', () {
    test('leaf city (no districts), null district → null', () {
      expect(
        validateProviderLocality(
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
