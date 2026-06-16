//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'approved_category_response.g.dart';

/// ApprovedCategoryResponse
///
/// Properties:
/// * [name]
/// * [displayName]
@BuiltValue()
abstract class ApprovedCategoryResponse
    implements
        Built<ApprovedCategoryResponse, ApprovedCategoryResponseBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  ApprovedCategoryResponse._();

  factory ApprovedCategoryResponse(
          [void updates(ApprovedCategoryResponseBuilder b)]) =
      _$ApprovedCategoryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApprovedCategoryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApprovedCategoryResponse> get serializer =>
      _$ApprovedCategoryResponseSerializer();
}

class _$ApprovedCategoryResponseSerializer
    implements PrimitiveSerializer<ApprovedCategoryResponse> {
  @override
  final Iterable<Type> types = const [
    ApprovedCategoryResponse,
    _$ApprovedCategoryResponse
  ];

  @override
  final String wireName = r'ApprovedCategoryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApprovedCategoryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApprovedCategoryResponse object, {
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
    required ApprovedCategoryResponseBuilder result,
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
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApprovedCategoryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApprovedCategoryResponseBuilder();
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
