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

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


