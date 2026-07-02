// Phase 14.0 — Riverpod wiring for the booking data layer.
//
// Exposes [bookingApiProvider] (the generated [BookingControllerApi]
// singleton), [bookingRepositoryProvider] ([HttpBookingRepository] backed by
// it), and [slotRepositoryProvider] ([HttpSlotRepository] backed by the
// shared core [masterApiProvider] — `MasterControllerApi` already has a
// core-level provider in `core/network/api_client_provider.dart`, so this
// file reuses it rather than constructing a second instance).
//
// Mirrors the established split-provider-file pattern (see
// `favorites/data/favorite_repository_provider.dart` /
// `schedule/data/schedule_repository_provider.dart`): the repository
// interfaces/impls stay provider-free and directly mocktail-testable; only
// this file carries `@riverpod` annotations.
//
// Override [bookingRepositoryProvider] / [slotRepositoryProvider] with a
// mocktail mock in tests — never construct [HttpBookingRepository] /
// [HttpSlotRepository] directly in production code.

import 'package:beautica_api/beautica_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';

import 'booking_repository.dart';
import 'slot_repository.dart';

part 'booking_providers.g.dart';

/// Provides the generated [BookingControllerApi] singleton.
@Riverpod(keepAlive: true)
BookingControllerApi bookingApi(Ref ref) =>
    BookingControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the [BookingRepository] singleton backed by the authenticated
/// [dioProvider] Dio instance (needed for the raw `getMyBookings` GET — see
/// the WIRE-FORMAT NOTE in `booking_repository.dart`) and [bookingApiProvider].
@Riverpod(keepAlive: true)
BookingRepository bookingRepository(Ref ref) => HttpBookingRepository(
  ref.watch(dioProvider),
  ref.watch(bookingApiProvider),
);

/// Provides the [SlotRepository] singleton backed by the CORE
/// [masterApiProvider] (`core/network/api_client_provider.dart`) — reused
/// rather than duplicated, since `MasterControllerApi` is already a
/// core-level singleton shared by the master/schedule/calendar features.
@Riverpod(keepAlive: true)
SlotRepository slotRepository(Ref ref) =>
    HttpSlotRepository(ref.watch(masterApiProvider));
