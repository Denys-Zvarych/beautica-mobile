// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_appointment_review_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateAppointmentReviewRequest extends CreateAppointmentReviewRequest {
  @override
  final int rating;
  @override
  final String? comment;

  factory _$CreateAppointmentReviewRequest(
          [void Function(CreateAppointmentReviewRequestBuilder)? updates]) =>
      (CreateAppointmentReviewRequestBuilder()..update(updates))._build();

  _$CreateAppointmentReviewRequest._({required this.rating, this.comment})
      : super._();
  @override
  CreateAppointmentReviewRequest rebuild(
          void Function(CreateAppointmentReviewRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateAppointmentReviewRequestBuilder toBuilder() =>
      CreateAppointmentReviewRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateAppointmentReviewRequest &&
        rating == other.rating &&
        comment == other.comment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateAppointmentReviewRequest')
          ..add('rating', rating)
          ..add('comment', comment))
        .toString();
  }
}

class CreateAppointmentReviewRequestBuilder
    implements
        Builder<CreateAppointmentReviewRequest,
            CreateAppointmentReviewRequestBuilder> {
  _$CreateAppointmentReviewRequest? _$v;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  CreateAppointmentReviewRequestBuilder() {
    CreateAppointmentReviewRequest._defaults(this);
  }

  CreateAppointmentReviewRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rating = $v.rating;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateAppointmentReviewRequest other) {
    _$v = other as _$CreateAppointmentReviewRequest;
  }

  @override
  void update(void Function(CreateAppointmentReviewRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateAppointmentReviewRequest build() => _build();

  _$CreateAppointmentReviewRequest _build() {
    final _$result = _$v ??
        _$CreateAppointmentReviewRequest._(
          rating: BuiltValueNullFieldError.checkNotNull(
              rating, r'CreateAppointmentReviewRequest', 'rating'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
