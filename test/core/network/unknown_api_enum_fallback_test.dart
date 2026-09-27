// Audit (2026-09-24, security MEDIUM) — a wire enum value this build predates
// must NEVER fail a whole response.
//
// Before `enumUnknownDefaultCase=true` (`scripts/regenerate_api.sh`), the
// generated built_value enums threw on any unknown value. `citySettlementType`
// now rides on `/users/me`, so one new backend settlement type would have
// failed the profile read — and a failed cold-start `/users/me` wiped the
// stored session. These tests decode REAL JSON through the app's own
// serializers (`beauticaSerializers`) and prove:
//   - an unknown `citySettlementType` decodes to the fallback, and the saved
//     label then carries NO prefix (the fallback is mapped to null, never
//     handed to `composeSettlementLabel` as a type);
//   - an unknown role becomes a typed `UnknownFailure`, never an Error;
//   - an unknown `masterType` fails safe to `MasterType.salonMaster`.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/features/auth/data/user_mapper.dart';
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/features/master/data/master_mapper.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_mapper.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

T _decode<T>(Serializer<T> serializer, Map<String, Object?> json) =>
    beauticaSerializers.deserializeWith(serializer, json) as T;

void main() {
  final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));

  // What the label reads with NO type: the bare, sanitised name.
  const String bareLabel = 'Львів';

  group('an unknown citySettlementType («HAMLET») decodes to the fallback and '
      'the saved label carries no prefix', () {
    test('UserProfileResponse', () {
      late final UserProfileResponse dto;
      expect(
        () => dto = _decode(UserProfileResponse.serializer, <String, Object?>{
          'id': 'u-1',
          'email': 'a@b.ua',
          'role': 'CLIENT',
          'cityId': 'c-1',
          'cityName': 'Львів',
          'oblastName': 'Львівська',
          'citySettlementType': 'HAMLET',
        }),
        returnsNormally,
      );
      expect(dto.citySettlementType, isNotNull);
      expect(isOpenApiUnknownDefault(dto.citySettlementType!), isTrue);

      final user = UserMapper.fromProfileDto(dto);
      expect(user.citySettlementType, isNull);
      expect(savedSettlementLabel(uk, user.savedSettlement), bareLabel);
    });

    test('SalonResponse', () {
      late final SalonResponse dto;
      expect(
        () => dto = _decode(SalonResponse.serializer, <String, Object?>{
          'id': 's-1',
          'name': 'Салон',
          'cityId': 'c-1',
          'oblastId': 'o-1',
          'city': 'Львів',
          'region': 'Львівська',
          'citySettlementType': 'HAMLET',
        }),
        returnsNormally,
      );
      final salon = SalonMapper.fromUpdateDto(dto);
      expect(salon.citySettlementType, isNull);
      expect(savedSettlementLabel(uk, salon.savedSettlement), bareLabel);
    });

    test('PublicSalonResponse', () {
      late final PublicSalonResponse dto;
      expect(
        () => dto = _decode(PublicSalonResponse.serializer, <String, Object?>{
          'id': 's-1',
          'name': 'Салон',
          'cityId': 'c-1',
          'oblastId': 'o-1',
          'city': 'Львів',
          'region': 'Львівська',
          'citySettlementType': 'HAMLET',
        }),
        returnsNormally,
      );
      final salon = SalonMapper.fromDto(dto);
      expect(salon.citySettlementType, isNull);
      expect(savedSettlementLabel(uk, salon.savedSettlement), bareLabel);
    });

    test('MasterDetailResponse (and an unknown masterType fails safe)', () {
      late final MasterDetailResponse dto;
      expect(
        () => dto = _decode(MasterDetailResponse.serializer, <String, Object?>{
          'masterId': 'm-1',
          'firstName': 'Оля',
          'lastName': 'Коваль',
          'reviewCount': 0,
          'masterType': 'FREELANCER',
          'city': 'Львів',
          'region': 'Львівська',
          'citySettlementType': 'HAMLET',
        }),
        returnsNormally,
      );
      final master = MasterMapper.fromDto(dto);
      expect(master.citySettlementType, isNull);
      expect(savedSettlementLabel(uk, master.savedSettlement), bareLabel);
      expect(master.type, MasterType.salonMaster);
    });
  });

  test('an unknown AuthResponse role decodes, then maps to a typed '
      'UnknownFailure — never an ArgumentError', () {
    late final AuthResponse dto;
    expect(
      () => dto = _decode(AuthResponse.serializer, <String, Object?>{
        'userId': 'u-1',
        'email': 'a@b.ua',
        'role': 'SUPERUSER',
        'accessToken': 'a',
        'refreshToken': 'r',
      }),
      returnsNormally,
    );
    expect(isOpenApiUnknownDefault(dto.role!), isTrue);
    expect(
      () => UserMapper.fromAuthResponse(dto),
      throwsA(isA<UnknownFailure>()),
    );
  });

  test('knownEnumName never returns the fallback name', () {
    expect(
      knownEnumName(
        UserProfileResponseCitySettlementTypeEnum.unknownDefaultOpenApi,
      ),
      isNull,
    );
    expect(
      knownEnumName(UserProfileResponseCitySettlementTypeEnum.VILLAGE),
      'VILLAGE',
    );
    expect(knownEnumName(null), isNull);
  });
}
