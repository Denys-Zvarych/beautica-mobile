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
import 'package:beautica_mobile/features/salon/domain/sibling_salon_option.dart';
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
    // Regression (2026-08-28) — `oblastId` shipped alongside
    // `SalonAddressEditScreen` (backend `dbe27a5`) so
    // `SalonAddressEditScreen._prePopulateLocality` can resolve the locality
    // cascade with a single targeted `oblastId -> cities -> districts`
    // lookup, replacing an earlier "scan every oblast's city list" resolver.
    // `SalonMapper.fromDto` hardcoded this to `null` in the first cut of
    // that work — every gate (analyze, guards, ~1900 tests, two audits)
    // stayed green because nothing asserted the DTO's `oblastId` ever
    // reached the domain `Salon`, so the cascade silently opened unresolved
    // for every salon with a real oblast. This is the direct regression pin.
    ..oblastId = 'oblast-uuid-1'
    ..districtId = 'district-uuid-1'
    ..street = 'вул. Хрещатик'
    ..buildingNo = '22'
    ..locationNote = '2 поверх',
);

/// Builds a DTO carrying the legacy free-text pair ALONGSIDE the now-mandatory
/// `cityId`/`oblastId` — a salon that predates Phase 10.6 and has never been
/// re-saved since (so the legacy strings linger), backfilled with a real city
/// by the RESUME §4 step D migration (backend `ec22d91`, V150/V151) rather
/// than having them cleared. `street`/`buildingNo`/`locationNote` stay unset —
/// the backfill only ever populated the mandatory city/oblast pair, not a
/// full taxonomy address.
///
/// RESUME §4 step D (mobile half, 2026-08-30) — this DTO used to carry NO
/// `cityId` at all (`PublicSalonResponse.cityId` was nullable then); that
/// shape is no longer constructible (`cityId`/`oblastId` are non-null on the
/// wire) or representative (the backend now guarantees every row, including
/// this one, has a real city).
PublicSalonResponse _legacyOnlyDto() => PublicSalonResponse(
  (b) => b
    ..id = 'salon-2'
    ..name = 'Салон «Гармонія»'
    ..reviewCount = 0
    ..cityId = 'city-uuid-legacy'
    ..oblastId = 'oblast-uuid-legacy'
    ..city = 'Київ'
    ..address = 'вул. Велика Васильківська, 44',
);

/// Builds a DTO with the mandatory `cityId`/`oblastId` pair but no other
/// address detail at all (no legacy free-text, no taxonomy street/building/
/// district/note) — the minimal valid shape.
///
/// RESUME §4 step D (mobile half, 2026-08-30) — used to be constructible with
/// NEITHER taxonomy NOR legacy fields at all; `cityId`/`oblastId` are now
/// non-null on the wire (backend `ec22d91`), so that all-blank shape can no
/// longer be built — every real salon has at least this much.
PublicSalonResponse _locationlessDto() => PublicSalonResponse(
  (b) => b
    ..id = 'salon-3'
    ..name = 'Салон без адреси'
    ..reviewCount = 0
    ..cityId = 'city-uuid-3'
    ..oblastId = 'oblast-uuid-3',
);

void main() {
  group('SalonMapper.fromDto', () {
    test('maps all 5 taxonomy locality fields (cityId/districtId/street/'
        'buildingNo/locationNote) from the DTO onto the domain Salon', () {
      final salon = SalonMapper.fromDto(_taxonomyOnlyDto());

      expect(salon.cityId, 'city-uuid-1');
      expect(
        salon.oblastId,
        'oblast-uuid-1',
        reason:
            'a mapper that hardcodes oblastId to null (the actual 2026-08-28 '
            'bug) leaves the SalonAddressEditScreen locality cascade with no '
            'oblast to resolve — this must go red on that regression.',
      );
      expect(salon.districtId, 'district-uuid-1');
      expect(salon.street, 'вул. Хрещатик');
      expect(salon.buildingNo, '22');
      expect(salon.locationNote, '2 поверх');
      // The legacy pair must stay null — this DTO never sent them.
      expect(salon.city, isNull);
      expect(salon.address, isNull);
    });

    test('maps the mandatory cityId/oblastId ALONGSIDE the lingering legacy '
        'city/address pair for a pre-Phase-10.6 salon backfilled with a real '
        'city (RESUME §4 step D)', () {
      final salon = SalonMapper.fromDto(_legacyOnlyDto());

      expect(salon.city, 'Київ');
      expect(salon.address, 'вул. Велика Васильківська, 44');
      expect(salon.cityId, 'city-uuid-legacy');
      expect(salon.oblastId, 'oblast-uuid-legacy');
      expect(salon.street, isNull);
      expect(salon.buildingNo, isNull);
      expect(salon.locationNote, isNull);
    });

    test('leaves every OPTIONAL locality field null when the DTO carries only '
        'the mandatory cityId/oblastId pair', () {
      final salon = SalonMapper.fromDto(_locationlessDto());

      expect(salon.cityId, 'city-uuid-3');
      expect(salon.oblastId, 'oblast-uuid-3');
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
          ..reviewCount = 0
          ..cityId = 'city-uuid-4'
          ..oblastId = 'oblast-uuid-4',
      );

      expect(() => SalonMapper.fromDto(dto), throwsA(isA<ServerFailure>()));
    });
  });

  // Regression (2026-08-28) — `SalonMapper.fromUpdateDto` (`PATCH
  // /salons/{salonId}` / `GET /salons/mine`, `SalonResponse`) carries its OWN
  // `oblastId` mapping line, independent of `fromDto` above — the same
  // "hardcoded null" bug could regress on this path without moving the
  // `fromDto` assertion at all. No prior test exercised this method at all.
  group('SalonMapper.fromUpdateDto', () {
    test('maps oblastId (and cityId) from a SalonResponse DTO', () {
      final SalonResponse dto = SalonResponse(
        (b) => b
          ..id = 'salon-4'
          ..name = 'Салон «Оновлений»'
          ..cityId = 'city-uuid-2'
          ..oblastId = 'oblast-uuid-2'
          ..street = 'вул. Саксаганського'
          ..buildingNo = '5',
      );

      final salon = SalonMapper.fromUpdateDto(dto);

      expect(salon.cityId, 'city-uuid-2');
      expect(salon.oblastId, 'oblast-uuid-2');
    });

    // RESUME §4 step D (mobile half, 2026-08-30) — RETITLED and updated: this
    // used to construct a `SalonResponse` with NO `cityId`/`oblastId` at all
    // to pin "leaves oblastId null when the DTO carries no locality".
    // `SalonResponse.cityId`/`.oblastId` are now non-null on the wire
    // (backend `ec22d91`) — that shape can no longer be built (built_value
    // throws at construction) or occur on a real PATCH response. This now
    // pins the adjacent, still-real gap instead: every OTHER optional
    // address field (street/buildingNo/districtId/locationNote) can still be
    // absent even though cityId/oblastId cannot.
    test('leaves street/buildingNo/districtId null when the DTO carries only '
        'the mandatory cityId/oblastId pair', () {
      final SalonResponse dto = SalonResponse(
        (b) => b
          ..id = 'salon-5'
          ..name = 'Салон без адреси'
          ..cityId = 'city-uuid-5'
          ..oblastId = 'oblast-uuid-5',
      );

      final salon = SalonMapper.fromUpdateDto(dto);

      expect(salon.cityId, 'city-uuid-5');
      expect(salon.oblastId, 'oblast-uuid-5');
      expect(salon.street, isNull);
      expect(salon.buildingNo, isNull);
      expect(salon.districtId, isNull);
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

  // The Phase 21.2 gap: `PublicSalonResponse` carried no `phone` at all, so
  // `fromDto` hard-coded `null` and the owner's «Контакти» block stayed empty
  // until an unrelated PATCH echoed a `SalonResponse` back. The DTO now ships
  // the field; these pin BOTH halves — that it is read, and that the
  // backend's `""`-for-cleared wire value is normalised to `null` rather than
  // reaching the UI as a present-but-empty contact row.
  group('SalonMapper.fromDto — contact fields', () {
    PublicSalonResponse dtoWith({String? phone, String? instagram}) =>
        PublicSalonResponse(
          (b) => b
            ..id = 'salon-1'
            ..name = 'Салон «Вельвет»'
            ..reviewCount = 0
            ..cityId = 'city-uuid-1'
            ..oblastId = 'oblast-uuid-1'
            ..phone = phone
            ..instagramUrl = instagram,
        );

    test(
      'reads phone off the PUBLIC DTO (it is no longer hard-coded null)',
      () {
        final salon = SalonMapper.fromDto(dtoWith(phone: '+380671112233'));
        expect(
          salon.phone,
          '+380671112233',
          reason:
              'a mapper that hard-codes phone to null is the exact bug this '
              'pins — the owner then sees no phone until an unrelated PATCH.',
        );
      },
    );

    test('maps instagramUrl off the PUBLIC DTO', () {
      final salon = SalonMapper.fromDto(dtoWith(instagram: '@velvet'));
      expect(salon.instagramUrl, '@velvet');
    });

    test('normalises a CLEARED field ("" on the wire) to null, for both '
        'contact fields', () {
      final salon = SalonMapper.fromDto(dtoWith(phone: '', instagram: ''));
      expect(salon.phone, isNull);
      expect(salon.instagramUrl, isNull);
    });

    test('normalises a whitespace-only value to null too', () {
      final salon = SalonMapper.fromDto(dtoWith(phone: '   ', instagram: ' '));
      expect(salon.phone, isNull);
      expect(salon.instagramUrl, isNull);
    });

    test('an absent field stays null', () {
      final salon = SalonMapper.fromDto(dtoWith());
      expect(salon.phone, isNull);
      expect(salon.instagramUrl, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 21.6 mobile-qa gap-closure — `SiblingSalonOptionMapper.fromJsonList`
  //
  // The ONE mapper in this file that parses RAW decoded JSON rather than a
  // generated `beautica_api` DTO (backend Phase 21.3b landed after the
  // committed OpenAPI snapshot), so it is the ONE mapper with no compile-time
  // schema behind it — every wire assumption it makes is unchecked unless it
  // is checked here.
  //
  // It fails CLOSED PER ROW: a row it cannot use is dropped and the rest of
  // the picker still renders. That contract is only meaningful if a bad row
  // genuinely cannot take the whole list down, so every case below mixes the
  // malformed row with a GOOD one and asserts the good one survived.
  // ─────────────────────────────────────────────────────────────────────────
  group('SiblingSalonOptionMapper.fromJsonList', () {
    Map<String, dynamic> goodRow() => <String, dynamic>{
      'id': 'salon-2',
      'name': 'Студія «Камелія»',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
    };

    test('maps a complete row verbatim', () {
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[goodRow()]);

      expect(out, hasLength(1));
      expect(out.single.id, 'salon-2');
      expect(out.single.name, 'Студія «Камелія»');
      expect(out.single.street, 'вул. Хрещатик');
      expect(out.single.buildingNo, '12');
    });

    test('drops a row that is not a JSON object, keeping its neighbours', () {
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[
            'not-an-object',
            42,
            null,
            <Object?>['nested', 'list'],
            goodRow(),
          ]);

      expect(
        out.map((SiblingSalonOption o) => o.id),
        <String>['salon-2'],
        reason:
            'four malformed rows must cost four rows, never the whole picker',
      );
    });

    test('drops a row whose id is missing, blank or not a String', () {
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[
            <String, dynamic>{'name': 'Без id'},
            <String, dynamic>{'id': '', 'name': 'Порожній id'},
            <String, dynamic>{'id': 12345, 'name': 'Числовий id'},
            <String, dynamic>{'id': null, 'name': 'Null id'},
            goodRow(),
          ]);

      expect(
        out.map((SiblingSalonOption o) => o.id),
        <String>['salon-2'],
        reason:
            'an option with no id could not be submitted as a rotate '
            'destination — a card that PATCHes nothing is worse than no card',
      );
    });

    test('a non-String or absent name collapses to empty, row still kept', () {
      // The id is what makes the row usable, so a bad NAME must not drop it —
      // the opposite fail-closed direction from `id`. Pinned so the two are
      // not silently unified later.
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[
            <String, dynamic>{'id': 'salon-a'},
            <String, dynamic>{'id': 'salon-b', 'name': 99},
          ]);

      expect(out.map((SiblingSalonOption o) => o.id), <String>[
        'salon-a',
        'salon-b',
      ]);
      expect(out.map((SiblingSalonOption o) => o.name), <String>['', '']);
    });

    test(
      'blank / whitespace / non-String street and buildingNo become null',
      () {
        // `MoveAdminSalonScreen` hands these to `buildStreetLine`, which treats
        // non-null as renderable — a `''` reaching it draws an empty address
        // row under the salon name.
        final List<SiblingSalonOption> out =
            SiblingSalonOptionMapper.fromJsonList(<Object?>[
              <String, dynamic>{
                'id': 'salon-blank',
                'name': 'Порожня адреса',
                'street': '   ',
                'buildingNo': '',
              },
              <String, dynamic>{
                'id': 'salon-typed',
                'name': 'Чужі типи',
                'street': 7,
                'buildingNo': <String>['12'],
              },
              <String, dynamic>{'id': 'salon-absent', 'name': 'Без адреси'},
            ]);

        expect(out, hasLength(3));
        for (final SiblingSalonOption o in out) {
          expect(o.street, isNull, reason: 'street of ${o.id}');
          expect(o.buildingNo, isNull, reason: 'buildingNo of ${o.id}');
        }
      },
    );

    test('trims a padded street and buildingNo', () {
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[
            <String, dynamic>{
              'id': 'salon-pad',
              'name': 'Пробіли',
              'street': '  вул. Хрещатик  ',
              'buildingNo': ' 12 ',
            },
          ]);

      expect(out.single.street, 'вул. Хрещатик');
      expect(out.single.buildingNo, '12');
    });

    test('an empty wire list maps to an empty list, never null', () {
      expect(SiblingSalonOptionMapper.fromJsonList(const <Object?>[]), isEmpty);
    });

    test('preserves wire ORDER — the picker renders rows as sent', () {
      final List<SiblingSalonOption> out =
          SiblingSalonOptionMapper.fromJsonList(<Object?>[
            <String, dynamic>{'id': 'c', 'name': 'C'},
            <String, dynamic>{'id': 'a', 'name': 'A'},
            <String, dynamic>{'id': 'b', 'name': 'B'},
          ]);

      expect(out.map((SiblingSalonOption o) => o.id), <String>['c', 'a', 'b']);
    });
  });
}
