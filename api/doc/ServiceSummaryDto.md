# beautica_api.model.ServiceSummaryDto

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**name** | **String** |  | [optional] 
**durationMinutes** | **int** |  | [optional] 
**priceFrom** | **num** |  | [optional] 
**category** | **String** | The service's category key — the same value as ServiceDefinitionResponse.category and CategoryRef.key; the website groups services by it (phase 383). | [optional] 
**categoryDisplayName** | **String** | Display name of that category, including a category the operator has since HIDDEN (SVC-56). Null for an unknown / rejected category; fall back to category then. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


