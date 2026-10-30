// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReportResponseStatusEnum _$reportResponseStatusEnum_OPEN =
    const ReportResponseStatusEnum._('OPEN');
const ReportResponseStatusEnum _$reportResponseStatusEnum_RESOLVED =
    const ReportResponseStatusEnum._('RESOLVED');
const ReportResponseStatusEnum
    _$reportResponseStatusEnum_unknownDefaultOpenApi =
    const ReportResponseStatusEnum._('unknownDefaultOpenApi');

ReportResponseStatusEnum _$reportResponseStatusEnumValueOf(String name) {
  switch (name) {
    case 'OPEN':
      return _$reportResponseStatusEnum_OPEN;
    case 'RESOLVED':
      return _$reportResponseStatusEnum_RESOLVED;
    case 'unknownDefaultOpenApi':
      return _$reportResponseStatusEnum_unknownDefaultOpenApi;
    default:
      return _$reportResponseStatusEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ReportResponseStatusEnum> _$reportResponseStatusEnumValues =
    BuiltSet<ReportResponseStatusEnum>(const <ReportResponseStatusEnum>[
  _$reportResponseStatusEnum_OPEN,
  _$reportResponseStatusEnum_RESOLVED,
  _$reportResponseStatusEnum_unknownDefaultOpenApi,
]);

Serializer<ReportResponseStatusEnum> _$reportResponseStatusEnumSerializer =
    _$ReportResponseStatusEnumSerializer();

class _$ReportResponseStatusEnumSerializer
    implements PrimitiveSerializer<ReportResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'OPEN': 'OPEN',
    'RESOLVED': 'RESOLVED',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'OPEN': 'OPEN',
    'RESOLVED': 'RESOLVED',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ReportResponseStatusEnum];
  @override
  final String wireName = 'ReportResponseStatusEnum';

  @override
  Object serialize(Serializers serializers, ReportResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReportResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReportResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ReportResponse extends ReportResponse {
  @override
  final String? id;
  @override
  final ReportResponseStatusEnum? status;
  @override
  final DateTime? createdAt;

  factory _$ReportResponse([void Function(ReportResponseBuilder)? updates]) =>
      (ReportResponseBuilder()..update(updates))._build();

  _$ReportResponse._({this.id, this.status, this.createdAt}) : super._();
  @override
  ReportResponse rebuild(void Function(ReportResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReportResponseBuilder toBuilder() => ReportResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReportResponse &&
        id == other.id &&
        status == other.status &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReportResponse')
          ..add('id', id)
          ..add('status', status)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class ReportResponseBuilder
    implements Builder<ReportResponse, ReportResponseBuilder> {
  _$ReportResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  ReportResponseStatusEnum? _status;
  ReportResponseStatusEnum? get status => _$this._status;
  set status(ReportResponseStatusEnum? status) => _$this._status = status;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  ReportResponseBuilder() {
    ReportResponse._defaults(this);
  }

  ReportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _status = $v.status;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReportResponse other) {
    _$v = other as _$ReportResponse;
  }

  @override
  void update(void Function(ReportResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReportResponse build() => _build();

  _$ReportResponse _build() {
    final _$result = _$v ??
        _$ReportResponse._(
          id: id,
          status: status,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
