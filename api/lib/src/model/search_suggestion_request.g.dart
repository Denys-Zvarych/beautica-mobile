// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_suggestion_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SearchSuggestionRequest extends SearchSuggestionRequest {
  @override
  final String q;
  @override
  final int? limit;
  @override
  final LocationFilter? location;

  factory _$SearchSuggestionRequest(
          [void Function(SearchSuggestionRequestBuilder)? updates]) =>
      (SearchSuggestionRequestBuilder()..update(updates))._build();

  _$SearchSuggestionRequest._({required this.q, this.limit, this.location})
      : super._();
  @override
  SearchSuggestionRequest rebuild(
          void Function(SearchSuggestionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SearchSuggestionRequestBuilder toBuilder() =>
      SearchSuggestionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SearchSuggestionRequest &&
        q == other.q &&
        limit == other.limit &&
        location == other.location;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, q.hashCode);
    _$hash = $jc(_$hash, limit.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SearchSuggestionRequest')
          ..add('q', q)
          ..add('limit', limit)
          ..add('location', location))
        .toString();
  }
}

class SearchSuggestionRequestBuilder
    implements
        Builder<SearchSuggestionRequest, SearchSuggestionRequestBuilder> {
  _$SearchSuggestionRequest? _$v;

  String? _q;
  String? get q => _$this._q;
  set q(String? q) => _$this._q = q;

  int? _limit;
  int? get limit => _$this._limit;
  set limit(int? limit) => _$this._limit = limit;

  LocationFilterBuilder? _location;
  LocationFilterBuilder get location =>
      _$this._location ??= LocationFilterBuilder();
  set location(LocationFilterBuilder? location) => _$this._location = location;

  SearchSuggestionRequestBuilder() {
    SearchSuggestionRequest._defaults(this);
  }

  SearchSuggestionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _q = $v.q;
      _limit = $v.limit;
      _location = $v.location?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SearchSuggestionRequest other) {
    _$v = other as _$SearchSuggestionRequest;
  }

  @override
  void update(void Function(SearchSuggestionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SearchSuggestionRequest build() => _build();

  _$SearchSuggestionRequest _build() {
    _$SearchSuggestionRequest _$result;
    try {
      _$result = _$v ??
          _$SearchSuggestionRequest._(
            q: BuiltValueNullFieldError.checkNotNull(
                q, r'SearchSuggestionRequest', 'q'),
            limit: limit,
            location: _location?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'location';
        _location?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SearchSuggestionRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
