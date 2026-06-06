// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_service_types200_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GetServiceTypes200Response extends GetServiceTypes200Response {
  @override
  final OneOf oneOf;

  factory _$GetServiceTypes200Response(
          [void Function(GetServiceTypes200ResponseBuilder)? updates]) =>
      (GetServiceTypes200ResponseBuilder()..update(updates))._build();

  _$GetServiceTypes200Response._({required this.oneOf}) : super._();
  @override
  GetServiceTypes200Response rebuild(
          void Function(GetServiceTypes200ResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetServiceTypes200ResponseBuilder toBuilder() =>
      GetServiceTypes200ResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetServiceTypes200Response && oneOf == other.oneOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, oneOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GetServiceTypes200Response')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class GetServiceTypes200ResponseBuilder
    implements
        Builder<GetServiceTypes200Response, GetServiceTypes200ResponseBuilder> {
  _$GetServiceTypes200Response? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  GetServiceTypes200ResponseBuilder() {
    GetServiceTypes200Response._defaults(this);
  }

  GetServiceTypes200ResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetServiceTypes200Response other) {
    _$v = other as _$GetServiceTypes200Response;
  }

  @override
  void update(void Function(GetServiceTypes200ResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GetServiceTypes200Response build() => _build();

  _$GetServiceTypes200Response _build() {
    final _$result = _$v ??
        _$GetServiceTypes200Response._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'GetServiceTypes200Response', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
