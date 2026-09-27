//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'sibling_salon_option.g.dart';

/// A salon offered as a rotate-admin destination: id, name and short address.
///
/// Properties:
/// * [id] - Send this as destinationSalonId to PATCH /salons/{salonId}/admins/{userId}/salon.
/// * [name] - Salon display name.
/// * [street] - Street of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
/// * [buildingNo] - Building number of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
@BuiltValue()
abstract class SiblingSalonOption
    implements Built<SiblingSalonOption, SiblingSalonOptionBuilder> {
  /// Send this as destinationSalonId to PATCH /salons/{salonId}/admins/{userId}/salon.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Salon display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Street of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
  @BuiltValueField(wireName: r'street')
  String? get street;

  /// Building number of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  SiblingSalonOption._();

  factory SiblingSalonOption([void updates(SiblingSalonOptionBuilder b)]) =
      _$SiblingSalonOption;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SiblingSalonOptionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SiblingSalonOption> get serializer =>
      _$SiblingSalonOptionSerializer();
}

class _$SiblingSalonOptionSerializer
    implements PrimitiveSerializer<SiblingSalonOption> {
  @override
  final Iterable<Type> types = const [SiblingSalonOption, _$SiblingSalonOption];

  @override
  final String wireName = r'SiblingSalonOption';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SiblingSalonOption object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SiblingSalonOption object, {
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
    required SiblingSalonOptionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.buildingNo = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SiblingSalonOption deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SiblingSalonOptionBuilder();
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
