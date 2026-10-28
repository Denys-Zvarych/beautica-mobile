//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/salon_service_master_ref.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_service_coverage.g.dart';

/// SalonServiceCoverage
///
/// Properties:
/// * [serviceId] - The service definition id — serviceCategories[].services[].id.
/// * [masters]
@BuiltValue()
abstract class SalonServiceCoverage
    implements Built<SalonServiceCoverage, SalonServiceCoverageBuilder> {
  /// The service definition id — serviceCategories[].services[].id.
  @BuiltValueField(wireName: r'serviceId')
  String get serviceId;

  @BuiltValueField(wireName: r'masters')
  BuiltList<SalonServiceMasterRef> get masters;

  SalonServiceCoverage._();

  factory SalonServiceCoverage([void updates(SalonServiceCoverageBuilder b)]) =
      _$SalonServiceCoverage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonServiceCoverageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonServiceCoverage> get serializer =>
      _$SalonServiceCoverageSerializer();
}

class _$SalonServiceCoverageSerializer
    implements PrimitiveSerializer<SalonServiceCoverage> {
  @override
  final Iterable<Type> types = const [
    SalonServiceCoverage,
    _$SalonServiceCoverage
  ];

  @override
  final String wireName = r'SalonServiceCoverage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonServiceCoverage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'serviceId';
    yield serializers.serialize(
      object.serviceId,
      specifiedType: const FullType(String),
    );
    yield r'masters';
    yield serializers.serialize(
      object.masters,
      specifiedType:
          const FullType(BuiltList, [FullType(SalonServiceMasterRef)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonServiceCoverage object, {
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
    required SalonServiceCoverageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'serviceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceId = valueDes;
          break;
        case r'masters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(SalonServiceMasterRef)]),
          ) as BuiltList<SalonServiceMasterRef>;
          result.masters.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonServiceCoverage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonServiceCoverageBuilder();
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
