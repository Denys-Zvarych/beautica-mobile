//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_list_removal_request.g.dart';

/// ClientListRemovalRequest
///
/// Properties:
/// * [clientId] - Registered client's user id (list row kind REGISTERED)
/// * [guestBookingId] - A guest's booking id in scope (list row anchorBookingId, kind GUEST)
@BuiltValue()
abstract class ClientListRemovalRequest
    implements
        Built<ClientListRemovalRequest, ClientListRemovalRequestBuilder> {
  /// Registered client's user id (list row kind REGISTERED)
  @BuiltValueField(wireName: r'clientId')
  String? get clientId;

  /// A guest's booking id in scope (list row anchorBookingId, kind GUEST)
  @BuiltValueField(wireName: r'guestBookingId')
  String? get guestBookingId;

  ClientListRemovalRequest._();

  factory ClientListRemovalRequest(
          [void updates(ClientListRemovalRequestBuilder b)]) =
      _$ClientListRemovalRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientListRemovalRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientListRemovalRequest> get serializer =>
      _$ClientListRemovalRequestSerializer();
}

class _$ClientListRemovalRequestSerializer
    implements PrimitiveSerializer<ClientListRemovalRequest> {
  @override
  final Iterable<Type> types = const [
    ClientListRemovalRequest,
    _$ClientListRemovalRequest
  ];

  @override
  final String wireName = r'ClientListRemovalRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientListRemovalRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.clientId != null) {
      yield r'clientId';
      yield serializers.serialize(
        object.clientId,
        specifiedType: const FullType(String),
      );
    }
    if (object.guestBookingId != null) {
      yield r'guestBookingId';
      yield serializers.serialize(
        object.guestBookingId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientListRemovalRequest object, {
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
    required ClientListRemovalRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'clientId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientId = valueDes;
          break;
        case r'guestBookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guestBookingId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientListRemovalRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientListRemovalRequestBuilder();
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
