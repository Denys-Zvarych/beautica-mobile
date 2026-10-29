// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reported_target_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_REVIEW =
    const ReportedTargetResponseTargetTypeEnum._('REVIEW');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_CLIENT_REVIEW =
    const ReportedTargetResponseTargetTypeEnum._('CLIENT_REVIEW');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_PORTFOLIO_PHOTO =
    const ReportedTargetResponseTargetTypeEnum._('PORTFOLIO_PHOTO');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_MASTER_PROFILE =
    const ReportedTargetResponseTargetTypeEnum._('MASTER_PROFILE');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_SALON_PROFILE =
    const ReportedTargetResponseTargetTypeEnum._('SALON_PROFILE');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_CLIENT_PROFILE =
    const ReportedTargetResponseTargetTypeEnum._('CLIENT_PROFILE');
const ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnum_unknownDefaultOpenApi =
    const ReportedTargetResponseTargetTypeEnum._('unknownDefaultOpenApi');

ReportedTargetResponseTargetTypeEnum
    _$reportedTargetResponseTargetTypeEnumValueOf(String name) {
  switch (name) {
    case 'REVIEW':
      return _$reportedTargetResponseTargetTypeEnum_REVIEW;
    case 'CLIENT_REVIEW':
      return _$reportedTargetResponseTargetTypeEnum_CLIENT_REVIEW;
    case 'PORTFOLIO_PHOTO':
      return _$reportedTargetResponseTargetTypeEnum_PORTFOLIO_PHOTO;
    case 'MASTER_PROFILE':
      return _$reportedTargetResponseTargetTypeEnum_MASTER_PROFILE;
    case 'SALON_PROFILE':
      return _$reportedTargetResponseTargetTypeEnum_SALON_PROFILE;
    case 'CLIENT_PROFILE':
      return _$reportedTargetResponseTargetTypeEnum_CLIENT_PROFILE;
    case 'unknownDefaultOpenApi':
      return _$reportedTargetResponseTargetTypeEnum_unknownDefaultOpenApi;
    default:
      return _$reportedTargetResponseTargetTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ReportedTargetResponseTargetTypeEnum>
    _$reportedTargetResponseTargetTypeEnumValues = BuiltSet<
        ReportedTargetResponseTargetTypeEnum>(const <ReportedTargetResponseTargetTypeEnum>[
  _$reportedTargetResponseTargetTypeEnum_REVIEW,
  _$reportedTargetResponseTargetTypeEnum_CLIENT_REVIEW,
  _$reportedTargetResponseTargetTypeEnum_PORTFOLIO_PHOTO,
  _$reportedTargetResponseTargetTypeEnum_MASTER_PROFILE,
  _$reportedTargetResponseTargetTypeEnum_SALON_PROFILE,
  _$reportedTargetResponseTargetTypeEnum_CLIENT_PROFILE,
  _$reportedTargetResponseTargetTypeEnum_unknownDefaultOpenApi,
]);

Serializer<ReportedTargetResponseTargetTypeEnum>
    _$reportedTargetResponseTargetTypeEnumSerializer =
    _$ReportedTargetResponseTargetTypeEnumSerializer();

class _$ReportedTargetResponseTargetTypeEnumSerializer
    implements PrimitiveSerializer<ReportedTargetResponseTargetTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'REVIEW': 'REVIEW',
    'CLIENT_REVIEW': 'CLIENT_REVIEW',
    'PORTFOLIO_PHOTO': 'PORTFOLIO_PHOTO',
    'MASTER_PROFILE': 'MASTER_PROFILE',
    'SALON_PROFILE': 'SALON_PROFILE',
    'CLIENT_PROFILE': 'CLIENT_PROFILE',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'REVIEW': 'REVIEW',
    'CLIENT_REVIEW': 'CLIENT_REVIEW',
    'PORTFOLIO_PHOTO': 'PORTFOLIO_PHOTO',
    'MASTER_PROFILE': 'MASTER_PROFILE',
    'SALON_PROFILE': 'SALON_PROFILE',
    'CLIENT_PROFILE': 'CLIENT_PROFILE',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[
    ReportedTargetResponseTargetTypeEnum
  ];
  @override
  final String wireName = 'ReportedTargetResponseTargetTypeEnum';

  @override
  Object serialize(
          Serializers serializers, ReportedTargetResponseTargetTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReportedTargetResponseTargetTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReportedTargetResponseTargetTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ReportedTargetResponse extends ReportedTargetResponse {
  @override
  final ReportedTargetResponseTargetTypeEnum? targetType;
  @override
  final String? targetId;

  factory _$ReportedTargetResponse(
          [void Function(ReportedTargetResponseBuilder)? updates]) =>
      (ReportedTargetResponseBuilder()..update(updates))._build();

  _$ReportedTargetResponse._({this.targetType, this.targetId}) : super._();
  @override
  ReportedTargetResponse rebuild(
          void Function(ReportedTargetResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReportedTargetResponseBuilder toBuilder() =>
      ReportedTargetResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReportedTargetResponse &&
        targetType == other.targetType &&
        targetId == other.targetId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, targetType.hashCode);
    _$hash = $jc(_$hash, targetId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReportedTargetResponse')
          ..add('targetType', targetType)
          ..add('targetId', targetId))
        .toString();
  }
}

class ReportedTargetResponseBuilder
    implements Builder<ReportedTargetResponse, ReportedTargetResponseBuilder> {
  _$ReportedTargetResponse? _$v;

  ReportedTargetResponseTargetTypeEnum? _targetType;
  ReportedTargetResponseTargetTypeEnum? get targetType => _$this._targetType;
  set targetType(ReportedTargetResponseTargetTypeEnum? targetType) =>
      _$this._targetType = targetType;

  String? _targetId;
  String? get targetId => _$this._targetId;
  set targetId(String? targetId) => _$this._targetId = targetId;

  ReportedTargetResponseBuilder() {
    ReportedTargetResponse._defaults(this);
  }

  ReportedTargetResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _targetType = $v.targetType;
      _targetId = $v.targetId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReportedTargetResponse other) {
    _$v = other as _$ReportedTargetResponse;
  }

  @override
  void update(void Function(ReportedTargetResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReportedTargetResponse build() => _build();

  _$ReportedTargetResponse _build() {
    final _$result = _$v ??
        _$ReportedTargetResponse._(
          targetType: targetType,
          targetId: targetId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
