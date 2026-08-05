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
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';

import 'appointment_repository.dart';
import 'booking_repository.dart';
import 'client_review_repository.dart';
import 'slot_repository.dart';

part 'booking_providers.g.dart';

/// Provides the generated [BookingControllerApi] singleton.
///
/// Built on [beauticaSerializers], NOT the generated `standardSerializers`:
/// this is the only generated api class that carries a
/// `BookingDetailResponse`, so it is where an unrecognised backend booking
/// status would otherwise throw out of the enum serializer before the domain
/// mapper could degrade it to [BookingStatus.unknown]. See
/// `core/network/unknown_enum_tolerance_plugin.dart`.
@Riverpod(keepAlive: true)
BookingControllerApi bookingApi(Ref ref) =>
    BookingControllerApi(ref.watch(dioProvider), beauticaSerializers);

/// Provides the generated [AppointmentControllerApi] singleton for the
/// multi-service single-visit write/read path (MO-1).
///
/// Built on [beauticaSerializers] for the same reason as [bookingApi] above:
/// it is the only generated api class carrying an `AppointmentDetailResponse`
/// (and, nested inside it, `AppointmentItemResponse`), both of which have the
/// same throwing status `EnumClass` `BookingDetailResponse` did. Leaving it on
/// `standardSerializers` would make their rows in `kBeauticaToleratedEnums`
/// inert.
@Riverpod(keepAlive: true)
AppointmentControllerApi appointmentApi(Ref ref) =>
    AppointmentControllerApi(ref.watch(dioProvider), beauticaSerializers);

/// Provides the generated [ReviewControllerApi] singleton for the CLIENT
/// leave-review write path (`POST /reviews`, Phase 14.6).
///
/// A dedicated provider local to this feature (mirrors the `salonReviewApi`
/// pattern in `salon/data/salon_repository.dart`) rather than importing another
/// feature's data layer — the architecture forbids a `data/` importing another
/// feature's `data/`.
@Riverpod(keepAlive: true)
ReviewControllerApi bookingReviewApi(Ref ref) =>
    ReviewControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the [BookingRepository] singleton backed by the authenticated
/// [dioProvider] Dio instance (needed for the raw `getMyBookings` GET — see
/// the WIRE-FORMAT NOTE in `booking_repository.dart`), [bookingApiProvider],
/// and [bookingReviewApiProvider] (the `POST /reviews` write path).
@Riverpod(keepAlive: true)
BookingRepository bookingRepository(Ref ref) => HttpBookingRepository(
  ref.watch(dioProvider),
  ref.watch(bookingApiProvider),
  ref.watch(bookingReviewApiProvider),
);

/// Provides the [AppointmentRepository] singleton backed by
/// [appointmentApiProvider] (the visit write/read endpoints).
@Riverpod(keepAlive: true)
AppointmentRepository appointmentRepository(Ref ref) =>
    HttpAppointmentRepository(ref.watch(appointmentApiProvider));

/// Provides the [SlotRepository] singleton backed by the CORE
/// [masterApiProvider] (`core/network/api_client_provider.dart`) — reused
/// rather than duplicated, since `MasterControllerApi` is already a
/// core-level singleton shared by the master/schedule/calendar features.
@Riverpod(keepAlive: true)
SlotRepository slotRepository(Ref ref) =>
    HttpSlotRepository(ref.watch(masterApiProvider));

/// Provides the generated [ClientReviewControllerApi] singleton for the
/// PROVIDER→CLIENT leave-feedback write path (`POST /client-reviews`, track
/// 7.x Wave B). A dedicated provider local to this feature — mirrors
/// [bookingReviewApi] above — rather than importing another feature's data
/// layer.
@Riverpod(keepAlive: true)
ClientReviewControllerApi clientReviewApi(Ref ref) =>
    ClientReviewControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the [ClientReviewRepository] singleton backed by
/// [clientReviewApiProvider].
@Riverpod(keepAlive: true)
ClientReviewRepository clientReviewRepository(Ref ref) =>
    HttpClientReviewRepository(ref.watch(clientReviewApiProvider));
