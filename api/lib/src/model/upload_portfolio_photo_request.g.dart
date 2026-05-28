// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_portfolio_photo_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadPortfolioPhotoRequest extends UploadPortfolioPhotoRequest {
  @override
  final Uint8List file;

  factory _$UploadPortfolioPhotoRequest(
          [void Function(UploadPortfolioPhotoRequestBuilder)? updates]) =>
      (UploadPortfolioPhotoRequestBuilder()..update(updates))._build();

  _$UploadPortfolioPhotoRequest._({required this.file}) : super._();
  @override
  UploadPortfolioPhotoRequest rebuild(
          void Function(UploadPortfolioPhotoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadPortfolioPhotoRequestBuilder toBuilder() =>
      UploadPortfolioPhotoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadPortfolioPhotoRequest && file == other.file;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, file.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadPortfolioPhotoRequest')
          ..add('file', file))
        .toString();
  }
}

class UploadPortfolioPhotoRequestBuilder
    implements
        Builder<UploadPortfolioPhotoRequest,
            UploadPortfolioPhotoRequestBuilder> {
  _$UploadPortfolioPhotoRequest? _$v;

  Uint8List? _file;
  Uint8List? get file => _$this._file;
  set file(Uint8List? file) => _$this._file = file;

  UploadPortfolioPhotoRequestBuilder() {
    UploadPortfolioPhotoRequest._defaults(this);
  }

  UploadPortfolioPhotoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _file = $v.file;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadPortfolioPhotoRequest other) {
    _$v = other as _$UploadPortfolioPhotoRequest;
  }

  @override
  void update(void Function(UploadPortfolioPhotoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadPortfolioPhotoRequest build() => _build();

  _$UploadPortfolioPhotoRequest _build() {
    final _$result = _$v ??
        _$UploadPortfolioPhotoRequest._(
          file: BuiltValueNullFieldError.checkNotNull(
              file, r'UploadPortfolioPhotoRequest', 'file'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
