// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'independent_master_update_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$IndependentMasterUpdateRequest extends IndependentMasterUpdateRequest {
  @override
  final String cityId;
  @override
  final String? districtId;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;

  factory _$IndependentMasterUpdateRequest(
          [void Function(IndependentMasterUpdateRequestBuilder)? updates]) =>
      (IndependentMasterUpdateRequestBuilder()..update(updates))._build();

  _$IndependentMasterUpdateRequest._(
      {required this.cityId,
      this.districtId,
      this.street,
      this.buildingNo,
      this.locationNote})
      : super._();
  @override
  IndependentMasterUpdateRequest rebuild(
          void Function(IndependentMasterUpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  IndependentMasterUpdateRequestBuilder toBuilder() =>
      IndependentMasterUpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is IndependentMasterUpdateRequest &&
        cityId == other.cityId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'IndependentMasterUpdateRequest')
          ..add('cityId', cityId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote))
        .toString();
  }
}

class IndependentMasterUpdateRequestBuilder
    implements
        Builder<IndependentMasterUpdateRequest,
            IndependentMasterUpdateRequestBuilder> {
  _$IndependentMasterUpdateRequest? _$v;

  String? _cityId;
  String? get cityId => _$this._cityId;
  set cityId(String? cityId) => _$this._cityId = cityId;

  String? _districtId;
  String? get districtId => _$this._districtId;
  set districtId(String? districtId) => _$this._districtId = districtId;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  IndependentMasterUpdateRequestBuilder() {
    IndependentMasterUpdateRequest._defaults(this);
  }

  IndependentMasterUpdateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(IndependentMasterUpdateRequest other) {
    _$v = other as _$IndependentMasterUpdateRequest;
  }

  @override
  void update(void Function(IndependentMasterUpdateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  IndependentMasterUpdateRequest build() => _build();

  _$IndependentMasterUpdateRequest _build() {
    final _$result = _$v ??
        _$IndependentMasterUpdateRequest._(
          cityId: BuiltValueNullFieldError.checkNotNull(
              cityId, r'IndependentMasterUpdateRequest', 'cityId'),
          districtId: districtId,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
