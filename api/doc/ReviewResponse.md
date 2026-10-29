# beautica_api.model.ReviewResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**clientDisplayName** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**rating** | **int** |  | [optional] 
**comment** | **String** |  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 
**authoredByViewer** | **bool** | True when the authenticated caller wrote this review (the app hides «Поскаржитися» on it); always false for an anonymous caller and on booking-link (slug) pages. | [optional] 
**source_** | **String** | Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


