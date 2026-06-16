//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_search_result.g.dart';

/// SalonSearchResult
///
/// Properties:
/// * [salonId]
/// * [name]
/// * [cityLabel]
/// * [districtLabel]
/// * [avatarUrl]
@BuiltValue()
abstract class SalonSearchResult
    implements Built<SalonSearchResult, SalonSearchResultBuilder> {
  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'cityLabel')
  String? get cityLabel;

  @BuiltValueField(wireName: r'districtLabel')
  String? get districtLabel;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  SalonSearchResult._();

  factory SalonSearchResult([void updates(SalonSearchResultBuilder b)]) =
      _$SalonSearchResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonSearchResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonSearchResult> get serializer =>
      _$SalonSearchResultSerializer();
}

class _$SalonSearchResultSerializer
    implements PrimitiveSerializer<SalonSearchResult> {
  @override
  final Iterable<Type> types = const [SalonSearchResult, _$SalonSearchResult];

  @override
  final String wireName = r'SalonSearchResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonSearchResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
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
    if (object.cityLabel != null) {
      yield r'cityLabel';
      yield serializers.serialize(
        object.cityLabel,
        specifiedType: const FullType(String),
      );
    }
    if (object.districtLabel != null) {
      yield r'districtLabel';
      yield serializers.serialize(
        object.districtLabel,
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
    SalonSearchResult object, {
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
    required SalonSearchResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'cityLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityLabel = valueDes;
          break;
        case r'districtLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtLabel = valueDes;
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
  SalonSearchResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonSearchResultBuilder();
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
