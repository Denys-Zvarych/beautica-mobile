// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_invite_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewInviteItemResponse extends ReviewInviteItemResponse {
  @override
  final String? bookingId;
  @override
  final String? serviceName;
  @override
  final String? masterName;

  factory _$ReviewInviteItemResponse(
          [void Function(ReviewInviteItemResponseBuilder)? updates]) =>
      (ReviewInviteItemResponseBuilder()..update(updates))._build();

  _$ReviewInviteItemResponse._(
      {this.bookingId, this.serviceName, this.masterName})
      : super._();
  @override
  ReviewInviteItemResponse rebuild(
          void Function(ReviewInviteItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewInviteItemResponseBuilder toBuilder() =>
      ReviewInviteItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewInviteItemResponse &&
        bookingId == other.bookingId &&
        serviceName == other.serviceName &&
        masterName == other.masterName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewInviteItemResponse')
          ..add('bookingId', bookingId)
          ..add('serviceName', serviceName)
          ..add('masterName', masterName))
        .toString();
  }
}

class ReviewInviteItemResponseBuilder
    implements
        Builder<ReviewInviteItemResponse, ReviewInviteItemResponseBuilder> {
  _$ReviewInviteItemResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  ReviewInviteItemResponseBuilder() {
    ReviewInviteItemResponse._defaults(this);
  }

  ReviewInviteItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _serviceName = $v.serviceName;
      _masterName = $v.masterName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewInviteItemResponse other) {
    _$v = other as _$ReviewInviteItemResponse;
  }

  @override
  void update(void Function(ReviewInviteItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewInviteItemResponse build() => _build();

  _$ReviewInviteItemResponse _build() {
    final _$result = _$v ??
        _$ReviewInviteItemResponse._(
          bookingId: bookingId,
          serviceName: serviceName,
          masterName: masterName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
