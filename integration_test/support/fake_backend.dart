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
  ];

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

  // ── Call-count telemetry (for assertions in tests) ────────────────────────

  int loginCalls = 0;
  int registerCalls = 0;
  int verifyEmailCalls = 0;
  int getMeCalls = 0; // GET /api/v1/users/me counter
  int getMasterCalls = 0;
  int patchProfileCalls = 0;
  Map<String, dynamic>? lastPatchBody;
  int getServicesCalls = 0;
  int createServiceCalls = 0;
  Map<String, dynamic>? lastCreatedService;
  int patchServiceCalls = 0;
  Map<String, dynamic>? lastPatchedService;
  int getScheduleCalls = 0;
  int postScheduleCalls = 0;
  int putScheduleCalls = 0;

  /// The `days` list from the most recent weekly-schedule POST/PUT body —
  /// each entry is `{ dayOfWeek, mode?, intervals?, times? }`. Lets a test
  /// assert the EXACT mode + discrete times the editor serialised (Phase 15.8).
  List<dynamic>? lastWeeklyDays;

  // ── Override telemetry (Phase 15.8) ───────────────────────────────────────
  int putOverrideCalls = 0;

  /// The most recent override PUT body — `{ date, kind, mode?, intervals?,
  /// times? }`. Lets a test assert the override the editor serialised.
  Map<String, dynamic>? lastOverrideBody;

  // ── Internal helpers ───────────────────────────────────────────────────────

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
      (server) => server.reply(200, _okVoid),
      request: const Request(method: RequestMethods.post),
    );

    // GET /api/v1/users/me
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) => server.replyCallback(200, (_) {
        getMeCalls++;
        return _ok(userJsonForRole(currentRole));
      }),
      request: const Request(method: RequestMethods.get),
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
      _adapter.onRoute(
        '/api/v1/independent-masters/me/services/$defId',
        (server) => server.replyCallback(200, (req) {
          patchServiceCalls++;
          final body = _decodeBody(req.data);
          lastPatchedService = body;
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

    // GET /api/v1/locations/oblasts — returns empty list (locality cascade)
    _adapter.onRoute(
      '/api/v1/locations/oblasts',
      (server) => server.reply(200, _okList(const <dynamic>[])),
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

    // GET /api/v1/service-categories/approved — one seeded category so the
    // service-create form can select it (category is required by the form).
    // Shape: list of ApprovedCategoryResponse { name, displayName }.
    _adapter.onRoute(
      '/api/v1/service-categories/approved',
      (server) => server.reply(
        200,
        _okList(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'NAILS', 'displayName': 'Нігті'},
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/platform-categories — empty list
    _adapter.onRoute(
      '/api/v1/platform-categories',
      (server) => server.reply(200, _okList(const <dynamic>[])),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// Decodes an HTTP request body that may be a raw JSON String or a Map.
  static Map<String, dynamic> _decodeBody(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
