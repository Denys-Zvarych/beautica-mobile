//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/salon_invite_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_invite_history_response.g.dart';

/// SalonInviteHistoryResponse
///
/// Properties:
/// * [invites]
/// * [truncated]
@BuiltValue()
abstract class SalonInviteHistoryResponse
    implements
        Built<SalonInviteHistoryResponse, SalonInviteHistoryResponseBuilder> {
  @BuiltValueField(wireName: r'invites')
  BuiltList<SalonInviteResponse>? get invites;

  @BuiltValueField(wireName: r'truncated')
  bool? get truncated;

  SalonInviteHistoryResponse._();

  factory SalonInviteHistoryResponse(
          [void updates(SalonInviteHistoryResponseBuilder b)]) =
      _$SalonInviteHistoryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonInviteHistoryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonInviteHistoryResponse> get serializer =>
      _$SalonInviteHistoryResponseSerializer();
}

class _$SalonInviteHistoryResponseSerializer
    implements PrimitiveSerializer<SalonInviteHistoryResponse> {
  @override
  final Iterable<Type> types = const [
    SalonInviteHistoryResponse,
    _$SalonInviteHistoryResponse
  ];

  @override
  final String wireName = r'SalonInviteHistoryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonInviteHistoryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.invites != null) {
      yield r'invites';
      yield serializers.serialize(
        object.invites,
        specifiedType:
            const FullType(BuiltList, [FullType(SalonInviteResponse)]),
      );
    }
    if (object.truncated != null) {
      yield r'truncated';
      yield serializers.serialize(
        object.truncated,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonInviteHistoryResponse object, {
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
    required SalonInviteHistoryResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'invites':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(SalonInviteResponse)]),
          ) as BuiltList<SalonInviteResponse>;
          result.invites.replace(valueDes);
          break;
        case r'truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.truncated = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonInviteHistoryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonInviteHistoryResponseBuilder();
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
