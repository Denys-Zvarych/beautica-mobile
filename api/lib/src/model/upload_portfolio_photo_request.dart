//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'dart:typed_data';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_portfolio_photo_request.g.dart';

/// UploadPortfolioPhotoRequest
///
/// Properties:
/// * [file]
@BuiltValue()
abstract class UploadPortfolioPhotoRequest
    implements
        Built<UploadPortfolioPhotoRequest, UploadPortfolioPhotoRequestBuilder> {
  @BuiltValueField(wireName: r'file')
  Uint8List get file;

  UploadPortfolioPhotoRequest._();

  factory UploadPortfolioPhotoRequest(
          [void updates(UploadPortfolioPhotoRequestBuilder b)]) =
      _$UploadPortfolioPhotoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadPortfolioPhotoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadPortfolioPhotoRequest> get serializer =>
      _$UploadPortfolioPhotoRequestSerializer();
}

class _$UploadPortfolioPhotoRequestSerializer
    implements PrimitiveSerializer<UploadPortfolioPhotoRequest> {
  @override
  final Iterable<Type> types = const [
    UploadPortfolioPhotoRequest,
    _$UploadPortfolioPhotoRequest
  ];

  @override
  final String wireName = r'UploadPortfolioPhotoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadPortfolioPhotoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'file';
    yield serializers.serialize(
      object.file,
      specifiedType: const FullType(Uint8List),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadPortfolioPhotoRequest object, {
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
    required UploadPortfolioPhotoRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'file':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Uint8List),
          ) as Uint8List;
          result.file = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadPortfolioPhotoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadPortfolioPhotoRequestBuilder();
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
