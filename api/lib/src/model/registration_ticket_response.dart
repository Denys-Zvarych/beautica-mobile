//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'registration_ticket_response.g.dart';

/// RegistrationTicketResponse
///
/// Properties:
/// * [registrationTicket]
@BuiltValue()
abstract class RegistrationTicketResponse
    implements
        Built<RegistrationTicketResponse, RegistrationTicketResponseBuilder> {
  @BuiltValueField(wireName: r'registrationTicket')
  String? get registrationTicket;

  RegistrationTicketResponse._();

  factory RegistrationTicketResponse(
          [void updates(RegistrationTicketResponseBuilder b)]) =
      _$RegistrationTicketResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegistrationTicketResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegistrationTicketResponse> get serializer =>
      _$RegistrationTicketResponseSerializer();
}

class _$RegistrationTicketResponseSerializer
    implements PrimitiveSerializer<RegistrationTicketResponse> {
  @override
  final Iterable<Type> types = const [
    RegistrationTicketResponse,
    _$RegistrationTicketResponse
  ];

  @override
  final String wireName = r'RegistrationTicketResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegistrationTicketResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.registrationTicket != null) {
      yield r'registrationTicket';
      yield serializers.serialize(
        object.registrationTicket,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RegistrationTicketResponse object, {
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
    required RegistrationTicketResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'registrationTicket':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.registrationTicket = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegistrationTicketResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegistrationTicketResponseBuilder();
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
