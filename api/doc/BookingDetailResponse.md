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
**locationNote** | **String** | The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo: a salon booking surfaces the salon's own note, an independent master surfaces their own note. Nullable — most providers never set one. | [optional] 
**categoryName** | **String** |  | [optional] 
**canReview** | **bool** |  | [optional] 
**providerCanReviewClient** | **bool** | TRUE only for the CURRENT authenticated viewer, and only on GET /bookings/{id}: the viewer has provider review-authority over this booking, its status is COMPLETED, it has a real (non-guest) client, and no ClientReview exists for it yet. FALSE for a CLIENT/SALON_MASTER viewer, an unauthorized provider, or any row served by GET /bookings/me (both the CLIENT and provider listing paths hardcode false — see BookingDetailResponse's class javadoc). Gates the \"Залишити відгук про клієнта\" CTA; the write endpoint (POST /client-reviews) re-checks the same conditions server-side regardless of this value. | [optional] 
**appointmentId** | **String** | The multi-service visit (BE-5) this booking belongs to, or null for a legacy single-service booking (appointment_id IS NULL). Strictly additive; when non-null the client can fetch the full visit via GET /appointments/{appointmentId}. Both mapper paths (entity + CLIENT projection) read the SAME appointment_id column, so they never diverge. | [optional] 
**clientAvatarUrl** | **String** | The booking client's profile photo — the same already-public Cloudflare R2 object URL served by masterAvatarUrl and every other avatar field in this API (never a signed URL, never a raw storage key). Lets a provider timeline render the client's photo instead of a generic glyph. NULL in two cases, both of which must render the fallback glyph: (1) a guest (LINK) booking, which has no registered account at all (client_id IS NULL, V89 chk_bookings_guest_fields) and therefore no photo and no fallback — unlike clientFirstName/clientLastName, which do fall back to the OTP-verified guest name; (2) a registered client who has never uploaded one. Do not distinguish the two client-side. Both causes mean strictly 'this booking has no client photo' — NULL here never encodes who is asking. The value depends only on the booking, so the same booking yields the same value on GET /bookings/{id} and on every row of GET /bookings/me, for a provider and for the client themselves alike; a client reading their own booking sees their own photo. Safe to cache by booking id across both endpoints. | [optional] 
**awaitingClosure** | **bool** | Derived, read-time-only (Phase 29.1/29.2) — TRUE when this booking's status is still CONFIRMED but its endsAt has already elapsed: no scheduled job ever transitions such a booking to a terminal state, so this flags the ones the provider still needs to close via /complete, /not-complete or /decline. NEVER persisted, NEVER cached — recomputed on every read from (status, endsAt, the current instant). Orthogonal to canReview: an elapsed-but-unclosed CONFIRMED booking reads TRUE here and FALSE for canReview, since review eligibility keys off closure (COMPLETED), never off elapsed wall-clock time. The same for every row of GET /bookings/me and for GET /bookings/{id} — a pure function of the booking, not of the viewer. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


