// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_create_services_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BulkCreateServicesRequest extends BulkCreateServicesRequest {
  @override
  final BuiltList<BulkServiceItemRequest> items;

  factory _$BulkCreateServicesRequest(
          [void Function(BulkCreateServicesRequestBuilder)? updates]) =>
      (BulkCreateServicesRequestBuilder()..update(updates))._build();

  _$BulkCreateServicesRequest._({required this.items}) : super._();
  @override
  BulkCreateServicesRequest rebuild(
          void Function(BulkCreateServicesRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BulkCreateServicesRequestBuilder toBuilder() =>
      BulkCreateServicesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BulkCreateServicesRequest && items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BulkCreateServicesRequest')
          ..add('items', items))
        .toString();
  }
}

class BulkCreateServicesRequestBuilder
    implements
        Builder<BulkCreateServicesRequest, BulkCreateServicesRequestBuilder> {
  _$BulkCreateServicesRequest? _$v;

  ListBuilder<BulkServiceItemRequest>? _items;
  ListBuilder<BulkServiceItemRequest> get items =>
      _$this._items ??= ListBuilder<BulkServiceItemRequest>();
  set items(ListBuilder<BulkServiceItemRequest>? items) =>
      _$this._items = items;

  BulkCreateServicesRequestBuilder() {
    BulkCreateServicesRequest._defaults(this);
  }

  BulkCreateServicesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BulkCreateServicesRequest other) {
    _$v = other as _$BulkCreateServicesRequest;
  }

  @override
  void update(void Function(BulkCreateServicesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BulkCreateServicesRequest build() => _build();

  _$BulkCreateServicesRequest _build() {
    _$BulkCreateServicesRequest _$result;
    try {
      _$result = _$v ??
          _$BulkCreateServicesRequest._(
            items: items.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BulkCreateServicesRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
