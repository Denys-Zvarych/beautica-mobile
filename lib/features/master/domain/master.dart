// Phase 4.1 — Master domain model.
//
// Immutable value object representing a beauty master as returned by the
// `GET /masters/{masterId}` endpoint. Uses `freezed` for value equality,
// copyWith, and pattern matching.
//
// [MasterType] bridges the backend's SCREAMING_SNAKE_CASE wire values
// (from [MasterDetailResponseMasterTypeEnum]) to idiomatic Dart lowerCamelCase
// enum variants so the rest of the domain layer never depends on generated
// API types.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../calendar/domain/working_hours.dart';

part 'master.freezed.dart';

/// The role / tenure type of a master in the Beautica platform.
///
/// Mirrors [MasterDetailResponseMasterTypeEnum] from the generated API package.
/// Conversion is done once at the data-layer boundary in [MasterMapper].
enum MasterType {
  /// Master employed within a salon (invited by a [salonOwner] or admin).
  salonMaster,

  /// Solo provider with no salon affiliation.
  independentMaster,

  /// Owner of a salon who also acts as a master.
  salonOwner,
}

/// A Beautica beauty master — the canonical domain entity returned by the
/// profile-read path.
///
/// All fields are flat and nullable-where-optional; there is no nested user
/// sub-object because [MasterDetailResponse] does not carry one.
@freezed
abstract class Master with _$Master {
  const factory Master({
    /// Backend-assigned UUID for this master.
    required String id,

    /// Master's given name.
    required String firstName,

    /// Master's family name.
    required String lastName,

    /// City where the master operates (display string, not a UUID).
    String? city,

    /// UUID of the city the master is located in. Used by [LocalityCascade]
    /// to pre-populate the city picker when opening the edit screen.
    String? cityId,

    /// UUID of the oblast (region) the master is located in. Used by
    /// [LocalityCascade] to pre-populate the region picker when opening the
    /// edit screen.
    String? oblastId,

    /// UUID of the city district, or `null` when the city has no districts or
    /// the master hasn't selected one.
    String? districtId,

    /// Street name where the master works.
    String? street,

    /// Building number (e.g. "22").
    String? buildingNo,

    /// Apartment/floor/office note (e.g. "кв. 3, 2 поверх").
    String? locationNote,

    /// Short bio text entered by the master.
    String? bio,

    /// URL of the master's profile avatar.
    String? avatarUrl,

    /// Average review rating (1.0–5.0 scale), or `null` when the master has no
    /// reviews yet.
    ///
    /// **`null` is the no-reviews state — NEVER coalesce it to `0.0`.** The
    /// backend stores `0.00` for an unreviewed master (`masters.avg_rating` is
    /// `NOT NULL DEFAULT 0.00`) and, since Phase 240, normalises that storage
    /// artefact to `null` on every endpoint that serves a master, precisely so
    /// a brand-new master is not shown a damning zero stars. Defaulting it back
    /// to `0` here would re-introduce the exact bug the backend removed.
    ///
    /// Render the no-rating treatment when null — `MasterStrip` shows the
    /// `—` placeholder, the discovery cards show «Без відгуків».
    double? avgRating,

    /// Total number of reviews received.
    required int reviewCount,

    /// Tenure / role type for this master.
    required MasterType type,

    /// UUID of the affiliated salon; `null` for [MasterType.independentMaster].
    String? salonId,

    /// Contact phone number as entered by the master.
    String? phoneNumber,

    /// Instagram handle or URL as entered by the master.
    /// May be a bare handle (e.g. "username"), "@"-prefixed handle, or full
    /// https://instagram.com/... URL — stored verbatim from user input.
    String? instagram,

    /// Optional professional title (e.g. "Майстер манікюру", "Стиліст").
    /// Nullable — absent when the master has not set one. Empty string from
    /// the API is normalised to `null` by the mapper.
    String? professionalTitle,

    /// The master's working week as a dense, ordered 7-entry list
    /// (Monday(1) … Sunday(7)), gap-filled by [WorkingHoursMapper.toDomainWeek]
    /// at the data-layer boundary. Carries the working hours bundled in
    /// `MasterDetailResponse.workingHours` so the calendar feature reads them
    /// from this cached profile instead of issuing a second `getMyProfile`
    /// round-trip (PERF M1). Defaults to an empty list only when constructed
    /// without a mapped profile (e.g. in tests); the mapper always materialises
    /// all 7 days.
    @Default(<WorkingHours>[]) List<WorkingHours> workingHours,
  }) = _Master;
}

/// Rating presentation helpers for [Master].
extension MasterRatingX on Master {
  /// The average rating to display, or `null` when there is no rating to show
  /// and the caller must render the no-rating treatment (`—` / «Без відгуків»).
  ///
  /// Collapses THREE distinct "no rating yet" shapes onto a single `null` so no
  /// call site has to remember all of them:
  ///
  ///  * [avgRating] is `null` — the Phase 240 wire contract for an unreviewed
  ///    master, and the canonical signal going forward.
  ///  * [avgRating] is `0.0` — the pre-240 wire shape, and still what a stale
  ///    backend or an older cached response sends. Rendering it would print a
  ///    damning «0.0» on a brand-new master, which is the exact bug Phase 240
  ///    set out to remove; a real average is always ≥ 1.0, so a zero here is a
  ///    storage artefact and never a genuine score.
  ///  * [reviewCount] is `0` — no reviews can produce no average, whatever the
  ///    rating field happens to carry.
  ///
  /// Mirrors the guard `MasterResultCard._RatingRow` already applies on the
  /// discovery cards, so every surface agrees on what "unrated" looks like.
  double? get displayRating {
    final double? avg = avgRating;
    if (avg == null || avg <= 0 || reviewCount <= 0) return null;
    return avg;
  }
}
