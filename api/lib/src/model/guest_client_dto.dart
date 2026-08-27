//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_client_dto.g.dart';

/// Walk-in (account-less) client identity for a staff-created booking.
///
/// Properties:
/// * [name]
/// * [surname]
/// * [phone] - Normalised to E.164 (+380XXXXXXXXX) server-side; foreign numbers are rejected.
@BuiltValue()
abstract class GuestClientDto
    implements Built<GuestClientDto, GuestClientDtoBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'surname')
  String get surname;

  /// Normalised to E.164 (+380XXXXXXXXX) server-side; foreign numbers are rejected.
  @BuiltValueField(wireName: r'phone')
  String get phone;

  GuestClientDto._();

  factory GuestClientDto([void updates(GuestClientDtoBuilder b)]) =
      _$GuestClientDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestClientDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestClientDto> get serializer =>
      _$GuestClientDtoSerializer();
}

class _$GuestClientDtoSerializer
    implements PrimitiveSerializer<GuestClientDto> {
  @override
  final Iterable<Type> types = const [GuestClientDto, _$GuestClientDto];

  @override
  final String wireName = r'GuestClientDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestClientDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'surname';
    yield serializers.serialize(
      object.surname,
      specifiedType: const FullType(String),
    );
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestClientDto object, {
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
    required GuestClientDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'surname':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.surname = valueDes;
          break;
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestClientDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestClientDtoBuilder();
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
