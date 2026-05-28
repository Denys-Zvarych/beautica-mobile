// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_update_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnum_CLIENT_NO_SHOW =
    const StatusUpdateRequestCancellationReasonEnum._('CLIENT_NO_SHOW');
const StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnum_CLIENT_CANCELLED =
    const StatusUpdateRequestCancellationReasonEnum._('CLIENT_CANCELLED');
const StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE =
    const StatusUpdateRequestCancellationReasonEnum._('PROVIDER_UNAVAILABLE');
const StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnum_DUPLICATE =
    const StatusUpdateRequestCancellationReasonEnum._('DUPLICATE');
const StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnum_OTHER =
    const StatusUpdateRequestCancellationReasonEnum._('OTHER');

StatusUpdateRequestCancellationReasonEnum
    _$statusUpdateRequestCancellationReasonEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT_NO_SHOW':
      return _$statusUpdateRequestCancellationReasonEnum_CLIENT_NO_SHOW;
    case 'CLIENT_CANCELLED':
      return _$statusUpdateRequestCancellationReasonEnum_CLIENT_CANCELLED;
    case 'PROVIDER_UNAVAILABLE':
      return _$statusUpdateRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE;
    case 'DUPLICATE':
      return _$statusUpdateRequestCancellationReasonEnum_DUPLICATE;
    case 'OTHER':
      return _$statusUpdateRequestCancellationReasonEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<StatusUpdateRequestCancellationReasonEnum>
    _$statusUpdateRequestCancellationReasonEnumValues = BuiltSet<
        StatusUpdateRequestCancellationReasonEnum>(const <StatusUpdateRequestCancellationReasonEnum>[
  _$statusUpdateRequestCancellationReasonEnum_CLIENT_NO_SHOW,
  _$statusUpdateRequestCancellationReasonEnum_CLIENT_CANCELLED,
  _$statusUpdateRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE,
  _$statusUpdateRequestCancellationReasonEnum_DUPLICATE,
  _$statusUpdateRequestCancellationReasonEnum_OTHER,
]);

Serializer<StatusUpdateRequestCancellationReasonEnum>
    _$statusUpdateRequestCancellationReasonEnumSerializer =
    _$StatusUpdateRequestCancellationReasonEnumSerializer();

class _$StatusUpdateRequestCancellationReasonEnumSerializer
    implements PrimitiveSerializer<StatusUpdateRequestCancellationReasonEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT_NO_SHOW': 'CLIENT_NO_SHOW',
    'CLIENT_CANCELLED': 'CLIENT_CANCELLED',
    'PROVIDER_UNAVAILABLE': 'PROVIDER_UNAVAILABLE',
    'DUPLICATE': 'DUPLICATE',
    'OTHER': 'OTHER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT_NO_SHOW': 'CLIENT_NO_SHOW',
    'CLIENT_CANCELLED': 'CLIENT_CANCELLED',
    'PROVIDER_UNAVAILABLE': 'PROVIDER_UNAVAILABLE',
    'DUPLICATE': 'DUPLICATE',
    'OTHER': 'OTHER',
  };

  @override
  final Iterable<Type> types = const <Type>[
    StatusUpdateRequestCancellationReasonEnum
  ];
  @override
  final String wireName = 'StatusUpdateRequestCancellationReasonEnum';

  @override
  Object serialize(Serializers serializers,
          StatusUpdateRequestCancellationReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  StatusUpdateRequestCancellationReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      StatusUpdateRequestCancellationReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$StatusUpdateRequest extends StatusUpdateRequest {
  @override
  final StatusUpdateRequestCancellationReasonEnum? cancellationReason;
  @override
  final String? comment;

  factory _$StatusUpdateRequest(
          [void Function(StatusUpdateRequestBuilder)? updates]) =>
      (StatusUpdateRequestBuilder()..update(updates))._build();

  _$StatusUpdateRequest._({this.cancellationReason, this.comment}) : super._();
  @override
  StatusUpdateRequest rebuild(
          void Function(StatusUpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StatusUpdateRequestBuilder toBuilder() =>
      StatusUpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StatusUpdateRequest &&
        cancellationReason == other.cancellationReason &&
        comment == other.comment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cancellationReason.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StatusUpdateRequest')
          ..add('cancellationReason', cancellationReason)
          ..add('comment', comment))
        .toString();
  }
}

class StatusUpdateRequestBuilder
    implements Builder<StatusUpdateRequest, StatusUpdateRequestBuilder> {
  _$StatusUpdateRequest? _$v;

  StatusUpdateRequestCancellationReasonEnum? _cancellationReason;
  StatusUpdateRequestCancellationReasonEnum? get cancellationReason =>
      _$this._cancellationReason;
  set cancellationReason(
          StatusUpdateRequestCancellationReasonEnum? cancellationReason) =>
      _$this._cancellationReason = cancellationReason;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  StatusUpdateRequestBuilder() {
    StatusUpdateRequest._defaults(this);
  }

  StatusUpdateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cancellationReason = $v.cancellationReason;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StatusUpdateRequest other) {
    _$v = other as _$StatusUpdateRequest;
  }

  @override
  void update(void Function(StatusUpdateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StatusUpdateRequest build() => _build();

  _$StatusUpdateRequest _build() {
    final _$result = _$v ??
        _$StatusUpdateRequest._(
          cancellationReason: cancellationReason,
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
