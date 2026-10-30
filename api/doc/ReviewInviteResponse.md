# beautica_api.model.ReviewInviteResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**state** | **String** |  | [optional] 
**providerName** | **String** |  | [optional] 
**providerType** | **String** |  | [optional] 
**visitDate** | [**Date**](Date.md) |  | [optional] 
**items** | [**BuiltList&lt;ReviewInviteItemResponse&gt;**](ReviewInviteItemResponse.md) |  | [optional] 
**displayName** | **String** |  | [optional] 
**avatarUrl** | **String** |  | [optional] 
**avgRating** | **num** | null while the provider has no reviews (never a fabricated 0). | [optional] 
**reviewCount** | **int** | Set on every OPEN form (0 when none); absent on ALREADY_REVIEWED. | [optional] 
**professionalTitle** | **String** | Master only; null for a salon. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


