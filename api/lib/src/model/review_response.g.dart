// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReviewResponseSource_Enum _$reviewResponseSourceEnum_APP =
    const ReviewResponseSource_Enum._('APP');
const ReviewResponseSource_Enum _$reviewResponseSourceEnum_GUEST_LINK =
    const ReviewResponseSource_Enum._('GUEST_LINK');
const ReviewResponseSource_Enum
    _$reviewResponseSourceEnum_unknownDefaultOpenApi =
    const ReviewResponseSource_Enum._('unknownDefaultOpenApi');

ReviewResponseSource_Enum _$reviewResponseSourceEnumValueOf(String name) {
  switch (name) {
    case 'APP':
      return _$reviewResponseSourceEnum_APP;
    case 'GUEST_LINK':
      return _$reviewResponseSourceEnum_GUEST_LINK;
    case 'unknownDefaultOpenApi':
      return _$reviewResponseSourceEnum_unknownDefaultOpenApi;
    default:
      return _$reviewResponseSourceEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ReviewResponseSource_Enum> _$reviewResponseSourceEnumValues =
    BuiltSet<ReviewResponseSource_Enum>(const <ReviewResponseSource_Enum>[
  _$reviewResponseSourceEnum_APP,
  _$reviewResponseSourceEnum_GUEST_LINK,
  _$reviewResponseSourceEnum_unknownDefaultOpenApi,
]);

Serializer<ReviewResponseSource_Enum> _$reviewResponseSourceEnumSerializer =
    _$ReviewResponseSource_EnumSerializer();

class _$ReviewResponseSource_EnumSerializer
    implements PrimitiveSerializer<ReviewResponseSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'APP': 'APP',
    'GUEST_LINK': 'GUEST_LINK',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'APP': 'APP',
    'GUEST_LINK': 'GUEST_LINK',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ReviewResponseSource_Enum];
  @override
  final String wireName = 'ReviewResponseSource_Enum';

  @override
  Object serialize(Serializers serializers, ReviewResponseSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReviewResponseSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReviewResponseSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ReviewResponse extends ReviewResponse {
  @override
  final String? id;
  @override
  final String? masterId;
  @override
  final String? clientDisplayName;
  @override
  final String? serviceName;
  @override
  final int? rating;
  @override
  final String? comment;
  @override
  final DateTime? createdAt;
  @override
  final bool? authoredByViewer;
  @override
  final ReviewResponseSource_Enum? source_;

  factory _$ReviewResponse([void Function(ReviewResponseBuilder)? updates]) =>
      (ReviewResponseBuilder()..update(updates))._build();

  _$ReviewResponse._(
      {this.id,
      this.masterId,
      this.clientDisplayName,
      this.serviceName,
      this.rating,
      this.comment,
      this.createdAt,
      this.authoredByViewer,
      this.source_})
      : super._();
  @override
  ReviewResponse rebuild(void Function(ReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewResponseBuilder toBuilder() => ReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewResponse &&
        id == other.id &&
        masterId == other.masterId &&
        clientDisplayName == other.clientDisplayName &&
        serviceName == other.serviceName &&
        rating == other.rating &&
        comment == other.comment &&
        createdAt == other.createdAt &&
        authoredByViewer == other.authoredByViewer &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, clientDisplayName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, authoredByViewer.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewResponse')
          ..add('id', id)
          ..add('masterId', masterId)
          ..add('clientDisplayName', clientDisplayName)
          ..add('serviceName', serviceName)
          ..add('rating', rating)
          ..add('comment', comment)
          ..add('createdAt', createdAt)
          ..add('authoredByViewer', authoredByViewer)
          ..add('source_', source_))
        .toString();
  }
}

class ReviewResponseBuilder
    implements Builder<ReviewResponse, ReviewResponseBuilder> {
  _$ReviewResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _clientDisplayName;
  String? get clientDisplayName => _$this._clientDisplayName;
  set clientDisplayName(String? clientDisplayName) =>
      _$this._clientDisplayName = clientDisplayName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  bool? _authoredByViewer;
  bool? get authoredByViewer => _$this._authoredByViewer;
  set authoredByViewer(bool? authoredByViewer) =>
      _$this._authoredByViewer = authoredByViewer;

  ReviewResponseSource_Enum? _source_;
  ReviewResponseSource_Enum? get source_ => _$this._source_;
  set source_(ReviewResponseSource_Enum? source_) => _$this._source_ = source_;

  ReviewResponseBuilder() {
    ReviewResponse._defaults(this);
  }

  ReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _masterId = $v.masterId;
      _clientDisplayName = $v.clientDisplayName;
      _serviceName = $v.serviceName;
      _rating = $v.rating;
      _comment = $v.comment;
      _createdAt = $v.createdAt;
      _authoredByViewer = $v.authoredByViewer;
      _source_ = $v.source_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewResponse other) {
    _$v = other as _$ReviewResponse;
  }

  @override
  void update(void Function(ReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewResponse build() => _build();

  _$ReviewResponse _build() {
    final _$result = _$v ??
        _$ReviewResponse._(
          id: id,
          masterId: masterId,
          clientDisplayName: clientDisplayName,
          serviceName: serviceName,
          rating: rating,
          comment: comment,
          createdAt: createdAt,
          authoredByViewer: authoredByViewer,
          source_: source_,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
