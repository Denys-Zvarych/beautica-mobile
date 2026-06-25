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

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

// ---------------------------------------------------------------------------
// Fixed clock instant used by all E2E tests (Phase 17.1 seed)
// ---------------------------------------------------------------------------

/// Fixed "now" for every integration test — 2026-06-14 12:00:00 UTC.
///
/// Inject this into the harness via:
///   `clockProvider.overrideWithValue(() => kFixedNow)`
final DateTime kFixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0);

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
  FakeBackend() : dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080')) {
    _adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = _adapter;
    _wire();
  }

  final Dio dio;
  late final DioAdapter _adapter;

  // ── Mutable master profile state ──────────────────────────────────────────

  /// The role currently "logged in" for this fake instance.
  /// Call [setCurrentRole] before asserting role-specific behaviour.
  UserRole currentRole = UserRole.independentMaster;

  String masterFirstName = 'Олена';
  String masterLastName = 'Ковальчук';
  String masterBio = 'Майстер манікюру.';
  String? masterPhone = '+380501234567';
  String? masterInstagram = '@olena_nails';

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
  String? clientCityId;
  String? clientCityName;
  String? clientDistrictId;
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
      'priceDisplay': '400 грн',
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
        'priceDisplay': '400 грн',
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
      'priceDisplay': 'від 200 до 350 грн',
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
        'priceDisplay': 'від 200 до 350 грн',
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
      'priceDisplay': '500 грн',
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
        'priceDisplay': '500 грн',
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
      'priceDisplay': '500 грн',
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
        'priceDisplay': '500 грн',
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

  // ── Call-count telemetry (for assertions in tests) ────────────────────────

  int loginCalls = 0;
  int logoutCalls = 0; // POST /api/v1/auth/logout counter
  int registerCalls = 0;
  int verifyEmailCalls = 0;
  int getMeCalls = 0; // GET /api/v1/users/me counter
  int patchMeCalls = 0; // PATCH /api/v1/users/me counter (CLIENT profile edit)
  Map<String, dynamic>?
  lastPatchMeBody; // body of the most recent PATCH /users/me
  int getMasterCalls = 0;
  int patchProfileCalls = 0;
  Map<String, dynamic>? lastPatchBody;
  int getServicesCalls = 0;
  int createServiceCalls = 0;
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

  // ── Favorites telemetry (Phase 13.4) ──────────────────────────────────────
  /// `POST /api/v1/favorites` (add) call count + the most recent body.
  int addFavoriteCalls = 0;
  Map<String, dynamic>? lastAddFavoriteBody;

  /// `DELETE /api/v1/favorites` (remove) call count + the most recent query.
  int removeFavoriteCalls = 0;
  Map<String, dynamic>? lastRemoveFavoriteQuery;

  // ── Override telemetry (Phase 15.8) ───────────────────────────────────────
  int putOverrideCalls = 0;

  /// The most recent override PUT body — `{ date, kind, mode?, intervals?,
  /// times? }`. Lets a test assert the override the editor serialised.
  Map<String, dynamic>? lastOverrideBody;

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
    'cityId': clientCityId,
    'cityName': clientCityName,
    'districtId': clientDistrictId,
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
          'avgRating': 4.9,
          'reviewCount': 24,
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
    'masterId': 'user-master-1',
    'firstName': masterFirstName,
    'lastName': masterLastName,
    'bio': masterBio,
    'phoneNumber': masterPhone,
    'instagram': masterInstagram,
    'avgRating': 4.8,
    'reviewCount': 10,
    'masterType': 'INDEPENDENT_MASTER',
  });

  // ── Route wiring ───────────────────────────────────────────────────────────

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

    // POST /api/v1/independent-masters/me/services
    _adapter.onRoute(
      '/api/v1/independent-masters/me/services',
      (server) => server.replyCallback(201, (req) {
        createServiceCalls++;
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
          'priceDisplay': '${body['price'] ?? body['priceMin'] ?? 0} грн',
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
            'priceDisplay': '${body['price'] ?? body['priceMin'] ?? 0} грн',
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

    // GET /api/v1/locations/oblasts/{oblastId}/cities — one seeded city WITHOUT
    // districts so a CLIENT can select a city through the real cascade and save
    // with ONLY the locality slice (no district step, no address fields). Shape:
    // CityResponse { id, oblastId, katotthCode, nameUk, nameEn, hasDistricts }.
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
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/{masterId}/effective-schedule — empty list.
    // Both /me alias and real masterId path are wired.
    // Query parameters (from/to) are not part of the route path — DioAdapter
    // matches on the path only, so one registration covers all from/to combos.
    for (final path in <String>[
      '/api/v1/masters/me/effective-schedule',
      '/api/v1/masters/user-master-1/effective-schedule',
    ]) {
      _adapter.onRoute(
        path,
        (server) => server.reply(200, _okList(const <dynamic>[])),
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
            (req.queryParameters['categoryName'] as String?) ?? '';
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
    // POST /api/v1/favorites — add (idempotent 200). Returns a FavoriteResponse
    // envelope so the generated addFavorite() deserializes cleanly.
    _adapter.onRoute(
      '/api/v1/favorites',
      (server) => server.replyCallback(200, (req) {
        addFavoriteCalls++;
        final body = _decodeBody(req.data);
        lastAddFavoriteBody = body;
        return _ok(<String, dynamic>{
          'id': 'fav-1',
          'targetType': body['targetType'] ?? 'MASTER',
          'targetId': body['targetId'] ?? '',
          'createdAt': '2026-06-14T12:00:00Z',
        });
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // DELETE /api/v1/favorites?targetType&targetId — remove (idempotent 204).
    _adapter.onRoute(
      '/api/v1/favorites',
      (server) => server.replyCallback(204, (req) {
        removeFavoriteCalls++;
        lastRemoveFavoriteQuery = Map<String, dynamic>.from(
          req.queryParameters,
        );
        return null;
      }),
      request: const Request(method: RequestMethods.delete),
    );
  }

  /// Decodes an HTTP request body that may be a raw JSON String or a Map.
  static Map<String, dynamic> _decodeBody(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
