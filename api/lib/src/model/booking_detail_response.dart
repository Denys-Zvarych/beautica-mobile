//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_detail_response.g.dart';

/// BookingDetailResponse
///
/// Properties:
/// * [id]
/// * [clientId]
/// * [masterId]
/// * [masterServiceId]
/// * [serviceName]
/// * [status]
/// * [startsAt]
/// * [endsAt]
/// * [priceAtBooking]
/// * [priceMaxAtBooking] - The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once.
/// * [durationMinutesAtBooking]
/// * [createdAt]
/// * [clientFirstName]
/// * [clientLastName]
/// * [masterFirstName]
/// * [masterLastName]
/// * [masterProfessionalTitle] - The master's professional title/headline (e.g. \"Перукар-стиліст\"), same field as MasterSummaryResponse/MasterDetailResponse. Nullable — a master may never have set one.
/// * [clientComment] - The client's booking-creation note (written once at POST /bookings). Visible to the provider. Distinct from clientCancellationNote below — this is NOT the cancellation reason.
/// * [providerComment] - Written by the provider on /decline or /not-complete. Visible to the CLIENT on both DECLINED and NOT_COMPLETED bookings — intentional, by locked product decision (\"all notes visible for all sides\"), NOT a privacy leak. Do not suppress this for any audience.
/// * [clientCancellationNote] - Written by the CLIENT on /cancel. Visible to the provider — the symmetric counterpart of providerComment. Only ever non-null on a CANCELLED booking.
/// * [masterAvatarUrl]
/// * [masterType]
/// * [salonName]
/// * [cityLabel]
/// * [districtLabel]
/// * [street]
/// * [buildingNo]
/// * [locationNote] - The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo, against the salon THIS BOOKING was made at (bookings.salon_id): a salon booking surfaces that salon's own note — never the master's current salon's, should the master have moved since — and an independent-master booking surfaces the master's own note. Nullable — most providers never set one.
/// * [categoryName]
/// * [canReview]
/// * [providerCanReviewClient] - TRUE only for the CURRENT authenticated viewer, and only on GET /bookings/{id}: the viewer has provider review-authority over this booking, the booking is COMPLETED (strictly — unlike the client-side canReview flag, an elapsed-but-unclosed CONFIRMED booking does NOT qualify here; see BookingClosureRule#isProviderReviewEligible), it has a real (non-guest) client, and no ClientReview exists for it yet. FALSE for a CLIENT/SALON_MASTER viewer, an unauthorized provider, or any row served by GET /bookings/me (both the CLIENT and provider listing paths hardcode false — see BookingDetailResponse's class javadoc). Gates the \"Залишити відгук про клієнта\" CTA; the write endpoint (POST /client-reviews) re-checks the same conditions server-side regardless of this value.
/// * [appointmentId] - The multi-service visit (BE-5) this booking belongs to, or null for a legacy single-service booking (appointment_id IS NULL). Strictly additive; when non-null the client can fetch the full visit via GET /appointments/{appointmentId}. Both mapper paths (entity + CLIENT projection) read the SAME appointment_id column, so they never diverge.
/// * [clientAvatarUrl] - The booking client's profile photo — the same already-public Cloudflare R2 object URL served by masterAvatarUrl and every other avatar field in this API (never a signed URL, never a raw storage key). Lets a provider timeline render the client's photo instead of a generic glyph. NULL in two cases, both of which must render the fallback glyph: (1) a guest (LINK) booking, which has no registered account at all (client_id IS NULL, V89 chk_bookings_guest_fields) and therefore no photo and no fallback — unlike clientFirstName/clientLastName, which do fall back to the OTP-verified guest name; (2) a registered client who has never uploaded one. Do not distinguish the two client-side. Both causes mean strictly 'this booking has no client photo' — NULL here never encodes who is asking. The value depends only on the booking, so the same booking yields the same value on GET /bookings/{id} and on every row of GET /bookings/me, for a provider and for the client themselves alike; a client reading their own booking sees their own photo. Safe to cache by booking id across both endpoints.
/// * [awaitingClosure] - Derived, read-time-only (Phase 29.1/29.2) — TRUE when this booking's status is still CONFIRMED but its endsAt has already elapsed: no scheduled job ever transitions such a booking to a terminal state, so this flags the ones the provider still needs to close via /complete, /not-complete or /decline. NEVER persisted, NEVER cached — recomputed on every read from (status, endsAt, the current instant). NOT orthogonal to canReview since the review-eligibility widening: an elapsed-but-unclosed CONFIRMED booking reads TRUE here AND (when it has a registered client and no existing review) TRUE for canReview too — closure-awaiting and review-eligible now deliberately overlap for exactly this row shape, by locked product decision (a booking that entered the client's Past tab by elapsed time is reviewable even before the provider closes it — see BookingClosureRule#isReviewEligible). The same for every row of GET /bookings/me and for GET /bookings/{id} — a pure function of the booking, not of the viewer.
/// * [masterAvgRating] - The master's public average rating, 1.00-5.00, read off the denormalized masters.avg_rating column — the SAME value served by GET /masters/{id} and GET /masters/{id}/reviews/summary, never independently re-aggregated. Agreement across those three endpoints is exact, not eventual: GET /masters/{id} is served from the 5-minute 'master-detail' cache, and ReviewEventListener#onReviewCreated evicts that entry by masterId once the rating recalculation commits, so a client that leaves a review sees the new average on the booking AND on the profile on the very next request. NULL when masterReviewCount is 0: the column stores 0.00 for an unreviewed master (V4 NOT NULL DEFAULT 0.00, and recalculateMasterRating's COALESCE(AVG(...), 0)), which is a storage artefact, not a rating — rendering it would show a brand-new master a damning zero stars. Render the 'no reviews yet' state when null; never substitute 0.
/// * [masterReviewCount] - How many reviews the master's average is computed from. 0 for an unreviewed master (a true fact, unlike a 0.00 average) and non-null on every path that serves this DTO today; typed nullable so a client treats an absent value as 'unknown' rather than 'zero reviews'.
/// * [salonId] - The salon this booking was made AT, as snapshotted on the booking row (bookings.salon_id). NULL for an INDEPENDENT_MASTER booking. Exists so a client can invalidate its own salon-scoped caches after leaving a review: ReviewService#createReview stamps the review with booking.getSalon() and ReviewEventListener recalculates THAT salon's avg_rating/review_count, so this is the id whose aggregates moved. As of phase 242 salonName and the street/buildingNo/locationNote/cityLabel/districtLabel block are resolved from this SAME booking snapshot, so salonId != null and salonName != null are one predicate and the id always identifies the premises whose address is displayed alongside it. (Before 242 the address block came from the master's LIVE salon and the two could disagree after a rotation — that divergence is gone.)
@BuiltValue()
abstract class BookingDetailResponse
    implements Built<BookingDetailResponse, BookingDetailResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'clientId')
  String? get clientId;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterServiceId')
  String? get masterServiceId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'status')
  BookingDetailResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  @BuiltValueField(wireName: r'priceAtBooking')
  num? get priceAtBooking;

  /// The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once.
  @BuiltValueField(wireName: r'priceMaxAtBooking')
  num? get priceMaxAtBooking;

  @BuiltValueField(wireName: r'durationMinutesAtBooking')
  int? get durationMinutesAtBooking;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'clientFirstName')
  String? get clientFirstName;

  @BuiltValueField(wireName: r'clientLastName')
  String? get clientLastName;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  /// The master's professional title/headline (e.g. \"Перукар-стиліст\"), same field as MasterSummaryResponse/MasterDetailResponse. Nullable — a master may never have set one.
  @BuiltValueField(wireName: r'masterProfessionalTitle')
  String? get masterProfessionalTitle;

  /// The client's booking-creation note (written once at POST /bookings). Visible to the provider. Distinct from clientCancellationNote below — this is NOT the cancellation reason.
  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  /// Written by the provider on /decline or /not-complete. Visible to the CLIENT on both DECLINED and NOT_COMPLETED bookings — intentional, by locked product decision (\"all notes visible for all sides\"), NOT a privacy leak. Do not suppress this for any audience.
  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  /// Written by the CLIENT on /cancel. Visible to the provider — the symmetric counterpart of providerComment. Only ever non-null on a CANCELLED booking.
  @BuiltValueField(wireName: r'clientCancellationNote')
  String? get clientCancellationNote;

  @BuiltValueField(wireName: r'masterAvatarUrl')
  String? get masterAvatarUrl;

  @BuiltValueField(wireName: r'masterType')
  BookingDetailResponseMasterTypeEnum? get masterType;
  // enum masterTypeEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  @BuiltValueField(wireName: r'cityLabel')
  String? get cityLabel;

  @BuiltValueField(wireName: r'districtLabel')
  String? get districtLabel;

  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  /// The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo, against the salon THIS BOOKING was made at (bookings.salon_id): a salon booking surfaces that salon's own note — never the master's current salon's, should the master have moved since — and an independent-master booking surfaces the master's own note. Nullable — most providers never set one.
  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  @BuiltValueField(wireName: r'categoryName')
  String? get categoryName;

  @BuiltValueField(wireName: r'canReview')
  bool? get canReview;

  /// TRUE only for the CURRENT authenticated viewer, and only on GET /bookings/{id}: the viewer has provider review-authority over this booking, the booking is COMPLETED (strictly — unlike the client-side canReview flag, an elapsed-but-unclosed CONFIRMED booking does NOT qualify here; see BookingClosureRule#isProviderReviewEligible), it has a real (non-guest) client, and no ClientReview exists for it yet. FALSE for a CLIENT/SALON_MASTER viewer, an unauthorized provider, or any row served by GET /bookings/me (both the CLIENT and provider listing paths hardcode false — see BookingDetailResponse's class javadoc). Gates the \"Залишити відгук про клієнта\" CTA; the write endpoint (POST /client-reviews) re-checks the same conditions server-side regardless of this value.
  @BuiltValueField(wireName: r'providerCanReviewClient')
  bool? get providerCanReviewClient;

  /// The multi-service visit (BE-5) this booking belongs to, or null for a legacy single-service booking (appointment_id IS NULL). Strictly additive; when non-null the client can fetch the full visit via GET /appointments/{appointmentId}. Both mapper paths (entity + CLIENT projection) read the SAME appointment_id column, so they never diverge.
  @BuiltValueField(wireName: r'appointmentId')
  String? get appointmentId;

  /// The booking client's profile photo — the same already-public Cloudflare R2 object URL served by masterAvatarUrl and every other avatar field in this API (never a signed URL, never a raw storage key). Lets a provider timeline render the client's photo instead of a generic glyph. NULL in two cases, both of which must render the fallback glyph: (1) a guest (LINK) booking, which has no registered account at all (client_id IS NULL, V89 chk_bookings_guest_fields) and therefore no photo and no fallback — unlike clientFirstName/clientLastName, which do fall back to the OTP-verified guest name; (2) a registered client who has never uploaded one. Do not distinguish the two client-side. Both causes mean strictly 'this booking has no client photo' — NULL here never encodes who is asking. The value depends only on the booking, so the same booking yields the same value on GET /bookings/{id} and on every row of GET /bookings/me, for a provider and for the client themselves alike; a client reading their own booking sees their own photo. Safe to cache by booking id across both endpoints.
  @BuiltValueField(wireName: r'clientAvatarUrl')
  String? get clientAvatarUrl;

  /// Derived, read-time-only (Phase 29.1/29.2) — TRUE when this booking's status is still CONFIRMED but its endsAt has already elapsed: no scheduled job ever transitions such a booking to a terminal state, so this flags the ones the provider still needs to close via /complete, /not-complete or /decline. NEVER persisted, NEVER cached — recomputed on every read from (status, endsAt, the current instant). NOT orthogonal to canReview since the review-eligibility widening: an elapsed-but-unclosed CONFIRMED booking reads TRUE here AND (when it has a registered client and no existing review) TRUE for canReview too — closure-awaiting and review-eligible now deliberately overlap for exactly this row shape, by locked product decision (a booking that entered the client's Past tab by elapsed time is reviewable even before the provider closes it — see BookingClosureRule#isReviewEligible). The same for every row of GET /bookings/me and for GET /bookings/{id} — a pure function of the booking, not of the viewer.
  @BuiltValueField(wireName: r'awaitingClosure')
  bool? get awaitingClosure;

  /// The master's public average rating, 1.00-5.00, read off the denormalized masters.avg_rating column — the SAME value served by GET /masters/{id} and GET /masters/{id}/reviews/summary, never independently re-aggregated. Agreement across those three endpoints is exact, not eventual: GET /masters/{id} is served from the 5-minute 'master-detail' cache, and ReviewEventListener#onReviewCreated evicts that entry by masterId once the rating recalculation commits, so a client that leaves a review sees the new average on the booking AND on the profile on the very next request. NULL when masterReviewCount is 0: the column stores 0.00 for an unreviewed master (V4 NOT NULL DEFAULT 0.00, and recalculateMasterRating's COALESCE(AVG(...), 0)), which is a storage artefact, not a rating — rendering it would show a brand-new master a damning zero stars. Render the 'no reviews yet' state when null; never substitute 0.
  @BuiltValueField(wireName: r'masterAvgRating')
  num? get masterAvgRating;

  /// How many reviews the master's average is computed from. 0 for an unreviewed master (a true fact, unlike a 0.00 average) and non-null on every path that serves this DTO today; typed nullable so a client treats an absent value as 'unknown' rather than 'zero reviews'.
  @BuiltValueField(wireName: r'masterReviewCount')
  int? get masterReviewCount;

  /// The salon this booking was made AT, as snapshotted on the booking row (bookings.salon_id). NULL for an INDEPENDENT_MASTER booking. Exists so a client can invalidate its own salon-scoped caches after leaving a review: ReviewService#createReview stamps the review with booking.getSalon() and ReviewEventListener recalculates THAT salon's avg_rating/review_count, so this is the id whose aggregates moved. As of phase 242 salonName and the street/buildingNo/locationNote/cityLabel/districtLabel block are resolved from this SAME booking snapshot, so salonId != null and salonName != null are one predicate and the id always identifies the premises whose address is displayed alongside it. (Before 242 the address block came from the master's LIVE salon and the two could disagree after a rotation — that divergence is gone.)
  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  BookingDetailResponse._();

  factory BookingDetailResponse(
      [void updates(BookingDetailResponseBuilder b)]) = _$BookingDetailResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingDetailResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingDetailResponse> get serializer =>
      _$BookingDetailResponseSerializer();
}

class _$BookingDetailResponseSerializer
    implements PrimitiveSerializer<BookingDetailResponse> {
  @override
  final Iterable<Type> types = const [
    BookingDetailResponse,
    _$BookingDetailResponse
  ];

  @override
  final String wireName = r'BookingDetailResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingDetailResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientId != null) {
      yield r'clientId';
      yield serializers.serialize(
        object.clientId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterServiceId != null) {
      yield r'masterServiceId';
      yield serializers.serialize(
        object.masterServiceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(BookingDetailResponseStatusEnum),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.endsAt != null) {
      yield r'endsAt';
      yield serializers.serialize(
        object.endsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.priceAtBooking != null) {
      yield r'priceAtBooking';
      yield serializers.serialize(
        object.priceAtBooking,
        specifiedType: const FullType(num),
      );
    }
    if (object.priceMaxAtBooking != null) {
      yield r'priceMaxAtBooking';
      yield serializers.serialize(
        object.priceMaxAtBooking,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.durationMinutesAtBooking != null) {
      yield r'durationMinutesAtBooking';
      yield serializers.serialize(
        object.durationMinutesAtBooking,
        specifiedType: const FullType(int),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.clientFirstName != null) {
      yield r'clientFirstName';
      yield serializers.serialize(
        object.clientFirstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientLastName != null) {
      yield r'clientLastName';
      yield serializers.serialize(
        object.clientLastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterFirstName != null) {
      yield r'masterFirstName';
      yield serializers.serialize(
        object.masterFirstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterLastName != null) {
      yield r'masterLastName';
      yield serializers.serialize(
        object.masterLastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterProfessionalTitle != null) {
      yield r'masterProfessionalTitle';
      yield serializers.serialize(
        object.masterProfessionalTitle,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clientComment != null) {
      yield r'clientComment';
      yield serializers.serialize(
        object.clientComment,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.providerComment != null) {
      yield r'providerComment';
      yield serializers.serialize(
        object.providerComment,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clientCancellationNote != null) {
      yield r'clientCancellationNote';
      yield serializers.serialize(
        object.clientCancellationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.masterAvatarUrl != null) {
      yield r'masterAvatarUrl';
      yield serializers.serialize(
        object.masterAvatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterType != null) {
      yield r'masterType';
      yield serializers.serialize(
        object.masterType,
        specifiedType: const FullType(BookingDetailResponseMasterTypeEnum),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType(String),
      );
    }
    if (object.cityLabel != null) {
      yield r'cityLabel';
      yield serializers.serialize(
        object.cityLabel,
        specifiedType: const FullType(String),
      );
    }
    if (object.districtLabel != null) {
      yield r'districtLabel';
      yield serializers.serialize(
        object.districtLabel,
        specifiedType: const FullType(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.categoryName != null) {
      yield r'categoryName';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType(String),
      );
    }
    if (object.canReview != null) {
      yield r'canReview';
      yield serializers.serialize(
        object.canReview,
        specifiedType: const FullType(bool),
      );
    }
    if (object.providerCanReviewClient != null) {
      yield r'providerCanReviewClient';
      yield serializers.serialize(
        object.providerCanReviewClient,
        specifiedType: const FullType(bool),
      );
    }
    if (object.appointmentId != null) {
      yield r'appointmentId';
      yield serializers.serialize(
        object.appointmentId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clientAvatarUrl != null) {
      yield r'clientAvatarUrl';
      yield serializers.serialize(
        object.clientAvatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.awaitingClosure != null) {
      yield r'awaitingClosure';
      yield serializers.serialize(
        object.awaitingClosure,
        specifiedType: const FullType(bool),
      );
    }
    if (object.masterAvgRating != null) {
      yield r'masterAvgRating';
      yield serializers.serialize(
        object.masterAvgRating,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.masterReviewCount != null) {
      yield r'masterReviewCount';
      yield serializers.serialize(
        object.masterReviewCount,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingDetailResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookingDetailResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'clientId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientId = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingDetailResponseStatusEnum),
          ) as BookingDetailResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'endsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.endsAt = valueDes;
          break;
        case r'priceAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceAtBooking = valueDes;
          break;
        case r'priceMaxAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.priceMaxAtBooking = valueDes;
          break;
        case r'durationMinutesAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutesAtBooking = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'clientFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientFirstName = valueDes;
          break;
        case r'clientLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientLastName = valueDes;
          break;
        case r'masterFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterFirstName = valueDes;
          break;
        case r'masterLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterLastName = valueDes;
          break;
        case r'masterProfessionalTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterProfessionalTitle = valueDes;
          break;
        case r'clientComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientComment = valueDes;
          break;
        case r'providerComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.providerComment = valueDes;
          break;
        case r'clientCancellationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientCancellationNote = valueDes;
          break;
        case r'masterAvatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterAvatarUrl = valueDes;
          break;
        case r'masterType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingDetailResponseMasterTypeEnum),
          ) as BookingDetailResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonName = valueDes;
          break;
        case r'cityLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityLabel = valueDes;
          break;
        case r'districtLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtLabel = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.buildingNo = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.locationNote = valueDes;
          break;
        case r'categoryName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryName = valueDes;
          break;
        case r'canReview':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.canReview = valueDes;
          break;
        case r'providerCanReviewClient':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.providerCanReviewClient = valueDes;
          break;
        case r'appointmentId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.appointmentId = valueDes;
          break;
        case r'clientAvatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientAvatarUrl = valueDes;
          break;
        case r'awaitingClosure':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.awaitingClosure = valueDes;
          break;
        case r'masterAvgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.masterAvgRating = valueDes;
          break;
        case r'masterReviewCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.masterReviewCount = valueDes;
          break;
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingDetailResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingDetailResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class BookingDetailResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const BookingDetailResponseStatusEnum CONFIRMED =
      _$bookingDetailResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const BookingDetailResponseStatusEnum DECLINED =
      _$bookingDetailResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const BookingDetailResponseStatusEnum COMPLETED =
      _$bookingDetailResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const BookingDetailResponseStatusEnum NOT_COMPLETED =
      _$bookingDetailResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const BookingDetailResponseStatusEnum CANCELLED =
      _$bookingDetailResponseStatusEnum_CANCELLED;

  static Serializer<BookingDetailResponseStatusEnum> get serializer =>
      _$bookingDetailResponseStatusEnumSerializer;

  const BookingDetailResponseStatusEnum._(String name) : super(name);

  static BuiltSet<BookingDetailResponseStatusEnum> get values =>
      _$bookingDetailResponseStatusEnumValues;
  static BookingDetailResponseStatusEnum valueOf(String name) =>
      _$bookingDetailResponseStatusEnumValueOf(name);
}

class BookingDetailResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const BookingDetailResponseMasterTypeEnum CLIENT =
      _$bookingDetailResponseMasterTypeEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const BookingDetailResponseMasterTypeEnum SALON_OWNER =
      _$bookingDetailResponseMasterTypeEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const BookingDetailResponseMasterTypeEnum SALON_ADMIN =
      _$bookingDetailResponseMasterTypeEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const BookingDetailResponseMasterTypeEnum SALON_MASTER =
      _$bookingDetailResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const BookingDetailResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$bookingDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;

  static Serializer<BookingDetailResponseMasterTypeEnum> get serializer =>
      _$bookingDetailResponseMasterTypeEnumSerializer;

  const BookingDetailResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<BookingDetailResponseMasterTypeEnum> get values =>
      _$bookingDetailResponseMasterTypeEnumValues;
  static BookingDetailResponseMasterTypeEnum valueOf(String name) =>
      _$bookingDetailResponseMasterTypeEnumValueOf(name);
}
