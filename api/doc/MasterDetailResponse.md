# beautica_api.model.MasterDetailResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterId** | **String** |  | [optional] 
**firstName** | **String** |  | [optional] 
**lastName** | **String** |  | [optional] 
**phoneNumber** | **String** |  | [optional] 
**city** | **String** |  | [optional] 
**street** | **String** |  | [optional] 
**buildingNo** | **String** |  | [optional] 
**locationNote** | **String** |  | [optional] 
**bio** | **String** |  | [optional] 
**instagram** | **String** |  | [optional] 
**professionalTitle** | **String** |  | [optional] 
**avatarUrl** | **String** |  | [optional] 
**avgRating** | **num** |  | [optional] 
**reviewCount** | **int** |  | [optional] 
**masterType** | **String** |  | [optional] 
**salon** | [**PublicSalonResponse**](PublicSalonResponse.md) |  | [optional] 
**workingHours** | [**BuiltList&lt;WorkingHoursResponse&gt;**](WorkingHoursResponse.md) |  | [optional] 
**cityId** | **String** |  | [optional] 
**oblastId** | **String** |  | [optional] 
**districtId** | **String** |  | [optional] 
**bookingsThisMonth** | **int** |  | [optional] 
**region** | **String** | Oblast name of the master's own settlement (cityId). Null when no city is set, and on the public path for salon-affiliated masters (masked like city). | [optional] 
**citySettlementType** | **String** | Kind of the master's own settlement (cityId). Null when no city is set, and wherever cityId is masked. | [optional] 
**cityHromadaNameUk** | **String** | Bare hromada adjective of the master's own settlement, populated only when its name is ambiguous within its oblast; null otherwise and wherever cityId is masked. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


