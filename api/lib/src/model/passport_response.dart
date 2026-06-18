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
/// * [favoriteProcedures]
/// * [favoriteDistricts]
/// * [budget]
/// * [bookingsConsidered]
@BuiltValue()
abstract class PassportResponse
    implements Built<PassportResponse, PassportResponseBuilder> {
  @BuiltValueField(wireName: r'favoriteProcedures')
  BuiltList<String>? get favoriteProcedures;

  @BuiltValueField(wireName: r'favoriteDistricts')
  BuiltList<String>? get favoriteDistricts;

  @BuiltValueField(wireName: r'budget')
  BudgetBand? get budget;

  @BuiltValueField(wireName: r'bookingsConsidered')
  int? get bookingsConsidered;

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
    if (object.favoriteProcedures != null) {
      yield r'favoriteProcedures';
      yield serializers.serialize(
        object.favoriteProcedures,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.favoriteDistricts != null) {
      yield r'favoriteDistricts';
      yield serializers.serialize(
        object.favoriteDistricts,
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
        case r'favoriteProcedures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.favoriteProcedures.replace(valueDes);
          break;
        case r'favoriteDistricts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.favoriteDistricts.replace(valueDes);
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
