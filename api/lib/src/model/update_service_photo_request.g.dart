// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_service_photo_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateServicePhotoRequest extends UpdateServicePhotoRequest {
  @override
  final String photoUrl;

  factory _$UpdateServicePhotoRequest(
          [void Function(UpdateServicePhotoRequestBuilder)? updates]) =>
      (UpdateServicePhotoRequestBuilder()..update(updates))._build();

  _$UpdateServicePhotoRequest._({required this.photoUrl}) : super._();
  @override
  UpdateServicePhotoRequest rebuild(
          void Function(UpdateServicePhotoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateServicePhotoRequestBuilder toBuilder() =>
      UpdateServicePhotoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateServicePhotoRequest && photoUrl == other.photoUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, photoUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateServicePhotoRequest')
          ..add('photoUrl', photoUrl))
        .toString();
  }
}

class UpdateServicePhotoRequestBuilder
    implements
        Builder<UpdateServicePhotoRequest, UpdateServicePhotoRequestBuilder> {
  _$UpdateServicePhotoRequest? _$v;

  String? _photoUrl;
  String? get photoUrl => _$this._photoUrl;
  set photoUrl(String? photoUrl) => _$this._photoUrl = photoUrl;

  UpdateServicePhotoRequestBuilder() {
    UpdateServicePhotoRequest._defaults(this);
  }

  UpdateServicePhotoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _photoUrl = $v.photoUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateServicePhotoRequest other) {
    _$v = other as _$UpdateServicePhotoRequest;
  }

  @override
  void update(void Function(UpdateServicePhotoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateServicePhotoRequest build() => _build();

  _$UpdateServicePhotoRequest _build() {
    final _$result = _$v ??
        _$UpdateServicePhotoRequest._(
          photoUrl: BuiltValueNullFieldError.checkNotNull(
              photoUrl, r'UpdateServicePhotoRequest', 'photoUrl'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
