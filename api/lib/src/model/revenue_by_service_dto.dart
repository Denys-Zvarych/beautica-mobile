//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_by_service_dto.g.dart';

/// RevenueByServiceDto
///
/// Properties:
/// * [serviceDefId]
/// * [serviceName]
/// * [bookingCount]
/// * [revenue]
@BuiltValue()
abstract class RevenueByServiceDto
    implements Built<RevenueByServiceDto, RevenueByServiceDtoBuilder> {
  @BuiltValueField(wireName: r'serviceDefId')
  String? get serviceDefId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'bookingCount')
  int? get bookingCount;

  @BuiltValueField(wireName: r'revenue')
  num? get revenue;

  RevenueByServiceDto._();

  factory RevenueByServiceDto([void updates(RevenueByServiceDtoBuilder b)]) =
      _$RevenueByServiceDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenueByServiceDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenueByServiceDto> get serializer =>
      _$RevenueByServiceDtoSerializer();
}

class _$RevenueByServiceDtoSerializer
    implements PrimitiveSerializer<RevenueByServiceDto> {
  @override
  final Iterable<Type> types = const [
    RevenueByServiceDto,
    _$RevenueByServiceDto
  ];

  @override
  final String wireName = r'RevenueByServiceDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenueByServiceDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.serviceDefId != null) {
      yield r'serviceDefId';
      yield serializers.serialize(
        object.serviceDefId,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
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
    RevenueByServiceDto object, {
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
    required RevenueByServiceDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'serviceDefId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceDefId = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
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
  RevenueByServiceDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenueByServiceDtoBuilder();
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
