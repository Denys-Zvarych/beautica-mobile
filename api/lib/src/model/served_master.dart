//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'served_master.g.dart';

/// A salon master who has served this client; the chip's masterId is a valid ?masterId= filter.
///
/// Properties:
/// * [masterId]
/// * [name]
/// * [avatarUrl]
@BuiltValue()
abstract class ServedMaster
    implements Built<ServedMaster, ServedMasterBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  ServedMaster._();

  factory ServedMaster([void updates(ServedMasterBuilder b)]) = _$ServedMaster;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServedMasterBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServedMaster> get serializer => _$ServedMasterSerializer();
}

class _$ServedMasterSerializer implements PrimitiveSerializer<ServedMaster> {
  @override
  final Iterable<Type> types = const [ServedMaster, _$ServedMaster];

  @override
  final String wireName = r'ServedMaster';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServedMaster object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServedMaster object, {
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
    required ServedMasterBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServedMaster deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServedMasterBuilder();
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
