// Search-page change (item 6) — unit tests for the address-line folding in the
// DTO → domain mappers ([MasterSearchMapper]/[SalonSearchMapper]).
//
// The private `_formatAddressLine(street, buildingNo, note)` precomputes the
// auth-gated «street, buildingNo · note» line ONCE at map time (so the
// scrolling result list never re-joins per card build()). It is exercised here
// through the PUBLIC `fromDto`, asserting the precomputed `addressLine` on the
// emitted domain item. The note (`locationNote`) is the new fold introduced by
// the two-line address layout.
//
// Contract pinned (street anchors the line):
//   • street + buildingNo + note → «street, buildingNo · note»
//   • street + buildingNo, no note → «street, buildingNo» (NO dangling « · »)
//   • street alone → «street»
//   • note present but street null → addressLine null (a note alone does NOT
//     render — there is no anchor to hang it on)
//   • all null / blank → addressLine null
//
// Region/oblast is NOT in the search contract, so it can never reach the
// addressLine — there is nothing to assert-against beyond the fields above.
//
// Pure mapper unit test — no network, no Dio, no provider graph.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/discovery/data/search_mapper.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// DTO fixtures — only the address fields vary; everything else is held valid.
// ---------------------------------------------------------------------------

MasterSearchResult _masterDto({
  String? street,
  String? buildingNo,
  String? locationNote,
}) =>
    (MasterSearchResultBuilder()
          ..masterId = 'master-1'
          ..firstName = 'Олена'
          ..lastName = 'Коваль'
          ..avgRating = 4.8
          ..reviewCount = 12
          ..cityLabel = 'Київ'
          ..districtLabel = 'Печерський'
          ..minEffectivePrice = 500
          ..street = street
          ..buildingNo = buildingNo
          ..locationNote = locationNote
          ..serviceNames = ListBuilder<String>(const <String>['Манікюр']))
        .build();

SalonSearchResult _salonDto({
  String? street,
  String? buildingNo,
  String? locationNote,
}) =>
    (SalonSearchResultBuilder()
          ..salonId = 'salon-1'
          ..name = 'Студія Краси «Камелія»'
          ..cityLabel = 'Київ'
          ..districtLabel = 'Печерський'
          ..priceMin = 300
          ..priceMax = 1200
          ..street = street
          ..buildingNo = buildingNo
          ..locationNote = locationNote
          ..serviceNames = ListBuilder<String>(const <String>['Манікюр']))
        .build();

void main() {
  // Run the identical address-folding matrix against BOTH mappers so neither
  // side can regress independently.
  group('MasterSearchMapper.addressLine — _formatAddressLine fold', () {
    test('street + buildingNo + note → «street, buildingNo · note»', () {
      final item = MasterSearchMapper.fromDto(
        _masterDto(
          street: 'вул. Хрещатик',
          buildingNo: '22',
          locationNote: 'вхід з двору',
        ),
      );

      expect(item.addressLine, 'вул. Хрещатик, 22 · вхід з двору');
    });

    test(
      'street + buildingNo, no note → «street, buildingNo» (no dangling « · »)',
      () {
        final item = MasterSearchMapper.fromDto(
          _masterDto(street: 'вул. Хрещатик', buildingNo: '22'),
        );

        expect(item.addressLine, 'вул. Хрещатик, 22');
        expect(
          item.addressLine,
          isNot(contains(' · ')),
          reason: 'an absent note must not leave a trailing « · » separator.',
        );
      },
    );

    test('street alone (no buildingNo) → «street»', () {
      final item = MasterSearchMapper.fromDto(
        _masterDto(street: 'вул. Хрещатик'),
      );

      expect(item.addressLine, 'вул. Хрещатик');
    });

    test(
      'note present but street null → addressLine null (note needs anchor)',
      () {
        final item = MasterSearchMapper.fromDto(
          _masterDto(locationNote: 'вхід з двору'),
        );

        expect(
          item.addressLine,
          isNull,
          reason:
              'a location note alone never renders without a street anchor.',
        );
      },
    );

    test('all address fields null → addressLine null (anonymous browse)', () {
      final item = MasterSearchMapper.fromDto(_masterDto());

      expect(item.addressLine, isNull);
    });

    test(
      'blank/whitespace fields are treated as absent → addressLine null',
      () {
        final item = MasterSearchMapper.fromDto(
          _masterDto(street: '   ', buildingNo: '  ', locationNote: '  '),
        );

        expect(item.addressLine, isNull);
      },
    );
  });

  group('SalonSearchMapper.addressLine — _formatAddressLine fold', () {
    test('street + buildingNo + note → «street, buildingNo · note»', () {
      final item = SalonSearchMapper.fromDto(
        _salonDto(
          street: 'вул. Сагайдачного',
          buildingNo: '10А',
          locationNote: '2 поверх',
        ),
      );

      expect(item.addressLine, 'вул. Сагайдачного, 10А · 2 поверх');
    });

    test(
      'street + buildingNo, no note → «street, buildingNo» (no dangling « · »)',
      () {
        final item = SalonSearchMapper.fromDto(
          _salonDto(street: 'вул. Сагайдачного', buildingNo: '10А'),
        );

        expect(item.addressLine, 'вул. Сагайдачного, 10А');
        expect(item.addressLine, isNot(contains(' · ')));
      },
    );

    test(
      'note present but street null → addressLine null (note needs anchor)',
      () {
        final item = SalonSearchMapper.fromDto(
          _salonDto(locationNote: '2 поверх'),
        );

        expect(item.addressLine, isNull);
      },
    );

    test('all address fields null → addressLine null (anonymous browse)', () {
      final item = SalonSearchMapper.fromDto(_salonDto());

      expect(item.addressLine, isNull);
    });
  });
}
