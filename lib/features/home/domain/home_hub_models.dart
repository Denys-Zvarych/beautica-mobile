// Phase 13.7 — Home Hub domain models (pure Dart, no Flutter import).
//
// Modelled on the preview's `home_hub_data.dart` shapes. All classes are
// plain immutable value objects until the backend 19.x endpoints land and
// freezed + json_serializable codegen is wired up (TODO 19.x).
//
// The `clientPhone` and `clientCity` fields on [ClientProfileSummary] are PII
// that trigger the ScreenProtectionManager in HomeHubScreen (§ CRITICAL-4).

/// The signed-in client's profile summary (hydrated from GET /users/me via
/// [AuthSession.user]).
class ClientProfileSummary {
  const ClientProfileSummary({
    required this.firstName,
    required this.lastName,
    required this.city,
    required this.phone,
    required this.clientRating,
    required this.memberSinceYear,
  });

  final String firstName;
  final String lastName;
  final String city;
  final String phone;

  /// The client's aggregate rating from masters/salons (two-sided ratings system).
  /// null = no rating yet (backend GET /clients/me/rating not yet shipped).
  /// When rated, shows ★ n.n. Never shows individual comments.
  /// TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments).
  final double? clientRating;

  final int memberSinceYear;

  String get fullName => '$firstName $lastName';

  String get initials {
    final f = firstName.isEmpty ? '' : firstName[0];
    final l = lastName.isEmpty ? '' : lastName[0];
    return '$f$l';
  }
}

/// The soonest upcoming (CONFIRMED) booking — drives the "Найближчий запис"
/// card and its live countdown chip.
class NextAppointment {
  const NextAppointment({
    required this.id,
    required this.masterName,
    required this.service,
    required this.dateLabel,
    required this.timeLabel,
    required this.location,
    required this.startsAt,
    required this.endsAt,
    required this.masterInitials,
  });

  final String id;
  final String masterName;
  final String service;
  final String dateLabel;
  final String timeLabel;
  final String location;
  final DateTime startsAt;

  /// The booking's real `endAt` (backend 19.3 enrichment) — lets add-to-
  /// calendar seed the event's true end instant instead of a guessed block.
  /// See `home_hub_screen.dart`'s `_addNextAppointmentToCalendar`.
  final DateTime endsAt;
  final String masterInitials;
}

/// A master in the favorites horizontal rail.
class FavoriteMasterItem {
  const FavoriteMasterItem({
    required this.masterId,
    required this.favoriteId,
    required this.name,
    required this.lastServiceName,
    required this.rating,
    required this.reviewCount,
    required this.initials,
  });

  final String masterId;

  /// The ID used for the DELETE /favorites/masters/:id call.
  final String favoriteId;

  final String name;
  final String lastServiceName;
  final double rating;
  final int reviewCount;
  final String initials;
}

/// One past procedure on the BEAUTY TIMELINE rail.
class TimelineEntry {
  const TimelineEntry({required this.category, required this.dateLabel});

  final String category;
  final String dateLabel;
}
