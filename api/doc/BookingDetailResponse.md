# beautica_api.model.BookingDetailResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**clientId** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**masterServiceId** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**status** | **String** |  | [optional] 
**startsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**endsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**priceAtBooking** | **num** |  | [optional] 
**priceMaxAtBooking** | **num** | The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once. | [optional] 
**durationMinutesAtBooking** | **int** |  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 
**clientFirstName** | **String** |  | [optional] 
**clientLastName** | **String** |  | [optional] 
**masterFirstName** | **String** |  | [optional] 
**masterLastName** | **String** |  | [optional] 
**masterProfessionalTitle** | **String** | The master's professional title/headline (e.g. \"Перукар-стиліст\"), same field as MasterSummaryResponse/MasterDetailResponse. Nullable — a master may never have set one. | [optional] 
**clientComment** | **String** | The client's booking-creation note (written once at POST /bookings). Visible to the provider. Distinct from clientCancellationNote below — this is NOT the cancellation reason. | [optional] 
**providerComment** | **String** | Written by the provider on /decline or /not-complete. Visible to the CLIENT on both DECLINED and NOT_COMPLETED bookings — intentional, by locked product decision (\"all notes visible for all sides\"), NOT a privacy leak. Do not suppress this for any audience. | [optional] 
**clientCancellationNote** | **String** | Written by the CLIENT on /cancel. Visible to the provider — the symmetric counterpart of providerComment. Only ever non-null on a CANCELLED booking. | [optional] 
**masterAvatarUrl** | **String** |  | [optional] 
**masterType** | **String** |  | [optional] 
**salonName** | **String** |  | [optional] 
**cityLabel** | **String** |  | [optional] 
**districtLabel** | **String** |  | [optional] 
**street** | **String** |  | [optional] 
**buildingNo** | **String** |  | [optional] 
**locationNote** | **String** | The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo, against the salon THIS BOOKING was made at (bookings.salon_id): a salon booking surfaces that salon's own note — never the master's current salon's, should the master have moved since — and an independent-master booking surfaces the master's own note. Nullable — most providers never set one. | [optional] 
**categoryName** | **String** | The RAW category slug (e.g. \"NAIL_SERVICE\"), sourced directly from service_definitions.category — NOT a human-readable display name, despite the field name. The Ukrainian display text lives in platform_categories.display_name, which no booking read path joins. Kept for backward compatibility with existing consumers; do not rename or repoint it to the display name without a coordinated client migration — that would silently change every current consumer's rendered value. New code that needs a stable machine key for icon/category resolution should prefer categoryKey below. | [optional] 
**canReview** | **bool** |  | [optional] 
**providerCanReviewClient** | **bool** | TRUE only for the CURRENT authenticated viewer, and only on GET /bookings/{id}: the viewer has provider review-authority over this booking, the booking is COMPLETED (strictly — unlike the client-side canReview flag, an elapsed-but-unclosed CONFIRMED booking does NOT qualify here; see BookingClosureRule#isProviderReviewEligible), it has a real (non-guest) client, and no ClientReview exists for it yet. FALSE for a CLIENT/SALON_MASTER viewer, an unauthorized provider, or any row of the CLIENT listing path of GET /bookings/me (which hardcodes false). The PROVIDER rows of GET /bookings/me carry the real per-row value — see BookingDetailResponse's class javadoc. Gates the \"Залишити відгук про клієнта\" CTA; the write endpoint (POST /client-reviews) re-checks the same conditions server-side regardless of this value. | [optional] 
**appointmentId** | **String** | The multi-service visit (BE-5) this booking belongs to, or null for a legacy single-service booking (appointment_id IS NULL). Strictly additive; when non-null the client can fetch the full visit via GET /appointments/{appointmentId}. Both mapper paths (entity + CLIENT projection) read the SAME appointment_id column, so they never diverge. | [optional] 
**clientAvatarUrl** | **String** | The booking client's profile photo — the same already-public Cloudflare R2 object URL served by masterAvatarUrl and every other avatar field in this API (never a signed URL, never a raw storage key). Lets a provider timeline render the client's photo instead of a generic glyph. NULL in two cases, both of which must render the fallback glyph: (1) a guest (LINK) booking, which has no registered account at all (client_id IS NULL, V89 chk_bookings_guest_fields) and therefore no photo and no fallback — unlike clientFirstName/clientLastName, which do fall back to the OTP-verified guest name; (2) a registered client who has never uploaded one. Do not distinguish the two client-side. Both causes mean strictly 'this booking has no client photo' — NULL here never encodes who is asking. The value depends only on the booking, so the same booking yields the same value on GET /bookings/{id} and on every row of GET /bookings/me, for a provider and for the client themselves alike; a client reading their own booking sees their own photo. Safe to cache by booking id across both endpoints. | [optional] 
**awaitingClosure** | **bool** | Derived, read-time-only (Phase 29.1/29.2) — TRUE when this booking's status is still CONFIRMED but its endsAt has already elapsed: no scheduled job ever transitions such a booking to a terminal state, so this flags the ones the provider still needs to close via /complete, /not-complete or /decline. NEVER persisted, NEVER cached — recomputed on every read from (status, endsAt, the current instant). NOT orthogonal to canReview since the review-eligibility widening: an elapsed-but-unclosed CONFIRMED booking reads TRUE here AND (when it has a registered client and no existing review) TRUE for canReview too — closure-awaiting and review-eligible now deliberately overlap for exactly this row shape, by locked product decision (a booking that entered the client's Past tab by elapsed time is reviewable even before the provider closes it — see BookingClosureRule#isReviewEligible). The same for every row of GET /bookings/me and for GET /bookings/{id} — a pure function of the booking, not of the viewer. | [optional] 
**masterAvgRating** | **num** | The master's public average rating, 1.00-5.00, read off the denormalized masters.avg_rating column — the SAME value served by GET /masters/{id} and GET /masters/{id}/reviews/summary, never independently re-aggregated. Agreement across those three endpoints is exact, not eventual: GET /masters/{id} is served from the 5-minute 'master-detail' cache, and ReviewEventListener#onReviewCreated evicts that entry by masterId once the rating recalculation commits, so a client that leaves a review sees the new average on the booking AND on the profile on the very next request. NULL when masterReviewCount is 0: the column stores 0.00 for an unreviewed master (V4 NOT NULL DEFAULT 0.00, and recalculateMasterRating's COALESCE(AVG(...), 0)), which is a storage artefact, not a rating — rendering it would show a brand-new master a damning zero stars. Render the 'no reviews yet' state when null; never substitute 0. | [optional] 
**masterReviewCount** | **int** | How many reviews the master's average is computed from. 0 for an unreviewed master (a true fact, unlike a 0.00 average) and non-null on every path that serves this DTO today; typed nullable so a client treats an absent value as 'unknown' rather than 'zero reviews'. | [optional] 
**salonId** | **String** | The salon this booking was made AT, as snapshotted on the booking row (bookings.salon_id). NULL for an INDEPENDENT_MASTER booking. Exists so a client can invalidate its own salon-scoped caches after leaving a review: ReviewService#createReview stamps the review with booking.getSalon() and ReviewEventListener recalculates THAT salon's avg_rating/review_count, so this is the id whose aggregates moved. As of phase 242 salonName and the street/buildingNo/locationNote/cityLabel/districtLabel block are resolved from this SAME booking snapshot, so salonId != null and salonName != null are one predicate and the id always identifies the premises whose address is displayed alongside it. (Before 242 the address block came from the master's LIVE salon and the two could disagree after a rotation — that divergence is gone.) | [optional] 
**categoryKey** | **String** | Stable machine key for the client-side category-icon resolver — the uppercase slug of the service's category (e.g. \"NAIL_SERVICE\"), or null when the service has no category. Mirrors ClientAggregationRepository#findTimeline's categoryKey/categoryName pair (Beauty Timeline). Prefer this over categoryName for icon resolution — categoryName is for display only. Never a fallback/placeholder value: a null here must render no icon, not a guessed one. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


