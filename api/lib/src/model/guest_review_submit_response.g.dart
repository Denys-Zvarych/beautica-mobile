// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_review_submit_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestReviewSubmitResponse extends GuestReviewSubmitResponse {
  @override
  final int? created;

  factory _$GuestReviewSubmitResponse(
          [void Function(GuestReviewSubmitResponseBuilder)? updates]) =>
      (GuestReviewSubmitResponseBuilder()..update(updates))._build();

  _$GuestReviewSubmitResponse._({this.created}) : super._();
  @override
  GuestReviewSubmitResponse rebuild(
          void Function(GuestReviewSubmitResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestReviewSubmitResponseBuilder toBuilder() =>
      GuestReviewSubmitResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestReviewSubmitResponse && created == other.created;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, created.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestReviewSubmitResponse')
          ..add('created', created))
        .toString();
  }
}

class GuestReviewSubmitResponseBuilder
    implements
        Builder<GuestReviewSubmitResponse, GuestReviewSubmitResponseBuilder> {
  _$GuestReviewSubmitResponse? _$v;

  int? _created;
  int? get created => _$this._created;
  set created(int? created) => _$this._created = created;

  GuestReviewSubmitResponseBuilder() {
    GuestReviewSubmitResponse._defaults(this);
  }

  GuestReviewSubmitResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _created = $v.created;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestReviewSubmitResponse other) {
    _$v = other as _$GuestReviewSubmitResponse;
  }

  @override
  void update(void Function(GuestReviewSubmitResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestReviewSubmitResponse build() => _build();

  _$GuestReviewSubmitResponse _build() {
    final _$result = _$v ??
        _$GuestReviewSubmitResponse._(
          created: created,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
