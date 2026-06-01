//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'package:dio/dio.dart';
import 'package:built_value/serializer.dart';
import 'package:beautica_api/src/serializers.dart';
import 'package:beautica_api/src/auth/api_key_auth.dart';
import 'package:beautica_api/src/auth/basic_auth.dart';
import 'package:beautica_api/src/auth/bearer_auth.dart';
import 'package:beautica_api/src/auth/oauth.dart';
import 'package:beautica_api/src/api/auth_controller_api.dart';
import 'package:beautica_api/src/api/booking_controller_api.dart';
import 'package:beautica_api/src/api/category_request_controller_api.dart';
import 'package:beautica_api/src/api/dashboard_controller_api.dart';
import 'package:beautica_api/src/api/device_controller_api.dart';
import 'package:beautica_api/src/api/independent_master_controller_api.dart';
import 'package:beautica_api/src/api/internal_category_controller_api.dart';
import 'package:beautica_api/src/api/location_controller_api.dart';
import 'package:beautica_api/src/api/master_controller_api.dart';
import 'package:beautica_api/src/api/media_controller_api.dart';
import 'package:beautica_api/src/api/review_controller_api.dart';
import 'package:beautica_api/src/api/salon_controller_api.dart';
import 'package:beautica_api/src/api/salon_master_controller_api.dart';
import 'package:beautica_api/src/api/search_controller_api.dart';
import 'package:beautica_api/src/api/service_catalog_controller_api.dart';
import 'package:beautica_api/src/api/service_controller_api.dart';
import 'package:beautica_api/src/api/user_controller_api.dart';

@Deprecated(
    "Never instantiate BeauticaApi() directly. Use individual API class constructors with ref.watch(dioProvider) instead to ensure auth interceptors and cert-pinning apply. See lib/core/network/dio_provider.dart.")
// ignore: deprecated_member_use_from_same_package
class BeauticaApi {
  static const String basePath = r'';

  final Dio dio;
  final Serializers serializers;

  BeauticaApi({
    Dio? dio,
    Serializers? serializers,
    String? basePathOverride,
    List<Interceptor>? interceptors,
  })  : this.serializers = serializers ?? standardSerializers,
        this.dio = dio ??
            Dio(BaseOptions(
              baseUrl: basePathOverride ?? basePath,
              connectTimeout: const Duration(milliseconds: 5000),
              receiveTimeout: const Duration(milliseconds: 3000),
            )) {
    if (interceptors == null) {
      this.dio.interceptors.addAll([
        OAuthInterceptor(),
        BasicAuthInterceptor(),
        BearerAuthInterceptor(),
        ApiKeyAuthInterceptor(),
      ]);
    } else {
      this.dio.interceptors.addAll(interceptors);
    }
  }

  void setOAuthToken(String name, String token) {
    if (this.dio.interceptors.any((i) => i is OAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is OAuthInterceptor)
              as OAuthInterceptor)
          .tokens[name] = token;
    }
  }

  void setBearerAuth(String name, String token) {
    if (this.dio.interceptors.any((i) => i is BearerAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BearerAuthInterceptor)
              as BearerAuthInterceptor)
          .tokens[name] = token;
    }
  }

  void setBasicAuth(String name, String username, String password) {
    if (this.dio.interceptors.any((i) => i is BasicAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BasicAuthInterceptor)
              as BasicAuthInterceptor)
          .authInfo[name] = BasicAuthInfo(username, password);
    }
  }

  void setApiKey(String name, String apiKey) {
    if (this.dio.interceptors.any((i) => i is ApiKeyAuthInterceptor)) {
      (this
                  .dio
                  .interceptors
                  .firstWhere((element) => element is ApiKeyAuthInterceptor)
              as ApiKeyAuthInterceptor)
          .apiKeys[name] = apiKey;
    }
  }

  /// Get AuthControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  AuthControllerApi getAuthControllerApi() {
    return AuthControllerApi(dio, serializers);
  }

  /// Get BookingControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  BookingControllerApi getBookingControllerApi() {
    return BookingControllerApi(dio, serializers);
  }

  /// Get CategoryRequestControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  CategoryRequestControllerApi getCategoryRequestControllerApi() {
    return CategoryRequestControllerApi(dio, serializers);
  }

  /// Get DashboardControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  DashboardControllerApi getDashboardControllerApi() {
    return DashboardControllerApi(dio, serializers);
  }

  /// Get DeviceControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  DeviceControllerApi getDeviceControllerApi() {
    return DeviceControllerApi(dio, serializers);
  }

  /// Get IndependentMasterControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  IndependentMasterControllerApi getIndependentMasterControllerApi() {
    return IndependentMasterControllerApi(dio, serializers);
  }

  /// Get InternalCategoryControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  InternalCategoryControllerApi getInternalCategoryControllerApi() {
    return InternalCategoryControllerApi(dio, serializers);
  }

  /// Get LocationControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  LocationControllerApi getLocationControllerApi() {
    return LocationControllerApi(dio, serializers);
  }

  /// Get MasterControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  MasterControllerApi getMasterControllerApi() {
    return MasterControllerApi(dio, serializers);
  }

  /// Get MediaControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  MediaControllerApi getMediaControllerApi() {
    return MediaControllerApi(dio, serializers);
  }

  /// Get ReviewControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ReviewControllerApi getReviewControllerApi() {
    return ReviewControllerApi(dio, serializers);
  }

  /// Get SalonControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  SalonControllerApi getSalonControllerApi() {
    return SalonControllerApi(dio, serializers);
  }

  /// Get SalonMasterControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  SalonMasterControllerApi getSalonMasterControllerApi() {
    return SalonMasterControllerApi(dio, serializers);
  }

  /// Get SearchControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  SearchControllerApi getSearchControllerApi() {
    return SearchControllerApi(dio, serializers);
  }

  /// Get ServiceCatalogControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ServiceCatalogControllerApi getServiceCatalogControllerApi() {
    return ServiceCatalogControllerApi(dio, serializers);
  }

  /// Get ServiceControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ServiceControllerApi getServiceControllerApi() {
    return ServiceControllerApi(dio, serializers);
  }

  /// Get UserControllerApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  UserControllerApi getUserControllerApi() {
    return UserControllerApi(dio, serializers);
  }
}
