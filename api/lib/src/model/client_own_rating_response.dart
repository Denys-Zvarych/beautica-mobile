//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_own_rating_response.g.dart';

/// ClientOwnRatingResponse
///
/// Properties:
/// * [bookingId]
/// * [visitAt]
/// * [serviceName]
/// * [stars]
@BuiltValue()
abstract class ClientOwnRatingResponse
    implements Built<ClientOwnRatingResponse, ClientOwnRatingResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'visitAt')
  DateTime? get visitAt;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'stars')
  int? get stars;

  ClientOwnRatingResponse._();

  factory ClientOwnRatingResponse(
          [void updates(ClientOwnRatingResponseBuilder b)]) =
      _$ClientOwnRatingResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientOwnRatingResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientOwnRatingResponse> get serializer =>
      _$ClientOwnRatingResponseSerializer();
}

class _$ClientOwnRatingResponseSerializer
    implements PrimitiveSerializer<ClientOwnRatingResponse> {
  @override
  final Iterable<Type> types = const [
    ClientOwnRatingResponse,
    _$ClientOwnRatingResponse
  ];

  @override
  final String wireName = r'ClientOwnRatingResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientOwnRatingResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType(String),
      );
    }
    if (object.visitAt != null) {
      yield r'visitAt';
      yield serializers.serialize(
        object.visitAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.stars != null) {
      yield r'stars';
      yield serializers.serialize(
        object.stars,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientOwnRatingResponse object, {
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
    required ClientOwnRatingResponseBuilder result,
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
        case r'visitAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.visitAt = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'stars':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.stars = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientOwnRatingResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientOwnRatingResponseBuilder();
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
