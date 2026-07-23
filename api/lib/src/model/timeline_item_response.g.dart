// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TimelineItemResponse extends TimelineItemResponse {
  @override
  final String? bookingId;
  @override
  final String? categoryKey;
  @override
  final String? categoryName;
  @override
  final Date? date;
  @override
  final String? masterId;
  @override
  final String? serviceName;

  factory _$TimelineItemResponse(
          [void Function(TimelineItemResponseBuilder)? updates]) =>
      (TimelineItemResponseBuilder()..update(updates))._build();

  _$TimelineItemResponse._(
      {this.bookingId,
      this.categoryKey,
      this.categoryName,
      this.date,
      this.masterId,
      this.serviceName})
      : super._();
  @override
  TimelineItemResponse rebuild(
          void Function(TimelineItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TimelineItemResponseBuilder toBuilder() =>
      TimelineItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TimelineItemResponse &&
        bookingId == other.bookingId &&
        categoryKey == other.categoryKey &&
        categoryName == other.categoryName &&
        date == other.date &&
        masterId == other.masterId &&
        serviceName == other.serviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, categoryKey.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TimelineItemResponse')
          ..add('bookingId', bookingId)
          ..add('categoryKey', categoryKey)
          ..add('categoryName', categoryName)
          ..add('date', date)
          ..add('masterId', masterId)
          ..add('serviceName', serviceName))
        .toString();
  }
}

class TimelineItemResponseBuilder
    implements Builder<TimelineItemResponse, TimelineItemResponseBuilder> {
  _$TimelineItemResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _categoryKey;
  String? get categoryKey => _$this._categoryKey;
  set categoryKey(String? categoryKey) => _$this._categoryKey = categoryKey;

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  TimelineItemResponseBuilder() {
    TimelineItemResponse._defaults(this);
  }

  TimelineItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _categoryKey = $v.categoryKey;
      _categoryName = $v.categoryName;
      _date = $v.date;
      _masterId = $v.masterId;
      _serviceName = $v.serviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TimelineItemResponse other) {
    _$v = other as _$TimelineItemResponse;
  }

  @override
  void update(void Function(TimelineItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TimelineItemResponse build() => _build();

  _$TimelineItemResponse _build() {
    final _$result = _$v ??
        _$TimelineItemResponse._(
          bookingId: bookingId,
          categoryKey: categoryKey,
          categoryName: categoryName,
          date: date,
          masterId: masterId,
          serviceName: serviceName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
