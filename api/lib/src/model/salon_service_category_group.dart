//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_definition_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_service_category_group.g.dart';

/// SalonServiceCategoryGroup
///
/// Properties:
/// * [category]
/// * [count]
/// * [services]
@BuiltValue()
abstract class SalonServiceCategoryGroup
    implements
        Built<SalonServiceCategoryGroup, SalonServiceCategoryGroupBuilder> {
  @BuiltValueField(wireName: r'category')
  String? get category;

  @BuiltValueField(wireName: r'count')
  int? get count;

  @BuiltValueField(wireName: r'services')
  BuiltList<ServiceDefinitionResponse>? get services;

  SalonServiceCategoryGroup._();

  factory SalonServiceCategoryGroup(
          [void updates(SalonServiceCategoryGroupBuilder b)]) =
      _$SalonServiceCategoryGroup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonServiceCategoryGroupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonServiceCategoryGroup> get serializer =>
      _$SalonServiceCategoryGroupSerializer();
}

class _$SalonServiceCategoryGroupSerializer
    implements PrimitiveSerializer<SalonServiceCategoryGroup> {
  @override
  final Iterable<Type> types = const [
    SalonServiceCategoryGroup,
    _$SalonServiceCategoryGroup
  ];

  @override
  final String wireName = r'SalonServiceCategoryGroup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonServiceCategoryGroup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.category != null) {
      yield r'category';
      yield serializers.serialize(
        object.category,
        specifiedType: const FullType(String),
      );
    }
    if (object.count != null) {
      yield r'count';
      yield serializers.serialize(
        object.count,
        specifiedType: const FullType(int),
      );
    }
    if (object.services != null) {
      yield r'services';
      yield serializers.serialize(
        object.services,
        specifiedType:
            const FullType(BuiltList, [FullType(ServiceDefinitionResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonServiceCategoryGroup object, {
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
    required SalonServiceCategoryGroupBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.category = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'services':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltList, [FullType(ServiceDefinitionResponse)]),
          ) as BuiltList<ServiceDefinitionResponse>;
          result.services.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonServiceCategoryGroup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonServiceCategoryGroupBuilder();
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
