// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'override_conflict_preview_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OverrideConflictPreviewResponse
    extends OverrideConflictPreviewResponse {
  @override
  final BuiltList<OverrideConflictResponse>? conflicts;
  @override
  final int? totalCount;
  @override
  final bool? truncated;
  @override
  final bool? scanTruncated;

  factory _$OverrideConflictPreviewResponse(
          [void Function(OverrideConflictPreviewResponseBuilder)? updates]) =>
      (OverrideConflictPreviewResponseBuilder()..update(updates))._build();

  _$OverrideConflictPreviewResponse._(
      {this.conflicts, this.totalCount, this.truncated, this.scanTruncated})
      : super._();
  @override
  OverrideConflictPreviewResponse rebuild(
          void Function(OverrideConflictPreviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OverrideConflictPreviewResponseBuilder toBuilder() =>
      OverrideConflictPreviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OverrideConflictPreviewResponse &&
        conflicts == other.conflicts &&
        totalCount == other.totalCount &&
        truncated == other.truncated &&
        scanTruncated == other.scanTruncated;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, conflicts.hashCode);
    _$hash = $jc(_$hash, totalCount.hashCode);
    _$hash = $jc(_$hash, truncated.hashCode);
    _$hash = $jc(_$hash, scanTruncated.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OverrideConflictPreviewResponse')
          ..add('conflicts', conflicts)
          ..add('totalCount', totalCount)
          ..add('truncated', truncated)
          ..add('scanTruncated', scanTruncated))
        .toString();
  }
}

class OverrideConflictPreviewResponseBuilder
    implements
        Builder<OverrideConflictPreviewResponse,
            OverrideConflictPreviewResponseBuilder> {
  _$OverrideConflictPreviewResponse? _$v;

  ListBuilder<OverrideConflictResponse>? _conflicts;
  ListBuilder<OverrideConflictResponse> get conflicts =>
      _$this._conflicts ??= ListBuilder<OverrideConflictResponse>();
  set conflicts(ListBuilder<OverrideConflictResponse>? conflicts) =>
      _$this._conflicts = conflicts;

  int? _totalCount;
  int? get totalCount => _$this._totalCount;
  set totalCount(int? totalCount) => _$this._totalCount = totalCount;

  bool? _truncated;
  bool? get truncated => _$this._truncated;
  set truncated(bool? truncated) => _$this._truncated = truncated;

  bool? _scanTruncated;
  bool? get scanTruncated => _$this._scanTruncated;
  set scanTruncated(bool? scanTruncated) =>
      _$this._scanTruncated = scanTruncated;

  OverrideConflictPreviewResponseBuilder() {
    OverrideConflictPreviewResponse._defaults(this);
  }

  OverrideConflictPreviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _conflicts = $v.conflicts?.toBuilder();
      _totalCount = $v.totalCount;
      _truncated = $v.truncated;
      _scanTruncated = $v.scanTruncated;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OverrideConflictPreviewResponse other) {
    _$v = other as _$OverrideConflictPreviewResponse;
  }

  @override
  void update(void Function(OverrideConflictPreviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OverrideConflictPreviewResponse build() => _build();

  _$OverrideConflictPreviewResponse _build() {
    _$OverrideConflictPreviewResponse _$result;
    try {
      _$result = _$v ??
          _$OverrideConflictPreviewResponse._(
            conflicts: _conflicts?.build(),
            totalCount: totalCount,
            truncated: truncated,
            scanTruncated: scanTruncated,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'conflicts';
        _conflicts?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'OverrideConflictPreviewResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
