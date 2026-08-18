# beautica_api.model.AppointmentDetailResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**status** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**masterFirstName** | **String** |  | [optional] 
**masterLastName** | **String** |  | [optional] 
**masterProfessionalTitle** | **String** | The master's professional title/headline. Nullable — a master may never have set one. | [optional] 
**masterAvatarUrl** | **String** |  | [optional] 
**masterType** | **String** |  | [optional] 
**salonName** | **String** | The name of the salon THIS VISIT was booked at (the visit's own salon snapshot), or null when the visit was with an independent master. Not the master's current affiliation — a master who has since moved salons does not rewrite a past visit's premises. | [optional] 
**startsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**endsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**totalDurationMinutes** | **int** |  | [optional] 
**totalPrice** | **num** |  | [optional] 
**totalPriceMax** | **num** | The summed range ceiling of the visit, present ONLY when at least one service was a genuine range at booking time. Null means a single total price — render totalPrice alone. Never re-derived on read. | [optional] 
**clientComment** | **String** | The client's booking-creation note for the whole visit. | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 
**items** | [**BuiltList&lt;AppointmentItemResponse&gt;**](AppointmentItemResponse.md) |  | [optional] 
**providerComment** | **String** | Written by the provider on the visit /decline or /not-complete. Shown to the CLIENT on both DECLINED and NOT_COMPLETED visits — intentional, by the locked \"all notes visible for all sides\" decision, NOT a privacy leak. Do not suppress for any audience. Same field/rule as BookingDetailResponse.providerComment, lifted to the visit header. | [optional] 
**clientCancellationNote** | **String** | Written by the CLIENT on the visit /cancel — the symmetric counterpart of providerComment, shown to the provider. Only ever non-null on a CANCELLED visit. Same field/rule as BookingDetailResponse.clientCancellationNote. | [optional] 
**cityLabel** | **String** | Discovery city label (Ukrainian). Resolved by the service through the same district-primary DiscoveryLocationResolver seam as BookingDetailResponse — salon locality when salon-employed, else the master's own user row. | [optional] 
**districtLabel** | **String** | Discovery district label (Ukrainian). Same resolution as cityLabel. | [optional] 
**street** | **String** | Arrival street — the BOOKED salon's when the visit was made at a salon, else the master's own. Same salon-vs-independent rule as BookingDetailResponse.street, resolved against the visit's own salon snapshot: a salon-employed master's PERSONAL street never leaks onto a salon visit, AND a master who has since moved salons cannot cause this visit to display the address of premises it was never booked at. | [optional] 
**buildingNo** | **String** | Arrival building number. | [optional] 
**locationNote** | **String** | Provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\"). Same salon-vs-independent resolution as street/buildingNo, against the salon THIS VISIT was booked at — never the master's personal note, and never a salon the master merely works at today. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


