//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_by_master_dto.g.dart';

/// RevenueByMasterDto
///
/// Properties:
/// * [masterId]
/// * [masterName]
/// * [bookingCount]
/// * [revenue]
@BuiltValue()
abstract class RevenueByMasterDto
    implements Built<RevenueByMasterDto, RevenueByMasterDtoBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  @BuiltValueField(wireName: r'bookingCount')
  int? get bookingCount;

  @BuiltValueField(wireName: r'revenue')
  num? get revenue;

  RevenueByMasterDto._();

  factory RevenueByMasterDto([void updates(RevenueByMasterDtoBuilder b)]) =
      _$RevenueByMasterDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenueByMasterDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenueByMasterDto> get serializer =>
      _$RevenueByMasterDtoSerializer();
}

class _$RevenueByMasterDtoSerializer
    implements PrimitiveSerializer<RevenueByMasterDto> {
  @override
  final Iterable<Type> types = const [RevenueByMasterDto, _$RevenueByMasterDto];

  @override
  final String wireName = r'RevenueByMasterDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenueByMasterDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
        specifiedType: const FullType(String),
      );
    }
    if (object.bookingCount != null) {
      yield r'bookingCount';
      yield serializers.serialize(
        object.bookingCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.revenue != null) {
      yield r'revenue';
      yield serializers.serialize(
        object.revenue,
        specifiedType: const FullType(num),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RevenueByMasterDto object, {
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
    required RevenueByMasterDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'bookingCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookingCount = valueDes;
          break;
        case r'revenue':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.revenue = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RevenueByMasterDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenueByMasterDtoBuilder();
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
