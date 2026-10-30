// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_report_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_REVIEW =
    const CreateReportRequestTargetTypeEnum._('REVIEW');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_CLIENT_REVIEW =
    const CreateReportRequestTargetTypeEnum._('CLIENT_REVIEW');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_PORTFOLIO_PHOTO =
    const CreateReportRequestTargetTypeEnum._('PORTFOLIO_PHOTO');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_MASTER_PROFILE =
    const CreateReportRequestTargetTypeEnum._('MASTER_PROFILE');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_SALON_PROFILE =
    const CreateReportRequestTargetTypeEnum._('SALON_PROFILE');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_CLIENT_PROFILE =
    const CreateReportRequestTargetTypeEnum._('CLIENT_PROFILE');
const CreateReportRequestTargetTypeEnum
    _$createReportRequestTargetTypeEnum_unknownDefaultOpenApi =
    const CreateReportRequestTargetTypeEnum._('unknownDefaultOpenApi');

CreateReportRequestTargetTypeEnum _$createReportRequestTargetTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'REVIEW':
      return _$createReportRequestTargetTypeEnum_REVIEW;
    case 'CLIENT_REVIEW':
      return _$createReportRequestTargetTypeEnum_CLIENT_REVIEW;
    case 'PORTFOLIO_PHOTO':
      return _$createReportRequestTargetTypeEnum_PORTFOLIO_PHOTO;
    case 'MASTER_PROFILE':
      return _$createReportRequestTargetTypeEnum_MASTER_PROFILE;
    case 'SALON_PROFILE':
      return _$createReportRequestTargetTypeEnum_SALON_PROFILE;
    case 'CLIENT_PROFILE':
      return _$createReportRequestTargetTypeEnum_CLIENT_PROFILE;
    case 'unknownDefaultOpenApi':
      return _$createReportRequestTargetTypeEnum_unknownDefaultOpenApi;
    default:
      return _$createReportRequestTargetTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<CreateReportRequestTargetTypeEnum>
    _$createReportRequestTargetTypeEnumValues = BuiltSet<
        CreateReportRequestTargetTypeEnum>(const <CreateReportRequestTargetTypeEnum>[
  _$createReportRequestTargetTypeEnum_REVIEW,
  _$createReportRequestTargetTypeEnum_CLIENT_REVIEW,
  _$createReportRequestTargetTypeEnum_PORTFOLIO_PHOTO,
  _$createReportRequestTargetTypeEnum_MASTER_PROFILE,
  _$createReportRequestTargetTypeEnum_SALON_PROFILE,
  _$createReportRequestTargetTypeEnum_CLIENT_PROFILE,
  _$createReportRequestTargetTypeEnum_unknownDefaultOpenApi,
]);

const CreateReportRequestReasonEnum _$createReportRequestReasonEnum_SPAM =
    const CreateReportRequestReasonEnum._('SPAM');
const CreateReportRequestReasonEnum _$createReportRequestReasonEnum_OFFENSIVE =
    const CreateReportRequestReasonEnum._('OFFENSIVE');
const CreateReportRequestReasonEnum _$createReportRequestReasonEnum_HARASSMENT =
    const CreateReportRequestReasonEnum._('HARASSMENT');
const CreateReportRequestReasonEnum _$createReportRequestReasonEnum_FALSE_INFO =
    const CreateReportRequestReasonEnum._('FALSE_INFO');
const CreateReportRequestReasonEnum
    _$createReportRequestReasonEnum_SEXUAL_CONTENT =
    const CreateReportRequestReasonEnum._('SEXUAL_CONTENT');
const CreateReportRequestReasonEnum _$createReportRequestReasonEnum_OTHER =
    const CreateReportRequestReasonEnum._('OTHER');
const CreateReportRequestReasonEnum
    _$createReportRequestReasonEnum_unknownDefaultOpenApi =
    const CreateReportRequestReasonEnum._('unknownDefaultOpenApi');

CreateReportRequestReasonEnum _$createReportRequestReasonEnumValueOf(
    String name) {
  switch (name) {
    case 'SPAM':
      return _$createReportRequestReasonEnum_SPAM;
    case 'OFFENSIVE':
      return _$createReportRequestReasonEnum_OFFENSIVE;
    case 'HARASSMENT':
      return _$createReportRequestReasonEnum_HARASSMENT;
    case 'FALSE_INFO':
      return _$createReportRequestReasonEnum_FALSE_INFO;
    case 'SEXUAL_CONTENT':
      return _$createReportRequestReasonEnum_SEXUAL_CONTENT;
    case 'OTHER':
      return _$createReportRequestReasonEnum_OTHER;
    case 'unknownDefaultOpenApi':
      return _$createReportRequestReasonEnum_unknownDefaultOpenApi;
    default:
      return _$createReportRequestReasonEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<CreateReportRequestReasonEnum>
    _$createReportRequestReasonEnumValues = BuiltSet<
        CreateReportRequestReasonEnum>(const <CreateReportRequestReasonEnum>[
  _$createReportRequestReasonEnum_SPAM,
  _$createReportRequestReasonEnum_OFFENSIVE,
  _$createReportRequestReasonEnum_HARASSMENT,
  _$createReportRequestReasonEnum_FALSE_INFO,
  _$createReportRequestReasonEnum_SEXUAL_CONTENT,
  _$createReportRequestReasonEnum_OTHER,
  _$createReportRequestReasonEnum_unknownDefaultOpenApi,
]);

Serializer<CreateReportRequestTargetTypeEnum>
    _$createReportRequestTargetTypeEnumSerializer =
    _$CreateReportRequestTargetTypeEnumSerializer();
Serializer<CreateReportRequestReasonEnum>
    _$createReportRequestReasonEnumSerializer =
    _$CreateReportRequestReasonEnumSerializer();

class _$CreateReportRequestTargetTypeEnumSerializer
    implements PrimitiveSerializer<CreateReportRequestTargetTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'REVIEW': 'REVIEW',
    'CLIENT_REVIEW': 'CLIENT_REVIEW',
    'PORTFOLIO_PHOTO': 'PORTFOLIO_PHOTO',
    'MASTER_PROFILE': 'MASTER_PROFILE',
    'SALON_PROFILE': 'SALON_PROFILE',
    'CLIENT_PROFILE': 'CLIENT_PROFILE',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'REVIEW': 'REVIEW',
    'CLIENT_REVIEW': 'CLIENT_REVIEW',
    'PORTFOLIO_PHOTO': 'PORTFOLIO_PHOTO',
    'MASTER_PROFILE': 'MASTER_PROFILE',
    'SALON_PROFILE': 'SALON_PROFILE',
    'CLIENT_PROFILE': 'CLIENT_PROFILE',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[CreateReportRequestTargetTypeEnum];
  @override
  final String wireName = 'CreateReportRequestTargetTypeEnum';

  @override
  Object serialize(
          Serializers serializers, CreateReportRequestTargetTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CreateReportRequestTargetTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CreateReportRequestTargetTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CreateReportRequestReasonEnumSerializer
    implements PrimitiveSerializer<CreateReportRequestReasonEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'SPAM': 'SPAM',
    'OFFENSIVE': 'OFFENSIVE',
    'HARASSMENT': 'HARASSMENT',
    'FALSE_INFO': 'FALSE_INFO',
    'SEXUAL_CONTENT': 'SEXUAL_CONTENT',
    'OTHER': 'OTHER',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'SPAM': 'SPAM',
    'OFFENSIVE': 'OFFENSIVE',
    'HARASSMENT': 'HARASSMENT',
    'FALSE_INFO': 'FALSE_INFO',
    'SEXUAL_CONTENT': 'SEXUAL_CONTENT',
    'OTHER': 'OTHER',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[CreateReportRequestReasonEnum];
  @override
  final String wireName = 'CreateReportRequestReasonEnum';

  @override
  Object serialize(
          Serializers serializers, CreateReportRequestReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CreateReportRequestReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CreateReportRequestReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CreateReportRequest extends CreateReportRequest {
  @override
  final CreateReportRequestTargetTypeEnum targetType;
  @override
  final String targetId;
  @override
  final CreateReportRequestReasonEnum reason;
  @override
  final String? comment;

  factory _$CreateReportRequest(
          [void Function(CreateReportRequestBuilder)? updates]) =>
      (CreateReportRequestBuilder()..update(updates))._build();

  _$CreateReportRequest._(
      {required this.targetType,
      required this.targetId,
      required this.reason,
      this.comment})
      : super._();
  @override
  CreateReportRequest rebuild(
          void Function(CreateReportRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateReportRequestBuilder toBuilder() =>
      CreateReportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateReportRequest &&
        targetType == other.targetType &&
        targetId == other.targetId &&
        reason == other.reason &&
        comment == other.comment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, targetType.hashCode);
    _$hash = $jc(_$hash, targetId.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateReportRequest')
          ..add('targetType', targetType)
          ..add('targetId', targetId)
          ..add('reason', reason)
          ..add('comment', comment))
        .toString();
  }
}

class CreateReportRequestBuilder
    implements Builder<CreateReportRequest, CreateReportRequestBuilder> {
  _$CreateReportRequest? _$v;

  CreateReportRequestTargetTypeEnum? _targetType;
  CreateReportRequestTargetTypeEnum? get targetType => _$this._targetType;
  set targetType(CreateReportRequestTargetTypeEnum? targetType) =>
      _$this._targetType = targetType;

  String? _targetId;
  String? get targetId => _$this._targetId;
  set targetId(String? targetId) => _$this._targetId = targetId;

  CreateReportRequestReasonEnum? _reason;
  CreateReportRequestReasonEnum? get reason => _$this._reason;
  set reason(CreateReportRequestReasonEnum? reason) => _$this._reason = reason;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  CreateReportRequestBuilder() {
    CreateReportRequest._defaults(this);
  }

  CreateReportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _targetType = $v.targetType;
      _targetId = $v.targetId;
      _reason = $v.reason;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateReportRequest other) {
    _$v = other as _$CreateReportRequest;
  }

  @override
  void update(void Function(CreateReportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateReportRequest build() => _build();

  _$CreateReportRequest _build() {
    final _$result = _$v ??
        _$CreateReportRequest._(
          targetType: BuiltValueNullFieldError.checkNotNull(
              targetType, r'CreateReportRequest', 'targetType'),
          targetId: BuiltValueNullFieldError.checkNotNull(
              targetId, r'CreateReportRequest', 'targetId'),
          reason: BuiltValueNullFieldError.checkNotNull(
              reason, r'CreateReportRequest', 'reason'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
