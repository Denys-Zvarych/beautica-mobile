// Unit tests for MasterMapper.fromDto — professionalTitle normalisation.
//
// WHY THIS FILE EXISTS
// --------------------
// The professionalTitle feature (feat/provider-professional-title) added
// empty→null normalisation in [MasterMapper.fromDto]:
//
//   professionalTitle: dto.professionalTitle?.isEmpty == true
//       ? null
//       : dto.professionalTitle,
//
// These tests pin that contract so a future mapper change cannot
// silently break the null-guard (which the UI uses to conditionally
// render the title row).
//
// Layer: Unit — pure Dart; no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/master/data/master_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MasterMapper.fromDto — professionalTitle normalisation', () {
    MasterDetailResponse _build({required String? professionalTitle}) =>
        (MasterDetailResponseBuilder()
              ..masterId = 'master-1'
              ..firstName = 'Оля'
              ..lastName = 'Коваль'
              ..avgRating = 4.5
              ..reviewCount = 0
              ..masterType =
                  MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER
              ..professionalTitle = professionalTitle)
            .build();

    test('maps a non-empty professionalTitle from the DTO unchanged', () {
      final master = MasterMapper.fromDto(
        _build(professionalTitle: 'Майстер манікюру'),
      );

      expect(master.professionalTitle, 'Майстер манікюру');
    });

    test('normalises an empty-string professionalTitle to null', () {
      final master = MasterMapper.fromDto(_build(professionalTitle: ''));

      expect(
        master.professionalTitle,
        isNull,
        reason:
            'an empty string from the API must be normalised to null so the '
            'UI null-guard hides the title row correctly',
      );
    });

    test('leaves professionalTitle as null when the DTO omits the field', () {
      final master = MasterMapper.fromDto(_build(professionalTitle: null));

      expect(master.professionalTitle, isNull);
    });

    test(
      'preserves leading/trailing whitespace — trimming is the repository\'s '
      'responsibility, not the mapper\'s',
      () {
        final master = MasterMapper.fromDto(
          _build(professionalTitle: '  Стиліст  '),
        );

        expect(
          master.professionalTitle,
          '  Стиліст  ',
          reason:
              'the mapper must NOT trim — trimming happens in the repository '
              'PATCH body; a value with padding from the server must survive '
              'the mapping boundary unchanged',
        );
      },
    );
  });
}
