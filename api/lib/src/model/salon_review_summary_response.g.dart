// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_review_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonReviewSummaryResponse extends SalonReviewSummaryResponse {
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final BuiltList<RatingBucket>? ratingDistribution;

  factory _$SalonReviewSummaryResponse(
          [void Function(SalonReviewSummaryResponseBuilder)? updates]) =>
      (SalonReviewSummaryResponseBuilder()..update(updates))._build();

  _$SalonReviewSummaryResponse._(
      {this.avgRating, this.reviewCount, this.ratingDistribution})
      : super._();
  @override
  SalonReviewSummaryResponse rebuild(
          void Function(SalonReviewSummaryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonReviewSummaryResponseBuilder toBuilder() =>
      SalonReviewSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonReviewSummaryResponse &&
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
    return (newBuiltValueToStringHelper(r'SalonReviewSummaryResponse')
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('ratingDistribution', ratingDistribution))
        .toString();
  }
}

class SalonReviewSummaryResponseBuilder
    implements
        Builder<SalonReviewSummaryResponse, SalonReviewSummaryResponseBuilder> {
  _$SalonReviewSummaryResponse? _$v;

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

  SalonReviewSummaryResponseBuilder() {
    SalonReviewSummaryResponse._defaults(this);
  }

  SalonReviewSummaryResponseBuilder get _$this {
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
  void replace(SalonReviewSummaryResponse other) {
    _$v = other as _$SalonReviewSummaryResponse;
  }

  @override
  void update(void Function(SalonReviewSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonReviewSummaryResponse build() => _build();

  _$SalonReviewSummaryResponse _build() {
    _$SalonReviewSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$SalonReviewSummaryResponse._(
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
            r'SalonReviewSummaryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
