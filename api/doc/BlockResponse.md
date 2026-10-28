# beautica_api.model.BlockResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**kind** | **String** |  | [optional] 
**displayName** | **String** |  | [optional] 
**avatarUrl** | **String** | Live avatar of the blocked account. CLIENT rows only; null for GUEST. | [optional] 
**maskedPhone** | **String** | Masked guest phone, last four digits only. GUEST rows only; null for CLIENT. | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


