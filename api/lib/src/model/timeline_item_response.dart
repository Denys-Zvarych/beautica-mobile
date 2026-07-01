//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'timeline_item_response.g.dart';

/// TimelineItemResponse
///
/// Properties:
/// * [bookingId]
/// * [categoryKey]
/// * [categoryName]
/// * [date]
/// * [masterId]
/// * [serviceName]
@BuiltValue()
abstract class TimelineItemResponse
    implements Built<TimelineItemResponse, TimelineItemResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'categoryKey')
  String? get categoryKey;

  @BuiltValueField(wireName: r'categoryName')
  String? get categoryName;

  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  TimelineItemResponse._();

  factory TimelineItemResponse([void updates(TimelineItemResponseBuilder b)]) =
      _$TimelineItemResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TimelineItemResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TimelineItemResponse> get serializer =>
      _$TimelineItemResponseSerializer();
}

class _$TimelineItemResponseSerializer
    implements PrimitiveSerializer<TimelineItemResponse> {
  @override
  final Iterable<Type> types = const [
    TimelineItemResponse,
    _$TimelineItemResponse
  ];

  @override
  final String wireName = r'TimelineItemResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TimelineItemResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType(String),
      );
    }
    if (object.categoryKey != null) {
      yield r'categoryKey';
      yield serializers.serialize(
        object.categoryKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.categoryName != null) {
      yield r'categoryName';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType(String),
      );
    }
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    TimelineItemResponse object, {
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
    required TimelineItemResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'categoryKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryKey = valueDes;
          break;
        case r'categoryName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryName = valueDes;
          break;
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TimelineItemResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TimelineItemResponseBuilder();
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
