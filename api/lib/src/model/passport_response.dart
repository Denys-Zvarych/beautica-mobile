//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/budget_band.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'passport_response.g.dart';

/// PassportResponse
///
/// Properties:
/// * [favoriteDistricts]
/// * [favoriteCities]
/// * [budget]
/// * [bookingsConsidered]
/// * [reviewsWritten]
/// * [memberSinceYear]
@BuiltValue()
abstract class PassportResponse
    implements Built<PassportResponse, PassportResponseBuilder> {
  @BuiltValueField(wireName: r'favoriteDistricts')
  BuiltList<String>? get favoriteDistricts;

  @BuiltValueField(wireName: r'favoriteCities')
  BuiltList<String>? get favoriteCities;

  @BuiltValueField(wireName: r'budget')
  BudgetBand? get budget;

  @BuiltValueField(wireName: r'bookingsConsidered')
  int? get bookingsConsidered;

  @BuiltValueField(wireName: r'reviewsWritten')
  int? get reviewsWritten;

  @BuiltValueField(wireName: r'memberSinceYear')
  int? get memberSinceYear;

  PassportResponse._();

  factory PassportResponse([void updates(PassportResponseBuilder b)]) =
      _$PassportResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PassportResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PassportResponse> get serializer =>
      _$PassportResponseSerializer();
}

class _$PassportResponseSerializer
    implements PrimitiveSerializer<PassportResponse> {
  @override
  final Iterable<Type> types = const [PassportResponse, _$PassportResponse];

  @override
  final String wireName = r'PassportResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PassportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.favoriteDistricts != null) {
      yield r'favoriteDistricts';
      yield serializers.serialize(
        object.favoriteDistricts,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.favoriteCities != null) {
      yield r'favoriteCities';
      yield serializers.serialize(
        object.favoriteCities,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.budget != null) {
      yield r'budget';
      yield serializers.serialize(
        object.budget,
        specifiedType: const FullType(BudgetBand),
      );
    }
    if (object.bookingsConsidered != null) {
      yield r'bookingsConsidered';
      yield serializers.serialize(
        object.bookingsConsidered,
        specifiedType: const FullType(int),
      );
    }
    if (object.reviewsWritten != null) {
      yield r'reviewsWritten';
      yield serializers.serialize(
        object.reviewsWritten,
        specifiedType: const FullType(int),
      );
    }
    if (object.memberSinceYear != null) {
      yield r'memberSinceYear';
      yield serializers.serialize(
        object.memberSinceYear,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PassportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PassportResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'favoriteDistricts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.favoriteDistricts.replace(valueDes);
          break;
        case r'favoriteCities':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.favoriteCities.replace(valueDes);
          break;
        case r'budget':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BudgetBand),
          ) as BudgetBand;
          result.budget.replace(valueDes);
          break;
        case r'bookingsConsidered':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookingsConsidered = valueDes;
          break;
        case r'reviewsWritten':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewsWritten = valueDes;
          break;
        case r'memberSinceYear':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.memberSinceYear = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PassportResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PassportResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
