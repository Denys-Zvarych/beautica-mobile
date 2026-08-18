// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_rating_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserRatingResponse extends UserRatingResponse {
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final BuiltList<RatingBucket>? ratingDistribution;

  factory _$UserRatingResponse(
          [void Function(UserRatingResponseBuilder)? updates]) =>
      (UserRatingResponseBuilder()..update(updates))._build();

  _$UserRatingResponse._(
      {this.avgRating, this.reviewCount, this.ratingDistribution})
      : super._();
  @override
  UserRatingResponse rebuild(
          void Function(UserRatingResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserRatingResponseBuilder toBuilder() =>
      UserRatingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserRatingResponse &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        ratingDistribution == other.ratingDistribution;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, ratingDistribution.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserRatingResponse')
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('ratingDistribution', ratingDistribution))
        .toString();
  }
}

class UserRatingResponseBuilder
    implements Builder<UserRatingResponse, UserRatingResponseBuilder> {
  _$UserRatingResponse? _$v;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  ListBuilder<RatingBucket>? _ratingDistribution;
  ListBuilder<RatingBucket> get ratingDistribution =>
      _$this._ratingDistribution ??= ListBuilder<RatingBucket>();
  set ratingDistribution(ListBuilder<RatingBucket>? ratingDistribution) =>
      _$this._ratingDistribution = ratingDistribution;

  UserRatingResponseBuilder() {
    UserRatingResponse._defaults(this);
  }

  UserRatingResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _ratingDistribution = $v.ratingDistribution?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserRatingResponse other) {
    _$v = other as _$UserRatingResponse;
  }

  @override
  void update(void Function(UserRatingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserRatingResponse build() => _build();

  _$UserRatingResponse _build() {
    _$UserRatingResponse _$result;
    try {
      _$result = _$v ??
          _$UserRatingResponse._(
            avgRating: avgRating,
            reviewCount: reviewCount,
            ratingDistribution: _ratingDistribution?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'ratingDistribution';
        _ratingDistribution?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UserRatingResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
