// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_suggestion_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SearchSuggestionResponseTypeEnum
    _$searchSuggestionResponseTypeEnum_CATEGORY =
    const SearchSuggestionResponseTypeEnum._('CATEGORY');
const SearchSuggestionResponseTypeEnum
    _$searchSuggestionResponseTypeEnum_SERVICE =
    const SearchSuggestionResponseTypeEnum._('SERVICE');
const SearchSuggestionResponseTypeEnum
    _$searchSuggestionResponseTypeEnum_unknownDefaultOpenApi =
    const SearchSuggestionResponseTypeEnum._('unknownDefaultOpenApi');

SearchSuggestionResponseTypeEnum _$searchSuggestionResponseTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'CATEGORY':
      return _$searchSuggestionResponseTypeEnum_CATEGORY;
    case 'SERVICE':
      return _$searchSuggestionResponseTypeEnum_SERVICE;
    case 'unknownDefaultOpenApi':
      return _$searchSuggestionResponseTypeEnum_unknownDefaultOpenApi;
    default:
      return _$searchSuggestionResponseTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<SearchSuggestionResponseTypeEnum>
    _$searchSuggestionResponseTypeEnumValues = BuiltSet<
        SearchSuggestionResponseTypeEnum>(const <SearchSuggestionResponseTypeEnum>[
  _$searchSuggestionResponseTypeEnum_CATEGORY,
  _$searchSuggestionResponseTypeEnum_SERVICE,
  _$searchSuggestionResponseTypeEnum_unknownDefaultOpenApi,
]);

Serializer<SearchSuggestionResponseTypeEnum>
    _$searchSuggestionResponseTypeEnumSerializer =
    _$SearchSuggestionResponseTypeEnumSerializer();

class _$SearchSuggestionResponseTypeEnumSerializer
    implements PrimitiveSerializer<SearchSuggestionResponseTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CATEGORY': 'CATEGORY',
    'SERVICE': 'SERVICE',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CATEGORY': 'CATEGORY',
    'SERVICE': 'SERVICE',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[SearchSuggestionResponseTypeEnum];
  @override
  final String wireName = 'SearchSuggestionResponseTypeEnum';

  @override
  Object serialize(
          Serializers serializers, SearchSuggestionResponseTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SearchSuggestionResponseTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SearchSuggestionResponseTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SearchSuggestionResponse extends SearchSuggestionResponse {
  @override
  final SearchSuggestionResponseTypeEnum? type;
  @override
  final String? label;
  @override
  final String? categoryKey;
  @override
  final String? serviceTypeSlug;

  factory _$SearchSuggestionResponse(
          [void Function(SearchSuggestionResponseBuilder)? updates]) =>
      (SearchSuggestionResponseBuilder()..update(updates))._build();

  _$SearchSuggestionResponse._(
      {this.type, this.label, this.categoryKey, this.serviceTypeSlug})
      : super._();
  @override
  SearchSuggestionResponse rebuild(
          void Function(SearchSuggestionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SearchSuggestionResponseBuilder toBuilder() =>
      SearchSuggestionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SearchSuggestionResponse &&
        type == other.type &&
        label == other.label &&
        categoryKey == other.categoryKey &&
        serviceTypeSlug == other.serviceTypeSlug;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, categoryKey.hashCode);
    _$hash = $jc(_$hash, serviceTypeSlug.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SearchSuggestionResponse')
          ..add('type', type)
          ..add('label', label)
          ..add('categoryKey', categoryKey)
          ..add('serviceTypeSlug', serviceTypeSlug))
        .toString();
  }
}

class SearchSuggestionResponseBuilder
    implements
        Builder<SearchSuggestionResponse, SearchSuggestionResponseBuilder> {
  _$SearchSuggestionResponse? _$v;

  SearchSuggestionResponseTypeEnum? _type;
  SearchSuggestionResponseTypeEnum? get type => _$this._type;
  set type(SearchSuggestionResponseTypeEnum? type) => _$this._type = type;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _categoryKey;
  String? get categoryKey => _$this._categoryKey;
  set categoryKey(String? categoryKey) => _$this._categoryKey = categoryKey;

  String? _serviceTypeSlug;
  String? get serviceTypeSlug => _$this._serviceTypeSlug;
  set serviceTypeSlug(String? serviceTypeSlug) =>
      _$this._serviceTypeSlug = serviceTypeSlug;

  SearchSuggestionResponseBuilder() {
    SearchSuggestionResponse._defaults(this);
  }

  SearchSuggestionResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _label = $v.label;
      _categoryKey = $v.categoryKey;
      _serviceTypeSlug = $v.serviceTypeSlug;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SearchSuggestionResponse other) {
    _$v = other as _$SearchSuggestionResponse;
  }

  @override
  void update(void Function(SearchSuggestionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SearchSuggestionResponse build() => _build();

  _$SearchSuggestionResponse _build() {
    final _$result = _$v ??
        _$SearchSuggestionResponse._(
          type: type,
          label: label,
          categoryKey: categoryKey,
          serviceTypeSlug: serviceTypeSlug,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
