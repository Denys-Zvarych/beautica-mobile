//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'budget_band.g.dart';

/// BudgetBand
///
/// Properties:
/// * [avg]
/// * [min]
/// * [max]
/// * [currency]
@BuiltValue()
abstract class BudgetBand implements Built<BudgetBand, BudgetBandBuilder> {
  @BuiltValueField(wireName: r'avg')
  num? get avg;

  @BuiltValueField(wireName: r'min')
  num? get min;

  @BuiltValueField(wireName: r'max')
  num? get max;

  @BuiltValueField(wireName: r'currency')
  String? get currency;

  BudgetBand._();

  factory BudgetBand([void updates(BudgetBandBuilder b)]) = _$BudgetBand;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BudgetBandBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BudgetBand> get serializer => _$BudgetBandSerializer();
}

class _$BudgetBandSerializer implements PrimitiveSerializer<BudgetBand> {
  @override
  final Iterable<Type> types = const [BudgetBand, _$BudgetBand];

  @override
  final String wireName = r'BudgetBand';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BudgetBand object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.avg != null) {
      yield r'avg';
      yield serializers.serialize(
        object.avg,
        specifiedType: const FullType(num),
      );
    }
    if (object.min != null) {
      yield r'min';
      yield serializers.serialize(
        object.min,
        specifiedType: const FullType(num),
      );
    }
    if (object.max != null) {
      yield r'max';
      yield serializers.serialize(
        object.max,
        specifiedType: const FullType(num),
      );
    }
    if (object.currency != null) {
      yield r'currency';
      yield serializers.serialize(
        object.currency,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BudgetBand object, {
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
    required BudgetBandBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'avg':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.avg = valueDes;
          break;
        case r'min':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.min = valueDes;
          break;
        case r'max':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.max = valueDes;
          break;
        case r'currency':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.currency = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BudgetBand deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BudgetBandBuilder();
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
