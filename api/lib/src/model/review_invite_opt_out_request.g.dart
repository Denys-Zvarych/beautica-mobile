// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_invite_opt_out_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewInviteOptOutRequest extends ReviewInviteOptOutRequest {
  @override
  final String? turnstileToken;

  factory _$ReviewInviteOptOutRequest(
          [void Function(ReviewInviteOptOutRequestBuilder)? updates]) =>
      (ReviewInviteOptOutRequestBuilder()..update(updates))._build();

  _$ReviewInviteOptOutRequest._({this.turnstileToken}) : super._();
  @override
  ReviewInviteOptOutRequest rebuild(
          void Function(ReviewInviteOptOutRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewInviteOptOutRequestBuilder toBuilder() =>
      ReviewInviteOptOutRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewInviteOptOutRequest &&
        turnstileToken == other.turnstileToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, turnstileToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewInviteOptOutRequest')
          ..add('turnstileToken', turnstileToken))
        .toString();
  }
}

class ReviewInviteOptOutRequestBuilder
    implements
        Builder<ReviewInviteOptOutRequest, ReviewInviteOptOutRequestBuilder> {
  _$ReviewInviteOptOutRequest? _$v;

  String? _turnstileToken;
  String? get turnstileToken => _$this._turnstileToken;
  set turnstileToken(String? turnstileToken) =>
      _$this._turnstileToken = turnstileToken;

  ReviewInviteOptOutRequestBuilder() {
    ReviewInviteOptOutRequest._defaults(this);
  }

  ReviewInviteOptOutRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _turnstileToken = $v.turnstileToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewInviteOptOutRequest other) {
    _$v = other as _$ReviewInviteOptOutRequest;
  }

  @override
  void update(void Function(ReviewInviteOptOutRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewInviteOptOutRequest build() => _build();

  _$ReviewInviteOptOutRequest _build() {
    final _$result = _$v ??
        _$ReviewInviteOptOutRequest._(
          turnstileToken: turnstileToken,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
