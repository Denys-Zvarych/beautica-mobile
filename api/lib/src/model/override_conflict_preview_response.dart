//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/override_conflict_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'override_conflict_preview_response.g.dart';

/// OverrideConflictPreviewResponse
///
/// Properties:
/// * [conflicts]
/// * [totalCount]
/// * [truncated]
/// * [scanTruncated]
@BuiltValue()
abstract class OverrideConflictPreviewResponse
    implements
        Built<OverrideConflictPreviewResponse,
            OverrideConflictPreviewResponseBuilder> {
  @BuiltValueField(wireName: r'conflicts')
  BuiltList<OverrideConflictResponse>? get conflicts;

  @BuiltValueField(wireName: r'totalCount')
  int? get totalCount;

  @BuiltValueField(wireName: r'truncated')
  bool? get truncated;

  @BuiltValueField(wireName: r'scanTruncated')
  bool? get scanTruncated;

  OverrideConflictPreviewResponse._();

  factory OverrideConflictPreviewResponse(
          [void updates(OverrideConflictPreviewResponseBuilder b)]) =
      _$OverrideConflictPreviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OverrideConflictPreviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OverrideConflictPreviewResponse> get serializer =>
      _$OverrideConflictPreviewResponseSerializer();
}

class _$OverrideConflictPreviewResponseSerializer
    implements PrimitiveSerializer<OverrideConflictPreviewResponse> {
  @override
  final Iterable<Type> types = const [
    OverrideConflictPreviewResponse,
    _$OverrideConflictPreviewResponse
  ];

  @override
  final String wireName = r'OverrideConflictPreviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OverrideConflictPreviewResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.conflicts != null) {
      yield r'conflicts';
      yield serializers.serialize(
        object.conflicts,
        specifiedType:
            const FullType(BuiltList, [FullType(OverrideConflictResponse)]),
      );
    }
    if (object.totalCount != null) {
      yield r'totalCount';
      yield serializers.serialize(
        object.totalCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.truncated != null) {
      yield r'truncated';
      yield serializers.serialize(
        object.truncated,
        specifiedType: const FullType(bool),
      );
    }
    if (object.scanTruncated != null) {
      yield r'scanTruncated';
      yield serializers.serialize(
        object.scanTruncated,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OverrideConflictPreviewResponse object, {
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
    required OverrideConflictPreviewResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'conflicts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(OverrideConflictResponse)]),
          ) as BuiltList<OverrideConflictResponse>;
          result.conflicts.replace(valueDes);
          break;
        case r'totalCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalCount = valueDes;
          break;
        case r'truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.truncated = valueDes;
          break;
        case r'scanTruncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.scanTruncated = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OverrideConflictPreviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OverrideConflictPreviewResponseBuilder();
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
