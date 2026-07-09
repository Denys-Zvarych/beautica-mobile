// Regression — SalonMapper.fromDto field-mapping unit tests.
//
// WHY THIS FILE EXISTS
// ---------------------
// The public salon-profile "no location at all" bug (mobile-side half of the
// two-layered regression alongside backend commit `ef96845`) was NOT a
// rendering bug — `_buildLocationLine` in `public_salon_profile_screen.dart`
// was already correct. The actual defect was one layer below: even after the
// OpenAPI client was regenerated with the new `PublicSalonResponse` taxonomy
// fields (`cityId`/`districtId`/`street`/`buildingNo`/`locationNote`),
// [SalonMapper.fromDto] never read them off the DTO — every [Salon] built
// from a real HTTP response had those fields silently `null`, no matter what
// the backend sent.
//
// The widget tests in `public_salon_profile_screen_test.dart` construct
// [Salon] fixtures directly in Dart, bypassing this exact translation
// boundary — they prove the screen renders correctly GIVEN a populated
// [Salon], but cannot prove the DTO's wire fields ever reach it. This file
// closes that gap: it is the most direct regression guard for the actual bug,
// asserting the DTO→domain field-by-field mapping the way
// `user_mapper_test.dart` does for the equivalent [User] location fields.
//
// Pure Dart unit test: no widget tree, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a DTO carrying ONLY the Phase 10.6+ taxonomy locality fields — the
/// shape every salon created/edited since Phase 10.6 actually has (legacy
/// `city`/`address` are null because the backend stopped writing them).
PublicSalonResponse _taxonomyOnlyDto() => PublicSalonResponse(
  (b) => b
    ..id = 'salon-1'
    ..name = 'Салон «Вельвет»'
    ..reviewCount = 0
    ..cityId = 'city-uuid-1'
    ..districtId = 'district-uuid-1'
    ..street = 'вул. Хрещатик'
    ..buildingNo = '22'
    ..locationNote = '2 поверх',
);

/// Builds a DTO carrying ONLY the legacy free-text pair — a salon that
/// predates Phase 10.6 and has never been re-saved since.
PublicSalonResponse _legacyOnlyDto() => PublicSalonResponse(
  (b) => b
    ..id = 'salon-2'
    ..name = 'Салон «Гармонія»'
    ..reviewCount = 0
    ..city = 'Київ'
    ..address = 'вул. Велика Васильківська, 44',
);

/// Builds a DTO with NEITHER taxonomy NOR legacy location fields.
PublicSalonResponse _locationlessDto() => PublicSalonResponse(
  (b) => b
    ..id = 'salon-3'
    ..name = 'Салон без адреси'
    ..reviewCount = 0,
);

void main() {
  group('SalonMapper.fromDto', () {
    test('maps all 5 taxonomy locality fields (cityId/districtId/street/'
        'buildingNo/locationNote) from the DTO onto the domain Salon', () {
      final salon = SalonMapper.fromDto(_taxonomyOnlyDto());

      expect(salon.cityId, 'city-uuid-1');
      expect(salon.districtId, 'district-uuid-1');
      expect(salon.street, 'вул. Хрещатик');
      expect(salon.buildingNo, '22');
      expect(salon.locationNote, '2 поверх');
      // The legacy pair must stay null — this DTO never sent them.
      expect(salon.city, isNull);
      expect(salon.address, isNull);
    });

    test('maps the legacy city/address pair when the DTO carries no taxonomy '
        'fields (backward compat for pre-Phase-10.6 salons)', () {
      final salon = SalonMapper.fromDto(_legacyOnlyDto());

      expect(salon.city, 'Київ');
      expect(salon.address, 'вул. Велика Васильківська, 44');
      expect(salon.cityId, isNull);
      expect(salon.street, isNull);
      expect(salon.buildingNo, isNull);
      expect(salon.locationNote, isNull);
    });

    test('leaves every locality field null when the DTO carries neither '
        'taxonomy nor legacy location data', () {
      final salon = SalonMapper.fromDto(_locationlessDto());

      expect(salon.cityId, isNull);
      expect(salon.districtId, isNull);
      expect(salon.street, isNull);
      expect(salon.buildingNo, isNull);
      expect(salon.locationNote, isNull);
      expect(salon.city, isNull);
      expect(salon.address, isNull);
    });

    test('throws ServerFailure when the DTO id is null', () {
      final PublicSalonResponse dto = PublicSalonResponse(
        (b) => b
          ..name = 'Без ідентифікатора'
          ..reviewCount = 0,
      );

      expect(() => SalonMapper.fromDto(dto), throwsA(isA<ServerFailure>()));
    });
  });

  // The salon master rail card renders `professionalTitle` when set (see
  // `public_salon_profile_screen_test.dart` → 'master role label'). Those
  // widget tests build [SalonMasterSummary] fixtures directly in Dart,
  // bypassing this translation boundary — so, exactly like the location-field
  // gap documented at the top of this file, they prove the SCREEN renders the
  // title but not that the DTO's `professionalTitle` wire field ever reaches
  // the domain model. This closes that gap.
  group('SalonMasterMapper.fromDtoList', () {
    MasterSummaryResponse masterDto({String? professionalTitle}) =>
        MasterSummaryResponse(
          (b) => b
            ..masterId = 'master-1'
            ..firstName = 'Ірина'
            ..lastName = 'Мороз'
            ..professionalTitle = professionalTitle
            ..reviewCount = 0
            ..masterType = MasterSummaryResponseMasterTypeEnum.SALON_MASTER,
        );

    test('passes professionalTitle through from the DTO onto the domain '
        'summary', () {
      final summaries = SalonMasterMapper.fromDtoList(<MasterSummaryResponse>[
        masterDto(professionalTitle: 'Топ-стиліст'),
      ]);

      expect(summaries, hasLength(1));
      expect(summaries.single.professionalTitle, 'Топ-стиліст');
    });

    test('leaves professionalTitle null when the DTO omits it', () {
      final summaries = SalonMasterMapper.fromDtoList(<MasterSummaryResponse>[
        masterDto(),
      ]);

      expect(summaries, hasLength(1));
      expect(summaries.single.professionalTitle, isNull);
    });
  });
}
