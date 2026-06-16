// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_client_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the generated [AuthControllerApi] singleton.
///
/// Backed by the authenticated [dioProvider] Dio instance (which carries
/// the full interceptor chain) and the generated [standardSerializers] with
/// [StandardJsonPlugin] applied, so all JSON maps arrive/depart as plain
/// Dart maps with no built_value key prefixes.

@ProviderFor(authApi)
final authApiProvider = AuthApiProvider._();

/// Provides the generated [AuthControllerApi] singleton.
///
/// Backed by the authenticated [dioProvider] Dio instance (which carries
/// the full interceptor chain) and the generated [standardSerializers] with
/// [StandardJsonPlugin] applied, so all JSON maps arrive/depart as plain
/// Dart maps with no built_value key prefixes.

final class AuthApiProvider
    extends
        $FunctionalProvider<
          AuthControllerApi,
          AuthControllerApi,
          AuthControllerApi
        >
    with $Provider<AuthControllerApi> {
  /// Provides the generated [AuthControllerApi] singleton.
  ///
  /// Backed by the authenticated [dioProvider] Dio instance (which carries
  /// the full interceptor chain) and the generated [standardSerializers] with
  /// [StandardJsonPlugin] applied, so all JSON maps arrive/depart as plain
  /// Dart maps with no built_value key prefixes.
  AuthApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authApiHash();

  @$internal
  @override
  $ProviderElement<AuthControllerApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AuthControllerApi create(Ref ref) {
    return authApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthControllerApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthControllerApi>(value),
    );
  }
}

String _$authApiHash() => r'0f810d973d538c31f9fd0faa2d3b6bda20423c1b';

/// Provides the generated [UserControllerApi] singleton.
///
/// Same Dio instance and serializers as [authApiProvider].

@ProviderFor(userApi)
final userApiProvider = UserApiProvider._();

/// Provides the generated [UserControllerApi] singleton.
///
/// Same Dio instance and serializers as [authApiProvider].

final class UserApiProvider
    extends
        $FunctionalProvider<
          UserControllerApi,
          UserControllerApi,
          UserControllerApi
        >
    with $Provider<UserControllerApi> {
  /// Provides the generated [UserControllerApi] singleton.
  ///
  /// Same Dio instance and serializers as [authApiProvider].
  UserApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userApiHash();

  @$internal
  @override
  $ProviderElement<UserControllerApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UserControllerApi create(Ref ref) {
    return userApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserControllerApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserControllerApi>(value),
    );
  }
}

String _$userApiHash() => r'46ce080c703ee972e4052065d04903c017e124be';

/// Provides the generated [MasterControllerApi] singleton.
///
/// Used by [HttpMasterRepository.getMyProfile] to fetch master profile data
/// via `GET /masters/{masterId}`. Same Dio instance and serializers as the
/// other API providers in this file.

@ProviderFor(masterApi)
final masterApiProvider = MasterApiProvider._();

/// Provides the generated [MasterControllerApi] singleton.
///
/// Used by [HttpMasterRepository.getMyProfile] to fetch master profile data
/// via `GET /masters/{masterId}`. Same Dio instance and serializers as the
/// other API providers in this file.

final class MasterApiProvider
    extends
        $FunctionalProvider<
          MasterControllerApi,
          MasterControllerApi,
          MasterControllerApi
        >
    with $Provider<MasterControllerApi> {
  /// Provides the generated [MasterControllerApi] singleton.
  ///
  /// Used by [HttpMasterRepository.getMyProfile] to fetch master profile data
  /// via `GET /masters/{masterId}`. Same Dio instance and serializers as the
  /// other API providers in this file.
  MasterApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'masterApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$masterApiHash();

  @$internal
  @override
  $ProviderElement<MasterControllerApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MasterControllerApi create(Ref ref) {
    return masterApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MasterControllerApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MasterControllerApi>(value),
    );
  }
}

String _$masterApiHash() => r'a65eae8f063767751d1fc49a0c9dbc1d679f3fc7';
