//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/revenue_by_date_dto.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/revenue_by_master_dto.dart';
import 'package:beautica_api/src/model/revenue_by_service_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_response.g.dart';

/// RevenueResponse
///
/// Properties:
/// * [totalCompletedBookings]
/// * [estimatedRevenue]
/// * [byMaster]
/// * [byService]
/// * [byDate]
@BuiltValue()
abstract class RevenueResponse
    implements Built<RevenueResponse, RevenueResponseBuilder> {
  @BuiltValueField(wireName: r'totalCompletedBookings')
  int? get totalCompletedBookings;

  @BuiltValueField(wireName: r'estimatedRevenue')
  num? get estimatedRevenue;

  @BuiltValueField(wireName: r'byMaster')
  BuiltList<RevenueByMasterDto>? get byMaster;

  @BuiltValueField(wireName: r'byService')
  BuiltList<RevenueByServiceDto>? get byService;

  @BuiltValueField(wireName: r'byDate')
  BuiltList<RevenueByDateDto>? get byDate;

  RevenueResponse._();

  factory RevenueResponse([void updates(RevenueResponseBuilder b)]) =
      _$RevenueResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenueResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenueResponse> get serializer =>
      _$RevenueResponseSerializer();
}

class _$RevenueResponseSerializer
    implements PrimitiveSerializer<RevenueResponse> {
  @override
  final Iterable<Type> types = const [RevenueResponse, _$RevenueResponse];

  @override
  final String wireName = r'RevenueResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenueResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.totalCompletedBookings != null) {
      yield r'totalCompletedBookings';
      yield serializers.serialize(
        object.totalCompletedBookings,
        specifiedType: const FullType(int),
      );
    }
    if (object.estimatedRevenue != null) {
      yield r'estimatedRevenue';
      yield serializers.serialize(
        object.estimatedRevenue,
        specifiedType: const FullType(num),
      );
    }
    if (object.byMaster != null) {
      yield r'byMaster';
      yield serializers.serialize(
        object.byMaster,
        specifiedType:
            const FullType(BuiltList, [FullType(RevenueByMasterDto)]),
      );
    }
    if (object.byService != null) {
      yield r'byService';
      yield serializers.serialize(
        object.byService,
        specifiedType:
            const FullType(BuiltList, [FullType(RevenueByServiceDto)]),
      );
    }
    if (object.byDate != null) {
      yield r'byDate';
      yield serializers.serialize(
        object.byDate,
        specifiedType: const FullType(BuiltList, [FullType(RevenueByDateDto)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RevenueResponse object, {
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
    required RevenueResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'totalCompletedBookings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalCompletedBookings = valueDes;
          break;
        case r'estimatedRevenue':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.estimatedRevenue = valueDes;
          break;
        case r'byMaster':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(RevenueByMasterDto)]),
          ) as BuiltList<RevenueByMasterDto>;
          result.byMaster.replace(valueDes);
          break;
        case r'byService':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(RevenueByServiceDto)]),
          ) as BuiltList<RevenueByServiceDto>;
          result.byService.replace(valueDes);
          break;
        case r'byDate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(RevenueByDateDto)]),
          ) as BuiltList<RevenueByDateDto>;
          result.byDate.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RevenueResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenueResponseBuilder();
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
