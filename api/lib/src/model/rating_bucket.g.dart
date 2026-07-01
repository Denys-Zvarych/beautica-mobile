// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rating_bucket.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RatingBucket extends RatingBucket {
  @override
  final int? rating;
  @override
  final int? count;

  factory _$RatingBucket([void Function(RatingBucketBuilder)? updates]) =>
      (RatingBucketBuilder()..update(updates))._build();

  _$RatingBucket._({this.rating, this.count}) : super._();
  @override
  RatingBucket rebuild(void Function(RatingBucketBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RatingBucketBuilder toBuilder() => RatingBucketBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RatingBucket &&
        rating == other.rating &&
        count == other.count;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RatingBucket')
          ..add('rating', rating)
          ..add('count', count))
        .toString();
  }
}

class RatingBucketBuilder
    implements Builder<RatingBucket, RatingBucketBuilder> {
  _$RatingBucket? _$v;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  RatingBucketBuilder() {
    RatingBucket._defaults(this);
  }

  RatingBucketBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rating = $v.rating;
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RatingBucket other) {
    _$v = other as _$RatingBucket;
  }

  @override
  void update(void Function(RatingBucketBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RatingBucket build() => _build();

  _$RatingBucket _build() {
    final _$result = _$v ??
        _$RatingBucket._(
          rating: rating,
          count: count,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
