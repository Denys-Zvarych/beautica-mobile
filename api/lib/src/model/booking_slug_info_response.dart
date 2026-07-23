//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_summary_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_slug_info_response.g.dart';

/// BookingSlugInfoResponse
///
/// Properties:
/// * [masterName]
/// * [avatarUrl]
/// * [bio]
/// * [services]
@BuiltValue()
abstract class BookingSlugInfoResponse
    implements Built<BookingSlugInfoResponse, BookingSlugInfoResponseBuilder> {
  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'bio')
  String? get bio;

  @BuiltValueField(wireName: r'services')
  BuiltList<ServiceSummaryDto>? get services;

  BookingSlugInfoResponse._();

  factory BookingSlugInfoResponse(
          [void updates(BookingSlugInfoResponseBuilder b)]) =
      _$BookingSlugInfoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingSlugInfoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingSlugInfoResponse> get serializer =>
      _$BookingSlugInfoResponseSerializer();
}

class _$BookingSlugInfoResponseSerializer
    implements PrimitiveSerializer<BookingSlugInfoResponse> {
  @override
  final Iterable<Type> types = const [
    BookingSlugInfoResponse,
    _$BookingSlugInfoResponse
  ];

  @override
  final String wireName = r'BookingSlugInfoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingSlugInfoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
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
    if (object.bio != null) {
      yield r'bio';
      yield serializers.serialize(
        object.bio,
        specifiedType: const FullType(String),
      );
    }
    if (object.services != null) {
      yield r'services';
      yield serializers.serialize(
        object.services,
        specifiedType: const FullType(BuiltList, [FullType(ServiceSummaryDto)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingSlugInfoResponse object, {
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
    required BookingSlugInfoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'bio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bio = valueDes;
          break;
        case r'services':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ServiceSummaryDto)]),
          ) as BuiltList<ServiceSummaryDto>;
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
  BookingSlugInfoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingSlugInfoResponseBuilder();
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
