// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page_response_timeline_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PageResponseTimelineItemResponse
    extends PageResponseTimelineItemResponse {
  @override
  final bool? success;
  @override
  final BuiltList<TimelineItemResponse>? data;
  @override
  final String? message;
  @override
  final int? page;
  @override
  final int? size;
  @override
  final int? totalElements;
  @override
  final int? totalPages;

  factory _$PageResponseTimelineItemResponse(
          [void Function(PageResponseTimelineItemResponseBuilder)? updates]) =>
      (PageResponseTimelineItemResponseBuilder()..update(updates))._build();

  _$PageResponseTimelineItemResponse._(
      {this.success,
      this.data,
      this.message,
      this.page,
      this.size,
      this.totalElements,
      this.totalPages})
      : super._();
  @override
  PageResponseTimelineItemResponse rebuild(
          void Function(PageResponseTimelineItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PageResponseTimelineItemResponseBuilder toBuilder() =>
      PageResponseTimelineItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PageResponseTimelineItemResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message &&
        page == other.page &&
        size == other.size &&
        totalElements == other.totalElements &&
        totalPages == other.totalPages;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, page.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, totalElements.hashCode);
    _$hash = $jc(_$hash, totalPages.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PageResponseTimelineItemResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('page', page)
          ..add('size', size)
          ..add('totalElements', totalElements)
          ..add('totalPages', totalPages))
        .toString();
  }
}

class PageResponseTimelineItemResponseBuilder
    implements
        Builder<PageResponseTimelineItemResponse,
            PageResponseTimelineItemResponseBuilder> {
  _$PageResponseTimelineItemResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<TimelineItemResponse>? _data;
  ListBuilder<TimelineItemResponse> get data =>
      _$this._data ??= ListBuilder<TimelineItemResponse>();
  set data(ListBuilder<TimelineItemResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  int? _page;
  int? get page => _$this._page;
  set page(int? page) => _$this._page = page;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  int? _totalElements;
  int? get totalElements => _$this._totalElements;
  set totalElements(int? totalElements) =>
      _$this._totalElements = totalElements;

  int? _totalPages;
  int? get totalPages => _$this._totalPages;
  set totalPages(int? totalPages) => _$this._totalPages = totalPages;

  PageResponseTimelineItemResponseBuilder() {
    PageResponseTimelineItemResponse._defaults(this);
  }

  PageResponseTimelineItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _page = $v.page;
      _size = $v.size;
      _totalElements = $v.totalElements;
      _totalPages = $v.totalPages;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PageResponseTimelineItemResponse other) {
    _$v = other as _$PageResponseTimelineItemResponse;
  }

  @override
  void update(void Function(PageResponseTimelineItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PageResponseTimelineItemResponse build() => _build();

  _$PageResponseTimelineItemResponse _build() {
    _$PageResponseTimelineItemResponse _$result;
    try {
      _$result = _$v ??
          _$PageResponseTimelineItemResponse._(
            success: success,
            data: _data?.build(),
            message: message,
            page: page,
            size: size,
            totalElements: totalElements,
            totalPages: totalPages,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PageResponseTimelineItemResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
