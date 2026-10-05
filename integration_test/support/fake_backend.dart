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
//  GET  /api/v1/salons/mine              — Phase 21.1 My Salons Hub (SALON_OWNER landing)
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

/// Phase 248 — the fixed id `POST /api/v1/masters/{masterId}/bookings`
/// mints for a walk-in booking created through the wizard. Fixed (not
/// generated) because this fake serves exactly one flow that submits this
/// endpoint per test; a second submit in the same test would overwrite the
/// same dataset row rather than appending a second one.
const String kWalkInBookingId = 'walkin-booking-1';

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

/// `phoneNumber` and `instagram` are POPULATED (mobile-qa 21.14 F3). The owner
/// «Профіль» tab renders its phone tile unconditionally and its Instagram tile
/// only when one is set, so an owner persona with neither contact let the E2E
/// exercise the em-dash arm ONLY — the populated arm was covered at widget
/// level, where the fixture is a Dart `User` and can therefore never prove the
/// two keys survive the `UserProfileResponse` decode. Both values are
/// obviously synthetic and follow the other personas' pattern
/// (`masterPhone` = `+380501111111`, `masterInstagram` = `@olena_nails`).
const Map<String, dynamic> _ownerUserJson = <String, dynamic>{
  'id': 'user-owner-1',
  'email': 'owner@beautica.ua',
  'role': 'SALON_OWNER',
  'firstName': 'Оксана',
  'lastName': 'Власник',
  'phoneNumber': '+380502222222',
  'instagram': '@oksana_salon',
};

const Map<String, dynamic> _masterUserJson = <String, dynamic>{
  'id': 'user-master-1',
  'email': 'master@beautica.ua',
  'role': 'INDEPENDENT_MASTER',
  'firstName': 'Олена',
  'lastName': 'Ковальчук',
};

/// mobile-qa Phase 21.8 gap-closure (2026-08-28) — SALON_ADMIN had no persona
/// at all: `userJsonForRole` fell through the `_ => _masterUserJson` default,
/// so `currentRole = UserRole.salonAdmin` silently logged in as an
/// INDEPENDENT_MASTER (wrong role string, no `salonId`). No E2E flow could
/// exercise the admin landing (`SalonHomeResolverScreen`'s synchronous
/// `session.user.salonId` arm) until this was added. `salonId` is
/// DELIBERATELY a different id than any row in [FakeBackend.mySalons]
/// (`salon-owner-1`) — the admin landing must never depend on
/// `mySalonsProvider` at all; sharing an id with the owner fixture would mask
/// a regression that made it do so.
///
/// mobile-qa Phase 21.16 (2026-09-05) — `phoneNumber` and `professionalTitle`
/// are POPULATED, for the same reason the owner persona's contacts were
/// (21.14 F3): `AdminOwnProfileScreen` renders BOTH conditionally, so an
/// unpopulated persona makes every assertion about them vacuous — the section
/// would be absent whether the decode worked or not, and a tile wired to the
/// wrong `UserProfileResponse` key would look identical to a correct one.
/// `instagram` is deliberately LEFT OFF: the admin profile must never draw an
/// Instagram tile, and that deny arm is proven at the widget tier
/// (`admin_own_profile_screen_test.dart`) with a fixture that HAS a handle —
/// adding one here would only make the E2E's own deny arm the weaker of the
/// two.
const Map<String, dynamic> _adminUserJson = <String, dynamic>{
  'id': 'user-admin-1',
  'email': 'admin@beautica.ua',
  'role': 'SALON_ADMIN',
  'firstName': 'Ірина',
  'lastName': 'Адміністратор',
  'phoneNumber': '+380663334455',
  'professionalTitle': 'Старший адміністратор',
  'salonId': 'salon-admin-1',
};

/// mobile-qa gap-closure (Phase 309-311 track, 2026-09-06) — the SAME class
/// of bug the 21.8 fix above closed for SALON_ADMIN, just not yet fixed for
/// this role: `userJsonForRole` fell through the `_ => _masterUserJson`
/// default, so `currentRole = UserRole.salonMaster` silently logged in as an
/// INDEPENDENT_MASTER (wrong role string, no way to reach `/staff/*` at all)
/// — no E2E flow could exercise ANY SALON_MASTER journey until this was
/// added, discovered while authoring
/// `salon_master_schedule_nav_flow_test.dart`. `salonId` is deliberately
/// OMITTED (unlike the admin persona above): `salonMasterOwnProfileNotifier`
/// treats a null `salonId` as "no employing salon" and degrades the
/// identity card gracefully (no salon-name/address rows), which is exactly
/// what this fixture needs for a role whose ONLY currently-shipped surfaces
/// (`/staff/profile`, `/staff/schedule`) do not depend on that salon read
/// resolving — see that notifier's own doc for the degrade-to-null path.
const Map<String, dynamic> _salonMasterUserJson = <String, dynamic>{
  'id': 'user-salon-master-1',
  'email': 'salonmaster@beautica.ua',
  'role': 'SALON_MASTER',
  'firstName': 'Тарас',
  'lastName': 'Майстренко',
};

/// Returns the stub JSON body for [UserRole] in `GET /users/me` shape.
///
/// Exhaustive over every [UserRole] (no wildcard default) — the SALON_ADMIN
/// and SALON_MASTER doc comments above both record what a wildcard here
/// actually costs: a role that silently logs in as INDEPENDENT_MASTER
/// instead of failing to compile the day a sixth role is added.
Map<String, dynamic> userJsonForRole(UserRole role) {
  return switch (role) {
    UserRole.client => _clientUserJson,
    UserRole.salonOwner => _ownerUserJson,
    UserRole.salonAdmin => _adminUserJson,
    UserRole.salonMaster => _salonMasterUserJson,
    UserRole.independentMaster => _masterUserJson,
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
///
/// `salonId` is forwarded when the persona has one. The real backend populates
/// it on this envelope for an invited `SALON_ADMIN`/`SALON_MASTER`, and
/// `POST /auth/invite/accept` NEVER follows with `GET /users/me` — so this
/// envelope is the only place the binding can reach the session, and a fake
/// that dropped it could not express an invite-accept → salon-home flow at all
/// (it would land on the resolver's incomplete-session arm instead of the
/// shell). Omitted entirely for personas with no salon so the wire stays the
/// shape the backend actually sends.
Map<String, dynamic> _authResponse(Map<String, dynamic> user) =>
    <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': <String, dynamic>{
        'userId': user['id'],
        'email': user['email'],
        'role': user['role'],
        if (user['salonId'] != null) 'salonId': user['salonId'],
        'accessToken': 'fake-access-token',
        'refreshToken': 'fake-refresh-token',
        'tokenType': 'Bearer',
      },
    };

// ---------------------------------------------------------------------------
// FakeBackend
// ---------------------------------------------------------------------------

/// The bare («not composed with an oblast/hromada suffix) display name for
/// every settlement id seeded by `GET /api/v1/settlements` below — the exact
/// shape `/users/me`'s denormalised `cityName` carries on the real wire.
///
/// Kept in agreement BY HAND with the `nameUk` values on the
/// `GET /api/v1/settlements` rows below — a PATCH-driven `cityId` change (the
/// Location edit screens) must echo the SAME name those rows would compose
/// bare (no oblast/hromada suffix). See the `PATCH /api/v1/users/me`
/// handler's own doc for why this now matters post-phase-346.
const Map<String, String> kSeededSettlementNames = <String, String>{
  'city-kyiv': 'Київ',
  'city-lviv': 'Львів',
  'city-with-districts': 'Дніпро',
  'village-ivanivka': 'Іванівка',
};

/// The oblast name (`oblastNameUk`) of every settlement id seeded by
/// `GET /api/v1/settlements` below — kept in agreement BY HAND with those
/// rows, exactly like [kSeededSettlementNames].
///
/// Backend Phase 328 (`f3720365`): `SalonResponse`/`PublicSalonResponse`
/// `city`/`region` are DERIVED from the salon's `cityId` (the settlement's
/// name and its oblast); the request-side `city`/`region`/`address` are
/// ignored. Every salon payload this fake serves goes through
/// [withSeededSalonLocality] so it carries that same derived pair.
const Map<String, String> kSeededSettlementOblastNames = <String, String>{
  'city-kyiv': 'Київ',
  'city-lviv': 'Львівська',
  'city-with-districts': 'Дніпропетровська',
  'village-ivanivka': 'Полтавська',
};

/// The wire `settlementType` of every settlement id seeded by
/// `GET /api/v1/settlements` below — kept in agreement BY HAND with those
/// rows, exactly like [kSeededSettlementNames].
///
/// Backend Phase 330 (`a9992eba`): every SAVED-locality read (`/users/me`,
/// `/salons/mine`, `/salons/{id}`, `/masters/me`, the public salon/master
/// reads) carries the settlement's `citySettlementType` so the client prefixes
/// the saved label («м.» / «с.») exactly as it prefixes a picked row.
const Map<String, String> kSeededSettlementTypes = <String, String>{
  'city-kyiv': 'CITY',
  'city-lviv': 'CITY',
  'city-with-districts': 'CITY',
  'village-ivanivka': 'VILLAGE',
};

/// The `hromadaNameUk` of the seeded settlements whose name is AMBIGUOUS in
/// their oblast — the only ones the server populates it for (phase-327 D3).
/// Absent id = null hromada, as on the wire.
const Map<String, String> kSeededSettlementHromadaNames = <String, String>{
  'village-ivanivka': 'Шишацька',
};

/// Backend Phase 330's saved-settlement label parts for [cityId]:
/// `citySettlementType` plus, ONLY for an ambiguous name,
/// `cityHromadaNameUk`. Empty for a missing or unseeded id (the server's
/// "does not resolve" null), so a caller spreads it unconditionally.
Map<String, dynamic> seededSettlementLabelParts(String? cityId) {
  final String? type = cityId == null ? null : kSeededSettlementTypes[cityId];
  if (type == null) return const <String, dynamic>{};
  return <String, dynamic>{
    'citySettlementType': type,
    if (kSeededSettlementHromadaNames[cityId] != null)
      'cityHromadaNameUk': kSeededSettlementHromadaNames[cityId],
  };
}

/// Returns [salon] with `city`/`region` derived from its `cityId` against the
/// seeded settlement fixtures, as the real backend does since Phase 328 —
/// plus Phase 330's `citySettlementType` / `cityHromadaNameUk`
/// ([seededSettlementLabelParts]).
///
/// A payload whose `cityId` is missing or not a seeded settlement is returned
/// UNCHANGED — e.g. `salon_shell_landing_flow_test.dart`'s deliberately
/// malformed (no-`cityId`) row must stay malformed.
Map<String, dynamic> withSeededSalonLocality(Map<String, dynamic> salon) {
  final Object? cityId = salon['cityId'];
  if (cityId is! String) return salon;
  final String? city = kSeededSettlementNames[cityId];
  if (city == null) return salon;
  return <String, dynamic>{
    ...salon,
    'city': city,
    'region': kSeededSettlementOblastNames[cityId],
    ...seededSettlementLabelParts(cityId),
  };
}

/// Stateful in-memory "backend" wired to a real [Dio] via [DioAdapter].
///
/// Each test creates a fresh instance so state never leaks between tests.
/// The [dio] field is the instance to inject into [dioProvider].
final class FakeBackend {
  FakeBackend({
    this.masterRowId = 'user-master-1',
    this.masterSalonId,
    this.masterMeNotFound = false,
    this.deleteMyAccountFailureStatusCode,
    this.deleteMyAccountFailureMessage =
        'FAKE-422: скасуйте деякі майбутні записи, щоб видалити акаунт',
    this.deleteServiceDelay,
    this.forgotPasswordFailureStatusCode,
    this.mediaAvatarUploadStatus,
  }) : dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080')) {
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
    _wireNotifications();
    _wireDeviceTokens();
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

  /// Phase 321 — the employing salon's id, echoed in `GET /masters/me`'s
  /// nested `salon` object (`MasterDetailResponse.salon.id`, which
  /// `MasterMapper.fromDto` reads as `Master.salonId` — a DIFFERENT wire
  /// shape than `GET /users/me`'s flat `salonId`, which `_salonMasterUserJson`
  /// deliberately omits for an unrelated reason, see that constant's doc).
  ///
  /// Defaults to `null` so `_masterDetailEnvelope()` omits the `salon` key
  /// entirely and every existing flow (including the phase-309/310 SALON_
  /// MASTER schedule flows, which never depend on it) keeps seeing the exact
  /// same body. Set it before boot for a flow that needs the viewer's OWN
  /// salon to resolve — e.g. the phase-321 `/staff/services` own-target flow,
  /// which reuses the `salon-xyz` / `master-removable` fixture pair
  /// [_wireSalonMasterServices] already wires by pairing this with
  /// `masterRowId: 'master-removable'`.
  final String? masterSalonId;

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

  /// Phase 346 QA — the taxonomy locality ids on `GET /masters/me`. Null by
  /// default and then OMITTED from the envelope, so every pre-existing flow's
  /// body is byte-identical. Written by `PATCH /independent-masters/me`.
  String? masterCityId;
  String? masterDistrictId;

  /// `PATCH /api/v1/independent-masters/me` (the master Location screen's
  /// `updateLocality`) call count + last body.
  int patchMasterLocalityCalls = 0;
  Map<String, dynamic>? lastPatchMasterLocalityBody;

  /// Every `query` the settlement autocomplete sent to `GET /settlements`,
  /// in order (the blank pre-typing request is recorded as '').
  final List<String> settlementQueries = <String>[];
  String? masterStreet;
  String? masterBuildingNo;
  String? masterLocationNote;

  // ── Phase 21.14 — the owner-as-master gate ────────────────────────────────

  /// Backend Phase 265's `UserProfileResponse.hasMasterProfile`, as served by
  /// `GET /users/me` for every NON-CLIENT persona.
  ///
  /// TRI-STATE, matching the wire exactly — `null` is not `false`:
  ///   • `null` (the DEFAULT) — the key is OMITTED from the body entirely, the
  ///     shape an older backend produces. `owner_own_profile_notifier.dart`
  ///     resolves that by probing `GET /masters/me`. Defaulting to null keeps
  ///     every pre-existing flow byte-identical.
  ///   • `true`  — proven positive; the master section loads.
  ///   • `false` — proven negative; the section renders ABSENT and the
  ///     `/masters/me` probe's result is discarded.
  ///
  /// Set BEFORE login (the value is read per-request by the `/users/me`
  /// handler, so a mid-flow change takes effect on the next read).
  bool? hasMasterProfile;

  /// When true, `GET /masters/me` replies **404** with the standard
  /// not-found envelope instead of the master detail.
  ///
  /// This is the real backend's answer for a `SALON_OWNER` who has no ACTIVE
  /// `masterType = SALON_OWNER` row — NOT 403, since backend `c4d69ac`
  /// widened that endpoint's `@PreAuthorize` to admit `SALON_OWNER`. It is
  /// also the shape of the RACE the loader degrades: `hasMasterProfile` was
  /// true when `/users/me` answered and the row was deactivated before
  /// `/masters/me` was reached. Defaults false so every existing flow keeps
  /// its 200.
  ///
  /// CONSTRUCTOR-TIME, unlike [hasMasterProfile]: `DioAdapter.onRoute` fixes a
  /// route's STATUS CODE at registration (only the BODY is resolved per
  /// request, by `replyCallback`), and `_wire()` runs from the constructor —
  /// so this cannot be a mutable field the way the body-level knobs are.
  final bool masterMeNotFound;

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

  /// Phase 346 follow-up (Phase 348 QA) — when non-null, the CLIENT
  /// `GET /users/me` serves THIS raw `citySettlementType` instead of the one
  /// derived from [clientCityId] ([seededSettlementLabelParts]). Exists so a
  /// flow can put a value THIS build predates (e.g. `HAMLET`) on the wire and
  /// prove the generated enum's unknown-value fallback keeps the session
  /// alive. `null` (the default) keeps the derived, real-backend shape.
  String? clientCitySettlementTypeOverride;

  // ── Mutable SALON_ADMIN identity state (PATCH /users/me round-trip,
  // Phase 356) ─────────────────────────────────────────────────────────────
  //
  // `client_personal_info_edit_screen.dart` / `client_contacts_edit_screen
  // .dart` are REUSED VERBATIM by the admin's own settings hub
  // (`RouteNames.adminEditPersonal`/`adminEditContacts`), and both PATCH the
  // SAME `/users/me` endpoint the CLIENT editors do. Before this state
  // existed, `GET /users/me` for a non-CLIENT role always served the STATIC
  // `_adminUserJson` — a save would round-trip through `PATCH /users/me` and
  // the screen would optimistically look saved, but the very next
  // `refreshUser()`/`clientEditProfileProvider` re-fetch would silently
  // revert to the pre-save name, which no widget-tier fixture (a
  // Dart-constructed `User`) can catch. Defaults match `_adminUserJson`
  // exactly, so every flow that never PATCHes these fields sees the exact
  // fixture it always has.
  String adminFirstName = 'Ірина';
  String adminLastName = 'Адміністратор';
  String? adminPhone = '+380663334455';

  // ── SALON_OWNER state (Phase 21.1 My Salons Hub) ───────────────────────────
  //
  // `GET /api/v1/salons/mine` — `SalonResponse` shape (carries `isPrimary`,
  // unlike the PUBLIC `PublicSalonResponse`). Mutable list, not a `const`,
  // so a flow that needs to pin the stagger-crash regression (~12 salons) or
  // the "no primary among many" edge case can replace it BEFORE boot without
  // forking a second fixture set. Defaults to exactly ONE primary salon —
  // the ordinary owner shape (registration always yields ≥1 salon).
  List<Map<String, dynamic>> mySalons = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'salon-owner-1',
      'ownerId': 'user-owner-1',
      'name': 'Салон Оксани',
      'city': 'Київ',
      // RESUME §4 step D (mobile half) — `SalonResponse.cityId`/`.oblastId`
      // are non-null on the wire (backend `ec22d91`); reusing the SAME
      // `city-kyiv`/`oblast-kyiv` pair every other salon fixture in this
      // file resolves against (see the `/locations/oblasts/oblast-kyiv/
      // cities` handler below) rather than a free-floating id that would
      // resolve to nothing.
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'Хрещатик',
      'buildingNo': '10',
      'isActive': true,
      'isPrimary': true,
    },
  ];

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

  /// Phase 318 (mobile-qa) — sequence for rows created through the
  /// SALON-scoped bulk-create route. A SEPARATE counter from
  /// [_nextServiceSeq] (the independent-master one) so the two id spaces
  /// never collide when a single test flow exercises both.
  int _nextSalonServiceSeq = 1;

  /// Phase 322 (mobile-qa) — sequence for rows created through the
  /// SALON_ADMIN own-salon bulk-create route
  /// (`_wireSalonAdminMasterServicesBulk`). A SEPARATE counter from
  /// [_nextSalonServiceSeq] so the two salon/master pairs' id spaces never
  /// collide when a single test flow somehow exercises both.
  int _nextSalonAdminServiceSeq = 1;

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

  /// 2026-09-14 (mobile-qa) — reseeds the weekly schedule as a NON-CONTIGUOUS
  /// Mon / Wed / Fri 10:00–19:00 pattern, which `weeklyScheduleSummary`
  /// renders as the long comma-joined «Пн, Ср, Пт · 10:00–19:00» form instead
  /// of the short «Пн–Вт» range the default seed produces.
  ///
  /// Exists for the `ManagementActionCard` truncation regression: with the
  /// default seed the schedule card's value is short enough to fit any
  /// column, which would make a `didExceedMaxLines` assertion pass whether or
  /// not the 2026-09-14 text-token fix is present
  /// (`project_fixture_values_can_defang_assertions`).
  ///
  /// Still TWO-OR-MORE working days and still Sunday-empty, so it is a
  /// drop-in for the default seed in every downstream assertion of the flow
  /// that uses it: toggling Monday off leaves Wed+Fri active (the PUT path,
  /// never the DELETE path), and `kFixedNow` (2026-06-14, a Sunday) still
  /// resolves to the per-day NO_SCHEDULE banner. Additive — no existing
  /// caller's behaviour changes.
  void seedNonContiguousWeeklySchedule() =>
      _weeklySchedule = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'schedule-1',
          'validFrom': '2026-06-14',
          'validTo': null,
          'days': <Map<String, dynamic>>[
            for (int day = 1; day <= 7; day++)
              <String, dynamic>{
                'dayOfWeek': day,
                'intervals': const <int>[1, 3, 5].contains(day)
                    ? <Map<String, dynamic>>[
                        <String, dynamic>{
                          'startTime': '10:00',
                          'endTime': '19:00',
                        },
                      ]
                    : <dynamic>[],
              },
          ],
        },
      ];

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

  /// `POST /api/v1/auth/invite/accept` call count.
  int acceptInviteCalls = 0;

  /// The full decoded body of the most recent `POST /api/v1/auth/invite/accept`
  /// — lets a flow prove the form's own field values reached the wire, rather
  /// than only that the button was tapped.
  Map<String, dynamic>? lastAcceptInviteBody;

  /// `GET /api/v1/auth/invite/validate` call count + the token it carried.
  ///
  /// The token is captured because it is the ONLY thing that links the deep
  /// link's query string to the network call: `AcceptInviteScreen` takes it
  /// from `state.uri.queryParameters['token']` and passes it to a FAMILY
  /// provider, so a screen that read the wrong query key would still render a
  /// perfectly normal form off a `''` token.
  int validateInviteCalls = 0;
  String? lastValidateInviteToken;

  // ── Beautica OTP task (Phase B) — password-reset OTP flow counters ────────

  /// Overrides the `POST /api/v1/auth/forgot-password` status.
  ///
  /// `null` (every pre-existing call site) keeps the generic anti-enumeration
  /// 200. Set it to 429 to reproduce the per-IP `AuthRateLimitFilter` bucket
  /// being exhausted — the body is then the FILTER's own bare
  /// `{"error":"Too many requests"}`, with no `message`, no `errors` and no
  /// `data.code`, because the filter runs BEFORE the controller and the
  /// generic-200 contract never gets a say. That exact shape is the point:
  /// a richer envelope would let a mapper branch that merely reads the body
  /// look correct.
  ///
  /// Read at construction time (like [deleteMyAccountFailureStatusCode]) —
  /// routes are wired once from the constructor, so pass it to `FakeBackend()`
  /// rather than mutating it after boot.
  final int? forgotPasswordFailureStatusCode;

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

  /// `GET /api/v1/salons/mine` call counter (Phase 21.1 My Salons Hub).
  int getMySalonsCalls = 0;

  /// `POST /api/v1/salons` call counter (Phase 21.3 «Register New Salon»,
  /// `RegisterSalonScreen`/`RegisterSalon.submit`).
  int createSalonCalls = 0;

  /// The full decoded body of the most recent `POST /api/v1/salons` request.
  Map<String, dynamic>? lastCreateSalonBody;

  /// When set, `POST /api/v1/salons` replies with this status instead of 200
  /// — lets a flow exercise `RegisterSalonScreen`'s error-snack path.
  int? createSalonFailureStatusCode;

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

  /// Status code `GET /api/v1/clients/me/passport` fails with, or null for the
  /// default 200. Set via [forcePassportFailure] — never assign directly:
  /// `DioAdapter.onRoute` bakes the reply's status code in at REGISTRATION
  /// time (`RequestHandler.replyCallback`'s `statusCode` param is captured the
  /// instant the route is registered, not read fresh per request), so the
  /// route has to be RE-REGISTERED for a status change to take effect — same
  /// device as [forceListMasterFavoritesFailure] / [forceRemoveFavoriteFailure].
  int? _passportFailureStatusCode;

  /// Makes the NEXT (and every subsequent) `GET /api/v1/clients/me/passport`
  /// fail with [statusCode] (a non-5xx, e.g. 400, so `beauticaProviderRetry`
  /// treats it as deterministic and does not silently retry behind the pull
  /// gesture — see `failure_retry_policy.dart`), driving `_PassportSection`'s
  /// `_PassportError` card (Qase defect #9 step 6, "airplane mode" pull).
  /// Call again with `null` to restore the default 200 — the flow that clears
  /// the failure and pulls again to prove the page recovers.
  void forcePassportFailure(int? statusCode) {
    _passportFailureStatusCode = statusCode;
    _wirePassport();
  }

  /// `GET /api/v1/clients/me/timeline` call counter (Phase 110 / mobile-qa
  /// gap-closure — this route did not exist at all until this pass; see
  /// [timelineRows]'s doc for the defect that absence caused).
  int getTimelineCalls = 0;

  /// Rows served by `GET /api/v1/clients/me/timeline`'s page envelope
  /// (`data.data`). Defaults to EMPTY, which drives the BEAUTY TIMELINE
  /// rail's `timeline_empty` state — the same default every sibling
  /// placeholder-shaped list uses ([favoriteMasterRows],
  /// [favoriteServiceRows]). Replace wholesale in a flow to serve populated
  /// completed-procedure history.
  ///
  /// Each row is a `TimelineItemResponse`: `bookingId` (String?, may be
  /// omitted/null — a row with no bookingId must render but stay
  /// non-tappable, see `timeline_mapper.dart`'s header), `categoryKey`,
  /// `categoryName`, `date` (a wire-format `Date`, i.e. a bare
  /// `"YYYY-MM-DD"` string — NOT an instant, see `api/lib/src/
  /// date_serializer.dart`), `masterId`, `serviceName`.
  ///
  /// mobile-qa DEFECT NOTE (found authoring the Phase 110 test gaps, fixed
  /// here): `HttpTimelineRepository` was wired to the REAL
  /// `GET /clients/me/timeline` endpoint, but this route was never added to
  /// FakeBackend. Every E2E flow that reached the BEAUTY TIMELINE section
  /// therefore hit an unmocked path and the card rendered its ERROR state —
  /// `find.byType(BeautyTimelineSection)` (only built on the DATA branch of
  /// `timelineAsync.when`) matched nothing, and `_scrollHubTo` threw `Bad
  /// state: No element` scrolling for a widget that was never built. Two
  /// tests in `client_home_hub_flow_test.dart` were red for exactly this
  /// reason before this route was added — this is test infrastructure
  /// (`integration_test/support/`), not `lib/` production code.
  List<Map<String, dynamic>> timelineRows = <Map<String, dynamic>>[];

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

  // ── «Улюблені» (Phase 111, mobile-qa) ──────────────────────────────────────
  //
  // `GET /api/v1/favorites/masters` and `/salons` — the two endpoints the
  // FavoritesScreen merges into one flat list. Before Phase 111 neither had a
  // handler at all, so the screen 404'd into its error surface in every E2E
  // that so much as landed on the favourites tab.
  //
  // Both default to EMPTY, which drives the "nothing saved yet" empty state and
  // leaves every pre-existing flow's behaviour unchanged.

  /// `GET /api/v1/favorites/masters` call counter — lets a flow prove a
  /// pull-to-refresh actually refetched rather than replaying a cached value.
  int listMasterFavoritesCalls = 0;

  /// `GET /api/v1/favorites/salons` call counter.
  int listSalonFavoritesCalls = 0;

  /// Rows served by `GET /api/v1/favorites/masters`. Each is a
  /// `FavoriteMasterResponse`: `masterId`, `firstName`, `lastName`,
  /// `avatarUrl`, `cityLabel`, `districtLabel`, `avgRating`, `street`,
  /// `buildingNo`, `locationNote`.
  List<Map<String, dynamic>> favoriteMasterRows = <Map<String, dynamic>>[];

  /// Rows served by `GET /api/v1/favorites/salons`. Each is a
  /// `FavoriteSalonResponse`: `salonId`, `name`, `avatarUrl`, `cityLabel`,
  /// `districtLabel`, `avgRating`, `street`, `buildingNo`, `locationNote`.
  List<Map<String, dynamic>> favoriteSalonRows = <Map<String, dynamic>>[];

  /// Status code `GET /api/v1/favorites/masters` fails with, or null for the
  /// default 200. Set via [forceListMasterFavoritesFailure] — never assign
  /// directly, because the route has to be RE-REGISTERED for a status change to
  /// take effect (same device as [forceRemoveFavoriteFailure]).
  int? _listMasterFavoritesFailureStatusCode;

  /// Makes the NEXT (and every subsequent) `GET /api/v1/favorites/masters` fail
  /// with [statusCode], so a flow can drive the «Улюблені» ERROR surface and
  /// its retry affordance. Call again with `null` to restore the default 200.
  ///
  /// Only the MASTERS feed is failed, deliberately: `Favorites._load` fetches
  /// both endpoints with `Future.wait`, which propagates the FIRST error — so
  /// failing one is enough to prove the whole load fails rather than
  /// half-rendering, which is a contract worth exercising in its own right.
  void forceListMasterFavoritesFailure(int? statusCode) {
    _listMasterFavoritesFailureStatusCode = statusCode;
    _wireListMasterFavorites();
  }

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

  /// Phase 350 — the FULL, ordered `serviceId` list the most recent
  /// `master-aaa/slots` request carried (`null` when the param was absent).
  /// Mirrors [lastMasterAaaWorkingDaysServiceIds] one step later in the
  /// flow — the rebook E2E advances past the date step into the TIME step
  /// and asserts availability was requested for the exact multi-service
  /// selection there too, not just at the calendar gate.
  List<String>? lastMasterAaaSlotsServiceIds;

  /// Phase 350 — when true, `GET /masters/master-aaa/services` omits
  /// `pub-assign-1` from its response, as if the client's booked service had
  /// been deactivated since. Models the D6 stale-service rebook scenario
  /// (`client_rebook_from_past_flow_test.dart`) without touching the seeded
  /// `booking-1`'s own `masterServiceId` (which stays `pub-assign-1` — the
  /// booking record itself never changes, only the live catalogue it is
  /// re-checked against). Off by default, so every pre-existing flow keeps
  /// seeing both services.
  bool publicMasterServiceRemoved = false;

  /// mobile-qa (2026-09-26, Phase 355 gap-closure) — when true,
  /// `GET /api/v1/masters/master-aaa/services` returns an empty list
  /// instead of [_publicMasterServicesEffective]. This is the SAME endpoint
  /// `SalonStaffProfileScreen`'s notifier reads (`getMasterServices`, via
  /// `publicServiceRepositoryProvider` — see `salon_staff_member_notifier
  /// .dart`), so it drives BOTH the owner/admin management-card «Ще немає»
  /// value AND the «Послуги» tab body for master-aaa, not merely the public
  /// client-facing profile the pre-existing [publicMasterServiceRemoved]
  /// flag models. A SEPARATE flag (not a reuse of that one) because that one
  /// removes exactly one seeded row to model a single stale booking, not a
  /// wholly empty catalogue. Off by default, so every pre-existing flow
  /// (public profile included) keeps seeing the seeded catalogue.
  bool masterAaaServicesEmpty = false;

  /// [_publicMasterServices], filtered per [publicMasterServiceRemoved] /
  /// [masterAaaServicesEmpty].
  List<Map<String, dynamic>> get _publicMasterServicesEffective =>
      masterAaaServicesEmpty
      ? const <Map<String, dynamic>>[]
      : publicMasterServiceRemoved
      ? _publicMasterServices
            .where((Map<String, dynamic> row) => row['id'] != 'pub-assign-1')
            .toList(growable: false)
      : _publicMasterServices;

  /// Phase 264 — the FULL, ordered `serviceId` list the most recent
  /// `/masters/$masterRowId/slots` request carried (the routed walk-in
  /// chain's OWN date/time step — `SlotDateScreen`/`SlotTimeScreen`, not the
  /// retired wizard's embedded `MasterSchedulePage`). `null` when the param
  /// was absent. Proves HARD CONSTRAINT 4: a 3-service walk-in visit
  /// requests availability for the WHOLE chained selection
  /// (`getMasterSlots(serviceIds: ordered)`), never `services.first` alone.
  List<String>? lastMasterOwnSlotsServiceIds;

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

  /// Per-`serviceDefId` status code the NEXT (and every subsequent)
  /// `GET /api/v1/salons/{salonId}/services/{serviceDefId}/masters` call
  /// fails with, or absent for the default 200. Set via
  /// [forceBookableMastersFailure] — never assign directly: same device as
  /// [forcePassportFailure]/[forceListMasterFavoritesFailure] —
  /// `DioAdapter.onRoute` bakes the reply's status code in at REGISTRATION
  /// time, so the route has to be RE-REGISTERED (see
  /// [_wireSalonBookableMasters]) for a status change to take effect.
  final Map<String, int> _bookableMastersFailureStatusCodeByService =
      <String, int>{};

  /// Makes the NEXT (and every subsequent) `GET /api/v1/salons/{salonId}/
  /// services/{serviceDefId}/masters` call for [serviceDefId] fail with
  /// [statusCode] — driving `salonMasterServiceCoverageProvider`'s Phase 266
  /// degraded/retry path instead of a genuine empty-coverage 200. Call again
  /// with `null` to restore the default 200 — the flow that clears the
  /// failure and taps retry to prove the row recovers.
  void forceBookableMastersFailure(String serviceDefId, int? statusCode) {
    if (statusCode == null) {
      _bookableMastersFailureStatusCodeByService.remove(serviceDefId);
    } else {
      _bookableMastersFailureStatusCodeByService[serviceDefId] = statusCode;
    }
    _wireSalonBookableMasters();
  }

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

  /// `GET /api/v1/salons/{salonId}/staff` — Phase 21.5 management-scoped
  /// staff roster (masters + admins, unmasked contacts) backing the
  /// «Персонал» grid tab. Distinct from [getSalonMastersCalls] above (the
  /// PUBLIC masters rail the client-facing profile still uses).
  int getSalonStaffCalls = 0;
  String? lastGetSalonStaffId;

  /// Per-salon breakdown of [getSalonStaffCalls] — keyed by the `{salonId}`
  /// whose route served the request.
  ///
  /// WHY THE AGGREGATE COUNTER CANNOT CARRY A PER-SALON ASSERTION.
  /// [getSalonStaffCalls] is ONE counter bumped by THREE route registrations
  /// (`salon-xyz`, `salon-admin-1`, [kOwnerSalonId]). A SALON_OWNER journey
  /// legitimately touches two of them: `AppHarness.loginAs(salonOwner)` lands
  /// on `/salons/home` -> `SalonShellScreen(salonId: kOwnerSalonId)`, whose
  /// slot 0 mounts the management profile and fetches THAT salon's roster —
  /// before the test ever navigates to `salon-xyz`. Two distinct
  /// `salonManagementProfileProvider` FAMILY ELEMENTS, one build and one fetch
  /// each; no rebuild, no invalidation, no redundant watch. An
  /// `expect(getSalonStaffCalls, 1)` therefore reads <2> and indicts
  /// production code that is behaving correctly — in production the
  /// management surface IS the shell (same salonId, same family element), and
  /// the jump to a second salon is a test-only `router.go`.
  ///
  /// This ledger makes "did SALON X's roster get re-fetched?" expressible
  /// without that cross-talk. Assert on `getSalonStaffCallsById[salonId]`
  /// (and on a DELTA across the interaction under test); keep the aggregate
  /// only for `greaterThanOrEqualTo` "it happened at all" checks.
  ///
  /// HISTORICAL NOTE (why this only started biting on this branch):
  /// `origin/dev` registers only TWO `getSalonStaffCalls++` sites —
  /// `/api/v1/salons/$kOwnerSalonId/staff` is UNREGISTERED there, so the
  /// shell's roster fetch goes unmatched, uncounted, and every SALON_OWNER
  /// integration test renders the shell's «Салон» slot in a SILENT ERROR
  /// STATE. Commit `cb79331a` (phase 21.12) registered that route and thereby
  /// made the pre-existing fetch countable; it did not introduce the fetch
  /// (`lib/routing/role_home.dart` is byte-identical dev<->HEAD, and dev's
  /// shell already mounts the same slot-0 screen).
  final Map<String, int> getSalonStaffCallsById = <String, int>{};

  // ─── Phase 21.6 — admin management (remove / rotate / sibling salons) ────
  //
  // `DELETE /salons/{salonId}/admins/{userId}`,
  // `PATCH  /salons/{salonId}/admins/{userId}/salon` and
  // `GET    /salons/{salonId}/sibling-salons` (backend Phase 21.3b).
  //
  // GENUINELY STATEFUL, like the pending-invite handlers: the DELETE and the
  // PATCH both REMOVE the administrator from [salonStaff], so a flow that
  // re-enters «Персонал» observes a roster the backend actually changed. A
  // canned 204 would let a purely client-side removal pass.

  /// The mutable `salon-xyz` roster served by
  /// `GET /salons/salon-xyz/staff` — seeded from [_salonStaff] per
  /// [FakeBackend] instance so one flow's removal never leaks into another.
  late final List<Map<String, dynamic>> salonStaff = <Map<String, dynamic>>[
    for (final Map<String, dynamic> row in _salonStaff)
      Map<String, dynamic>.from(row),
  ];

  /// mobile-qa Phase 308 LOW closure (2026-09-05) — the mutable
  /// `salon-admin-1` roster served by `GET /salons/salon-admin-1/staff`.
  ///
  /// DELIBERATELY an ISOLATED fixture, not a widened `salonStaff` (the
  /// `salon-xyz` roster above): three unrelated integration files
  /// (`owner_own_profile_flow_test.dart`, `salon_shell_landing_flow_test.dart`,
  /// `salon_management_profile_flow_test.dart` PART B) already assert against
  /// `salon-xyz`'s roster shape or `salon-admin-1`'s previously-EMPTY one
  /// (the latter only for its own empty-state — none reads THIS list's
  /// content), and Phase 307 had to widen three pre-existing exact-roster
  /// assertions by exactly one element after adding a fixture to the SHARED
  /// list. A second, salon-admin-1-scoped list avoids that ripple entirely.
  ///
  /// Seeded with `admin-peer-1`, a CO-admin distinct from the logged-in
  /// `_adminUserJson.id` (`user-admin-1`) — so a genuine SALON_ADMIN session
  /// viewing this roster is looking at a peer, not their own row. That
  /// distinction matters: `StaffSettingsScreen`'s `canManageStaff`
  /// gate (`isOwner && member?.userId != currentUserId`) is `false` for an
  /// admin viewer regardless of whose row it is (an admin is never `isOwner`),
  /// but a self-row subject would let a reader conflate "not the owner" with
  /// "cannot remove yourself" — two different reasons the row could be
  /// absent. A peer isolates the ONE gate under test.
  ///
  /// mobile-qa gap-closure (2026-09-12) — WIDENED with a THIRD row,
  /// `user-admin-1` (== `_adminUserJson.id`, the logged-in admin's OWN
  /// account), so `salon_staff_settings_admin_gate_flow_test.dart` can drive
  /// the real «Команда» tab end-to-end and prove
  /// `salon_management_profile_screen.dart`'s self-exclusion filter
  /// (restored 2026-09-12 from an over-broad masters-only one — see that
  /// file's own comment) over the real wire: the viewer's own row must be
  /// absent from the rendered grid while `admin-peer-1`'s co-admin row
  /// renders. Checked against every other consumer of this list
  /// (`grep -a -rn salonAdminOneStaff integration_test/`) before widening —
  /// `salon_admin_set_master_services_flow_test.dart` only reads the master
  /// row below by key, and `salon_admin_edit_master_schedule_flow_test.dart`
  /// only asserts that same master row's card is present, neither by exact
  /// list length — so a third row is safe to append here.
  late final List<Map<String, dynamic>> salonAdminOneStaff =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'userId': 'admin-peer-1',
          'masterId': null,
          'role': 'SALON_ADMIN',
          'firstName': 'Марія',
          'lastName': 'Сусідська',
          'professionalTitle': null,
          'avatarUrl': null,
          'phoneNumber': '+380639998877',
          'instagram': null,
          'bio': null,
          'avgRating': null,
          'reviewCount': 0,
          'serviceCount': 0,
        },
        // Phase 312 (mobile-qa) — a MASTER row on the SALON_ADMIN persona's
        // OWN salon (`salon-admin-1`), added so the real "admin opens a
        // master's schedule" E2E journey has a roster entry to tap. `userId`
        // is DELIBERATELY DIFFERENT from `masterId` (mirrors `_salonStaff`'s
        // `master-removable` row) so a userId/masterId swap bug on the ADMIN
        // path is caught the same way it already is on the owner path.
        <String, dynamic>{
          'userId': 'user-master-under-admin',
          'masterId': 'master-admin-target',
          'role': 'SALON_MASTER',
          'firstName': 'Настя',
          'lastName': 'Майстриня',
          'professionalTitle': null,
          'avatarUrl': null,
          'phoneNumber': '+380671119900',
          'instagram': null,
          'bio': null,
          'avgRating': null,
          'reviewCount': 0,
          'serviceCount': 0,
        },
        // mobile-qa gap-closure (2026-09-12) — the VIEWER'S OWN admin row.
        // `userId` MUST equal `_adminUserJson['id']` (`user-admin-1`) for
        // the self-exclusion filter to have anything to exclude; name
        // matches `_adminUserJson` too so a rendered card (if the filter
        // regressed and let it through) is recognisable as "self" in a
        // failure diff.
        <String, dynamic>{
          'userId': 'user-admin-1',
          'masterId': null,
          'role': 'SALON_ADMIN',
          'firstName': 'Ірина',
          'lastName': 'Адміністратор',
          'professionalTitle': 'Старший адміністратор',
          'avatarUrl': null,
          'phoneNumber': '+380663334455',
          'instagram': null,
          'bio': null,
          'avgRating': null,
          'reviewCount': 0,
          'serviceCount': 0,
        },
      ];

  /// mobile-qa gap-closure (2026-09-12) — the `salon-admin-1`-scoped sibling-
  /// salons payload served by `GET /salons/salon-admin-1/sibling-salons`.
  ///
  /// ISOLATED from [siblingSalons] (the `salon-xyz` payload above) for the
  /// same reason [salonAdminOneStaff] is its own list rather than a widened
  /// `salonStaff`: nothing else reads this one, so widening the shared list
  /// would risk rippling into `salon-xyz`'s own exact-content assertions for
  /// zero benefit. Same shape as [siblingSalons] (id/name/street/buildingNo
  /// — `SiblingSalonOption`), and non-empty on purpose: an empty destination
  /// list is indistinguishable from a broken endpoint in
  /// [MoveAdminSalonScreen]'s rendered output, so a flow asserting the
  /// LOADED (not merely non-error) state needs at least one real row here.
  final List<Map<String, dynamic>> salonAdminOneSiblingSalons =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'salon-admin-sibling-1',
          'name': 'Філія на Оболоні',
          'street': 'просп. Оболонський',
          'buildingNo': '12',
        },
      ];

  int removeAdminCalls = 0;
  String? lastRemoveAdminUserId;

  int rotateAdminCalls = 0;
  String? lastRotateAdminUserId;
  Map<String, dynamic>? lastRotateAdminBody;

  /// Phase 307 — `DELETE /api/v1/salons/salon-xyz/masters/{masterId}` call
  /// count + the last `masterId` PATH SEGMENT (never `userId`) it carried.
  /// Keyed by name `lastRemoveMasterId`, not `...UserId`, on purpose: a flow
  /// asserting `fb.lastRemoveMasterId == <masterId>` is the wire-level D2
  /// pin — a client that sent `userId` instead would 404 (see
  /// `SalonRepository.removeMaster`'s own doc), which is a DIFFERENT,
  /// equally-visible failure, but this counter is what proves the byte on
  /// the wire was right when the call DOES succeed.
  int removeMasterCalls = 0;
  String? lastRemoveMasterId;

  int siblingSalonsCalls = 0;

  /// `GET /salons/salon-xyz/sibling-salons` payload — the ACTIVE salons
  /// sharing this salon's owner, minus this salon. Shape mirrors the
  /// backend's `SiblingSalonOption` (id + name + street + buildingNo ONLY —
  /// deliberately narrower than `SalonResponse`). Since the OpenAPI snapshot
  /// refresh this is deserialized by the GENERATED built_value model, so the
  /// shape here is now schema-checked rather than merely conventional.
  final List<Map<String, dynamic>> siblingSalons = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'salon-sibling-1',
      'name': 'Студія «Камелія» на Подолі',
      'street': 'вул. Спаська',
      'buildingNo': '5',
    },
    <String, dynamic>{
      'id': 'salon-sibling-2',
      'name': 'Барбершоп «Дуб»',
      'street': 'вул. Січових Стрільців',
      'buildingNo': '4',
    },
  ];

  /// When non-null, the next `DELETE .../admins/{userId}` answers with this
  /// status instead of 204. Set it via [forceRemoveAdminFailure] — the route
  /// closure captures the value at REGISTRATION time (the same re-wiring
  /// discipline [forceInviteStaffFailure] documents).
  int? _removeAdminFailureStatusCode;

  void forceRemoveAdminFailure(int? statusCode) {
    _removeAdminFailureStatusCode = statusCode;
    _wireAdminManagement();
  }

  /// Same contract as [forceRemoveAdminFailure], for the rotate PATCH.
  int? _rotateAdminFailureStatusCode;

  void forceRotateAdminFailure(int? statusCode) {
    _rotateAdminFailureStatusCode = statusCode;
    _wireAdminManagement();
  }

  /// Same contract as [forceRemoveAdminFailure] (Phase 307), for
  /// `DELETE .../masters/{masterId}`. Backend 297/298 can answer 403
  /// (not owner / self-removal), 409 (own master row / already detached /
  /// audit-blocked) or 404 (not found) — this fixture never distinguishes
  /// the WIRE status from its cause; the mobile mapper's own tests own that.
  int? _removeMasterFailureStatusCode;

  void forceRemoveMasterFailure(int? statusCode) {
    _removeMasterFailureStatusCode = statusCode;
    _wireAdminManagement();
  }

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

  // ── Owner/admin salon management (Phase 21.2) ──────────────────────────

  /// `PATCH /api/v1/salons/{salonId}` call count + the exact last decoded
  /// wire body — lets a flow assert the dirty-diff contract reached the
  /// network (e.g. an untouched `phone` key is ABSENT/null in the body).
  int updateSalonCalls = 0;
  Map<String, dynamic>? lastUpdateSalonBody;

  /// When set, `PATCH /api/v1/salons/salon-xyz` replies with this status and
  /// a failure envelope instead of applying the request.
  int? updateSalonFailureStatusCode;

  /// `DELETE /api/v1/salons/{salonId}` call count.
  int deleteSalonCalls = 0;

  /// When set, `DELETE /api/v1/salons/salon-xyz` replies with this status and
  /// a failure envelope instead of succeeding.
  int? deleteSalonFailureStatusCode;

  /// `DELETE /api/v1/users/me` call count — the CLIENT delete-account
  /// endpoint (mobile-qa, 2026-09-08).
  int deleteMyAccountCalls = 0;

  /// When set (constructor-time — see [masterMeNotFound]'s identical note:
  /// `DioAdapter.onRoute` fixes a route's STATUS CODE at registration, only
  /// the BODY is resolved per request, and route wiring runs from THIS
  /// constructor, so this cannot be a mutable field), `DELETE
  /// /api/v1/users/me` replies with this status instead of the default 204.
  /// 422 carries [deleteMyAccountFailureMessage] as the envelope's
  /// `message` (surfaced verbatim via
  /// `AccountDeleteBookingLimitFailure.serverMessage`); 429 carries no body
  /// (the repository maps 429 by status code alone, before any body is
  /// read — see `HttpUserRepository._mapDeleteAccountException`).
  final int? deleteMyAccountFailureStatusCode;

  /// The 422 envelope's `message` — a distinctive default so a flow that
  /// asserts the message reached the UI verbatim actually proves the wire
  /// round-trip, not a fallback string that would pass regardless.
  /// CONSTRUCTOR-TIME, same reason as [deleteMyAccountFailureStatusCode].
  final String deleteMyAccountFailureMessage;

  /// Phase 21.4 — `POST /api/v1/salons/{salonId}/invite` call count + the
  /// exact last decoded wire body (email/role), so a flow can assert the
  /// REAL serialized request reached the network — mirrors
  /// [updateSalonCalls]/[lastUpdateSalonBody]'s shape exactly.
  int inviteStaffCalls = 0;
  Map<String, dynamic>? lastInviteStaffBody;

  /// Status code `POST /api/v1/salons/salon-xyz/invite` fails with, or null
  /// for the default 200. Set via [forceInviteStaffFailure] — never assign
  /// directly: `DioAdapter.onRoute` bakes the reply's status code in at
  /// REGISTRATION time (`RequestHandler.replyCallback`'s `statusCode` param
  /// is captured the instant the route is registered, not read fresh per
  /// request), so the route has to be RE-REGISTERED for a status change to
  /// take effect — same device as [forceListMasterFavoritesFailure]/
  /// [forceRemoveFavoriteFailure]. A direct assignment silently does
  /// nothing once the constructor's initial registration has already run.
  int? _inviteStaffFailureStatusCode;

  /// Phase 303 — optional `data.code` sub-code for the failure body (e.g.
  /// `EMAIL_ALREADY_REGISTERED` on a 409), so a flow can drive
  /// [ErrorMapperInterceptor]'s typed-failure branch rather than only the
  /// bare-status-code generic path. `null` (the default) reproduces the
  /// original `data: null` envelope every pre-Phase-303 call site still
  /// gets. Same re-registration discipline as [_inviteStaffFailureStatusCode]
  /// — set only via [forceInviteStaffFailure].
  String? _inviteStaffFailureErrorCode;

  /// Makes the NEXT (and every subsequent) `POST /api/v1/salons/salon-xyz
  /// /invite` fail with [statusCode]. Call again with `null` to restore the
  /// default 200 success. [errorCode], when given, is nested as
  /// `data: {"code": errorCode}` in the failure envelope — pass
  /// `'EMAIL_ALREADY_REGISTERED'` with `statusCode: 409` to drive
  /// [EmailAlreadyRegisteredFailure] end-to-end.
  void forceInviteStaffFailure(int? statusCode, {String? errorCode}) {
    _inviteStaffFailureStatusCode = statusCode;
    _inviteStaffFailureErrorCode = errorCode;
    _wireInviteStaff();
  }

  // ─── Staff-invitation HISTORY ────────────────────────────────────────────
  //
  // The salon's OUTBOUND invitation rows, served by
  // `GET /api/v1/salons/salon-xyz/invites` and mutated by BOTH
  // `POST .../invite` (appends a PENDING row) and
  // `DELETE .../invites/{inviteId}` (flips one to CANCELLED — the real
  // endpoint REVOKES the row, it does not delete it). Genuinely stateful on
  // purpose: the two journeys this backs — "cancel one and it STAYS cancelled
  // across a refetch" and "an invite you just sent APPEARS in the list" — are
  // exactly the ones a stateless canned response could not tell apart from
  // the broken behaviour.
  //
  // The GET serves rows in the order [pendingInvites] holds them, mimicking a
  // server that has ALREADY sorted `createdAt DESC`. It does not sort: a fake
  // that re-sorted would let a client which dropped the server order pass.
  //
  // `createdAt` is anchored to [kFixedNow] (the instant the harness injects
  // through `clockProvider`), matching `_clientPublicReview`'s own convention.
  // NOTE: `SalonInviteRow`'s «надіслано …» caption goes through
  // `formatRelativeDate`, whose `now` defaults to the HOST clock rather than
  // `clockProvider` (pre-existing, app-wide — `ReviewCard` does the same), so
  // that ONE caption is host-relative regardless of what is seeded here. No
  // flow asserts on it; the assertions are on the invitee email, which is
  // clock-free.

  /// Two ready-made PENDING invitation rows — a MASTER and an ADMIN, so a
  /// flow that opts in exercises both `SalonInviteMapper` role branches.
  /// Copy them in with [seedPendingInvites].
  ///
  /// Both are pending because the journeys built on this seed CANCEL one: a
  /// terminal row renders no cancel action at all. For a mixed-status history
  /// use [seedSalonInviteHistoryRows] instead.
  static List<Map<String, dynamic>> get seedPendingInviteRows =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'inviteId': 'invite-seed-a',
          'recipientEmail': 'anna.master@beautica.ua',
          'role': 'SALON_MASTER',
          'status': 'PENDING',
          'createdAt': '2026-06-12T09:00:00Z',
          'expiresAt': '2026-06-14T09:00:00Z',
        },
        <String, dynamic>{
          'inviteId': 'invite-seed-b',
          'recipientEmail': 'borys.admin@beautica.ua',
          'role': 'SALON_ADMIN',
          'status': 'PENDING',
          'createdAt': '2026-06-13T09:00:00Z',
          'expiresAt': '2026-06-15T09:00:00Z',
        },
      ];

  /// Four rows covering ALL FOUR wire statuses, ordered exactly as the server
  /// would return them — `createdAt` DESC, newest first.
  ///
  /// The `createdAt` values descend while the ids ascend, so a client that
  /// re-sorted by anything else (id, email, status) would visibly reorder the
  /// list rather than land on the same sequence by luck. Copy them in with
  /// [seedSalonInviteHistory].
  static List<Map<String, dynamic>> get seedSalonInviteHistoryRows =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'inviteId': 'invite-hist-1',
          'recipientEmail': 'pending.master@beautica.ua',
          'role': 'SALON_MASTER',
          'status': 'PENDING',
          'createdAt': '2026-06-20T09:00:00Z',
          'expiresAt': '2026-06-22T09:00:00Z',
        },
        <String, dynamic>{
          'inviteId': 'invite-hist-2',
          'recipientEmail': 'cancelled.admin@beautica.ua',
          'role': 'SALON_ADMIN',
          'status': 'CANCELLED',
          'createdAt': '2026-06-18T09:00:00Z',
          'expiresAt': '2026-06-20T09:00:00Z',
        },
        <String, dynamic>{
          'inviteId': 'invite-hist-3',
          'recipientEmail': 'expired.master@beautica.ua',
          'role': 'SALON_MASTER',
          'status': 'EXPIRED',
          'createdAt': '2026-06-14T09:00:00Z',
          'expiresAt': '2026-06-16T09:00:00Z',
        },
        <String, dynamic>{
          'inviteId': 'invite-hist-4',
          'recipientEmail': 'accepted.admin@beautica.ua',
          'role': 'SALON_ADMIN',
          'status': 'ACCEPTED',
          'createdAt': '2026-06-10T09:00:00Z',
          'expiresAt': '2026-06-12T09:00:00Z',
        },
      ];

  /// Rows served by `GET /api/v1/salons/salon-xyz/invites`, in order.
  /// Mutable and read INSIDE the route callback (never captured at
  /// registration), so a POST/DELETE landing mid-flow is visible to the very
  /// next GET.
  ///
  /// EMPTY BY DEFAULT, deliberately. `InviteStaffScreen` renders its
  /// pending-only block when that filtered list is non-empty, so seeding rows
  /// here globally would inject two extra `SalonInviteRow`s into the tree of
  /// EVERY flow that opens the invite form, and one extra
  /// `GET .../invites` into its call ledger. A shared fake must not
  /// silently change what an unrelated flow renders or counts — opt in with
  /// [seedPendingInvites] instead.
  ///
  /// This default originally ALSO worked around
  /// `salon_management_profile_flow_test.dart`'s role-toggle tap going
  /// ambiguous (the pending row's admin role chip reuses the toggle's own
  /// `Icons.admin_panel_settings_outlined`). That workaround is spent: the
  /// toggle segments now carry `kInviteRoleAdminKey`/`kInviteRoleMasterKey`
  /// and that flow taps by key, so it is immune to extra role glyphs. The
  /// empty default is kept on the tree/ledger-hygiene grounds above alone.
  List<Map<String, dynamic>> pendingInvites = <Map<String, dynamic>>[];

  /// Loads [seedPendingInviteRows] (deep-copied, so a mutation in one test
  /// cannot leak into the next) into [pendingInvites].
  void seedPendingInvites() {
    pendingInvites = seedPendingInviteRows;
  }

  /// Loads [seedSalonInviteHistoryRows] — the four-status, newest-first
  /// fixture — into [pendingInvites]. Opt-in for the same tree/ledger-hygiene
  /// reason [seedPendingInvites] is.
  void seedSalonInviteHistory() {
    pendingInvites = seedSalonInviteHistoryRows;
  }

  /// `truncated` reported by the history GET. False by default, so no flow
  /// renders the truncation note unless it asks for it.
  bool salonInvitesTruncated = false;

  /// `GET /api/v1/salons/salon-xyz/invites` call count — lets a flow
  /// prove a REFETCH actually happened (or, for the optimistic-cancel
  /// contract, that one did NOT).
  int listSalonInvitesCalls = 0;

  /// `DELETE /api/v1/salons/salon-xyz/invites/{inviteId}` call count + the
  /// id of the last one, so a flow can prove the RIGHT invitation was
  /// addressed — a cancel that removed the wrong row would still "make a row
  /// disappear".
  int cancelInviteCalls = 0;
  String? lastCancelInviteId;

  /// Monotonic suffix for ids minted by `POST .../invite`. Starts past the
  /// seeded rows so a minted id can never collide with one of them.
  int _mintedInviteSeq = 0;

  /// Status code the invite-history GET fails with, or null for 200. Set via
  /// [forcePendingInvitesFailure] — never assign directly (see
  /// [_inviteStaffFailureStatusCode]'s doc for why a status change needs the
  /// route RE-REGISTERED).
  int? _pendingInvitesFailureStatusCode;

  /// Makes the NEXT (and every subsequent)
  /// `GET /api/v1/salons/salon-xyz/invites` fail with [statusCode].
  /// Call again with `null` to restore the default 200.
  void forcePendingInvitesFailure(int? statusCode) {
    _pendingInvitesFailureStatusCode = statusCode;
    _wirePendingInvites();
  }

  /// Status code the cancel DELETE fails with, or null for 204. Set via
  /// [forceCancelInviteFailure] — never assign directly.
  int? _cancelInviteFailureStatusCode;

  /// Makes the NEXT (and every subsequent)
  /// `DELETE /api/v1/salons/salon-xyz/invites/{inviteId}` fail with
  /// [statusCode]. A failed cancel must leave the row PENDING in
  /// [pendingInvites] — the handler only flips it on the success path.
  void forceCancelInviteFailure(int? statusCode) {
    _cancelInviteFailureStatusCode = statusCode;
    _wireCancelInvite();
  }

  /// Mutable profile state for `salon-xyz`, shared by BOTH read paths — the
  /// PUBLIC `GET /salons/salon-xyz` (`_publicSalonDetailEnvelope`) and the
  /// owner/admin `PATCH /salons/salon-xyz` response.
  ///
  /// These three fields used to be PATCH-response-only, deliberately kept
  /// SEPARATE from the public envelope because `PublicSalonResponse` carried
  /// no `phone` at all (the Phase 21.2 gap) — the phone field even
  /// started `null` to mirror a `GET` that could never return one. That gap
  /// is CLOSED: the backend now serves `phone` on the public DTO and the
  /// regenerated client declares it
  /// (`api/lib/src/model/public_salon_response.dart`), so keeping two
  /// divergent sources of truth would let a flow "prove" the phone renders
  /// while the public envelope it actually reads never carried one. ONE
  /// source now; the public envelope reads these directly.
  ///
  /// PUBLIC and mutable so a flow can shape the «Контакти» block BEFORE
  /// [FakeBackend]'s constructor wires its routes — e.g. `salonInstagramUrl =
  /// null` for the phone-only combination, or `salonPhone = ''` to exercise
  /// the backend's `""`-verbatim-for-a-cleared-field wire contract that
  /// `SalonMapper._blankToNull` exists to absorb.
  ///
  /// [salonPhone] is seeded to a REAL number on purpose. A `null` seed would
  /// defang every phone assertion in this file's dependants: the pre-fix
  /// `SalonMapper.fromDto` hard-coded `phone: null`, so a null fixture makes
  /// "no phone row renders" pass identically before and after the fix. The
  /// value is deliberately DIFFERENT from the one
  /// `salon_management_profile_flow_test.dart` types into the contacts form,
  /// so an edit still produces a genuine dirty diff.
  String _salonManageName = 'Студія Краси «Камелія»';
  String? salonDescription =
      'Затишна студія краси у центрі Києва. Манікюр, догляд за бровами '
      'та стрижки — довірливий сервіс з 2018 року.';
  String? salonPhone = '+380 44 500 10 20';
  String? salonInstagramUrl = '@kamelia_salon';

  /// RESUME §4 step D (mobile half) — `SalonResponse.cityId`/`.oblastId` are
  /// now non-null on the wire (backend `ec22d91`, `salons.city_id` DB-level
  /// `NOT NULL`), so the PATCH response below must always echo a real pair
  /// or `SalonMapper.fromUpdateDto`'s deserialization throws. Seeded to the
  /// SAME `city-kyiv`/`oblast-kyiv` pair `_publicSalonDetailEnvelope` uses,
  /// mirroring the "untouched field round-trips unchanged" contract the
  /// other `_salonManage*` fields already follow. `districtId` stays
  /// nullable — `city-kyiv` has none.
  ///
  /// Public + shared with the `GET /salons/salon-xyz` read (Phase 348 QA), so
  /// a flow can seat `salon-xyz` in a VILLAGE before login and a saved
  /// address edit is what the NEXT read returns — the real backend has one
  /// `salons.city_id`, not a PATCH echo that the GET ignores.
  String salonManageCityId = 'city-kyiv';
  final String _salonManageOblastId = 'oblast-kyiv';
  String? _salonManageDistrictId;

  int patchProfileCalls = 0;
  Map<String, dynamic>? lastPatchBody;
  int getServicesCalls = 0;
  int createServiceCalls = 0;

  /// `DELETE /api/v1/services/{serviceDefId}` call count — the NULL-TARGET
  /// (independent-master) delete, mobile phase 316's central claim: the
  /// dispatch added to `HttpServiceRepository.deactivate` must leave this path
  /// firing byte-identically when no [SalonMasterTarget] is in scope.
  ///
  /// GENUINELY STATEFUL, mirroring `deleteSalonCalls` / `deleteMyAccountCalls`:
  /// a successful DELETE also REMOVES the row from [_services], so the very
  /// next `GET /independent-masters/me/services` reflects it. Without that a
  /// flow could only prove the DELETE was SENT — the list would keep serving
  /// the "deleted" card forever and a post-delete "the card is gone" assertion
  /// could not distinguish a correct refresh from a broken one.
  int deleteServiceCalls = 0;

  /// The service-DEFINITION id carried in the path of the last
  /// `DELETE /api/v1/services/{serviceDefId}`.
  ///
  /// The seeded fixtures deliberately give every service an assignment id that
  /// DIFFERS from its definition id (`assign-1` vs `svc-1`), so a flow
  /// asserting this value pins the definition-id contract
  /// (`service_edit_screen.dart` passes `service.serviceDefId`, never
  /// `service.id`) rather than passing on either
  /// (`project_fixture_values_can_defang_assertions`).
  String? lastDeletedServiceDefId;

  // ── Phase 317 — the SALON-TARGET services seam ──────────────────────────
  //
  // `GET  /api/v1/salons/{salonId}/masters/{masterId}/services`      (BE 309)
  // `DELETE /api/v1/salons/{s}/masters/{m}/services/{serviceDefId}`  (BE 307)
  //
  // These are the two endpoints `HttpServiceRepository` dispatches to when a
  // `SalonMasterTarget` is in scope (`_listForSalonMaster` /
  // `_unassignFromSalonMaster`). Wired for the roster row whose `userId`
  // (`user-master-removable`) DIFFERS from its `masterId`
  // (`master-removable`), so a flow that asserts the emitted path proves the
  // route builder resolved the `masters` ROW id — with `master-aaa`, whose two
  // ids are identical, the assertion would pass on either
  // (`project_fixture_values_can_defang_assertions`).
  //
  // Registered per EXACT path (the same shape every other salon-xyz route in
  // this file uses) so a request for any other salon/master fails loudly as an
  // unmatched route rather than silently counting.

  /// `GET /api/v1/salons/salon-xyz/masters/master-removable/services` call
  /// count, and the exact path the last one carried.
  int getSalonMasterServicesCalls = 0;
  String? lastSalonMasterServicesPath;

  /// When true, `GET /masters/master-removable/services` — the PUBLIC
  /// per-master read `SalonMasterOwnProfileNotifier` actually calls (see
  /// that file's header: `publicServiceRepositoryProvider.getMasterServices`,
  /// NOT the salon-scoped endpoint [_wireSalonMasterServices] wires) —
  /// returns an empty list instead of [_salonMasterServices]. Models a
  /// SALON_MASTER whose owner/admin has not assigned them any services yet,
  /// for `salon_master_own_profile_tabs_flow_test.dart`'s empty-catalogue
  /// «Послуги» tab case. Off by default, so every pre-existing flow keeps
  /// seeing the seeded catalogue. Status stays 200 either way (only the body
  /// varies), so this flag can be read directly inside the existing
  /// `replyCallback` — no re-registration setter needed (see the RULE
  /// comment above [_wireSalonMasterServices]; that rule is about
  /// STATUS-dependent routes).
  ///
  /// mobile-qa (2026-09-26, Phase 355 gap-closure) — ALSO read by
  /// [_wireSalonMasterServices]'s own GET handler (the salon-scoped `GET
  /// /salons/salon-xyz/masters/master-removable/services` the read-only
  /// `/staff/services` route — [ServicesListScreen] with `writable: false`
  /// — actually resolves through). Both endpoints describe the SAME
  /// underlying fact ("this master has no assigned services"), so one flag
  /// covers both rather than adding a near-duplicate second one.
  bool salonMasterOwnServicesEmpty = false;

  /// Phase 324 (mobile-qa D3) — the cross-role-bleed control counterpart to
  /// [getSalonMasterServicesCalls]/[lastSalonMasterServicesPath]: `GET
  /// /api/v1/salons/salon-xyz/masters/master-aaa/services`. SAME salon
  /// (`salon-xyz`), a DIFFERENT master row already on that salon's roster
  /// (`_salonStaff`'s `master-aaa` entry) — the two masters a single owner
  /// session can navigate between in sequence: roster -> master A's
  /// «Послуги» -> back -> master B's «Послуги». Kept as a SEPARATE counter/
  /// path (never reused across the two master ids) so a bleed bug — master
  /// B's list rendering from a STALE `keepAlive` read of master A's request,
  /// or a `ServiceTarget` that outlives the pop — is visible as "the wrong
  /// counter moved" / "the path still says master-removable", not merely as
  /// "a counter moved".
  int getSalonMasterAaaServicesCalls = 0;
  String? lastSalonMasterAaaServicesPath;

  /// mobile-qa (2026-09-26, Phase 355 gap-closure) — when true,
  /// `GET /api/v1/salons/salon-xyz/masters/master-aaa/services`
  /// ([_wireSalonMasterAaaServices]) returns an empty list instead of
  /// [_salonMasterAaaServices]. Models master-aaa having NO assigned
  /// services, for the "owner opens a master with neither a schedule nor
  /// services — both management-card values render red" E2E. Pair with
  /// [seedNoWeeklySchedule] (the schedule half of that same scenario). Off
  /// by default, so every pre-existing master-aaa flow keeps seeing the
  /// seeded two-item catalogue.
  bool salonMasterAaaServicesEmpty = false;

  /// Phase 322 (mobile-qa) — the SALON_ADMIN persona's own-salon counterpart
  /// to [getSalonMasterServicesCalls]/[lastSalonMasterServicesPath]: `GET
  /// /api/v1/salons/salon-admin-1/masters/master-admin-target/services`.
  /// Kept as SEPARATE counters (not reused across the two salon/master
  /// pairs) so a phase-322 flow's assertions cannot pass on a call that was
  /// actually dispatched against `salon-xyz`/`master-removable`.
  int getSalonAdminMasterServicesCalls = 0;
  String? lastSalonAdminMasterServicesPath;

  /// `DELETE /api/v1/salons/{s}/masters/{m}/services/{serviceDefId}` — the
  /// per-master UNASSIGN. GENUINELY STATEFUL, mirroring [deleteServiceCalls]:
  /// a successful unassign REMOVES the row from [_salonMasterServices], so the
  /// next `GET .../services` reflects it and a "the card is gone" assertion
  /// can tell a correct refresh from a broken one.
  int unassignServiceCalls = 0;
  String? lastUnassignedServiceDefId;
  String? lastUnassignPath;

  // ── Phase 317 — the SPLIT service update (band vs shared definition) ──────
  //
  // THE DEFECT THESE MODEL. Editing one salon master's price/duration used to
  // PATCH the SHARED definition (`PATCH /api/v1/services/{defId}`), silently
  // re-pricing every OTHER master who performs that service. Modelling only
  // the call ROUTING would be too weak a fake to catch it: both endpoints
  // answer 200, so a flow that merely counted calls could pass while the
  // other master's price moved. So this fake models the SHARED SEMANTICS —
  // a definition PATCH carrying money/time CASCADES onto every salon master
  // row that resolves against that definition and has no per-master override
  // — which is what makes "master A's price is untouched" a real assertion
  // rather than a reading of a fixture that could never have changed.

  /// `PATCH /api/v1/salons/{s}/masters/{m}/services/{serviceDefId}` — the
  /// PER-MASTER band write. GENUINELY STATEFUL: a successful call rewrites
  /// THAT master's row only and records a per-master override, so the next
  /// `GET .../services` reflects it and the cascade below skips the row.
  int updateMasterBandCalls = 0;
  String? lastBandPatchPath;
  String? lastBandPatchedServiceDefId;
  Map<String, dynamic>? lastBandPatchBody;

  /// `PATCH /api/v1/services/{serviceDefId}` for a SALON-OWNED definition —
  /// the shared row. [patchSharedDefinitionCalls] counts every such PATCH;
  /// [patchSharedDefinitionPricedCalls] counts only those carrying a money or
  /// time key under EITHER endpoint's spelling.
  ///
  /// The split write sends an IDENTITY-ONLY PATCH here, so the total is
  /// expected to be ≥ 1 on a rename — it is the PRICED counter that must stay
  /// at zero. Counting only the total would make a "no definition PATCH"
  /// assertion fail on correct code and tempt a weaker assertion.
  int patchSharedDefinitionCalls = 0;
  int patchSharedDefinitionPricedCalls = 0;
  Map<String, dynamic>? lastSharedDefinitionPatchBody;

  /// `masterId|serviceDefId` pairs that carry a PER-MASTER band override.
  /// A definition-level price/duration change does not reach these rows —
  /// exactly as on the backend, where an override wins over the shared band.
  final Set<String> _salonBandOverrides = <String>{};

  /// Every salon-scoped master-service row this fake holds, across all three
  /// per-master catalogues. The cascade and the read helpers walk this so a
  /// new fixture list is picked up by adding it HERE, once.
  List<Map<String, dynamic>> get _allSalonRows => <Map<String, dynamic>>[
    ..._salonMasterServices,
    ..._salonMasterAaaServices,
    ..._salonAdminMasterServices,
  ];

  /// The RESOLVED price floor one salon master currently shows for
  /// [serviceDefId] — the per-master value a client would render, not the
  /// shared definition's. `null` when that master has no row for it.
  num? salonResolvedPrice(String masterId, String serviceDefId) {
    for (final Map<String, dynamic> row in _allSalonRows) {
      if (row['masterId'] == masterId &&
          (row['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
              serviceDefId) {
        return row['priceMin'] as num?;
      }
    }
    return null;
  }

  /// The RESOLVED duration one salon master currently shows for
  /// [serviceDefId]. Same contract as [salonResolvedPrice].
  int? salonResolvedDuration(String masterId, String serviceDefId) {
    for (final Map<String, dynamic> row in _allSalonRows) {
      if (row['masterId'] == masterId &&
          (row['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
              serviceDefId) {
        return row['effectiveDurationMinutes'] as int?;
      }
    }
    return null;
  }

  /// The SHARED definition's own band floor for [serviceDefId] — what a
  /// definition-level PATCH rewrites.
  num? salonSharedDefinitionPrice(String serviceDefId) {
    for (final Map<String, dynamic> row in _allSalonRows) {
      final Map<String, dynamic>? def =
          row['serviceDefinition'] as Map<String, dynamic>?;
      if (def?['id'] == serviceDefId) return def?['priceMin'] as num?;
    }
    return null;
  }

  /// Phase 322 (mobile-qa) — the SALON_ADMIN own-salon counterpart to
  /// [unassignServiceCalls]/[lastUnassignedServiceDefId]/[lastUnassignPath],
  /// for `DELETE /api/v1/salons/salon-admin-1/masters/master-admin-target
  /// /services/{serviceDefId}`. GENUINELY STATEFUL, mirroring
  /// [unassignServiceCalls]: removes the row from
  /// [_salonAdminMasterServices].
  int unassignAdminServiceCalls = 0;
  String? lastUnassignedAdminServiceDefId;
  String? lastUnassignAdminPath;

  /// Phase 319 — when `true`, every `DELETE /salons/{s}/masters/{m}/services
  /// /{serviceDefId}` answers HTTP **409** with the plain-English body shape
  /// the real backend sends (`ServiceCatalogService.java:289-297` — no
  /// `data` envelope, no structured count; `HttpServiceRepository
  /// ._mapUnassignException` maps ANY 409 on this path to
  /// [ServiceUnassignBlockedFailure] regardless of body) instead of the
  /// default `204` unassign-success. [_salonMasterServices] is left
  /// UNTOUCHED — nothing was written, so a flow asserting the row survives
  /// after a refusal is asserting something this fake actually enforces, not
  /// merely something it never bothered to remove.
  ///
  /// RE-WIRES ON WRITE — see [rescheduleClientOverlapConflict]'s doc for why
  /// a status change requires re-registering the routes rather than a field
  /// `replyCallback` would read too late (status is captured at registration
  /// time, never per-request).
  bool get unassignServiceBlocked => _unassignServiceBlocked;
  set unassignServiceBlocked(bool value) {
    _unassignServiceBlocked = value;
    _wireSalonMasterServices();
  }

  bool _unassignServiceBlocked = false;

  /// Phase 318 (mobile-qa) — `POST /api/v1/salons/{s}/masters/{m}/services
  /// /bulk`, the SALON-scoped counterpart to [bulkCreateCalls]. GENUINELY
  /// STATEFUL: a successful call APPENDS to [_salonMasterServices], so the
  /// next `GET .../services` (both the salon-scoped list AND the public
  /// `/masters/{id}/services` read the staff profile uses) reflects it.
  int salonBulkCreateCalls = 0;
  List<dynamic>? lastSalonBulkItems;
  String? lastSalonBulkPath;

  /// Phase 322 (mobile-qa) — the SALON_ADMIN own-salon counterpart to
  /// [salonBulkCreateCalls]/[lastSalonBulkItems]/[lastSalonBulkPath], for
  /// `POST /api/v1/salons/salon-admin-1/masters/master-admin-target/services
  /// /bulk`. GENUINELY STATEFUL: appends into [_salonAdminMasterServices].
  int salonAdminBulkCreateCalls = 0;
  List<dynamic>? lastSalonAdminBulkItems;
  String? lastSalonAdminBulkPath;

  /// The salon master's OWN catalogue — deliberately DISJOINT from [_services]
  /// (different names, different ids, different prices), so a screen that
  /// resolved to the ROOT repository and rendered the OPERATOR's own menu is
  /// visibly, assertably wrong rather than indistinguishable.
  final List<Map<String, dynamic>> _salonMasterServices =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'salon-assign-1',
          'masterId': 'master-removable',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 750,
          'priceMax': null,
          'priceDisplay': '750 ₴',
          'effectiveDurationMinutes': 90,
          'serviceDefinition': <String, dynamic>{
            'id': 'salon-def-1',
            'name': 'Нарощення нігтів',
            'description': null,
            'category': 'NAILS',
            'baseDurationMinutes': 90,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 750,
            'priceMax': null,
            'priceDisplay': '750 ₴',
            'photoUrl': null,
          },
        },
        <String, dynamic>{
          'id': 'salon-assign-2',
          'masterId': 'master-removable',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 300,
          'priceMax': null,
          'priceDisplay': '300 ₴',
          'effectiveDurationMinutes': 30,
          'serviceDefinition': <String, dynamic>{
            'id': 'salon-def-2',
            'name': 'Зняття покриття',
            'description': null,
            'category': 'NAILS',
            'baseDurationMinutes': 30,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 300,
            'priceMax': null,
            'priceDisplay': '300 ₴',
            'photoUrl': null,
          },
        },
      ];

  /// Phase 324 (mobile-qa D3) — master A's (`master-aaa`) catalogue on the
  /// SAME salon (`salon-xyz`) as [_salonMasterServices] (master B,
  /// `master-removable`) — deliberately DISJOINT names/ids/prices from BOTH
  /// [_salonMasterServices] and [_services] so a bleed in either direction
  /// (cross-master or cross-role) renders visibly, assertably wrong rather
  /// than a coincidentally-matching list. Read-only fixture (no bulk/
  /// unassign route registered against it) — D3 only needs a second
  /// distinct, real list to navigate to and read back.
  final List<Map<String, dynamic>> _salonMasterAaaServices =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'salon-aaa-assign-1',
          'masterId': 'master-aaa',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 550,
          'priceMax': null,
          'priceDisplay': '550 ₴',
          'effectiveDurationMinutes': 45,
          'serviceDefinition': <String, dynamic>{
            'id': 'salon-aaa-def-1',
            'name': 'Педикюр класичний',
            'description': null,
            'category': 'NAILS',
            'baseDurationMinutes': 45,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 550,
            'priceMax': null,
            'priceDisplay': '550 ₴',
            'photoUrl': null,
          },
        },
        // Phase 317 (mobile-qa) — the CROSS-MASTER VICTIM ROW. This is the one
        // fixture in the file that deliberately BREAKS the disjointness rule
        // above, and it has to: the phase-317 defect is only observable when
        // two masters SHARE a definition. `salon-def-1` is master B's
        // (`master-removable`) first row, so master A resolves against the
        // very same salon-owned definition — at the same 750 ₴ / 90 min, with
        // NO per-master override, which is what makes A susceptible to a
        // definition-level price write.
        //
        // The row's ASSIGNMENT id stays A-specific (`salon-aaa-assign-shared`,
        // never `salon-assign-1`), so the existing cross-bleed assertions in
        // `salon_owner_set_master_services_flow_test.dart` — which are keyed
        // on assignment ids — keep their meaning untouched.
        <String, dynamic>{
          'id': 'salon-aaa-assign-shared',
          'masterId': 'master-aaa',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 750,
          'priceMax': null,
          'priceDisplay': '750 ₴',
          'effectiveDurationMinutes': 90,
          'serviceDefinition': <String, dynamic>{
            'id': 'salon-def-1',
            'name': 'Нарощення нігтів',
            'description': null,
            'category': 'NAILS',
            'baseDurationMinutes': 90,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 750,
            'priceMax': null,
            'priceDisplay': '750 ₴',
            'photoUrl': null,
          },
        },
      ];

  /// Phase 322 (mobile-qa) — the SALON_ADMIN persona's own-salon
  /// counterpart to [_salonMasterServices]: `master-admin-target`'s catalogue
  /// on `salon-admin-1`, the admin's OWN salon (`_adminUserJson.salonId`).
  /// GENUINELY STATEFUL, same reasoning as [_salonMasterServices] — a
  /// successful bulk-create appends, a successful unassign removes. Seeded
  /// with exactly ONE row so the phase-322 flow can unassign a genuinely
  /// PRE-EXISTING row (not merely the one it just added in the same test —
  /// `project_fixture_values_can_defang_assertions`) after also adding a
  /// second one via the FAB.
  final List<Map<String, dynamic>> _salonAdminMasterServices =
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'salon-admin-assign-1',
          'masterId': 'master-admin-target',
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 400,
          'priceMax': null,
          'priceDisplay': '400 ₴',
          'effectiveDurationMinutes': 40,
          'serviceDefinition': <String, dynamic>{
            'id': 'salon-admin-def-1',
            'name': 'Манікюр під наглядом адміністратора',
            'description': null,
            'category': 'NAILS',
            'baseDurationMinutes': 40,
            'bufferMinutesAfter': 0,
            'isActive': true,
            'priceType': 'FIXED',
            'priceMin': 400,
            'priceMax': null,
            'priceDisplay': '400 ₴',
            'photoUrl': null,
          },
        },
      ];

  /// Artificial latency for `DELETE /api/v1/services/{serviceDefId}`.
  ///
  /// Constructor-time (`onRoute` freezes the reply at registration, same
  /// reason [deleteMyAccountFailureStatusCode] is final). `null` (default)
  /// answers immediately, so every existing flow is unchanged.
  ///
  /// Exists for ONE flow: the double-tap re-entrancy guard
  /// (`_ServiceEditScreenState._deleting`, mobile phase 316). That race only
  /// exists WHILE the DELETE is in flight — once the confirmation dialog pops,
  /// the delete icon behind it is hit-testable again but the screen has not
  /// popped yet. With an immediate reply that window is sub-frame and cannot
  /// be driven from a test; the counter increments at DISPATCH time (the
  /// `replyCallback` body runs BEFORE the adapter awaits `delay` —
  /// `dio_adapter.dart:59`), so the delay widens the window without hiding a
  /// second call that did happen.
  final Duration? deleteServiceDelay;

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

  /// Phase 076 (jank audit) — appends [count] extra services to the master's
  /// own list, spread over [categories] round-robin, so a scroll-perf flow can
  /// mount a list well past the default three rows. Additive: nothing calls
  /// this but `integration_test/perf/scroll_jank_test.dart`. Ids are
  /// `assign-bulk-<i>`; call BEFORE the services list first resolves.
  void seedManyServices(
    int count, {
    List<String> categories = const <String>['NAILS', 'FACE', 'HAIR'],
  }) {
    for (int i = 0; i < count; i++) {
      final String category = categories[i % categories.length];
      _services.add(<String, dynamic>{
        'id': 'assign-bulk-$i',
        'masterId': 'user-master-1',
        'isActive': true,
        'priceType': 'FIXED',
        'priceMin': 300 + i,
        'priceMax': null,
        'priceDisplay': '${300 + i} ₴',
        'effectiveDurationMinutes': 45,
        'serviceDefinition': <String, dynamic>{
          'id': 'svc-bulk-$i',
          'name': 'Послуга $i',
          'description': null,
          'category': category,
          'baseDurationMinutes': 45,
          'bufferMinutesAfter': 0,
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 300 + i,
          'priceMax': null,
          'priceDisplay': '${300 + i} ₴',
          'photoUrl': null,
        },
      });
    }
  }

  /// Phase 076 (jank audit) — when non-null, `GET /search/masters` serves
  /// these rows in pages of 20 (real `page` slice, `totalPages` derived)
  /// instead of the two-row default. Set by [seedManySearchMasters].
  List<Map<String, dynamic>>? _searchMastersBulk;

  /// Seeds [count] master search results (see [_searchMastersBulk]).
  void seedManySearchMasters(int count) {
    _searchMastersBulk = <Map<String, dynamic>>[
      for (int i = 0; i < count; i++)
        <String, dynamic>{
          'masterId': 'master-bulk-$i',
          'firstName': 'Майстер',
          'lastName': 'Номер$i',
          'cityLabel': 'Київ',
          'districtLabel': 'Печерський',
          'avgRating': 4.5,
          'reviewCount': 3,
          'avatarUrl': null,
          'minEffectivePrice': 300 + i,
        },
    ];
  }

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

  // ── Media avatar telemetry (Phase 070) ────────────────────────────────────
  /// Number of `POST /api/v1/media/avatar` calls the fake received (counted
  /// even when [mediaAvatarUploadStatus] makes it fail).
  int mediaAvatarUploadCalls = 0;

  /// Phase 367 — the full request URI of every `POST /api/v1/media/avatar`,
  /// so a test can prove the upload names NO target user (no query, no
  /// `userId`): a personal avatar is set only by the person themselves.
  final List<Uri> mediaAvatarUploadUris = <Uri>[];

  /// Phase 367 QA — the multipart part NAMES (text fields AND file parts) of
  /// every `POST /api/v1/media/avatar`, one list per request. A self-avatar
  /// upload carries exactly one part, `file`: any `userId` / `targetUserId`
  /// form field would show up here. A non-multipart body is recorded as
  /// `<non-multipart:Type>` so it can never pass as "only `file`".
  final List<List<String>> mediaAvatarUploadPartNames = <List<String>>[];

  /// Phase 367 QA — the full request URI of every `DELETE /api/v1/media/avatar`
  /// (no query may name a target user).
  final List<Uri> mediaAvatarDeleteUris = <Uri>[];

  /// Phase 367 QA — the request body of every `DELETE /api/v1/media/avatar`
  /// (must be absent: a self-avatar removal names no user).
  final List<Object?> mediaAvatarDeleteBodies = <Object?>[];

  /// Number of `DELETE /api/v1/media/avatar` calls the fake accepted (204).
  int mediaAvatarDeleteCalls = 0;

  /// When non-null, `POST /api/v1/media/avatar` replies with this status and a
  /// bare `{success:false}` body instead of the 200 success envelope — e.g.
  /// 413 (too large), 400 (bad format), 503 (storage off).
  ///
  /// Read at construction time (like [forgotPasswordFailureStatusCode]):
  /// `replyCallback`'s status is fixed when the route is wired from the
  /// constructor, so mutating this after boot is a silent no-op (it was a
  /// mutable field until QA measured exactly that). Pass it to `FakeBackend()`.
  final int? mediaAvatarUploadStatus;

  /// Phase 073 — the avatar URL `GET /masters/me` (and, Phase 367, `GET
  /// /users/me` for every role) currently reports: set by a
  /// successful `POST /media/avatar` (a NEW url per upload, like the real
  /// per-upload R2 key), cleared by `DELETE /media/avatar`. Null until the first
  /// upload, so every pre-existing flow's `/masters/me` body is unchanged.
  String? mediaAvatarUrl;

  /// Successful avatar uploads so far — numbers the fake URLs.
  int _mediaAvatarSeq = 0;

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

  // ── Search suggestions telemetry (Phase 352) ──────────────────────────────
  /// `GET /api/v1/search/suggestions` call count — proves the debounced
  /// provider issues exactly one request per settled `(term, place)` key.
  int searchSuggestionsCalls = 0;

  /// The last `q`, `location.cityId` and `location.districtId` carried on a
  /// `/search/suggestions` request. Null until the first call.
  String? lastSearchSuggestionsQuery;
  String? lastSearchSuggestionsCityId;
  String? lastSearchSuggestionsDistrictId;

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
    // Backend Phase 330: `oblastName` follows the RESOLVED settlement (the
    // oblast half of the saved label), so a seeded `cityId` wins over the
    // hand-set [clientOblastName]; an unseeded/absent city keeps it.
    'oblastName':
        kSeededSettlementOblastNames[clientCityId] ?? clientOblastName,
    'cityId': clientCityId,
    'cityName': clientCityName,
    ...seededSettlementLabelParts(clientCityId),
    if (clientCitySettlementTypeOverride != null)
      'citySettlementType': clientCitySettlementTypeOverride,
    'districtId': clientDistrictId,
    'districtName': clientDistrictName,
    'street': clientStreet,
    'buildingNo': clientBuildingNo,
    'locationNote': clientLocationNote,
  };

  /// The SALON_ADMIN `GET /users/me` body (Phase 356), built from the
  /// mutable [adminFirstName]/[adminLastName]/[adminPhone] state so a PATCH
  /// made through the reused CLIENT Personal/Contacts edit screens
  /// round-trips on the next read — the exact same role [_clientProfileBody]
  /// plays for the CLIENT editors. `professionalTitle`/`salonId` are OUT OF
  /// SCOPE for this phase (D7) and stay the static `_adminUserJson` values.
  Map<String, dynamic> _adminProfileBody() => <String, dynamic>{
    'id': 'user-admin-1',
    'email': 'admin@beautica.ua',
    'role': 'SALON_ADMIN',
    'firstName': adminFirstName,
    'lastName': adminLastName,
    'phoneNumber': adminPhone,
    'professionalTitle': 'Старший адміністратор',
    'salonId': 'salon-admin-1',
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
    // Phase 073 — omitted until an avatar upload set it.
    if (mediaAvatarUrl != null) 'avatarUrl': mediaAvatarUrl,
    // professionalTitle is optional — null is valid (omitted from the
    // ApiResponse.data when the master has not set one). Include only when
    // set so flows that do not exercise this field see a clean seed.
    if (masterProfessionalTitle != null)
      'professionalTitle': masterProfessionalTitle,
    // Address fields (Phase 219/220/221) — same "omit when null" shape as
    // professionalTitle above, so flows that never set these keep seeing the
    // pre-existing location-less seed (no location row on MasterProfileScreen).
    if (masterCity != null) 'city': masterCity,
    if (masterCityId != null) 'cityId': masterCityId,
    // Backend Phase 330 — `region` (from the resolved settlement) and the
    // saved-label parts, derived from [masterCityId] like a salon read. An
    // unseeded/absent id adds nothing, so location-less flows are unchanged.
    if (kSeededSettlementOblastNames[masterCityId] != null)
      'region': kSeededSettlementOblastNames[masterCityId],
    ...seededSettlementLabelParts(masterCityId),
    if (masterDistrictId != null) 'districtId': masterDistrictId,
    if (masterStreet != null) 'street': masterStreet,
    if (masterBuildingNo != null) 'buildingNo': masterBuildingNo,
    if (masterLocationNote != null) 'locationNote': masterLocationNote,
    'avgRating': 4.8,
    'reviewCount': 10,
    'masterType': 'INDEPENDENT_MASTER',
    // Phase 321 — omitted (not merely null) when [masterSalonId] is unset, so
    // every pre-existing flow's body is byte-identical. `cityId`/`oblastId`
    // are non-nullable on the generated `PublicSalonResponse`, so they must
    // be present for the envelope to deserialize at all — placeholder values,
    // never read by `MasterMapper.fromDto` (only `.salon.id` is).
    if (masterSalonId != null)
      'salon': withSeededSalonLocality(<String, dynamic>{
        'id': masterSalonId,
        'name': 'Салон',
        'cityId': 'city-kyiv',
        'oblastId': 'oblast-kyiv',
      }),
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
  ///
  /// The USER-level address `MasterDetailResponse` carries for an
  /// INDEPENDENT_MASTER. Named constants (not inline literals) so a test can
  /// assert against the value the fake actually serves instead of
  /// hard-coding a Cyrillic literal into a `find.text(...)`, which
  /// `scripts/forbid_cyrillic_finder.sh` forbids.
  static const String kPublicMasterCity = 'Київ';
  static const String kPublicMasterStreet = 'вул. Хрещатик';
  static const String kPublicMasterBuildingNo = '12';
  static const String kPublicMasterLocationNote = '2 поверх';

  /// VENUE-ADDRESS SEAM (2026-09-18) — when `true`, the PUBLIC master-detail
  /// envelope OMITS `city`/`street`/`buildingNo`/`locationNote` entirely,
  /// reproducing what the real backend does for a `SALON_MASTER` /
  /// `SALON_OWNER`: `MasterDetailResponse.java:104-127` deliberately nulls a
  /// salon master's USER-level address because "a salon master's precise
  /// address is the salon's business address".
  ///
  /// This is the ONLY fixture shape under which the done screen's `venue*`
  /// override is DISCRIMINATING. With the default (address present) the
  /// `Master` fallback composes «вул. Хрещатик, 12, Київ» — the very same
  /// string the booking carries — so an address assertion would pass
  /// identically with and without the fix. Seed this together with a
  /// DISTINCT [bookingStreet]/[bookingBuildingNo]/[bookingCityLabel] to get a
  /// test that can actually go red.
  ///
  /// Defaults to `false`; every pre-existing flow is untouched.
  bool publicMasterAddressSuppressed = false;

  /// Phase 351 gap-fix (mobile-qa, 2026-09-25) — when `true`, `master-aaa`'s
  /// public detail omits `bio` (wire `null`) instead of the seeded sentence,
  /// so a CLIENT-facing flow can drive the «Про майстра» tab's EMPTY-bio
  /// branch (`public-master-profile-about-empty`) end to end. Defaults to
  /// `false`; every pre-existing flow that expects the seeded bio is
  /// untouched.
  bool publicMasterBioSuppressed = false;

  /// Phase 358 — when `true`, `master-aaa`'s public detail wires
  /// `masterType: 'SALON_MASTER'` instead of the default `INDEPENDENT_MASTER`,
  /// so a CLIENT-facing flow can drive the public-profile «Записатись до
  /// майстра» CTA for a salon-affiliated master end to end (the shelf used to
  /// be independent-only; Phase 358 restored it for every master type — see
  /// `public_master_profile_screen.dart`'s file header). Defaults to `false`;
  /// every pre-existing flow that expects an INDEPENDENT_MASTER is untouched.
  /// Address fields stay wired regardless (unlike the real backend, which
  /// nulls them for a salon master — see [publicMasterAddressSuppressed] for
  /// that seam) because no flow using this flag asserts on the address.
  bool publicMasterTypeSalon = false;

  Map<String, dynamic> _publicMasterDetailEnvelope() => _ok(<String, dynamic>{
    'masterId': 'master-aaa',
    'firstName': 'Софія',
    'lastName': 'Бондар',
    // VENUE-ADDRESS SEAM (2026-09-18) — see [publicMasterAddressSuppressed].
    // Present by default, so every pre-existing flow's body is byte-identical.
    if (!publicMasterAddressSuppressed) ...<String, dynamic>{
      'city': kPublicMasterCity,
      'street': kPublicMasterStreet,
      'buildingNo': kPublicMasterBuildingNo,
      'locationNote': kPublicMasterLocationNote,
    },
    'bio': publicMasterBioSuppressed
        ? null
        : 'Майстриня манікюру з 6-річним досвідом.',
    'instagram': '@sofia_nails',
    'avgRating': publicMasterReviewLanded
        ? kPublicMasterAvgRatingAfterReview
        : kPublicMasterAvgRatingBeforeReview,
    'reviewCount': publicMasterReviewLanded
        ? kPublicMasterReviewCountAfterReview
        : kPublicMasterReviewCountBeforeReview,
    'masterType': publicMasterTypeSalon ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
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
  /// oblastId/districtId/street/buildingNo/locationNote/instagramUrl/
  /// avatarUrl/coverImageUrl/avgRating/reviewCount).
  ///
  /// Carries the Phase 10.6+ taxonomy locality fields
  /// (`cityId`/`oblastId`/`street`/`buildingNo`/`locationNote`) and leaves
  /// the legacy free-text `address` null — the real shape of every salon
  /// created/edited since Phase 10.6 (backend Phase 328 nulls `address` once
  /// a salon has a `street`). `city`/`region` are NOT free text any more:
  /// [withSeededSalonLocality] derives them from `cityId`, exactly as the
  /// backend does since Phase 328 (`f3720365`). Their earlier ABSENCE here is
  /// why no flow caught the empty settlement prefill on the salon address
  /// edit screen. See `salon_mapper_test.dart` for the mapper-level
  /// counterpart and `public_salon_profile_flow_test.dart` for the assertion
  /// that reads the rendered address text.
  ///
  /// RESUME §4 step D (mobile half, 2026-08-30) — `oblastId` used to be
  /// OMITTED here on purpose (see the now-stale "Finding 5" comment this
  /// replaced): `PublicSalonResponse.oblastId` was nullable and several
  /// flows (`salon_edit_forms_flow_test.dart`'s Test 2/3) were deliberately
  /// built around `_prePopulateLocality` bailing out on the missing field
  /// so the cascade opened fully unresolved. `oblastId` is now non-null on
  /// the wire (backend `ec22d91`, `salons.city_id`/`cities.oblast_id` are
  /// both DB-level `NOT NULL`) — omitting it would throw at deserialization,
  /// not just leave the field blank — so it MUST be populated. `oblast-kyiv`
  /// is the real seeded parent of `city-kyiv` (see the `GET /locations/
  /// oblasts/oblast-kyiv/cities` handler below), so `salon-xyz`'s cascade
  /// now pre-populates correctly instead of opening blank; the two dependent
  /// tests' explanatory comments were updated to match (they still function
  /// unchanged — re-selecting an already-resolved oblast/city is a no-op).
  ///
  /// mobile-qa (2026-08-30) — `description`/`phone`/`instagramUrl` now read
  /// the SHARED mutable [salonDescription]/[salonPhone]/[salonInstagramUrl]
  /// state instead of hard-coded literals. `phone` is on this envelope AT ALL
  /// only because the backend gap-fix put `PublicSalonResponse.phone` on the
  /// wire; a fixture that kept omitting it would have made the mobile
  /// gap-fix untestable end to end — every "the phone renders on first load"
  /// assertion would have been satisfiable only by the very PATCH round-trip
  /// the fix exists to make unnecessary. See those fields' own doc.
  Map<String, dynamic> _publicSalonDetailEnvelope() => _ok(
    withSeededSalonLocality(<String, dynamic>{
      'id': 'salon-xyz',
      'name': 'Студія Краси «Камелія»',
      'description': salonDescription,
      'phone': salonPhone,
      // 'city-kyiv' is a real seeded id (see the `GET /locations/oblasts/
      // oblast-kyiv/cities` handler below) — deliberately still a
      // hasDistricts:false city so no existing flow that assumes a leaf
      // (no-district) cascade for salon-xyz changes behaviour.
      'cityId': salonManageCityId,
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'locationNote': salonLocationNote,
      'instagramUrl': salonInstagramUrl,
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
    }),
  );

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
          'avatarUrl': 'https://media.test/avatars/master-aaa.png',
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
          'avatarUrl': 'https://media.test/avatars/master-ccc.png',
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

  /// Phase 21.5 — management-scoped staff roster for `salon-xyz`
  /// (`GET /salons/{salonId}/staff`), backing the owner/admin «Персонал»
  /// grid. One master entry (mirrors `master-aaa`'s public rail identity so
  /// the two reads agree) plus one admin entry — proving the roster now
  /// surfaces admins too, unlike [_salonMasters] above. Shape matches
  /// `SalonStaffMemberResponse`.
  static const List<Map<String, dynamic>> _salonStaff = <Map<String, dynamic>>[
    <String, dynamic>{
      'userId': 'master-aaa',
      'masterId': 'master-aaa',
      'role': 'SALON_MASTER',
      'firstName': 'Софія',
      'lastName': 'Бондар',
      'professionalTitle': null,
      'avatarUrl': 'https://media.test/avatars/master-aaa.png',
      'phoneNumber': '+380671112233',
      'instagram': null,
      'bio': null,
      'avgRating': kPublicMasterAvgRatingBeforeReview,
      'reviewCount': kPublicMasterReviewCountBeforeReview,
      'serviceCount': 1,
    },
    <String, dynamic>{
      'userId': 'admin-zzz',
      'masterId': null,
      'role': 'SALON_ADMIN',
      'firstName': 'Ірина',
      'lastName': 'Ковальська',
      'professionalTitle': null,
      'avatarUrl': null,
      'phoneNumber': '+380509998877',
      'instagram': null,
      // Admins carry no bio BY DESIGN — see `SalonStaffMember`'s own header
      // doc.
      'bio': null,
      'avgRating': null,
      'reviewCount': 0,
      'serviceCount': 0,
    },
    // Phase 307 — a SECOND master, with a `masterId` DELIBERATELY DIFFERENT
    // from its `userId` (unlike `master-aaa`, whose two ids are identical and
    // so cannot catch a userId/masterId swap). The one target of the
    // remove-master flow — `master-aaa` stays untouched as that flow's own
    // CONTROL row.
    <String, dynamic>{
      'userId': 'user-master-removable',
      'masterId': 'master-removable',
      'role': 'SALON_MASTER',
      'firstName': 'Марина',
      'lastName': 'Литвин',
      'professionalTitle': null,
      'avatarUrl': null,
      'phoneNumber': '+380631112233',
      'instagram': null,
      'bio': null,
      'avgRating': null,
      'reviewCount': 0,
      'serviceCount': 0,
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

  /// The catalogue id of the salon's SHARED NAILS service — the row every
  /// salon-wide aggregation assertion is written against.
  static const String kSalonSharedCatalogServiceId = 'salon-svc-shared';

  /// Prices contributed to a catalogue service by roster masters BEYOND the
  /// one the baseline [_salonServiceCategories] fixture already prices.
  ///
  /// Empty in the seeded state, so every existing consumer of
  /// `GET /salons/salon-xyz/services` reads the baseline byte-for-byte. The
  /// salon-scoped bulk-assign handler appends here, which is what models the
  /// backend's locked rule — a salon's catalogue IS the set of services its
  /// active masters perform, priced ACROSS them, so a second master at a
  /// different price turns a single price into a RANGE.
  final Map<String, List<double>> _salonCatalogExtraAssignmentPrices =
      <String, List<double>>{};

  /// The salon catalogue as the server would aggregate it RIGHT NOW.
  ///
  /// Deep-copies the baseline and folds [_salonCatalogExtraAssignmentPrices]
  /// into each affected row's price band. The ONLY observable difference a
  /// re-read can produce is on that band, which is precisely why the «Послуги»
  /// tab's rendered price is a genuine stale-vs-fresh discriminator: nothing
  /// else about the row moves.
  ///
  /// The backend formats the display string itself (single `"500 ₴"` or an
  /// en-dash range `"200–600 ₴"`) and mobile renders it verbatim — mirrored
  /// here, NOT recomputed client-side.
  List<Map<String, dynamic>> _salonServiceCatalogNow() {
    if (_salonCatalogExtraAssignmentPrices.isEmpty) {
      return _salonServiceCategories;
    }
    return <Map<String, dynamic>>[
      for (final Map<String, dynamic> group in _salonServiceCategories)
        <String, dynamic>{
          ...group,
          'services': <Map<String, dynamic>>[
            for (final Map<String, dynamic> svc
                in (group['services'] as List<dynamic>)
                    .cast<Map<String, dynamic>>())
              _aggregatedCatalogService(svc),
          ],
        },
    ];
  }

  Map<String, dynamic> _aggregatedCatalogService(Map<String, dynamic> svc) {
    final List<double> extra =
        _salonCatalogExtraAssignmentPrices[svc['id'] as String] ??
        const <double>[];
    if (extra.isEmpty) return svc;

    double lo = (svc['priceMin'] as num).toDouble();
    double hi = lo;
    for (final double p in extra) {
      if (p < lo) lo = p;
      if (p > hi) hi = p;
    }
    final bool isRange = hi > lo;
    return <String, dynamic>{
      ...svc,
      'priceType': isRange ? 'RANGE' : 'FIXED',
      'priceMin': lo,
      'priceMax': isRange ? hi : null,
      'priceDisplay': isRange ? '${_uah(lo)}–${_uah(hi)} ₴' : '${_uah(lo)} ₴',
    };
  }

  /// Whole-hryvnia rendering — the backend never emits a trailing `.0`.
  static String _uah(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

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

  /// Phase 9.7 — `masterAvatarUrl` of the seeded `booking-1` (detail + list).
  /// `null` (default) keeps every pre-existing flow's wire body unchanged; the
  /// leave-review flow seeds a `media.test` URL to prove the master photo
  /// reaches «Залишити відгук»'s `MasterFeedbackCard`.
  String? bookingMasterAvatarUrl;

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
  ///
  /// ⚠ WHOSE VIEW THE `true` DEFAULT MODELS (Phase 320). The real value is
  /// computed by `BookingService#computeProviderCanReviewClient` (backend
  /// `a0df4cf`), whose provider-authority leg is the SINGLE term
  /// `isPerformingMasterOfBooking(...)`; the former
  /// `|| hasProviderAuthorityOverBooking(...)` disjunct, which admitted the
  /// salon's owner and its assigned admin whoever performed the service, is
  /// gone. The seeded booking's master is `master-aaa`, so the `true` default
  /// is the PERFORMING MASTER's answer — correct for the INDEPENDENT_MASTER
  /// and `SALON_MASTER` personas that drive the review flows, and for an
  /// owner-as-master flow if one is ever written.
  ///
  /// A flow driving a `SALON_OWNER`/`SALON_ADMIN` session that is NOT the
  /// performing master into `GET /bookings/{id}` MUST seed this `false` — the
  /// real server does. Leaving the default would let such a flow pass against
  /// a CTA the real app never renders.
  /// `salon_owner_bookings_board_flow_test.dart` does exactly that.
  bool bookingProviderCanReviewClient = true;

  /// Phase 334 — the CLIENT's review of the master (`{rating, comment?}`,
  /// wire shape of `ClientAuthoredReviewResponse`), served ONLY on
  /// `GET /bookings/{id}` — and on the `PATCH` reschedule reply, which is the
  /// same `BookingDetailResponse` DTO — NEVER on a listing row.
  ///
  /// `null` (the default) means the booking carries no client review and the
  /// `reviewByClient` key is OMITTED from the payload entirely, exactly as the
  /// real backend does — matching the neighbouring optional
  /// `masterAvgRating` / `masterReviewCount` keys, so every pre-334 flow keeps
  /// the byte-identical payload it had.
  ///
  /// LISTING SURFACES DO NOT CARRY IT. `_seededBookingJson` takes
  /// [includeReviewByClient] and `_bookingsPageEnvelope` (the `GET
  /// /bookings/me` rows) leaves it at its `false` default, mirroring the real
  /// backend's unconditional null on every listing; `datasetBookingRow` never
  /// emits the key at all. That asymmetry is the point: `Booking.reviewByClient`
  /// being null on a list means "this surface does not answer that question",
  /// and a fake that answered it there would let a screen reading the review
  /// off a LIST pass a test it must fail.
  Map<String, Object?>? bookingReviewByClient;

  /// When true, `POST /client-reviews` replies HTTP **409** instead of 200 —
  /// feedback about this booking's client already exists (it landed from
  /// another device, or a second submit raced the destination screen's own
  /// pre-gate snapshot). Drives `ClientReviewRepository`'s 409 branch →
  /// `ClientReviewAlreadyExistsFailure` → `LeaveClientFeedbackScreen`'s
  /// `_alreadyReviewed` swap to `_NotReviewable`, which pointedly does NOT pop.
  /// Off by default so every other flow's submit stays a clean 200.
  ///
  /// RE-WIRES ON WRITE — DO NOT COLLAPSE BACK INTO A PLAIN FIELD. See
  /// [createRejectDuplicate]'s doc for the full `DioAdapter.onRoute`
  /// registration-time-status trap: `replyCallback` captures its `statusCode`
  /// when [_wire] runs (from the constructor, where this flag is always still
  /// false) and only `data` stays lazy, so a plain field would change the BODY
  /// and leave the status at 200 — silently un-arming any flow that sets it.
  bool get clientReviewRejectDuplicate => _clientReviewRejectDuplicate;
  set clientReviewRejectDuplicate(bool value) {
    _clientReviewRejectDuplicate = value;
    _wireClientReviews();
  }

  bool _clientReviewRejectDuplicate = false;

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

  /// The last `allowClientOverlap` wire value submitted on
  /// `PATCH /bookings/{id}/reschedule`, decoded on EVERY call regardless of
  /// [rescheduleClientOverlapConflict] — lets a flow prove the override
  /// actually reaches the wire on the confirmed resubmit (booking-conflict
  /// popup track), independent of which status this fake happened to answer.
  bool? lastRescheduleAllowClientOverlap;

  /// When `true`, `PATCH /bookings/{id}/reschedule` answers HTTP **409** with
  /// the typed `CLIENT_BOOKING_CONFLICT` envelope
  /// (`HttpBookingRepository._extractClientBookingConflict`'s exact shape)
  /// instead of the default 200 success — simulating the CLIENT already
  /// having a different overlapping booking. Off by default so every other
  /// reschedule flow keeps its clean 200.
  ///
  /// RE-WIRES ON WRITE — see [createRejectDuplicate]'s doc for why a status
  /// change requires re-registering the route rather than just flipping a
  /// field `replyCallback` would read too late (status is captured at
  /// registration time, never per-request).
  ///
  /// A real backend re-evaluates the conflict per REQUEST based on whether
  /// `allowClientOverlap` was set — this fake cannot do that within one
  /// registration (see [_wireRescheduleBooking]'s doc), so a flow driving the
  /// "confirm the popup, resubmit succeeds" journey must flip this back to
  /// `false` itself between the rejected attempt and the resubmit, exactly as
  /// it would flip [createRejectDuplicate]. [lastRescheduleAllowClientOverlap]
  /// still proves what the RESUBMIT actually sent, independent of that timing.
  bool get rescheduleClientOverlapConflict => _rescheduleClientOverlapConflict;
  set rescheduleClientOverlapConflict(bool value) {
    _rescheduleClientOverlapConflict = value;
    _wireRescheduleBooking();
  }

  bool _rescheduleClientOverlapConflict = false;

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

  /// The COMPLETE twin of [declineChild] — flips ONLY the tapped child's
  /// status to COMPLETED, keyed on [bookingId] (2026-08-17 CRITICAL fix).
  ///
  /// Complete was the LAST provider transition still routed through the
  /// whole-visit `PATCH /appointments/{id}/complete`, which closed every child
  /// of the visit in lockstep AND evaluated its temporal guard against the
  /// VISIT's `startsAt` (the first service) — so completing one archive row
  /// silently completed siblings whose own start had not arrived. Now that
  /// `completeAppointmentService` passes THIS child's own id, completing
  /// `booking-1` must leave `booking-2` CONFIRMED; this method is what makes
  /// that sibling assertion real rather than self-referential.
  void completeChild(String bookingId) {
    if (bookingId == 'booking-2') {
      siblingBookingStatus = 'COMPLETED';
    } else {
      bookingStatus = 'COMPLETED';
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

  /// Phase 248 — `POST /api/v1/masters/{masterId}/bookings` call count (the
  /// INDEPENDENT_MASTER walk-in «Новий запис» wizard's own submit,
  /// `BookingRepository.createMasterBooking`, backend 22.4
  /// `StaffBookingsApi.createStaffBooking`). Distinct from every other create
  /// counter in this file — this endpoint is provider-scoped, not the CLIENT
  /// `POST /bookings` write.
  int createStaffBookingCalls = 0;

  /// The most recent walk-in submit's decoded JSON body — `masterServiceId` /
  /// `startsAt` / `guest.{name,surname,phone}` — so a flow can assert exactly
  /// what went on the wire without re-deriving it from UI state.
  Map<String, dynamic>? lastStaffBookingRequestBody;

  /// `GET /api/v1/bookings/$kWalkInBookingId` call count.
  ///
  /// STALE as a description of [BookingRepository.createMasterBooking] as of
  /// Phase 256 (mobile-qa audit) — that method no longer makes a follow-up
  /// GET at all: since the response widened to the full
  /// `AppointmentDetailResponse` (`items[]`, totals, a real `endAt`), the
  /// POST's own response body is parsed directly via `AppointmentMapper
  /// .fromDto` and returned. This counter and its route (below) are dead
  /// for THAT call path today; the route itself is harmless to keep — other
  /// booking-detail fetches for [kWalkInBookingId] may still hit it — but a
  /// zero count here no longer signals anything about `createMasterBooking`.
  int getWalkInBookingDetailCalls = 0;

  /// The row [kWalkInBookingId]'s POST handler most recently built — served
  /// back by the `GET /api/v1/bookings/$kWalkInBookingId` route above so the
  /// detail follow-up sees the SAME booking it just created, not a stale
  /// placeholder.
  Map<String, dynamic>? _lastWalkInBookingRow;

  /// When non-null, `GET /api/v1/bookings/booking-1` replies with THIS HTTP
  /// status (and a plain error envelope) instead of `200` + the seeded booking.
  ///
  /// The single-booking fetch is the one round trip several screens PRE-GATE on
  /// — `BookingDetailScreen` and `LeaveClientFeedbackScreen` both render their
  /// whole body out of `bookingDetailProvider(id)` — and until this knob existed
  /// NO flow could reach either screen's `error:` branch, so their retry
  /// affordances were E2E-unreachable (mobile-qa INFO, 2026-08-17 cycle 1;
  /// closed cycle 2). [getBookingDetailCalls] still increments on a failing
  /// reply, so a flow can prove a manual «Повторити» genuinely RE-ISSUES the
  /// request rather than merely rebuilding.
  ///
  /// PREFER `404`. `beauticaProviderRetry` (`core/errors/failure_retry_policy.dart`)
  /// classifies the resulting [NotFoundFailure] as DETERMINISTIC, so the element
  /// settles into `AsyncError` on the FIRST attempt and the error UI renders at
  /// once. A `5xx` maps to a transient `ServerFailure` and is fed into Riverpod's
  /// default backoff curve instead — ~10 attempts over ~38 s, parked in
  /// `AsyncLoading` the whole time, which no bounded `AppHarness.settle` can
  /// outwait (and which would make [getBookingDetailCalls] non-deterministic).
  /// Use `5xx` here only with `AppHarness.boot(..., retry: (_, _) => null)`.
  ///
  /// RE-WIRES ON WRITE — DO NOT COLLAPSE BACK INTO A PLAIN FIELD. Identical
  /// `DioAdapter.onRoute` trap to [clientReviewRejectDuplicate] /
  /// [createRejectDuplicate]: `replyCallback` captures its `statusCode` when
  /// [_wire] runs (from the constructor, where this is always still null) and
  /// keeps only `data` lazy, so a plain field would swap the BODY and silently
  /// leave the status at 200 — the flow would then see a deserialization
  /// failure, or nothing at all, instead of the error branch it asked for.
  int? get bookingDetailFailStatus => _bookingDetailFailStatus;
  set bookingDetailFailStatus(int? value) {
    _bookingDetailFailStatus = value;
    _wireBookingDetail();
  }

  int? _bookingDetailFailStatus;

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

  /// VENUE ADDRESS (2026-09-18) — the seeded booking's OWN address, i.e. the
  /// place the visit happens, as `BookingDetailResponse.java:580-648` resolves
  /// it server-side (the SALON's business address for a salon master, the
  /// master's own for an independent one).
  ///
  /// Defaults are byte-for-byte the literals `_seededBookingJson` used to
  /// hard-code, so every pre-existing flow sees the identical wire body.
  ///
  /// ⚠ A test that means to PROVE the done screen's `venue*` override is
  /// load-bearing must seed these to something DIFFERENT from the public
  /// master's own address AND set [publicMasterAddressSuppressed] — otherwise
  /// the `Master` fallback composes the very same string and the assertion is
  /// vacuous in both directions. [kSalonVenueStreet] and friends below are
  /// the ready-made distinct salon address for exactly that.
  String bookingStreet = kPublicMasterStreet;
  String bookingBuildingNo = kPublicMasterBuildingNo;
  String bookingCityLabel = kPublicMasterCity;
  String? bookingLocationNote;

  /// A SALON business address, deliberately distinct from
  /// [kPublicMasterStreet] / [kPublicMasterBuildingNo] in every part, so a
  /// rendered assertion against it can only pass when the value came off the
  /// `Booking` and not off the `Master`. Borrowed from the sibling-salon
  /// fixture's own «вул. Спаська, 5», so the address is one this fake already
  /// treats as a real salon's.
  static const String kSalonVenueStreet = 'вул. Спаська';
  static const String kSalonVenueBuildingNo = '5';
  static const String kSalonVenueCity = 'Київ';
  static const String kSalonVenueLocationNote = 'вхід з двору';

  /// The enriched `BookingDetailResponse` body for the seeded booking, built
  /// from the CURRENT mutable status/note so a post-cancel re-fetch reflects
  /// the new state. Wire keys mirror the DTO the [BookingMapper] reads.
  ///
  /// [includeReviewByClient] is the DETAIL-ONLY switch for phase 334's
  /// `reviewByClient` key — see [bookingReviewByClient] for why a listing must
  /// never carry it. Callers serving a `BookingDetailResponse` pass `true`;
  /// `_bookingsPageEnvelope` keeps the `false` default.
  Map<String, dynamic> _seededBookingJson({
    bool includeReviewByClient = false,
  }) => <String, dynamic>{
    'id': 'booking-1',
    'masterId': 'master-aaa',
    'masterFirstName': 'Софія',
    'masterLastName': 'Бондар',
    'masterAvatarUrl': bookingMasterAvatarUrl,
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
    'categoryName': 'NAIL_SERVICE',
    // VENUE ADDRESS (2026-09-18) — the address the BACKEND already resolved
    // salon-vs-independent server-side (`BookingDetailResponse.java:580-648`),
    // i.e. the place the visit actually happens. Seam-backed so a flow can
    // make it DIFFER from the master's USER-level address — see
    // [bookingStreet]. Defaults reproduce the pre-seam literals exactly.
    'cityLabel': bookingCityLabel,
    'districtLabel': 'Печерський',
    'street': bookingStreet,
    'buildingNo': bookingBuildingNo,
    'durationMinutesAtBooking': 90,
    'priceAtBooking': bookingPrice,
    'priceMaxAtBooking': bookingPriceMax,
    'startsAt': bookingStartsAt,
    'endsAt': bookingEndsAt,
    'status': bookingStatus,
    'canReview': bookingCanReview,
    'providerCanReviewClient': bookingProviderCanReviewClient,
    // Phase 334. Emitted ONLY on a detail payload AND only when seeded, so the
    // default keeps the pre-334 shape (key absent entirely) — same idiom as
    // `masterAvgRating` below.
    if (includeReviewByClient && bookingReviewByClient != null)
      'reviewByClient': bookingReviewByClient,
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
    'locationNote': bookingLocationNote,
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
    'categoryName': 'NAIL_SERVICE',
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
  ///
  /// [providerCanReviewClient] models the REAL per-row value the backend now
  /// computes on the provider rows of `GET /bookings/me` (backend
  /// `fix/list-provider-can-review-client`, 2026-08-17). It used to be omitted
  /// from this row entirely — matching the backend's then-hardcoded `false` —
  /// which is why `MasterBookingCard.onReview` could not be gated on it. It
  /// defaults to `false` (an already-reviewed or not-yet-eligible row), so a
  /// flow that wants the archive's «Відгук» CTA must opt in per row. Note this
  /// is INDEPENDENT of [bookingProviderCanReviewClient], which is what
  /// `GET /bookings/{id}` returns — seeding them differently is how a flow
  /// exercises the stale-list-vs-fresh-detail race the destination screen's
  /// pre-gate exists for.
  Map<String, dynamic> datasetBookingRow({
    required String id,
    required String status,
    required DateTime startsAt,
    Duration duration = const Duration(minutes: 60),
    bool providerCanReviewClient = false,
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
    'categoryName': 'NAIL_SERVICE',
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
    'providerCanReviewClient': providerCanReviewClient,
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

  /// The inclusive `[from, to]` LOCAL-DAY window a `/bookings/me` request
  /// carried, as a date token (`YYYY-MM-DD` → host-local midnight, directly
  /// comparable to [kyivDayOf]'s output — see `kyiv_day.dart`'s header on date
  /// tokens). `null` when the param is absent; both are independently optional
  /// on the real endpoint (`BookingRepository.getMyBookings`'s doc).
  ///
  /// Tolerates a full ISO instant as well as a bare date by taking the first
  /// 10 characters: the repository sends `toApiDate(...)`, but a caller that
  /// ever sent an instant must not blow up the fake's route callback (the same
  /// defensive posture [_scalarQueryParam] exists for).
  static DateTime? _dayWindowBound(Map<String, dynamic> query, String key) {
    final String? raw = _scalarQueryParam(query, key);
    if (raw == null || raw.length < 10) return null;
    return DateTime.tryParse(raw.substring(0, 10));
  }

  /// Whether dataset [row]'s `startsAt` falls inside the inclusive Kyiv-day
  /// window `[from, to]` — the fake half of the real endpoint's day filter.
  ///
  /// WHY THIS EXISTS (2026-08-17, unbounded-hang fix)
  /// ------------------------------------------------
  /// [_slicedBookingsPageEnvelope] used to filter by `partition`/`status`
  /// ONLY and silently ignore `from`/`to`, so a day-scoped request
  /// (`from=today&to=today` — what `bookingsDayProvider` sends for the
  /// master's «Мої записи» timeline) was handed the WHOLE dataset. That is not
  /// a harmless over-return: the fake was strictly WEAKER than the real
  /// backend, so it could both mask a bug (a screen that mishandles the day
  /// window looks fine) and manufacture one (a far-past fixture row reaching a
  /// single-day timeline made `BookingsTimelineGrid` try to build ~56 500 hour
  /// rows, starving the Dart event loop and hanging
  /// `master_archive_flow_test.dart` scenario 2 with no timer-based deadline
  /// able to fire). A fake that answers a narrower question than it was asked
  /// is a divergence, full stop — do not relax this to keep a flow green;
  /// fix the flow's fixture dates instead.
  ///
  /// The comparison is by KYIV DAY, not by raw instant, because the real
  /// endpoint's `from`/`to` are LOCAL calendar days (`toApiDate`), so a
  /// 21:00 UTC row on the previous UTC day is still "today" in Kyiv.
  static bool _withinDayWindow(
    Map<String, dynamic> row,
    DateTime? from,
    DateTime? to,
  ) {
    if (from == null && to == null) return true;
    final DateTime day = kyivDayOf(DateTime.parse(row['startsAt'] as String));
    if (from != null && day.isBefore(from)) return false;
    if (to != null && day.isAfter(to)) return false;
    return true;
  }

  /// The real (day window, statuses, sort, page) slice over
  /// [_bookingsDataset] — see the section doc above. Filters the WHOLE dataset
  /// by the inclusive `[from, to]` local-day window ([_withinDayWindow]) AND
  /// by the repeated `status`
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
    // The inclusive local-day window, honoured BEFORE partition/status —
    // exactly like the real endpoint. See [_withinDayWindow]'s doc for why
    // ignoring it (as this did until 2026-08-17) is a genuine divergence and
    // not a harmless over-return.
    final DateTime? fromDay = _dayWindowBound(query, 'from');
    final DateTime? toDay = _dayWindowBound(query, 'to');

    final List<Map<String, dynamic>> filtered =
        dataset
            .where(
              (Map<String, dynamic> b) =>
                  _withinDayWindow(b, fromDay, toDay) &&
                  (partition != null
                      ? _matchesPartition(b, partition, now)
                      : (statuses == null || statuses.contains(b['status']))),
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

  /// Wires the two Phase 317 SALON-TARGET service endpoints for the
  /// `salon-xyz` / `master-removable` pair. See [getSalonMasterServicesCalls].
  void _wireSalonMasterServices() {
    const String base =
        '/api/v1/salons/salon-xyz/masters/master-removable/services';

    _adapter.onRoute(
      base,
      (server) => server.replyCallback(200, (_) {
        getSalonMasterServicesCalls++;
        lastSalonMasterServicesPath = base;
        return _okList(
          salonMasterOwnServicesEmpty
              ? <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.from(
                  _salonMasterServices.map(Map<String, dynamic>.from),
                ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // One DELETE route per SEEDED definition id — an unassign for an id that
    // was never seeded fails loudly as an unmatched route instead of silently
    // counting (the same rule the `DELETE /api/v1/services/{defId}` loop
    // follows). Note the path is keyed on the DEFINITION id, never the
    // assignment id: `service_edit_screen.dart` passes `service.serviceDefId`,
    // and the fixture gives the two rows DIFFERENT values for those.
    for (final Map<String, dynamic> svc in _salonMasterServices) {
      final String defId =
          (svc['serviceDefinition'] as Map<String, dynamic>?)?['id']
              as String? ??
          '';
      if (defId.isEmpty) continue;
      final String path = '$base/$defId';
      _adapter.onRoute(
        path,
        (server) =>
            server.replyCallback(_unassignServiceBlocked ? 409 : 204, (_) {
              unassignServiceCalls++;
              lastUnassignedServiceDefId = defId;
              lastUnassignPath = path;
              if (_unassignServiceBlocked) {
                // Plain-English body, no `data` envelope — the real backend's
                // exact shape (see [unassignServiceBlocked]'s doc). The row is
                // deliberately NOT removed: nothing was written.
                return <String, dynamic>{
                  'success': false,
                  'message':
                      'Master has 2 future confirmed booking(s) for this '
                      'service.',
                };
              }
              _salonMasterServices.removeWhere(
                (Map<String, dynamic> s) =>
                    (s['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
                    defId,
              );
              return null;
            }),
        request: const Request(method: RequestMethods.delete),
      );

      // Phase 317 — PATCH on the SAME path: the PER-MASTER BAND write, the
      // endpoint a salon-master price/duration edit must land on. Registered
      // per SEEDED definition id for the same reason the DELETE above is: a
      // band PATCH for an id that was never seeded fails loudly as an
      // unmatched route instead of silently counting.
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(200, (req) {
          updateMasterBandCalls++;
          lastBandPatchPath = path;
          lastBandPatchedServiceDefId = defId;
          final Map<String, dynamic> body = _decodeBody(req.data);
          lastBandPatchBody = body;
          return _ok(_applySalonBand('master-removable', defId, body));
        }),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
    }
  }

  /// Phase 317 — applies a PER-MASTER band PATCH body to ONE master's row and
  /// records the override.
  ///
  /// READS ONLY THE BAND ENDPOINT'S OWN WIRE NAMES, deliberately: `price` is
  /// the FLOOR in BOTH modes here (there is no `priceMin` key) and the
  /// duration is `durationOverrideMinutes` (never `baseDurationMinutes`).
  /// Also accepting the definition endpoint's spellings would DEFANG every
  /// phase-317 assertion at once — a repository that transcribed the wrong
  /// mapper would still appear to work against this fake.
  ///
  /// Returns the updated row (a MasterServiceResponse-shaped map), which is
  /// what the real endpoint answers with.
  Map<String, dynamic> _applySalonBand(
    String masterId,
    String serviceDefId,
    Map<String, dynamic> body,
  ) {
    _salonBandOverrides.add('$masterId|$serviceDefId');
    for (final Map<String, dynamic> row in _allSalonRows) {
      if (row['masterId'] != masterId) continue;
      if ((row['serviceDefinition'] as Map<String, dynamic>?)?['id'] !=
          serviceDefId) {
        continue;
      }
      final Object? priceType = body['priceType'];
      if (priceType != null) {
        row['priceType'] = priceType;
        row['priceMin'] = body['price'];
        // Absent for FIXED — write the null through so a FIXED band genuinely
        // CLEARS a previous ceiling instead of leaving a stale one.
        row['priceMax'] = body['priceMax'];
        row['priceDisplay'] = _priceDisplay(
          body['price'] as num?,
          body['priceMax'] as num?,
        );
      }
      final Object? duration = body['durationOverrideMinutes'];
      if (duration != null) row['effectiveDurationMinutes'] = duration;
      return Map<String, dynamic>.from(row);
    }
    // No such row: answer the shape anyway so the failure surfaces as a test
    // assertion rather than a deserialization crash.
    return <String, dynamic>{
      'id': 'unknown-assignment',
      'masterId': masterId,
      'isActive': true,
      'priceType': body['priceType'] ?? 'FIXED',
      'priceMin': body['price'] ?? 0,
      'priceMax': body['priceMax'],
      'priceDisplay': _priceDisplay(
        body['price'] as num?,
        body['priceMax'] as num?,
      ),
      'effectiveDurationMinutes': body['durationOverrideMinutes'] ?? 60,
      'serviceDefinition': <String, dynamic>{
        'id': serviceDefId,
        'name': 'Unknown',
        'category': 'NAILS',
        'baseDurationMinutes': 60,
        'isActive': true,
        'priceType': 'FIXED',
        'priceMin': 0,
        'priceMax': null,
        'priceDisplay': '0 ₴',
      },
    };
  }

  /// Phase 317 — `PATCH /api/v1/services/{serviceDefId}` for the SALON-OWNED
  /// definitions, the SHARED row several masters resolve against.
  ///
  /// The split write sends an IDENTITY-ONLY body here, so the route existing
  /// is not itself the assertion — [patchSharedDefinitionPricedCalls] is. The
  /// cascade in [_applySharedDefinitionPatch] is what turns a price on this
  /// body into a VISIBLE change on another master's screen, which is the harm
  /// the phase-317 flow asserts against.
  void _wireSalonSharedDefinitions() {
    final Set<String> defIds = <String>{
      for (final Map<String, dynamic> row in _allSalonRows)
        (row['serviceDefinition'] as Map<String, dynamic>?)?['id'] as String? ??
            '',
    }..removeWhere((String id) => id.isEmpty);

    for (final String defId in defIds) {
      _adapter.onRoute(
        '/api/v1/services/$defId',
        (server) => server.replyCallback(200, (req) {
          patchSharedDefinitionCalls++;
          final Map<String, dynamic> body = _decodeBody(req.data);
          lastSharedDefinitionPatchBody = body;
          // EVERY spelling either endpoint uses for money or time. A
          // regression that picked the other name must still be counted, or
          // the "priced writes stayed at zero" assertion would be satisfied
          // by the very bug it exists to catch.
          const List<String> moneyOrTime = <String>[
            'price',
            'priceMin',
            'priceMax',
            'priceType',
            'baseDurationMinutes',
            'durationMinutes',
            'durationOverrideMinutes',
          ];
          final bool priced = moneyOrTime.any(body.containsKey);
          if (priced) patchSharedDefinitionPricedCalls++;
          return _ok(_applySharedDefinitionPatch(defId, body, priced: priced));
        }),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
    }
  }

  /// Applies a SHARED-definition PATCH and cascades it, modelling the backend:
  /// a definition-level price/duration change re-prices and re-times every
  /// master resolving against that definition who has NO per-master override.
  ///
  /// This cascade is the point of the whole fixture. Without it a flow could
  /// only assert which endpoint was called; with it, the other master's
  /// rendered price actually moves when the bug is present.
  Map<String, dynamic> _applySharedDefinitionPatch(
    String serviceDefId,
    Map<String, dynamic> body, {
    required bool priced,
  }) {
    Map<String, dynamic>? touched;
    for (final Map<String, dynamic> row in _allSalonRows) {
      final Map<String, dynamic>? def =
          row['serviceDefinition'] as Map<String, dynamic>?;
      if (def == null || def['id'] != serviceDefId) continue;

      if (body['name'] != null) def['name'] = body['name'];
      if (body['category'] != null) def['category'] = body['category'];
      if (body['serviceTypeId'] != null) {
        def['serviceTypeId'] = body['serviceTypeId'];
      }
      // The definition endpoint's own spellings: floor `priceMin` (RANGE) or
      // `price` (FIXED), duration `baseDurationMinutes`.
      final num? floor = (body['priceMin'] ?? body['price']) as num?;
      final num? ceiling = body['priceMax'] as num?;
      final Object? baseDuration = body['baseDurationMinutes'];
      if (body['priceType'] != null) {
        def['priceType'] = body['priceType'];
        def['priceMin'] = floor;
        def['priceMax'] = ceiling;
        def['priceDisplay'] = _priceDisplay(floor, ceiling);
      }
      if (baseDuration != null) def['baseDurationMinutes'] = baseDuration;

      // THE CASCADE. A master with a per-master override keeps their own
      // band; everyone else inherits the shared one — which is precisely how
      // one master's edit used to re-price the whole salon.
      final bool overridden = _salonBandOverrides.contains(
        '${row['masterId']}|$serviceDefId',
      );
      if (priced && !overridden) {
        if (body['priceType'] != null) {
          row['priceType'] = body['priceType'];
          row['priceMin'] = floor;
          row['priceMax'] = ceiling;
          row['priceDisplay'] = _priceDisplay(floor, ceiling);
        }
        if (baseDuration != null) {
          row['effectiveDurationMinutes'] = baseDuration;
        }
      }
      touched ??= def;
    }
    return touched ??
        <String, dynamic>{
          'id': serviceDefId,
          'name': body['name'] ?? 'Unknown',
          'category': body['category'] ?? 'NAILS',
          'baseDurationMinutes': body['baseDurationMinutes'] ?? 60,
          'isActive': true,
          'priceType': body['priceType'] ?? 'FIXED',
          'priceMin': (body['priceMin'] ?? body['price']) ?? 0,
          'priceMax': body['priceMax'],
          'priceDisplay': '0 ₴',
        };
  }

  /// The server-formatted price label the real backend returns. Whole amounts
  /// render without a decimal tail, matching the seeded fixtures ('750 ₴').
  static String _priceDisplay(num? floor, num? ceiling) {
    if (floor == null) return '';
    String fmt(num v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toString();
    return ceiling == null
        ? '${fmt(floor)} ₴'
        : '${fmt(floor)}–${fmt(ceiling)} ₴';
  }

  /// Phase 324 (mobile-qa D3) — the cross-role-bleed control route: `GET
  /// /api/v1/salons/salon-xyz/masters/master-aaa/services`. Read-only (no
  /// bulk/unassign registered) — see [getSalonMasterAaaServicesCalls]'s doc.
  void _wireSalonMasterAaaServices() {
    const String base = '/api/v1/salons/salon-xyz/masters/master-aaa/services';

    _adapter.onRoute(
      base,
      (server) => server.replyCallback(200, (_) {
        getSalonMasterAaaServicesCalls++;
        lastSalonMasterAaaServicesPath = base;
        return _okList(
          salonMasterAaaServicesEmpty
              ? <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.from(
                  _salonMasterAaaServices.map(Map<String, dynamic>.from),
                ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// Phase 318 (mobile-qa) — `POST /api/v1/salons/salon-xyz/masters/
  /// master-removable/services/bulk`, the SALON-scoped counterpart to
  /// [_wireBulkCreateServices]. Mirrors that method's success shape (echo one
  /// created service per submitted item) but APPENDS into
  /// [_salonMasterServices] instead of the independent master's [_services] —
  /// this is the ONE thing that makes the phase-318 FAB→setup→submit flow's
  /// "new service appears in the list" and "the stat tile count increased on
  /// return" assertions genuine rather than reading a fixture that never
  /// changed. No rejection outcomes are wired (unlike
  /// [_wireBulkCreateServices]) — nothing in this repo's test suite yet drives
  /// a validation/duplicate failure through the salon-scoped path.
  void _wireSalonMasterServicesBulk() {
    const String path =
        '/api/v1/salons/salon-xyz/masters/master-removable/services/bulk';
    _adapter.onRoute(
      path,
      (server) => server.replyCallback(200, (req) {
        salonBulkCreateCalls++;
        lastSalonBulkPath = path;
        final body = _decodeBody(req.data);
        final items = (body['items'] as List<dynamic>?) ?? const <dynamic>[];
        lastSalonBulkItems = items;

        final created = <Map<String, dynamic>>[];
        for (final item in items) {
          final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
          final defId = 'salon-def-bulk-$_nextSalonServiceSeq';
          final row = <String, dynamic>{
            'id': 'salon-assign-bulk-$_nextSalonServiceSeq',
            'masterId': 'master-removable',
            'isActive': true,
            'priceType': map['priceType'] ?? 'FIXED',
            'priceMin': map['price'] ?? map['priceMin'] ?? 0,
            'priceMax': map['priceMax'],
            'priceDisplay': '${map['price'] ?? map['priceMin'] ?? 0} ₴',
            'effectiveDurationMinutes': map['durationMinutes'] ?? 60,
            'serviceDefinition': <String, dynamic>{
              'id': defId,
              'name': 'Salon bulk service $_nextSalonServiceSeq',
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
          };
          _salonMasterServices.add(row);
          created.add(row);
          _nextSalonServiceSeq++;

          // SALON-WIDE AGGREGATION (2026-09-14). A salon-scoped assignment is
          // a second master taking on one of the SALON's services, so the
          // salon catalogue's own row for it re-prices across the masters who
          // now perform it — see [_salonCatalogExtraAssignmentPrices]. Modelled
          // against the shared NAILS row because that is the one the baseline
          // fixture already prices (400 ₴) and the one the «Послуги» tab
          // assertions name. Recorded HERE, at the write, so the catalogue
          // change is causally tied to the operator's action rather than to a
          // test-only knob a passing test could set without doing anything.
          final num? assigned = (map['price'] ?? map['priceMin']) as num?;
          if (assigned != null) {
            _salonCatalogExtraAssignmentPrices
                .putIfAbsent(kSalonSharedCatalogServiceId, () => <double>[])
                .add(assigned.toDouble());
          }
        }
        return _okList(created);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  /// Phase 322 (mobile-qa) — the SALON_ADMIN own-salon counterpart to
  /// [_wireSalonMasterServices], for the `salon-admin-1` / `master-admin-target`
  /// pair. Proves the exact SAME salon-target GET/DELETE wire an owner hits
  /// (`_wireSalonMasterServices`'s own doc) also fires for a SALON_ADMIN of
  /// that salon — a role-only gate would coincidentally still hit ONE of
  /// these two salon/master pairs, so the two are kept fully separate
  /// (different counters, different fixture list) rather than parameterised
  /// over a shared one.
  void _wireSalonAdminMasterServices() {
    const String base =
        '/api/v1/salons/salon-admin-1/masters/master-admin-target/services';

    _adapter.onRoute(
      base,
      (server) => server.replyCallback(200, (_) {
        getSalonAdminMasterServicesCalls++;
        lastSalonAdminMasterServicesPath = base;
        return _okList(
          List<Map<String, dynamic>>.from(
            _salonAdminMasterServices.map(Map<String, dynamic>.from),
          ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // One DELETE route per SEEDED definition id — same rule
    // [_wireSalonMasterServices] follows, for the same reason.
    for (final Map<String, dynamic> svc in _salonAdminMasterServices) {
      final String defId =
          (svc['serviceDefinition'] as Map<String, dynamic>?)?['id']
              as String? ??
          '';
      if (defId.isEmpty) continue;
      final String path = '$base/$defId';
      _adapter.onRoute(
        path,
        (server) => server.replyCallback(204, (_) {
          unassignAdminServiceCalls++;
          lastUnassignedAdminServiceDefId = defId;
          lastUnassignAdminPath = path;
          _salonAdminMasterServices.removeWhere(
            (Map<String, dynamic> s) =>
                (s['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
                defId,
          );
          return null;
        }),
        request: const Request(method: RequestMethods.delete),
      );
    }
  }

  /// Phase 322 (mobile-qa) — `POST /api/v1/salons/salon-admin-1/masters/
  /// master-admin-target/services/bulk`, the SALON_ADMIN own-salon
  /// counterpart to [_wireSalonMasterServicesBulk]. Same mirrored shape,
  /// APPENDS into [_salonAdminMasterServices] instead.
  void _wireSalonAdminMasterServicesBulk() {
    const String path =
        '/api/v1/salons/salon-admin-1/masters/master-admin-target/services'
        '/bulk';
    _adapter.onRoute(
      path,
      (server) => server.replyCallback(200, (req) {
        salonAdminBulkCreateCalls++;
        lastSalonAdminBulkPath = path;
        final body = _decodeBody(req.data);
        final items = (body['items'] as List<dynamic>?) ?? const <dynamic>[];
        lastSalonAdminBulkItems = items;

        final created = <Map<String, dynamic>>[];
        for (final item in items) {
          final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
          final defId = 'salon-admin-def-bulk-$_nextSalonAdminServiceSeq';
          final row = <String, dynamic>{
            'id': 'salon-admin-assign-bulk-$_nextSalonAdminServiceSeq',
            'masterId': 'master-admin-target',
            'isActive': true,
            'priceType': map['priceType'] ?? 'FIXED',
            'priceMin': map['price'] ?? map['priceMin'] ?? 0,
            'priceMax': map['priceMax'],
            'priceDisplay': '${map['price'] ?? map['priceMin'] ?? 0} ₴',
            'effectiveDurationMinutes': map['durationMinutes'] ?? 60,
            'serviceDefinition': <String, dynamic>{
              'id': defId,
              'name': 'Salon admin bulk service $_nextSalonAdminServiceSeq',
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
          };
          _salonAdminMasterServices.add(row);
          created.add(row);
          _nextSalonAdminServiceSeq++;
        }
        return _okList(created);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

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

  /// (Re-)registers `PATCH /api/v1/bookings/booking-1/reschedule` — client
  /// reschedule (track 24.x auto-confirm). Status is chosen by
  /// [rescheduleClientOverlapConflict] (that field's doc explains why a
  /// status-dependent route must be re-registered by a `_wireX` method
  /// rather than inlined in [_wire] — see [_wireCreateService]'s doc for the
  /// full `DioAdapter.onRoute` mechanics).
  ///
  ///   - `false` (default) — moves the seeded booking to the submitted
  ///     `newStartsAt`, keeps it CONFIRMED (a reschedule never changes
  ///     status), and returns the enriched `BookingDetailResponse` the
  ///     repository maps back (unlike cancel, which is void). The 90-minute
  ///     span is preserved so the moved booking's end tracks its new start.
  ///   - `true` — answers HTTP 409 with the exact `CLIENT_BOOKING_CONFLICT`
  ///     envelope `HttpBookingRepository._extractClientBookingConflict`
  ///     decodes, simulating the CLIENT already holding a different
  ///     overlapping booking.
  ///
  /// [lastRescheduleAllowClientOverlap] is decoded from the body on EVERY
  /// call, both branches — see that field's doc for why.
  void _wireRescheduleBooking() {
    _adapter.onRoute(
      '/api/v1/bookings/booking-1/reschedule',
      (server) => server.replyCallback(
        _rescheduleClientOverlapConflict ? 409 : 200,
        (req) {
          rescheduleBookingCalls++;
          final body = _decodeBody(req.data);
          final String? newStartsAt = body['newStartsAt'] as String?;
          lastRescheduleNewStartsAt = newStartsAt;
          lastRescheduleAllowClientOverlap =
              body['allowClientOverlap'] as bool?;
          if (_rescheduleClientOverlapConflict) {
            return <String, dynamic>{
              'success': false,
              'data': <String, dynamic>{
                'code': 'CLIENT_BOOKING_CONFLICT',
                'conflictingBookingId': 'booking-existing',
                'serviceName': 'Стрижка',
                'masterName': 'Ірина Бондар',
                'startsAt': bookingStartsAt,
                'endsAt': bookingEndsAt,
              },
              'message': 'Client already has an overlapping booking',
            };
          }
          if (newStartsAt != null) {
            final DateTime start = DateTime.parse(newStartsAt).toUtc();
            final DateTime end = start.add(const Duration(minutes: 90));
            bookingStartsAt = start.toIso8601String();
            bookingEndsAt = end.toIso8601String();
          }
          // A reschedule leaves the booking CONFIRMED — never touches status.
          // `BookingDetailResponse` shape → carries phase 334's review.
          return _ok(_seededBookingJson(includeReviewByClient: true));
        },
      ),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );
  }

  /// (Re-)registers `POST /api/v1/salons/salon-xyz/invite`.
  /// See [forceInviteStaffFailure]. The fake just records the decoded body
  /// (email/role) and counts the call, mirroring the PATCH/DELETE salon
  /// handlers above; a real `InviteResponse` only carries
  /// `invitedEmail`/`expiresAt`, both nullable, so an empty data object is a
  /// valid success envelope.
  void _wireInviteStaff() {
    final int? failStatus = _inviteStaffFailureStatusCode;
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/invite',
      (server) => server.replyCallback(failStatus ?? 200, (req) {
        inviteStaffCalls++;
        final body = _decodeBody(req.data);
        lastInviteStaffBody = body;
        if (failStatus != null) {
          final String? errorCode = _inviteStaffFailureErrorCode;
          return <String, dynamic>{
            'success': false,
            'data': errorCode == null
                ? null
                : <String, dynamic>{'code': errorCode},
            'message': 'Failed to invite staff',
          };
        }
        // Phase 21.11 — a real POST does not just answer 200, it CREATES an
        // `InviteToken` row that the history GET then returns. The fake
        // mints one here for the same reason the DELETE handler below really
        // revokes one: without it, "the invite you just sent appears
        // in the list" would be indistinguishable from the bug where the
        // list is never invalidated, and the fixture would silently defang
        // the assertion.
        // Prepended, not appended: the history endpoint serves newest first,
        // and a freshly minted invitation is the newest row there is.
        pendingInvites.insert(0, <String, dynamic>{
          'inviteId': 'invite-minted-${++_mintedInviteSeq}',
          'recipientEmail': body['email'],
          'role': body['role'],
          'status': 'PENDING',
          'createdAt': kFixedNow.toUtc().toIso8601String(),
          'expiresAt': kFixedNow
              .toUtc()
              .add(const Duration(hours: 48))
              .toIso8601String(),
        });
        return _ok(<String, dynamic>{
          'invitedEmail': body['email'],
          'expiresAt': null,
        });
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  /// (Re-)registers `GET /api/v1/salons/salon-xyz/invites`.
  /// See [forcePendingInvitesFailure].
  ///
  /// Serves a COPY of [pendingInvites] read at REQUEST time — the list is
  /// mutated by `_wireInviteStaff`'s insert and `_wireCancelInvite`'s status
  /// flip, and capturing it at registration time would freeze the very state
  /// these journeys exist to observe.
  ///
  /// `data` is an OBJECT (`{invites, truncated}`), not a bare array: the
  /// history envelope carries the truncation flag alongside the rows.
  void _wirePendingInvites() {
    final int? failStatus = _pendingInvitesFailureStatusCode;
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/invites',
      (server) => server.replyCallback(failStatus ?? 200, (req) {
        listSalonInvitesCalls++;
        if (failStatus != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to list salon invites',
          };
        }
        return _ok(<String, dynamic>{
          'invites': List<Map<String, dynamic>>.from(
            pendingInvites.map(Map<String, dynamic>.from),
          ),
          'truncated': salonInvitesTruncated,
        });
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// (Re-)registers `DELETE /api/v1/salons/salon-xyz/invites/{inviteId}` —
  /// which REVOKES the invitation rather than deleting it: the row stays in
  /// the history reading CANCELLED. See [forceCancelInviteFailure].
  ///
  /// A RegExp route: the id segment varies per request AND new ids are minted
  /// mid-flow by `POST .../invite`, so the "register one literal route per
  /// seeded id" device used elsewhere in this file cannot cover them. The
  /// pattern requires a segment AFTER `/invites/`, so it can never collide
  /// with the history GET at `/invites` itself.
  void _wireCancelInvite() {
    final int? failStatus = _cancelInviteFailureStatusCode;
    _adapter.onRoute(
      RegExp(r'/api/v1/salons/salon-xyz/invites/[^/]+$'),
      (server) => server.replyCallback(failStatus ?? 204, (req) {
        cancelInviteCalls++;
        final String inviteId = req.path.split('/').last;
        lastCancelInviteId = inviteId;
        if (failStatus != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to cancel invite',
          };
        }
        // The real endpoint revokes in place — the row survives, carrying its
        // new terminal status. A fake that REMOVED it would let a client
        // which wrongly drops cancelled rows pass every refetch assertion.
        for (int i = 0; i < pendingInvites.length; i++) {
          if (pendingInvites[i]['inviteId'] == inviteId) {
            pendingInvites[i] = <String, dynamic>{
              ...pendingInvites[i],
              'status': 'CANCELLED',
            };
          }
        }
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.delete),
    );
  }

  /// (Re-)registers the three Phase 21.6 admin-management routes.
  ///
  /// Route ORDER matters here, and only here in this file: the rotate PATCH
  /// lives at `.../admins/{userId}/salon` while the remove DELETE lives at
  /// `.../admins/{userId}`. Both are RegExp routes (the `{userId}` segment
  /// varies), so the remove pattern is anchored with a trailing `$` and
  /// excludes a further `/` segment — without that it would also match the
  /// rotate path. The method matchers already separate them; the patterns are
  /// made disjoint anyway, for the reason `_wireCancelInvite` records.
  void _wireAdminManagement() {
    // GET /api/v1/salons/salon-xyz/sibling-salons — the rotate-destination
    // picker. Serves a COPY read at request time.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/sibling-salons',
      (server) => server.replyCallback(200, (_) {
        siblingSalonsCalls++;
        return _okList(
          List<Map<String, dynamic>>.from(
            siblingSalons.map(Map<String, dynamic>.from),
          ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/salons/salon-xyz/admins/{userId}/salon — rotate. The
    // administrator leaves THIS salon's roster (they now belong to the
    // destination), which is what makes "they are gone from «Персонал» after
    // a real refetch" a genuine assertion rather than a client-side illusion.
    final int? rotateFail = _rotateAdminFailureStatusCode;
    _adapter.onRoute(
      RegExp(r'/api/v1/salons/salon-xyz/admins/[^/]+/salon$'),
      (server) => server.replyCallback(rotateFail ?? 204, (req) {
        rotateAdminCalls++;
        final List<String> segments = req.path.split('/');
        lastRotateAdminUserId = segments[segments.length - 2];
        lastRotateAdminBody = _decodeBody(req.data);
        if (rotateFail != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to rotate admin',
          };
        }
        salonStaff.removeWhere(
          (Map<String, dynamic> row) => row['userId'] == lastRotateAdminUserId,
        );
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // DELETE /api/v1/salons/salon-xyz/admins/{userId} — remove (unassign).
    final int? removeFail = _removeAdminFailureStatusCode;
    _adapter.onRoute(
      RegExp(r'/api/v1/salons/salon-xyz/admins/[^/]+$'),
      (server) => server.replyCallback(removeFail ?? 204, (req) {
        removeAdminCalls++;
        lastRemoveAdminUserId = req.path.split('/').last;
        if (removeFail != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to remove admin',
          };
        }
        // The backend nulls the user's `salon_id`; it does NOT delete the
        // account. From this salon's roster the observable effect is the
        // same: the row is gone.
        salonStaff.removeWhere(
          (Map<String, dynamic> row) => row['userId'] == lastRemoveAdminUserId,
        );
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.delete),
    );

    // DELETE /api/v1/salons/salon-xyz/masters/{masterId} — Phase 307 (backend
    // Phase 297 + 298). Registered as its OWN pattern (`/masters/` vs
    // `/admins/` above) so the two DELETE routes can never shadow each
    // other. Removes the row keyed by `masterId` — the WIRE proof that the
    // client sent the Master-row id, not the roster's `userId`: a client
    // bug that sent `userId` here would remove NOTHING (no row's `masterId`
    // equals a `userId`) and the flow's "gone from the roster" assertion
    // would correctly fail.
    final int? removeMasterFail = _removeMasterFailureStatusCode;
    _adapter.onRoute(
      RegExp(r'/api/v1/salons/salon-xyz/masters/[^/]+$'),
      (server) => server.replyCallback(removeMasterFail ?? 204, (req) {
        removeMasterCalls++;
        lastRemoveMasterId = req.path.split('/').last;
        if (removeMasterFail != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to remove master',
          };
        }
        // The backend HARD-DELETES the master's account (Phase 297) and
        // cancels+notifies their future bookings (Phase 298) — from this
        // salon's roster the observable effect is that the row is gone.
        salonStaff.removeWhere(
          (Map<String, dynamic> row) => row['masterId'] == lastRemoveMasterId,
        );
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.delete),
    );

    // GET /api/v1/masters/master-removable/services — the removable
    // master's active services, fetched by `salonStaffMemberProfileProvider`
    // whenever its staff/settings profile is opened.
    //
    // Phase 318 (mobile-qa) — WIDENED from a static empty reply to mirror the
    // LIVE [_salonMasterServices] state. Both endpoints describe the SAME
    // underlying master catalogue (this one via the PUBLIC per-master read,
    // `/salons/{s}/masters/{m}/services` via the salon-scoped one) — a real
    // backend's two reads would agree, and a static empty reply here made the
    // phase-318 D4 refetch assertion and the inherited backlog-802 stale-count
    // regression (unassign in the subtree must move THIS screen's count)
    // structurally untestable, since the read this screen renders from never
    // moved no matter what the subtree wrote.
    _adapter.onRoute(
      '/api/v1/masters/master-removable/services',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterServicesCalls++;
        lastGetPublicMasterServicesId = 'master-removable';
        return _okList(
          salonMasterOwnServicesEmpty
              ? <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.from(
                  _salonMasterServices.map(Map<String, dynamic>.from),
                ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/masters/master-admin-target/services — Phase 312
    // (mobile-qa). `salonAdminOneStaff`'s new master row's active services,
    // fetched by the SAME `salonStaffMemberProfileProvider` chain the two
    // registrations above serve — without this, opening that roster row's
    // profile (a prerequisite for reaching its D3 schedule row) throws and
    // the whole staff-profile screen renders `ErrorState` instead. Empty,
    // same reasoning as `master-removable` above: this fixture's flows never
    // assert on service content.
    //
    // Phase 325 (mobile-qa, 2026-09-12) — this emptiness is now ALSO the
    // deliberate zero-service fixture for
    // `salon_admin_set_master_services_flow_test.dart`'s E2E assertion that
    // the «Послуги» `ManagementActionCard` on `SalonStaffProfileScreen`
    // renders `staffProfileServicesEmpty` («Ще немає»), never
    // `staffProfileServicesCount(0)`, for a master whose catalogue is
    // genuinely empty. Never seed a row here — doing so would silently
    // remove the only E2E-reachable empty catalogue (`master-removable`, the
    // owner-flow counterpart, always seeds two rows).
    _adapter.onRoute(
      '/api/v1/masters/master-admin-target/services',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterServicesCalls++;
        lastGetPublicMasterServicesId = 'master-admin-target';
        return _okList(const <Map<String, dynamic>>[]);
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// (Re-)registers the three `GET /api/v1/salons/salon-xyz/services/
  /// {serviceDefId}/masters` routes (Phase 23.x bookable-masters rewire; see
  /// the call site's own doc for the coverage split). Extracted into its own
  /// method (Phase 266) so [forceBookableMastersFailure] can re-register
  /// just one service's route with a failing status code without touching
  /// the other two — same device as [_wirePassport].
  void _wireSalonBookableMasters() {
    int? failStatusFor(String serviceDefId) =>
        _bookableMastersFailureStatusCodeByService[serviceDefId];

    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/services/salon-svc-shared/masters',
      (server) =>
          server.replyCallback(failStatusFor('salon-svc-shared') ?? 200, (_) {
            getBookableMastersCalls++;
            requestedBookableMastersServiceDefIds.add('salon-svc-shared');
            if (failStatusFor('salon-svc-shared') != null) {
              return <String, dynamic>{
                'success': false,
                'data': null,
                'message': 'Failed to load bookable masters',
              };
            }
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
      (server) => server.replyCallback(
        failStatusFor('salon-svc-exclusive') ?? 200,
        (_) {
          getBookableMastersCalls++;
          requestedBookableMastersServiceDefIds.add('salon-svc-exclusive');
          if (failStatusFor('salon-svc-exclusive') != null) {
            return <String, dynamic>{
              'success': false,
              'data': null,
              'message': 'Failed to load bookable masters',
            };
          }
          return _okList(<Map<String, dynamic>>[
            _bookableMasterEnvelope(
              masterId: 'master-ddd',
              serviceDefId: 'salon-svc-exclusive',
              firstName: 'Оксана',
              lastName: 'Іванова',
            ),
          ]);
        },
      ),
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
      (server) => server.replyCallback(
        failStatusFor('salon-svc-namefallback') ?? 200,
        (_) {
          getBookableMastersCalls++;
          requestedBookableMastersServiceDefIds.add('salon-svc-namefallback');
          if (failStatusFor('salon-svc-namefallback') != null) {
            return <String, dynamic>{
              'success': false,
              'data': null,
              'message': 'Failed to load bookable masters',
            };
          }
          return _okList(const <Map<String, dynamic>>[]);
        },
      ),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// (Re-)registers `GET /api/v1/clients/me/passport` — CLIENT's derived
  /// BEAUTY PASSPORT (backend 19.5). Without this route the mock router 404s
  /// and the passport tab renders its ERROR state instead of the empty
  /// variant the flow asserts.
  ///
  /// Defaults to the EMPTY passport (bookingsConsidered 0, no lists, no
  /// budget) — the state a freshly-seeded fake client is in. Mutate
  /// [passportBody] from a flow to serve a populated passport instead.
  /// See [forcePassportFailure] for the error-card path.
  void _wirePassport() {
    final int? failStatus = _passportFailureStatusCode;
    _adapter.onRoute(
      '/api/v1/clients/me/passport',
      (server) => server.replyCallback(failStatus ?? 200, (_) {
        getPassportCalls++;
        if (failStatus != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to load passport',
          };
        }
        return _ok(passportBody);
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// (Re-)registers `GET /api/v1/favorites/masters`.
  /// See [forceListMasterFavoritesFailure].
  void _wireListMasterFavorites() {
    final int? failStatus = _listMasterFavoritesFailureStatusCode;
    _adapter.onRoute(
      '/api/v1/favorites/masters',
      (server) => server.replyCallback(failStatus ?? 200, (_) {
        listMasterFavoritesCalls++;
        if (failStatus != null) {
          return <String, dynamic>{
            'success': false,
            'data': null,
            'message': 'Failed to list favorite masters',
          };
        }
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <String, dynamic>{
            'data': favoriteMasterRows,
            'page': 0,
            'size': 20,
            'totalElements': favoriteMasterRows.length,
            'totalPages': favoriteMasterRows.isEmpty ? 0 : 1,
          },
        };
      }),
      request: const Request(method: RequestMethods.get),
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
        // Phase 111 (mobile-qa) — a MASTER/SALON removal PERSISTS, mirroring
        // the real backend, so a following `GET /favorites/masters` genuinely
        // reflects it. Without this a flow can only prove the DELETE was SENT;
        // it cannot prove the row is actually gone on a re-read, which is the
        // half a client would notice. Same device as the SERVICE add above.
        // Shape-tolerant reads, never a raw cast — see
        // `scripts/forbid_raw_query_param_cast.sh`.
        final String? type = _scalarQueryParam(
          req.queryParameters,
          'targetType',
        );
        final String? id = _scalarQueryParam(req.queryParameters, 'targetId');
        if (type == 'MASTER' && id != null) {
          favoriteMasterRows = favoriteMasterRows
              .where((Map<String, dynamic> r) => r['masterId'] != id)
              .toList();
        } else if (type == 'SALON' && id != null) {
          favoriteSalonRows = favoriteSalonRows
              .where((Map<String, dynamic> r) => r['salonId'] != id)
              .toList();
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

    // GET /api/v1/auth/invite/validate?token=… — the invite PREVIEW the
    // AcceptInviteScreen renders before it will show the form at all.
    //
    // Added with the invite-accept E2E (mobile-qa 2026-09-06). Without it the
    // screen's `acceptInviteProvider(token)` resolved to an AsyncError against
    // the DioAdapter's own "no matching route" reply and the screen rendered
    // the invalid-invite banner — the form (and therefore the whole accept
    // path) was unreachable from `integration_test/`, which is why the
    // dropped-`salonId` regression could only ever be caught by hand.
    //
    // Branches on [currentRole] exactly like login/accept do, so the invited
    // email the preview shows and the persona the accept envelope returns are
    // the SAME account — an E2E that showed one address and signed in as
    // another would be pinning nothing.
    //
    // `expiresAt` is anchored to [kFixedNow], NOT `DateTime.now()`: the screen
    // renders `expiresInHoursFrom(ref.watch(clockProvider)())`, and the harness
    // pins that clock to [kFixedNow]. A host-clock fixture here would be the
    // exact fixture-clock/app-clock MIX that M15 names.
    _adapter.onRoute(
      '/api/v1/auth/invite/validate',
      (server) => server.replyCallback(200, (req) {
        validateInviteCalls++;
        lastValidateInviteToken = _scalarQueryParam(
          req.queryParameters,
          'token',
        );
        final user = userJsonForRole(currentRole);
        return _ok(<String, dynamic>{
          'invitedEmail': user['email'],
          'role': user['role'],
          'expiresAt': kFixedNow
              .add(const Duration(hours: 48))
              .toUtc()
              .toIso8601String(),
        });
      }),
      request: const Request(method: RequestMethods.get),
    );

    // POST /api/v1/auth/invite/accept — the invited-staff account creation.
    //
    // Replies with the SAME `AuthResponse` envelope login uses, driven by
    // [currentRole], so setting `currentRole = UserRole.salonAdmin` yields the
    // admin persona's `salonId` on the envelope — exactly what the real
    // backend returns (verified live: HTTP 201 with a populated `salonId`).
    // This flow does NOT hit `GET /users/me`, so the envelope is the session's
    // only source for that binding.
    _adapter.onRoute(
      '/api/v1/auth/invite/accept',
      (server) => server.replyCallback(200, (req) {
        acceptInviteCalls++;
        lastAcceptInviteBody = _decodeBody(req.data);
        return _authResponse(userJsonForRole(currentRole));
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
      (server) =>
          server.replyCallback(forgotPasswordFailureStatusCode ?? 200, (req) {
            forgotPasswordCalls++;
            lastForgotPasswordEmail = _decodeBody(req.data)['email'] as String?;
            if (forgotPasswordFailureStatusCode != null) {
              // The rate-limit FILTER's own body — deliberately NOT the
              // `{success,message,data}` envelope the controllers use.
              return <String, dynamic>{'error': 'Too many requests'};
            }
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

    // POST /api/v1/media/avatar — multipart (`file` part), so the body is not
    // decoded. 200 with the public URL on success; [mediaAvatarUploadStatus]
    // switches it to a failure status. Tests that render the returned URL must
    // allow the `media.test` host via MediaConfig's debug hosts.
    _adapter.onRoute(
      '/api/v1/media/avatar',
      (server) => server.replyCallback(mediaAvatarUploadStatus ?? 200, (
        RequestOptions options,
      ) {
        mediaAvatarUploadCalls++;
        mediaAvatarUploadUris.add(options.uri);
        final Object? body = options.data;
        mediaAvatarUploadPartNames.add(
          body is FormData
              ? <String>[
                  for (final MapEntry<String, String> f in body.fields) f.key,
                  for (final MapEntry<String, MultipartFile> f in body.files)
                    f.key,
                ]
              : <String>['<non-multipart:${body.runtimeType}>'],
        );
        if (mediaAvatarUploadStatus != null) {
          return <String, dynamic>{'success': false};
        }
        final String url =
            'https://media.test/avatars/u1/${++_mediaAvatarSeq}.jpg';
        mediaAvatarUrl = url;
        return _ok(<String, dynamic>{'avatarUrl': url});
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // DELETE /api/v1/media/avatar → 204.
    _adapter.onRoute(
      '/api/v1/media/avatar',
      (server) => server.replyCallback(204, (RequestOptions options) {
        mediaAvatarDeleteCalls++;
        mediaAvatarDeleteUris.add(options.uri);
        mediaAvatarDeleteBodies.add(options.data);
        mediaAvatarUrl = null;
        return null;
      }),
      // `Matchers.any` (Phase 367 QA): a DELETE that smuggled a body must
      // still reach this handler and be RECORDED, so
      // `expectSelfOnlyAvatarRequests` fails on the body itself rather than
      // on an opaque unmatched-route error.
      request: const Request(method: RequestMethods.delete, data: Matchers.any),
    );

    // GET /api/v1/users/me
    // For the CLIENT role, returns the MUTABLE client body so a PATCH /users/me
    // round-trips on the next read (the edit screens invalidate
    // clientEditProfileProvider → re-fetch). Phase 356 — SALON_ADMIN gets the
    // SAME treatment via [_adminProfileBody] (its own admin editors reuse the
    // CLIENT ones and PATCH the identical endpoint). Every other role keeps
    // the static fixture.
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) => server.replyCallback(200, (_) {
        getMeCalls++;
        // Phase 367 — `avatarUrl` (backend 344, every role) mirrors the
        // last successful `/media/avatar` write; OMITTED while none happened,
        // so every pre-existing flow's body is byte-identical.
        final String? avatar = mediaAvatarUrl;
        return switch (currentRole) {
          UserRole.client => _ok(<String, dynamic>{
            ..._clientProfileBody(),
            'avatarUrl': ?avatar,
          }),
          UserRole.salonAdmin => _ok(<String, dynamic>{
            ..._adminProfileBody(),
            if (hasMasterProfile != null) 'hasMasterProfile': hasMasterProfile,
            'avatarUrl': ?avatar,
          }),
          // Phase 21.14 — `hasMasterProfile` is OMITTED unless the flow set
          // it, so the default body is byte-identical to the pre-21.14 one
          // and `null` stays a genuine "key absent", not a serialized null.
          _ => _ok(<String, dynamic>{
            ...userJsonForRole(currentRole),
            if (hasMasterProfile != null) 'hasMasterProfile': hasMasterProfile,
            'avatarUrl': ?avatar,
          }),
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/mine — Phase 21.1 My Salons Hub (the SALON_OWNER
    // landing, `mySalonsProvider`). `SalonResponse` shape (isPrimary etc.) —
    // see [mySalons]'s own doc for why it is mutable.
    _adapter.onRoute(
      '/api/v1/salons/mine',
      (server) => server.replyCallback(200, (_) {
        getMySalonsCalls++;
        return _okList(mySalons.map(withSeededSalonLocality).toList());
      }),
      request: const Request(method: RequestMethods.get),
    );

    // POST /api/v1/salons — Phase 21.3 «Register New Salon»
    // (RegisterSalonScreen → RegisterSalon.submit → HttpSalonRepository
    // .create). Appends the new salon onto the SAME mutable [mySalons] list
    // `GET /api/v1/salons/mine` serves, so a flow that drives the real
    // `ref.invalidate(mySalonsProvider)` round trip sees the new salon on
    // the hub's NEXT read without a manual refresh — the exact contract
    // `register_salon_notifier.dart`'s own doc describes.
    // `HttpSalonRepository.create` returns `Future<void>` and never parses
    // the response body, so the returned envelope's `data` shape does not
    // need to mirror the real `SalonResponse` beyond `success: true`.
    _adapter.onRoute(
      '/api/v1/salons',
      (server) =>
          server.replyCallback(createSalonFailureStatusCode ?? 200, (req) {
            createSalonCalls++;
            final body = _decodeBody(req.data);
            lastCreateSalonBody = body;
            if (createSalonFailureStatusCode != null) {
              return <String, dynamic>{
                'success': false,
                'data': null,
                'message': 'Failed to create salon',
              };
            }
            final String newId = 'salon-created-$createSalonCalls';
            mySalons.add(
              withSeededSalonLocality(<String, dynamic>{
                'id': newId,
                'ownerId': 'user-owner-1',
                'name': body['name'] as String? ?? '',
                // RESUME §4 step D (mobile half) — `SalonResponse.cityId`/
                // `.oblastId` are non-null on the wire. `register_salon_
                // notifier.dart` always sends a real `cityId` on `POST
                // /salons`, so echo it back rather than a hard-coded value;
                // every seeded city (`city-kyiv`/`city-lviv`/
                // `city-with-districts`) resolves to the SAME seeded
                // `oblast-kyiv`, so that half is always correct regardless of
                // which city was picked.
                'cityId': (body['cityId'] as String?) ?? 'city-kyiv',
                'oblastId': 'oblast-kyiv',
                'street': body['street'] as String? ?? '',
                'buildingNo': body['buildingNo'] as String? ?? '',
                'isActive': true,
                'isPrimary': false,
                if (body['phone'] != null) 'phone': body['phone'],
                if (body['instagramUrl'] != null)
                  'instagramUrl': body['instagramUrl'],
                // `city`/`region` are re-derived from the SENT `cityId` by
                // [withSeededSalonLocality] (backend Phase 328).
              }),
            );
            return _ok(<String, dynamic>{'id': newId, 'name': body['name']});
          }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
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
    // (backend 19.5). See [_wirePassport].
    _wirePassport();

    // GET /api/v1/clients/me/timeline — CLIENT's BEAUTY TIMELINE
    // (completed-procedure history, backend 19.5). Wired now that
    // `HttpTimelineRepository` calls the real endpoint — see [timelineRows]'s
    // doc for the defect this route's ABSENCE caused before this pass.
    // Envelope shape mirrors `_wireListMasterFavorites`'s page envelope
    // exactly: outer `ApiResponse` (`success`/`message`/`data`), inner
    // `PageResponse` (`data`/`page`/`size`/`totalElements`/`totalPages`).
    _adapter.onRoute(
      '/api/v1/clients/me/timeline',
      (server) => server.replyCallback(200, (_) {
        getTimelineCalls++;
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <String, dynamic>{
            'data': timelineRows,
            'page': 0,
            'size': 20,
            'totalElements': timelineRows.length,
            'totalPages': timelineRows.isEmpty ? 0 : 1,
          },
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/users/me — profile partial update (the shared,
    // no-role-restriction endpoint every `*_edit_screen.dart` in the app
    // hits via UserControllerApi.updateMe). Merge-onto-cache: each key
    // present in the body overlays the in-memory state; keys absent from
    // the body are preserved.
    //
    // Phase 356 — SALON_ADMIN branch. The admin's own settings hub reuses
    // `client_personal_info_edit_screen.dart`/`client_contacts_edit_screen
    // .dart` VERBATIM, so it PATCHes this exact endpoint too, but must never
    // fall into the CLIENT mutation branch below (touching `clientFirstName`
    // et al. would be silently harmless today — nothing reads those for an
    // admin session — but would leave [adminFirstName] et al. stale, which
    // IS observed: `GET /users/me` for SALON_ADMIN now serves
    // [_adminProfileBody]). Also keeps the admin's OWN row inside
    // [salonAdminOneStaff] in lock-step (D6 — «Команда» is UNFILTERED and
    // renders the viewer's own row, so a stale name there is directly
    // observable without a second endpoint).
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) => server.replyCallback(200, (req) {
        patchMeCalls++;
        final body = _decodeBody(req.data);
        lastPatchMeBody = body;

        if (currentRole == UserRole.salonAdmin) {
          if (body.containsKey('firstName')) {
            adminFirstName = body['firstName'] as String? ?? adminFirstName;
          }
          if (body.containsKey('lastName')) {
            adminLastName = body['lastName'] as String? ?? adminLastName;
          }
          if (body.containsKey('phoneNumber')) {
            adminPhone = body['phoneNumber'] as String?;
          }
          for (final Map<String, dynamic> row in salonAdminOneStaff) {
            if (row['userId'] != 'user-admin-1') continue;
            if (body.containsKey('firstName')) {
              row['firstName'] = adminFirstName;
            }
            if (body.containsKey('lastName')) row['lastName'] = adminLastName;
          }
          return _ok(_adminProfileBody());
        }

        // CONTRACT NOTES the CLIENT flow asserts against:
        //   • `instagram` is NEVER sent by ClientProfileRepository — if it
        //     ever appears in the body this would surface it
        //     (lastPatchMeBody captured).
        //   • a null `cityId` in the body is a VALID save (CLIENT location
        //     optional) and clears the city; the body still carries cityId
        //     (built_value emits it when the location slice is touched).
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
        //
        // Phase 346 mobile-qa fix — `clientCityName` used to just carry the
        // PREVIOUS name forward on a cityId change (harmless while the search
        // prefill resolved city NAMES through a live oblast/city taxonomy
        // lookup by id, never off this denormalised field). Now that
        // `SearchFiltersController.prefillFromProfileIfNeeded` reads
        // `user.cityName` directly off `/users/me` with no taxonomy round
        // trip at all (search_filters_controller.dart:388-393), a stale name
        // here would leak into Search on the very next open after a real
        // Location-edit save — exactly the regression
        // `client_search_flow_test.dart`'s mid-session-city-change flow
        // exists to catch. Derived from [kSeededSettlementNames] so it always
        // agrees with the `GET /api/v1/settlements` rows below.
        if (body.containsKey('cityId')) {
          clientCityId = body['cityId'] as String?;
          clientCityName = clientCityId == null
              ? null
              : (kSeededSettlementNames[clientCityId] ?? clientCityName);
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

    // DELETE /api/v1/users/me — CLIENT delete-account (mobile-qa,
    // 2026-09-08). Same path string as the GET/PATCH handlers above,
    // differentiated by method — `http_mock_adapter` already resolves that
    // combination correctly for this exact path (GET + PATCH already share
    // it). Default 204; [deleteMyAccountFailureStatusCode] forces 422 (body
    // carries [deleteMyAccountFailureMessage] so `ValidationFailure
    // .serverMessage` → `AccountDeleteBookingLimitFailure.serverMessage`
    // round-trips through the REAL `ErrorMapperInterceptor`, not a
    // hand-mapped stand-in) or 429 (no body needed — the repository maps 429
    // by status code alone, before any body is read).
    _adapter.onRoute(
      '/api/v1/users/me',
      (server) =>
          server.replyCallback(deleteMyAccountFailureStatusCode ?? 204, (_) {
            deleteMyAccountCalls++;
            if (deleteMyAccountFailureStatusCode == 422) {
              return <String, dynamic>{
                'success': false,
                'data': null,
                'message': deleteMyAccountFailureMessage,
              };
            }
            if (deleteMyAccountFailureStatusCode != null) {
              return <String, dynamic>{'success': false, 'data': null};
            }
            return null;
          }),
      request: const Request(method: RequestMethods.delete),
    );

    // GET /api/v1/masters/me
    //
    // Phase 21.14: [masterMeNotFound] flips this to the 404 a SALON_OWNER with
    // no active master row really receives — 404 and not 403, since backend
    // `c4d69ac` widened this endpoint's @PreAuthorize to admit SALON_OWNER.
    // Chosen at wire time (see that field's doc).
    _adapter.onRoute(
      '/api/v1/masters/me',
      (server) => masterMeNotFound
          ? server.replyCallback(404, (_) {
              getMasterCalls++;
              return _masterNotFoundEnvelope();
            })
          : server.replyCallback(200, (_) {
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

    // Phase 264 — GET /api/v1/masters/{masterRowId}, the PUBLIC master-detail
    // endpoint keyed on the master's OWN row id. The routed walk-in chain's
    // `BookingConfirmScreen` (a REUSED CLIENT screen, `publicMasterProfile
    // Provider(masterId)`) always re-resolves the target master through this
    // public endpoint — even when the target IS the signed-in master
    // themselves — unlike the retired wizard, which only ever read
    // `masterProfileProvider` (`GET /masters/me`, registered above). Reuses
    // [_masterDetailEnvelope] verbatim (REUSE-FIRST) rather than a second,
    // possibly-drifting envelope shape: the public view of "my own profile"
    // is the same identity `GET /masters/me` already returns. Registered
    // AFTER the more-specific `.../reviews`/`.../reviews/summary` routes
    // above (same "more specific path first" ordering those routes'
    // own comment establishes) so this bare-id route can never shadow them.
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterCalls++;
        lastGetPublicMasterId = masterRowId;
        return _masterDetailEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // Phase 264 — GET /api/v1/masters/{masterRowId}/services, the PUBLIC
    // active-services counterpart `publicMasterProfileProvider` fetches
    // alongside the detail route just above. Reuses [_services] verbatim
    // (REUSE-FIRST) — the SAME wire shape `_publicMasterServices`'s own doc
    // already notes ("Shapes match the generated `MasterServiceResponse`,
    // the same envelope `_services` uses"), so this is not a new fixture,
    // just a new route onto an existing one.
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/services',
      (server) => server.replyCallback(200, (_) {
        getPublicMasterServicesCalls++;
        lastGetPublicMasterServicesId = masterRowId;
        return _okList(_services);
      }),
      request: const Request(method: RequestMethods.get),
    );

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
        return _okList(_publicMasterServicesEffective);
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
    _wireSalonBookableMasters();

    // GET /api/v1/masters/master-aaa/slots?date=&serviceId= — Phase 14.1 slot
    // picker (SlotRepository.getMasterSlots). Query params are not part of
    // the DioAdapter route match (path only — see the salon-xyz/masters
    // comment below), so one registration answers every date/service the
    // booking-flow E2E requests.
    _adapter.onRoute(
      '/api/v1/masters/master-aaa/slots',
      (server) => server.replyCallback(200, (req) {
        getMasterSlotsCalls++;
        // Phase 350 — records the FULL multi-service selection, mirroring
        // the working-days registration above.
        lastMasterAaaSlotsServiceIds = _multiQueryParam(
          req.queryParameters,
          'serviceId',
        );
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

    // Phase 248 — the INDEPENDENT_MASTER walk-in flow's OWN date/time
    // picker. Originally the retired single-screen wizard's embedded
    // `MasterSchedulePage`; Phase 264 repointed the SAME masterId at the
    // routed chain's `SlotDateScreen`/`SlotTimeScreen` instead (the CLIENT
    // screens' own `SlotRepository.getMasterSlots` call) — this route
    // registration did not need to change, only its consumer did.
    // `master.id` there resolves to `masterRowId` (`GET /masters/me`'s own
    // id), so this mirrors the `master-ccc`/`master-ddd` pair one level up:
    // the master books THEMSELVES, not a roster colleague. Reuses the shared
    // `_workingDaysEnvelope()`/`_availableSlotsEnvelope()` fixtures — every
    // day across a wide window is working, and the slots land on
    // `kyivDayOf(serverNow)` — so the wizard's calendar/time step needs no
    // fixture of its own beyond this registration.
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/working-days',
      (server) => server.replyCallback(200, (_) {
        getWorkingDaysCalls++;
        return _workingDaysEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/slots',
      (server) => server.replyCallback(200, (req) {
        getMasterSlotsCalls++;
        // Phase 264 — the walk-in chain's OWN slot-availability request
        // (the client's `SlotDateScreen`/`SlotTimeScreen`, not the retired
        // wizard's embedded `MasterSchedulePage`). See
        // [lastMasterOwnSlotsServiceIds]'s own doc.
        lastMasterOwnSlotsServiceIds = _multiQueryParam(
          req.queryParameters,
          'serviceId',
        );
        return _availableSlotsEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );

    // Phase 248 — `POST /api/v1/masters/{masterId}/bookings`, the walk-in
    // wizard's own submit (`BookingRepository.createMasterBooking`, backend
    // 22.4 `StaffBookingsApi.createStaffBooking`). Mints the FIXED
    // [kWalkInBookingId] and APPENDS the new row to [_bookingsDataset] —
    // lazily initialising it if the test never called
    // [seedManyBookingsDataset] — so the very next day-scoped
    // `GET /bookings/me` the wizard's own success invalidation triggers
    // (`MasterCreateBookingNotifier.submit`'s `ref.invalidate
    // (bookingsDayProvider)`) actually shows it. `guest.name`/`guest.surname`
    // map onto `clientFirstName`/`clientLastName` — the fields the MASTER'S
    // OWN card reads (see `datasetBookingRow`'s doc: it seeds the
    // counterparty-identity fields empty on purpose, spread in by the
    // caller).
    //
    // PHASE 256 — the wire request body carries `masterServiceIds` (plural,
    // ORDERED — Phase 252 widened the scalar `masterServiceId` this handler
    // used to read), and the response must be a real
    // `AppointmentDetailResponse` shape (`items[]`, `totalPrice`,
    // `totalDurationMinutes`, a real `endsAt`) — `AppointmentMapper.fromDto`
    // tolerates an absent `items` as an EMPTY list rather than throwing, so a
    // stale single-`Booking`-shaped reply here would silently render a
    // done step with NO services instead of failing loudly. Each id is
    // chained onto the previous item with a fixed 10-minute buffer — NOT
    // back-to-back — so a multi-service run genuinely proves the done step
    // renders the SERVER's window/totals, not a re-derived local sum (the
    // same D3 regression `should_renderServerVisitWindow_when_
    // multiServiceVisitCreated` pins at the widget tier, proven here end to
    // end through the real repository/mapper/wire path instead of a fake
    // repository).
    _adapter.onRoute(
      '/api/v1/masters/$masterRowId/bookings',
      (server) => server.replyCallback(201, (req) {
        createStaffBookingCalls++;
        final Map<String, dynamic> body = _decodeBody(req.data);
        lastStaffBookingRequestBody = body;
        final DateTime startsAt = DateTime.parse(body['startsAt'] as String);
        final Map<String, dynamic> guest = (body['guest'] as Map)
            .cast<String, dynamic>();
        final List<dynamic> serviceIds =
            (body['masterServiceIds'] as List?) ?? const <dynamic>[];

        const Duration itemBuffer = Duration(minutes: 10);
        DateTime cursor = startsAt;
        final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
        double totalPrice = 0;
        double totalPriceMaxSum = 0;
        bool anyRange = false;
        for (final dynamic rawId in serviceIds) {
          final String assignId = rawId as String;
          final Map<String, dynamic> assignment = _services.firstWhere(
            (Map<String, dynamic> s) => s['id'] == assignId,
            orElse: () => throw StateError(
              'FakeBackend: unknown masterServiceId "$assignId" in a '
              'walk-in create — seed it in _services first',
            ),
          );
          final Map<String, dynamic> def =
              (assignment['serviceDefinition'] as Map).cast<String, dynamic>();
          final int duration = assignment['effectiveDurationMinutes'] as int;
          final double priceMin = (assignment['priceMin'] as num).toDouble();
          final double? priceMax = (assignment['priceMax'] as num?)?.toDouble();
          final DateTime itemStart = cursor;
          final DateTime itemEnd = itemStart.add(Duration(minutes: duration));
          items.add(<String, dynamic>{
            'bookingId': 'walkin-booking-${items.length + 1}',
            'masterServiceId': assignId,
            'serviceName': def['name'],
            'status': 'CONFIRMED',
            'startsAt': itemStart.toIso8601String(),
            'endsAt': itemEnd.toIso8601String(),
            'durationMinutesAtBooking': duration,
            'priceAtBooking': priceMin,
            'priceMaxAtBooking': priceMax,
          });
          totalPrice += priceMin;
          totalPriceMaxSum += priceMax ?? priceMin;
          if (priceMax != null) anyRange = true;
          cursor = itemEnd.add(itemBuffer);
        }
        // No trailing buffer past the LAST item — the buffer only ever sits
        // BETWEEN items.
        final DateTime visitEnd = items.isEmpty
            ? startsAt
            : cursor.subtract(itemBuffer);

        final Map<String, dynamic> row = <String, dynamic>{
          ...datasetBookingRow(
            id: kWalkInBookingId,
            status: 'CONFIRMED',
            startsAt: startsAt,
            duration: visitEnd.difference(startsAt),
          ),
          'masterServiceId': serviceIds.isNotEmpty ? serviceIds.first : null,
          'clientId': null,
          'clientFirstName': guest['name'],
          'clientLastName': guest['surname'],
          // Overrides `datasetBookingRow`'s single-service defaults with the
          // REAL chained visit shape (`AppointmentDetailResponse` fields) —
          // see this route's own doc above for why an absent `items` here
          // would fail silently rather than loudly.
          'endsAt': visitEnd.toIso8601String(),
          'totalDurationMinutes': visitEnd.difference(startsAt).inMinutes,
          'totalPrice': totalPrice,
          'totalPriceMax': anyRange ? totalPriceMaxSum : null,
          'items': items,
        };
        (_bookingsDataset ??= <Map<String, dynamic>>[]).add(row);
        _lastWalkInBookingRow = row;
        return _ok(row);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // GET /api/v1/bookings/$kWalkInBookingId — kept registered for any OTHER
    // flow that looks up this fixed id by detail fetch. NOT a follow-up
    // `createMasterBooking` itself makes any more — see
    // [getWalkInBookingDetailCalls]'s doc (mobile-qa Phase 256 audit) for why
    // that used to be true and no longer is.
    _adapter.onRoute(
      '/api/v1/bookings/$kWalkInBookingId',
      (server) => server.replyCallback(200, (_) {
        getWalkInBookingDetailCalls++;
        return _ok(
          _lastWalkInBookingRow ??
              datasetBookingRow(
                id: kWalkInBookingId,
                status: 'CONFIRMED',
                startsAt: serverNow,
              ),
        );
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

    // GET /api/v1/salons/salon-xyz/staff — Phase 21.5 owner/admin «Персонал»
    // grid (SalonControllerApi.getSalonStaff). Envelope is a PLAIN list under
    // `data` (`ApiResponseListSalonStaffMemberResponse`), unlike the
    // paginated `/masters` rail above — `_okList` matches that shape.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz/staff',
      (server) => server.replyCallback(200, (_) {
        getSalonStaffCalls++;
        getSalonStaffCallsById.update(
          'salon-xyz',
          (int n) => n + 1,
          ifAbsent: () => 1,
        );
        lastGetSalonStaffId = 'salon-xyz';
        // A COPY read at REQUEST time — `salonStaff` is mutated by the admin
        // remove/rotate handlers, and capturing it at registration would
        // freeze the very state those journeys exist to observe (same rule
        // `_wirePendingInvites` states for its own list).
        return _okList(
          List<Map<String, dynamic>>.from(
            salonStaff.map(Map<String, dynamic>.from),
          ),
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
        // AGGREGATED AT REQUEST TIME, never captured at registration — see
        // [_salonServiceCatalogNow]. A catalogue frozen at wiring time cannot
        // tell a refetch from a served cache, which is exactly the bug the
        // 2026-09-14 arm of `salon_owner_set_master_services_flow_test.dart`
        // exists to catch.
        return _ok(<String, dynamic>{'categories': _salonServiceCatalogNow()});
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

    // ── SALON_ADMIN's own salon (`salon-admin-1`) ─────────────────────────
    //
    // mobile-qa (2026-08-30) — until now the admin persona
    // (`_adminUserJson.salonId == 'salon-admin-1'`) had NO salon-detail or
    // staff fixture at all, so every admin flow that reached the Salon Shell
    // rendered an error state and no flow could assert anything the
    // management profile actually draws. `salonManageGuard`'s admin arm is an
    // exact `session.user.salonId == :salonId` check, so an admin can ONLY
    // ever reach this id — there is no way to borrow `salon-xyz`'s fixtures.
    //
    // Deliberately shaped as the EMPTY-CONTACTS, EMPTY-DESCRIPTION salon:
    // both owner-only «Додати …» links WOULD render here for a SALON_OWNER,
    // which is exactly what makes "an admin sees neither" a real assertion
    // rather than one satisfied by the salon simply having a description and
    // an Instagram on file (M14 — a negative assertion that passes for the
    // wrong reason is indistinguishable from a real one).
    _adapter.onRoute(
      '/api/v1/salons/salon-admin-1',
      (server) => server.replyCallback(200, (_) {
        getSalonByIdCalls++;
        lastGetSalonId = 'salon-admin-1';
        return _ok(
          withSeededSalonLocality(<String, dynamic>{
            'id': 'salon-admin-1',
            'name': 'Салон Адміністратора',
            'description': null,
            'cityId': 'city-kyiv',
            'oblastId': 'oblast-kyiv',
            'street': 'вул. Січових Стрільців',
            'buildingNo': '7',
            'locationNote': null,
            'phone': null,
            'instagramUrl': null,
            'avatarUrl': null,
            'coverImageUrl': null,
            'avgRating': null,
            'reviewCount': 0,
          }),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-admin-1/staff — mobile-qa Phase 308 LOW
    // closure (2026-09-05): was a hardcoded empty roster (the «Персонал»
    // grid's own empty state, `salon-manage-staff-empty`, is separately
    // pinned at the widget tier and does not need this endpoint populated).
    // Now serves the mutable [salonAdminOneStaff] — see that field's own doc
    // for why this is an ISOLATED fixture rather than a widened `salonStaff`.
    // A COPY read at REQUEST time, mirroring `salon-xyz`'s own handler above.
    _adapter.onRoute(
      '/api/v1/salons/salon-admin-1/staff',
      (server) => server.replyCallback(200, (_) {
        getSalonStaffCalls++;
        getSalonStaffCallsById.update(
          'salon-admin-1',
          (int n) => n + 1,
          ifAbsent: () => 1,
        );
        lastGetSalonStaffId = 'salon-admin-1';
        return _okList(
          List<Map<String, dynamic>>.from(
            salonAdminOneStaff.map(Map<String, dynamic>.from),
          ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/salons/salon-admin-1/sibling-salons — mobile-qa
    // gap-closure (2026-09-12): `MoveAdminSalonScreen`'s destination picker
    // is REACHABLE from `salon-admin-1` (`salonManageStaffSettings` admits a
    // SALON_ADMIN onto a co-admin's settings page and `row-admin-move-salon`
    // is live there), but until now nothing served this GET for that salon
    // id, so the screen always rendered its `ErrorState` branch —
    // reachable, not usable. Mirrors `salon-xyz`'s own handler above
    // (a COPY read at REQUEST time) but serves the ISOLATED
    // [salonAdminOneSiblingSalons] list — see that field's own doc for why.
    _adapter.onRoute(
      '/api/v1/salons/salon-admin-1/sibling-salons',
      (server) => server.replyCallback(200, (_) {
        siblingSalonsCalls++;
        return _okList(
          List<Map<String, dynamic>>.from(
            salonAdminOneSiblingSalons.map(Map<String, dynamic>.from),
          ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/salons/salon-xyz — owner/admin profile save (Phase 21.2).
    // Distinct wire shape from the public `GET` above (`SalonResponse` vs
    // `PublicSalonResponse`), but the two now agree on `phone`: both read the
    // SAME mutable [salonPhone], because the backend gap-fix put `phone` on
    // the public DTO too. Applies only the DIRTY fields the request carries
    // onto the mutable `_salonManage*` state so a flow can prove BOTH halves
    // of the dirty-diff contract on a real (fake) wire round-trip: an
    // untouched field never overwrites the persisted value, an edited one
    // does.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz',
      (server) =>
          server.replyCallback(updateSalonFailureStatusCode ?? 200, (req) {
            updateSalonCalls++;
            final body = _decodeBody(req.data);
            lastUpdateSalonBody = body;
            if (updateSalonFailureStatusCode != null) {
              return <String, dynamic>{
                'success': false,
                'data': null,
                'message': 'Failed to update salon',
              };
            }
            if (body['name'] is String) {
              _salonManageName = body['name'] as String;
            }
            if (body.containsKey('description')) {
              salonDescription = body['description'] as String?;
            }
            if (body.containsKey('phone')) {
              salonPhone = body['phone'] as String?;
            }
            if (body.containsKey('instagramUrl')) {
              salonInstagramUrl = body['instagramUrl'] as String?;
            }
            // `saveAddress` sends `cityId` UNCONDITIONALLY (never diffed —
            // see this handler's own doc above), so a real save always
            // carries it; `districtId` stays diffed-by-omission (a leaf
            // city legitimately sends none). Falls back to the current
            // mutable value so an untouched-locality PATCH (e.g. Test 4,
            // editing only `street`) still echoes a valid, non-null pair.
            if (body['cityId'] is String) {
              salonManageCityId = body['cityId'] as String;
            }
            if (body.containsKey('districtId')) {
              _salonManageDistrictId = body['districtId'] as String?;
            }
            // `city`/`region` re-derived from the (possibly just-PATCHed)
            // `cityId` — backend Phase 328.
            return _ok(
              withSeededSalonLocality(<String, dynamic>{
                'id': 'salon-xyz',
                'name': _salonManageName,
                'description': salonDescription,
                'cityId': salonManageCityId,
                'oblastId': _salonManageOblastId,
                'districtId': _salonManageDistrictId,
                'street': (body['street'] as String?) ?? 'вул. Хрещатик',
                'buildingNo': (body['buildingNo'] as String?) ?? '12',
                'phone': salonPhone,
                'instagramUrl': salonInstagramUrl,
              }),
            );
          }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // DELETE /api/v1/salons/salon-xyz — owner-only salon deactivation
    // (Phase 21.2). Backend soft-deactivates; the fake counts the call and
    // lets a flow assert the wire request actually fired.
    //
    // mobile-qa gap-closure (2026-09-02) — on success this now ALSO removes
    // the matching row from [mySalons], so `GET /salons/mine` reflects the
    // deletion on the very next read. Before this fix the handler was a
    // pure counter: `mySalons` kept serving the "deleted" row forever, so
    // `salon_management_profile_flow_test.dart`'s post-delete-landing
    // assertion could not distinguish a correct resolver from a buggy one
    // that picked the just-deleted salon — the fixture always had a
    // DIFFERENT salon (`salon-owner-1`) marked primary, so the assertion
    // passed regardless of whether the delete actually took effect. Checked
    // before making this change: `deleteSalonCalls`/
    // `deleteSalonFailureStatusCode` are read by exactly one integration
    // file (`salon_management_profile_flow_test.dart`), and no other test
    // reads `mySalons` immediately after a delete call — nothing depends on
    // the old no-op behaviour.
    _adapter.onRoute(
      '/api/v1/salons/salon-xyz',
      (server) =>
          server.replyCallback(deleteSalonFailureStatusCode ?? 204, (_) {
            deleteSalonCalls++;
            if (deleteSalonFailureStatusCode != null) {
              return <String, dynamic>{
                'success': false,
                'data': null,
                'message': 'Failed to delete salon',
              };
            }
            mySalons.removeWhere(
              (Map<String, dynamic> s) => s['id'] == 'salon-xyz',
            );
            return null;
          }),
      request: const Request(method: RequestMethods.delete),
    );

    // POST /api/v1/salons/salon-xyz/invite — owner/admin staff-invite form
    // (Phase 21.4). See [_wireInviteStaff] / [forceInviteStaffFailure].
    _wireInviteStaff();
    // GET/DELETE /api/v1/salons/salon-xyz/invites/... — the Phase 21.11
    // invite history and its per-row cancel.
    // Registered AFTER the POST above so a future overlapping-prefix change
    // keeps the same insertion-order semantics the rest of this file relies
    // on; the three routes are disjoint today (POST /invite vs GET
    // /invites vs DELETE /invites/{id}).
    _wirePendingInvites();
    _wireCancelInvite();
    // GET /salons/salon-xyz/sibling-salons,
    // DELETE/PATCH /salons/salon-xyz/admins/{userId}[/salon] — Phase 21.6.
    _wireAdminManagement();

    // PATCH /api/v1/independent-masters/me — Phase 346 QA. The master
    // Location screen's `updateLocality`. Applied the way the real backend
    // applies it: `cityId` is written and `city` is its DENORMALISED mirror
    // (`MasterDetailResponse.city` — "a denormalised mirror of
    // cities.name_uk, written beside cityId"), resolved from
    // [kSeededSettlementNames] so it agrees with the `/settlements` rows. The
    // locality is a UNIT, so an omitted `districtId` clears it.
    _adapter.onRoute(
      '/api/v1/independent-masters/me',
      (server) => server.replyCallback(200, (req) {
        patchMasterLocalityCalls++;
        final body = _decodeBody(req.data);
        lastPatchMasterLocalityBody = body;
        final String? cityId = body['cityId'] as String?;
        masterCityId = cityId;
        masterCity = cityId == null ? null : kSeededSettlementNames[cityId];
        masterDistrictId = body['districtId'] as String?;
        if (body['street'] is String) masterStreet = body['street'] as String;
        if (body['buildingNo'] is String) {
          masterBuildingNo = body['buildingNo'] as String;
        }
        masterLocationNote = body['locationNote'] as String?;
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
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

    _wireSalonMasterServices();

    _wireSalonMasterAaaServices();

    _wireSalonMasterServicesBulk();

    _wireSalonAdminMasterServices();

    _wireSalonAdminMasterServicesBulk();

    // Phase 317 — the SHARED salon definitions (`PATCH /api/v1/services/
    // {defId}`) and the cascade that makes one master's definition write
    // visible on ANOTHER master's screen. Must run AFTER the three
    // per-master catalogues are wired: it enumerates their seeded
    // definition ids.
    _wireSalonSharedDefinitions();

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

    // DELETE /api/v1/services/{serviceDefId} — the REAL deactivate endpoint
    // (`deactivateServiceDefinition`, keyed on the service-DEFINITION id, NOT
    // the assignment id). Mobile phase 316 (mobile-qa, 2026-09-10): before
    // this, NO integration flow exercised service delete at all, so the
    // phase's central claim — "`DELETE /services/{id}` still fires unchanged
    // for a null target" — rested on unit tests alone.
    //
    // Registered per SEEDED definition id (the same per-service loop shape the
    // PATCH handlers above use) rather than as one catch-all, so a DELETE for
    // an id that was never seeded fails loudly as an unmatched route instead
    // of silently counting.
    //
    // Follows the `DELETE /salons/salon-xyz` precedent: count the call, record
    // the id, and MUTATE [_services] so the follow-up GET reflects the
    // deletion. Note the counter/removal run at DISPATCH time — the adapter
    // awaits [deleteServiceDelay] only AFTER this callback returns
    // (`dio_adapter.dart:59`) — which is what lets the double-tap flow assert
    // "exactly one DELETE" against a still-in-flight first one.
    for (final defId in <String>[
      for (final svc in _services)
        (svc['serviceDefinition'] as Map<String, dynamic>?)?['id'] as String? ??
            '',
    ]) {
      if (defId.isEmpty) continue;
      _adapter.onRoute(
        '/api/v1/services/$defId',
        (server) => server.replyCallback(204, (_) {
          deleteServiceCalls++;
          lastDeletedServiceDefId = defId;
          _services.removeWhere(
            (Map<String, dynamic> s) =>
                (s['serviceDefinition'] as Map<String, dynamic>?)?['id'] ==
                defId,
          );
          return null;
        }, delay: deleteServiceDelay),
        request: const Request(method: RequestMethods.delete),
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
      // Phase 312 (mobile-qa) — the two viewed-master ids the owner/admin
      // "edit a chosen master's schedule" E2E journeys drive: `master-aaa`
      // (salon-xyz roster) and `master-admin-target` (salon-admin-1 roster).
      '/api/v1/masters/master-aaa/weekly-schedules',
      '/api/v1/masters/master-admin-target/weekly-schedules',
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
      // Phase 312 (mobile-qa) — the two viewed-master ids the owner/admin
      // "edit a chosen master's schedule" E2E journeys drive: `master-aaa`
      // (salon-xyz roster) and `master-admin-target` (salon-admin-1 roster).
      '/api/v1/masters/master-aaa/weekly-schedules',
      '/api/v1/masters/master-admin-target/weekly-schedules',
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
      // Phase 312 (mobile-qa) — see the GET loop above for why these two.
      '/api/v1/masters/master-aaa/weekly-schedules/schedule-1',
      '/api/v1/masters/master-admin-target/weekly-schedules/schedule-1',
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
    for (final masterId in <String>[
      'me',
      'user-master-1',
      // Phase 312 (mobile-qa) — see the weekly-schedules GET loop's comment.
      'master-aaa',
      'master-admin-target',
    ]) {
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
    for (final masterId in <String>[
      'me',
      'user-master-1',
      // Phase 312 (mobile-qa) — see the weekly-schedules GET loop's comment.
      'master-aaa',
      'master-admin-target',
    ]) {
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
          // Phase 21.10 QA follow-up (salon_edit_forms_flow_test.dart) — the
          // ONLY seeded city with `hasDistricts: true` in this whole fixture
          // file. Needed to drive the locality-PAIR contract
          // (`SalonAddressEditScreen.saveAddress`'s per-field cityId/
          // districtId dirty-diff) against a REAL city that requires a
          // district, which city-kyiv/city-lviv above cannot exercise.
          <String, dynamic>{
            'id': 'city-with-districts',
            'oblastId': 'oblast-kyiv',
            'katotthCode': 'UA80000000000093318',
            'nameUk': 'Дніпро',
            'nameEn': 'Dnipro',
            'hasDistricts': true,
          },
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/settlements?query=… — Phase 346. The «Населений пункт»
    // autocomplete that REPLACED the Область → Місто cascade above. Shape:
    // SettlementSearchResponse { settlementId, nameUk, settlementType,
    // oblastNameUk, hromadaNameUk }.
    //
    // The ids deliberately MIRROR the cascade cities seeded above
    // (`city-kyiv`, `city-lviv`, `city-with-districts`), because the settlement
    // id IS the `cityId` every profile/salon write submits and the key the
    // `/locations/cities/{id}/districts` route below is registered under. A
    // flow that picks «Дніпро» here must therefore reach the SAME district
    // handler the cascade reached — that is what keeps the district half of
    // these flows honest after the swap.
    //
    // DioAdapter matches on the PATH only, so this one registration answers
    // every `query` value, including the blank pre-typing one. That is fine
    // for the flows: they pick by row key, and the row keys are stable ids.
    // `hromadaNameUk` is non-null on exactly one row so a flow can prove the
    // three-part disambiguating label renders, which is the only thing the
    // settlement rows do that the cascade rows could not.
    _adapter.onRoute(
      '/api/v1/settlements',
      (server) => server.replyCallback(200, (req) {
        // Phase 346 QA — records the `query` of every settlement search, so
        // a flow can pin that the TYPED term (and only the debounced one)
        // reached the wire. Recording only: the answer is unchanged.
        settlementQueries.add(
          _scalarQueryParam(req.queryParameters, 'query') ?? '',
        );
        return _okList(<Map<String, dynamic>>[
          <String, dynamic>{
            'settlementId': 'city-kyiv',
            'nameUk': 'Київ',
            'settlementType': 'CITY',
            'oblastNameUk': 'Київ',
            'hromadaNameUk': null,
          },
          <String, dynamic>{
            'settlementId': 'city-lviv',
            'nameUk': 'Львів',
            'settlementType': 'CITY',
            'oblastNameUk': 'Львівська',
            'hromadaNameUk': null,
          },
          <String, dynamic>{
            'settlementId': 'city-with-districts',
            'nameUk': 'Дніпро',
            'settlementType': 'CITY',
            'oblastNameUk': 'Дніпропетровська',
            'hromadaNameUk': null,
          },
          // The ambiguous class: a village whose name+oblast pair collides, so
          // the server populates the hromada and the client renders the
          // three-part label. No cascade row could express this at all.
          <String, dynamic>{
            'settlementId': 'village-ivanivka',
            'nameUk': 'Іванівка',
            'settlementType': 'VILLAGE',
            'oblastNameUk': 'Полтавська',
            'hromadaNameUk': 'Шишацька',
          },
        ]);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/locations/cities/{cityId}/districts — Phase 346. EVERY
    // settlement is asked this question now (the settlement search response
    // carries no `hasDistricts` flag), so the three that have no districts
    // need an explicit empty answer. Without it an unrouted GET would surface
    // as a failure instead of the "this settlement is a leaf" signal the
    // district row gates on.
    for (final String leafId in <String>[
      'city-kyiv',
      'city-lviv',
      'village-ivanivka',
    ]) {
      _adapter.onRoute(
        '/api/v1/locations/cities/$leafId/districts',
        (server) => server.reply(200, _okList(const <dynamic>[])),
        request: const Request(method: RequestMethods.get),
      );
    }

    // GET /api/v1/locations/cities/city-with-districts/districts — Phase
    // 21.10 QA follow-up. One seeded district so a flow can drive the REAL
    // district picker sheet. Shape: CityDistrictResponse { id, cityId,
    // katotthCode, nameUk, nameEn }.
    _adapter.onRoute(
      '/api/v1/locations/cities/city-with-districts/districts',
      (server) => server.reply(
        200,
        _okList(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'district-podil',
            'cityId': 'city-with-districts',
            'katotthCode': 'UA80000000000093319',
            'nameUk': 'Подільський район',
            'nameEn': 'Podilskyi district',
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
      // Phase 312 (mobile-qa) — see the weekly-schedules GET loop's comment.
      '/api/v1/masters/master-aaa/effective-schedule',
      '/api/v1/masters/master-admin-target/effective-schedule',
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
      // Phase 312 (mobile-qa) — see the weekly-schedules GET loop's comment.
      '/api/v1/masters/master-aaa/overrides',
      '/api/v1/masters/master-admin-target/overrides',
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
        final List<Map<String, dynamic>>? bulk = _searchMastersBulk;
        if (bulk != null) {
          const int pageSize = 20;
          final int from = (page < 0 ? 0 : page) * pageSize;
          final int to = (from + pageSize) > bulk.length
              ? bulk.length
              : from + pageSize;
          return _searchEnvelope(
            from >= bulk.length
                ? const <Map<String, dynamic>>[]
                : bulk.sublist(from, to),
            page: page < 0 ? 0 : page,
            totalPages: (bulk.length / pageSize).ceil(),
            totalElements: bulk.length,
          );
        }
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

    // GET /api/v1/search/suggestions?q=&limit=[&location.cityId=][&location
    // .districtId=] — Phase 352. Locality-aware: «Нарощення нігтів» (SERVICE,
    // category NAILS, slug `nail-extension`) is offered in settlement
    // `city-kyiv` and nationally (no place chosen); ABSENT for `city-lviv` —
    // this is what the integration flow's refetch-on-place-change step
    // proves. Keyed on `q` case/apostrophe-insensitively containing «нар»
    // (word-start), mirroring the real backend's D4 rules closely enough for
    // the flow; every other term returns an empty list.
    //
    // Additive (QA cycle, 2026-09-26): `q` containing «бров» echoes a
    // CATEGORY row (BROWS, «Брови») unconditionally (every place, including
    // national) — the same category the LOCAL matcher already renders
    // instantly from `/service-categories/approved`'s BROWS entry. Server and
    // local agreeing on this term is deliberate: it lets a CATEGORY-tap E2E
    // flow assert the row regardless of exactly when the debounce lands,
    // instead of racing a local row against a server answer that would
    // otherwise wipe it. Disjoint from the «нар» branch below — no term used
    // by any flow contains both substrings.
    _adapter.onRoute(
      '/api/v1/search/suggestions',
      (server) => server.replyCallback(200, (req) {
        searchSuggestionsCalls++;
        final Map<String, dynamic> reqJson = _decodeRequest(
          req.queryParameters,
        );
        final String q = (reqJson['q'] as String? ?? '').toLowerCase();
        final String? cityId = reqJson['location.cityId'] as String?;
        lastSearchSuggestionsQuery = reqJson['q'] as String?;
        lastSearchSuggestionsCityId = cityId;
        lastSearchSuggestionsDistrictId =
            reqJson['location.districtId'] as String?;

        if (q.contains('бров')) {
          return _okList(<Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'CATEGORY',
              'label': 'Брови',
              'categoryKey': 'BROWS',
            },
          ]);
        }

        if (!q.contains('нар')) return _okList(const <dynamic>[]);

        // Available in `city-kyiv` and nationally; absent in `city-lviv`.
        if (cityId == 'city-lviv') return _okList(const <dynamic>[]);
        return _okList(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'SERVICE',
            'label': 'Нарощення нігтів',
            'categoryKey': 'NAILS',
            'serviceTypeSlug': 'nail-extension',
          },
        ]);
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

    // GET /api/v1/favorites/masters and /salons — the two «Улюблені» feeds
    // (Phase 111). Registered BEFORE the bare `/api/v1/favorites` handlers for
    // the same reason `/favorites/services` is: DioAdapter matches on the PATH,
    // so the longer path must get first refusal.
    //
    // Without these the mock router 404s and the favourites branch renders its
    // ERROR surface — silently changing what every assertion on that tab
    // measures, exactly as the wish-list section did before its own route
    // existed.
    _wireListMasterFavorites();

    _adapter.onRoute(
      '/api/v1/favorites/salons',
      (server) => server.replyCallback(200, (_) {
        listSalonFavoritesCalls++;
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <String, dynamic>{
            'data': favoriteSalonRows,
            'page': 0,
            'size': 20,
            'totalElements': favoriteSalonRows.length,
            'totalPages': favoriteSalonRows.isEmpty ? 0 : 1,
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

    _wireBookingDetail();
    _wireSalonBoard();
    _wireSalonAdminBoard();
    _wireSalonMultiServiceWizard();

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

    _wireRescheduleBooking();

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
        // 2026-09-19 (mobile-qa) — the SALON-BOARD twin of the
        // `_bookingsDataset` mutation above, added for the same reason and
        // with the same shape. `GET /bookings/salon/{id}` reads
        // [salonBoardBookings] at REQUEST time, so without this the board's
        // very next fetch would still report `booking-1` as CONFIRMED and
        // `salon_owner_bookings_board_flow_test.dart`'s post-decline
        // invalidation guard could not tell "the board's cache never dropped"
        // (the regression) from "the fake never learned about the write".
        // Status-flip, not a row removal, because that is what the real
        // backend does — the board's own client-side day-list narrowing
        // (CANCELLED/DECLINED hidden by default, locked 2026-08-13) is what
        // must then take the card off screen.
        final int boardIdx = salonBoardBookings.indexWhere(
          (Map<String, dynamic> row) => row['id'] == 'booking-1',
        );
        if (boardIdx != -1) {
          salonBoardBookings[boardIdx] = <String, dynamic>{
            ...salonBoardBookings[boardIdx],
            'status': 'DECLINED',
          };
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
    //
    // 2026-08-18 (mobile-qa) — ALSO resets `awaitingClosure` to `false`.
    // `BookingDetailResponse.awaitingClosure`'s own doc defines it as
    // "Derived, read-time-only … TRUE when this booking's status is still
    // CONFIRMED but its endsAt has already elapsed" — i.e. the real backend
    // recomputes it on every read, so it can never stay `true` once the row
    // is COMPLETED. This fake previously left a seeded `awaitingClosure:
    // true` row unchanged across `/complete`, which does not reproduce that:
    // a fixture built with `awaitingClosure: true` to make the archive
    // card's «Виконано» slot render pre-completion would falsely keep
    // showing that same slot post-completion (`MasterBookingCard.
    // _buildFullBody`'s `showComplete` reads `b.awaitingClosure` directly,
    // not `b.status`), stacking it next to the newly-eligible «Відгук» slot
    // — the exact visual shape this whole fix chain exists to prevent, just
    // reproduced by fake-fidelity drift instead of a mapper/widget bug. See
    // `master_archive_review_flow_test.dart`'s scenario 9.
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
              'awaitingClosure': false,
            };
          }
        }
        // Phase 345 — the SAME mutation on the SALON archive list, for
        // exactly the reason the two paragraphs above give for the
        // `/bookings/me` dataset. The salon archive re-reads
        // `GET /bookings/salon/{id}?partition=HISTORY` after a close; without
        // this, that re-read would hand back the unchanged CONFIRMED row and
        // "the closed row left the «Підтверджено» filter" would be
        // unprovable at the salon host while passing at the master host —
        // a fake-fidelity divergence between two callers of one write.
        final int salonIdx = salonArchiveBookings.indexWhere(
          (Map<String, dynamic> row) => row['id'] == 'booking-1',
        );
        if (salonIdx != -1) {
          salonArchiveBookings[salonIdx] = <String, dynamic>{
            ...salonArchiveBookings[salonIdx],
            'status': 'COMPLETED',
            'awaitingClosure': false,
          };
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

    _wireClientReviews();
  }

  /// GET /api/v1/bookings/booking-1 — «Деталі запису» for the seeded booking.
  /// Concrete path (DioAdapter has no path-template matching); reflects the
  /// CURRENT mutable status/time so a post-cancel / post-reschedule re-open
  /// shows the new state.
  ///
  /// Split out of [_wire] into its own method so [bookingDetailFailStatus]'s
  /// setter can RE-REGISTER the route with a different status — see that field's
  /// doc for why a plain field cannot work. [getBookingDetailCalls] is bumped on
  /// BOTH branches: a flow proving a manual retry re-issues the request needs
  /// the failing replies counted too.
  // ── Phase 21.12 — the SALON «Записи» board ────────────────────────────────
  //
  // `GET /api/v1/bookings/salon/{salonId}` had NO registration in this file at
  // all before Phase 21.12's QA pass (verified by enumerating every
  // `_adapter.onRoute` path), and neither did `salon-owner-1`'s own
  // `/salons/{id}` / `/staff` / `/masters` reads — every existing salon
  // fixture is keyed to `salon-xyz` or `salon-admin-1`. So the owner's OWN
  // primary salon (the one `roleHomePath` lands them on, and therefore the one
  // the board actually mounts for) could not be served at all, and the board
  // was unreachable at the E2E tier.
  //
  // `DioAdapter.onRoute` matches the PATH ONLY — query params are ignored —
  // so one registration covers every day the rail navigates to. The handler
  // captures the query instead, which is what lets a flow assert the Kyiv day
  // window that went on the wire.

  /// The salon id these handlers serve — the id [mySalons] defaults its ONE
  /// primary salon to, i.e. the one an owner's `roleHomePath` lands on.
  static const String kOwnerSalonId = 'salon-owner-1';

  /// mobile-qa (phase 341) — the SALON_ADMIN's own salon (`_adminUserJson
  /// .salonId`), the id their `roleHomePath` lands on. A DIFFERENT id than
  /// [kOwnerSalonId] on purpose (see `_adminUserJson`'s own doc) — reused
  /// here, rather than re-declaring the literal a third time, so the Phase
  /// 341 multi-service wizard E2E arm can drive the SAME journey as either
  /// role against ITS OWN salon.
  static const String kAdminSalonId = 'salon-admin-1';

  /// `GET /api/v1/bookings/salon/{kOwnerSalonId}` call count.
  int getSalonBookingsCalls = 0;

  /// The raw query of the MOST RECENT salon-board fetch, as Dio sent it.
  /// The endpoint takes NO status/service predicate (the narrowing is
  /// client-side — see `bookings_day_query.dart`), so a flow can assert that
  /// nothing filter-shaped ever appears here.
  Map<String, dynamic>? lastSalonBookingsQuery;

  /// The rows `GET /bookings/salon/{id}` serves. Mutable and read at REQUEST
  /// time so a flow can reseed it between navigations.
  List<Map<String, dynamic>> salonBoardBookings = <Map<String, dynamic>>[];

  /// `GET /api/v1/salons/{kOwnerSalonId}/masters/effective-schedule` call
  /// count (Phase 335 — the board's roster-wide working-hours fetch).
  int getSalonRosterEffectiveScheduleCalls = 0;

  /// The rows that endpoint serves — a list of
  /// `SalonMasterEffectiveScheduleResponse` maps
  /// (`{masterId, days: [EffectiveDayResponse…]}`). EMPTY by default, which is
  /// every pre-existing flow's behaviour byte-for-byte: no master contributes
  /// a window, `SalonBookingsScreen.boardWindowFor` returns `null`, and the
  /// board's timeline stays on the booking-derived bounds it had before this
  /// phase. Read at REQUEST time so a flow can reseed between navigations.
  ///
  /// Query params (`from`/`to`) are ignored, same as every other route in this
  /// file — the whole seeded list comes back for any range requested.
  List<Map<String, dynamic>> salonRosterEffectiveSchedule =
      <Map<String, dynamic>>[];

  /// One `SalonMasterEffectiveScheduleResponse` entry: [masterId] working the
  /// given [intervals] on each of [dates].
  ///
  /// ROSTER-COMPLETENESS is the caller's to model: the real endpoint emits an
  /// entry for EVERY active master, including one with no schedule rows (pass
  /// `dayOff: true`, or an empty [dates] list). A flow that seeds only the
  /// masters it cares about is modelling a roster that small, not a partial
  /// response — the client cannot tell the difference and must not need to.
  static Map<String, dynamic> salonRosterScheduleEntry({
    required String masterId,
    required List<DateTime> dates,
    bool dayOff = false,
    List<(String start, String end)> intervals = const <(String, String)>[
      ('09:00:00', '18:00:00'),
    ],
  }) => <String, dynamic>{
    'masterId': masterId,
    'days': <Map<String, dynamic>>[
      for (final DateTime date in dates)
        seedEffectiveScheduleDay(date, dayOff: dayOff, intervals: intervals),
    ],
  };

  /// One salon-board row, in the same `BookingResponse` wire shape
  /// [datasetBookingRow] uses, but with the MASTER parameterised — which is
  /// the whole point of a salon-wide board and the one field
  /// `SalonBookingsScreen.columnsFor` partitions on.
  ///
  /// [providerCanReviewClient] and [awaitingClosure] are ADDITIVE (phase 345
  /// D3) and both default to the value every pre-345 caller already got
  /// (`false`), so no existing board fixture changes shape. They exist for the
  /// SALON ARCHIVE fixture, which must discriminate on axes a board row never
  /// needed:
  ///
  ///  * `providerCanReviewClient` — the archive's «Відгук» CTA is gated on the
  ///    SERVER FLAG, not on the viewer's role (phase 342 D7). A fixture whose
  ///    rows are uniformly `false` cannot tell a flag-gated CTA from a
  ///    role-gated one that happens to be off, so the 345 fixture carries BOTH
  ///    values. The hardcoded-`false` reasoning below still holds for every
  ///    row the BOARD serves; it is not a universal truth about the endpoint,
  ///    and an owner-as-master row (the owner performing the booking
  ///    themselves) genuinely comes back `true`.
  ///  * `awaitingClosure` — server-computed (backend phase 29.1/29.2);
  ///    `BookingMapper` reads `dto.awaitingClosure ?? false`, so a row that
  ///    omits it never trips «Виконано» however elapsed and CONFIRMED it is.
  ///    The elapsed-unclosed CONFIRMED row is D3's sharpest discriminator —
  ///    the ONE row `_legacyStatusesFor`'s status-only fallback structurally
  ///    cannot reach — so the archive fixture has to be able to build it.
  Map<String, dynamic> salonBoardBookingRow({
    required String id,
    required String masterId,
    required String masterFirstName,
    required String masterLastName,
    required DateTime startsAt,
    String status = 'CONFIRMED',
    Duration duration = const Duration(minutes: 60),
    String clientFirstName = 'Марія',
    String clientLastName = 'Іванюк',
    bool providerCanReviewClient = false,
    bool awaitingClosure = false,
  }) => <String, dynamic>{
    'id': id,
    'masterId': masterId,
    'masterFirstName': masterFirstName,
    'masterLastName': masterLastName,
    'masterAvatarUrl': null,
    'masterType': 'SALON_MASTER',
    'clientFirstName': clientFirstName,
    'clientLastName': clientLastName,
    'salonName': 'Салон Оксани',
    'masterServiceId': 'pub-assign-1',
    'serviceName': 'Манікюр',
    'categoryName': 'NAIL_SERVICE',
    'cityLabel': 'Київ',
    'districtLabel': 'Печерський',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'durationMinutesAtBooking': duration.inMinutes,
    'priceAtBooking': bookingPrice,
    'priceMaxAtBooking': null,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': startsAt.add(duration).toIso8601String(),
    'status': status,
    'canReview': false,
    // Phase 320 — HARDCODED `false`, and deliberately NOT parameterised. This
    // row is served to the salon board's SALON_OWNER/SALON_ADMIN viewer, who
    // by construction is not [masterId]. `BookingService`'s page-scoped form
    // of `computeProviderCanReviewClient` (backend `a0df4cf`) now answers on
    // `isPerformingMasterOfBooking(...)` alone, so `false` is the ONLY value
    // the real server can return for these rows. An owner-as-master board row
    // would need its own seeder that passes the owner's OWN master id.
    //
    // ⟶ Phase 345 D3: still true of every row the BOARD serves, which is why
    // the parameter defaults to `false`. The ARCHIVE fixture overrides it on
    // the owner-as-master rows — see the constructor doc above.
    'providerCanReviewClient': providerCanReviewClient,
    // Phase 345 D3 — see the constructor doc. `false` (the default) is
    // semantically identical to omitting the key, which is what every pre-345
    // board row did (`BookingMapper` reads `dto.awaitingClosure ?? false`).
    'awaitingClosure': awaitingClosure,
    'clientComment': null,
    'providerComment': null,
    'clientCancellationNote': null,
    'masterProfessionalTitle': 'Майстриня манікюру',
    'locationNote': null,
  };

  // ── Phase 345 — the SALON «Архів» read ────────────────────────────────────
  //
  // `GET /api/v1/bookings/salon/{salonId}` serves TWO DIFFERENT callers with
  // two disjoint query shapes, and before this phase the fake could not tell
  // them apart:
  //
  //   * the BOARD    — `from`/`to` (one Kyiv day), no `partition`;
  //   * the ARCHIVE  — `partition=HISTORY`, `sort`, `page`, no `from`/`to`
  //                    (`master_archive_notifier.dart`'s `_fetchPage` salon
  //                    arm).
  //
  // The pre-345 handler ignored BOTH shapes and returned the whole
  // [salonBoardBookings] list as a single page — which is exactly the D2
  // hazard: a fake that ignores `partition` makes every archive assertion
  // pass while the app could be sending anything at all, and it cannot model
  // the one row that distinguishes a real HISTORY read from the legacy
  // status-only approximation (an elapsed unclosed `CONFIRMED`).
  //
  // So the partition branch is served from its OWN list, with its OWN
  // counter. The separation is the discriminator: a handler that stopped
  // reading `partition` would serve the board's UPCOMING rows to the archive
  // and every D1/D3 assertion goes red.

  /// `GET /api/v1/bookings/salon/{id}` calls that carried a `partition` param
  /// — i.e. the ARCHIVE's reads, never the board's. Counted separately from
  /// [getSalonBookingsCalls] (which still counts EVERY call to the path, its
  /// documented meaning) so a flow can assert "exactly one archive fetch"
  /// without having to subtract the board's own traffic.
  int getSalonArchiveCalls = 0;

  /// The raw query of the most recent ARCHIVE fetch (the `partition`-carrying
  /// branch). Distinct from [lastSalonBookingsQuery], which is last-write-wins
  /// across BOTH shapes — a board refresh landing after the archive's fetch
  /// would silently retarget an assertion written against that field.
  Map<String, dynamic>? lastSalonArchiveQuery;

  /// The rows the ARCHIVE branch pages over. Mutable and read at REQUEST time,
  /// same contract as [salonBoardBookings].
  ///
  /// Deliberately a SEPARATE list from [salonBoardBookings]: the board shows
  /// one day of mostly-UPCOMING rows and the archive shows the salon's whole
  /// terminal history, so sharing one list would force every board fixture to
  /// double as an archive fixture and would make "the handler read
  /// `partition`" unobservable.
  List<Map<String, dynamic>> salonArchiveBookings = <Map<String, dynamic>>[];

  /// The ROSTER-SCALE salon-history fixture phase 345 D6 measures the
  /// `_MasterArchiveScreenState._kMaxAutoContinueAttempts` walk against, and
  /// phase 342 D10's reopen condition is evaluated against.
  ///
  /// Deterministic — no `DateTime.now()`, no randomness, no host-clock read.
  /// [anchor] is the caller's already-pinned "now" (`kFixedNow` in the E2E
  /// tier), and every row is derived from it, so the fixture clock and the app
  /// clock are the SAME clock (`project_test_clock_coherence_invariant`).
  ///
  /// ## Composition, and why these numbers
  ///
  /// [masters] masters × [days] days, one booking per master per day,
  /// newest-first. The outcome of row `i` (counting back from the most recent)
  /// comes from a fixed 50-row cycle:
  ///
  /// | Outcome | Per 50 | Share | Why |
  /// |---|---|---|---|
  /// | `COMPLETED` | 43 | 86 % | the overwhelming majority of a working salon's history |
  /// | `CANCELLED` | 2 | 4 % | client-initiated |
  /// | `DECLINED` | 1 | 2 % | provider-initiated, rarer than a client cancel |
  /// | `NOT_COMPLETED` | 2 | 4 % | no-shows |
  /// | elapsed unclosed `CONFIRMED` | 2 | 4 % | the closure backlog — D3's sharpest row |
  ///
  /// These are a MODEL, stated so the measurement can be re-read against a
  /// different one rather than presented as measured truth about real salons.
  /// What the measurement actually turns on is not the percentages but the
  /// LONGEST RUN of consecutive raw pages containing no row the active filter
  /// matches — which is why [leadingMatchlessDays] exists.
  ///
  /// [leadingMatchlessDays] prepends that many days of pure `COMPLETED` rows
  /// at the NEWEST end — a salon that simply has not cancelled anything
  /// recently. It is the one knob that can starve the walk, and it is how the
  /// exact budget boundary is probed rather than guessed.
  ///
  /// `providerCanReviewClient` is `true` on exactly the `COMPLETED` rows whose
  /// master is [ownerAsMasterId] (D3 axis 2: the owner performing their own
  /// booking is the one case the real backend answers `true` for), and `false`
  /// everywhere else.
  static List<Map<String, dynamic>> salonArchiveRosterScaleFixture(
    FakeBackend fb, {
    required DateTime anchor,
    int masters = 8,
    int days = 90,
    int leadingMatchlessDays = 0,
    String ownerAsMasterId = 'master-aaa',
  }) {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    final int totalDays = days + leadingMatchlessDays;
    int cycle = 0;
    for (int d = 0; d < totalDays; d++) {
      final bool inLeadingGap = d < leadingMatchlessDays;
      for (int m = 0; m < masters; m++) {
        // Two hours apart, so no two rows on one day share an instant and the
        // newest-first sort is total.
        final DateTime startsAt = anchor.subtract(
          Duration(days: d + 1, hours: m * 2),
        );
        final String status;
        final bool awaitingClosure;
        if (inLeadingGap) {
          status = 'COMPLETED';
          awaitingClosure = false;
        } else {
          final int i = cycle++;
          if (i % 25 == 7) {
            status = 'CANCELLED';
            awaitingClosure = false;
          } else if (i % 50 == 19) {
            status = 'DECLINED';
            awaitingClosure = false;
          } else if (i % 25 == 11) {
            status = 'NOT_COMPLETED';
            awaitingClosure = false;
          } else if (i % 25 == 23) {
            status = 'CONFIRMED';
            awaitingClosure = true;
          } else {
            status = 'COMPLETED';
            awaitingClosure = false;
          }
        }
        final String masterId = 'master-${String.fromCharCode(97 + m) * 3}';
        rows.add(
          fb.salonBoardBookingRow(
            id: 'arch-$d-$m',
            masterId: masterId,
            masterFirstName: _kRosterFirstNames[m % _kRosterFirstNames.length],
            masterLastName: _kRosterLastNames[m % _kRosterLastNames.length],
            startsAt: startsAt,
            status: status,
            awaitingClosure: awaitingClosure,
            providerCanReviewClient:
                status == 'COMPLETED' && masterId == ownerAsMasterId,
          ),
        );
      }
    }
    return rows;
  }

  /// Names for [salonArchiveRosterScaleFixture]'s roster. Ukrainian, and
  /// carrying no place data at all — the occupied-territory ban is absolute.
  static const List<String> _kRosterFirstNames = <String>[
    'Софія',
    'Олена',
    'Марія',
    'Ірина',
    'Наталія',
    'Дарина',
    'Катерина',
    'Оксана',
  ];

  static const List<String> _kRosterLastNames = <String>[
    'Бондар',
    'Ткаченко',
    'Гриценко',
    'Мельник',
    'Савченко',
    'Кравець',
    'Лисенко',
    'Полішук',
  ];

  /// The real (partition, sort, page) slice over [salonArchiveBookings] —
  /// the salon twin of [_slicedBookingsPageEnvelope], and deliberately built
  /// on the SAME [_matchesPartition] predicate so the two endpoints cannot
  /// drift on what `HISTORY` means.
  ///
  /// Implements backend phase 322 D2's precedence rule verbatim: when
  /// `partition` is present it wins OUTRIGHT and `status` is not consulted at
  /// all. That is what makes the archive's outcome filter client-side, and it
  /// is the rule the `_kMaxAutoContinueAttempts` walk exists to pay for — so a
  /// fake that honoured `status` here would hide the cost entirely.
  Map<String, dynamic> _slicedSalonArchiveEnvelope(Map<String, dynamic> query) {
    final String? partition = _scalarQueryParam(query, 'partition');
    final String sort = _scalarQueryParam(query, 'sort') ?? 'startsAt,desc';
    final bool ascending = sort.endsWith(',asc');
    final int page = _intQueryParam(query, 'page', 0);
    final int size = _intQueryParam(query, 'size', 20);
    final DateTime now = serverNow;
    // Honoured even though the archive never sends them — a fake that answers
    // a NARROWER question than it was asked is a divergence, and a fake that
    // answers a WIDER one is the same divergence in mirror image.
    final DateTime? fromDay = _dayWindowBound(query, 'from');
    final DateTime? toDay = _dayWindowBound(query, 'to');

    final List<Map<String, dynamic>> filtered =
        salonArchiveBookings
            .where(
              (Map<String, dynamic> b) =>
                  _withinDayWindow(b, fromDay, toDay) &&
                  (partition == null || _matchesPartition(b, partition, now)),
            )
            .map(Map<String, dynamic>.from)
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

  /// The ONE `GET /bookings/salon/{id}` handler body, shared by
  /// [kOwnerSalonId] and [kAdminSalonId] so the two registrations cannot
  /// disagree about which shape they are answering. Branches on `partition`
  /// exactly as the real backend's own `getSalonBookings` does.
  Map<String, dynamic> _salonBookingsReply(RequestOptions req) {
    getSalonBookingsCalls++;
    final Map<String, dynamic> query = Map<String, dynamic>.from(
      req.queryParameters,
    );
    lastSalonBookingsQuery = query;

    final String? partition = backendSupportsPartition
        ? _scalarQueryParam(query, 'partition')
        : null;
    if (partition != null) {
      getSalonArchiveCalls++;
      lastSalonArchiveQuery = query;
      return _slicedSalonArchiveEnvelope(query);
    }

    // The BOARD's own day fetch — byte-identical to the pre-345 handler.
    // A COPY read at REQUEST time; the list is mutable by design.
    final List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(
      salonBoardBookings.map(Map<String, dynamic>.from),
    );
    return _searchEnvelope(
      rows,
      page: 0,
      totalPages: 1,
      totalElements: rows.length,
    );
  }

  /// `GET /api/v1/bookings/salon/{kOwnerSalonId}/booked-days` call count
  /// (backend Phase 319 — the salon rail's dots).
  int salonBookedDaysCalls = 0;

  /// Kyiv date-only `yyyy-MM-dd` keys for walk-ins the salon wizard has
  /// POSTed during this run (mobile-qa PASS A, 2026-09-19).
  ///
  /// The two `/booked-days` handlers derive their answer from
  /// [salonBoardBookings], which a wizard POST does not touch — so before
  /// this field a created walk-in could never make a NEW day appear in the
  /// dot set, and any E2E assertion that "the rail gained its dot" would have
  /// been vacuous in BOTH directions (`project_fixture_values_can_defang_
  /// assertions`). The real backend obviously reports the day it just booked;
  /// the fake now does too.
  ///
  /// Kept separate from [salonBoardBookings] deliberately: unioning a day is
  /// all the dot set needs, and appending a synthetic row to the board's own
  /// list would silently change what every existing board assertion in this
  /// tier renders.
  final Set<String> createdWalkInDayKeys = <String>{};

  /// The raw query of the MOST RECENT salon booked-days call, as Dio sent it.
  /// Lets a flow assert the Kyiv-anchored ±`kBookedDaysSpanDays` window
  /// `salonBookedDaysProvider` (`booked_days_notifier.dart`) sends — and that
  /// nothing filter-shaped ever appears on it.
  Map<String, dynamic>? lastSalonBookedDaysQuery;

  void _wireSalonBoard() {
    // GET /api/v1/bookings/salon/{id}/booked-days?from=&to= — the dot set
    // behind the salon «Записи» day rail (backend Phase 319). Registered
    // BEFORE `/api/v1/bookings/salon/{id}` deliberately, for the same reason
    // `/me/booked-days` precedes `/me`: DioAdapter matches on the path, and
    // the longer path must get first refusal.
    //
    // Derived from [salonBoardBookings] at REQUEST time (that list is mutable
    // by design), so a dot can never point at a day the board itself renders
    // empty — the invariant the backend's own `getSalonBookedDays` javadoc
    // pins by reusing one query with no status predicate on either side.
    _adapter.onRoute(
      '/api/v1/bookings/salon/$kOwnerSalonId/booked-days',
      (server) => server.replyCallback(200, (req) {
        salonBookedDaysCalls++;
        lastSalonBookedDaysQuery = Map<String, dynamic>.from(
          req.queryParameters,
        );
        final Set<String> days = <String>{};
        for (final Map<String, dynamic> row in salonBoardBookings) {
          final Object? startsAt = row['startsAt'];
          if (startsAt is String && startsAt.length >= 10) {
            days.add(startsAt.substring(0, 10));
          }
        }
        // Walk-ins POSTed through the salon wizard during this run — see
        // [createdWalkInDayKeys]. A real server reports the day it just
        // booked; without this the dot set can never gain a day and a
        // post-create rail assertion is vacuous.
        days.addAll(createdWalkInDayKeys);
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': days.toList()..sort(),
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // The board's own day fetch — AND, since phase 345, the archive's
    // `partition=HISTORY` read. [_salonBookingsReply] branches; see its doc.
    _adapter.onRoute(
      '/api/v1/bookings/salon/$kOwnerSalonId',
      (server) => server.replyCallback(200, _salonBookingsReply),
      request: const Request(method: RequestMethods.get),
    );

    // The board's ROSTER — `salonMastersRosterProvider`. Serves the SAME
    // [_salonMasters] fixture the `salon-xyz` rail does, so a column header
    // rendered here and a rail card rendered there cannot disagree.
    _adapter.onRoute(
      '/api/v1/salons/$kOwnerSalonId/masters',
      (server) => server.replyCallback(200, (_) {
        getSalonMastersCalls++;
        lastGetSalonMastersId = kOwnerSalonId;
        return _searchEnvelope(
          _salonMasters,
          page: 0,
          totalPages: 1,
          totalElements: _salonMasters.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    // The board's WORKING-HOURS union (Phase 335) —
    // `salonEffectiveScheduleProvider`. Registered unconditionally so the
    // board's fetch never 404s into the silent-degradation path by accident;
    // it serves an EMPTY list unless [salonRosterEffectiveSchedule] is seeded,
    // which IS the degradation path and is what every pre-existing flow gets.
    //
    // MUST be its own registration: `DioAdapter.onRoute` matches the whole
    // path, so the `/masters` route above does NOT cover `/masters/
    // effective-schedule`.
    _adapter.onRoute(
      '/api/v1/salons/$kOwnerSalonId/masters/effective-schedule',
      (server) => server.replyCallback(200, (_) {
        getSalonRosterEffectiveScheduleCalls++;
        return _okList(salonRosterEffectiveSchedule);
      }),
      request: const Request(method: RequestMethods.get),
    );

    // The board's SUBTITLE — `salonManagementProfileProvider` `.wait`s these
    // two, so BOTH must answer or the subtitle stays null and the provider
    // parks in AsyncError.
    _adapter.onRoute(
      '/api/v1/salons/$kOwnerSalonId',
      (server) => server.replyCallback(200, (_) {
        getSalonByIdCalls++;
        lastGetSalonId = kOwnerSalonId;
        return _ok(<String, dynamic>{
          ...mySalons.first,
          'description': null,
          'phone': null,
          'instagramUrl': null,
          'districtId': null,
          'locationNote': null,
        });
      }),
      request: const Request(method: RequestMethods.get),
    );

    _adapter.onRoute(
      '/api/v1/salons/$kOwnerSalonId/staff',
      (server) => server.replyCallback(200, (_) {
        getSalonStaffCalls++;
        getSalonStaffCallsById.update(
          kOwnerSalonId,
          (int n) => n + 1,
          ifAbsent: () => 1,
        );
        lastGetSalonStaffId = kOwnerSalonId;
        return _okList(
          List<Map<String, dynamic>>.from(
            salonStaff.map(Map<String, dynamic>.from),
          ),
        );
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// mobile-qa (phase 341) — the board wiring [kAdminSalonId] never had.
  ///
  /// Every existing admin E2E flow (`salon_admin_edit_master_schedule_flow_
  /// test.dart`, `salon_management_profile_flow_test.dart`, …) reaches
  /// `/staff` (roster) or `/profile` — none of them ever opened the «Записи»
  /// tab, so `GET /bookings/salon/$kAdminSalonId` and its siblings were never
  /// registered. The Phase 341 E2E arm is the first admin flow to open that
  /// tab, so it needs the same four routes [_wireSalonBoard] already gives
  /// [kOwnerSalonId] — reusing the SAME backing fields ([salonBoardBookings],
  /// [_salonMasters], [salonRosterEffectiveSchedule]): a single `FakeBackend`
  /// instance only ever logs in as ONE role per test, so there is no risk of
  /// the two salon ids' board data disagreeing within one run.
  void _wireSalonAdminBoard() {
    _adapter.onRoute(
      '/api/v1/bookings/salon/$kAdminSalonId/booked-days',
      (server) => server.replyCallback(200, (req) {
        salonBookedDaysCalls++;
        lastSalonBookedDaysQuery = Map<String, dynamic>.from(
          req.queryParameters,
        );
        final Set<String> days = <String>{};
        for (final Map<String, dynamic> row in salonBoardBookings) {
          final Object? startsAt = row['startsAt'];
          if (startsAt is String && startsAt.length >= 10) {
            days.add(startsAt.substring(0, 10));
          }
        }
        // Walk-ins POSTed through the salon wizard during this run — see
        // [createdWalkInDayKeys]. A real server reports the day it just
        // booked; without this the dot set can never gain a day and a
        // post-create rail assertion is vacuous.
        days.addAll(createdWalkInDayKeys);
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': days.toList()..sort(),
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // The SAME shared body as [kOwnerSalonId]'s registration (phase 345) —
    // the two ids must not disagree about what `partition` means, and the
    // SALON_ADMIN walks the identical archive arm.
    _adapter.onRoute(
      '/api/v1/bookings/salon/$kAdminSalonId',
      (server) => server.replyCallback(200, _salonBookingsReply),
      request: const Request(method: RequestMethods.get),
    );

    _adapter.onRoute(
      '/api/v1/salons/$kAdminSalonId/masters',
      (server) => server.replyCallback(200, (_) {
        getSalonMastersCalls++;
        lastGetSalonMastersId = kAdminSalonId;
        return _searchEnvelope(
          _salonMasters,
          page: 0,
          totalPages: 1,
          totalElements: _salonMasters.length,
        );
      }),
      request: const Request(method: RequestMethods.get),
    );

    _adapter.onRoute(
      '/api/v1/salons/$kAdminSalonId/masters/effective-schedule',
      (server) => server.replyCallback(200, (_) {
        getSalonRosterEffectiveScheduleCalls++;
        return _okList(salonRosterEffectiveSchedule);
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  // ── Phase 341 (mobile-qa) — the SALON multi-service wizard's OWN
  // catalogue, coverage, and booking-create fixtures ────────────────────────
  //
  // Phases 335-340 widened `SalonCreateBookingScreen`'s `masters` step to
  // resolve an assignment id per SELECTED service (not just the first) and
  // `_submit` to send every one of them. Neither the client-facing `salon-
  // xyz` fixture (2 services, no "covers some but not all" master) nor
  // [kOwnerSalonId]'s own board fixture (no catalogue/coverage/create routes
  // at all, before this method) can prove the regression this track closes:
  // a master must be bookable ONLY if they cover EVERY selected service, and
  // the wire request must carry every one of them, in order.
  //
  // THREE services (not two) — a 2-service fixture cannot express "covers 2
  // of 3", the exact case an `any` filter would get wrong and `every`
  // (phase 335 D2) must get right.
  //
  // FOUR roster masters, reusing existing [_salonMasters] identities (no
  // new master rows minted, so the roster's own rendering/ordering tests
  // stay byte-identical):
  //   * [kSalonWizardMasterFull] (`master-aaa`) — covers ALL THREE and HAS
  //     free time on the picked day -> the one bookable tile.
  //   * [kSalonWizardMasterPartial] (`master-eee`) — covers TWO of three
  //     (svc A, B — NOT C) -> the DISCRIMINATING case: an `any` filter would
  //     still show this master as covering; `every` must exclude it
  //     (`project_fixture_values_can_defang_assertions` — an all-covering
  //     fixture could never catch the `any`→`every` regression this track
  //     fixes). 2026-09-18 real-device fix: a non-covering master is now
  //     HIDDEN outright (never rendered as a tile at all), not merely
  //     dimmed — see [SalonMastersStep]'s own header.
  //   * [kSalonWizardMasterNone] (`master-fff`) — covers NONE -> absent from
  //     every coverage response below, hidden for the ordinary reason.
  //   * [kSalonWizardMasterSlotless] (`master-ggg`, mobile-qa phase 341
  //     device-pass addition) — covers ALL THREE (same as `master-aaa`) but
  //     its OWN `/slots` route always answers an EMPTY list -> the THIRD
  //     tile state the 2026-09-18 device pass introduced: a covering master
  //     with genuinely zero free time renders DISABLED with «Немає вільного
  //     часу» rather than hidden or tappable. A second `/working-days`
  //     registration lets it also participate in the date step's covering-
  //     master fan-out (`_unionAvailability`) without ever confirming a day
  //     non-working on its own (its schedule-shape working-days answer is
  //     the ordinary wide-window "working every day" envelope — its slots,
  //     not its schedule shape, are what's empty).
  //
  // Registered for BOTH [kOwnerSalonId] and [kAdminSalonId] — the SAME
  // catalogue/coverage DATA under two different salon-scoped paths, mirroring
  // [_wireSalonBoard]'s own precedent of serving [_salonMasters] under both
  // `salon-xyz` and [kOwnerSalonId] — so the Phase 341 E2E arm can drive the
  // identical multi-service journey as either SALON_OWNER or SALON_ADMIN.
  //
  // Assignment ids are minted by [_bookableMasterEnvelope] as
  // `assign-$masterId-$serviceDefId` — DIFFERENT from the serviceDefId on
  // every entry (`wiz-svc-a` -> `assign-master-aaa-wiz-svc-a`), which is what
  // keeps the id-space pin (`SalonMastersStep.onPick`'s own doc — NEVER
  // `service.serviceDefId`) non-vacuous.
  static const String kSalonWizardMasterFull = 'master-aaa';
  static const String kSalonWizardMasterPartial = 'master-eee';
  static const String kSalonWizardMasterNone = 'master-fff';
  static const String kSalonWizardMasterSlotless = 'master-ggg';

  static const String kSalonWizSvcA = 'wiz-svc-a';
  static const String kSalonWizSvcB = 'wiz-svc-b';
  static const String kSalonWizSvcC = 'wiz-svc-c';

  /// Cyrillic service NAMES — kept as NAMED constants and never spelled
  /// inline inside a `find.text(...)` call site, so no call site ever
  /// carries a raw Cyrillic literal (`scripts/forbid_cyrillic_finder.sh`
  /// scans the call site's own text, not the constant's resolved value —
  /// same precedent as `master_create_booking_test.dart`'s `_kSvc1Name`).
  static const String kSalonWizSvcAName = 'Манікюр';
  static const String kSalonWizSvcBName = 'Брови';
  static const String kSalonWizSvcCName = 'Вії';

  /// `POST /api/v1/masters/$kSalonWizardMasterFull/bookings` call count —
  /// deliberately a SEPARATE counter from [createStaffBookingCalls]
  /// ([_wire]'s `$masterRowId`-keyed route): that route models an
  /// INDEPENDENT_MASTER booking THEMSELVES; this one models a
  /// SALON_OWNER/SALON_ADMIN booking a ROSTER master. Same backend
  /// operation, different caller shape — kept distinct so a count assertion
  /// here can never be satisfied by the other flow's traffic.
  int createSalonWizardBookingCalls = 0;

  /// The wire body of the MOST RECENT `POST …/$kSalonWizardMasterFull
  /// /bookings` call.
  Map<String, dynamic>? lastSalonWizardBookingRequestBody;

  List<Map<String, dynamic>> _salonWizardCatalog() => <Map<String, dynamic>>[
    <String, dynamic>{
      'category': 'NAILS',
      'count': 1,
      'services': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': kSalonWizSvcA,
          'name': kSalonWizSvcAName,
          'description': null,
          'category': 'NAILS',
          'serviceTypeSlug': null,
          'baseDurationMinutes': 60,
          'bufferMinutesAfter': 0,
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 400,
          'priceMax': null,
          'priceDisplay': '400 ₴',
          'photoUrl': null,
        },
      ],
    },
    <String, dynamic>{
      'category': 'BROWS',
      'count': 1,
      'services': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': kSalonWizSvcB,
          'name': kSalonWizSvcBName,
          'description': null,
          'category': 'BROWS',
          'serviceTypeSlug': null,
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
    <String, dynamic>{
      'category': 'LASHES',
      'count': 1,
      'services': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': kSalonWizSvcC,
          'name': kSalonWizSvcCName,
          'description': null,
          'category': 'LASHES',
          'serviceTypeSlug': null,
          'baseDurationMinutes': 90,
          'bufferMinutesAfter': 0,
          'isActive': true,
          'priceType': 'FIXED',
          'priceMin': 600,
          'priceMax': null,
          'priceDisplay': '600 ₴',
          'photoUrl': null,
        },
      ],
    },
  ];

  /// The per-service assignment-id lookup [_wireSalonMultiServiceWizard]'s
  /// coverage routes mint via [_bookableMasterEnvelope], reused here to
  /// resolve `POST …/bookings`'s `masterServiceIds` back to a
  /// name/duration/price for the response `items[]` — kept as ONE literal
  /// map (rather than re-deriving the `assign-$masterId-$serviceDefId`
  /// string twice) so the two can never drift apart.
  static const Map<String, Map<String, dynamic>> _kSalonWizardAssignments =
      <String, Map<String, dynamic>>{
        'assign-master-aaa-wiz-svc-a': <String, dynamic>{
          'name': kSalonWizSvcAName,
          'duration': 60,
          'priceMin': 400.0,
          'priceMax': null,
        },
        'assign-master-aaa-wiz-svc-b': <String, dynamic>{
          'name': kSalonWizSvcBName,
          'duration': 45,
          'priceMin': 300.0,
          'priceMax': null,
        },
        'assign-master-aaa-wiz-svc-c': <String, dynamic>{
          'name': kSalonWizSvcCName,
          'duration': 90,
          'priceMin': 600.0,
          'priceMax': null,
        },
      };

  void _wireSalonMultiServiceWizardCatalogFor(String salonId) {
    _adapter.onRoute(
      '/api/v1/salons/$salonId/services',
      (server) => server.replyCallback(
        200,
        // Same envelope shape as the `salon-xyz` catalogue route
        // (`{'categories': [...]}`, wrapped in `_ok`, NOT `_okList`) —
        // `SalonServiceCatalogMapper.fromDto` reads `.categories`.
        (_) => _ok(<String, dynamic>{'categories': _salonWizardCatalog()}),
      ),
      request: const Request(method: RequestMethods.get),
    );

    _adapter.onRoute(
      '/api/v1/salons/$salonId/services/$kSalonWizSvcA/masters',
      (server) => server.replyCallback(
        200,
        (_) => _okList(<Map<String, dynamic>>[
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterFull,
            serviceDefId: kSalonWizSvcA,
            firstName: 'Софія',
            lastName: 'Бондар',
          ),
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterPartial,
            serviceDefId: kSalonWizSvcA,
            firstName: 'Тетяна',
            lastName: 'Мельник',
          ),
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterSlotless,
            serviceDefId: kSalonWizSvcA,
            firstName: 'Юлія',
            lastName: 'Шевченко',
          ),
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );
    _adapter.onRoute(
      '/api/v1/salons/$salonId/services/$kSalonWizSvcB/masters',
      (server) => server.replyCallback(
        200,
        (_) => _okList(<Map<String, dynamic>>[
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterFull,
            serviceDefId: kSalonWizSvcB,
            firstName: 'Софія',
            lastName: 'Бондар',
          ),
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterPartial,
            serviceDefId: kSalonWizSvcB,
            firstName: 'Тетяна',
            lastName: 'Мельник',
          ),
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterSlotless,
            serviceDefId: kSalonWizSvcB,
            firstName: 'Юлія',
            lastName: 'Шевченко',
          ),
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );
    // svc C — the full-covering master AND the slotless master (both cover
    // ALL three). `master-eee` (partial) is absent here, on purpose: this is
    // what makes it "covers two of three".
    _adapter.onRoute(
      '/api/v1/salons/$salonId/services/$kSalonWizSvcC/masters',
      (server) => server.replyCallback(
        200,
        (_) => _okList(<Map<String, dynamic>>[
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterFull,
            serviceDefId: kSalonWizSvcC,
            firstName: 'Софія',
            lastName: 'Бондар',
          ),
          _bookableMasterEnvelope(
            masterId: kSalonWizardMasterSlotless,
            serviceDefId: kSalonWizSvcC,
            firstName: 'Юлія',
            lastName: 'Шевченко',
          ),
        ]),
      ),
      request: const Request(method: RequestMethods.get),
    );
  }

  void _wireSalonMultiServiceWizard() {
    _wireSalonMultiServiceWizardCatalogFor(kOwnerSalonId);
    _wireSalonMultiServiceWizardCatalogFor(kAdminSalonId);

    // `POST /api/v1/masters/$kSalonWizardMasterFull/bookings` — the salon
    // wizard's OWN submit, addressed at a ROSTER master (never
    // `$masterRowId` — see [createSalonWizardBookingCalls]'s own doc).
    // `salonId` is NEVER part of the wire body (phase 338 D2 — structurally
    // nowhere to put it), so ONE registration serves whichever of
    // [kOwnerSalonId]/[kAdminSalonId] the caller opened the wizard from.
    //
    // Reads the PLURAL `masterServiceIds` field — the exact regression this
    // whole track closes (`_submit` used to send a one-element list built
    // from `_primaryService` alone). A fake that silently accepted a
    // singular `masterServiceId` here would mask that regression completely
    // (phase 256's own pre-existing-defect note, cited again by phase 341
    // D2) — there is no such fallback below.
    _adapter.onRoute(
      '/api/v1/masters/$kSalonWizardMasterFull/bookings',
      (server) => server.replyCallback(201, (req) {
        createSalonWizardBookingCalls++;
        final Map<String, dynamic> body = _decodeBody(req.data);
        lastSalonWizardBookingRequestBody = body;
        final DateTime startsAt = DateTime.parse(body['startsAt'] as String);
        final Map<String, dynamic> guest = (body['guest'] as Map)
            .cast<String, dynamic>();
        final List<dynamic> serviceIds =
            (body['masterServiceIds'] as List?) ?? const <dynamic>[];
        // The Kyiv civil day this visit lands on — what the rail's dot set
        // must gain (see [createdWalkInDayKeys]). Derived from the instant
        // the wizard put on the WIRE, never from a host-clock read.
        final DateTime bookedKyivDay = kyivDayOf(startsAt);
        createdWalkInDayKeys.add(
          '${bookedKyivDay.year.toString().padLeft(4, '0')}-'
          '${bookedKyivDay.month.toString().padLeft(2, '0')}-'
          '${bookedKyivDay.day.toString().padLeft(2, '0')}',
        );

        const Duration itemBuffer = Duration(minutes: 10);
        DateTime cursor = startsAt;
        final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
        double totalPrice = 0;
        double totalPriceMaxSum = 0;
        bool anyRange = false;
        for (final dynamic rawId in serviceIds) {
          final String assignId = rawId as String;
          final Map<String, dynamic>? assignment =
              _kSalonWizardAssignments[assignId];
          if (assignment == null) {
            throw StateError(
              'FakeBackend: unknown salon-wizard masterServiceId '
              '"$assignId" — seed it in _kSalonWizardAssignments first',
            );
          }
          final int duration = assignment['duration'] as int;
          final double priceMin = assignment['priceMin'] as double;
          final double? priceMax = assignment['priceMax'] as double?;
          final DateTime itemStart = cursor;
          final DateTime itemEnd = itemStart.add(Duration(minutes: duration));
          items.add(<String, dynamic>{
            'bookingId': 'salon-wizard-booking-${items.length + 1}',
            'masterServiceId': assignId,
            'serviceName': assignment['name'],
            'status': 'CONFIRMED',
            'startsAt': itemStart.toIso8601String(),
            'endsAt': itemEnd.toIso8601String(),
            'durationMinutesAtBooking': duration,
            'priceAtBooking': priceMin,
            'priceMaxAtBooking': priceMax,
          });
          totalPrice += priceMin;
          totalPriceMaxSum += priceMax ?? priceMin;
          if (priceMax != null) anyRange = true;
          cursor = itemEnd.add(itemBuffer);
        }
        final DateTime visitEnd = items.isEmpty
            ? startsAt
            : cursor.subtract(itemBuffer);

        final Map<String, dynamic> row = <String, dynamic>{
          ...datasetBookingRow(
            id: 'salon-wizard-booking-1',
            status: 'CONFIRMED',
            startsAt: startsAt,
            duration: visitEnd.difference(startsAt),
          ),
          'masterServiceId': serviceIds.isNotEmpty ? serviceIds.first : null,
          'clientId': null,
          'clientFirstName': guest['name'],
          'clientLastName': guest['surname'],
          'endsAt': visitEnd.toIso8601String(),
          'totalDurationMinutes': visitEnd.difference(startsAt).inMinutes,
          'totalPrice': totalPrice,
          'totalPriceMax': anyRange ? totalPriceMaxSum : null,
          'items': items,
        };
        return _ok(row);
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );

    // `GET /api/v1/masters/$kSalonWizardMasterSlotless/slots` — mobile-qa
    // phase 341 device-pass addition. ALWAYS answers an empty slot list
    // (path-only route match, same caveat as every other `/slots`
    // registration in this file), regardless of the requested date/
    // serviceIds — this master's whole reason for existing in the fixture
    // is "covers everything, has nothing free", so there is no scenario in
    // this journey where it should ever answer non-empty.
    _adapter.onRoute(
      '/api/v1/masters/$kSalonWizardMasterSlotless/slots',
      (server) => server.replyCallback(200, (_) {
        getMasterSlotsCalls++;
        final DateTime day = kyivDayOf(serverNow);
        return _ok(<String, dynamic>{
          'date':
              '${day.year.toString().padLeft(4, '0')}-'
              '${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}',
          'slots': const <Map<String, dynamic>>[],
        });
      }),
      request: const Request(method: RequestMethods.get),
    );

    // `GET /api/v1/masters/$kSalonWizardMasterSlotless/working-days` — lets
    // this master also participate in `SalonDateStep`'s covering-master
    // fan-out (it covers all three wizard services, same as `master-aaa`)
    // without ever confirming a day non-working on its own: reuses the SAME
    // wide-window "working every day" envelope [_workingDaysEnvelope]
    // builds for `master-aaa` (including [forceNonWorkingDate], so a test
    // that forces a day off for the UNION check forces it off for BOTH
    // covering masters at once, proving the union rather than one master's
    // schedule alone). This master's SLOTS are what's empty, never its
    // schedule shape.
    _adapter.onRoute(
      '/api/v1/masters/$kSalonWizardMasterSlotless/working-days',
      (server) => server.replyCallback(200, (_) {
        getWorkingDaysCalls++;
        return _workingDaysEnvelope();
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  void _wireBookingDetail() {
    final int? failStatus = _bookingDetailFailStatus;
    _adapter.onRoute(
      '/api/v1/bookings/booking-1',
      (server) => server.replyCallback(failStatus ?? 200, (_) {
        getBookingDetailCalls++;
        if (failStatus != null) return _bookingNotFoundEnvelope();
        // THE detail endpoint — the only surface the real backend ever puts
        // `reviewByClient` on (phase 334).
        return _ok(_seededBookingJson(includeReviewByClient: true));
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  /// Error envelope for a failing single-booking fetch — the shape the backend's
  /// `GlobalExceptionHandler` emits for a `NotFoundException` (mirrors
  /// [_masterNotFoundEnvelope]). Used by [bookingDetailFailStatus].
  static Map<String, dynamic> _bookingNotFoundEnvelope() => <String, dynamic>{
    'success': false,
    'message': 'Booking not found',
    'data': null,
  };

  /// POST /api/v1/client-reviews — PROVIDER leave-client-feedback (track 7.x
  /// Wave B). Records the submitted bookingId/rating/comment and flips
  /// [bookingProviderCanReviewClient] false so a subsequent detail re-fetch
  /// (the screen invalidates `bookingDetailProvider` on success — the exact
  /// regression this flip exists to pin) re-resolves the provider footer's
  /// «Залишити відгук про клієнта» CTA away, mirroring `/api/v1/reviews`
  /// flipping [bookingCanReview]. The generated
  /// `ClientReviewControllerApi.create` deserializes an
  /// `ApiResponse<ClientReviewResponse>`; a `data: null` envelope is valid
  /// (every `ClientReviewResponse` field is nullable) and the repository
  /// returns void anyway.
  ///
  /// Split out of [_wire] into its own method so
  /// [clientReviewRejectDuplicate]'s setter can RE-REGISTER the route with a
  /// different status — see that field's doc for why a plain field cannot work.
  void _wireClientReviews() {
    _adapter.onRoute(
      '/api/v1/client-reviews',
      (server) =>
          server.replyCallback(_clientReviewRejectDuplicate ? 409 : 200, (req) {
            createClientReviewCalls++;
            final body = _decodeBody(req.data);
            lastClientReviewBookingId = body['bookingId'] as String?;
            lastClientReviewRating = body['rating'] as int?;
            lastClientReviewComment = body['comment'] as String?;
            if (_clientReviewRejectDuplicate) {
              // Deliberately does NOT flip [bookingProviderCanReviewClient].
              // The screen's 409 branch invalidates `bookingDetailProvider`,
              // so the refetch that follows still answers `true` — which means
              // the `_NotReviewable` state a flow then observes can ONLY have
              // come from the screen's own `_alreadyReviewed` flag, never from
              // a conveniently-agreeing server. Flipping it here would make
              // that assertion pass for the wrong reason.
              return _okVoid;
            }
            bookingProviderCanReviewClient = false;
            return _okVoid;
          }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
  }

  // ── Phase 365 — the in-app notification feed (`/api/v1/notifications`) ──────
  //
  // Four STATEFUL routes (list, unread-count, mark-one-read, mark-all-read) so
  // a flow can drive the REAL `HttpNotificationRepository` + generated
  // `NotificationsApi` + Dio stack with no repository override. Before this the
  // fake had no notification route at all, so every flow that mounts a header
  // with the live bell polled a missing route (closed backlog INFO).
  //
  // DEFAULT = ZERO UNREAD: nothing is seeded, `unread-count` answers 0 and the
  // feed answers an empty page, so every pre-existing flow behaves as before
  // (no dot). A flow seeds items with [seedNotification]; the unread count is
  // always DERIVED from the rows, never stored, so a mark-read moves it exactly
  // like the real backend.
  //
  // IDs: the mapper drops any `id` / target id that is not a UUID, so seeded
  // ids are UUID-shaped. [kNotificationBookingId] is the one booking a seeded
  // target can point at — the fake serves its detail (`GET /bookings/<it>`)
  // from the same seeded booking `booking-1` uses, with only the `id` swapped.

  /// UUID-shaped id of the booking the notification fixtures target; its
  /// `GET /api/v1/bookings/{id}` detail is served by [_wireNotifications].
  static const String kNotificationBookingId =
      '5a1f0000-0000-4000-8000-000000000001';

  final List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];

  /// Call counters + the ids / `upTo` the mutating routes received.
  int notificationFeedCalls = 0;
  int notificationUnreadCountCalls = 0;
  int notificationMarkAllCalls = 0;
  final List<String> notificationMarkedReadIds = <String>[];
  final List<String?> notificationMarkAllUpTo = <String?>[];

  /// Unread rows right now — what `GET /notifications/unread-count` answers
  /// (the backend caps it at 99; no flow seeds that many).
  int get unreadNotificationCount => _notifications
      .where((Map<String, dynamic> n) => n['read'] != true)
      .length;

  /// Seeds ONE notification row and returns its UUID-shaped id.
  ///
  /// [type] is the wire enum (`BOOKING_DECLINED`, `BOOKING_CREATED`,
  /// `INVITE_ACCEPTED`, …). [targetKind] defaults from the ids given: a
  /// [bookingId] -> `BOOKING`, a [salonId] alone -> `SALON_TEAM`, neither ->
  /// `NONE`. [age] is subtracted from [kFixedNow] (M15 — the one injected
  /// clock), so a larger age is an older row.
  String seedNotification({
    required String type,
    String? bookingId,
    String? salonId,
    String? targetKind,
    String? salonName,
    bool read = false,
    Duration age = const Duration(hours: 1),
  }) {
    final int n = _notifications.length + 1;
    final String id =
        '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
    final String kind =
        targetKind ??
        (bookingId != null
            ? 'BOOKING'
            : salonId != null
            ? 'SALON_TEAM'
            : 'NONE');
    _notifications.add(<String, dynamic>{
      'id': id,
      'type': type,
      'createdAt': kFixedNow.subtract(age).toUtc().toIso8601String(),
      'read': read,
      'target': <String, dynamic>{
        'kind': kind,
        'bookingId': ?bookingId,
        'salonId': ?salonId,
      },
      // Non-empty on purpose: an EMPTY params block on a booking item reads as
      // "the viewer lost access" (`isNotificationUnavailable`).
      'params': <String, dynamic>{
        'counterpartName': 'Client $n',
        'serviceName': 'Service $n',
        'startsAt': kFixedNow
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'salonName': ?salonName,
      },
    });
    _adapter.onRoute(
      '/api/v1/notifications/$id/read',
      (server) => server.replyCallback(200, (_) {
        notificationMarkedReadIds.add(id);
        _setNotificationRead((Map<String, dynamic> row) => row['id'] == id);
        return _okVoid;
      }),
      request: const Request(method: RequestMethods.patch),
    );
    return id;
  }

  void _setNotificationRead(bool Function(Map<String, dynamic> row) test) {
    for (final Map<String, dynamic> row in _notifications) {
      if (test(row)) row['read'] = true;
    }
  }

  void _wireNotifications() {
    // GET /api/v1/notifications?page&size — newest first, paged like the real
    // endpoint (`PageResponseNotificationResponse`).
    _adapter.onRoute(
      '/api/v1/notifications',
      (server) => server.replyCallback(200, (req) {
        notificationFeedCalls++;
        final int page = _intQueryParam(req.queryParameters, 'page', 0);
        final int size = _intQueryParam(req.queryParameters, 'size', 20);
        final List<Map<String, dynamic>> sorted =
            List<Map<String, dynamic>>.of(_notifications)..sort(
              (Map<String, dynamic> a, Map<String, dynamic> b) =>
                  (b['createdAt'] as String).compareTo(
                    a['createdAt'] as String,
                  ),
            );
        final int from = (page * size).clamp(0, sorted.length);
        final int to = (from + size).clamp(0, sorted.length);
        return <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': sorted.sublist(from, to),
          'page': page,
          'size': size,
          'totalElements': sorted.length,
          'totalPages': (sorted.length / size).ceil(),
        };
      }),
      request: const Request(method: RequestMethods.get),
    );

    // GET /api/v1/notifications/unread-count — derived from the rows.
    _adapter.onRoute(
      '/api/v1/notifications/unread-count',
      (server) => server.replyCallback(200, (_) {
        notificationUnreadCountCalls++;
        return _ok(<String, dynamic>{'count': unreadNotificationCount});
      }),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/notifications/read-all {upTo?} — marks every row created at
    // or before `upTo` (default: all) read and answers the number updated.
    _adapter.onRoute(
      '/api/v1/notifications/read-all',
      (server) => server.replyCallback(200, (req) {
        notificationMarkAllCalls++;
        final String? upToRaw = _decodeBody(req.data)['upTo'] as String?;
        notificationMarkAllUpTo.add(upToRaw);
        final DateTime? upTo = upToRaw == null ? null : DateTime.parse(upToRaw);
        int updated = 0;
        for (final Map<String, dynamic> row in _notifications) {
          final bool covered =
              upTo == null ||
              !DateTime.parse(row['createdAt'] as String).isAfter(upTo);
          if (row['read'] != true && covered) {
            row['read'] = true;
            updated++;
          }
        }
        return _ok(<String, dynamic>{'updated': updated});
      }),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    // GET /api/v1/bookings/<kNotificationBookingId> — the detail a notification
    // tap lands on. `booking-1`'s own route is keyed to that literal, and a
    // seeded target must be UUID-shaped, so this serves the same seeded booking
    // under the UUID.
    _adapter.onRoute(
      '/api/v1/bookings/$kNotificationBookingId',
      (server) => server.replyCallback(200, (_) {
        getBookingDetailCalls++;
        return _ok(<String, dynamic>{
          ..._seededBookingJson(includeReviewByClient: true),
          'id': kNotificationBookingId,
        });
      }),
      request: const Request(method: RequestMethods.get),
    );
  }

  // ── Phase 067 — FCM device-token registration (`/api/v1/devices/token`) ─────
  //
  // POST (register / rebind) and DELETE (unregister), both 204 with the body
  // `{token, platform?}`. Recorded in arrival order so a flow can assert the
  // user journey (register -> DELETE on logout -> re-register). The token is
  // test-fixture data here; production never logs it.

  /// Every device-token call, in order: `POST <token> <platform>` /
  /// `DELETE <token>`.
  final List<String> deviceTokenCalls = <String>[];

  /// Tokens POSTed (register), in order.
  List<String> get registeredDeviceTokens => <String>[
    for (final String c in deviceTokenCalls)
      if (c.startsWith('POST ')) c.split(' ')[1],
  ];

  /// Tokens DELETEd (unregister), in order.
  List<String> get unregisteredDeviceTokens => <String>[
    for (final String c in deviceTokenCalls)
      if (c.startsWith('DELETE ')) c.split(' ')[1],
  ];

  void _wireDeviceTokens() {
    _adapter.onRoute(
      '/api/v1/devices/token',
      (server) => server.replyCallback(204, (req) {
        final Map<String, dynamic> body = _decodeBody(req.data);
        deviceTokenCalls.add('POST ${body['token']} ${body['platform']}');
        return null;
      }),
      request: const Request(method: RequestMethods.post, data: Matchers.any),
    );
    _adapter.onRoute(
      '/api/v1/devices/token',
      (server) => server.replyCallback(204, (req) {
        final Map<String, dynamic> body = _decodeBody(req.data);
        deviceTokenCalls.add('DELETE ${body['token']}');
        return null;
      }),
      request: const Request(method: RequestMethods.delete, data: Matchers.any),
    );
  }

  /// Decodes an HTTP request body that may be a raw JSON String or a Map.
  static Map<String, dynamic> _decodeBody(dynamic data) {
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
