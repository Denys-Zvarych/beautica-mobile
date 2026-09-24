// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settlement_search_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SettlementSearchResponseSettlementTypeEnum
    _$settlementSearchResponseSettlementTypeEnum_CITY =
    const SettlementSearchResponseSettlementTypeEnum._('CITY');
const SettlementSearchResponseSettlementTypeEnum
    _$settlementSearchResponseSettlementTypeEnum_TOWN =
    const SettlementSearchResponseSettlementTypeEnum._('TOWN');
const SettlementSearchResponseSettlementTypeEnum
    _$settlementSearchResponseSettlementTypeEnum_VILLAGE =
    const SettlementSearchResponseSettlementTypeEnum._('VILLAGE');
const SettlementSearchResponseSettlementTypeEnum
    _$settlementSearchResponseSettlementTypeEnum_SETTLEMENT =
    const SettlementSearchResponseSettlementTypeEnum._('SETTLEMENT');

SettlementSearchResponseSettlementTypeEnum
    _$settlementSearchResponseSettlementTypeEnumValueOf(String name) {
  switch (name) {
    case 'CITY':
      return _$settlementSearchResponseSettlementTypeEnum_CITY;
    case 'TOWN':
      return _$settlementSearchResponseSettlementTypeEnum_TOWN;
    case 'VILLAGE':
      return _$settlementSearchResponseSettlementTypeEnum_VILLAGE;
    case 'SETTLEMENT':
      return _$settlementSearchResponseSettlementTypeEnum_SETTLEMENT;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SettlementSearchResponseSettlementTypeEnum>
    _$settlementSearchResponseSettlementTypeEnumValues = BuiltSet<
        SettlementSearchResponseSettlementTypeEnum>(const <SettlementSearchResponseSettlementTypeEnum>[
  _$settlementSearchResponseSettlementTypeEnum_CITY,
  _$settlementSearchResponseSettlementTypeEnum_TOWN,
  _$settlementSearchResponseSettlementTypeEnum_VILLAGE,
  _$settlementSearchResponseSettlementTypeEnum_SETTLEMENT,
]);

Serializer<SettlementSearchResponseSettlementTypeEnum>
    _$settlementSearchResponseSettlementTypeEnumSerializer =
    _$SettlementSearchResponseSettlementTypeEnumSerializer();

class _$SettlementSearchResponseSettlementTypeEnumSerializer
    implements PrimitiveSerializer<SettlementSearchResponseSettlementTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CITY': 'CITY',
    'TOWN': 'TOWN',
    'VILLAGE': 'VILLAGE',
    'SETTLEMENT': 'SETTLEMENT',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CITY': 'CITY',
    'TOWN': 'TOWN',
    'VILLAGE': 'VILLAGE',
    'SETTLEMENT': 'SETTLEMENT',
  };

  @override
  final Iterable<Type> types = const <Type>[
    SettlementSearchResponseSettlementTypeEnum
  ];
  @override
  final String wireName = 'SettlementSearchResponseSettlementTypeEnum';

  @override
  Object serialize(Serializers serializers,
          SettlementSearchResponseSettlementTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SettlementSearchResponseSettlementTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SettlementSearchResponseSettlementTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SettlementSearchResponse extends SettlementSearchResponse {
  @override
  final String? settlementId;
  @override
  final String? nameUk;
  @override
  final SettlementSearchResponseSettlementTypeEnum? settlementType;
  @override
  final String? oblastNameUk;
  @override
  final String? hromadaNameUk;

  factory _$SettlementSearchResponse(
          [void Function(SettlementSearchResponseBuilder)? updates]) =>
      (SettlementSearchResponseBuilder()..update(updates))._build();

  _$SettlementSearchResponse._(
      {this.settlementId,
      this.nameUk,
      this.settlementType,
      this.oblastNameUk,
      this.hromadaNameUk})
      : super._();
  @override
  SettlementSearchResponse rebuild(
          void Function(SettlementSearchResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SettlementSearchResponseBuilder toBuilder() =>
      SettlementSearchResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SettlementSearchResponse &&
        settlementId == other.settlementId &&
        nameUk == other.nameUk &&
        settlementType == other.settlementType &&
        oblastNameUk == other.oblastNameUk &&
        hromadaNameUk == other.hromadaNameUk;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, settlementId.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, settlementType.hashCode);
    _$hash = $jc(_$hash, oblastNameUk.hashCode);
    _$hash = $jc(_$hash, hromadaNameUk.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SettlementSearchResponse')
          ..add('settlementId', settlementId)
          ..add('nameUk', nameUk)
          ..add('settlementType', settlementType)
          ..add('oblastNameUk', oblastNameUk)
          ..add('hromadaNameUk', hromadaNameUk))
        .toString();
  }
}

class SettlementSearchResponseBuilder
    implements
        Builder<SettlementSearchResponse, SettlementSearchResponseBuilder> {
  _$SettlementSearchResponse? _$v;

  String? _settlementId;
  String? get settlementId => _$this._settlementId;
  set settlementId(String? settlementId) => _$this._settlementId = settlementId;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  SettlementSearchResponseSettlementTypeEnum? _settlementType;
  SettlementSearchResponseSettlementTypeEnum? get settlementType =>
      _$this._settlementType;
  set settlementType(
          SettlementSearchResponseSettlementTypeEnum? settlementType) =>
      _$this._settlementType = settlementType;

  String? _oblastNameUk;
  String? get oblastNameUk => _$this._oblastNameUk;
  set oblastNameUk(String? oblastNameUk) => _$this._oblastNameUk = oblastNameUk;

  String? _hromadaNameUk;
  String? get hromadaNameUk => _$this._hromadaNameUk;
  set hromadaNameUk(String? hromadaNameUk) =>
      _$this._hromadaNameUk = hromadaNameUk;

  SettlementSearchResponseBuilder() {
    SettlementSearchResponse._defaults(this);
  }

  SettlementSearchResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _settlementId = $v.settlementId;
      _nameUk = $v.nameUk;
      _settlementType = $v.settlementType;
      _oblastNameUk = $v.oblastNameUk;
      _hromadaNameUk = $v.hromadaNameUk;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SettlementSearchResponse other) {
    _$v = other as _$SettlementSearchResponse;
  }

  @override
  void update(void Function(SettlementSearchResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SettlementSearchResponse build() => _build();

  _$SettlementSearchResponse _build() {
    final _$result = _$v ??
        _$SettlementSearchResponse._(
          settlementId: settlementId,
          nameUk: nameUk,
          settlementType: settlementType,
          oblastNameUk: oblastNameUk,
          hromadaNameUk: hromadaNameUk,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
