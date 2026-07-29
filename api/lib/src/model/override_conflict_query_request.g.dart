// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'override_conflict_query_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const OverrideConflictQueryRequestKindEnum
    _$overrideConflictQueryRequestKindEnum_DAY_OFF =
    const OverrideConflictQueryRequestKindEnum._('DAY_OFF');
const OverrideConflictQueryRequestKindEnum
    _$overrideConflictQueryRequestKindEnum_CUSTOM_HOURS =
    const OverrideConflictQueryRequestKindEnum._('CUSTOM_HOURS');

OverrideConflictQueryRequestKindEnum
    _$overrideConflictQueryRequestKindEnumValueOf(String name) {
  switch (name) {
    case 'DAY_OFF':
      return _$overrideConflictQueryRequestKindEnum_DAY_OFF;
    case 'CUSTOM_HOURS':
      return _$overrideConflictQueryRequestKindEnum_CUSTOM_HOURS;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<OverrideConflictQueryRequestKindEnum>
    _$overrideConflictQueryRequestKindEnumValues = BuiltSet<
        OverrideConflictQueryRequestKindEnum>(const <OverrideConflictQueryRequestKindEnum>[
  _$overrideConflictQueryRequestKindEnum_DAY_OFF,
  _$overrideConflictQueryRequestKindEnum_CUSTOM_HOURS,
]);

const OverrideConflictQueryRequestModeEnum
    _$overrideConflictQueryRequestModeEnum_INTERVAL =
    const OverrideConflictQueryRequestModeEnum._('INTERVAL');
const OverrideConflictQueryRequestModeEnum
    _$overrideConflictQueryRequestModeEnum_EXPLICIT_TIMES =
    const OverrideConflictQueryRequestModeEnum._('EXPLICIT_TIMES');

OverrideConflictQueryRequestModeEnum
    _$overrideConflictQueryRequestModeEnumValueOf(String name) {
  switch (name) {
    case 'INTERVAL':
      return _$overrideConflictQueryRequestModeEnum_INTERVAL;
    case 'EXPLICIT_TIMES':
      return _$overrideConflictQueryRequestModeEnum_EXPLICIT_TIMES;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<OverrideConflictQueryRequestModeEnum>
    _$overrideConflictQueryRequestModeEnumValues = BuiltSet<
        OverrideConflictQueryRequestModeEnum>(const <OverrideConflictQueryRequestModeEnum>[
  _$overrideConflictQueryRequestModeEnum_INTERVAL,
  _$overrideConflictQueryRequestModeEnum_EXPLICIT_TIMES,
]);

Serializer<OverrideConflictQueryRequestKindEnum>
    _$overrideConflictQueryRequestKindEnumSerializer =
    _$OverrideConflictQueryRequestKindEnumSerializer();
Serializer<OverrideConflictQueryRequestModeEnum>
    _$overrideConflictQueryRequestModeEnumSerializer =
    _$OverrideConflictQueryRequestModeEnumSerializer();

class _$OverrideConflictQueryRequestKindEnumSerializer
    implements PrimitiveSerializer<OverrideConflictQueryRequestKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };

  @override
  final Iterable<Type> types = const <Type>[
    OverrideConflictQueryRequestKindEnum
  ];
  @override
  final String wireName = 'OverrideConflictQueryRequestKindEnum';

  @override
  Object serialize(
          Serializers serializers, OverrideConflictQueryRequestKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  OverrideConflictQueryRequestKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      OverrideConflictQueryRequestKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$OverrideConflictQueryRequestModeEnumSerializer
    implements PrimitiveSerializer<OverrideConflictQueryRequestModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };

  @override
  final Iterable<Type> types = const <Type>[
    OverrideConflictQueryRequestModeEnum
  ];
  @override
  final String wireName = 'OverrideConflictQueryRequestModeEnum';

  @override
  Object serialize(
          Serializers serializers, OverrideConflictQueryRequestModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  OverrideConflictQueryRequestModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      OverrideConflictQueryRequestModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$OverrideConflictQueryRequest extends OverrideConflictQueryRequest {
  @override
  final Date from;
  @override
  final Date to;
  @override
  final OverrideConflictQueryRequestKindEnum kind;
  @override
  final OverrideConflictQueryRequestModeEnum? mode;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;
  @override
  final bool? kindConsistent;

  factory _$OverrideConflictQueryRequest(
          [void Function(OverrideConflictQueryRequestBuilder)? updates]) =>
      (OverrideConflictQueryRequestBuilder()..update(updates))._build();

  _$OverrideConflictQueryRequest._(
      {required this.from,
      required this.to,
      required this.kind,
      this.mode,
      this.intervals,
      this.times,
      this.kindConsistent})
      : super._();
  @override
  OverrideConflictQueryRequest rebuild(
          void Function(OverrideConflictQueryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OverrideConflictQueryRequestBuilder toBuilder() =>
      OverrideConflictQueryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OverrideConflictQueryRequest &&
        from == other.from &&
        to == other.to &&
        kind == other.kind &&
        mode == other.mode &&
        intervals == other.intervals &&
        times == other.times &&
        kindConsistent == other.kindConsistent;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, to.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jc(_$hash, kindConsistent.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OverrideConflictQueryRequest')
          ..add('from', from)
          ..add('to', to)
          ..add('kind', kind)
          ..add('mode', mode)
          ..add('intervals', intervals)
          ..add('times', times)
          ..add('kindConsistent', kindConsistent))
        .toString();
  }
}

class OverrideConflictQueryRequestBuilder
    implements
        Builder<OverrideConflictQueryRequest,
            OverrideConflictQueryRequestBuilder> {
  _$OverrideConflictQueryRequest? _$v;

  Date? _from;
  Date? get from => _$this._from;
  set from(Date? from) => _$this._from = from;

  Date? _to;
  Date? get to => _$this._to;
  set to(Date? to) => _$this._to = to;

  OverrideConflictQueryRequestKindEnum? _kind;
  OverrideConflictQueryRequestKindEnum? get kind => _$this._kind;
  set kind(OverrideConflictQueryRequestKindEnum? kind) => _$this._kind = kind;

  OverrideConflictQueryRequestModeEnum? _mode;
  OverrideConflictQueryRequestModeEnum? get mode => _$this._mode;
  set mode(OverrideConflictQueryRequestModeEnum? mode) => _$this._mode = mode;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  bool? _kindConsistent;
  bool? get kindConsistent => _$this._kindConsistent;
  set kindConsistent(bool? kindConsistent) =>
      _$this._kindConsistent = kindConsistent;

  OverrideConflictQueryRequestBuilder() {
    OverrideConflictQueryRequest._defaults(this);
  }

  OverrideConflictQueryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _from = $v.from;
      _to = $v.to;
      _kind = $v.kind;
      _mode = $v.mode;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
      _kindConsistent = $v.kindConsistent;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OverrideConflictQueryRequest other) {
    _$v = other as _$OverrideConflictQueryRequest;
  }

  @override
  void update(void Function(OverrideConflictQueryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OverrideConflictQueryRequest build() => _build();

  _$OverrideConflictQueryRequest _build() {
    _$OverrideConflictQueryRequest _$result;
    try {
      _$result = _$v ??
          _$OverrideConflictQueryRequest._(
            from: BuiltValueNullFieldError.checkNotNull(
                from, r'OverrideConflictQueryRequest', 'from'),
            to: BuiltValueNullFieldError.checkNotNull(
                to, r'OverrideConflictQueryRequest', 'to'),
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'OverrideConflictQueryRequest', 'kind'),
            mode: mode,
            intervals: _intervals?.build(),
            times: _times?.build(),
            kindConsistent: kindConsistent,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'intervals';
        _intervals?.build();
        _$failedField = 'times';
        _times?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'OverrideConflictQueryRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
