// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cancel_booking_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnum_CLIENT_NO_SHOW =
    const CancelBookingRequestCancellationReasonEnum._('CLIENT_NO_SHOW');
const CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnum_CLIENT_CANCELLED =
    const CancelBookingRequestCancellationReasonEnum._('CLIENT_CANCELLED');
const CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE =
    const CancelBookingRequestCancellationReasonEnum._('PROVIDER_UNAVAILABLE');
const CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnum_DUPLICATE =
    const CancelBookingRequestCancellationReasonEnum._('DUPLICATE');
const CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnum_OTHER =
    const CancelBookingRequestCancellationReasonEnum._('OTHER');

CancelBookingRequestCancellationReasonEnum
    _$cancelBookingRequestCancellationReasonEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT_NO_SHOW':
      return _$cancelBookingRequestCancellationReasonEnum_CLIENT_NO_SHOW;
    case 'CLIENT_CANCELLED':
      return _$cancelBookingRequestCancellationReasonEnum_CLIENT_CANCELLED;
    case 'PROVIDER_UNAVAILABLE':
      return _$cancelBookingRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE;
    case 'DUPLICATE':
      return _$cancelBookingRequestCancellationReasonEnum_DUPLICATE;
    case 'OTHER':
      return _$cancelBookingRequestCancellationReasonEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CancelBookingRequestCancellationReasonEnum>
    _$cancelBookingRequestCancellationReasonEnumValues = BuiltSet<
        CancelBookingRequestCancellationReasonEnum>(const <CancelBookingRequestCancellationReasonEnum>[
  _$cancelBookingRequestCancellationReasonEnum_CLIENT_NO_SHOW,
  _$cancelBookingRequestCancellationReasonEnum_CLIENT_CANCELLED,
  _$cancelBookingRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE,
  _$cancelBookingRequestCancellationReasonEnum_DUPLICATE,
  _$cancelBookingRequestCancellationReasonEnum_OTHER,
]);

Serializer<CancelBookingRequestCancellationReasonEnum>
    _$cancelBookingRequestCancellationReasonEnumSerializer =
    _$CancelBookingRequestCancellationReasonEnumSerializer();

class _$CancelBookingRequestCancellationReasonEnumSerializer
    implements PrimitiveSerializer<CancelBookingRequestCancellationReasonEnum> {
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
    CancelBookingRequestCancellationReasonEnum
  ];
  @override
  final String wireName = 'CancelBookingRequestCancellationReasonEnum';

  @override
  Object serialize(Serializers serializers,
          CancelBookingRequestCancellationReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CancelBookingRequestCancellationReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CancelBookingRequestCancellationReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CancelBookingRequest extends CancelBookingRequest {
  @override
  final CancelBookingRequestCancellationReasonEnum cancellationReason;
  @override
  final String? comment;

  factory _$CancelBookingRequest(
          [void Function(CancelBookingRequestBuilder)? updates]) =>
      (CancelBookingRequestBuilder()..update(updates))._build();

  _$CancelBookingRequest._({required this.cancellationReason, this.comment})
      : super._();
  @override
  CancelBookingRequest rebuild(
          void Function(CancelBookingRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CancelBookingRequestBuilder toBuilder() =>
      CancelBookingRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CancelBookingRequest &&
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
    return (newBuiltValueToStringHelper(r'CancelBookingRequest')
          ..add('cancellationReason', cancellationReason)
          ..add('comment', comment))
        .toString();
  }
}

class CancelBookingRequestBuilder
    implements Builder<CancelBookingRequest, CancelBookingRequestBuilder> {
  _$CancelBookingRequest? _$v;

  CancelBookingRequestCancellationReasonEnum? _cancellationReason;
  CancelBookingRequestCancellationReasonEnum? get cancellationReason =>
      _$this._cancellationReason;
  set cancellationReason(
          CancelBookingRequestCancellationReasonEnum? cancellationReason) =>
      _$this._cancellationReason = cancellationReason;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  CancelBookingRequestBuilder() {
    CancelBookingRequest._defaults(this);
  }

  CancelBookingRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cancellationReason = $v.cancellationReason;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CancelBookingRequest other) {
    _$v = other as _$CancelBookingRequest;
  }

  @override
  void update(void Function(CancelBookingRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CancelBookingRequest build() => _build();

  _$CancelBookingRequest _build() {
    final _$result = _$v ??
        _$CancelBookingRequest._(
          cancellationReason: BuiltValueNullFieldError.checkNotNull(
              cancellationReason,
              r'CancelBookingRequest',
              'cancellationReason'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
