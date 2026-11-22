// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_visit_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientVisitResponse extends ClientVisitResponse {
  @override
  final String? visitKey;
  @override
  final DateTime? startsAt;
  @override
  final String? salonId;
  @override
  final BuiltList<Item>? items;

  factory _$ClientVisitResponse(
          [void Function(ClientVisitResponseBuilder)? updates]) =>
      (ClientVisitResponseBuilder()..update(updates))._build();

  _$ClientVisitResponse._(
      {this.visitKey, this.startsAt, this.salonId, this.items})
      : super._();
  @override
  ClientVisitResponse rebuild(
          void Function(ClientVisitResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientVisitResponseBuilder toBuilder() =>
      ClientVisitResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientVisitResponse &&
        visitKey == other.visitKey &&
        startsAt == other.startsAt &&
        salonId == other.salonId &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, visitKey.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientVisitResponse')
          ..add('visitKey', visitKey)
          ..add('startsAt', startsAt)
          ..add('salonId', salonId)
          ..add('items', items))
        .toString();
  }
}

class ClientVisitResponseBuilder
    implements Builder<ClientVisitResponse, ClientVisitResponseBuilder> {
  _$ClientVisitResponse? _$v;

  String? _visitKey;
  String? get visitKey => _$this._visitKey;
  set visitKey(String? visitKey) => _$this._visitKey = visitKey;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  ListBuilder<Item>? _items;
  ListBuilder<Item> get items => _$this._items ??= ListBuilder<Item>();
  set items(ListBuilder<Item>? items) => _$this._items = items;

  ClientVisitResponseBuilder() {
    ClientVisitResponse._defaults(this);
  }

  ClientVisitResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _visitKey = $v.visitKey;
      _startsAt = $v.startsAt;
      _salonId = $v.salonId;
      _items = $v.items?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientVisitResponse other) {
    _$v = other as _$ClientVisitResponse;
  }

  @override
  void update(void Function(ClientVisitResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientVisitResponse build() => _build();

  _$ClientVisitResponse _build() {
    _$ClientVisitResponse _$result;
    try {
      _$result = _$v ??
          _$ClientVisitResponse._(
            visitKey: visitKey,
            startsAt: startsAt,
            salonId: salonId,
            items: _items?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ClientVisitResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
