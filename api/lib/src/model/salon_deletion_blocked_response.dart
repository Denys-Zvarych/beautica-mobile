//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_deletion_blocked_response.g.dart';

/// Payload under `data` of the 409 SALON_DELETION_BLOCKED response. Branch on `code`; direct the owner to contact support rather than retrying.
///
/// Properties:
/// * [code] - Stable machine-readable error code.
/// * [affectedStaffCount] - Count of DISTINCT staff accounts implicated by the audit — never a per-violation-row count.
@BuiltValue()
abstract class SalonDeletionBlockedResponse
    implements
        Built<SalonDeletionBlockedResponse,
            SalonDeletionBlockedResponseBuilder> {
  /// Stable machine-readable error code.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// Count of DISTINCT staff accounts implicated by the audit — never a per-violation-row count.
  @BuiltValueField(wireName: r'affectedStaffCount')
  int? get affectedStaffCount;

  SalonDeletionBlockedResponse._();

  factory SalonDeletionBlockedResponse(
          [void updates(SalonDeletionBlockedResponseBuilder b)]) =
      _$SalonDeletionBlockedResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonDeletionBlockedResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonDeletionBlockedResponse> get serializer =>
      _$SalonDeletionBlockedResponseSerializer();
}

class _$SalonDeletionBlockedResponseSerializer
    implements PrimitiveSerializer<SalonDeletionBlockedResponse> {
  @override
  final Iterable<Type> types = const [
    SalonDeletionBlockedResponse,
    _$SalonDeletionBlockedResponse
  ];

  @override
  final String wireName = r'SalonDeletionBlockedResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonDeletionBlockedResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.affectedStaffCount != null) {
      yield r'affectedStaffCount';
      yield serializers.serialize(
        object.affectedStaffCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonDeletionBlockedResponse object, {
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
    required SalonDeletionBlockedResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'affectedStaffCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.affectedStaffCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonDeletionBlockedResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonDeletionBlockedResponseBuilder();
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
