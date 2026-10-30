// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewInviteResponse extends ReviewInviteResponse {
  @override
  final String? state;
  @override
  final String? providerName;
  @override
  final String? providerType;
  @override
  final Date? visitDate;
  @override
  final BuiltList<ReviewInviteItemResponse>? items;
  @override
  final String? displayName;
  @override
  final String? avatarUrl;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final String? professionalTitle;

  factory _$ReviewInviteResponse(
          [void Function(ReviewInviteResponseBuilder)? updates]) =>
      (ReviewInviteResponseBuilder()..update(updates))._build();

  _$ReviewInviteResponse._(
      {this.state,
      this.providerName,
      this.providerType,
      this.visitDate,
      this.items,
      this.displayName,
      this.avatarUrl,
      this.avgRating,
      this.reviewCount,
      this.professionalTitle})
      : super._();
  @override
  ReviewInviteResponse rebuild(
          void Function(ReviewInviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewInviteResponseBuilder toBuilder() =>
      ReviewInviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewInviteResponse &&
        state == other.state &&
        providerName == other.providerName &&
        providerType == other.providerType &&
        visitDate == other.visitDate &&
        items == other.items &&
        displayName == other.displayName &&
        avatarUrl == other.avatarUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        professionalTitle == other.professionalTitle;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, providerName.hashCode);
    _$hash = $jc(_$hash, providerType.hashCode);
    _$hash = $jc(_$hash, visitDate.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewInviteResponse')
          ..add('state', state)
          ..add('providerName', providerName)
          ..add('providerType', providerType)
          ..add('visitDate', visitDate)
          ..add('items', items)
          ..add('displayName', displayName)
          ..add('avatarUrl', avatarUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('professionalTitle', professionalTitle))
        .toString();
  }
}

class ReviewInviteResponseBuilder
    implements Builder<ReviewInviteResponse, ReviewInviteResponseBuilder> {
  _$ReviewInviteResponse? _$v;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  String? _providerName;
  String? get providerName => _$this._providerName;
  set providerName(String? providerName) => _$this._providerName = providerName;

  String? _providerType;
  String? get providerType => _$this._providerType;
  set providerType(String? providerType) => _$this._providerType = providerType;

  Date? _visitDate;
  Date? get visitDate => _$this._visitDate;
  set visitDate(Date? visitDate) => _$this._visitDate = visitDate;

  ListBuilder<ReviewInviteItemResponse>? _items;
  ListBuilder<ReviewInviteItemResponse> get items =>
      _$this._items ??= ListBuilder<ReviewInviteItemResponse>();
  set items(ListBuilder<ReviewInviteItemResponse>? items) =>
      _$this._items = items;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  ReviewInviteResponseBuilder() {
    ReviewInviteResponse._defaults(this);
  }

  ReviewInviteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _state = $v.state;
      _providerName = $v.providerName;
      _providerType = $v.providerType;
      _visitDate = $v.visitDate;
      _items = $v.items?.toBuilder();
      _displayName = $v.displayName;
      _avatarUrl = $v.avatarUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _professionalTitle = $v.professionalTitle;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewInviteResponse other) {
    _$v = other as _$ReviewInviteResponse;
  }

  @override
  void update(void Function(ReviewInviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewInviteResponse build() => _build();

  _$ReviewInviteResponse _build() {
    _$ReviewInviteResponse _$result;
    try {
      _$result = _$v ??
          _$ReviewInviteResponse._(
            state: state,
            providerName: providerName,
            providerType: providerType,
            visitDate: visitDate,
            items: _items?.build(),
            displayName: displayName,
            avatarUrl: avatarUrl,
            avgRating: avgRating,
            reviewCount: reviewCount,
            professionalTitle: professionalTitle,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ReviewInviteResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
