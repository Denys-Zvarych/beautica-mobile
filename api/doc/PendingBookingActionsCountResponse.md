# beautica_api.model.PendingBookingActionsCountResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**count** | **int** | Total bookings still needing a provider action: toClose + toRateClient. Uncapped; the client caps its display. | [optional] 
**toClose** | **int** | CONFIRMED bookings whose end has passed (offer «Завершити» / «Не відбувся»). | [optional] 
**toRateClient** | **int** | COMPLETED bookings with a registered client and no client review yet (offer «Залишити відгук про клієнта»). | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


