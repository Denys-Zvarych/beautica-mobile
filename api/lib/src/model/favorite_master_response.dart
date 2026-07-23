//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'favorite_master_response.g.dart';

/// FavoriteMasterResponse
///
/// Properties:
/// * [masterId]
/// * [firstName]
/// * [lastName]
/// * [avatarUrl]
/// * [cityLabel]
/// * [districtLabel]
/// * [avgRating]
/// * [lastServiceName]
@BuiltValue()
abstract class FavoriteMasterResponse
    implements Built<FavoriteMasterResponse, FavoriteMasterResponseBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'firstName')
  String? get firstName;

  @BuiltValueField(wireName: r'lastName')
  String? get lastName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'cityLabel')
  String? get cityLabel;

  @BuiltValueField(wireName: r'districtLabel')
  String? get districtLabel;

  @BuiltValueField(wireName: r'avgRating')
  double? get avgRating;

  @BuiltValueField(wireName: r'lastServiceName')
  String? get lastServiceName;

  FavoriteMasterResponse._();

  factory FavoriteMasterResponse(
          [void updates(FavoriteMasterResponseBuilder b)]) =
      _$FavoriteMasterResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FavoriteMasterResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FavoriteMasterResponse> get serializer =>
      _$FavoriteMasterResponseSerializer();
}

class _$FavoriteMasterResponseSerializer
    implements PrimitiveSerializer<FavoriteMasterResponse> {
  @override
  final Iterable<Type> types = const [
    FavoriteMasterResponse,
    _$FavoriteMasterResponse
  ];

  @override
  final String wireName = r'FavoriteMasterResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FavoriteMasterResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.firstName != null) {
      yield r'firstName';
      yield serializers.serialize(
        object.firstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastName != null) {
      yield r'lastName';
      yield serializers.serialize(
        object.lastName,
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
    if (object.avgRating != null) {
      yield r'avgRating';
      yield serializers.serialize(
        object.avgRating,
        specifiedType: const FullType(double),
      );
    }
    if (object.lastServiceName != null) {
      yield r'lastServiceName';
      yield serializers.serialize(
        object.lastServiceName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FavoriteMasterResponse object, {
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
    required FavoriteMasterResponseBuilder result,
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
        case r'firstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.firstName = valueDes;
          break;
        case r'lastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
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
        case r'avgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.avgRating = valueDes;
          break;
        case r'lastServiceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastServiceName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FavoriteMasterResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FavoriteMasterResponseBuilder();
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
