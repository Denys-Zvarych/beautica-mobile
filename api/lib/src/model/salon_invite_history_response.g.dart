// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_invite_history_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonInviteHistoryResponse extends SalonInviteHistoryResponse {
  @override
  final BuiltList<SalonInviteResponse>? invites;
  @override
  final bool? truncated;

  factory _$SalonInviteHistoryResponse(
          [void Function(SalonInviteHistoryResponseBuilder)? updates]) =>
      (SalonInviteHistoryResponseBuilder()..update(updates))._build();

  _$SalonInviteHistoryResponse._({this.invites, this.truncated}) : super._();
  @override
  SalonInviteHistoryResponse rebuild(
          void Function(SalonInviteHistoryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonInviteHistoryResponseBuilder toBuilder() =>
      SalonInviteHistoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonInviteHistoryResponse &&
        invites == other.invites &&
        truncated == other.truncated;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, invites.hashCode);
    _$hash = $jc(_$hash, truncated.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonInviteHistoryResponse')
          ..add('invites', invites)
          ..add('truncated', truncated))
        .toString();
  }
}

class SalonInviteHistoryResponseBuilder
    implements
        Builder<SalonInviteHistoryResponse, SalonInviteHistoryResponseBuilder> {
  _$SalonInviteHistoryResponse? _$v;

  ListBuilder<SalonInviteResponse>? _invites;
  ListBuilder<SalonInviteResponse> get invites =>
      _$this._invites ??= ListBuilder<SalonInviteResponse>();
  set invites(ListBuilder<SalonInviteResponse>? invites) =>
      _$this._invites = invites;

  bool? _truncated;
  bool? get truncated => _$this._truncated;
  set truncated(bool? truncated) => _$this._truncated = truncated;

  SalonInviteHistoryResponseBuilder() {
    SalonInviteHistoryResponse._defaults(this);
  }

  SalonInviteHistoryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _invites = $v.invites?.toBuilder();
      _truncated = $v.truncated;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonInviteHistoryResponse other) {
    _$v = other as _$SalonInviteHistoryResponse;
  }

  @override
  void update(void Function(SalonInviteHistoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonInviteHistoryResponse build() => _build();

  _$SalonInviteHistoryResponse _build() {
    _$SalonInviteHistoryResponse _$result;
    try {
      _$result = _$v ??
          _$SalonInviteHistoryResponse._(
            invites: _invites?.build(),
            truncated: truncated,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'invites';
        _invites?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonInviteHistoryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
