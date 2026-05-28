//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_by_date_dto.g.dart';

/// RevenueByDateDto
///
/// Properties:
/// * [date]
/// * [bookingCount]
/// * [revenue]
@BuiltValue()
abstract class RevenueByDateDto
    implements Built<RevenueByDateDto, RevenueByDateDtoBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'bookingCount')
  int? get bookingCount;

  @BuiltValueField(wireName: r'revenue')
  num? get revenue;

  RevenueByDateDto._();

  factory RevenueByDateDto([void updates(RevenueByDateDtoBuilder b)]) =
      _$RevenueByDateDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenueByDateDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenueByDateDto> get serializer =>
      _$RevenueByDateDtoSerializer();
}

class _$RevenueByDateDtoSerializer
    implements PrimitiveSerializer<RevenueByDateDto> {
  @override
  final Iterable<Type> types = const [RevenueByDateDto, _$RevenueByDateDto];

  @override
  final String wireName = r'RevenueByDateDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenueByDateDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
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
    RevenueByDateDto object, {
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
    required RevenueByDateDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
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
  RevenueByDateDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenueByDateDtoBuilder();
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
