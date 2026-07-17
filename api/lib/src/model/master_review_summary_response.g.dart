// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_review_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterReviewSummaryResponse extends MasterReviewSummaryResponse {
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final BuiltList<RatingBucket>? ratingDistribution;

  factory _$MasterReviewSummaryResponse(
          [void Function(MasterReviewSummaryResponseBuilder)? updates]) =>
      (MasterReviewSummaryResponseBuilder()..update(updates))._build();

  _$MasterReviewSummaryResponse._(
      {this.avgRating, this.reviewCount, this.ratingDistribution})
      : super._();
  @override
  MasterReviewSummaryResponse rebuild(
          void Function(MasterReviewSummaryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterReviewSummaryResponseBuilder toBuilder() =>
      MasterReviewSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterReviewSummaryResponse &&
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
    return (newBuiltValueToStringHelper(r'MasterReviewSummaryResponse')
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('ratingDistribution', ratingDistribution))
        .toString();
  }
}

class MasterReviewSummaryResponseBuilder
    implements
        Builder<MasterReviewSummaryResponse,
            MasterReviewSummaryResponseBuilder> {
  _$MasterReviewSummaryResponse? _$v;

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

  MasterReviewSummaryResponseBuilder() {
    MasterReviewSummaryResponse._defaults(this);
  }

  MasterReviewSummaryResponseBuilder get _$this {
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
  void replace(MasterReviewSummaryResponse other) {
    _$v = other as _$MasterReviewSummaryResponse;
  }

  @override
  void update(void Function(MasterReviewSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterReviewSummaryResponse build() => _build();

  _$MasterReviewSummaryResponse _build() {
    _$MasterReviewSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$MasterReviewSummaryResponse._(
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
            r'MasterReviewSummaryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
