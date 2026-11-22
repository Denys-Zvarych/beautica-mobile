//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'stats.g.dart';

/// Own-scope visit counts; a visit = one appointment (or one single booking). A partly cancelled visit that still has a COMPLETED row counts in completedVisits.
///
/// Properties:
/// * [totalVisits]
/// * [completedVisits]
/// * [upcomingVisits]
@BuiltValue()
abstract class Stats implements Built<Stats, StatsBuilder> {
  @BuiltValueField(wireName: r'totalVisits')
  int? get totalVisits;

  @BuiltValueField(wireName: r'completedVisits')
  int? get completedVisits;

  @BuiltValueField(wireName: r'upcomingVisits')
  int? get upcomingVisits;

  Stats._();

  factory Stats([void updates(StatsBuilder b)]) = _$Stats;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StatsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Stats> get serializer => _$StatsSerializer();
}

class _$StatsSerializer implements PrimitiveSerializer<Stats> {
  @override
  final Iterable<Type> types = const [Stats, _$Stats];

  @override
  final String wireName = r'Stats';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Stats object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.totalVisits != null) {
      yield r'totalVisits';
      yield serializers.serialize(
        object.totalVisits,
        specifiedType: const FullType(int),
      );
    }
    if (object.completedVisits != null) {
      yield r'completedVisits';
      yield serializers.serialize(
        object.completedVisits,
        specifiedType: const FullType(int),
      );
    }
    if (object.upcomingVisits != null) {
      yield r'upcomingVisits';
      yield serializers.serialize(
        object.upcomingVisits,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Stats object, {
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
    required StatsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'totalVisits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalVisits = valueDes;
          break;
        case r'completedVisits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.completedVisits = valueDes;
          break;
        case r'upcomingVisits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.upcomingVisits = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Stats deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StatsBuilder();
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
