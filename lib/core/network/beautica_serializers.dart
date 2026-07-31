// The app's [Serializers] instance — the generated `standardSerializers` plus
// Beautica's own tolerance plugins.
//
// WHY NOT MUTATE `standardSerializers`
// ------------------------------------
// The generated package declares `standardSerializers` as a mutable top-level
// variable, so reassigning it at bootstrap would "just work" for every
// consumer. It is deliberately NOT done: the value is read at provider
// construction time all over `lib/`, and widget/integration tests build those
// providers without going through `main()`, so the tolerance would be present
// or absent depending on boot ordering — the exact class of
// works-in-app/fails-in-test skew that hid the original defect.
//
// SCOPE OF ADOPTION
// -----------------
// Adoption is EXHAUSTIVE for the DTOs the tolerance covers rather than
// partial — every generated api class that can deserialize one of them is
// built on this instance:
//
//   BookingDetailResponse     → `booking_controller_api.dart`, via
//                               `bookingApiProvider`, plus
//                               `HttpBookingRepository._deserialize`'s
//                               raw-Dio page read.
//   AppointmentDetailResponse → `appointment_controller_api.dart`, via
//   + AppointmentItemResponse   `appointmentApiProvider` (the item response is
//                               only ever reached nested inside the detail
//                               response).
//
// (Verified by grep over `api/lib/src/api/`.) Every other repository still
// holds `standardSerializers`; migrate them here as their own DTOs gain
// tolerated enums — a row in `kBeauticaToleratedEnums` is INERT for an api
// class that was never migrated, and see that table's doc for the mapper work
// each new row also requires.

import 'package:beautica_api/beautica_api.dart';
import 'package:built_value/serializer.dart';

import 'unknown_enum_tolerance_plugin.dart';

/// [standardSerializers] with [UnknownEnumTolerancePlugin] appended.
///
/// Appending (rather than prepending) puts it AFTER `StandardJsonPlugin`, so
/// it sees built_value's flat list form — which the plugin handles alongside
/// the raw map form precisely so this ordering is not load-bearing.
final Serializers beauticaSerializers =
    (standardSerializers.toBuilder()
          ..addPlugin(UnknownEnumTolerancePlugin(kBeauticaToleratedEnums)))
        .build();
