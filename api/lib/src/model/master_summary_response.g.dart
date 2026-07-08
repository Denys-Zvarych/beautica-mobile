// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MasterSummaryResponseMasterTypeEnum
    _$masterSummaryResponseMasterTypeEnum_SALON_MASTER =
    const MasterSummaryResponseMasterTypeEnum._('SALON_MASTER');
const MasterSummaryResponseMasterTypeEnum
    _$masterSummaryResponseMasterTypeEnum_INDEPENDENT_MASTER =
    const MasterSummaryResponseMasterTypeEnum._('INDEPENDENT_MASTER');
const MasterSummaryResponseMasterTypeEnum
    _$masterSummaryResponseMasterTypeEnum_SALON_OWNER =
    const MasterSummaryResponseMasterTypeEnum._('SALON_OWNER');

MasterSummaryResponseMasterTypeEnum
    _$masterSummaryResponseMasterTypeEnumValueOf(String name) {
  switch (name) {
    case 'SALON_MASTER':
      return _$masterSummaryResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$masterSummaryResponseMasterTypeEnum_INDEPENDENT_MASTER;
    case 'SALON_OWNER':
      return _$masterSummaryResponseMasterTypeEnum_SALON_OWNER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MasterSummaryResponseMasterTypeEnum>
    _$masterSummaryResponseMasterTypeEnumValues = BuiltSet<
        MasterSummaryResponseMasterTypeEnum>(const <MasterSummaryResponseMasterTypeEnum>[
  _$masterSummaryResponseMasterTypeEnum_SALON_MASTER,
  _$masterSummaryResponseMasterTypeEnum_INDEPENDENT_MASTER,
  _$masterSummaryResponseMasterTypeEnum_SALON_OWNER,
]);

Serializer<MasterSummaryResponseMasterTypeEnum>
    _$masterSummaryResponseMasterTypeEnumSerializer =
    _$MasterSummaryResponseMasterTypeEnumSerializer();

class _$MasterSummaryResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<MasterSummaryResponseMasterTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
  };

  @override
  final Iterable<Type> types = const <Type>[
    MasterSummaryResponseMasterTypeEnum
  ];
  @override
  final String wireName = 'MasterSummaryResponseMasterTypeEnum';

  @override
  Object serialize(
          Serializers serializers, MasterSummaryResponseMasterTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MasterSummaryResponseMasterTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MasterSummaryResponseMasterTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MasterSummaryResponse extends MasterSummaryResponse {
  @override
  final String? masterId;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? professionalTitle;
  @override
  final String? avatarUrl;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final MasterSummaryResponseMasterTypeEnum? masterType;

  factory _$MasterSummaryResponse(
          [void Function(MasterSummaryResponseBuilder)? updates]) =>
      (MasterSummaryResponseBuilder()..update(updates))._build();

  _$MasterSummaryResponse._(
      {this.masterId,
      this.firstName,
      this.lastName,
      this.professionalTitle,
      this.avatarUrl,
      this.avgRating,
      this.reviewCount,
      this.masterType})
      : super._();
  @override
  MasterSummaryResponse rebuild(
          void Function(MasterSummaryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterSummaryResponseBuilder toBuilder() =>
      MasterSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterSummaryResponse &&
        masterId == other.masterId &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        professionalTitle == other.professionalTitle &&
        avatarUrl == other.avatarUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        masterType == other.masterType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterSummaryResponse')
          ..add('masterId', masterId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('professionalTitle', professionalTitle)
          ..add('avatarUrl', avatarUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('masterType', masterType))
        .toString();
  }
}

class MasterSummaryResponseBuilder
    implements Builder<MasterSummaryResponse, MasterSummaryResponseBuilder> {
  _$MasterSummaryResponse? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  MasterSummaryResponseMasterTypeEnum? _masterType;
  MasterSummaryResponseMasterTypeEnum? get masterType => _$this._masterType;
  set masterType(MasterSummaryResponseMasterTypeEnum? masterType) =>
      _$this._masterType = masterType;

  MasterSummaryResponseBuilder() {
    MasterSummaryResponse._defaults(this);
  }

  MasterSummaryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _professionalTitle = $v.professionalTitle;
      _avatarUrl = $v.avatarUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _masterType = $v.masterType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterSummaryResponse other) {
    _$v = other as _$MasterSummaryResponse;
  }

  @override
  void update(void Function(MasterSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterSummaryResponse build() => _build();

  _$MasterSummaryResponse _build() {
    final _$result = _$v ??
        _$MasterSummaryResponse._(
          masterId: masterId,
          firstName: firstName,
          lastName: lastName,
          professionalTitle: professionalTitle,
          avatarUrl: avatarUrl,
          avgRating: avgRating,
          reviewCount: reviewCount,
          masterType: masterType,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
