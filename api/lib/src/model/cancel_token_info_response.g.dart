// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cancel_token_info_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CancelTokenInfoResponse extends CancelTokenInfoResponse {
  @override
  final String? masterName;
  @override
  final String? serviceName;
  @override
  final DateTime? startsAt;
  @override
  final bool? cancellable;
  @override
  final DateTime? windowClosesAt;

  factory _$CancelTokenInfoResponse(
          [void Function(CancelTokenInfoResponseBuilder)? updates]) =>
      (CancelTokenInfoResponseBuilder()..update(updates))._build();

  _$CancelTokenInfoResponse._(
      {this.masterName,
      this.serviceName,
      this.startsAt,
      this.cancellable,
      this.windowClosesAt})
      : super._();
  @override
  CancelTokenInfoResponse rebuild(
          void Function(CancelTokenInfoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CancelTokenInfoResponseBuilder toBuilder() =>
      CancelTokenInfoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CancelTokenInfoResponse &&
        masterName == other.masterName &&
        serviceName == other.serviceName &&
        startsAt == other.startsAt &&
        cancellable == other.cancellable &&
        windowClosesAt == other.windowClosesAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, cancellable.hashCode);
    _$hash = $jc(_$hash, windowClosesAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CancelTokenInfoResponse')
          ..add('masterName', masterName)
          ..add('serviceName', serviceName)
          ..add('startsAt', startsAt)
          ..add('cancellable', cancellable)
          ..add('windowClosesAt', windowClosesAt))
        .toString();
  }
}

class CancelTokenInfoResponseBuilder
    implements
        Builder<CancelTokenInfoResponse, CancelTokenInfoResponseBuilder> {
  _$CancelTokenInfoResponse? _$v;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  bool? _cancellable;
  bool? get cancellable => _$this._cancellable;
  set cancellable(bool? cancellable) => _$this._cancellable = cancellable;

  DateTime? _windowClosesAt;
  DateTime? get windowClosesAt => _$this._windowClosesAt;
  set windowClosesAt(DateTime? windowClosesAt) =>
      _$this._windowClosesAt = windowClosesAt;

  CancelTokenInfoResponseBuilder() {
    CancelTokenInfoResponse._defaults(this);
  }

  CancelTokenInfoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterName = $v.masterName;
      _serviceName = $v.serviceName;
      _startsAt = $v.startsAt;
      _cancellable = $v.cancellable;
      _windowClosesAt = $v.windowClosesAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CancelTokenInfoResponse other) {
    _$v = other as _$CancelTokenInfoResponse;
  }

  @override
  void update(void Function(CancelTokenInfoResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CancelTokenInfoResponse build() => _build();

  _$CancelTokenInfoResponse _build() {
    final _$result = _$v ??
        _$CancelTokenInfoResponse._(
          masterName: masterName,
          serviceName: serviceName,
          startsAt: startsAt,
          cancellable: cancellable,
          windowClosesAt: windowClosesAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
