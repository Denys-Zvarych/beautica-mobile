// Phase 17.3 — Shared fake backend for integration tests.
//
// WHAT
// ----
// Wraps a [Dio] instance with a [DioAdapter] that acts as a tiny stateful HTTP
// server — no real socket, no process boundary. Extracted from the original
// `edit_profile_flow_test.dart` and extended with seeded, deterministic
// fixtures for every journey the 17.3 suite covers.
//
// DETERMINISM CONTRACT
// --------------------
// All fixture data is pre-set (never random). The fake is driven by the
// SEEDED_FIXED_DATE clock (2026-06-14 12:00 UTC) declared at the bottom of
// this file and injected into every harness boot.
//
// FIXTURE PERSONAS
// ----------------
//  kClientUser       — UserRole.client, email client@beautica.ua
//  kSalonOwnerUser   — UserRole.salonOwner, email owner@beautica.ua
//  kMasterUser       — UserRole.independentMaster, email master@beautica.ua
//                      (pre-seeded with FIXED + RANGE services and schedule)
//
// ENDPOINTS WIRED
// ---------------
//  POST /api/v1/auth/login               — validates email+password against fixtures
//  POST /api/v1/auth/register/{role}     — returns verificationRequired envelope
//  POST /api/v1/auth/verify-email        — returns auth tokens
//  GET  /api/v1/users/me                 — returns user from current session
//  POST /api/v1/auth/logout              — no-op 200
//  POST /api/v1/auth/forgot-password     — Beautica OTP task Phase B, generic 200
//  POST /api/v1/auth/verify-password-reset-otp — Beautica OTP task Phase B, returns {resetTicket}
//  POST /api/v1/users/me/change-password/request-otp — Beautica OTP task Phase B, authenticated, no-op 200
//  POST /api/v1/auth/reset-password      — Beautica OTP task Phase B, void on success
//  GET  /api/v1/masters/me               — master profile
//  PATCH /api/v1/independent-masters/me/profile  — mutates master profile
//  GET  /api/v1/independent-masters/me/services  — service list
//  POST /api/v1/independent-masters/me/services  — creates service
//  GET  /api/v1/independent-masters/me/services/:id  — single service
//  PATCH /api/v1/independent-masters/me/services/:id  — edits service
//  GET  /api/v1/masters/{me|masterId}/weekly-schedules  — weekly schedule (Mon+Tue active)
//  POST /api/v1/masters/{me|masterId}/weekly-schedules  — create schedule
//  PUT  /api/v1/masters/{me|masterId}/weekly-schedules/schedule-1 — update schedule
//  GET  /api/v1/locations/oblasts        — empty list (locality cascade)
//  GET  /api/v1/salons/salon-xyz                  — public salon detail (Phase 13.6)
//  GET  /api/v1/salons/salon-xyz/masters          — salon masters rail
//  GET  /api/v1/salons/salon-xyz/services         — salon service catalogue
//  GET  /api/v1/salons/salon-xyz/reviews/summary  — salon review-summary header
//  GET  /api/v1/salons/salon-xyz/reviews          — salon reviews list
//  GET  /api/v1/salons/salon-xyz/portfolio        — salon portfolio photo rail
//  GET  /api/v1/masters/master-aaa/slots          — Phase 14.1 slot-picker availability
//  GET  /api/v1/masters/master-aaa/working-days   — Phase 14.14 calendar day-availability gate
//  GET  /api/v1/salons/salon-xyz/services/{serviceDefId}/masters — Phase 23.x bookable-masters
//                                                                   (salon-svc-shared/salon-svc-exclusive)
//  GET  /api/v1/masters/{master-ccc,master-ddd}/working-days — Phase 14.16 salon time-picker (per assigned master)
//  GET  /api/v1/masters/{master-ccc,master-ddd}/slots        — Phase 14.17 salon time-picker (per assigned master)
//
// USAGE
// -----
//   final fb = FakeBackend();                   // owns its own Dio instance
//   final harness = AppHarness.boot(tester, fakeBackend: fb);
//   // after test: fb.dio is already closed by Dio's own GC.
//
// RAW-TEXT TAP CONVENTION (enforced here)
// ----------------------------------------
// Integration tests MUST drive navigation using key-based finders only:
//   await tester.tap(find.byKey(const Key('login_submit')));
// Raw Ukrainian `find.text(...)` may be used for CONTENT ASSERTIONS only,
// never for tapping. Violations re-introduce the flake source the 17.1 suite
// removed. See app_harness.dart for the detailed policy note.

import 'dart:convert';

import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

// ---------------------------------------------------------------------------
// Fixed clock instant used by all E2E tests (Phase 17.1 seed)
// ---------------------------------------------------------------------------

/// Fixed "now" for every integration test — 2026-06-14 12:00:00 UTC.
///
/// Inject this into the harness via:
///   `clockProvider.overrideWithValue(() => kFixedNow)`
///
// This literal IS the injected clock, not a booking fixture. It is fixed BY
// DESIGN — every E2E flow's date arithmetic is deterministic precisely because
// "now" does not move. It never reaches `BookingDisplayX.isPast` (which
// deliberately reads the real device clock, not `clockProvider`), so it cannot
// become a stale-upcoming time bomb. Making it now-relative would destroy the
// determinism it exists to provide.
// future-date-ok: the injected fixed clock itself — see the note above.
final DateTime kFixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0);

/// The REAL device clock, captured once per process, as the anchor for every
/// "upcoming booking" fixture instant.
///
/// [kFixedNow] cannot serve that role: it is injected through `clockProvider`,
/// which the app's own presentation logic honours, but `BookingDisplayX.isPast`
/// deliberately compares `endAt` against `DateTime.now()` — the DEVICE instant,
/// not the injected one, because it is a presentation-only "has this slot
/// already passed" signal. So a fixture that must read as UPCOMING has to be in
/// the future of the REAL clock. Captured once so `bookingStartsAt` and
/// `bookingEndsAt` cannot drift apart across two separate `now()` reads.
/// TIME-OF-DAY IS PINNED, ONLY THE DATE ROLLS. The anchor is 15:00 UTC on a
/// future DATE — the exact wall-clock the retired `'2026-07-20T15:00:00Z'`
/// literal used, so nothing downstream changes except that the date can no
/// longer expire. A bare `DateTime.now()` anchor would have made the fixture's
/// time-of-day depend on when the suite happens to run, and a late-evening run
/// would push the 90-minute booking across midnight — quietly breaking the
/// day-scoped `from == to` assertions in `master_bookings_flow_test.dart`,
/// which is a worse failure mode than the bomb it replaces.
final DateTime _kFixtureDay = () {
  // instant-ok: deliberately the DEVICE clock — see the doc comment above
  final DateTime now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day, 15);
}();

/// An ISO-8601 UTC instant [offset] past [_kFixtureDay] — the now-relative
/// replacement for hand-rolled absolute future literals. See
/// [FakeBackend.bookingStartsAt] for the incident this prevents.
String _futureInstant(Duration offset) =>
    _kFixtureDay.add(offset).toIso8601String();

// ---------------------------------------------------------------------------
// Fixture personas (stable across the full test suite)
// ---------------------------------------------------------------------------

const Map<String, dynamic> _clientUserJson = <String, dynamic>{
  'id': 'user-client-1',
  'email': 'client@beautica.ua',
  'role': 'CLIENT',
  'firstName': 'Дмитро',
  'lastName': 'Клієнт',
};

const Map<String, dynamic> _ownerUserJson = <String, dynamic>{
  'id': 'user-owner-1',
  'email': 'owner@beautica.ua',
  'role': 'SALON_OWNER',
  'firstName': 'Оксана',
  'lastName': 'Власник',
};

const Map<String, dynamic> _masterUserJson = <String, dynamic>{
  'id': 'user-master-1',
  'email': 'master@beautica.ua',
  'role': 'INDEPENDENT_MASTER',
  'firstName': 'Олена',
  'lastName': 'Ковальчук',
};

/// Returns the stub JSON body for [UserRole] in `GET /users/me` shape.
Map<String, dynamic> userJsonForRole(UserRole role) {
  return switch (role) {
    UserRole.client => _clientUserJson,
    UserRole.salonOwner => _ownerUserJson,
    UserRole.independentMaster => _masterUserJson,
    _ => _masterUserJson,
  };
}

// ---------------------------------------------------------------------------
// Static helpers — standard API envelopes
// ---------------------------------------------------------------------------

Map<String, dynamic> _ok(Map<String, dynamic> data) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': data,
};

Map<String, dynamic> _okList(List<dynamic> data) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': data,
};

const Map<String, dynamic> _okVoid = <String, dynamic>{
  'success': true,
  'data': null,
  'message': 'ok',
};

/// Builds an `ApiResponse<AuthResponse>` envelope matching the backend wire
/// format.
///
/// `AuthResponse` (generated built_value) expects `userId`, `email`, and
/// `role` at the TOP LEVEL of `data` — NOT nested under a `user` sub-object.
/// Wire shape:
/// ```json
/// {
///   "success": true,
///   "data": {
///     "userId": "...",
///     "email":  "...",
///     "role":   "INDEPENDENT_MASTER",
///     "accessToken":  "...",
///     "refreshToken": "...",
///     "tokenType": "Bearer"
///   }
/// }
/// ```
/// The [user] map must contain `id`, `email`, and `role` keys (as produced
/// by the fixture personas above).
Map<String, dynamic> _authResponse(Map<String, dynamic> user) =>
    <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': <String, dynamic>{
        'userId': user['id'],
        'email': user['email'],
        'role': user['role'],
        'accessToken': 'fake-access-token',
        'refreshToken': 'fake-refresh-token',
        'tokenType': 'Bearer',
      },
    };

// ---------------------------------------------------------------------------
// FakeBackend
// ---------------------------------------------------------------------------

/// Stateful in-memory "backend" wired to a real [Dio] via [DioAdapter].
///
/// Each test creates a fresh instance so state never leaks between tests.
/// The [dio] field is the instance to inject into [dioProvider].
final class FakeBackend {
  FakeBackend({this.masterRowId = 'user-master-1'})
    : dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080')) {
    _adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = _adapter;
    // PARITY WITH PRODUCTION. `dioProvider` (lib/core/network/dio_provider.dart)
    // installs ErrorMapperInterceptor on every real Dio; without it here the
    // harness silently diverged from the app on EVERY non-2xx response.
    //
    // The interceptor is what parses a 400's `errors` map into
    // `ValidationFailure.fieldErrors`. Missing it, a 400 reached the repository
    // as a bare DioException with `error == null`, so `if (e.error is Failure)`
    // was false, `_mapDioException` returned `ValidationFailure(fieldErrors:
    // const {})`, and the per-field map was DISCARDED — screens that render
    // inline field errors fell through to their generic snackbar instead. That
    // made a working production path look broken in E2E (see
    // service_setup_field_error_flow_test.dart).
    //
    // Only ErrorMapperInterceptor is installed. AuthInterceptor / RefreshInterceptor
    // are deliberately omitted: FakeBackend accepts any token and never replies
    // 401, and RefreshInterceptor would need a live refresh endpoint + retry
    // queue that no flow exercises.
    dio.interceptors.add(ErrorMapperInterceptor());
    _wire();
  }

  /// The Master-ROW UUID that `GET /masters/me` reports for the authenticated
  /// master, and the id its review endpoints are keyed on. In PRODUCTION this
  /// DIFFERS from the User UUID (`user-master-1`): the `masters` table PK is an
  /// independently `@GeneratedValue` UUID, distinct from the `user_id` FK.
  ///
  /// The default keeps it equal to the User id so every existing flow is
  /// unchanged. The master-received-reviews flow overrides it with a DISTINCT
  /// value so the flow FAILS if the reviews screen keys its endpoints on
  /// `session.user.id` instead of the loaded profile's master-row id — turning
  /// the flow into a genuine guard for that correctness bug rather than a
  /// fixture-masked false pass.
  final String masterRowId;

  final Dio dio;
  late final DioAdapter _adapter;

  // ── Mutable master profile state ──────────────────────────────────────────

  /// The role currently "logged in" for this fake instance.
  /// Call [setCurrentRole] before asserting role-specific behaviour.
  UserRole currentRole = UserRole.independentMaster;

  String masterFirstName = 'Олена';
  String masterLastName = 'Ковальчук';
  String masterBio = 'Майстер манікюру.';
  String? masterPhone = '+380501111111';
  String? masterInstagram = '@olena_nails';

  /// Optional professional title returned by `GET /masters/me` and mutated
  /// by `PATCH /independent-masters/me/profile`. Starts null so flows that
  /// do not exercise this field see a clean seed. Set it to a non-null string
  /// BEFORE [_wire] if you need the initial profile to carry a title.
  String? masterProfessionalTitle;

  /// Optional address fields on `GET /masters/me` (the AUTHENTICATED master's
  /// OWN profile, distinct from the PUBLIC `_publicMasterDetailEnvelope()`
  /// used by the CLIENT-facing journey). All start null so every existing
  /// flow that hits `GET /masters/me` keeps seeing a clean, location-less
  /// seed — no location row renders on `MasterProfileScreen` for them. A flow
  /// exercising Phase 219/220/221 (the split address lines + tap-to-expand
  /// note) sets these BEFORE login/boot.
  String? masterCity;
  String? masterStreet;
  String? masterBuildingNo;
  String? masterLocationNote;

  // ── Mutable CLIENT profile state (PATCH /users/me round-trip) ──────────────
  //
  // The CLIENT `GET /users/me` echoes these mutable fields so a save made by the
  // Contacts / Location edit screens round-trips on the next read (the edit
  // screens invalidate clientEditProfileProvider → re-fetch /users/me). Phone +
  // location start empty so the edit screens see a clean seed; the city is
  // OPTIONAL for a CLIENT, so a null city must persist as a valid save.
  String clientFirstName = 'Дмитро';
  String clientLastName = 'Клієнт';
  String? clientPhone;
  // oblastId/oblastName are emitted on GET /users/me so the search-page
  // saved-location PREFILL can resolve the saved locality cascade (the prefill
  // requires BOTH oblastId and cityId non-null). They start null so the profile
  // edit flows keep seeing a clean, location-less seed; a flow that exercises the
  // prefill sets them (+ clientCityId/clientCityName) on the FakeBackend instance
  // BEFORE login.
  String? clientOblastId;
  String? clientOblastName;
  String? clientCityId;
  String? clientCityName;
  String? clientDistrictId;
  String? clientDistrictName;
  String? clientStreet;
  String? clientBuildingNo;
  String? clientLocationNote;

  // ── Service state ─────────────────────────────────────────────────────────

  /// In-memory services list. Starts pre-seeded.
  ///
  /// Shape MUST match the real `MasterServiceResponse` wire format:
  ///   `{ "id": ASSIGNMENT_UUID, "serviceDefinition": { "id": DEF_UUID, ... }, ... }`
  final List<Map<String, dynamic>> _services = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'assign-1',
      'masterId': 'user-master-1',
      'isActive': true,
      'priceType': 'FIXED',
      'priceMin': 400,
      'priceMax': null,
      'priceDisplay': '400 ₴',
      'effectiveDurationMinutes': 60,
      'serviceDefinition': <String, dynamic>{
        'id': 'svc-1',
        'name': 'Манікюр класичний',
        'description': null,
        'category': 'NAILS',
        'baseDurationMinutes': 60,
        'bufferMinutesAfter': 0,
        'isActive': true,
        'priceType': 'FIXED',
        'priceMin': 400,
        'priceMax': null,
        'priceDisplay': '400 ₴',
        'photoUrl': null,
      },
    },
    <String, dynamic>{
      'id': 'assign-2',
      'masterId': 'user-master-1',
      'isActive': true,
      'priceType': 'RANGE',
      'priceMin': 200,
      'priceMax': 350,
      'priceDisplay': 'від 200 до 350 ₴',
      'effectiveDurationMinutes': 45,
      'serviceDefinition': <String, dynamic>{
        'id': 'svc-2',
        'name': 'Брови корекція',
        'description': null,
        'category': 'FACE',
        'baseDurationMinutes': 45,
        'bufferMinutesAfter': 0,
        'isActive': true,
        'priceType': 'RANGE',
        'priceMin': 200,
        'priceMax': 350,
        'priceDisplay': 'від 200 до 350 ₴',
        'photoUrl': null,
      },
    },
    // Type-bearing service in NAILS (category A) with a serviceType belonging to
    // NAILS. Drives the Phase 16.5 edit-flow category-switch regression test: a
    // valid category↔serviceType pair on load. Its PATCH succeeds (200) so the
    // positive flow can submit after re-picking a type for the new category.
    <String, dynamic>{
      'id': 'assign-typed',
      'masterId': 'user-master-1',
      'isActive': true,
      'priceType': 'FIXED',
      'priceMin': 500,
      'priceMax': null,
      'priceDisplay': '500 ₴',
      'effectiveDurationMinutes': 60,
      'serviceTypeId': 'type-nails-classic',
      'serviceTypeNameUk': 'Класичний манікюр',
      'serviceDefinition': <String, dynamic>{
        'id': 'svc-typed',
        'name': 'Класичний манікюр',
        'description': null,
        'category': 'NAILS',
        'baseDurationMinutes': 60,
        'bufferMinutesAfter': 0,
        'isActive': true,
        'priceType': 'FIXED',
        'priceMin': 500,
        'priceMax': null,
        'priceDisplay': '500 ₴',
        'photoUrl': null,
        'serviceTypeId': 'type-nails-classic',
        'serviceTypeNameUk': 'Класичний манікюр',
      },
    },
    // Negative-path service: same valid NAILS + serviceType pair on load, but its
    // PATCH ALWAYS returns the backend's fieldless 400 mismatch envelope
    // ({success:false, message:"service type does not belong to the selected
    // category"} — NO `errors` map). Drives the regression assert that the form
    // maps that 400 to the localized inline `serviceTypeCategoryMismatch` error
    // (Phase 16.5 fix #3) rather than a raw English snackbar.
    <String, dynamic>{
      'id': 'assign-mismatch',
      'masterId': 'user-master-1',
      'isActive': true,
      'priceType': 'FIXED',
      'priceMin': 500,
      'priceMax': null,
      'priceDisplay': '500 ₴',
      'effectiveDurationMinutes': 60,
      'serviceTypeId': 'type-nails-classic',
      'serviceTypeNameUk': 'Класичний манікюр',
      'serviceDefinition': <String, dynamic>{
        'id': 'svc-mismatch',
        'name': 'Класичний манікюр',
        'description': null,
        'category': 'NAILS',
        'baseDurationMinutes': 60,
        'bufferMinutesAfter': 0,
        'isActive': true,
        'priceType': 'FIXED',
        'priceMin': 500,
        'priceMax': null,
        'priceDisplay': '500 ₴',
        'photoUrl': null,
        'serviceTypeId': 'type-nails-classic',
        'serviceTypeNameUk': 'Класичний манікюр',
      },
    },
  ];

  /// Service types per platform-category slug (Phase 16.5 picker source). The
  /// `GET /service-types?categoryName=` route returns the slice for the queried
  /// category — so a category switch genuinely repopulates the list and a type
  /// from category A is never offered under category B. Shape matches
  /// PlatformServiceTypeResponse { id, slug, nameUk, categoryName }.
  static List<Map<String, dynamic>> _serviceTypesFor(String category) {
    switch (category) {
      case 'NAILS':
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'type-nails-classic',
            'slug': 'CLASSIC_MANICURE',
            'nameUk': 'Класичний манікюр',
            'categoryName': 'NAILS',
          },
          // Second NAILS service type (Phase 13.11) — gives the search drawer two
          // selectable chips so the per-service filter E2E can prove a TWO-slug
          // selection assembles two repeated `serviceTypeSlugs` params on the wire.
          <String, dynamic>{
            'id': 'type-nails-gel',
            'slug': 'GEL_MANICURE',
            'nameUk': 'Манікюр гель-лак',
            'categoryName': 'NAILS',
          },
        ];
      case 'BROWS':
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'type-brows-correction',
            'slug': 'BROW_CORRECTION',
            'nameUk': 'Корекція брів',
            'categoryName': 'BROWS',
          },
        ];
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  /// Slug → Ukrainian display name, mirroring [_serviceTypesFor]. Used to echo a
  /// realistic `matchedServiceNames` slice (≤3) for whatever `serviceTypeSlugs`
  /// the search carried — see [_withMatchedNames].
  static const Map<String, String> _serviceTypeNameUk = <String, String>{
    'CLASSIC_MANICURE': 'Класичний манікюр',
    'GEL_MANICURE': 'Манікюр гель-лак',
    'BROW_CORRECTION': 'Корекція брів',
  };

  /// Reads the `serviceTypeSlugs` multi-valued param off the FLAT search query
  /// map. The repository sends a `List<String>` value (Dio `ListFormat.multi` →
  /// repeated bare params), so the DioAdapter handler sees the raw list. A single
  /// value is normalised to a one-element list; absent → null (no constraint).
  static List<String>? _slugsFrom(Map<String, dynamic> query) {
    final raw = query['serviceTypeSlugs'];
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((Object? e) => e.toString()).toList(growable: false);
    }
    return <String>[raw.toString()];
  }

  /// Injects a backend-style `matchedServiceNames` (≤3) onto each result row when
  /// the search carried a `serviceTypeSlugs` filter — mirroring the real backend
  /// contract (matched names populated ONLY when filtering). Without slugs the
  /// rows are returned unchanged (no key → null matched line → the card falls
  /// back to the generic `serviceNames`).
  static List<Map<String, dynamic>> _withMatchedNames(
    List<Map<String, dynamic>> rows,
    List<String>? slugs,
  ) {
    if (slugs == null || slugs.isEmpty) return rows;
    final List<String> matched = slugs
        .map((String s) => _serviceTypeNameUk[s] ?? s)
        .take(3)
        .toList(growable: false);
    return rows
        .map(
          (Map<String, dynamic> r) => <String, dynamic>{
            ...r,
            'matchedServiceNames': matched,
          },
        )
        .toList(growable: false);
  }

  int _nextServiceSeq = 3;

  // ── Schedule ID sequence (deterministic — never wall-clock) ──────────────
  // Starts at 100 to avoid collision with the seeded 'schedule-1'.
  int _scheduleSeq = 100;

  // ── Schedule state ────────────────────────────────────────────────────────

  /// Weekly schedule in the `WeeklyScheduleResponse` wire format:
  /// `{ id, validFrom, validTo, days: [{ dayOfWeek, intervals: [{startTime,
  /// endTime}] }] }`.
  ///
  /// The seeded entry has Monday (dayOfWeek=1) AND Tuesday (dayOfWeek=2) active
  /// with 09:00–18:00 intervals. Two active days are intentional: when the test
  /// toggles Monday OFF, Tuesday remains active → allOff=false → the editor
  /// calls upsertWeeklySchedule(scheduleId='schedule-1') → PUT. If only Monday
  /// were active, toggling it OFF would make allOff=true → DELETE path instead.
  List<Map<String, dynamic>> _weeklySchedule = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'schedule-1',
      'validFrom': '2026-06-14',
      'validTo': null,
      'days': <Map<String, dynamic>>[
        <String, dynamic>{
          'dayOfWeek': 1,
          'intervals': <Map<String, dynamic>>[
            <String, dynamic>{'startTime': '09:00', 'endTime': '18:00'},
          ],
        },
        <String, dynamic>{
          'dayOfWeek': 2,
          'intervals': <Map<String, dynamic>>[
            <String, dynamic>{'startTime': '09:00', 'endTime': '18:00'},
          ],
        },
        <String, dynamic>{'dayOfWeek': 3, 'intervals': <dynamic>[]},
        <String, dynamic>{'dayOfWeek': 4, 'intervals': <dynamic>[]},
        <String, dynamic>{'dayOfWeek': 5, 'intervals': <dynamic>[]},
        <String, dynamic>{'dayOfWeek': 6, 'intervals': <dynamic>[]},
        <String, dynamic>{'dayOfWeek': 7, 'intervals': <dynamic>[]},
      ],
    },
  ];

  /// Clears the seeded weekly schedule so `GET …/weekly-schedules` returns an
  /// empty list — the NO_SCHEDULE / FIRST-CREATE state. Drives the Bug 2
  /// first-create flow (back-without-save must not persist; Save creates exactly
  /// one template). Call BEFORE the editor loads. The POST/PUT counters
  /// (`postScheduleCalls` / `putScheduleCalls`) keep recording, so a test can
  /// assert ZERO upserts on a back-without-save and exactly ONE on a Save.
  void seedNoWeeklySchedule() => _weeklySchedule = <Map<String, dynamic>>[];

  /// Phase 244 — `GET …/effective-schedule` is registered ONCE below,
  /// unconditionally returning an EMPTY list (every date resolves to
  /// NO_SCHEDULE) unless this is set. `null` (the default, and every
  /// pre-existing flow's behaviour) preserves that byte-for-byte. Set it to
  /// seed the master booking timeline's working-hours-window feature: each
  /// entry is one `EffectiveDayResponse` JSON map — see
  /// [seedEffectiveScheduleDay] for a convenience builder. Query params
  /// (`from`/`to`) are ignored, same as every other route in this file — the
  /// whole seeded list is returned for any range requested.
  List<Map<String, dynamic>>? _effectiveScheduleOverride;

  /// Seeds `GET …/effective-schedule` to return exactly [days] instead of the
  /// default empty list.
  void seedEffectiveSchedule(List<Map<String, dynamic>> days) =>
      _effectiveScheduleOverride = days;

  /// Builds one `EffectiveDayResponse` JSON entry for [seedEffectiveSchedule]
  /// — an INTERVAL day (never EXPLICIT_TIMES) with a single working interval
  /// `[startTime, endTime)` when [intervals] is omitted, or a settled day-off
  /// (`OVERRIDE_DAY_OFF`, empty intervals) when [dayOff] is `true`.
  static Map<String, dynamic> seedEffectiveScheduleDay(
    DateTime date, {
    bool dayOff = false,
    List<(String start, String end)> intervals = const <(String, String)>[
      ('09:00:00', '18:00:00'),
    ],
  }) => <String, dynamic>{
    'date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'source': dayOff ? 'OVERRIDE_DAY_OFF' : 'TEMPLATE',
    'intervals': dayOff
        ? const <dynamic>[]
        : <Map<String, dynamic>>[
            for (final (String start, String end) in intervals)
              <String, dynamic>{'startTime': start, 'endTime': end},
          ],
    'times': const <dynamic>[],
    'windowStart': null,
    'windowEnd': null,
  };

  /// Reseeds the weekly schedule so MONDAY carries a STORED WORKING WINDOW
  /// (`windowStart`/`windowEnd`, added to the contract 2026-07-27).
  ///
  /// Monday's canonical intervals are `[10:00–18:00]` while its stored window is
  /// `09:00–18:00` — i.e. the master saved a «Перерва» 09:00–10:00 flush against
  /// the window START. That is the exact row the backend now persists, and the
  /// row the editor must re-render as a WINDOW + BREAK rather than as a
  /// shortened 10:00–18:00 working day.
  ///
  /// Tuesday stays an ordinary LEGACY row (intervals only, no window) so the
  /// same run also proves the legacy regime still renders unchanged, and so
  /// closing Monday never trips the all-off DELETE path.
  void seedWeeklyScheduleWithStoredWindow() =>
      _weeklySchedule = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'schedule-1',
          'validFrom': '2026-06-14',
          'validTo': null,
          'days': <Map<String, dynamic>>[
            <String, dynamic>{
              'dayOfWeek': 1,
              'intervals': <Map<String, dynamic>>[
                <String, dynamic>{
                  'startTime': '10:00:00',
                  'endTime': '18:00:00',
                },
              ],
              'windowStart': '09:00:00',
              'windowEnd': '18:00:00',
            },
            <String, dynamic>{
              'dayOfWeek': 2,
              'intervals': <Map<String, dynamic>>[
                <String, dynamic>{
                  'startTime': '09:00:00',
                  'endTime': '18:00:00',
                },
              ],
            },
            <String, dynamic>{'dayOfWeek': 3, 'intervals': <dynamic>[]},
            <String, dynamic>{'dayOfWeek': 4, 'intervals': <dynamic>[]},
            <String, dynamic>{'dayOfWeek': 5, 'intervals': <dynamic>[]},
            <String, dynamic>{'dayOfWeek': 6, 'intervals': <dynamic>[]},
            <String, dynamic>{'dayOfWeek': 7, 'intervals': <dynamic>[]},
          ],
        },
      ];

  // ── Call-count telemetry (for assertions in tests) ────────────────────────

  int loginCalls = 0;
  int logoutCalls = 0; // POST /api/v1/auth/logout counter
  int registerCalls = 0;
  int verifyEmailCalls = 0;

  // ── Beautica OTP task (Phase B) — password-reset OTP flow counters ────────

  /// `POST /api/v1/auth/forgot-password` call count + the last requested email.
  int forgotPasswordCalls = 0;
  String? lastForgotPasswordEmail;

  /// `POST /api/v1/auth/verify-password-reset-otp` call count + the last
  /// email/code submitted. Always succeeds with [resetTicketToIssue] unless
  /// [passwordResetOtpResult] is overridden.
  int verifyPasswordResetOtpCalls = 0;
  String? lastVerifyPasswordResetOtpEmail;
  String? lastVerifyPasswordResetOtpCode;

  /// The `resetTicket` value the fake `verify-password-reset-otp` endpoint
  /// returns on success.
  String resetTicketToIssue = 'fake-reset-ticket';

  /// `POST /api/v1/users/me/change-password/request-otp` call count
  /// (authenticated entry point).
  int requestChangePasswordOtpCalls = 0;

  /// `POST /api/v1/auth/reset-password` call count + the last resetTicket /
  /// newPassword submitted.
  int resetPasswordCalls = 0;
  String? lastResetPasswordTicket;
  String? lastResetPasswordNewPassword;

  int getMeCalls = 0; // GET /api/v1/users/me counter

  /// `GET /api/v1/clients/me/passport` call counter (Phase 13.8 wire-up).
  int getPassportCalls = 0;

  /// Body served by `GET /api/v1/clients/me/passport`. Defaults to the passport
  /// of a client with NO derived history: empty lists, no budget band,
  /// `bookingsConsidered: 0`. Replace wholesale in a flow to serve a populated
  /// one.
  ///
  /// `memberSinceYear` IS REQUIRED AND MUST STAY. `PassportMapper` THROWS on a
  /// payload that omits it (Phase 235 removed the `DateTime.now().year`
  /// fabrication that used to paper over exactly this), so a body without it
  /// makes the passport section render its ERROR card rather than any data
  /// state — a fake-backend defect that would look like a screen bug. It is a
  /// fixed literal on purpose: deriving it from the host clock would be the
  /// clock-mixing trap (`kFixedNow` pins the app's clock, the host does not).
  ///
  /// `favoriteCities` and `reviewsWritten` are likewise always present: the
  /// rebuilt page (Phase 238) renders both — the cities on the derived block's
  /// locality line, the review count in the identity strip's counter column.
  Map<String, dynamic> passportBody = <String, dynamic>{
    'favoriteDistricts': <String>[],
    'favoriteCities': <String>[],
    'budget': null,
    'bookingsConsidered': 0,
    'reviewsWritten': 0,
    'memberSinceYear': 2021,
  };

  /// `GET /api/v1/favorites/services` call counter — the BEAUTY WISH LIST feed
  /// (backend 247, mobile Phase 237).
  int listServiceFavoritesCalls = 0;

  /// Rows served by `GET /api/v1/favorites/services`. Defaults to EMPTY, which
  /// drives the wish-list section's empty state. Replace wholesale in a flow.
  ///
  /// Each row is a `FavoriteServiceResponse`: `masterServiceId`, `masterId`,
  /// `serviceName`, `masterFirstName`, `masterLastName`, `durationMinutes`,
  /// `priceType` (`FIXED` | `RANGE`), `priceMin`, `priceMax`, `priceDisplay`.
  List<Map<String, dynamic>> favoriteServiceRows = <Map<String, dynamic>>[];
  int patchMeCalls = 0; // PATCH /api/v1/users/me counter (CLIENT profile edit)
  Map<String, dynamic>?
  lastPatchMeBody; // body of the most recent PATCH /users/me
  int getMasterCalls = 0;

  /// `GET /api/v1/masters/{masterId}` (PUBLIC detail, Phase 13.5) call count +
  /// the id requested. Distinct from [getMasterCalls] (the master-only
  /// `GET /masters/me`): a CLIENT viewing a public profile hits THIS route, never
  /// `me`. The public-master-profile E2E asserts a non-zero count here AND a zero
  /// [getMasterCalls] (proving the CLIENT path never touched the 403-only `me`).
  int getPublicMasterCalls = 0;
  String? lastGetPublicMasterId;

  /// `GET /api/v1/masters/{masterId}/services` (PUBLIC services, Phase 13.5)
  /// call count + the id requested. Feeds the public profile's services-count
  /// stat tile.
  int getPublicMasterServicesCalls = 0;
  String? lastGetPublicMasterServicesId;

  /// `GET /api/v1/masters/{masterId}/slots` (Phase 14.1 slot picker) call
  /// count. The DioAdapter route match is path-only, so this increments once
  /// per date the client picks on `SlotDateScreen` — used by the booking-flow
  /// E2E to assert the day tap actually hit the network instead of rendering
  /// stale state.
  int getMasterSlotsCalls = 0;

  /// `GET /api/v1/masters/{masterId}/working-days` (Phase 14.14 calendar
  /// day-availability gate) call count — incremented once per distinct
  /// `WorkingDaysQuery` (masterId + visible-month range) `SlotDateScreen`
  /// resolves. Used by the booking-flow E2E to assert the gate actually hit
  /// the real network before the day cell becomes tappable.
  int getWorkingDaysCalls = 0;

  /// When set, [_workingDaysEnvelope] reports THIS single date-only day as
  /// `working: false` (every other day in the response window stays
  /// `working: true`, same as the unconditional default). Lets an E2E test
  /// force a specific, real-network-resolved day to be non-working WITHOUT
  /// hand-rolling a whole new envelope — used by the "non-working day is
  /// inert end-to-end" flow (Phase 14.14 QA gap-fix) to mark "today" itself
  /// non-working so the negative assertion is 100% real-world-date-safe (no
  /// month-boundary edge case from picking a relative "tomorrow"/"last day
  /// of month" day).
  DateTime? forceNonWorkingDate;

  /// Like [forceNonWorkingDate], but reports the day `working: false` ONLY
  /// when the working-days request carried a `serviceId` (the backend's
  /// AVAILABILITY-AWARE mode). A request WITHOUT a serviceId (schedule-shape
  /// mode) still sees it `working: true`. This models the exact backend
  /// behaviour the Phase 14.20 fix relies on, so an E2E test can prove the
  /// booking calendar now threads the chosen service's id into the query:
  /// old, schedule-shape code (no serviceId) would resolve the day working and
  /// dead-end on «Немає вільного часу»; the fixed code sends the serviceId and
  /// the day is disabled up front.
  DateTime? forceNonWorkingDateWhenServiceScoped;

  /// The `serviceId` query param the MOST RECENT `master-aaa/working-days`
  /// request carried (`null` when absent = schedule-shape mode). Lets the
  /// booking-flow E2E assert the calendar threads `services.first.id` into the
  /// working-days query — the Phase 14.20 wiring under test.
  String? lastMasterAaaWorkingDaysServiceId;

  /// The FULL, ordered `serviceId` list the most recent
  /// `master-aaa/working-days` request carried (`null` when the param was
  /// absent = schedule-shape mode). [lastMasterAaaWorkingDaysServiceId] is the
  /// scalar view of the same read and is kept because existing assertions
  /// depend on it; this field is what makes the MULTI-service selection
  /// assertable — the generated client sends `serviceId` as a repeated param,
  /// so a multi-service booking threads N ids and the scalar view silently
  /// keeps only the first.
  List<String>? lastMasterAaaWorkingDaysServiceIds;

  /// `GET /api/v1/salons/{salonId}/services/{serviceDefId}/masters` call
  /// count (Phase 23.x bookable-masters rewire) — the salon booking flow's
  /// `salonMasterServiceCoverageProvider` now calls this ONCE PER SELECTED
  /// SERVICE instead of fanning `GET /masters/{id}/services` out over the
  /// WHOLE roster (the pre-rewire Phase 14.13 shape). [requestedBookable
  /// MastersServiceDefIds] records WHICH `serviceDefId`s were actually
  /// queried, so the E2E can assert the call count scales with the CLIENT's
  /// selection (2 selected services -> 2 calls, roster size irrelevant),
  /// never with the 8-master roster.
  int getBookableMastersCalls = 0;
  final Set<String> requestedBookableMastersServiceDefIds = <String>{};

  /// The `serviceId` query param the salon time-picker's real
  /// `GET /masters/{masterId}/slots` request carried for `master-ccc` /
  /// `master-ddd` respectively — bugfix regression guard (Phase 14.16/14.17
  /// masterService-not-found fix). [_bookableMasterEnvelope]'s fixture
  /// `masterServiceId` (`assign-<masterId>-<serviceDefId>`, the per-master
  /// ASSIGNMENT id) is deliberately DIFFERENT from the salon-wide CATALOG id
  /// (e.g. `salon-svc-shared`) — exactly like production, where
  /// `master_services.id` is never equal to `service_definitions.id`. The
  /// original bug sent the catalog id here, 404ing server-side with
  /// "masterService not found"; the salon-booking E2E below asserts this
  /// equals the ASSIGNMENT id, never the catalog id.
  String? lastMasterCccSlotsServiceId;
  String? lastMasterDddSlotsServiceId;

  // ── Public salon profile telemetry (Phase 13.6) ───────────────────────────
  //
  // Five independent read endpoints back the "Про салон" hero + the 4-tab
  // switcher — each tab loads via its own provider, so a broken tab must not
  // blank the others. Every counter below is bumped by its own route handler
  // and paired with the id/sort the request carried, mirroring the public
  // master profile's [getPublicMasterCalls]/[lastGetPublicMasterId] pattern.

  /// `GET /api/v1/salons/{salonId}` — salon detail (hero card).
  int getSalonByIdCalls = 0;
  String? lastGetSalonId;

  /// `GET /api/v1/salons/{salonId}/masters` — masters rail ("Майстри" tab).
  int getSalonMastersCalls = 0;
  String? lastGetSalonMastersId;

  /// `GET /api/v1/salons/{salonId}/services` — service catalogue ("Послуги").
  int getSalonServiceCatalogCalls = 0;
  String? lastGetSalonServiceCatalogId;

  /// `GET /api/v1/salons/{salonId}/reviews/summary` — rating summary header.
  int getSalonReviewSummaryCalls = 0;
  String? lastGetSalonReviewSummaryId;

  /// `GET /api/v1/salons/{salonId}/reviews?sort=` — reviews list. Records the
  /// last `sort` wire value so a sort-change test can assert the re-fetch
  /// carried the new value.
  int getSalonReviewsCalls = 0;
  String? lastGetSalonReviewsSort;

  /// `GET /api/v1/masters/{masterRowId}/reviews/summary` — master received-
  /// reviews header (Phase 4.5/4.6). Keyed on [masterRowId], the master-row id.
  int getMasterReviewSummaryCalls = 0;

  /// `GET /api/v1/masters/{masterRowId}/reviews?sort=` — master received-reviews
  /// list. Records the last `sort` wire value so a sort-change test asserts the
  /// re-fetch carried the new value; the fake reorders the fixture per sort so
  /// the reorder is observable end-to-end.
  int getMasterReviewsCalls = 0;
  String? lastGetMasterReviewsSort;

  /// WRONG-ID counters: hits to the review endpoints keyed on the USER id
  /// (`user-master-1`) — the id the buggy screen would use. In a correctly
  /// fixed screen these stay 0; a non-zero value is the fingerprint of the
  /// `session.user.id`-vs-`master.id` bug. Only reachable when [masterRowId]
  /// is overridden to differ from the User id.
  int getMasterReviewSummaryWrongIdCalls = 0;
  int getMasterReviewsWrongIdCalls = 0;

  /// `GET /api/v1/masters/master-aaa/reviews/summary` — PUBLIC master reviews
  /// header (Phase 4.x `PublicMasterReviewsScreen`), reached by tapping the
  /// public profile's «Відгуки» stat tile. Kept DISTINCT from
  /// [getMasterReviewSummaryCalls] (the `masterRowId`-keyed AUTHENTICATED
  /// master's own-reviews route) so a CLIENT's public-reviews journey can
  /// assert it never touches the self route (and vice versa).
  int getPublicMasterReviewSummaryCalls = 0;

  /// `GET /api/v1/masters/master-aaa/reviews?sort=` — PUBLIC master reviews
  /// list. Records the last sort wire value for parity with the self-route
  /// counter above.
  int getPublicMasterReviewsCalls = 0;
  String? lastGetPublicMasterReviewsSort;

  /// `GET /api/v1/salons/{salonId}/portfolio` — real photo rail on the "Про
  /// салон" tab (previously an unwired endpoint — see
  /// `salon_portfolio_notifier.dart`). Goes through the GENERATED
  /// `MediaControllerApi` client, unlike the hand-rolled Pageable reads above.
  int getSalonPortfolioCalls = 0;
  String? lastGetSalonPortfolioId;

  /// `salon-xyz`'s `locationNote` on the PUBLIC salon-detail envelope
  /// (`_publicSalonDetailEnvelope`). Mutable (mirrors [masterLocationNote])
  /// so a flow can swap in an oversized note BEFORE boot to pin the Phase
  /// 223 (b) regression — a `locationNote` long enough to have evicted the
  /// street address off the OLD combined hero line must no longer be able to
  /// do so now that it renders only on the About tab. Defaults to the
  /// original short fixture value so every existing assertion against it is
  /// unaffected.
  String salonLocationNote = '2 поверх';

  int patchProfileCalls = 0;
  Map<String, dynamic>? lastPatchBody;
  int getServicesCalls = 0;
  int createServiceCalls = 0;

  /// Count of `POST /independent-masters/me/services/bulk` (first-time setup)
  /// calls, and the exact `items` list of the last one — lets a flow prove the
  /// bulk-save actually reached the network (vs. being blocked client-side).
  int bulkCreateCalls = 0;
  List<dynamic>? lastBulkItems;

  /// When true, the bulk-setup route replies HTTP 400 with a per-field error
  /// envelope (`errors: {"items[<i>].durationMinutes": …}`) for the item index
  /// in [bulkRejectItemIndex], mirroring the backend's `@Max(480)` per-item
  /// validation. Off by default so every OTHER flow's bulk save (none today)
  /// stays a clean 201.
  ///
  /// RE-WIRES ON WRITE — see [createRejectDuplicate] for why a plain field
  /// cannot work here (`onRoute` freezes the status code at registration time).
  bool get bulkRejectDurationField => _bulkRejectDurationField;
  set bulkRejectDurationField(bool value) {
    _bulkRejectDurationField = value;
    _wireBulkCreateServices();
  }

  bool _bulkRejectDurationField = false;
  int bulkRejectItemIndex = 0;

  /// When true, the bulk-setup route replies HTTP **409** with the typed
  /// `{ data: { code: "DUPLICATE_SERVICE", serviceName: null,
  /// existingServiceDefId } }` envelope instead of the default 200 — one item in
  /// the batch names a service the master already offers, so the backend rolled
  /// the WHOLE batch back (the endpoint is all-or-nothing; nothing was written).
  ///
  /// Since `beautica-backend` c5e420f made bulk create ADDITIVE, a 409 on this
  /// route means exactly this one thing, which is why the repository's
  /// `_mapBulkCreateException` decodes it straight to [ServiceDuplicateFailure]
  /// and `ServiceSetupScreen._save` surfaces it as a SNACKBAR while KEEPING the
  /// master on the screen with their selection intact. `serviceName` is null on
  /// the bulk envelope (the backend does not name the offender there), so the
  /// failure renders its plain `serviceErrDuplicate` copy.
  ///
  /// RE-WIRES ON WRITE — DO NOT COLLAPSE BACK INTO A PLAIN FIELD. See
  /// [createRejectDuplicate] for the full explanation: `replyCallback` captures
  /// its status code at REGISTRATION time, so a plain `bool` read inside [_wire]
  /// is always still `false` and flipping it later changes only the BODY —
  /// leaving the status at 200, which the repository reads as a SUCCESS. The
  /// flow then fails on the missing error copy, pointing at the screen instead
  /// of at this fake.
  bool get bulkRejectDuplicate => _bulkRejectDuplicate;
  set bulkRejectDuplicate(bool value) {
    _bulkRejectDuplicate = value;
    _wireBulkCreateServices();
  }

  bool _bulkRejectDuplicate = false;

  /// The `existingServiceDefId` the bulk duplicate-409 envelope reports. Threaded
  /// through so a flow can assert the typed field survives the decode; the screen
  /// renders the localized copy regardless of its value.
  String bulkDuplicateExistingServiceDefId = 'def-existing-bulk';

  /// When true, the single-create route
  /// (`POST /independent-masters/me/services`) replies HTTP 409 with the typed
  /// `{ data: { code: "DUPLICATE_SERVICE", serviceName, existingServiceDefId } }`
  /// envelope instead of the default 201 — the service the master tried to add is
  /// already in their menu. Drives the repository's
  /// `_mapServiceWriteException` → [ServiceDuplicateFailure] → inline
  /// service-type error on the form (NOT the generic errServer snackbar, and NO
  /// pop). Off by default so every other flow's create stays a clean 201.
  ///
  /// RE-WIRES ON WRITE — DO NOT COLLAPSE BACK INTO A PLAIN FIELD
  /// ------------------------------------------------------------
  /// `DioAdapter.onRoute` invokes its `MockServerCallback` IMMEDIATELY, at
  /// registration time (`http_mock_adapter/src/mixins/request_handling.dart`,
  /// `requestHandlerCallback(matcher)`), and `replyCallback(statusCode, data)`
  /// captures `statusCode` right there — only `data` stays lazy per-request.
  /// So the original `replyCallback(createRejectDuplicate ? 409 : 201, …)`
  /// evaluated the ternary inside [_wire] (called from the constructor), where
  /// the flag is ALWAYS still false. Flipping it afterwards changed the BODY to
  /// the DUPLICATE_SERVICE envelope but left the status at **201** — so
  /// `HttpServiceRepository.create` saw a success, `_mapServiceWriteException`
  /// never ran, and the flow could never observe [ServiceDuplicateFailure]. The
  /// duplicate E2E was silently un-armed (it failed on the missing inline copy,
  /// pointing at the screen rather than at this fake).
  ///
  /// Writing through a setter re-registers the route with the status the flag
  /// now implies. `Recording.mockResponse` scans ALL matchers and keeps the
  /// LAST one that matches, and `RequestMatcher` has no `==` override (identity
  /// equality → `indexOf` returns the real index), so the freshly-appended
  /// registration deterministically wins over the constructor's.
  bool get createRejectDuplicate => _createRejectDuplicate;
  set createRejectDuplicate(bool value) {
    _createRejectDuplicate = value;
    _wireCreateService();
  }

  bool _createRejectDuplicate = false;

  /// The `serviceName` the duplicate-409 envelope reports (the clashing service's
  /// display name). Threaded through so a flow can assert the typed field survives
  /// the decode; the form renders the localized copy regardless of its value.
  String createDuplicateServiceName = 'Класичний манікюр';

  /// Test-support: empties the pre-seeded services list so
  /// `GET /api/v1/independent-masters/me/services` returns `[]`. Used by flows
  /// that must exercise the zero-services empty state (e.g. the master-home
  /// «Додати послуги» CTA). Call BEFORE `AppHarness.boot` / before the master
  /// profile's services section resolves.
  void clearServices() => _services.clear();
  Map<String, dynamic>? lastCreatedService;
  int patchServiceCalls = 0;
  Map<String, dynamic>? lastPatchedService;

  /// Body of the most recent PATCH against the type-bearing service
  /// (`svc-typed`) — lets the edit-flow regression test assert the EXACT
  /// `serviceTypeId` / `categoryName` the form submitted after a category switch.
  Map<String, dynamic>? lastTypedPatchBody;

  /// Count of `GET /service-types` calls + the last `categoryName` queried.
  /// Proves the picker re-queried the new category after a switch (Phase 16.5).
  int getServiceTypesCalls = 0;
  String? lastServiceTypesCategory;
  int getScheduleCalls = 0;
  int postScheduleCalls = 0;
  int putScheduleCalls = 0;

  /// The `days` list from the most recent weekly-schedule POST/PUT body —
  /// each entry is `{ dayOfWeek, mode?, intervals?, times? }`. Lets a test
  /// assert the EXACT mode + discrete times the editor serialised (Phase 15.8).
  List<dynamic>? lastWeeklyDays;

  /// The `validFrom` / `validTo` strings from the most recent weekly-schedule
  /// POST/PUT body. Lets a first-create test assert the editor persisted the
  /// PICKED validity window (not a fabricated open-ended default).
  String? lastWeeklyValidFrom;
  String? lastWeeklyValidTo;

  // ── Support-contact telemetry ─────────────────────────────────────────────
  /// Number of `POST /api/v1/support/contact` calls the fake accepted (202).
  int supportContactCalls = 0;

  // ── Discovery search telemetry (Phase 13.4) ───────────────────────────────
  /// `GET /api/v1/search/masters` call count + the last `page` requested.
  int searchMastersCalls = 0;
  int? lastSearchMastersPage;

  /// The last `q` (free-text) + `sort` carried on a `/search/masters` request
  /// (Phase 19.x search wire-up). Null until the first call / when omitted.
  String? lastSearchMastersQuery;
  String? lastSearchMastersSort;

  /// The last FLAT `location.cityId` / `location.districtId` the repository sent
  /// on a `/search/masters` request. Null when the filter was absent. Proves the
  /// city scope reaches the wire as a FLAT @ModelAttribute key (the city-filter
  /// wire-format regression) — a bracket-nested `request[location][cityId]` would
  /// leave these null and an all-regions result would slip through.
  String? lastSearchMastersCityId;
  String? lastSearchMastersDistrictId;

  /// The last `serviceTypeSlugs` multi-valued param the repository sent on a
  /// `/search/masters` request (Phase 13.11 per-service filter). Null when no
  /// service chip was selected (the param is omitted) — so a non-null list with
  /// the selected slugs proves the chip selection reached the wire AND a stale
  /// cross-category slug was dropped on a category switch.
  List<String>? lastSearchMastersServiceTypeSlugs;

  /// The FULL decoded FLAT query map from the most recent `/search/masters`
  /// request — every key the backend's `@ModelAttribute` binder would see in
  /// ONE place (`q`, `sort`, `category`, `location.cityId`,
  /// `location.districtId`, `minPrice`, `maxPrice`, `minRating`,
  /// `serviceTypeSlugs`, `page`, `size`). The individual `lastSearchMasters*`
  /// fields above each capture a single facet in isolation, which is enough to
  /// prove a facet reached the wire AT ALL, but NOT that several facets
  /// travelled TOGETHER on the SAME request — two flows could each set one
  /// field on two different calls and a test comparing them would be
  /// comparing across requests, not within one. This field exists so a single
  /// assertion block can pull `q` + `location.cityId` + `category` +
  /// `maxPrice` off ONE map and prove simultaneity (the "search term resets my
  /// other filters" regression class).
  Map<String, dynamic>? lastSearchMastersQueryMap;

  /// `GET /api/v1/search/salons` call count + the last `page` requested.
  int searchSalonsCalls = 0;
  int? lastSearchSalonsPage;

  /// The last `q` (free-text) + `sort` carried on a `/search/salons` request.
  String? lastSearchSalonsQuery;
  String? lastSearchSalonsSort;

  /// The last FLAT `location.cityId` / `location.districtId` on a
  /// `/search/salons` request. See [lastSearchMastersCityId].
  String? lastSearchSalonsCityId;
  String? lastSearchSalonsDistrictId;

  /// The last `serviceTypeSlugs` multi-valued param on a `/search/salons`
  /// request. See [lastSearchMastersServiceTypeSlugs].
  List<String>? lastSearchSalonsServiceTypeSlugs;

  /// The FULL decoded FLAT query map from the most recent `/search/salons`
  /// request. See [lastSearchMastersQueryMap] — the salon-endpoint twin, used
  /// to prove the SAME set of facets travelled together on this endpoint too.
  Map<String, dynamic>? lastSearchSalonsQueryMap;

  // ── Favorites telemetry (Phase 13.4) ──────────────────────────────────────
  /// `POST /api/v1/favorites` (add) call count + the most recent body.
  int addFavoriteCalls = 0;
  Map<String, dynamic>? lastAddFavoriteBody;

  /// `DELETE /api/v1/favorites` (remove) call count + the most recent query.
  int removeFavoriteCalls = 0;
  Map<String, dynamic>? lastRemoveFavoriteQuery;

  /// `DELETE /api/v1/favorites` failure override. `null` (default) keeps the
  /// idempotent 204. Set via [forceRemoveFavoriteFailure] — never assign
  /// directly, since a status change needs the route RE-REGISTERED (see that
  /// method's doc).
  int? _removeFavoriteFailureStatusCode;

  /// Makes the NEXT (and every subsequent) `DELETE /api/v1/favorites`
  /// answer [statusCode] instead of the default 204 — e.g. to simulate a
  /// FAILED un-favourite. Call again with `null` to restore the default.
  ///
  /// A re-registration hook, not a mutable field the route reads lazily:
  /// `http_mock_adapter`'s `replyCallback` bakes its status code in as a
  /// fixed `int` argument AT REGISTRATION time (never a per-request
  /// callback), so changing the status requires calling `_adapter.onRoute`
  /// again for the same path — which wins because [Recording.mockResponse]
  /// resolves to the LAST matching entry in `history`, not the first.
  /// Mirrors `_wireCreateService`'s identical `_createRejectDuplicate` +
  /// re-registration precedent elsewhere in this file.
  void forceRemoveFavoriteFailure(int? statusCode) {
    _removeFavoriteFailureStatusCode = statusCode;
    _wireRemoveFavorite();
  }

  // ── Override telemetry (Phase 15.8) ───────────────────────────────────────
  int putOverrideCalls = 0;

  /// The most recent override PUT body — `{ date, kind, mode?, intervals?,
  /// times? }`. Lets a test assert the override the editor serialised.
  Map<String, dynamic>? lastOverrideBody;

  // ── Override booking-conflict preview telemetry (2026-07-26 design) ────────
  /// `POST /api/v1/masters/{masterId}/overrides/conflicts` call count.
  int previewConflictsCalls = 0;

  /// The most recent conflict-preview request body — `{ from, to, kind, mode?,
  /// intervals?, times? }`.
  Map<String, dynamic>? lastConflictQueryBody;

  /// Conflicts the NEXT `previewConflicts` call(s) report — wire-shaped rows
  /// `{ bookingId, appointmentId, date, startsAt, endsAt, clientDisplayName,
  /// serviceName }`. Empty by default (no conflicts), so every flow that never
  /// seeds this keeps the pre-existing "no gate to see" behaviour; a flow
  /// driving the non-empty path sets this BEFORE booting.
  List<Map<String, dynamic>> conflictPreviewRows = <Map<String, dynamic>>[];

  /// `PUT /overrides/{date}` calls made with `cancelOverlapping: true` while
  /// [conflictPreviewRows] was non-empty — the fake's stand-in for "the server
  /// atomically declined every conflicting booking with this write" (D3). Also
  /// flips the seeded `booking-1` fixture's [bookingStatus] to `DECLINED` so a
  /// flow can assert the conflicting booking is gone from the source of truth
  /// the app re-reads after the invalidation the sheet issues on confirm.
  int overrideCancelOverlappingWrites = 0;

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// The CLIENT `GET /users/me` body, built from the mutable client state so a
  /// PATCH made by the Contacts / Location edit screen round-trips on re-fetch.
  /// Shape matches `UserProfileResponse` (the DTO `UserMapper.fromProfileDto`
  /// consumes): id / email / role / firstName / lastName + the optional
  /// phone + location enrichment fields.
  Map<String, dynamic> _clientProfileBody() => <String, dynamic>{
    'id': 'user-client-1',
    'email': 'client@beautica.ua',
    'role': 'CLIENT',
    'firstName': clientFirstName,
    'lastName': clientLastName,
    'phoneNumber': clientPhone,
    'oblastId': clientOblastId,
    'oblastName': clientOblastName,
    'cityId': clientCityId,
    'cityName': clientCityName,
    'districtId': clientDistrictId,
    'districtName': clientDistrictName,
    'street': clientStreet,
    'buildingNo': clientBuildingNo,
    'locationNote': clientLocationNote,
  };

  // ── Discovery search fixtures (Phase 13.4) ────────────────────────────────
  //
  // Two pages of master results + one page of salon results so the E2E can drive
  // BOTH the first-page render AND a loadMore append. Shapes match the generated
  // `MasterSearchResult` / `SalonSearchResult` DTOs (camelCase wire keys). The
  // mapper rejects a null/empty id, so every row carries a non-empty id.
  static const List<Map<String, dynamic>> _searchMastersPage0 =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'masterId': 'master-aaa',
          'firstName': 'Софія',
          'lastName': 'Бондар',
          'cityLabel': 'Київ',
          'districtLabel': 'Печерський',
          // Same master, same aggregate as the public detail / summary — a
          // search card that disagreed with the profile it opens would be the
          // same harness infidelity, just moved one endpoint over.
          'avgRating': kPublicMasterAvgRatingBeforeReview,
          'reviewCount': kPublicMasterReviewCountBeforeReview,
          'avatarUrl': null,
          'minEffectivePrice': 450,
        },
      ];

  static const List<Map<String, dynamic>> _searchMastersPage1 =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'masterId': 'master-bbb',
          'firstName': 'Ірина',
          'lastName': 'Левчук',
          'cityLabel': 'Київ',
          'districtLabel': 'Шевченківський',
          'avgRating': 0,
          'reviewCount': 0,
          'avatarUrl': null,
          'minEffectivePrice': 700,
        },
      ];

  static const List<Map<String, dynamic>>
  _searchSalonsPage0 = <Map<String, dynamic>>[
    <String, dynamic>{
      'salonId': 'salon-xyz',
      'name': 'Студія Краси «Камелія»',
      'cityLabel': 'Київ',
      'districtLabel': 'Печерський',
      'avatarUrl': null,
      'priceMin': 300,
      'priceMax': 1200,
      // Auth-gated address (item 6) — the seeded caller is authenticated, so
      // the salon row carries street + buildingNo + note; the mapper folds them
      // into its precomputed addressLine «вул. Хрещатик, 12 · 2 поверх» (the
      // card renders the locality on line 1 and this street·note line on
      // line 2).
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'locationNote': '2 поверх',
      // Services preview (item 7) — the card renders the « · »-joined line.
      'serviceNames': <String>['Манікюр', 'Стрижка'],
    },
  ];

  /// Builds the `ApiResponse<PageResponse<…>>` envelope the generated client
  /// deserializes: `{ success, data: { data: [...], page, size, totalElements,
  /// totalPages }, message }`.
  static Map<String, dynamic> _searchEnvelope(
    List<Map<String, dynamic>> rows, {
    required int page,
    required int totalPages,
    required int totalElements,
  }) => <String, dynamic>{
    'success': true,
    'message': 'ok',
    'data': <String, dynamic>{
      'data': rows,
      'page': page,
      'size': 20,
      'totalElements': totalElements,
      'totalPages': totalPages,
    },
  };

  /// Extracts the zero-based `page` from the FLAT search query map.
  ///
  /// WIRE-FORMAT FIX: the repository now sends `@ModelAttribute`-bindable FLAT
  /// params (`page=0&size=20&sort=…&location.cityId=…&q=…`) directly — NOT the
  /// old `?request=<json>` object-query wrapper the generated client used. The
  /// `page` arrives as its own top-level query key.
  static int _pageFromRequest(Map<String, dynamic> query) {
    final raw = query['page'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Reads the FLAT search query map as a plain `{ key: value }` map. Mirrors the
  /// wire the @ModelAttribute binder reads: `q`, `sort`, `category`,
  /// `location.cityId`, `location.districtId`, `minPrice`, `maxPrice`,
  /// `minRating`, `page`, `size`. Used to capture `q` / `sort` / `location.*`
  /// telemetry. The values are already URL-decoded by DioAdapter.
  static Map<String, dynamic> _decodeRequest(Map<String, dynamic> query) =>
      Map<String, dynamic>.from(query);

  Map<String, dynamic> _masterDetailEnvelope() => _ok(<String, dynamic>{
    'masterId': masterRowId,
    'firstName': masterFirstName,
    'lastName': masterLastName,
    'bio': masterBio,
    'phoneNumber': masterPhone,
    'instagram': masterInstagram,
    // professionalTitle is optional — null is valid (omitted from the
    // ApiResponse.data when the master has not set one). Include only when
    // set so flows that do not exercise this field see a clean seed.
    if (masterProfessionalTitle != null)
      'professionalTitle': masterProfessionalTitle,
    // Address fields (Phase 219/220/221) — same "omit when null" shape as
    // professionalTitle above, so flows that never set these keep seeing the
    // pre-existing location-less seed (no location row on MasterProfileScreen).
    if (masterCity != null) 'city': masterCity,
    if (masterStreet != null) 'street': masterStreet,
    if (masterBuildingNo != null) 'buildingNo': masterBuildingNo,
    if (masterLocationNote != null) 'locationNote': masterLocationNote,
    'avgRating': 4.8,
    'reviewCount': 10,
    'masterType': 'INDEPENDENT_MASTER',
  });

  /// PUBLIC master-detail envelope for the Phase 13.5 client-facing profile.
  ///
  /// Keyed on the Master-row UUID `master-aaa` (the same id the search-results
  /// fixture seeds), so a CLIENT pushing `/masters/master-aaa` resolves a real
  /// profile: «Софія Бондар», INDEPENDENT_MASTER, an Instagram handle (so the
  /// validated contact tile renders + launches), and a rating/reviews block.
  ///
  /// INSTANCE (not static) because the rating block MOVES once the client's
  /// `POST /reviews` lands — see [publicMasterReviewLanded].
  Map<String, dynamic> _publicMasterDetailEnvelope() => _ok(<String, dynamic>{
    'masterId': 'master-aaa',
    'firstName': 'Софія',
    'lastName': 'Бондар',
    'city': 'Київ',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'locationNote': '2 поверх',
    'bio': 'Майстриня манікюру з 6-річним досвідом.',
    'instagram': '@sofia_nails',
    'avgRating': publicMasterReviewLanded
        ? kPublicMasterAvgRatingAfterReview
        : kPublicMasterAvgRatingBeforeReview,
    'reviewCount': publicMasterReviewLanded
        ? kPublicMasterReviewCountAfterReview
        : kPublicMasterReviewCountBeforeReview,
    'masterType': 'INDEPENDENT_MASTER',
  });

  /// PUBLIC active-services list for `master-aaa` — a deterministic TWO-item
  /// list so the profile's services-count stat tile renders «2». Shapes match
  /// the generated `MasterServiceResponse` (the same envelope `_services` uses).
  static const List<Map<String, dynamic>> _publicMasterServices =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'pub-assign-1',
          'masterId': 'master-aaa',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 500,
          'priceMax': null,
          'priceDisplay': '500 ₴',
          'effectiveDurationMinutes': 90,
          'serviceDefinition': <String, dynamic>{
            'id': 'pub-svc-1',
            'name': 'Манікюр з покриттям',
            'description': null,
            'category': 'NAILS',
            // Service-type slug (Phase 16.3 space, mirrored on
            // ServiceDefinitionResponse) — the SAME slug space the discovery
            // search filter uses. Drives the search→booking pre-selection
            // exact-slug match: filtering by CLASSIC_MANICURE pre-checks THIS
            // service and NOT pub-svc-2 (GEL_MANICURE).
            'serviceTypeSlug': 'CLASSIC_MANICURE',
            'baseDurationMinutes': 90,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 500,
            'priceMax': null,
            'priceDisplay': '500 ₴',
            'photoUrl': null,
          },
        },
        <String, dynamic>{
          'id': 'pub-assign-2',
          'masterId': 'master-aaa',
          'isActive': true,
          'priceType': 'RANGE',
          'priceMin': 300,
          'priceMax': 600,
          'priceDisplay': 'від 300 до 600 ₴',
          'effectiveDurationMinutes': 60,
          'serviceDefinition': <String, dynamic>{
            'id': 'pub-svc-2',
            'name': 'Дизайн нігтів',
            'description': null,
            'category': 'NAILS',
            // A DIFFERENT service-type slug in the same category — must stay
            // UN-checked when the search pre-selection carried only
            // CLASSIC_MANICURE (exact-slug match, no false positives).
            'serviceTypeSlug': 'GEL_MANICURE',
            'baseDurationMinutes': 60,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'RANGE',
            'priceMin': 300,
            'priceMax': 600,
            'priceDisplay': 'від 300 до 600 ₴',
            'photoUrl': null,
          },
        },
      ];

  /// Public services count for `master-aaa` — used by the E2E to assert the
  /// rendered services-count stat without hard-coding the literal in two places.
  static int get publicMasterServicesCount => _publicMasterServices.length;

  /// `FavoriteServiceResponse` display fields for master-aaa's two public
  /// services, keyed by `masterServiceId` — mirrors [_publicMasterServices]
  /// verbatim. Used by the `POST /api/v1/favorites` (SERVICE) handler below to
  /// make an add genuinely visible on the next `GET /favorites/services`.
  static const Map<String, Map<String, dynamic>>
  _masterAaaFavoriteServiceFields = <String, Map<String, dynamic>>{
    'pub-assign-1': <String, dynamic>{
      'masterId': 'master-aaa',
      'serviceName': 'Манікюр з покриттям',
      'masterFirstName': 'Софія',
      'masterLastName': 'Бондар',
      'durationMinutes': 90,
      'priceType': 'FIXED',
      'priceMin': 500,
      'priceMax': null,
      'priceDisplay': '500 ₴',
    },
    'pub-assign-2': <String, dynamic>{
      'masterId': 'master-aaa',
      'serviceName': 'Дизайн нігтів',
      'masterFirstName': 'Софія',
      'masterLastName': 'Бондар',
      'durationMinutes': 60,
      'priceType': 'RANGE',
      'priceMin': 300,
      'priceMax': 600,
      'priceDisplay': 'від 300 до 600 ₴',
    },
  };

  /// `FavoriteServiceResponse` SALON-arm display fields for `salon-xyz`'s
  /// public catalogue services, keyed by `serviceDefId` — mirrors
  /// [_salonServiceCategories] verbatim. Used by the `POST /api/v1/favorites`
  /// (SALON_SERVICE) handler below, the SALON-arm counterpart of
  /// [_masterAaaFavoriteServiceFields]: without it a heart tapped on the
  /// salon's own service-selection screen would POST successfully but the
  /// Beauty Passport read-back would never show the row, which is exactly the
  /// gap `salon_service_favourite_flow_test.dart` (mobile-qa) closes.
  static const Map<String, Map<String, dynamic>> _salonServiceFavoriteFields =
      <String, Map<String, dynamic>>{
        'salon-svc-shared': <String, dynamic>{
          'salonName': 'Студія Краси «Камелія»',
          'salonAvatarUrl': null,
          'serviceName': 'Манікюр класичний',
          'durationMinutes': 60,
          'priceDisplay': '400 ₴',
        },
        'salon-svc-namefallback': <String, dynamic>{
          'salonName': 'Студія Краси «Камелія»',
          'salonAvatarUrl': null,
          'serviceName': 'Манікюр класичний VIP',
          'durationMinutes': 75,
          'priceDisplay': '550 ₴',
        },
        'salon-svc-exclusive': <String, dynamic>{
          'salonName': 'Студія Краси «Камелія»',
          'salonAvatarUrl': null,
          'serviceName': 'Корекція брів',
          'durationMinutes': 45,
          'priceDisplay': '300 ₴',
        },
      };

  /// Builds one `BookableMasterResponse`-shaped envelope entry (Phase 23.x
  /// `GET /salons/{salonId}/services/{serviceDefId}/masters`) for [masterId]
  /// on [serviceDefId]. `masterServiceId` deliberately follows the SAME
  /// `assign-<masterId>-<serviceDefId>` convention the old (now-removed)
  /// `_masterServiceEnvelope` used — a DIFFERENT string from [serviceDefId]
  /// itself, exactly like production (`master_services.id` is never equal to
  /// `service_definitions.id`) — so [lastMasterCccSlotsServiceId]/
  /// [lastMasterDddSlotsServiceId]'s masterService-not-found regression guard
  /// (Phase 14.16/14.17) keeps proving what it always proved.
  static Map<String, dynamic> _bookableMasterEnvelope({
    required String masterId,
    required String serviceDefId,
    required String firstName,
    required String lastName,
  }) => <String, dynamic>{
    'masterId': masterId,
    'masterServiceId': 'assign-$masterId-$serviceDefId',
    'firstName': firstName,
    'lastName': lastName,
    'professionalTitle': null,
    'avatarUrl': null,
    'avgRating': 4.7,
    'reviewCount': 10,
  };

  /// PUBLIC available-slots envelope for `master-aaa` — answers
  /// `GET /api/v1/masters/master-aaa/slots?date=&serviceId=` (Phase 14.1
  /// `SlotRepository.getMasterSlots`). The DioAdapter route match is
  /// path-only (query params ignored — see the `salon-xyz/masters` comment
  /// above), so this SAME two-slot fixture answers whichever date/service the
  /// booking-flow E2E requests. Both slots map to `BookingSlot.available ==
  /// true` (the wire contract carries no availability flag — see
  /// `BookingSlotMapper`), which is exactly what the flow needs: at least one
  /// tappable chip on the time screen.
  ///
  /// The day these slots are dated on is [serverNow] (default [kFixedNow]) —
  /// the clock the app under test is on — not the device clock. The route
  /// match ignores query params, so the DATE never affected which request
  /// this answered; what it did affect is what the confirm screen then
  /// renders, which was the HOST's calendar day while the calendar the user
  /// just tapped was drawn from the injected one. Same two-clock rule as
  /// [_workingDaysEnvelope]; no longer `static` because it now reads
  /// instance state.
  Map<String, dynamic> _availableSlotsEnvelope() {
    final DateTime day = kyivDayOf(serverNow);
    DateTime at(int hourUtc, int minute) =>
        DateTime.utc(day.year, day.month, day.day, hourUtc, minute);
    Map<String, dynamic> slot(DateTime start, DateTime end) =>
        <String, dynamic>{
          'startsAt': start.toIso8601String(),
          'endsAt': end.toIso8601String(),
        };
    return _ok(<String, dynamic>{
      'date':
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
      'slots': <Map<String, dynamic>>[
        for (final (int hourUtc, int minute) in availableSlotUtcStarts)
          slot(at(hourUtc, minute), at(hourUtc, minute + 30)),
      ],
    });
  }

  /// The `(hourUtc, minute)` starts [_availableSlotsEnvelope] emits, on the
  /// KYIV day of [serverNow]. Each slot runs 30 minutes.
  ///
  /// WHY UTC, AND WHY THIS DEFAULT
  /// ------------------------------
  /// These used to be built with a bare local `DateTime(...)`, so the instant
  /// on the wire moved with the HOST `TZ`: on the Kyiv dev VM `at(10, 0)` was
  /// 07:00Z (chip reads 10:00 Kyiv); on a `TZ=UTC` runner the same line
  /// produced 10:00Z (chip reads 13:00 Kyiv). Same fixture, two different
  /// rendered times — and the app under test runs on the INJECTED clock, not
  /// the host's, so this was the fake-backend spelling of the two-clock trap
  /// `_workingDaysEnvelope` already documents just below.
  ///
  /// The default `07:00Z / 11:00Z` reproduces the dev VM's previous behaviour
  /// EXACTLY (10:00 and 14:00 Kyiv, June being EEST/+3) — now as a property of
  /// the fixture rather than of the runner. Every E2E that consumes these picks
  /// `SlotChip … .first`, so neither the count nor the times are load-bearing
  /// anywhere; a flow that cares sets this field explicitly.
  ///
  /// The real backend emits each slot at its KYIV wall-clock with an offset
  /// (`…T13:00:00+03:00`) and the generated client normalises to UTC, so a UTC
  /// instant here is the same value the app would hold in production.
  List<(int, int)> availableSlotUtcStarts = const <(int, int)>[(7, 0), (11, 0)];

  /// PUBLIC working-days envelope for `master-aaa` — answers
  /// `GET /api/v1/masters/master-aaa/working-days?from=&to=` (Phase 14.14
  /// `SlotRepository.getWorkingDays`). The DioAdapter route match is
  /// path-only (query params ignored — see the `salon-xyz/masters` comment
  /// above), so one registration must answer whichever visible-month range
  /// `SlotDateScreen` requests. Every day across a WIDE window (5 months
  /// back to 5 months forward from "now") is marked `working: true` so the
  /// booking-flow E2E's "tap today" step stays admissible regardless of
  /// which real-world date the suite runs on, mirroring
  /// `_availableSlotsEnvelope`'s "at least one tappable target" intent —
  /// EXCEPT [forceNonWorkingDate], if set, which reports as `working: false`
  /// so a test can exercise the gate's negative path against the real
  /// endpoint instead of only wiring the fixture — and
  /// [forceNonWorkingDateWhenServiceScoped], which does the same but ONLY when
  /// the request carried a [serviceId] (the availability-aware mode the Phase
  /// 14.20 fix depends on).
  Map<String, dynamic> _workingDaysEnvelope({String? serviceId}) {
    // ANCHORED TO [serverNow] (which defaults to [kFixedNow]), NOT the device
    // clock. The window this builds decides which calendar cells the app
    // renders as TAPPABLE, and the app's calendar is drawn from the INJECTED
    // clock — so a host-anchored window is only correct while the two clocks
    // happen to sit within five months of each other. That was a live time
    // bomb: with `kFixedNow` at 2026-06-14, a suite run any time after
    // ~2026-11-30 would have produced a window that no longer covers the
    // month the calendar is showing, marking EVERY visible day non-working,
    // stripping every cell's `GestureDetector`, and silently re-creating the
    // exact no-op-tap failure the 2026-08-04 fix removed — with no code
    // change to blame it on. Anchoring to the same clock the app is on makes
    // the coverage a property of the fixture rather than of the run date.
    final DateTime now = serverNow;
    final DateTime from = DateTime(now.year, now.month - 5, 1);
    final DateTime to = DateTime(now.year, now.month + 6, 0);
    final DateTime? nonWorking = forceNonWorkingDate;
    final DateTime? nonWorkingWhenScoped = serviceId != null
        ? forceNonWorkingDateWhenServiceScoped
        : null;
    bool matches(DateTime? forced, DateTime d) =>
        forced != null &&
        d.year == forced.year &&
        d.month == forced.month &&
        d.day == forced.day;
    final List<Map<String, dynamic>> days = <Map<String, dynamic>>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      final bool isForcedNonWorking =
          matches(nonWorking, d) || matches(nonWorkingWhenScoped, d);
      days.add(<String, dynamic>{
        'date':
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
        'working': !isForcedNonWorking,
      });
    }
    return _okList(days);
  }

  // ---------------------------------------------------------------------------
  // Public salon profile fixtures (Phase 13.6)
  // ---------------------------------------------------------------------------
  //
  // Keyed on `salon-xyz` — the SAME id the discovery search-results fixture
  // (`_searchSalonsPage0`) seeds, so tapping the rendered `salon_card_salon-xyz`
  // in the real results screen lands on a profile backed by a real, coherent
  // fixture rather than a second unrelated salon id.

  /// PUBLIC salon-detail envelope for `salon-xyz`. Shape matches
  /// `PublicSalonResponse` (id/name/description/city/region/address/cityId/
  /// districtId/street/buildingNo/locationNote/instagramUrl/avatarUrl/
  /// coverImageUrl/avgRating/reviewCount).
  ///
  /// Deliberately carries ONLY the Phase 10.6+ taxonomy locality fields
  /// (`cityId`/`street`/`buildingNo`/`locationNote`) and leaves the legacy
  /// `city`/`address` pair null — this is the real shape of every salon
  /// created/edited since Phase 10.6, and is the exact fixture shape the
  /// "public salon profile shows no location" regression needed: a fixture
  /// with the legacy pair populated would pass through the OLD (broken)
  /// `SalonMapper.fromDto`, which silently dropped the taxonomy fields, just
  /// as easily as the fixed one. See `salon_mapper_test.dart` for the
  /// mapper-level unit-test counterpart and
  /// `public_salon_profile_flow_test.dart` for the assertion that reads the
  /// rendered address text.
  Map<String, dynamic> _publicSalonDetailEnvelope() => _ok(<String, dynamic>{
    'id': 'salon-xyz',
    'name': 'Студія Краси «Камелія»',
    'description':
        'Затишна студія краси у центрі Києва. Манікюр, догляд за бровами '
        'та стрижки — довірливий сервіс з 2018 року.',
    'region': 'Київська',
    'cityId': 'city-uuid-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'locationNote': salonLocationNote,
    'instagramUrl': '@kamelia_salon',
    'avatarUrl': null,
    'coverImageUrl': null,
    // ONE reconciled number per field, shared with the review-summary envelope
    // below and derivable from the rows [_salonReviewsFor] actually returns.
    // This used to read `reviewCount: 3` against the summary's `4` — the exact
    // shape of defanging that made the master-side flow toothless (detail said
    // 24, summary said 2), so no assertion could tell a stale cache from a
    // refetch. See [kSalonAvgRatingBeforeReview].
    'avgRating': salonReviewLanded
        ? kSalonAvgRatingAfterReview
        : kSalonAvgRatingBeforeReview,
    'reviewCount': salonReviewLanded
        ? kSalonReviewCountAfterReview
        : kSalonReviewCountBeforeReview,
  });

  /// PUBLIC masters rail for `salon-xyz` — EIGHT masters, deliberately over
  /// [kSalonMastersInitialCount] (6, see `public_salon_profile_screen.dart`),
  /// so the "Майстри" tab renders both a genuine multi-card rail AND the
  /// eager-build-cap "show all" affordance (mobile-perf LOW fix, Phase 13.6
  /// audit follow-up). The first reuses `master-aaa` (the SAME master-id the
  /// public-master-profile fixture already serves at `GET /masters/master-aaa`),
  /// so tapping its rail card in the salon flow exercises the REAL
  /// cross-feature navigation into an already-fixtured public master profile
  /// without inventing a second detail stub. The first TWO entries
  /// (`master-aaa`/`master-ccc`) are load-bearing for other assertions in
  /// `public_salon_profile_flow_test.dart` (names, ids) — order matters, they
  /// must stay first so they remain inside the initial (uncapped) batch;
  /// entries 3–8 exist purely to push the roster over the cap threshold and
  /// prove the reveal interaction end to end against the REAL wire response
  /// (the hand-rolled `page=0&size=50` Pageable decode in
  /// `HttpSalonRepository` — a boundary the widget tier's fake repository
  /// bypasses entirely, so a silent truncation there would be invisible to
  /// `public_salon_profile_screen_test.dart`). Shape matches
  /// `MasterSummaryResponse` (masterId/firstName/lastName/avatarUrl/
  /// avgRating/reviewCount/masterType).
  static const List<Map<String, dynamic>> _salonMasters =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'masterId': 'master-aaa',
          'firstName': 'Софія',
          'lastName': 'Бондар',
          'avatarUrl': null,
          // Same master as the public detail / summary / search card — the
          // rail card opens THAT profile, so the numbers must match.
          'avgRating': kPublicMasterAvgRatingBeforeReview,
          'reviewCount': kPublicMasterReviewCountBeforeReview,
          'masterType': 'SALON_MASTER',
        },
        <String, dynamic>{
          'masterId': 'master-ccc',
          'firstName': 'Марія',
          'lastName': 'Гриценко',
          'avatarUrl': null,
          'avgRating': 4.6,
          'reviewCount': 9,
          'masterType': 'SALON_OWNER',
        },
        <String, dynamic>{
          'masterId': 'master-ddd',
          'firstName': 'Оксана',
          'lastName': 'Іванова',
          'avatarUrl': null,
          'avgRating': 4.8,
          'reviewCount': 15,
          'masterType': 'SALON_MASTER',
        },
        <String, dynamic>{
          'masterId': 'master-eee',
          'firstName': 'Тетяна',
          'lastName': 'Мельник',
          'avatarUrl': null,
          'avgRating': 4.7,
          'reviewCount': 11,
          'masterType': 'SALON_MASTER',
        },
        <String, dynamic>{
          'masterId': 'master-fff',
          'firstName': 'Наталія',
          'lastName': 'Коваль',
          'avatarUrl': null,
          'avgRating': 4.5,
          'reviewCount': 7,
          'masterType': 'SALON_MASTER',
        },
        <String, dynamic>{
          'masterId': 'master-ggg',
          'firstName': 'Юлія',
          'lastName': 'Шевченко',
          'avatarUrl': null,
          'avgRating': 4.9,
          'reviewCount': 20,
          'masterType': 'SALON_MASTER',
        },
        // 7th entry (index 6) — the FIRST master beyond the 6-item initial
        // cap. Must NOT render until the "show all" affordance is tapped.
        <String, dynamic>{
          'masterId': 'master-hhh',
          'firstName': 'Катерина',
          'lastName': 'Бондаренко',
          'avatarUrl': null,
          'avgRating': 4.6,
          'reviewCount': 5,
          'masterType': 'SALON_MASTER',
        },
        <String, dynamic>{
          'masterId': 'master-iii',
          'firstName': 'Вікторія',
          'lastName': 'Пономаренко',
          'avatarUrl': null,
          'avgRating': 4.4,
          'reviewCount': 3,
          'masterType': 'SALON_MASTER',
        },
      ];

  /// PUBLIC service catalogue for `salon-xyz` — two categories, one service
  /// each: NAILS carries the salon's SHARED signature service (offered by
  /// every master on the rail), BROWS carries an EXCLUSIVE service (offered
  /// by only one master). The category/service split is what the "Послуги"
  /// tab's accordion groups by; the shared-vs-exclusive distinction is not a
  /// wire field (the catalogue has no per-master mapping) — it is captured
  /// here only in naming/comment for fixture realism. Shape matches
  /// `SalonServiceCatalogResponse` → `SalonServiceCategoryGroup` →
  /// `ServiceDefinitionResponse`.
  static const List<Map<String, dynamic>> _salonServiceCategories =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'category': 'NAILS',
          'count': 2,
          'services': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'salon-svc-shared',
              'name': 'Манікюр класичний',
              'description': null,
              'category': 'NAILS',
              // Service-type slug (ServiceDefinitionResponse.serviceTypeSlug) —
              // the SAME slug space as the discovery search filter. A salon
              // search pre-selection filtered by CLASSIC_MANICURE pre-checks
              // THIS catalogue service and not salon-svc-exclusive.
              'serviceTypeSlug': 'CLASSIC_MANICURE',
              'serviceTypeNameUk': 'Класичний манікюр',
              'baseDurationMinutes': 60,
              'bufferMinutesAfter': 0,
              'isActive': true,
              'priceType': 'FIXED',
              'priceMin': 400,
              'priceMax': null,
              'priceDisplay': '400 ₴',
              'photoUrl': null,
            },
            // REGRESSION FIXTURE (salon-prefill label-fallback bug): this
            // service has NO serviceTypeSlug (the service-type picker is
            // optional, so a null slug is common) — it can ONLY be matched via
            // its serviceTypeNameUk ('Класичний манікюр', the platform
            // service-type name the CLASSIC_MANICURE filter resolves its label
            // to). Its CUSTOM `name` ('Манікюр класичний VIP') deliberately
            // DIFFERS from that label, so the pre-fix code — which compared the
            // custom name — never pre-checked/pinned it. Exercises the
            // serviceTypeNameUk fallback end-to-end (mirrors the master path).
            <String, dynamic>{
              'id': 'salon-svc-namefallback',
              'name': 'Манікюр класичний VIP',
              'description': null,
              'category': 'NAILS',
              'serviceTypeSlug': null,
              'serviceTypeNameUk': 'Класичний манікюр',
              'baseDurationMinutes': 75,
              'bufferMinutesAfter': 0,
              'isActive': true,
              'priceType': 'FIXED',
              'priceMin': 550,
              'priceMax': null,
              'priceDisplay': '550 ₴',
              'photoUrl': null,
            },
          ],
        },
        <String, dynamic>{
          'category': 'BROWS',
          'count': 1,
          'services': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'salon-svc-exclusive',
              'name': 'Корекція брів',
              'description': null,
              'category': 'BROWS',
              // A DIFFERENT service-type slug in a DIFFERENT category — must
              // stay UN-checked under a CLASSIC_MANICURE search pre-selection.
              'serviceTypeSlug': 'BROW_CORRECTION',
              'baseDurationMinutes': 45,
              'bufferMinutesAfter': 0,
              'isActive': true,
              'priceType': 'FIXED',
              'priceMin': 300,
              'priceMax': null,
              'priceDisplay': '300 ₴',
              'photoUrl': null,
            },
          ],
        },
      ];

  /// PUBLIC review-summary envelope for `salon-xyz` — matches the FOUR
  /// reviews in [_salonReviews] (one 5★, two 4★, one 3★; avg stays exactly
  /// 4.0 — (5+4+4+3)/4 — so the existing `salon-review-summary-average`
  /// assertion in `public_salon_profile_flow_test.dart` is unaffected by the
  /// 4th review added for the empty-string serviceName branch below). Shape
  /// matches `SalonReviewSummaryResponse` → `RatingBucket`.
  ///
  /// After [salonReviewLanded] flips, the client's own 5★ joins the aggregate:
  /// five reviews, (5+4+3+4+5)/5 = 4.2 EXACTLY, and the 5★ bucket goes 1 → 2.
  /// Both moves are arithmetically derivable from the rows [_salonReviewsFor]
  /// returns, and 4.2 is exact in one decimal — no rounding-boundary ambiguity
  /// (which is why the seeded 5th review is a 5★ and not, say, a 4★: that
  /// would land on 4.0 and move nothing at all).
  Map<String, dynamic> _salonReviewSummaryEnvelope() => _ok(<String, dynamic>{
    'avgRating': salonReviewLanded
        ? kSalonAvgRatingAfterReview
        : kSalonAvgRatingBeforeReview,
    'reviewCount': salonReviewLanded
        ? kSalonReviewCountAfterReview
        : kSalonReviewCountBeforeReview,
    'ratingDistribution': <Map<String, dynamic>>[
      <String, dynamic>{'rating': 5, 'count': salonReviewLanded ? 2 : 1},
      <String, dynamic>{'rating': 4, 'count': 2},
      <String, dynamic>{'rating': 3, 'count': 1},
      <String, dynamic>{'rating': 2, 'count': 0},
      <String, dynamic>{'rating': 1, 'count': 0},
    ],
  });

  /// The salon's review rows as the server would serve them RIGHT NOW: the four
  /// seeded rows, plus the client's own review once [salonReviewLanded] flips.
  ///
  /// Appended to EVERY sort bucket — the fake does not re-implement the
  /// backend's ordering (see [_salonReviews]), and the per-sort invalidation
  /// loop is proven by the CALL COUNTER plus the row's presence in a second,
  /// separately-warmed bucket rather than by its position in the list.
  List<Map<String, dynamic>> _salonReviewsFor() => <Map<String, dynamic>>[
    ..._salonReviews,
    if (salonReviewLanded)
      <String, dynamic>{
        'id': kSalonClientReviewId,
        'masterId': 'master-aaa',
        'masterFirstName': 'Софія',
        'masterLastName': 'Бондар',
        'clientDisplayName': 'Олена К.',
        'serviceName': 'Манікюр з покриттям',
        'rating': 5,
        'comment': 'Дуже задоволена, дякую!',
        // M15 — anchored to the harness's INJECTED clock, the same one the app
        // renders this row against. Never the host clock.
        'createdAt': kFixedNow.toUtc().toIso8601String(),
      },
  ];

  /// PUBLIC reviews list for `salon-xyz` — four reviews split across both
  /// seeded masters. The fake ignores the `sort` query value and always
  /// returns this same fixed list (the sort contract is the SERVER's — the
  /// fake only needs to prove the wire value reaches the backend, via
  /// [lastGetSalonReviewsSort]). Shape matches `SalonReviewResponse`.
  ///
  /// `serviceName` deliberately covers all THREE wire shapes the shared
  /// `_salonReviewCard` mapper must handle (mirrors [_masterReviews] below):
  /// salon-review-1 has a resolved name (unlabelled sub-line renders),
  /// salon-review-3 omits the field entirely (null → sub-line hidden), and
  /// salon-review-4 sends an explicit empty string (also → sub-line hidden,
  /// never a stray icon with no name after the «послуга: » label removal).
  static const List<Map<String, dynamic>> _salonReviews =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'salon-review-1',
          'masterId': 'master-aaa',
          'masterFirstName': 'Софія',
          'masterLastName': 'Бондар',
          'clientDisplayName': 'Олена К.',
          'serviceName': 'Манікюр класичний',
          'rating': 5,
          'comment': 'Чудовий сервіс, дуже задоволена результатом!',
          'createdAt': '2026-06-10T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'salon-review-2',
          'masterId': 'master-ccc',
          'masterFirstName': 'Марія',
          'masterLastName': 'Гриценко',
          'clientDisplayName': 'Ірина П.',
          'serviceName': 'Корекція брів',
          'rating': 4,
          'comment': 'Все сподобалось, трохи довго чекала на прийом.',
          'createdAt': '2026-06-05T14:00:00Z',
        },
        <String, dynamic>{
          'id': 'salon-review-3',
          'masterId': 'master-aaa',
          'masterFirstName': 'Софія',
          'masterLastName': 'Бондар',
          'clientDisplayName': 'Дарина М.',
          'serviceName': null,
          'rating': 3,
          'comment': 'Непогано, але є куди рости.',
          'createdAt': '2026-05-20T09:00:00Z',
        },
        <String, dynamic>{
          'id': 'salon-review-4',
          'masterId': 'master-ccc',
          'masterFirstName': 'Марія',
          'masterLastName': 'Гриценко',
          'clientDisplayName': 'Юлія Р.',
          'serviceName': '',
          'rating': 4,
          'comment': 'Приємна атмосфера, дякую!',
          'createdAt': '2026-05-15T11:00:00Z',
        },
      ];

  /// Master received-reviews summary envelope (Phase 4.5). Matches the THREE
  /// reviews in [_masterReviews] (one 5★, one 4★, one 3★). Shape matches
  /// `MasterReviewSummaryResponse` → `RatingBucket`.
  static Map<String, dynamic> _masterReviewSummaryEnvelope() =>
      _ok(<String, dynamic>{
        'avgRating': 4.0,
        'reviewCount': 3,
        'ratingDistribution': <Map<String, dynamic>>[
          <String, dynamic>{'rating': 5, 'count': 1},
          <String, dynamic>{'rating': 4, 'count': 1},
          <String, dynamic>{'rating': 3, 'count': 1},
          <String, dynamic>{'rating': 2, 'count': 0},
          <String, dynamic>{'rating': 1, 'count': 0},
        ],
      });

  /// Master received-reviews fixture — three reviews with DISTINCT ids, ratings
  /// and dates so the per-sort reordering below is observable. `serviceName`
  /// (backend `92280c3`) deliberately covers all three wire shapes the mapper
  /// + screen must handle: mr-1 has a resolved name (the unlabelled
  /// service-name sub-line renders), mr-2 omits the field entirely (null →
  /// sub-line hidden), and mr-3 sends an explicit empty string (also →
  /// sub-line hidden, never a stray icon with no name). Shape matches
  /// `ReviewResponse`.
  static const List<Map<String, dynamic>> _masterReviews =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'mr-1',
          'clientDisplayName': 'Іра К.',
          'rating': 5,
          'comment': 'Найкращий майстер, дуже задоволена!',
          'createdAt': '2026-06-10T10:00:00Z',
          'serviceName': 'Манікюр',
        },
        <String, dynamic>{
          'id': 'mr-2',
          'clientDisplayName': 'Оля В.',
          'rating': 3,
          'comment': 'Непогано, але можна краще.',
          'createdAt': '2026-05-01T09:00:00Z',
        },
        <String, dynamic>{
          'id': 'mr-3',
          'clientDisplayName': 'Ніна С.',
          'rating': 4,
          'comment': 'Все сподобалось, дякую.',
          'createdAt': '2026-05-20T14:00:00Z',
          'serviceName': '',
        },
      ];

  /// Returns [_masterReviews] server-ordered by the `sort` wire value. Unlike
  /// the salon fake (which ignores sort), the master fake really reorders so an
  /// E2E can assert the list visibly reorders after a sort change — proving the
  /// screen re-keyed its provider AND that the new sort reached the wire. ISO
  /// timestamps compare lexicographically, so string compare = chronological.
  static List<Map<String, dynamic>> _masterReviewsFor(String? sort) {
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[
      ..._masterReviews,
    ];
    switch (sort) {
      case 'OLDEST':
        list.sort(
          (a, b) =>
              (a['createdAt'] as String).compareTo(b['createdAt'] as String),
        );
      case 'HIGHEST':
        list.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
      case 'LOWEST':
        list.sort((a, b) => (a['rating'] as int).compareTo(b['rating'] as int));
      case 'NEWEST':
      default:
        list.sort(
          (a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String),
        );
    }
    return list;
  }

  /// Error envelope for the wrong-id master summary route (mirrors the backend's
  /// `masterRepository.findById(userId).orElseThrow(NotFoundException)` → 404).
  static Map<String, dynamic> _masterNotFoundEnvelope() => <String, dynamic>{
    'success': false,
    'message': 'Master not found',
    'data': null,
  };

  /// PUBLIC master reviews fixture for `master-aaa` (Phase 4.x
  /// `PublicMasterReviewsScreen`, reached from the public profile's
  /// «Відгуки» stat tile) — deliberately DISTINCT ids from [_masterReviews]
  /// (the AUTHENTICATED-master `mr-*` self fixture) so a test can tell the
  /// two review surfaces apart at a glance if the wrong route is ever hit.
  static const List<Map<String, dynamic>> _publicMasterReviews =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'pub-r1',
          'clientDisplayName': 'Марія Т.',
          'rating': 5,
          'comment': 'Чудова робота, рекомендую!',
          'createdAt': '2026-06-01T12:00:00Z',
          'serviceName': 'Манікюр з покриттям',
        },
        <String, dynamic>{
          'id': 'pub-r2',
          'clientDisplayName': 'Дарина Л.',
          'rating': 4,
          'comment': 'Все дуже сподобалось.',
          'createdAt': '2026-05-10T09:00:00Z',
        },
      ];

  /// Matches [_publicMasterReviews] (one 5★, one 4★) and the seeded
  /// `master-aaa` public-detail `avgRating`.
  ///
  /// INSTANCE (not static): once the client's `POST /reviews` lands the
  /// aggregate moves and the 5★ bucket gains the new review — see
  /// [publicMasterReviewLanded].
  Map<String, dynamic> _publicMasterReviewSummaryEnvelope() =>
      _ok(<String, dynamic>{
        'avgRating': publicMasterReviewLanded
            ? kPublicMasterAvgRatingAfterReview
            : kPublicMasterAvgRatingBeforeReview,
        'reviewCount': publicMasterReviewLanded
            ? kPublicMasterReviewCountAfterReview
            : kPublicMasterReviewCountBeforeReview,
        'ratingDistribution': <Map<String, dynamic>>[
          <String, dynamic>{
            'rating': 5,
            'count': publicMasterReviewLanded ? 2 : 1,
          },
          <String, dynamic>{'rating': 4, 'count': 1},
          <String, dynamic>{'rating': 3, 'count': 0},
          <String, dynamic>{'rating': 2, 'count': 0},
          <String, dynamic>{'rating': 1, 'count': 0},
        ],
      });

  /// Returns [_publicMasterReviews] server-ordered by the `sort` wire value —
  /// mirrors [_masterReviewsFor]'s reordering so a future sort test on the
  /// public reviews screen has the same real-reorder guarantee.
  /// The review row the CLIENT's `POST /reviews` adds to `master-aaa`'s public
  /// list. `createdAt` is just BEFORE the harness's injected `kFixedNow`
  /// (2026-06-14 12:00 UTC), so it is genuinely the NEWEST row without being a
  /// future timestamp — the clock the app renders it against is the same
  /// injected one (M15: fixture clock and app clock must not disagree).
  static const Map<String, dynamic> _clientPublicReview = <String, dynamic>{
    'id': kClientReviewId,
    'clientDisplayName': 'Олена К.',
    'rating': 5,
    'comment': 'Дуже задоволена, дякую!',
    'createdAt': '2026-06-14T11:00:00Z',
    'serviceName': 'Манікюр з покриттям',
  };

  /// INSTANCE (not static): includes [_clientPublicReview] once the client's
  /// review has landed — see [publicMasterReviewLanded]. The new row is added
  /// BEFORE sorting, so it lands in the right place in every sort bucket.
  List<Map<String, dynamic>> _publicMasterReviewsFor(String? sort) {
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[
      ..._publicMasterReviews,
      if (publicMasterReviewLanded) _clientPublicReview,
    ];
    switch (sort) {
      case 'OLDEST':
        list.sort(
          (a, b) =>
              (a['createdAt'] as String).compareTo(b['createdAt'] as String),
        );
      case 'HIGHEST':
        list.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
      case 'LOWEST':
        list.sort((a, b) => (a['rating'] as int).compareTo(b['rating'] as int));
      case 'NEWEST':
      default:
        list.sort(
          (a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String),
        );
    }
    return list;
  }

  /// PUBLIC portfolio gallery for `salon-xyz` — THREE photos backing the
  /// "Про салон" tab's real photo rail (previously an unwired backend
  /// endpoint — see `salon_portfolio_notifier.dart`). Shape matches
  /// `MediaFileResponse`. Unlike [_salonMasters]/[_salonReviews] above (the
  /// custom `PageResponse` shape [_searchEnvelope] builds), this list is
  /// wrapped in Spring's DEFAULT `Page<T>` envelope by
  /// [_salonPortfolioEnvelope] below — the read goes through the GENERATED
  /// `MediaControllerApi.getSalonPortfolio` client (built_value
  /// deserialization), not the salon repository's raw-Dio Pageable
  /// workaround the other two rails use.
  static const List<Map<String, dynamic>> _salonPortfolioPhotos =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'media-1',
          'entityType': 'SALON',
          'entityId': 'salon-xyz',
          'mediaType': 'PORTFOLIO',
          'url': 'https://cdn.beautica.ua/portfolio/salon-xyz/1.jpg',
          'createdAt': '2026-05-01T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'media-2',
          'entityType': 'SALON',
          'entityId': 'salon-xyz',
          'mediaType': 'PORTFOLIO',
          'url': 'https://cdn.beautica.ua/portfolio/salon-xyz/2.jpg',
          'createdAt': '2026-05-02T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'media-3',
          'entityType': 'SALON',
          'entityId': 'salon-xyz',
          'mediaType': 'PORTFOLIO',
          'url': 'https://cdn.beautica.ua/portfolio/salon-xyz/3.jpg',
          'createdAt': '2026-05-03T10:00:00Z',
        },
      ];

  /// Builds the `ApiResponse<Page<MediaFileResponse>>` envelope
  /// `PageMediaFileResponse`'s built_value deserializer expects — Spring's
  /// default Page shape (`content`/`totalElements`/…), NOT the custom
  /// `PageResponse` shape [_searchEnvelope] builds.
  Map<String, dynamic> _salonPortfolioEnvelope() => _ok(<String, dynamic>{
    'content': _salonPortfolioPhotos,
    'totalElements': _salonPortfolioPhotos.length,
    'totalPages': 1,
    'size': _salonPortfolioPhotos.length,
    'number': 0,
    'first': true,
    'last': true,
    'numberOfElements': _salonPortfolioPhotos.length,
    'empty': false,
  });

  // ── My-bookings / booking-detail / cancel state (track 14.x) ───────────────
  //
  // A single seeded CONFIRMED booking (`booking-1`) drives the client's «МОЇ
  // ЗАПИСИ» → «Деталі запису» → «Скасувати запис» journey end-to-end. Cancel
  // mutates [bookingStatus] to `CANCELLED` and stores the free-text note, so a
  // re-fetch of the list (page 0 per status) and the detail moves the booking
  // out of Майбутні and into Скасовані as a client cancellation. `PENDING` is
  // retired (auto-confirm) — the seed is CONFIRMED, visible immediately.

  /// Current wire status of the seeded `booking-1`. Starts CONFIRMED; a
  /// successful cancel flips it to CANCELLED.
  String bookingStatus = 'CONFIRMED';

  /// Server-computed `canReview` for the seeded booking (Phase 14.6). A flow
  /// that exercises the leave-review journey seeds this `true` (with
  /// [bookingStatus] = `COMPLETED`); a successful `POST /reviews` flips it
  /// `false` so a detail re-fetch re-resolves the entry CTA away and a stale
  /// deep link lands on the not-reviewable info state.
  bool bookingCanReview = false;

  /// `POST /reviews` call count + the last rating/comment/bookingId submitted
  /// (Phase 14.6). Asserted by the leave-review flow.
  int createReviewCalls = 0;
  int? lastReviewRating;
  String? lastReviewComment;
  String? lastReviewBookingId;

  /// True once a `POST /reviews` has landed — the review the CLIENT just wrote
  /// is now part of `master-aaa`'s PUBLIC review data.
  ///
  /// Exists for the `client_review_refreshes_master_surfaces_flow` regression:
  /// the three master public surfaces are independent `keepAlive` caches with a
  /// 5-minute TTL, so an E2E can only tell "refetched" from "served stale" if
  /// the SERVER's answer actually MOVES after the write. Flipping this changes
  /// three fixtures at once, exactly as the real backend would:
  ///   • `_publicMasterDetailEnvelope` → [kPublicMasterAvgRatingAfterReview] /
  ///     [kPublicMasterDetailReviewCountAfterReview] (the profile stat tiles);
  ///   • `_publicMasterReviewSummaryEnvelope` → the same average and
  ///     [kPublicMasterSummaryCountAfterReview] (the aggregate card);
  ///   • `_publicMasterReviewsFor` → appends [kClientReviewId] to every sort
  ///     bucket (the review the client just wrote).
  ///
  /// Starts `false`, so every pre-existing flow sees the original fixtures
  /// unchanged; only a flow that BOTH posts a review AND then reads the public
  /// master surfaces is affected.
  bool publicMasterReviewLanded = false;

  /// The SALON-side twin of [publicMasterReviewLanded] (phase 233). Flipped by
  /// the same `POST /reviews`, because a review of a salon-employed master
  /// moves `salons.avg_rating` / `review_count` too — `ReviewEventListener`
  /// recalculates BOTH aggregates before the 201 returns.
  ///
  /// Exists for the `client_review_refreshes_salon_surfaces_flow` regression,
  /// for exactly the reason its master twin does: the three salon surfaces are
  /// independent `keepAlive` caches behind a 5-minute TTL, so an E2E can only
  /// tell "refetched" from "served stale" if the SERVER's answer genuinely
  /// MOVES after the write. Flipping this changes three fixtures at once:
  ///   • `_publicSalonDetailEnvelope` → the hero card's ★ rating / count;
  ///   • `_salonReviewSummaryEnvelope` → the same average, plus the 5★ bucket;
  ///   • `_salonReviewsFor` → appends [kSalonClientReviewId] to every bucket.
  ///
  /// Starts `false`, so every pre-existing salon flow sees the original
  /// fixtures unchanged.
  bool salonReviewLanded = false;

  /// `salon-xyz`'s review aggregate — ONE number per field, shared by the
  /// public DETAIL and the review SUMMARY endpoints alike.
  ///
  /// These used to disagree (detail `reviewCount: 3` vs summary `4`) — the
  /// same defanging that made the master fixture toothless before it was
  /// reconciled. The seeded truth is FOUR: [_salonReviews] has four rows and
  /// the summary's own distribution (one 5★, two 4★, one 3★) sums to four, and
  /// (5+4+4+3)/4 = 4.0 exactly.
  ///
  /// The base is deliberately SMALL. One more 5★ across a large base cannot
  /// shift a 1-decimal average (the master fixture's old 24-review base put
  /// 123/25 = 4.92 → still «4.9»), and an assertion that cannot move cannot
  /// distinguish a refetch from a `keepAlive` cache hit. Across four it does:
  /// (5+4+4+3+5)/5 = 4.2 EXACTLY — a full 0.2 move, no rounding boundary.
  static const double kSalonAvgRatingBeforeReview = 4.0;
  static const double kSalonAvgRatingAfterReview = 4.2;
  static const int kSalonReviewCountBeforeReview = 4;
  static const int kSalonReviewCountAfterReview = 5;

  /// Id of the review row the client's `POST /reviews` adds to `salon-xyz`'s
  /// public list. Distinct from the seeded `salon-review-*` rows so
  /// `find.byKey(Key('salon-review-$kSalonClientReviewId'))` is unambiguous
  /// proof the list was re-fetched rather than served from the keepAlive cache.
  static const String kSalonClientReviewId = 'salon-r-new';

  /// `master-aaa`'s review aggregate — ONE number per field, shared by EVERY
  /// endpoint that reports it.
  ///
  /// These used to disagree: the public DETAIL said `reviewCount: 24` while the
  /// review SUMMARY for the same master said `2`, and the search card / salon
  /// roster said `24` again. A count-consistency regression between two of
  /// those payloads was therefore invisible — the fixture already disagreed by
  /// design, so no assertion could tell a bug from the baseline.
  ///
  /// The reconciled base is the SEEDED TRUTH, not the larger number: the
  /// summary's own `ratingDistribution` (one 5★ + one 4★) and
  /// [_publicMasterReviews] (two rows) both say TWO reviews, and the average is
  /// exactly (5+4)/2. Reconciling upward to 24 would have required inventing a
  /// 24-wide distribution AND would have made the post-review assertions
  /// toothless: one more 5★ review cannot move a 1-decimal average across 24
  /// existing ones (123/25 = 4.92 → still «4.9»), so the E2E could no longer
  /// tell a genuine re-fetch from a stale `keepAlive` cache by value.
  ///
  /// After the client's 5★ lands: three reviews, (5+5+4)/3 = 4.67 → «4.7».
  /// Both fields move, and both moves are arithmetically derivable from the
  /// review rows the list endpoint actually returns.
  static const double kPublicMasterAvgRatingBeforeReview = 4.5;
  static const double kPublicMasterAvgRatingAfterReview = 4.7;
  static const int kPublicMasterReviewCountBeforeReview = 2;
  static const int kPublicMasterReviewCountAfterReview = 3;

  /// Id of the review row the client's `POST /reviews` adds to `master-aaa`'s
  /// public list. Distinct from the seeded `pub-r*` rows so
  /// `find.byKey(Key('master-review-$kClientReviewId'))` is unambiguous proof
  /// that the list was re-fetched rather than served from the keepAlive cache.
  static const String kClientReviewId = 'pub-r-new';

  /// Server-computed `providerCanReviewClient` for the seeded booking (track
  /// 7.x Wave B). Gates `BookingDetailScreen`'s own «Залишити відгук про
  /// клієнта» CTA (see `_DetailBody._providerActions`) exactly like
  /// [bookingCanReview] gates the CLIENT footer. A flow that exercises the
  /// leave-client-feedback journey seeds this `true` (with [bookingStatus] =
  /// `COMPLETED`); a successful `POST /client-reviews` flips it `false` so a
  /// detail re-fetch (triggered by the screen's `bookingDetailProvider`
  /// invalidation on success) re-resolves the CTA away, mirroring
  /// [bookingCanReview]'s post-review flip.
  bool bookingProviderCanReviewClient = true;

  /// `POST /client-reviews` call count + the last rating/comment/bookingId
  /// submitted (track 7.x Wave B — the PROVIDER→CLIENT «ВІДГУК ПРО КЛІЄНТА»
  /// mirror of [createReviewCalls] above). Asserted by the
  /// leave-client-feedback flow.
  int createClientReviewCalls = 0;
  int? lastClientReviewRating;
  String? lastClientReviewComment;
  String? lastClientReviewBookingId;

  /// `GET /users/me/rating` fixture (track 7.x Wave B — «Мій рейтинг»). Null
  /// [myRatingAvgRating] means no reviews yet (the empty state); a flow that
  /// exercises the rated state overrides it before booting.
  double? myRatingAvgRating;
  int myRatingReviewCount = 0;
  int getMyRatingCalls = 0;

  /// Wire `{rating, count}` buckets for the rated-state distribution table
  /// (QA follow-up — the two-column `RatingSummaryCard` breakdown). Null
  /// means the route omits `ratingDistribution` entirely (the repository's
  /// null-list branch — all-zero distribution). Deliberately scrambled wire
  /// order by default (matches `_masterReviewSummaryEnvelope`'s sibling
  /// fixture): a flow asserting the per-star counts render must prove the
  /// REAL `GET /users/me/rating` HTTP round-trip folds this correctly, not
  /// just a synthetic ClientRating built in a widget test.
  List<Map<String, dynamic>>? myRatingDistribution;

  /// The client's free-text cancellation note, captured on cancel (may be null
  /// — a silent self-cancellation).
  String? bookingClientCancellationNote;

  /// The seeded booking's current start/end instants (ISO-8601 UTC). Mutable so
  /// a successful RESCHEDULE (`PATCH /bookings/{id}/reschedule`, track 24.x)
  /// moves the booking to a new time and a subsequent detail / My-Bookings
  /// re-fetch reflects it. The 90-minute span mirrors the booked service
  /// (`pub-assign-1`, `effectiveDurationMinutes: 90`).
  ///
  /// ⚠ NOW-RELATIVE ON PURPOSE — DO NOT PIN THESE BACK TO AN ABSOLUTE LITERAL.
  /// They used to read `'2026-07-20T15:00:00Z'`, i.e. the SAME expired instant
  /// that caused the 2026-07-20 booking-detail incident
  /// (`scripts/forbid_stale_future_date_fixture.sh` was written for it, but it
  /// only scans `test/features/booking/` — `integration_test/` was outside its
  /// reach, so this copy of the bomb survived and went off silently on
  /// 2026-07-20). `BookingDisplayX.isPast` compares against the REAL device
  /// clock (`DateTime.now()`), NOT the harness's `clockProvider` override, so
  /// once that instant passed, the seeded CONFIRMED booking started reading as
  /// ELAPSED: «Деталі запису» drops add-to-calendar, «Перенести» and
  /// «Скасувати запис» and offers «Записатись знову» instead. Every flow
  /// asserting a CONFIRMED affordance therefore fails on a DATE rather than on
  /// a code change.
  ///
  /// Anchored a week out from `DateTime.now()` instead — the same fix
  /// `test/helpers/booking_fixture_dates.dart`'s `futureBookingStart()` applies
  /// on the widget tier. A flow that needs an ELAPSED booking still overrides
  /// both fields explicitly (see `client_elapsed_booking_readonly_flow_test`),
  /// and every consumer derives its expected date from these fields rather
  /// than re-typing one, so nothing is coupled to the literal.
  String bookingStartsAt = _futureInstant(const Duration(days: 7));
  String bookingEndsAt = _futureInstant(const Duration(days: 7, minutes: 90));

  /// The seeded booking's frozen price pair, exactly as the backend emits it:
  /// `priceAtBooking` is the floor, `priceMaxAtBooking` the RANGE ceiling.
  ///
  /// [bookingPriceMax] defaults to `null`, which is NOT a missing value — the
  /// backend sets the ceiling only when the master genuinely left the service
  /// as a `RANGE` at booking time, so null means "this booking has one price"
  /// and every other flow in the suite keeps rendering «650 ₴» exactly as
  /// before. A flow that wants the band seeds both (see
  /// `booking_price_band_flow_test.dart`).
  ///
  /// NOTE: the `priceMaxAtBooking` key is now ALWAYS emitted, with an explicit
  /// `null` when unset — that is what the real endpoint puts on the wire, and
  /// the generated deserializer's `if (valueDes == null) continue;` treats an
  /// explicit null and an absent key identically. Emitting it unconditionally
  /// means the suite exercises the real payload shape rather than a
  /// pre-contract one.
  num bookingPrice = 650;
  num? bookingPriceMax;

  /// Phase 240 — the master's public rating, as carried BY THE BOOKING.
  ///
  /// Both default to `null`, which is the PRE-240 wire shape (a backend that
  /// simply omits the fields), so every pre-existing flow keeps seeing exactly
  /// the payload it saw before and its assertions are untouched. A flow that
  /// exercises the rating surfaces sets them before boot.
  ///
  /// They are deliberately SEPARATE knobs rather than one: the whole point of
  /// `BookingDisplayX.masterDisplayRating` is that the average and the count
  /// disagree in three distinct ways (null average, stale `0.0` average,
  /// known-zero count), and a single knob could not seed those apart.
  ///
  /// `null` here is NOT the same as `0`. A null COUNT means "unknown" (a
  /// pre-240 backend), which must not suppress a genuine average; a `0` count
  /// is a positive assertion of "no reviews". Keep them independently
  /// settable so a flow can seed either.
  num? bookingMasterAvgRating;
  int? bookingMasterReviewCount;

  /// `PATCH /bookings/{id}/cancel` call count + the last comment sent.
  int cancelBookingCalls = 0;
  String? lastCancelComment;

  /// Track 27.x Wave A — `PATCH /bookings/{id}/decline` (PROVIDER decline)
  /// call count + the last `StatusUpdateRequest` body the fake actually
  /// received (`comment`/`cancellationReason`, wire keys as
  /// `booking_repository.dart`'s `declineBooking` serialises them). Flips
  /// [bookingStatus] to `DECLINED` on success — mirrors the client cancel
  /// route above, but on the PROVIDER write path.
  int declineBookingCalls = 0;
  String? lastDeclineComment;
  String? lastDeclineCancellationReason;

  /// Track 27.x Wave A — `PATCH /bookings/{id}/complete` (PROVIDER complete,
  /// no request body) call count. Flips [bookingStatus] to `COMPLETED` on
  /// success.
  int completeBookingCalls = 0;

  /// `PATCH /bookings/{id}/reschedule` call count + the last `newStartsAt`
  /// wire value the client submitted (track 24.x auto-confirm reschedule).
  int rescheduleBookingCalls = 0;
  String? lastRescheduleNewStartsAt;

  /// Track 27.x/MO-6 — the seeded booking's `appointmentId`, `null` by
  /// default (a plain single-service booking). A flow proving the
  /// appointment-child provider-write routing (`BookingDetailScreen`'s
  /// `_confirmDecline`/`_confirmComplete` routing to
  /// `AppointmentRepository.completeAppointment`/`declineAppointment` instead
  /// of the per-booking endpoints) sets this to a non-null id BEFORE booting
  /// the harness, so `GET /bookings/booking-1` serves a booking whose
  /// `appointmentId` is non-null — mirroring how `bookingPriceMax` is seeded
  /// for the RANGE-price flow. The per-booking `/decline`/`/complete` ROUTES
  /// below still exist and would still (unrealistically) succeed if hit — the
  /// real backend's `assertNotAppointmentChild` 409 guard is NOT reproduced
  /// here; the routing proof instead rests on the write count staying at 0 on
  /// [declineBookingCalls]/[completeBookingCalls] while the hand-faked
  /// `AppointmentRepository` (see
  /// `master_appointment_child_booking_actions_flow_test.dart`) records the
  /// call — the same "prove it went to the OTHER path" shape every other
  /// appointment-vs-booking flow in this suite already uses.
  String? bookingAppointmentId;

  /// Track 27.x/MO-6 (PER-SERVICE decline) — a SIBLING service of the same
  /// multi-service visit as `booking-1` (both carry [bookingAppointmentId]).
  /// Served at the concrete `GET /bookings/booking-2` route below with its OWN
  /// status ([siblingBookingStatus]), INDEPENDENT of `booking-1`'s
  /// [bookingStatus]. This is the "reflect per-item status" surface the
  /// per-service decline regression needs: declining ONE child
  /// (`declineChild('booking-1')`) must leave this sibling CONFIRMED — the old
  /// whole-visit decline flipped BOTH. A flow that exercises the sibling seeds
  /// [bookingAppointmentId] before booting so `booking-2` reads as a real
  /// visit child.
  String siblingBookingStatus = 'CONFIRMED';

  /// `GET /bookings/booking-2` (sibling detail) call count — non-zero proves
  /// the sibling detail actually re-fetched through the real HTTP boundary
  /// (not a stale cached CONFIRMED value).
  int getSiblingBookingDetailCalls = 0;

  /// Flips ONLY the tapped child's status to DECLINED, keyed on [bookingId] —
  /// `booking-1` moves [bookingStatus], `booking-2` moves
  /// [siblingBookingStatus]. Because the per-service decline fix passes THIS
  /// child's own id (never the whole visit), declining `booking-1` here leaves
  /// `booking-2` CONFIRMED. The old whole-visit `declineAppointment` would have
  /// moved every child at once — this per-item routing is exactly what makes
  /// the sibling assertion a genuine regression guard.
  void declineChild(String bookingId) {
    if (bookingId == 'booking-2') {
      siblingBookingStatus = 'DECLINED';
    } else {
      bookingStatus = 'DECLINED';
    }
  }

  /// Track 30.x (PER-ITEM reschedule) — `booking-2`'s OWN start/end window,
  /// INDEPENDENT of `booking-1`'s [bookingStartsAt]/[bookingEndsAt], mirroring
  /// how [siblingBookingStatus] is independent of [bookingStatus]. Defaults to
  /// the SAME instant as `booking-1` (both seeded as if the visit were still
  /// contiguous) with the sibling's own 60-minute duration
  /// (`durationMinutesAtBooking: 60` in [_seededSiblingBookingJson]) — until
  /// [rescheduleChild] moves one of them, at which point the two diverge. This
  /// is the "did the sibling's window survive untouched" surface the per-item
  /// reschedule regression needs: moving `booking-1` must leave THIS pair
  /// byte-for-byte unchanged (track 30.x's locked "no cascade, no
  /// gap-closing" invariant) — the retired whole-visit reschedule would have
  /// moved every child's window at once.
  String siblingBookingStartsAt = _futureInstant(const Duration(days: 7));
  String siblingBookingEndsAt = _futureInstant(
    const Duration(days: 7, minutes: 60),
  );

  /// Moves ONLY the tapped child's own start/end window, keyed on [bookingId]
  /// — mirrors [declineChild]'s per-child field routing. `booking-1` moves
  /// [bookingStartsAt]/[bookingEndsAt], `booking-2` moves its OWN
  /// [siblingBookingStartsAt]/[siblingBookingEndsAt]. Because the per-item
  /// reschedule fix passes THIS child's own id (never the whole visit),
  /// rescheduling `booking-1` here leaves `booking-2`'s window untouched — the
  /// old whole-visit `rescheduleAppointment` would have moved every child's
  /// window in lockstep.
  void rescheduleChild(String bookingId, DateTime newStart, DateTime newEnd) {
    if (bookingId == 'booking-2') {
      siblingBookingStartsAt = newStart.toIso8601String();
      siblingBookingEndsAt = newEnd.toIso8601String();
    } else {
      bookingStartsAt = newStart.toIso8601String();
      bookingEndsAt = newEnd.toIso8601String();
    }
  }

  /// `GET /bookings/booking-1` (detail) + `GET /bookings/me` (list) call
  /// counts. A reschedule invalidates BOTH `bookingDetailProvider(id)` and
  /// `myBookingsProvider(upcoming)`, so a test asserts these counters climb
  /// AFTER the submit — proving each invalidation actually re-fetched (not a
  /// silent no-op). `getMyBookingsCalls` counts every status fan-out call; the
  /// upcoming tab fetches the single CONFIRMED status.
  int getBookingDetailCalls = 0;
  int getMyBookingsCalls = 0;

  /// `GET /bookings/me/booked-days` call count (Phase 7.6 day rail).
  int bookedDaysCalls = 0;

  /// The raw `from`/`to` query params of the MOST RECENT
  /// `GET /bookings/me/booked-days` call, as Dio actually sent them.
  ///
  /// mobile-qa (2026-08-02, backlog :226 audit) — the fixed reply below never
  /// inspects the request window (it always echoes [bookingStartsAt]'s own
  /// day), so without this capture nothing at the E2E tier could tell a
  /// Kyiv-anchored `from`/`to` apart from a device/UTC-day one — the exact
  /// gap `kyiv_day_boundary_flow_test.dart` closes for the ±180-day window
  /// `bookedDaysProvider` (`booked_days_notifier.dart`) sends.
  Map<String, dynamic>? lastBookedDaysQuery;

  /// The FULL raw query map (page/size/sort/status, as Dio actually sent it —
  /// ints stay ints, the repeated `status` stays a `List<String>`) of the
  /// MOST RECENT `GET /bookings/me` call. Mobile-qa pagination/sort flow
  /// (Step 2.7 Rule 3b) — lets a test pin the exact `sort=startsAt,<asc|desc>`
  /// wire value per tab at the HTTP boundary, not just the mapped domain
  /// argument the unit suite already covers.
  ///
  /// Populated UNCONDITIONALLY by the `/bookings/me` route callback itself —
  /// on EVERY hit, whether or not [seedManyBookingsDataset] was ever called.
  /// It used to be assigned only inside [_slicedBookingsPageEnvelope] (the
  /// opt-in dataset branch), so any flow that never seeds a dataset — e.g.
  /// `master_bookings_flow_test.dart` — left this `null` forever even though
  /// the request genuinely reached the fake and the screen rendered real
  /// data from [_bookingsPageEnvelope]. A `last*Query` telemetry field that
  /// only populates on one opt-in code path is a silent-null footgun: do NOT
  /// move this assignment back into a status-specific branch — keep it at
  /// the top of the shared route callback, before any dispatch.
  Map<String, dynamic>? lastMyBookingsQuery;

  /// The seeded booking's provider affiliation (phase 232). Defaults to the
  /// INDEPENDENT_MASTER shape every pre-existing flow already asserts against:
  /// no salon name, no salon id.
  ///
  /// ⚠️ [bookingSalonId] and [bookingSalonName] are SEPARATE knobs on purpose —
  /// seeding one without the other is a legitimate (if unusual) wire shape, and
  /// `booking_mapper_test` pins that neither is derived from the other. A flow
  /// that wants a realistic salon booking seeds all three fields together:
  /// ```dart
  /// final fb = FakeBackend()
  ///   ..bookingMasterType = 'SALON_MASTER'
  ///   ..bookingSalonId = 'salon-xyz'
  ///   ..bookingSalonName = 'Студія Краси «Камелія»';
  /// ```
  /// `salon-xyz` is the id the public-salon fixtures above already serve, so
  /// the review fan-out lands on a salon this fake can actually render.
  String bookingMasterType = 'INDEPENDENT_MASTER';
  String? bookingSalonName;
  String? bookingSalonId;

  /// The enriched `BookingDetailResponse` body for the seeded booking, built
  /// from the CURRENT mutable status/note so a post-cancel re-fetch reflects
  /// the new state. Wire keys mirror the DTO the [BookingMapper] reads.
  Map<String, dynamic> _seededBookingJson() => <String, dynamic>{
    'id': 'booking-1',
    'masterId': 'master-aaa',
    'masterFirstName': 'Софія',
    'masterLastName': 'Бондар',
    'masterAvatarUrl': null,
    'masterType': bookingMasterType,
    'salonName': bookingSalonName,
    // Phase 232. Emitted UNCONDITIONALLY (not behind an `if`, unlike the
    // Phase-240 rating pair below) because `null` is this field's real
    // steady-state value: the default seeded booking is an INDEPENDENT_MASTER
    // booking, and the mapper must map that null cleanly rather than treat it
    // as a missing field. A flow that needs the salon half seeds all three of
    // [bookingSalonId] / [bookingSalonName] / [bookingMasterType].
    'salonId': bookingSalonId,
    // Phase 7.2 — the counterparty as the PROVIDER sees it. Seeded from the
    // same [clientFirstName]/[clientLastName] the `/users/me` handler serves,
    // so the master's booking detail shows the client whose session the client
    // flows drive; a divergence here would let the provider-view flow pass
    // against a name no other surface uses.
    'clientId': 'client-1',
    'clientFirstName': clientFirstName,
    'clientLastName': clientLastName,
    // The booked service's id MUST match one of `master-aaa`'s PUBLIC
    // catalogue services (`_publicMasterServices`) so the reschedule helper
    // (`startBookingReschedule`) can resolve the booked `MasterService` by id
    // from `GET /masters/master-aaa/services`. `pub-assign-1` is
    // «Манікюр з покриттям», 90 min — consistent with the fields below.
    'masterServiceId': 'pub-assign-1',
    'serviceName': 'Манікюр з покриттям',
    'categoryName': 'Манікюр',
    'cityLabel': 'Київ',
    'districtLabel': 'Печерський',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'durationMinutesAtBooking': 90,
    'priceAtBooking': bookingPrice,
    'priceMaxAtBooking': bookingPriceMax,
    'startsAt': bookingStartsAt,
    'endsAt': bookingEndsAt,
    'status': bookingStatus,
    'canReview': bookingCanReview,
    'providerCanReviewClient': bookingProviderCanReviewClient,
    'clientComment': null,
    'providerComment': null,
    'clientCancellationNote': bookingClientCancellationNote,
    'masterProfessionalTitle': 'Майстриня манікюру',
    // Phase 240. Emitted ONLY when seeded, so the default payload keeps the
    // PRE-240 shape (fields absent entirely) and every pre-existing flow's
    // assertions are untouched. An absent `masterReviewCount` is exactly the
    // "unknown count" case `masterDisplayRating` must not treat as zero.
    if (bookingMasterAvgRating != null)
      'masterAvgRating': bookingMasterAvgRating,
    if (bookingMasterReviewCount != null)
      'masterReviewCount': bookingMasterReviewCount,
    'locationNote': null,
    'appointmentId': bookingAppointmentId,
  };

  /// The enriched `BookingDetailResponse` body for the SIBLING child
  /// (`booking-2`) of the same visit as `booking-1` — a SECOND service of the
  /// visit, carrying the same [bookingAppointmentId] but its OWN independent
  /// [siblingBookingStatus]. Distinct `serviceName` so a rendered assertion
  /// can tell the two children apart; same master/window as `booking-1` so its
  /// provider footer offers the same CONFIRMED affordances until (and only if)
  /// it is itself declined.
  Map<String, dynamic> _seededSiblingBookingJson() => <String, dynamic>{
    'id': 'booking-2',
    'masterId': 'master-aaa',
    'masterFirstName': 'Софія',
    'masterLastName': 'Бондар',
    'masterAvatarUrl': null,
    'masterType': 'INDEPENDENT_MASTER',
    'salonName': null,
    'clientId': 'client-1',
    'clientFirstName': clientFirstName,
    'clientLastName': clientLastName,
    'masterServiceId': 'pub-assign-2',
    'serviceName': 'Дизайн нігтів',
    'categoryName': 'Манікюр',
    'cityLabel': 'Київ',
    'districtLabel': 'Печерський',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'durationMinutesAtBooking': 60,
    'priceAtBooking': 400,
    'priceMaxAtBooking': null,
    'startsAt': siblingBookingStartsAt,
    'endsAt': siblingBookingEndsAt,
    'status': siblingBookingStatus,
    'canReview': false,
    'providerCanReviewClient': false,
    'clientComment': null,
    'providerComment': null,
    'clientCancellationNote': null,
    'masterProfessionalTitle': 'Майстриня манікюру',
    'locationNote': null,
    'appointmentId': bookingAppointmentId,
  };

  /// The `ApiResponse<PageResponse<BookingDetailResponse>>` envelope for the
  /// seeded booking, returned ONLY for the status matching its current
  /// [bookingStatus]; every other status filter returns an empty page.
  ///
  /// [statusFilter] is the parsed repeated-`status` param, NOT a raw scalar —
  /// see [_bookingStatusesFrom]. It must stay list-shaped: `getMyBookings`
  /// sends its `Set<BookingStatus>` with Dio's `ListFormat.multi`, so
  /// `queryParameters['status']` arrives as a `List` even for a single value.
  /// This branch used to read it as `query['status'] as String?`, which THREW
  /// a `TypeError` inside the route callback for every request the client
  /// actually makes — the failure surfaced as a repeatedly-retried empty list
  /// rather than as an error, so it read like "no bookings" instead of like a
  /// broken fake. The dataset branch ([_slicedBookingsPageEnvelope]) already
  /// parsed it correctly; only this one did not.
  Map<String, dynamic> _bookingsPageEnvelope(List<String>? statusFilter) {
    final bool matches =
        statusFilter == null || statusFilter.contains(bookingStatus);
    final List<Map<String, dynamic>> rows = matches
        ? <Map<String, dynamic>>[_seededBookingJson()]
        : <Map<String, dynamic>>[];
    return <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': <String, dynamic>{
        'data': rows,
        'page': 0,
        'size': 20,
        'totalElements': rows.length,
        'totalPages': rows.isEmpty ? 0 : 1,
      },
    };
  }

  // ── Pagination/sort regression dataset (mobile-qa, Step 2.7 Rule 3b) ──────
  //
  // The single-seeded-`booking-1` model above (`_bookingsPageEnvelope`) hands
  // back a HAND-PICKED bucket keyed only by the current status — it cannot
  // catch a dropped `sort` param or a reverted per-status client-side fan-out,
  // because it never actually sorts or globally paginates anything. That gap
  // is exactly how the two bugs this dataset regression-tests shipped green:
  //   Bug B — `getMyBookings` sent no `sort` param; the REAL backend defaults
  //     to `startsAt,DESC`, so page 0 of a >20-upcoming-booking client
  //     returned the 20 FARTHEST-future rows, hiding the very next
  //     appointment.
  //   Bug A — Минулі/Скасовані fanned out ONE request PER status, merging two
  //     independently-paginated streams client-side — only correct as a
  //     prefix, so a tab spanning >20 items in EACH of two statuses could
  //     drop/reshuffle rows on load-more.
  //
  // [_bookingsDataset] (opt-in via [seedManyBookingsDataset]) replaces the
  // single-seeded-booking route with a REAL (statuses, sort, page) slice over
  // a whole in-memory table — [_slicedBookingsPageEnvelope] filters + sorts +
  // paginates the FULL dataset on every call, the same shape work the real
  // `GET /bookings/me` does server-side (backend Phase 26.1 status union +
  // Phase 26.3 sort). A dropped `sort` param or a reverted fan-out surfaces
  // here exactly as it would against the real backend — this is deliberately
  // NOT a per-call hand-picked response.
  List<Map<String, dynamic>>? _bookingsDataset;

  /// Phase 227 (mobile-qa) rollout-safety-valve negative control. Whether
  /// this fake backend understands the `partition` query param (backend
  /// Phase 28.2). Defaults `true` — a modern, partition-aware backend.
  ///
  /// Setting this to `false` models an OLD backend that has not deployed
  /// Phase 28.2 yet: mirroring Spring's REAL behaviour of silently DROPPING
  /// an unrecognised query parameter (never a 400), [_slicedBookingsPageEnvelope]
  /// then never reads `partition` at all and falls straight through to
  /// `status`-only filtering — regardless of what the request actually
  /// carries. Composed with what the CALLER sends, this reproduces both
  /// halves of the Phase 227 rollout safety valve:
  ///   - caller sends BOTH `partition`+`status` (the real
  ///     `MyBookingsNotifier`) → degrades SAFELY to exactly the pre-227
  ///     `status`-only filter (today's shipped behaviour, elapsed CONFIRMED
  ///     rows still stuck in Майбутні — a known, harmless regression to the
  ///     old bug, not new wrong data).
  ///   - caller sends ONLY `partition`, no `status` → this fake (mirroring
  ///     Spring) applies NO filter at all → the entire unfiltered dataset
  ///     comes back. This is the negative control:
  ///     `client_my_bookings_partition_flow_test.dart` drives this second
  ///     case directly (bypassing the notifier, which never omits `status`)
  ///     to make legible exactly what the valve protects against.
  bool backendSupportsPartition = true;

  /// The instant [_slicedBookingsPageEnvelope] treats as "now" when computing
  /// [_partitionOf] — i.e. the fake's model of the BACKEND's own clock.
  /// Defaults to [kFixedNow], the SAME instant the harness overrides
  /// `clockProvider` to for the app under test (`e2e_boot_policy.dart`). In
  /// production the backend's clock and the app's clock are the same clock;
  /// in the harness the app believes "now" is `kFixedNow`, so the fake's
  /// server-side partition classification must agree, or fixtures anchored
  /// to `kFixedNow` (the documented [_bookingsDataset] seeding convention —
  /// see `client_my_bookings_pagination_sort_flow_test.dart`) drift into the
  /// wrong partition every day the real wall clock moves further past
  /// `kFixedNow`. A bare `DateTime.now().toUtc()` here was exactly that bug:
  /// harmless while filtering was status-only (pre-227), but Phase 227's
  /// `partition`-wins-outright precedence rule newly exposes every
  /// `kFixedNow`-anchored fixture to real-clock classification.
  ///
  /// This is DELIBERATELY a different clock than [_kFixtureDay] /
  /// `BookingDisplayX.isPast` (both real-clock, by design — see the module
  /// doc comment above [kFixedNow]): those model a presentation-only,
  /// UI-side "has this slot passed" signal that reads the DEVICE clock on
  /// purpose, never the injected one. The two clocks would only disagree on
  /// a row whose `endsAt` falls between `kFixedNow` and the real wall clock,
  /// and the two flows that combine partition classification with an
  /// `isPast`-gated detail screen (`client_my_bookings_partition_flow_test`,
  /// `client_elapsed_booking_readonly_flow_test`) deliberately anchor those
  /// specific rows at 2020/2035 — far enough from both clocks that this
  /// never arises. A test that genuinely needs a different "server now" may
  /// override this field directly; nothing in the suite currently does.
  DateTime serverNow = kFixedNow;

  /// The backend Phase 28.1/28.2 time-based partition membership of one
  /// [_bookingsDataset] row, mirroring `BookingSpecifications#partition`'s
  /// predicate (see `docs/backend-phases/phase-217-28.2-...md`) exactly:
  ///   - `CANCELLED`/`DECLINED` → `CANCELLED`.
  ///   - `CONFIRMED` with `endsAt` ON OR AFTER [now] → `UPCOMING`.
  ///   - `CONFIRMED` with `endsAt` BEFORE [now], or `COMPLETED`/
  ///     `NOT_COMPLETED` (elapsed by definition) → `PAST`.
  ///   - any other status (defensive — `UNKNOWN` has no real occurrence in
  ///     this dataset) matches NO partition, mirroring the backend never
  ///     classifying an unrecognised status into any of the three.
  static String? _partitionOf(Map<String, dynamic> row, DateTime now) {
    final String status = row['status'] as String;
    switch (status) {
      case 'CANCELLED':
      case 'DECLINED':
        return 'CANCELLED';
      case 'COMPLETED':
      case 'NOT_COMPLETED':
        return 'PAST';
      case 'CONFIRMED':
        final DateTime endsAt = DateTime.parse(row['endsAt'] as String);
        return endsAt.isBefore(now) ? 'PAST' : 'UPCOMING';
      default:
        return null;
    }
  }

  /// Whether dataset row [row] matches the requested [partition] WIRE VALUE
  /// — composes [_partitionOf]'s four disjoint COVER buckets with the
  /// backend's UNION *views* over them. `HISTORY` (mobile `BookingPartition
  /// .history`, backend `81e8166` `feat/booking-partition-history`) is
  /// `PAST ∪ CANCELLED` ≡ everything except `UPCOMING` — mirrors
  /// `AWAITING_CLOSURE`'s own category of view (a SUBSET rather than a fifth
  /// disjoint bucket); `AWAITING_CLOSURE` itself is not modelled by this
  /// fake, as no current suite drives it against `FakeBackend`. A row whose
  /// status [_partitionOf] cannot classify (the defensive `default: null`
  /// case — no real occurrence in this dataset) matches neither a disjoint
  /// bucket NOR `HISTORY`, mirroring the backend never classifying an
  /// unrecognised status into any partition at all.
  static bool _matchesPartition(
    Map<String, dynamic> row,
    String partition,
    DateTime now,
  ) {
    final String? bucket = _partitionOf(row, now);
    if (partition == 'HISTORY') return bucket != null && bucket != 'UPCOMING';
    return bucket == partition;
  }

  /// Builds one dataset row in the same wire shape [_seededBookingJson] uses,
  /// parameterized by [id]/[status]/[startsAt] so a test can seed a large,
  /// scrambled-insertion-order table. [duration] defaults to a realistic
  /// service length.
  Map<String, dynamic> datasetBookingRow({
    required String id,
    required String status,
    required DateTime startsAt,
    Duration duration = const Duration(minutes: 60),
  }) => <String, dynamic>{
    'id': id,
    'masterId': 'master-aaa',
    'masterFirstName': 'Софія',
    'masterLastName': 'Бондар',
    'masterAvatarUrl': null,
    'masterType': 'INDEPENDENT_MASTER',
    'salonName': null,
    'masterServiceId': 'pub-assign-1',
    'serviceName': 'Манікюр з покриттям',
    'categoryName': 'Манікюр',
    'cityLabel': 'Київ',
    'districtLabel': 'Печерський',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'durationMinutesAtBooking': duration.inMinutes,
    'priceAtBooking': bookingPrice,
    // Same contract as [_seededBookingJson]: always present, null unless the
    // flow seeded a genuine RANGE.
    'priceMaxAtBooking': bookingPriceMax,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': startsAt.add(duration).toIso8601String(),
    'status': status,
    'canReview': false,
    'clientComment': null,
    'providerComment': null,
    'clientCancellationNote': null,
    'masterProfessionalTitle': 'Майстриня манікюру',
    'locationNote': null,
  };

  /// Replaces the single-seeded-booking `/bookings/me` behaviour with a real
  /// (statuses, sort, page) slice over [bookings] — see the section doc above
  /// for why. Takes ownership of a COPY of [bookings]; the caller's own list
  /// is never mutated by the sort inside [_slicedBookingsPageEnvelope].
  void seedManyBookingsDataset(List<Map<String, dynamic>> bookings) {
    _bookingsDataset = List<Map<String, dynamic>>.of(bookings);
  }

  /// Reads the repeated `status` query param the same way `serviceTypeSlugs`
  /// is read elsewhere in this file (see [_slugsFrom]) — Dio's
  /// `ListFormat.multi` renders a `Set<BookingStatus>` as repeated bare
  /// `status=` params, so the handler sees either a raw `List` (2+ values) or
  /// a bare scalar (exactly one value). Absent → null (no filter — mirrors
  /// the real backend's "no status constraint" behaviour).
  List<String>? _bookingStatusesFrom(Map<String, dynamic> query) {
    final raw = query['status'];
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((Object? e) => e.toString()).toList(growable: false);
    }
    return <String>[raw.toString()];
  }

  /// Reads a multi-valued query param that the GENERATED api client sends via
  /// [encodeCollectionQueryParameter] — i.e. as a Dio [ListParam], not as a
  /// bare `List` and not as a scalar.
  ///
  /// This is the third shape this file has had to learn (see
  /// [_bookingStatusesFrom]'s doc comment for the first two, and the
  /// `TypeError`-inside-the-route-callback failure mode it describes — it is
  /// IDENTICAL here). Since the `d42c7cf1` OpenAPI regen, `serviceId` on
  /// `/masters/{id}/working-days` and `/masters/{id}/slots` is declared
  /// list-valued, so `master_controller_api.dart` wraps it in
  /// `ListParam<Object?>{value: [...], format: ListFormat.multi}`. Reading it
  /// as `query['serviceId'] as String?` threw inside the callback, the request
  /// failed, and `workingDaysProvider` went `AsyncError` — surfacing as
  /// `_WorkingDaysErrorBody` instead of the calendar grid rather than as an
  /// obviously-broken fake.
  ///
  /// Accepts all four shapes so the helper survives the next regen too:
  /// [ListParam] → its `value`; raw `List` → itself; scalar → one-element
  /// list; absent/null → null (no constraint).
  static List<String>? _multiQueryParam(
    Map<String, dynamic> query,
    String key,
  ) {
    final Object? raw = query[key];
    if (raw == null) return null;
    if (raw is ListParam) {
      return raw.value.map((Object? e) => e.toString()).toList(growable: false);
    }
    if (raw is List) {
      return raw.map((Object? e) => e.toString()).toList(growable: false);
    }
    return <String>[raw.toString()];
  }

  /// The FIRST value of a query param that this fake treats as scalar, read
  /// through the shape-tolerant [_multiQueryParam] rather than by casting.
  ///
  /// Use this for EVERY scalar query-param read instead of
  /// `query['key'] as String?`. The direct cast is banned by
  /// `scripts/forbid_raw_query_param_cast.sh` because it is a latent
  /// `TypeError`-inside-the-route-callback bomb: a param that is scalar today
  /// becomes a Dio [ListParam] the moment an OpenAPI regen re-declares it
  /// list-valued, and the throw surfaces as an ERROR BODY in the widget tree
  /// (or a silently-empty list), never as an obviously-broken fake. That exact
  /// bug has landed three times in this file — `status`, then `serviceId` on
  /// working-days, then `serviceId` on slots.
  ///
  /// Returns null when the param is absent or present-but-empty.
  static String? _scalarQueryParam(Map<String, dynamic> query, String key) {
    final List<String>? values = _multiQueryParam(query, key);
    if (values == null || values.isEmpty) return null;
    return values.first;
  }

  /// The single `serviceId` a request carried, for the (overwhelmingly common)
  /// single-service case — `null` when the param is absent entirely. Callers
  /// that care about the MULTI-service selection read [_multiQueryParam]
  /// directly; this is the scalar convenience view that the pre-existing
  /// `lastMaster…ServiceId` telemetry fields are typed for.
  static String? _serviceIdFrom(Map<String, dynamic> query) =>
      _scalarQueryParam(query, 'serviceId');

  /// Defensive int query-param read — mirrors `_pageFromRequest` elsewhere in
  /// this file: DioAdapter sometimes hands back the original Dart `int` dio
  /// was called with, sometimes a stringified value, depending on the
  /// transport path.
  int _intQueryParam(Map<String, dynamic> query, String key, int fallback) {
    final raw = query[key];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }

  /// The real (statuses, sort, page) slice over [_bookingsDataset] — see the
  /// section doc above. Filters the WHOLE dataset by the repeated `status`
  /// params (or no filter when absent), sorts the filtered set by `startsAt`
  /// in the direction the `sort` param carries — defaulting to `desc` when
  /// `sort` is ABSENT, mirroring the real endpoint's actual default (the
  /// precise gap Bug B exploited: no `sort` sent → server default
  /// `startsAt,DESC` → farthest-future page 0) — then slices out
  /// `[page*size, page*size+size)`. [lastMyBookingsQuery] is recorded by the
  /// caller (the shared `/bookings/me` route callback), not here — see that
  /// field's doc comment for why it must stay unconditional.
  ///
  /// Phase 227 (mobile-qa): also implements the backend 28.2 PRECEDENCE rule
  /// — when a `partition` param is present AND [backendSupportsPartition],
  /// it wins OUTRIGHT and `status` is not even consulted (mirrors
  /// `BookingService#getMyBookings`'s `statuses = partition != null ? null :
  /// …` — see phase-217's doc). When [backendSupportsPartition] is `false`,
  /// `partition` is never read at all (the old-backend model), so filtering
  /// falls through to `status` exactly as it did pre-227 — including the
  /// degenerate case where `status` is ALSO absent, which yields NO filter
  /// at all. That degenerate case is deliberate: it is the fake half of the
  /// Phase 227 rollout-safety-valve negative control.
  Map<String, dynamic> _slicedBookingsPageEnvelope(Map<String, dynamic> query) {
    final List<Map<String, dynamic>> dataset = _bookingsDataset!;
    final String? partition = backendSupportsPartition
        ? _scalarQueryParam(query, 'partition')
        : null;
    final List<String>? statuses = _bookingStatusesFrom(query);
    final String sort = _scalarQueryParam(query, 'sort') ?? 'startsAt,desc';
    final bool ascending = sort.endsWith(',asc');
    final int page = _intQueryParam(query, 'page', 0);
    final int size = _intQueryParam(query, 'size', 20);
    final DateTime now = serverNow;

    final List<Map<String, dynamic>> filtered =
        dataset
            .where(
              (Map<String, dynamic> b) => partition != null
                  ? _matchesPartition(b, partition, now)
                  : (statuses == null || statuses.contains(b['status'])),
            )
            .toList(growable: false)
          ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
            final DateTime aStart = DateTime.parse(a['startsAt'] as String);
            final DateTime bStart = DateTime.parse(b['startsAt'] as String);
            return ascending
                ? aStart.compareTo(bStart)
                : bStart.compareTo(aStart);
          });

    final int totalElements = filtered.length;
    final int totalPages = totalElements == 0
        ? 0
        : (totalElements / size).ceil();
    final int start = page * size;
    final int end = (start + size) > totalElements
        ? totalElements
        : start + size;
    final List<Map<String, dynamic>> rows = start >= totalElements
        ? const <Map<String, dynamic>>[]
        : filtered.sublist(start, end);

    return <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': <String, dynamic>{
        'data': rows,
        'page': page,
        'size': size,
        'totalElements': totalElements,
        'totalPages': totalPages,
      },
    };
  }

  // ── Route wiring ───────────────────────────────────────────────────────────

  // ── Status-flag routes (re-wired on every flag write) ─────────────────────
  //
  // `DioAdapter.onRoute` runs its `MockServerCallback` IMMEDIATELY (see
  // `http_mock_adapter/src/mixins/request_handling.dart` → `onRoute`, which
  // ends in `requestHandlerCallback(matcher)`), and `MockServer.replyCallback`
  // captures `statusCode` at that moment — only the DATA callback is invoked
  // per-request. Any route whose STATUS depends on a mutable [FakeBackend]
  // flag therefore CANNOT be registered once from [_wire]: the flag is still
  // at its default when the constructor runs, so the status is frozen there
  // forever while the body silently switches to the error envelope. That is a
  // fake that answers `201 {success:false, …}` / `200 {success:false, …}` — a
  // shape no real backend ever emits and no repository error path can see, so
  // the E2E asserting the error surface fails pointing at the SCREEN.
  //
  // These methods exist so the flag setters can re-register the route with the
  // status the flag now implies. Re-registration wins because
  // `Recording.mockResponse` keeps the LAST matcher that matches the request.
  //
  // RULE: never inline one of these back into [_wire], and never add a new
  // `server.reply*(<flag> ? … : …, …)` directly in [_wire] — give it a
  // `_wireX()` + re-wiring setter like these two.

  /// (Re-)registers `POST /api/v1/independent-masters/me/services`.
  /// See [createRejectDuplicate].
  void _wireCreateService() {
    _adapter.onRoute(
      '/api/v1/independent-masters/me/services',
      (server) =>
          server.replyCallback(_createRejectDuplicate ? 409 : 201, (req) {
            createServiceCalls++;
            if (_createRejectDuplicate) {
              return <String, dynamic>{
                'success': false,
                'data': <String, dynamic>{
                  'code': 'DUPLICATE_SERVICE',
                  'serviceName': createDuplicateServiceName,
                  'existingServiceDefId': 'def-existing',
                },
                'message': 'This service already exists',
              };
            }
            final body = _decodeBody(req.data);
            final defId = 'svc-$_nextServiceSeq';
            final assignId = 'assign-$_nextServiceSeq';
            final name = body['name'] as String? ?? 'New Service';
            final priceType = body['priceType'] as String? ?? 'FIXED';
            final newService = <String, dynamic>{
              'id': assignId,
              'masterId': 'user-master-1',
              'isActive': true,
              'priceType': priceType,
              'priceMin': body['price'] ?? body['priceMin'] ?? 0,
              'priceMax': body['priceMax'],
              'priceDisplay': '${body['price'] ?? body['priceMin'] ?? 0} ₴',
              'effectiveDurationMinutes': body['durationMinutes'] ?? 60,
              'serviceDefinition': <String, dynamic>{
                'id': defId,
                'name': name,
                'description': null,
                'category': body['categoryName'] ?? 'NAILS',
                'baseDurationMinutes': body['durationMinutes'] ?? 60,
                'bufferMinutesAfter': 0,
                'isActive': true,
                'priceType': priceType,
                'priceMin': body['price'] ?? body['priceMin'] ?? 0,
                'priceMax': body['priceMax'],
                'priceDisplay': '${body['price'] ?? body['priceMin'] ?? 0} ₴',
                'photoUrl': null,
              },
            };
            _nextServiceSeq++;
            _services.add(newService);
            lastCreatedService = newService;
            return _ok(newService);
          }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  /// (Re-)registers `DELETE /api/v1/favorites?targetType&targetId`.
  /// See [forceRemoveFavoriteFailure].
  void _wireRemoveFavorite() {
    final int? failStatus = _removeFavoriteFailureStatusCode;
    _adapter.onRoute(
      '/api/v1/favorites',
      (server) => server.replyCallback(failStatus ?? 204, (req) {
        removeFavoriteCalls++;
        lastRemoveFavoriteQuery = Map<String, dynamic>.from(
          req.queryParameters,
        );
        if (failStatus != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to remove favorite',
          };
        }
        return null;
      }),
      request: const Request(method: RequestMethods.delete),
    );
  }

  /// (Re-)registers `POST /api/v1/independent-masters/me/services/bulk`.
  /// See [bulkRejectDurationField] and [bulkRejectDuplicate].
  void _wireBulkCreateServices() {
    // POST /api/v1/independent-masters/me/services/bulk — the ONE "add services"
    // write (setup AND append, since beautica-backend c5e420f made it additive).
    // A DISTINCT path from the single-create route above (exact-string match, so
    // no collision).
    //
    // Three mutually exclusive outcomes, in the order the status ternary below
    // resolves them:
    //   • [bulkRejectDuplicate]     → 409 typed DUPLICATE_SERVICE envelope
    //                                 (whole batch rolled back; nothing written).
    //   • [bulkRejectDurationField] → 400 per-field envelope keyed on
    //                                 `items[<bulkRejectItemIndex>].durationMinutes`
    //                                 — the shape ErrorMapperInterceptor maps to
    //                                 ValidationFailure.fieldErrors, driving the
    //                                 screen's inline per-row error.
    //   • neither (default)         → 200 echoing one created service per item.
    // The duplicate wins when both are armed, matching the backend: the
    // uniqueness conflict aborts the transaction before per-field validation
    // feedback would matter. Arming both is a test-authoring mistake either way.
    //
    // The call counter + `lastBulkItems` capture run BEFORE the branch on every
    // outcome, so a flow can always prove the POST genuinely reached the network
    // (vs. being blocked client-side) even on the rejection paths.
    _adapter.onRoute(
      '/api/v1/independent-masters/me/services/bulk',
      (server) => server.replyCallback(
        _bulkRejectDuplicate ? 409 : (_bulkRejectDurationField ? 400 : 200),
        (req) {
          bulkCreateCalls++;
          final body = _decodeBody(req.data);
          final items = (body['items'] as List<dynamic>?) ?? const <dynamic>[];
          lastBulkItems = items;
          if (_bulkRejectDuplicate) {
            // Shape decoded by `HttpServiceRepository._isDuplicateService` /
            // `._extractDuplicateService`: the code lives at `data.code`, and
            // `serviceName` is explicitly null on the bulk envelope.
            return <String, dynamic>{
              'success': false,
              'data': <String, dynamic>{
                'code': 'DUPLICATE_SERVICE',
                'serviceName': null,
                'existingServiceDefId': bulkDuplicateExistingServiceDefId,
              },
              'message': 'One of these services is already in your menu',
            };
          }
          if (_bulkRejectDurationField) {
            return <String, dynamic>{
              'success': false,
              'message': 'Validation failed',
              'errors': <String, dynamic>{
                'items[$bulkRejectItemIndex].durationMinutes':
                    'Duration must be at most 480 minutes (8 hours)',
              },
            };
          }
          // Success: echo a created service per submitted item so the envelope
          // shape matches ApiResponse<List<MasterServiceResponse>>.
          final created = <Map<String, dynamic>>[];
          for (final item in items) {
            final map = item is Map<String, dynamic>
                ? item
                : <String, dynamic>{};
            final defId = 'svc-bulk-$_nextServiceSeq';
            created.add(<String, dynamic>{
              'id': 'assign-bulk-$_nextServiceSeq',
              'masterId': 'user-master-1',
              'isActive': true,
              'priceType': map['priceType'] ?? 'FIXED',
              'priceMin': map['price'] ?? map['priceMin'] ?? 0,
              'priceMax': map['priceMax'],
              'priceDisplay': '${map['price'] ?? map['priceMin'] ?? 0} ₴',
              'effectiveDurationMinutes': map['durationMinutes'] ?? 60,
              'serviceDefinition': <String, dynamic>{
                'id': defId,
                'name': 'Bulk service $_nextServiceSeq',
                'description': null,
                'category': 'NAILS',
                'baseDurationMinutes': map['durationMinutes'] ?? 60,
                'bufferMinutesAfter': 0,
                'isActive': true,
                'priceType': map['priceType'] ?? 'FIXED',
                'priceMin': map['price'] ?? map['priceMin'] ?? 0,
                'priceMax': map['priceMax'],
                'priceDisplay': '${map['price'] ?? map['priceMin'] ?? 0} ₴',
                'photoUrl': null,
              },
            });
            _nextServiceSeq++;
          }
          return _okList(created);
        },
      ),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  void _wire() {
    // POST /api/v1/auth/login — accept any email/password; use currentRole
    _adapter.onRoute(
      '/api/v1/auth/login',
      (server) => server.replyCallback(200, (_) {
        loginCalls++;
        final user = userJsonForRole(currentRole);
        return _authResponse(user);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/register — CLIENT / SALON_OWNER generic path.
    // Wired before /independent-master so the more specific route below takes
    // priority when the DioAdapter walks the list in insertion order.
    _adapter.onRoute(
      '/api/v1/auth/register',
      (server) => server.replyCallback(200, (_) {
        registerCalls++;
        return _ok(<String, dynamic>{
          'verificationRequired': true,
          'email': 'new@beautica.ua',
        });
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/register/independent-master
    _adapter.onRoute(
      '/api/v1/auth/register/independent-master',
      (server) => server.replyCallback(200, (_) {
        registerCalls++;
        return _ok(<String, dynamic>{
          'verificationRequired': true,
          'email': 'new@beautica.ua',
        });
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/verify-email
    _adapter.onRoute(
      '/api/v1/auth/verify-email',
      (server) => server.replyCallback(200, (_) {
        verifyEmailCalls++;
        return _authResponse(_masterUserJson);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/refresh
    _adapter.onRoute(
      '/api/v1/auth/refresh',
      (server) => server.reply(
        200,
        _ok(<String, dynamic>{
          'accessToken': 'fake-access-token',
          'refreshToken': 'fake-refresh-token',
        }),
      ),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/logout
    _adapter.onRoute(
      '/api/v1/auth/logout',
      (server) => server.replyCallback(200, (_) {
        logoutCalls++;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post),
    );

    // ── Beautica OTP task (Phase B) — password-reset OTP flow ────────────────

    // POST /api/v1/auth/forgot-password — unauthenticated OTP request.
    // Always returns a generic 200 (anti-enumeration) regardless of email.
    _adapter.onRoute(
      '/api/v1/auth/forgot-password',
      (server) => server.replyCallback(200, (req) {
        forgotPasswordCalls++;
        lastForgotPasswordEmail = _decodeBody(req.data)['email'] as String?;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/auth/verify-password-reset-otp — unauthenticated OTP verify.
    // Returns {resetTicket} on success.
    _adapter.onRoute(
      '/api/v1/auth/verify-password-reset-otp',
      (server) => server.replyCallback(200, (req) {
        verifyPasswordResetOtpCalls++;
        final body = _decodeBody(req.data);
        lastVerifyPasswordResetOtpEmail = body['email'] as String?;
        lastVerifyPasswordResetOtpCode = body['code'] as String?;
        return _ok(<String, dynamic>{'resetTicket': resetTicketToIssue});
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/users/me/change-password/request-otp — authenticated OTP
    // request (settings "change password" entry point). No request body.
    _adapter.onRoute(
      '/api/v1/users/me/change-password/request-otp',
      (server) => server.replyCallback(200, (_) {
        requestChangePasswordOtpCalls++;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post),
    );

    // POST /api/v1/auth/reset-password — completes the reset with the
    // resetTicket minted by verify-password-reset-otp. Void on success.
    _adapter.onRoute(
      '/api/v1/auth/reset-password',
      (server) => server.replyCallback(200, (req) {
        resetPasswordCalls++;
        final body = _decodeBody(req.data);
        lastResetPasswordTicket = body['resetTicket'] as String?;
        lastResetPasswordNewPassword = body['newPassword'] as String?;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/support/contact — multipart contact submission. The body is
    // FormData (a `request` JSON part + 0..5 `attachments` file parts), so we
    // do not decode it; the endpoint's contract is a 202 Accepted on success.
    _adapter.onRoute(
      '/api/v1/support/contact',
      (server) => server.replyCallback(202, (_) {
        supportContactCalls++;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // GET /api/v1/users/me
    // For the CLIENT role, returns the MUTABLE client body so a PATCH /users/me
    // round-trips on the next read (the edit screens invalidate
    // clientEditProfileProvider → re-fetch). Other roles keep the static fixture.
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) => server.replyCallback(200, (_) {
        getMeCalls++;
        return currentRole == UserRole.client
            ? _ok(_clientProfileBody())
            : _ok(userJsonForRole(currentRole));
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/users/me/rating — CLIENT's own aggregate two-sided rating
    // (track 7.x Wave B, «Мій рейтинг»). A DISTINCT path from `/users/me`
    // above — the mock router matches by exact path, so registration order
    // relative to the sibling `/users/me` GET/PATCH routes does not matter
    // here (unlike the `.../reviews` vs `.../reviews/summary` prefix case
    // elsewhere in this file).
    _adapter.onRoute(
      '/api/v1/users/me/rating',
      (server) => server.replyCallback(200, (_) {
        getMyRatingCalls++;
        return _ok(<String, dynamic>{
          'avgRating': myRatingAvgRating,
          'reviewCount': myRatingReviewCount,
          if (myRatingDistribution != null)
            'ratingDistribution': myRatingDistribution,
        });
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/clients/me/passport — CLIENT's derived BEAUTY PASSPORT
    // (backend 19.5). Wired now that HttpPassportRepository calls the real
    // endpoint: without this route the mock router 404s and the passport tab
    // renders its ERROR state instead of the empty variant the flow asserts.
    //
    // Defaults to the EMPTY passport (bookingsConsidered 0, no lists, no
    // budget) — the state a freshly-seeded fake client is in. Mutate
    // [passportBody] from a flow to serve a populated passport instead.
    _adapter.onRoute(
      '/api/v1/clients/me/passport',
      (server) => server.replyCallback(200, (_) {
        getPassportCalls++;
        return _ok(passportBody);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/users/me — CLIENT profile partial update (the shared,
    // CLIENT-callable profile endpoint the client edit screens hit via
    // UserControllerApi.updateMe). Merge-onto-cache: each key present in the body
    // overlays the in-memory state; keys absent from the body are preserved.
    //
    // CONTRACT NOTES the flow asserts against:
    //   • `instagram` is NEVER sent by ClientProfileRepository — if it ever
    //     appears in the body this would surface it (lastPatchMeBody captured).
    //   • a null `cityId` in the body is a VALID save (CLIENT location optional)
    //     and clears the city; the body still carries cityId (built_value emits
    //     it when the location slice is touched).
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) => server.replyCallback(200, (req) {
        patchMeCalls++;
        final body = _decodeBody(req.data);
        lastPatchMeBody = body;
        if (body.containsKey('firstName')) {
          clientFirstName = body['firstName'] as String? ?? clientFirstName;
        }
        if (body.containsKey('lastName')) {
          clientLastName = body['lastName'] as String? ?? clientLastName;
        }
        if (body.containsKey('phoneNumber')) {
          clientPhone = body['phoneNumber'] as String?;
        }
        // The location slice is sent only when the Location screen owns it; when
        // present, cityId/districtId/street/buildingNo/locationNote are applied
        // exactly as carried (including a null cityId — clears the city).
        if (body.containsKey('cityId')) {
          clientCityId = body['cityId'] as String?;
          clientCityName = clientCityId == null ? null : clientCityName;
        }
        if (body.containsKey('districtId')) {
          clientDistrictId = body['districtId'] as String?;
        }
        if (body.containsKey('street')) {
          clientStreet = body['street'] as String?;
        }
        if (body.containsKey('buildingNo')) {
          clientBuildingNo = body['buildingNo'] as String?;
        }
        if (body.containsKey('locationNote')) {
          clientLocationNote = body['locationNote'] as String?;
        }
        // The update response is an ApiResponseUserProfileResponse — return the
        // updated profile body so the generated client deserializes cleanly.
        return _ok(_clientProfileBody());
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // GET /api/v1/masters/me
    _adapter.onRoute(
      '/api/v1/masters/me',
      (server) => server.replyCallback(200, (_) {
        getMasterCalls++;
        return _masterDetailEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/{masterRowId}/reviews/summary — master received-
    // reviews header (Phase 4.5/4.6). Keyed on the MASTER-ROW id reported by
    // GET /masters/me, which the screen must read from the loaded profile —
    // NOT session.user.id. Registered BEFORE the list route (more specific
    // path first) so a `.../reviews` match can never shadow `.../reviews/summary`.
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/reviews/summary',
      (server) => server.replyCallback(200, (_) {
        getMasterReviewSummaryCalls++;
        return _masterReviewSummaryEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/{masterRowId}/reviews?sort=&page=&size= — master
    // received-reviews list. Reorders the fixture per the requested sort and
    // records the wire value so an E2E can assert both re-fetch AND reorder.
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/reviews',
      (server) => server.replyCallback(200, (req) {
        getMasterReviewsCalls++;
        lastGetMasterReviewsSort = _scalarQueryParam(
          req.queryParameters,
          'sort',
        );
        final List<Map<String, dynamic>> rows = _masterReviewsFor(
          lastGetMasterReviewsSort,
        );
        return _searchEnvelope(
          rows,
          page: 0,
          totalPages: 1,
          totalElements: rows.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // WRONG-ID GUARD (only when masterRowId differs from the User id): model
    // what the real backend returns if the screen mistakenly queries by User
    // id — summary → 404 (findById(userId).orElseThrow), list → empty (no
    // reviews match a non-master id). Registering these makes a buggy screen
    // fail CLEANLY (empty list + summary error) rather than throwing an
    // unmatched-route error, and lets the flow assert the fingerprint counters.
    if (masterRowId != 'user-master-1') {
      _adapter.onRoute(
        '/api/v1/masters/user-master-1/reviews/summary',
        (server) => server.replyCallback(404, (_) {
          getMasterReviewSummaryWrongIdCalls++;
          return _masterNotFoundEnvelope();
        }),
        request: const Request(method: RequestMethods.get),
      );
      _adapter.onRoute(
        '/api/v1/masters/user-master-1/reviews',
        (server) => server.replyCallback(200, (_) {
          getMasterReviewsWrongIdCalls++;
          return _searchEnvelope(
            const <Map<String, dynamic>>[],
            page: 0,
            totalPages: 0,
            totalElements: 0,
          );
        }),
        request: const Request(method: RequestMethods.get),
      );
    }

    // GET /api/v1/masters/master-aaa — PUBLIC master detail (Phase 13.5). The
    // client-facing public profile resolves the target master by its Master-row
    // UUID through the generated MasterControllerApi.getMasterDetail. Wired as a
    // concrete path (DioAdapter has no path-template matching) for the
    // search-results fixture id `master-aaa`.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterCalls++;
        lastGetPublicMasterId = 'master-aaa';
        return _publicMasterDetailEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-aaa/services — PUBLIC active services for the
    // same master. Feeds the public profile's services-count stat tile.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/services',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterServicesCalls++;
        lastGetPublicMasterServicesId = 'master-aaa';
        return _okList(_publicMasterServices);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-aaa/reviews/summary — PUBLIC master reviews
    // header (Phase 4.x), reached from the public profile's «Відгуки» stat
    // tile. Registered BEFORE the list route below (more specific path
    // first) so a `.../reviews` match can never shadow `.../reviews/summary`
    // — same ordering discipline as the `masterRowId`-keyed self routes above.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/reviews/summary',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterReviewSummaryCalls++;
        return _publicMasterReviewSummaryEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-aaa/reviews?sort=&page=&size= — PUBLIC master
    // reviews list.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/reviews',
      (server) => server.replyCallback(200, (req) {
        getPublicMasterReviewsCalls++;
        lastGetPublicMasterReviewsSort = _scalarQueryParam(
          req.queryParameters,
          'sort',
        );
        final List<Map<String, dynamic>> rows = _publicMasterReviewsFor(
          lastGetPublicMasterReviewsSort,
        );
        return _searchEnvelope(
          rows,
          page: 0,
          totalPages: 1,
          totalElements: rows.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/services/{serviceDefId}/masters — Phase
    // 23.x bookable-masters rewire. SUPERSEDES the Phase 14.13 per-master
    // `GET /masters/{id}/services` fan-out that used to be registered here
    // for all 7 non-`master-aaa` roster masters: `salonMasterServiceCoverage
    // Provider` now calls THIS endpoint ONCE PER SELECTED SERVICE, and the
    // backend does the active/assigned/schedule-usable filtering
    // server-side — a master is either IN the response (bookable) or simply
    // absent (never rendered), with no client-side derivation at all.
    //
    // Coverage split, mirroring the catalogue's own "shared vs exclusive"
    // naming:
    //   salon-svc-shared    -> ONLY master-ccc is bookable
    //   salon-svc-exclusive -> ONLY master-ddd is bookable
    // Every other roster master (master-aaa, master-eee..master-iii) is
    // simply never returned by EITHER route below — exactly how the real
    // backend represents "not bookable for this service", including the bug
    // this rewire fixes: a master with an active assignment but no usable
    // schedule (like `master-eee` here, standing in for "Роман" in this
    // session's regression report) is server-filtered OUT of the response
    // rather than sent with a disabled-everything calendar. Selecting BOTH
    // salon services therefore yields exactly 2 eligible masters (of 8 on
    // the roster), each the sole candidate for its service — a deterministic
    // auto-attach scenario the E2E can assert without re-proving the
    // contested-choice UI branch logic already exhaustively covered at the
    // widget tier (salon_master_selection_screen_test.dart).
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/services/salon-svc-shared/masters',
      (server) => server.replyCallback(200, (_) {
        getBookableMastersCalls++;
        requestedBookableMastersServiceDefIds.add('salon-svc-shared');
        return _okList(<Map<String, dynamic>>[
          _bookableMasterEnvelope(
            masterId: 'master-ccc',
            serviceDefId: 'salon-svc-shared',
            firstName: 'Марія',
            lastName: 'Гриценко',
          ),
        ]);
      }),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/services/salon-svc-exclusive/masters',
      (server) => server.replyCallback(200, (_) {
        getBookableMastersCalls++;
        requestedBookableMastersServiceDefIds.add('salon-svc-exclusive');
        return _okList(<Map<String, dynamic>>[
          _bookableMasterEnvelope(
            masterId: 'master-ddd',
            serviceDefId: 'salon-svc-exclusive',
            firstName: 'Оксана',
            lastName: 'Іванова',
          ),
        ]);
      }),
      request: const Request(method: RequestMethods.get),
    );
    // `salon-svc-namefallback` is a REAL catalogue entry (see
    // `_salonServiceCategories` above) that no roster master performs —
    // an EMPTY 200, not an unregistered route, so the salon-service deep-link
    // seed's "empty-roster" path (Phase G,
    // `wishlist_salon_service_redirect_flow_test.dart`) can be exercised
    // without conflating it with a genuine network-error state.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/services/salon-svc-namefallback/masters',
      (server) => server.replyCallback(200, (_) {
        getBookableMastersCalls++;
        requestedBookableMastersServiceDefIds.add('salon-svc-namefallback');
        return _okList(const <Map<String, dynamic>>[]);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-aaa/slots?date=&serviceId= — Phase 14.1 slot
    // picker (SlotRepository.getMasterSlots). Query params are not part of
    // the DioAdapter route match (path only — see the salon-xyz/masters
    // comment below), so one registration answers every date/service the
    // booking-flow E2E requests.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/slots',
      (server) => server.replyCallback(200, (_) {
        getMasterSlotsCalls++;
        return _availableSlotsEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-aaa/working-days?from=&to= — Phase 14.14
    // calendar day-availability gate (SlotRepository.getWorkingDays). Same
    // path-only route-match caveat as the `/slots` registration above.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/working-days',
      (server) => server.replyCallback(200, (req) {
        getWorkingDaysCalls++;
        // Phase 14.20: the fixed booking calendar threads the chosen service's
        // id into this query (availability-aware mode). Record it, and answer
        // in the same mode the request asked for.
        final List<String>? serviceIds = _multiQueryParam(
          req.queryParameters,
          'serviceId',
        );
        final String? serviceId = (serviceIds == null || serviceIds.isEmpty)
            ? null
            : serviceIds.first;
        lastMasterAaaWorkingDaysServiceIds = serviceIds;
        lastMasterAaaWorkingDaysServiceId = serviceId;
        return _workingDaysEnvelope(serviceId: serviceId);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // Phase 14.16/14.17 salon booking time-picker (SalonTimeScreen /
    // salon_booking_schedule_notifier.dart's workingDaysProvider /
    // salonMasterDaySlotsProvider). The salon-booking E2E's TWO eligible
    // roster masters (`master-ccc` — covers `salon-svc-shared`, `master-ddd`
    // — covers `salon-svc-exclusive`, per the coverage split above) each need
    // their OWN `/working-days` + `/slots` routes: the time screen renders
    // one `PageView` slide per assigned master and fetches EACH slide's
    // calendar/slots independently. Registering these for only ONE of the two
    // (mirroring the exact Phase 14.13 bug this session's phase docs warn
    // against — where only `master-aaa` had `/services` wired and every other
    // roster master 404'd) would 404 the second slide's provider the moment
    // the flow reaches it. Reuses the same shared counters/envelopes
    // `master-aaa` uses above — this file has only one `FakeBackend` instance
    // per test, so the counts stay scoped to whichever test exercises them.
    _adapter.onRoute(
      '/api/v1/masters/master-ccc/working-days',
      (server) => server.replyCallback(200, (_) {
        getWorkingDaysCalls++;
        return _workingDaysEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/masters/master-ccc/slots',
      (server) => server.replyCallback(200, (req) {
        getMasterSlotsCalls++;
        lastMasterCccSlotsServiceId = _serviceIdFrom(req.queryParameters);
        return _availableSlotsEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/masters/master-ddd/working-days',
      (server) => server.replyCallback(200, (_) {
        getWorkingDaysCalls++;
        return _workingDaysEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/masters/master-ddd/slots',
      (server) => server.replyCallback(200, (req) {
        getMasterSlotsCalls++;
        lastMasterDddSlotsServiceId = _serviceIdFrom(req.queryParameters);
        return _availableSlotsEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // ── Public salon profile (Phase 13.6) ─────────────────────────────────────
    //
    // GET /api/v1/salons/salon-xyz — hero card (SalonControllerApi.getSalon,
    // consumed via HttpSalonRepository.getSalonById). Wired as a concrete path
    // (DioAdapter has no path-template matching) for the search-results
    // fixture id `salon-xyz`.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz',
      (server) => server.replyCallback(200, (_) {
        getSalonByIdCalls++;
        lastGetSalonId = 'salon-xyz';
        return _publicSalonDetailEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/masters?page=&size= — "Майстри" tab rail.
    // Query params are not part of the DioAdapter route match (path only), so
    // one registration covers the fixed page=0&size=50 request the repository
    // sends.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/masters',
      (server) => server.replyCallback(200, (_) {
        getSalonMastersCalls++;
        lastGetSalonMastersId = 'salon-xyz';
        return _searchEnvelope(
          _salonMasters,
          page: 0,
          totalPages: 1,
          totalElements: _salonMasters.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/services — "Послуги" tab catalogue
    // (ServiceControllerApi.getSalonServiceCatalog).
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/services',
      (server) => server.replyCallback(200, (_) {
        getSalonServiceCatalogCalls++;
        lastGetSalonServiceCatalogId = 'salon-xyz';
        return _ok(<String, dynamic>{'categories': _salonServiceCategories});
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/reviews/summary — "Відгуки" tab header
    // (ReviewControllerApi.getSalonReviewSummary). Registered BEFORE the
    // sibling `/reviews` route below — both are exact-string DioAdapter routes
    // (no prefix matching), so registration order does not actually matter
    // here, but the more-specific path is kept first for readability.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/reviews/summary',
      (server) => server.replyCallback(200, (_) {
        getSalonReviewSummaryCalls++;
        lastGetSalonReviewSummaryId = 'salon-xyz';
        return _salonReviewSummaryEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/reviews?sort=&page=&size= — "Відгуки" tab
    // list. Ignores the sort value for content (always returns the same 3-item
    // fixture — the fake is not re-implementing the backend's sort), but
    // records the requested `sort` wire value so a sort-change test can assert
    // the new value reached the wire.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/reviews',
      (server) => server.replyCallback(200, (req) {
        getSalonReviewsCalls++;
        lastGetSalonReviewsSort = _scalarQueryParam(
          req.queryParameters,
          'sort',
        );
        final List<Map<String, dynamic>> rows = _salonReviewsFor();
        return _searchEnvelope(
          rows,
          page: 0,
          totalPages: 1,
          totalElements: rows.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-xyz/portfolio — "Про салон" tab real photo
    // rail (MediaControllerApi.getSalonPortfolio, previously unwired).
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/portfolio',
      (server) => server.replyCallback(200, (_) {
        getSalonPortfolioCalls++;
        lastGetSalonPortfolioId = 'salon-xyz';
        return _salonPortfolioEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/independent-masters/me/profile
    _adapter.onRoute(
      '/api/v1/independent-masters/me/profile',
      (server) => server.replyCallback(200, (req) {
        patchProfileCalls++;
        final body = _decodeBody(req.data);
        lastPatchBody = body;
        if (body['firstName'] is String) {
          masterFirstName = body['firstName'] as String;
        }
        if (body['lastName'] is String) {
          masterLastName = body['lastName'] as String;
        }
        if (body['bio'] is String) masterBio = body['bio'] as String;
        masterInstagram = body['instagram'] as String?;
        masterPhone = body['phoneNumber'] as String?;
        // professionalTitle: '' means "clear it" (null on next GET); a non-empty
        // value updates the stored title.
        if (body.containsKey('professionalTitle')) {
          final raw = body['professionalTitle'];
          masterProfessionalTitle = (raw is String && raw.isNotEmpty)
              ? raw
              : null;
        }
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // GET /api/v1/independent-masters/me/services
    _adapter.onRoute(
      '/api/v1/independent-masters/me/services',
      (server) => server.replyCallback(200, (_) {
        getServicesCalls++;
        return _okList(_services);
      }),
      request: const Request(method: RequestMethods.get),
    );

    _wireCreateService();

    _wireBulkCreateServices();

    // GET /api/v1/independent-masters/me/services/:id
    // Wired for the two pre-seeded services (keyed by serviceDefId in the path).
    for (final svc in _services) {
      final defId =
          (svc['serviceDefinition'] as Map<String, dynamic>?)?['id']
              as String? ??
          '';
      if (defId.isNotEmpty) {
        _adapter.onRoute(
          '/api/v1/independent-masters/me/services/$defId',
          (server) => server.replyCallback(200, (_) => _ok(svc)),
          request: const Request(method: RequestMethods.get),
        );
      }
    }

    // PATCH /api/v1/independent-masters/me/services/:id (serviceDefId)
    // Generic handler for every seeded service — keyed by serviceDefinition.id
    // so both svc-1 (FIXED) and svc-2 (RANGE) accept PATCH without a separate
    // hardcoded route per service. (MEDIUM-2 fix — QA-recommended generic form.)
    for (final svc in _services) {
      final defId =
          (svc['serviceDefinition'] as Map<String, dynamic>?)?['id']
              as String? ??
          '';
      if (defId.isEmpty) continue;
      // NB: the Phase 16.5 regression services (svc-typed / svc-mismatch) are
      // PATCHed at the REAL `/api/v1/services/{serviceDefId}` path, wired
      // separately below — this generic loop uses the (different) legacy path and
      // is left untouched for the pre-existing svc-1 / svc-2 fixtures.
      _adapter.onRoute(
        '/api/v1/independent-masters/me/services/$defId',
        (server) => server.replyCallback(200, (req) {
          patchServiceCalls++;
          final body = _decodeBody(req.data);
          lastPatchedService = body;
          if (defId == 'svc-typed') lastTypedPatchBody = body;
          // Mutate the service-definition name/price in-memory.
          final idx = _services.indexWhere(
            (s) =>
                (s['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
                defId,
          );
          if (idx >= 0) {
            final def =
                _services[idx]['serviceDefinition'] as Map<String, dynamic>;
            if (body['name'] != null) def['name'] = body['name'];
            if (body['priceMin'] != null) def['priceMin'] = body['priceMin'];
            if (body['priceMax'] != null) def['priceMax'] = body['priceMax'];
          }
          return _ok(_services[idx >= 0 ? idx : 0]);
        }),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
    }

    // PATCH /api/v1/services/{serviceDefId} — the REAL update endpoint
    // (updateServiceDefinition keys on the service-definition id at this path,
    // NOT the /independent-masters/me/services/:id path the generic loop above
    // uses). Wired here for the Phase 16.5 edit-flow regression services so a
    // real save actually fires:
    //   • svc-typed    → 200 (positive flow: re-picked type persists)
    //   • svc-mismatch → fieldless 400 mismatch envelope (negative flow)
    _adapter.onRoute(
      '/api/v1/services/svc-typed',
      (server) => server.replyCallback(200, (req) {
        patchServiceCalls++;
        final body = _decodeBody(req.data);
        lastPatchedService = body;
        lastTypedPatchBody = body;
        final idx = _services.indexWhere(
          (s) =>
              (s['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
              'svc-typed',
        );
        return _ok(_services[idx >= 0 ? idx : 0]);
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );
    _adapter.onRoute(
      '/api/v1/services/svc-mismatch',
      (server) => server.replyCallback(400, (req) {
        patchServiceCalls++;
        return <String, dynamic>{
          'success': false,
          'message': 'service type does not belong to the selected category',
          // NB: intentionally NO `errors` field — the bug class this guards.
        };
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // GET /api/v1/masters/{masterId}/weekly-schedules
    // The ScheduleRepository uses the real masterId (from MasterDetailResponse),
    // NOT the /me alias. Both the real-ID path (live backend contract) and the
    // /me alias are wired so the fake covers both.
    for (final path in <String>[
      '/api/v1/masters/me/weekly-schedules',
      '/api/v1/masters/user-master-1/weekly-schedules',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(200, (_) {
          getScheduleCalls++;
          return _okList(_weeklySchedule);
        }),
        request: const Request(method: RequestMethods.get),
      );
    }

    // POST /api/v1/masters/{masterId}/weekly-schedules (create template)
    // Returns a valid WeeklyScheduleResponse so the mapper can deserialize it.
    for (final path in <String>[
      '/api/v1/masters/me/weekly-schedules',
      '/api/v1/masters/user-master-1/weekly-schedules',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(200, (req) {
          postScheduleCalls++;
          final body = _decodeBody(req.data);
          lastWeeklyDays = body['days'] as List<dynamic>?;
          lastWeeklyValidFrom = body['validFrom'] as String?;
          lastWeeklyValidTo = body['validTo'] as String?;
          // Build a WeeklyScheduleResponse-shaped envelope from the request.
          // Use a deterministic counter ID — never wall-clock (MEDIUM-1 fix).
          final newEntry = <String, dynamic>{
            'id': 'schedule-${_scheduleSeq++}',
            'validFrom': body['validFrom'] ?? '2026-06-14',
            'validTo': body['validTo'],
            'days': body['days'] ?? <dynamic>[],
          };
          // Upsert into in-memory state (keyed by the new entry's own id).
          final idx = _weeklySchedule.indexWhere(
            (s) => s['id'] == newEntry['id'],
          );
          if (idx >= 0) {
            _weeklySchedule[idx] = newEntry;
          } else {
            _weeklySchedule = <Map<String, dynamic>>[
              ..._weeklySchedule,
              newEntry,
            ];
          }
          return _ok(newEntry);
        }),
        request: const Request(method: RequestMethods.post, data: Matchers.any),
      );
    }

    // PUT /api/v1/masters/{masterId}/weekly-schedules/{scheduleId} (update template)
    // Called by upsertWeeklySchedule when scheduleId is non-null (UPDATE path).
    // The seeded schedule has id='schedule-1', so the editor calls PUT, not POST.
    for (final path in <String>[
      '/api/v1/masters/me/weekly-schedules/schedule-1',
      '/api/v1/masters/user-master-1/weekly-schedules/schedule-1',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(200, (req) {
          putScheduleCalls++;
          final body = _decodeBody(req.data);
          lastWeeklyDays = body['days'] as List<dynamic>?;
          // mobile-qa (calendar-consolidation, Rule 3b integration coverage):
          // the POST handler above has captured these two fields since they
          // were added, but the PUT (UPDATE) handler never did — despite the
          // field doc above claiming "POST/PUT" — so no test exercising the
          // UPDATE path (the seeded schedule-1 default, i.e. every existing-
          // template flow) could ever assert the validFrom/validTo a PUT
          // actually carried. Mirrors the POST handler exactly.
          lastWeeklyValidFrom = body['validFrom'] as String?;
          lastWeeklyValidTo = body['validTo'] as String?;
          final updatedEntry = <String, dynamic>{
            'id': 'schedule-1',
            'validFrom': body['validFrom'] ?? '2026-06-14',
            'validTo': body['validTo'],
            'days': body['days'] ?? <dynamic>[],
          };
          final idx = _weeklySchedule.indexWhere(
            (s) => s['id'] == 'schedule-1',
          );
          if (idx >= 0) {
            _weeklySchedule[idx] = updatedEntry;
          }
          return _ok(updatedEntry);
        }),
        request: const Request(method: RequestMethods.put, data: Matchers.any),
      );
    }

    // PUT /api/v1/masters/{masterId}/overrides/{date} (Phase 15.8 — upsert a
    // per-date override). The date segment is a `YYYY-MM-DD` path param, so a
    // RegExp route matches every date for both the /me alias and the real id.
    // The reply echoes a ScheduleOverrideResponse-shaped envelope built from the
    // request body so the mapper can deserialize it (kind/mode/intervals/times).
    for (final masterId in <String>['me', 'user-master-1']) {
      _adapter.onRoute(
        RegExp(
          '/api/v1/masters/$masterId/overrides/'
          r'\d{4}-\d{2}-\d{2}$',
        ),
        (server) => server.replyCallback(200, (req) {
          putOverrideCalls++;
          final body = _decodeBody(req.data);
          lastOverrideBody = body;
          // 2026-07-26 booking-conflict design: a confirmed write carries
          // `cancelOverlapping: true` — the real backend then atomically
          // declines every conflicting CONFIRMED booking with the write. The
          // fake mirrors that ONLY as a status flip on the seeded booking
          // fixture (no per-booking id matching — this fake is not the
          // preview endpoint's source of truth, `conflictPreviewRows` is).
          if (body['cancelOverlapping'] == true &&
              conflictPreviewRows.isNotEmpty) {
            overrideCancelOverlappingWrites++;
            bookingStatus = 'DECLINED';
          }
          // Echo the request back as a response-shaped override so the read
          // mapper round-trips it (date/kind/mode/intervals/times).
          return _ok(<String, dynamic>{
            'date': body['date'],
            'kind': body['kind'] ?? 'CUSTOM_HOURS',
            'mode': body['mode'],
            'intervals': body['intervals'] ?? <dynamic>[],
            'times': body['times'] ?? <dynamic>[],
          });
        }),
        request: const Request(method: RequestMethods.put, data: Matchers.any),
      );
    }

    // POST /api/v1/masters/{masterId}/overrides/conflicts (2026-07-26
    // booking-conflict design) — read-only preview of every CONFIRMED booking
    // the pending override would leave without availability. Reports whatever
    // a flow seeded in [conflictPreviewRows] (empty by default, so every flow
    // that never sets it keeps the pre-existing "no gate to see" behaviour —
    // `_noConflicts`-equivalent at the wire boundary).
    for (final masterId in <String>['me', 'user-master-1']) {
      _adapter.onRoute(
        '/api/v1/masters/$masterId/overrides/conflicts',
        (server) => server.replyCallback(200, (req) {
          previewConflictsCalls++;
          lastConflictQueryBody = _decodeBody(req.data);
          return _ok(<String, dynamic>{
            'conflicts': conflictPreviewRows,
            'totalCount': conflictPreviewRows.length,
            'truncated': false,
            'scanTruncated': false,
          });
        }),
        request: const Request(method: RequestMethods.post, data: Matchers.any),
      );
    }

    // GET /api/v1/locations/oblasts — one seeded oblast so the locality cascade
    // picker has a selectable row (the CLIENT Location flow drives the REAL
    // picker sheets to make the form dirty now that the free-text address fields
    // — the previous "type a street to dirty" mechanism — are gone). Shape:
    // OblastResponse { id, katotthCode, nameUk, nameEn }.
    _adapter.onRoute(
      '/api/v1/locations/oblasts',
      (server) => server.reply(
        200,
        _okList(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'oblast-kyiv',
            'katotthCode': 'UA32000000000000000',
            'nameUk': 'Київська',
            'nameEn': 'Kyiv Oblast',
          },
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/locations/oblasts/{oblastId}/cities — TWO seeded cities
    // (both WITHOUT districts) so a CLIENT can select a city through the real
    // cascade and save with ONLY the locality slice (no district step, no
    // address fields). Shape: CityResponse { id, oblastId, katotthCode, nameUk,
    // nameEn, hasDistricts }.
    //
    // city-lviv (added alongside city-kyiv) lets a flow drive a REAL
    // city-to-city locality CHANGE via the Location edit screen — needed by the
    // mid-session search-prefill regression flow (client_search_flow_test.dart)
    // which proves a CLIENT switching their saved city reaches Пошук on the very
    // next open, without a logout/restart.
    _adapter.onRoute(
      '/api/v1/locations/oblasts/oblast-kyiv/cities',
      (server) => server.reply(
        200,
        _okList(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'city-kyiv',
            'oblastId': 'oblast-kyiv',
            'katotthCode': 'UA80000000000093317',
            'nameUk': 'Київ',
            'nameEn': 'Kyiv',
            'hasDistricts': false,
          },
          <String, dynamic>{
            'id': 'city-lviv',
            'oblastId': 'oblast-kyiv',
            'katotthCode': 'UA46000000000026870',
            'nameUk': 'Львів',
            'nameEn': 'Lviv',
            'hasDistricts': false,
          },
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/{masterId}/effective-schedule — empty list by
    // default; [seedEffectiveSchedule] overrides it (Phase 244).
    // Both /me alias and real masterId path are wired.
    // Query parameters (from/to) are not part of the route path — DioAdapter
    // matches on the path only, so one registration covers all from/to combos.
    for (final path in <String>[
      '/api/v1/masters/me/effective-schedule',
      '/api/v1/masters/user-master-1/effective-schedule',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(
          200,
          (_) => _okList(_effectiveScheduleOverride ?? const <dynamic>[]),
        ),
        request: const Request(method: RequestMethods.get),
      );
    }

    // GET /api/v1/masters/{masterId}/overrides — empty list (no overrides seeded).
    // Needed by OverridesNotifier which effectiveScheduleProvider depends on.
    for (final path in <String>[
      '/api/v1/masters/me/overrides',
      '/api/v1/masters/user-master-1/overrides',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.reply(200, _okList(const <dynamic>[])),
        request: const Request(method: RequestMethods.get),
      );
    }

    // GET /api/v1/service-categories/approved — seeded categories so the
    // service form can select / switch between them (category is required by the
    // form). NAILS + BROWS are both seeded so the edit-flow category-switch test
    // (Phase 16.5 regression) can change category A → B. Shape: list of
    // ApprovedCategoryResponse { name, displayName }.
    _adapter.onRoute(
      '/api/v1/service-categories/approved',
      (server) => server.reply(
        200,
        _okList(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'NAILS', 'displayName': 'Нігті'},
          <String, dynamic>{'name': 'BROWS', 'displayName': 'Брови'},
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/service-types?categoryName=X — second-level picker source
    // (Phase 16.5 regression). Keyed on the `categoryName` query param so a
    // category switch genuinely re-queries and the option list repopulates for
    // the new category. Shape: list of PlatformServiceTypeResponse
    // { id, slug, nameUk, categoryName }. Unknown categories → empty list.
    _adapter.onRoute(
      '/api/v1/service-types',
      (server) => server.replyCallback(200, (req) {
        getServiceTypesCalls++;
        final String category =
            _scalarQueryParam(req.queryParameters, 'categoryName') ?? '';
        lastServiceTypesCategory = category;
        return _okList(_serviceTypesFor(category));
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/platform-categories — empty list
    _adapter.onRoute(
      '/api/v1/platform-categories',
      (server) => server.reply(200, _okList(const <dynamic>[])),
      request: const Request(method: RequestMethods.get),
    );

    // ── Discovery search (Phase 13.4) ─────────────────────────────────────────
    //
    // GET /api/v1/search/masters?page=&size=&sort=&location.cityId=&… — paged.
    // The repository sends FLAT @ModelAttribute-bindable query params (the city
    // arrives as `location.cityId`, NOT a bracket-nested `request[location]…`).
    // Page 0 returns one master + signals a second page
    // (totalPages=2); page 1 returns the second master (last page). This drives
    // both the first-page render AND the loadMore append in the E2E.
    _adapter.onRoute(
      '/api/v1/search/masters',
      (server) => server.replyCallback(200, (req) {
        searchMastersCalls++;
        final int page = _pageFromRequest(req.queryParameters);
        lastSearchMastersPage = page;
        final Map<String, dynamic> reqJson = _decodeRequest(
          req.queryParameters,
        );
        lastSearchMastersQuery = reqJson['q'] as String?;
        lastSearchMastersSort = reqJson['sort'] as String?;
        lastSearchMastersCityId = reqJson['location.cityId'] as String?;
        lastSearchMastersDistrictId = reqJson['location.districtId'] as String?;
        lastSearchMastersServiceTypeSlugs = _slugsFrom(reqJson);
        // Snapshot the WHOLE flat map so a test can prove several facets
        // (q + location.cityId + category + minPrice/maxPrice) arrived on
        // this SAME request — see [lastSearchMastersQueryMap].
        lastSearchMastersQueryMap = Map<String, dynamic>.from(reqJson);
        if (page <= 0) {
          return _searchEnvelope(
            _withMatchedNames(
              _searchMastersPage0,
              lastSearchMastersServiceTypeSlugs,
            ),
            page: 0,
            totalPages: 2,
            totalElements: 2,
          );
        }
        return _searchEnvelope(
          _withMatchedNames(
            _searchMastersPage1,
            lastSearchMastersServiceTypeSlugs,
          ),
          page: page,
          totalPages: 2,
          totalElements: 2,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/search/salons?page=&size=&sort=&location.cityId=&… — 1 page.
    _adapter.onRoute(
      '/api/v1/search/salons',
      (server) => server.replyCallback(200, (req) {
        searchSalonsCalls++;
        final int page = _pageFromRequest(req.queryParameters);
        lastSearchSalonsPage = page;
        final Map<String, dynamic> reqJson = _decodeRequest(
          req.queryParameters,
        );
        lastSearchSalonsQuery = reqJson['q'] as String?;
        lastSearchSalonsSort = reqJson['sort'] as String?;
        lastSearchSalonsCityId = reqJson['location.cityId'] as String?;
        lastSearchSalonsDistrictId = reqJson['location.districtId'] as String?;
        lastSearchSalonsServiceTypeSlugs = _slugsFrom(reqJson);
        // Snapshot the WHOLE flat map — see [lastSearchSalonsQueryMap].
        lastSearchSalonsQueryMap = Map<String, dynamic>.from(reqJson);
        // Salons have a single page: page 0 carries the row, any later page is
        // empty (the notifier only re-requests salons while salonHasMore).
        if (page <= 0) {
          return _searchEnvelope(
            _withMatchedNames(
              _searchSalonsPage0,
              lastSearchSalonsServiceTypeSlugs,
            ),
            page: 0,
            totalPages: 1,
            totalElements: 1,
          );
        }
        return _searchEnvelope(
          const <Map<String, dynamic>>[],
          page: page,
          totalPages: 1,
          totalElements: 1,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // ── Favorites (Phase 13.4) ────────────────────────────────────────────────
    //
    // GET /api/v1/favorites/services — the CLIENT's BEAUTY WISH LIST feed
    // (backend 247). Registered BEFORE `/api/v1/favorites` deliberately:
    // DioAdapter matches on the PATH, so the longer path must get first
    // refusal or the bare `/favorites` handlers would swallow it.
    //
    // Without this route the mock router 404s and the passport page's wish-list
    // section renders its ERROR card — which draws a `cloud_off` glyph and
    // silently changes what every other assertion on that page measures.
    _adapter.onRoute(
      '/api/v1/favorites/services',
      (server) => server.replyCallback(200, (_) {
        listServiceFavoritesCalls++;
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <String, dynamic>{
            'data': favoriteServiceRows,
            'page': 0,
            'size': 20,
            'totalElements': favoriteServiceRows.length,
            'totalPages': favoriteServiceRows.isEmpty ? 0 : 1,
          },
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // POST /api/v1/favorites — add (idempotent 200). Returns a FavoriteResponse
    // envelope so the generated addFavorite() deserializes cleanly.
    //
    // Phase 240 (mobile-qa, service_favourite_flow_test.dart): a SERVICE add
    // also appends the corresponding row to [favoriteServiceRows], so a
    // following `GET /favorites/services` genuinely reflects it — mirroring
    // the real backend's persistence. The app itself never bridges
    // `favoriteToggleProvider` (the heart) to `wishlistProvider` (the list) —
    // see `service_selector_sheet.dart`'s prime-from-wishlist comment — so
    // this is the ONLY source of truth the fake can offer for "does the just-
    // favourited service show up on the wish list". Looked up from
    // [_masterAaaFavoriteServiceFields] (master-aaa is the only master this
    // fake fully catalogues); an unknown id is a no-op, same as before this
    // change.
    //
    // Phase F (mobile-qa, salon_service_favourite_flow_test.dart): a
    // SALON_SERVICE add mirrors the same persistence, keyed by `serviceDefId`
    // against [_salonServiceFavoriteFields] and stamped `sourceType: 'SALON'`
    // — the exact wire shape `WishlistMapper._fromSalonDto` requires
    // (`salonId`/`serviceDefId` present, no master fields at all). Before this
    // handler existed, tapping a heart on the salon service-selection screen
    // POSTed successfully but the Beauty Passport read-back could never show
    // it — the redirect flow test worked around that gap by seeding
    // `favoriteServiceRows` directly; this closes the gap so the favouriting
    // half of the journey is exercised for real too.
    _adapter.onRoute(
      '/api/v1/favorites',
      (server) => server.replyCallback(200, (req) {
        addFavoriteCalls++;
        final body = _decodeBody(req.data);
        lastAddFavoriteBody = body;
        if (body['targetType'] == 'SERVICE') {
          final String targetId = (body['targetId'] as String?) ?? '';
          final Map<String, dynamic>? fields =
              _masterAaaFavoriteServiceFields[targetId];
          if (fields != null &&
              !favoriteServiceRows.any(
                (Map<String, dynamic> r) => r['masterServiceId'] == targetId,
              )) {
            favoriteServiceRows = <Map<String, dynamic>>[
              ...favoriteServiceRows,
              <String, dynamic>{'masterServiceId': targetId, ...fields},
            ];
          }
        } else if (body['targetType'] == 'SALON_SERVICE') {
          final String targetId = (body['targetId'] as String?) ?? '';
          final Map<String, dynamic>? fields =
              _salonServiceFavoriteFields[targetId];
          if (fields != null &&
              !favoriteServiceRows.any(
                (Map<String, dynamic> r) => r['serviceDefId'] == targetId,
              )) {
            favoriteServiceRows = <Map<String, dynamic>>[
              ...favoriteServiceRows,
              <String, dynamic>{
                'sourceType': 'SALON',
                'salonId': 'salon-xyz',
                'serviceDefId': targetId,
                ...fields,
              },
            ];
          }
        }
        return _ok(<String, dynamic>{
          'id': 'fav-1',
          'targetType': body['targetType'] ?? 'MASTER',
          'targetId': body['targetId'] ?? '',
          'createdAt': '2026-06-14T12:00:00Z',
        });
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // DELETE /api/v1/favorites?targetType&targetId — remove (idempotent 204
    // by default; see [forceRemoveFavoriteFailure] for the failure variant).
    _wireRemoveFavorite();

    // GET /api/v1/bookings/me/booked-days?from=&to= — the dot set behind the
    // master's «Мої записи» day rail (backend Phase 26.5). Registered BEFORE
    // `/api/v1/bookings/me` deliberately: DioAdapter matches on the path, and
    // the longer path must get first refusal.
    //
    // Returns the seeded booking's own day, so the rail auto-centres on real
    // content rather than on `today − 180`. `bookedDaysCalls` lets a flow prove
    // the rail is fed by this FILTER-INDEPENDENT endpoint and not by the
    // (filtered) list — the invariant `master_bookings_screen_test.dart` pins
    // at the widget tier.
    _adapter.onRoute(
      '/api/v1/bookings/me/booked-days',
      (server) => server.replyCallback(200, (req) {
        bookedDaysCalls++;
        lastBookedDaysQuery = Map<String, dynamic>.from(req.queryParameters);
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <String>[bookingStartsAt.substring(0, 10)],
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/bookings/me?status=&sort=&page=&size= — the client's «МОЇ
    // ЗАПИСИ» list. DioAdapter matches path-only, so the single handler
    // dispatches on whether a full [_bookingsDataset] has been seeded: when
    // it has (mobile-qa pagination/sort regression flow), every call is
    // served by the REAL (statuses, sort, page) slice in
    // [_slicedBookingsPageEnvelope]; otherwise (every other flow using this
    // fake) it falls back to the original single-seeded-`booking-1` behaviour
    // keyed off the current status. [lastMyBookingsQuery] is recorded here,
    // UNCONDITIONALLY, before the dataset dispatch — see that field's doc
    // comment for why it must never move back behind the dataset check.
    _adapter.onRoute(
      '/api/v1/bookings/me',
      (server) => server.replyCallback(200, (req) {
        getMyBookingsCalls++;
        lastMyBookingsQuery = Map<String, dynamic>.from(req.queryParameters);
        if (_bookingsDataset != null) {
          return _slicedBookingsPageEnvelope(
            Map<String, dynamic>.from(req.queryParameters),
          );
        }
        // Parsed with the SAME list-aware reader the dataset branch uses — a
        // bare `as String?` cast throws here (see [_bookingsPageEnvelope]).
        return _bookingsPageEnvelope(
          _bookingStatusesFrom(Map<String, dynamic>.from(req.queryParameters)),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/bookings/booking-1 — «Деталі запису» for the seeded booking.
    // Concrete path (DioAdapter has no path-template matching); reflects the
    // CURRENT mutable status/time so a post-cancel / post-reschedule re-open
    // shows the new state.
    _adapter.onRoute(
      '/api/v1/bookings/booking-1',
      (server) => server.replyCallback(200, (_) {
        getBookingDetailCalls++;
        return _ok(_seededBookingJson());
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/bookings/booking-2 — «Деталі запису» for the SIBLING child of
    // the same multi-service visit (per-service decline regression). Reflects
    // its OWN mutable [siblingBookingStatus] so a re-open after declining
    // `booking-1` proves this sibling stayed CONFIRMED.
    _adapter.onRoute(
      '/api/v1/bookings/booking-2',
      (server) => server.replyCallback(200, (_) {
        getSiblingBookingDetailCalls++;
        return _ok(_seededSiblingBookingJson());
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/bookings/booking-1/reschedule — client reschedule (track
    // 24.x auto-confirm). Moves the seeded booking to the submitted
    // `newStartsAt`, keeps it CONFIRMED (a reschedule never changes status),
    // and returns the enriched `BookingDetailResponse` the repository maps back
    // (unlike cancel, which is void). The 90-minute span is preserved so the
    // moved booking's end tracks its new start.
    _adapter.onRoute(
      '/api/v1/bookings/booking-1/reschedule',
      (server) => server.replyCallback(200, (req) {
        rescheduleBookingCalls++;
        final body = _decodeBody(req.data);
        final String? newStartsAt = body['newStartsAt'] as String?;
        lastRescheduleNewStartsAt = newStartsAt;
        if (newStartsAt != null) {
          final DateTime start = DateTime.parse(newStartsAt).toUtc();
          final DateTime end = start.add(const Duration(minutes: 90));
          bookingStartsAt = start.toIso8601String();
          bookingEndsAt = end.toIso8601String();
        }
        // A reschedule leaves the booking CONFIRMED — never touches status.
        return _ok(_seededBookingJson());
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // PATCH /api/v1/bookings/booking-1/cancel — client cancellation. Flips the
    // seeded booking to CANCELLED and stores the free-text comment as the
    // client cancellation note (cancellationReason enum is CLIENT_CANCELLED,
    // sent by the repository but not asserted here). Returns Response<void>.
    _adapter.onRoute(
      '/api/v1/bookings/booking-1/cancel',
      (server) => server.replyCallback(200, (req) {
        cancelBookingCalls++;
        final body = _decodeBody(req.data);
        final String? comment = body['comment'] as String?;
        lastCancelComment = comment;
        bookingClientCancellationNote = comment;
        bookingStatus = 'CANCELLED';
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // PATCH /api/v1/bookings/booking-1/decline — Track 27.x Wave A, the
    // PROVIDER decline write path (`booking_repository.dart`'s
    // `declineBooking`). Flips the seeded booking to DECLINED and captures the
    // exact `StatusUpdateRequest` wire body — `cancellationReason` (always
    // `PROVIDER_UNAVAILABLE` for this affordance) and the optional `comment` —
    // so a flow can assert the REAL serialised shape reached the fake, not
    // just that a mocked repository method was invoked with the right Dart
    // arguments (that gap is exactly what the widget-tier
    // `booking_detail_provider_footer_test.dart` cannot close).
    //
    // 2026-08-16 (mobile-qa) — ALSO mutates the `booking-1` row of
    // [_bookingsDataset], when one is seeded, to `status: 'DECLINED'`, mirroring
    // the `/complete` route's identical dataset mutation below. Without this,
    // `master_archive_review_flow_test.dart`'s invalidation regression guard
    // (archive → pushed detail → decline → back to archive) could never
    // observe the row reclassify into the «Скасовано»
    // (`BookingStatusFilterGroup.cancelled`) filter on the archive's fixed
    // `partition: HISTORY` fetch (see [_matchesPartition]) even with a
    // byte-correct `invalidateBookingViewsAfterProviderClose` fix — the
    // dataset itself would still report the pre-decline CONFIRMED row on the
    // very next `GET /bookings/me`, and the test could not tell "the cache
    // never dropped" apart from "the fake never learned about the write".
    _adapter.onRoute(
      '/api/v1/bookings/booking-1/decline',
      (server) => server.replyCallback(200, (req) {
        declineBookingCalls++;
        final body = _decodeBody(req.data);
        lastDeclineComment = body['comment'] as String?;
        lastDeclineCancellationReason = body['cancellationReason'] as String?;
        bookingStatus = 'DECLINED';
        final List<Map<String, dynamic>>? dataset = _bookingsDataset;
        if (dataset != null) {
          final int idx = dataset.indexWhere(
            (Map<String, dynamic> row) => row['id'] == 'booking-1',
          );
          if (idx != -1) {
            dataset[idx] = <String, dynamic>{
              ...dataset[idx],
              'status': 'DECLINED',
            };
          }
        }
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // PATCH /api/v1/bookings/booking-1/complete — Track 27.x Wave A, the
    // PROVIDER complete write path. No request body (`completeBooking`'s
    // generated client call sends none) — flips the seeded booking to
    // COMPLETED.
    //
    // Phase 231 (mobile-qa) — ALSO mutates the `booking-1` row of
    // [_bookingsDataset], when one is seeded, to `status: 'COMPLETED'`.
    // Without this, a dataset-backed flow (`master_archive_flow_test.dart`)
    // that closes `booking-1` and then re-fetches through
    // `masterArchiveProvider`'s invalidation would see the SAME unchanged
    // CONFIRMED row come back — the write would appear to succeed (200,
    // `completeBookingCalls` climbs) while the list silently kept showing
    // stale data, which is a materially weaker proof than "the booking
    // actually left the «Підтверджено» filter after closing". Every other
    // field on the row is preserved via spread; only `status` moves. Mirrors
    // [declineChild]'s existing per-row mutation for the non-dataset seeded
    // booking.
    _adapter.onRoute(
      '/api/v1/bookings/booking-1/complete',
      (server) => server.replyCallback(200, (_) {
        completeBookingCalls++;
        bookingStatus = 'COMPLETED';
        final List<Map<String, dynamic>>? dataset = _bookingsDataset;
        if (dataset != null) {
          final int idx = dataset.indexWhere(
            (Map<String, dynamic> row) => row['id'] == 'booking-1',
          );
          if (idx != -1) {
            dataset[idx] = <String, dynamic>{
              ...dataset[idx],
              'status': 'COMPLETED',
            };
          }
        }
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch),
    );

    // POST /api/v1/reviews — CLIENT leave-review (Phase 14.6). Records the
    // submitted bookingId/rating/comment and flips [bookingCanReview] false so a
    // subsequent detail re-fetch (the notifier invalidates
    // `bookingDetailProvider`) re-resolves the entry CTA away. The generated
    // `ReviewControllerApi.createReview` deserializes an
    // `ApiResponse<ReviewResponse>`; a `data: null` envelope is valid (every
    // ReviewResponse field is nullable) and the repository returns void anyway.
    _adapter.onRoute(
      '/api/v1/reviews',
      (server) => server.replyCallback(200, (req) {
        createReviewCalls++;
        final body = _decodeBody(req.data);
        lastReviewBookingId = body['bookingId'] as String?;
        lastReviewRating = body['rating'] as int?;
        lastReviewComment = body['comment'] as String?;
        bookingCanReview = false;
        // The written review is now part of master-aaa's PUBLIC review data:
        // the profile's rating/count, the summary aggregate and the review list
        // all move. Without this the E2E could not tell a real re-fetch from a
        // keepAlive cache hit — both would render identical numbers.
        publicMasterReviewLanded = true;
        // …and, when the booking was made at a salon, of that SALON's public
        // review data too: the backend recalculates `salons.avg_rating` /
        // `review_count` in the same listener, before the 201 returns. Same
        // rationale as the line above — without this the salon E2E could not
        // tell a real re-fetch from a keepAlive cache hit.
        //
        // Gated on the seeded booking actually having a salon, so an
        // INDEPENDENT_MASTER flow never silently moves salon numbers it has no
        // business moving (and the negative half of the widget suite keeps a
        // truthful server to mirror).
        if (bookingSalonId != null) salonReviewLanded = true;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // POST /api/v1/client-reviews — PROVIDER leave-client-feedback (track 7.x
    // Wave B). Records the submitted bookingId/rating/comment and flips
    // [bookingProviderCanReviewClient] false so a subsequent detail re-fetch
    // (the screen invalidates `bookingDetailProvider` on success — the exact
    // regression this flip exists to pin) re-resolves the provider footer's
    // «Залишити відгук про клієнта» CTA away, mirroring `/api/v1/reviews`
    // above flipping [bookingCanReview]. The generated
    // `ClientReviewControllerApi.create` deserializes an
    // `ApiResponse<ClientReviewResponse>`; a `data: null` envelope is valid
    // (every `ClientReviewResponse` field is nullable) and the repository
    // returns void anyway.
    _adapter.onRoute(
      '/api/v1/client-reviews',
      (server) => server.replyCallback(200, (req) {
        createClientReviewCalls++;
        final body = _decodeBody(req.data);
        lastClientReviewBookingId = body['bookingId'] as String?;
        lastClientReviewRating = body['rating'] as int?;
        lastClientReviewComment = body['comment'] as String?;
        bookingProviderCanReviewClient = false;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  /// Decodes an HTTP request body that may be a raw JSON String or a Map.
  static Map<String, dynamic> _decodeBody(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
