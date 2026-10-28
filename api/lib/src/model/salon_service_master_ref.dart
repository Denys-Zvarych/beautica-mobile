//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_service_master_ref.g.dart';

/// SalonServiceMasterRef
///
/// Properties:
/// * [masterId] - Matches SalonBookingSlugMasterItem.masterId; the {masterId} of the salon guest routes.
/// * [masterServiceId] - This master's assignment of the service: the serviceId / masterServiceIds value of the salon guest availability, bookable-days and booking routes.
@BuiltValue()
abstract class SalonServiceMasterRef
    implements Built<SalonServiceMasterRef, SalonServiceMasterRefBuilder> {
  /// Matches SalonBookingSlugMasterItem.masterId; the {masterId} of the salon guest routes.
  @BuiltValueField(wireName: r'masterId')
  String get masterId;

  /// This master's assignment of the service: the serviceId / masterServiceIds value of the salon guest availability, bookable-days and booking routes.
  @BuiltValueField(wireName: r'masterServiceId')
  String get masterServiceId;

  SalonServiceMasterRef._();

  factory SalonServiceMasterRef(
      [void updates(SalonServiceMasterRefBuilder b)]) = _$SalonServiceMasterRef;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonServiceMasterRefBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonServiceMasterRef> get serializer =>
      _$SalonServiceMasterRefSerializer();
}

class _$SalonServiceMasterRefSerializer
    implements PrimitiveSerializer<SalonServiceMasterRef> {
  @override
  final Iterable<Type> types = const [
    SalonServiceMasterRef,
    _$SalonServiceMasterRef
  ];

  @override
  final String wireName = r'SalonServiceMasterRef';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonServiceMasterRef object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterId';
    yield serializers.serialize(
      object.masterId,
      specifiedType: const FullType(String),
    );
    yield r'masterServiceId';
    yield serializers.serialize(
      object.masterServiceId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonServiceMasterRef object, {
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
    required SalonServiceMasterRefBuilder result,
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
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonServiceMasterRef deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonServiceMasterRefBuilder();
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
