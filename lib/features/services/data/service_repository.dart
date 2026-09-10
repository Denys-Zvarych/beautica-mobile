// Phase 5.1 — ServiceRepository: interface, HTTP implementation, and provider.
//
// Wraps the generated [ServiceControllerApi] for the INDEPENDENT_MASTER service
// management surface:
//   - listMyServices()  → GET  /api/v1/independent-masters/me/services
//                          (Phase 16.9 — authenticated owner endpoint; derives
//                           the master from the JWT principal and INCLUDES
//                           drafts. The public GET /masters/{masterId}/services
//                           still exists for public-browse but is no longer
//                           used here because it filters drafts out.)
//   - getMyService(id)  → GET  /api/v1/independent-masters/me/services (filter by id;
//                          no single-resource endpoint exists in the current API)
//   - create(input)     → POST  /api/v1/independent-masters/me/services
//   - update(defId, …)  → PATCH /api/v1/services/{serviceDefId}
//                          (generated updateServiceDefinition; keyed on the
//                           service-definition id, NOT the assignment id)
//   - deactivate(defId) → DELETE /api/v1/services/{serviceDefId}
//                          (keyed on the service-definition id)
//
// The [masterId] required by [getMasterServices] is resolved from
// [masterProfileProvider] at provider construction time — this is the
// Master-row UUID (from MasterDetailResponse.masterId), NOT the User UUID
// from the auth session. User.id != Master.id; using the wrong UUID caused
// GET /api/v1/masters/{masterId}/services to always return [].
//
// All DioExceptions are mapped to typed [Failure] subclasses. No raw Dio
// types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'master_service_mapper.dart';
import 'service_type_mapper.dart';

part 'service_repository.g.dart';

/// Contract for the service management layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside
/// the implementation and never escape.
abstract interface class ServiceRepository {
  /// Returns the services of the current `serviceTarget` — the caller's own
  /// when the target is `null`.
  ///
  /// `null` target (every shipped call site today): wraps `GET
  /// /api/v1/independent-masters/me/services` — the authenticated owner
  /// endpoint, master derived from the JWT principal.
  ///
  /// [SalonMasterTarget] (phase 315 D1): wraps `GET
  /// /api/v1/salons/{salonId}/masters/{masterId}/services` — the same named
  /// master's services, as driven by that salon's OWNER/ADMIN. The dispatch
  /// lives INSIDE this method (`HttpServiceRepository._listForSalonMaster`)
  /// rather than as a parallel public method, so every existing caller
  /// (`ServicesList.build()`, `getMyService()`, `serviceByIdProvider`, …)
  /// retargets for free.
  ///
  /// Returns an empty list when the master has no services configured — but
  /// ONLY for a well-formed empty array. A 200 whose envelope carries a null
  /// `data` throws [ServerFailure]: a malformed success must never be
  /// presentable as an empty catalogue.
  Future<List<MasterService>> listMyServices();

  /// Returns a single service by its assignment [id].
  ///
  /// Fetches the full list and filters client-side (no single-resource
  /// endpoint in the current API). Throws [NotFoundFailure] when the
  /// requested [id] is absent from the list.
  Future<MasterService> getMyService(String id);

  /// Returns the active services for an arbitrary [masterId] (public browse).
  ///
  /// Wraps the PUBLIC `GET /api/v1/masters/{masterId}/services` endpoint (drafts
  /// are filtered out server-side). Unlike [listMyServices] this takes the
  /// target master as a parameter and does NOT require the caller to be that
  /// master, so it is safe to call from a CLIENT session — it drives the
  /// services stat tile and the read-only service-categories section on the
  /// client-facing public master profile (Phase 13.5).
  /// Returns an empty list when the master has no active services — but ONLY
  /// for a well-formed empty array; a 200 with a null `data` envelope throws
  /// [ServerFailure], exactly as [listMyServices] does.
  Future<List<MasterService>> getMasterServices(String masterId);

  /// Creates a new service for the authenticated master.
  ///
  /// Wraps `POST /api/v1/independent-masters/me/services`. Returns the
  /// newly-created [MasterService] as mapped from the backend response.
  Future<MasterService> create(MasterServiceCreate input);

  /// Creates ALL of [items] in one request for the current `serviceTarget` —
  /// the authenticated master's own catalogue when the target is `null`.
  ///
  /// `null` target (every shipped call site today): wraps `POST
  /// /api/v1/independent-masters/me/services/bulk` — the one-pass multi-select
  /// setup endpoint. **Additive** since `beautica-backend` c5e420f: callable
  /// whether or not the master already has a catalogue, so it backs both
  /// first-time setup and "add more services".
  ///
  /// [SalonMasterTarget] (phase 315 D2): wraps `POST
  /// /api/v1/salons/{salonId}/masters/{masterId}/services/bulk` — the same
  /// named master's catalogue, driven by that salon's OWNER/ADMIN. Only the
  /// path string differs; the request-body builder is shared verbatim between
  /// both branches (`BulkCreateServicesRequest` is the same DTO on both
  /// endpoints).
  ///
  /// Either way, the backend derives each service's name + category from its
  /// `serviceTypeId`, then persists the per-item duration + pricing block.
  /// Returns the list of newly-created [MasterService] records as mapped from
  /// the response (same envelope shape `listMyServices()` parses).
  ///
  /// All-or-nothing: if any item collides, the whole batch is rolled back and
  /// nothing is written.
  ///
  /// A generated `ServiceControllerApi.bulkCreateMasterServices` binding
  /// already exists for the salon path in today's committed snapshot, but
  /// swapping EITHER branch onto the generated client is explicitly deferred
  /// (phase 315 D2) — mixing "raw Dio on one branch, generated client on the
  /// other" would make the diff unreviewable and put two independent risks in
  /// one change. Both branches issue the POST via the raw authenticated [Dio]
  /// instance and deserialize the response with the same [standardSerializers]
  /// used by the generated client.
  ///
  /// Throws:
  ///   - [ServiceDuplicateFailure] on **409** (`data.code ==
  ///     "DUPLICATE_SERVICE"` — one item names a service the master already
  ///     offers; the batch was rolled back). Under a salon target this now
  ///     means "this master already performs it" — the SAME failure type, the
  ///     same "already in your menu" copy (phase 315 D4 — the existing handler
  ///     is inherited unchanged).
  ///   - [ServicePriceShapeMismatchFailure] on **400** (`data.code ==
  ///     "SERVICE_PRICE_SHAPE_MISMATCH"`, salon target only) — an item's price
  ///     shape cannot be represented on the salon's already-reused service
  ///     definition. Carries the salon's actual governing shape (phase 315 D3).
  ///   - [BulkSetupBusyFailure] on **503** (per-master lock held past the
  ///     backend's 3 s ceiling). Transient; safe to retry, nothing was written.
  ///   - [ValidationFailure] on **400/422** WITHOUT the price-shape-mismatch
  ///     code (malformed items, or a service-type id repeated within the
  ///     batch).
  ///   - [NetworkFailure] / [ServerFailure] on other transport errors.
  Future<List<MasterService>> bulkCreate(List<MasterServiceBulkItem> items);

  /// Partially updates an existing service identified by its
  /// service-definition id ([serviceDefId]).
  ///
  /// Wraps `PATCH /api/v1/services/{serviceDefId}`. [serviceDefId] MUST be
  /// [MasterService.serviceDefId] (the underlying service-definition UUID), NOT
  /// [MasterService.id] (the assignment UUID) — the backend keys this endpoint
  /// on the definition and a wrong id yields a 404 ("Запис не знайдено").
  ///
  /// Only fields present in [patch] (non-null) are sent; absent fields are left
  /// unchanged on the backend. [assignmentId] is carried through onto the
  /// returned [MasterService.id] (the PATCH response omits the assignment id).
  /// Returns the updated [MasterService].
  Future<MasterService> update(
    String serviceDefId,
    MasterServiceUpdate patch, {
    required String assignmentId,
  });

  /// Deactivates (soft-deletes) a service identified by its service-definition
  /// id ([serviceDefId]) — or, with a [SalonMasterTarget] in scope, unassigns
  /// ONE master from it (phase 316 D1).
  ///
  /// `null` target (every shipped call site today): wraps
  /// `DELETE /api/v1/services/{serviceDefId}`. [serviceDefId] MUST be
  /// [MasterService.serviceDefId] (the underlying service-definition UUID), NOT
  /// [MasterService.id] (the assignment UUID) — the backend keys this endpoint
  /// on the definition and a wrong id fails to resolve/authorise. The backend
  /// marks the *definition* inactive rather than removing it — every master in
  /// the salon (or the sole independent master) loses the service. Calling
  /// this method twice is idempotent — a 200 on either call resolves without
  /// throwing.
  ///
  /// [SalonMasterTarget] target: wraps
  /// `DELETE /api/v1/salons/{salonId}/masters/{masterId}/services/{serviceDefId}`
  /// (backend phase 307). Deactivates ONE `master_services` ROW — the shared
  /// definition and every OTHER master in the salon are untouched. This is the
  /// surgical operation the salon surface must use: after backend phase 302 a
  /// salon master's definitions are salon-owned and shared, so the null-target
  /// branch above would silently remove the service from the whole salon (and
  /// backend phase 306 admits `SALON_ADMIN` on that endpoint, so it would
  /// *succeed*). [serviceDefId] carries the same definition-id contract as the
  /// null-target branch — never the assignment id.
  ///
  /// Throws [ServiceUnassignBlockedFailure] on the salon branch's **409**: the
  /// master still has future CONFIRMED bookings for this service and nothing
  /// was written. This refusal is the shipping contract (backend phase 307
  /// D4) — there is no cascade-cancel follow-up.
  Future<void> deactivate(String serviceDefId);

  /// Returns the list of approved service categories for the picker.
  ///
  /// Wraps `GET /api/v1/service-categories/approved` (authenticated). Each
  /// option carries the wire [ServiceCategoryOption.name] (sent to the
  /// backend) and the Ukrainian [ServiceCategoryOption.displayName] (shown to
  /// the user). Returns an empty list when no categories are approved.
  Future<List<ServiceCategoryOption>> fetchApprovedCategories();

  /// Submits a request to add a new service category for admin review.
  ///
  /// Wraps `POST /api/v1/service-categories/requests` (authenticated;
  /// master/owner/admin only). The new category is created in a PENDING state
  /// and approved out-of-band by an admin — it does NOT immediately appear in
  /// [fetchApprovedCategories].
  ///
  /// - [name]: uppercase wire slug matching `^[A-Z][A-Z0-9_]*$` (≤50 chars).
  /// - [displayName]: non-blank Ukrainian label (≤100 chars).
  /// - [initialServiceName]: OPTIONAL free-text name of an initial service-type
  ///   the requester wants seeded under the new category (≤255 chars server-side;
  ///   the UI caps at 100). Sent only when non-null/non-empty.
  ///
  /// Throws:
  ///   - [CategoryAlreadyExistsFailure] on **409** (already exists/pending).
  ///   - [CategoryRequestThrottledFailure] on **429** (rate-limited, 5/hr).
  ///   - [ValidationFailure] on **400/422** (malformed name/displayName).
  Future<void> requestCategory({
    required String name,
    required String displayName,
    String? initialServiceName,
  });

  /// Returns the list of platform service types under [categoryName] for the
  /// second-level picker.
  ///
  /// Wraps `GET /api/v1/service-catalog/service-types?categoryName=...`
  /// (the slug-contract `PlatformServiceTypeResponse` branch). Each option
  /// carries the wire [ServiceTypeOption.slug] (persisted on the service) and
  /// the Ukrainian [ServiceTypeOption.nameUk] (shown to the user and used to
  /// pre-fill the service name).
  ///
  /// Degrades gracefully: an unknown category, an empty backend result, or a
  /// response that resolves to the legacy alternate branch all yield an **empty
  /// list** rather than throwing. Transport errors are mapped to the feature's
  /// typed [Failure] subclasses.
  Future<List<ServiceTypeOption>> fetchServiceTypes(String categoryName);

  /// Submits a suggestion for a new platform service type under [categoryName]
  /// for admin review.
  ///
  /// Wraps `POST /api/v1/service-types/suggest` (authenticated). The suggested
  /// type is created in a PENDING state and approved out-of-band by an admin —
  /// it does NOT immediately appear in [fetchServiceTypes].
  ///
  /// - [categoryName]: the System-B slug of the owning category (NOT a UUID).
  ///   This is the wire `categoryName` field per the backend 16.7 contract.
  /// - [name]: non-blank Ukrainian label for the suggested service type.
  /// - [description]: optional free-form context for the reviewer; omitted from
  ///   the request when null/empty.
  ///
  /// Throws:
  ///   - [ValidationFailure] on **400/422** (malformed name/description),
  ///     carrying any field errors keyed by `name` / `description`.
  ///   - [CategoryRequestThrottledFailure] on **429** (rate-limited).
  ///   - [ServerFailure] / [NetworkFailure] on other transport errors.
  Future<void> suggestServiceType({
    required String categoryName,
    required String name,
    String? description,
  });
}

/// HTTP implementation of [ServiceRepository].
///
/// Inject via [serviceRepositoryProvider] — never construct directly.
///
/// [_serviceApi] drives all generated-API calls (list/create/update/deactivate).
/// [_masterId] is resolved from the authenticated session at provider
/// construction time. As of Phase 16.9 it is no longer a path parameter (the
/// list/get/create/update/deactivate endpoints all derive the master from the
/// JWT principal); it is retained purely as a readiness guard — a non-empty
/// value means the master profile has resolved, so [_assertAuthenticated] can
/// fail fast before issuing a call on an unauthenticated session.
final class HttpServiceRepository implements ServiceRepository {
  HttpServiceRepository({
    required ServiceControllerApi serviceApi,
    required CategoryRequestControllerApi categoryApi,
    required ServiceCatalogControllerApi catalogApi,
    required Dio dio,
    required String masterId,
    this.target,
    String sessionUserId = '',
  }) : _serviceApi = serviceApi,
       _categoryApi = categoryApi,
       _catalogApi = catalogApi,
       _dio = dio,
       _masterId = masterId,
       _sessionUserId = sessionUserId;

  final ServiceControllerApi _serviceApi;
  final CategoryRequestControllerApi _categoryApi;
  final ServiceCatalogControllerApi _catalogApi;

  /// The raw authenticated [Dio] instance (full interceptor chain). Used ONLY
  /// for the bulk-setup POST, which the generated [ServiceControllerApi] does
  /// not yet expose. All other calls go through the generated client.
  final Dio _dio;
  final String _masterId;

  /// The signed-in principal's User UUID, or `''` when no session has resolved.
  ///
  /// This is the SESSION-READINESS evidence the salon arm of
  /// [_assertAuthenticated] needs, and it is deliberately NOT [_masterId]:
  /// in salon mode the acting user is a SALON_OWNER/SALON_ADMIN who has no
  /// master row at all, so [_masterId] is legitimately `''` there (D4 row 3)
  /// and carries no session information.
  ///
  /// Pre-phase-314 a non-empty [_masterId] implied `masterProfileProvider` had
  /// resolved, i.e. an authenticated session — the guard's stated purpose
  /// ("fail fast instead of firing a call that would 401 mid-flight"). The
  /// salon arm broke that implication by passing on two arbitrary non-empty
  /// strings; this field restores it (security LOW, phase 314 audit).
  ///
  /// Defaults to `''` — FAIL CLOSED. A direct construction that says nothing
  /// about the session is treated as "no session", so a caller must opt IN to
  /// salon mode by supplying the evidence. `serviceRepositoryProvider` is the
  /// only production constructor and supplies it from
  /// `authProvider.select(authUserIdOrNull)`; the narrowed selector is
  /// mandatory (a bare `ref.watch(authProvider)` renotifies on every silent
  /// token refresh — `authUserIdOrNull`'s doc, and
  /// `project_bare_auth_watch_destroys_state`).
  ///
  /// The User UUID, NOT the Master-row UUID — the two are different rows
  /// (User.id != Master.id) and this one is never sent on the wire.
  final String _sessionUserId;

  /// Whose services this repository operates on.
  ///
  /// `null` — the default and the value every shipped call site produces —
  /// means the authenticated INDEPENDENT_MASTER's own services, i.e. exactly
  /// today's behaviour. A [SalonMasterTarget] means a SALON_OWNER/SALON_ADMIN
  /// is driving a named master on their own salon's roster.
  ///
  /// Phase 314 stores this and consults it ONLY in [_assertAuthenticated]
  /// (D4). It drives NO path dispatch: reads and bulk are phase 315, delete is
  /// phase 316. A repository built with `target: null` is observationally
  /// identical to one built without the argument at all.
  ///
  /// Public (not `_`-prefixed) on purpose: `service_repository_provider_test`
  /// asserts on the value the provider threaded in, including the
  /// `ProviderScope` unwind case.
  final ServiceTarget? target;

  static const _tag = 'feature.services.repository';

  /// Readiness guard. Throws [UnauthorizedFailure] before any network call.
  ///
  /// Two arms, one per [target] state — [ServiceTarget] is sealed so the
  /// `switch` below is exhaustive and a third state cannot be added silently:
  ///
  ///   • `null` (independent master) — byte-identical to the pre-phase-314
  ///     check: throw when [_masterId] is empty. An empty masterId means the
  ///     master profile has not yet resolved (the auth session is not
  ///     [Authenticated]). The owner endpoints derive the master from the JWT
  ///     principal, so this is no longer about a missing path segment; it is a
  ///     readiness guard that surfaces the real cause to callers instead of
  ///     firing a call that would 401 mid-flight. THIS ARM IS THE ONE A
  ///     CARELESS "just make salon mode work" REFACTOR DELETES — it is pinned
  ///     by its own row in the `service_repository_test` D4 matrix.
  ///
  ///   • [SalonMasterTarget] — the acting user is an owner or admin who has no
  ///     master row of their own, so [_masterId] is LEGITIMATELY empty and the
  ///     arm above would reject every call. The readiness question is asked in
  ///     two halves instead: is there a SESSION at all ([_sessionUserId]
  ///     non-empty), and did the TARGET resolve (both `salonId` and `masterId`
  ///     non-empty)?
  ///
  ///     The session half is not decoration. Pre-314 the null arm's non-empty
  ///     [_masterId] implied `masterProfileProvider` had resolved, i.e. an
  ///     authenticated session; the salon arm as first written passed on any
  ///     two non-empty strings and lost that implication, so the guard no
  ///     longer did the one thing it claims to do. The backend still rejects
  ///     an unauthenticated call, so this is a READINESS guard, never an
  ///     authz gate — but it is the readiness guard's whole contract.
  ///     Pinned by `service_repository_provider_test`'s row 5, which is the
  ///     only place target and session actually meet.
  void _assertAuthenticated() {
    switch (target) {
      case null:
        if (_masterId.isEmpty) {
          throw const UnauthorizedFailure();
        }
      case SalonMasterTarget(:final salonId, :final masterId):
        if (_sessionUserId.isEmpty || salonId.isEmpty || masterId.isEmpty) {
          throw const UnauthorizedFailure();
        }
    }
  }

  /// Percent-encodes [value] so it lands as EXACTLY ONE path segment of a
  /// hand-built raw-[Dio] path, REJECTING any value that cannot be one.
  ///
  /// The single encoder for all three raw paths in this file
  /// ([_listForSalonMaster], [bulkCreate], [_unassignFromSalonMaster]) — those
  /// bypass the generated client's automatic encoding (see
  /// `api/lib/src/api/service_controller_api.dart`), so an id carrying a
  /// path-significant character would otherwise retarget the request on the
  /// authenticated [_dio] that holds the bearer token. One helper, three call
  /// sites: a fix here reaches every raw path at once.
  ///
  /// **Encoding alone is NOT sufficient, which is why this also rejects.**
  /// [Uri.encodeComponent] does not escape `.`, so a bare `..` or `.` survives
  /// it verbatim. Dio then issues the request as
  /// `Uri.parse(url).normalizePath()` (`dio-5.9.2/lib/src/options.dart:642`),
  /// and `normalizePath` REMOVES dot-segments per RFC 3986 §5.2.4. Measured,
  /// not assumed: with `masterId` and `serviceDefId` both `'..'`,
  /// `DELETE /api/v1/salons/S/masters/../services/..` collapses to
  /// `DELETE /api/v1/salons/S/` — one trailing slash away from the
  /// delete-the-whole-salon endpoint (`SalonController.java:208`). A single
  /// `'.'` deletes its own segment and shifts every later one left.
  ///
  /// REJECT rather than sanitise: these ids are server-issued UUIDs, so a
  /// dot-segment here is a PROGRAMMING error, not user input to be repaired.
  /// Silently rewriting a caller's id would send a well-formed request about
  /// the wrong resource, which is strictly worse than not sending one.
  ///
  /// Composite values that merely CONTAIN dot-segments (`a/../../b`) are safe
  /// and pass: the separators encode to `%2F`, and `normalizePath` splits on
  /// literal `/` only. Nor can encoding manufacture a dot-segment —
  /// [Uri.encodeComponent] emits `%2E` for no input (it never escapes `.`, and
  /// any literal `%` becomes `%25`), so Dart's unreserved-character
  /// normalization has nothing to decode back into `.`.
  ///
  /// Throws [UnknownFailure] wrapping an [ArgumentError]: unreachable in
  /// production (nothing constructs a [SalonMasterTarget] yet and the ids are
  /// UUIDs), non-transient in [failureRetryPolicy], and a [Failure] rather
  /// than a raw [ArgumentError] so the repository never leaks an unmapped
  /// error type past its boundary.
  static String _pathSegment(String value, String name) {
    final encoded = Uri.encodeComponent(value);
    // `encoded.contains('/')` cannot fire for encodeComponent (it escapes `/`
    // to `%2F`); it is kept so a future swap onto a laxer encoder — encodeFull
    // does NOT escape `/` — trips here instead of shipping a path split.
    if (encoded.isEmpty ||
        encoded == '.' ||
        encoded == '..' ||
        encoded.contains('/')) {
      if (kDebugMode) {
        log(
          '_pathSegment: refusing to build a path with $name="$value" — it is '
          'empty or a dot-segment that Dio\'s normalizePath() would collapse',
          name: _tag,
          level: 1000,
        );
      }
      throw UnknownFailure(
        cause: ArgumentError.value(
          value,
          name,
          'must be a single non-empty path segment (not "." or "..")',
        ),
      );
    }
    return encoded;
  }

  @override
  Future<List<MasterService>> listMyServices() async {
    _assertAuthenticated();
    // Phase 315 D1 — dispatch INSIDE this method rather than a parallel
    // public method: one seam, so every existing caller (ServicesList.build(),
    // getMyService(), serviceByIdProvider, …) retargets for free with no fork
    // to repeat at each call site.
    final t = target;
    if (t is SalonMasterTarget) {
      return _listForSalonMaster(t);
    }
    try {
      // The owner's own services list uses the authenticated endpoint
      // `GET /api/v1/independent-masters/me/services`, which derives the master
      // from the JWT principal (no masterId path param). The public
      // `GET /masters/{masterId}/services` endpoint stays available for any
      // public-browse use; this caller no longer touches it.
      final res = await _serviceApi.getMyServices();
      final list = res.data?.data;
      if (list == null) {
        // A 200 whose envelope carries no `data` array is a MALFORMED success,
        // not an empty catalogue. Collapsing it onto `const []` (as this used
        // to) rendered the "no services" em-dash for a response that in fact
        // failed to deliver anything — a stripped/garbled body was
        // indistinguishable from a master who genuinely has zero services.
        // Throwing routes it to the error path instead (`ServicesStatTile`
        // then shows its distinct '?' glyph rather than '—'). Matches the
        // same-shape guard the write endpoints in this file already apply.
        if (kDebugMode) {
          log(
            'listMyServices: ApiResponseListMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return list.map(MasterServiceMapper.fromDto).toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'listMyServices failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Salon-target counterpart of [listMyServices]'s try block above (phase 315
  /// D1): `GET /api/v1/salons/{salonId}/masters/{masterId}/services` — the
  /// named master's full services list (including drafts), as driven by that
  /// salon's OWNER/ADMIN.
  ///
  /// ⚠️ UNVERIFIED AGAINST A REAL BACKEND. Phase 315's Background section
  /// asserts this GET already exists in the committed snapshot alongside the
  /// bulk POST — that is NOT true: as of this writing, neither
  /// `beautica-backend@dev` nor `feat/salon-owned-master-services` declares
  /// any `@GetMapping` at this path (only the bulk-create POST and the
  /// per-master unassign DELETE exist at `/salons/{s}/masters/{m}/...`), and
  /// mobile phase 313's own "delta is one endpoint, not twelve" table lists
  /// only the DELETE as new. This method is implemented literally per the
  /// phase-315 D1 spec and is exercised only against a mocked Dio in tests;
  /// nothing in-app calls it yet (no salon UI exists before phase 318). Until
  /// a real GET lands at this path server-side, this call 404s. Flagged to the
  /// phase owner — do not remove this comment without confirming the endpoint
  /// is live.
  ///
  /// No generated binding exists for this exact path today — mirrors
  /// [bulkCreate]'s raw-`_dio.post` precedent (D2's reasoning applies equally
  /// here: no generated client method, so the raw authenticated [Dio] is used
  /// directly and the envelope is hand-parsed with the same
  /// [standardSerializers] deserializer [bulkCreate] uses). [t.masterId] is
  /// interpolated EXACTLY as given — no re-derivation from the session; this
  /// layer is a pass-through, and resolving a userId to a `masters` row id is
  /// phase 317's job, not this one's.
  Future<List<MasterService>> _listForSalonMaster(SalonMasterTarget t) async {
    // [t.salonId] / [t.masterId] go through the shared [_pathSegment] encoder,
    // which BOTH percent-encodes and rejects dot-segments — encoding alone is
    // not enough, see that method's doc. Deliberately OUTSIDE the `try`: its
    // [UnknownFailure] must reach the caller as-is, not be reshaped by the
    // handlers below. Encoding a well-formed UUID is a no-op.
    final salonId = _pathSegment(t.salonId, 'salonId');
    final masterId = _pathSegment(t.masterId, 'masterId');
    try {
      final res = await _dio.get<Object?>(
        '/api/v1/salons/$salonId/masters/$masterId/services',
      );
      final raw = res.data;
      final dataList = (raw is Map<String, Object?>) ? raw['data'] : null;
      if (dataList is! List) {
        // Same malformed-success guard as the null-target branch above: a 200
        // whose envelope carries no `data` array must never render as "this
        // master has zero services".
        if (kDebugMode) {
          log(
            '_listForSalonMaster(${t.salonId}, ${t.masterId}): response '
            '`data` is not a list (got ${dataList.runtimeType})',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return dataList
          .map((Object? element) {
            final dto = standardSerializers.deserializeWith(
              MasterServiceResponse.serializer,
              element,
            );
            if (dto == null) {
              throw const ServerFailure(statusCode: null);
            }
            return MasterServiceMapper.fromDto(dto);
          })
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          '_listForSalonMaster(${t.salonId}, ${t.masterId}) failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<MasterService> getMyService(String id) async {
    _assertAuthenticated();
    final services = await listMyServices();
    final match = services.where((s) => s.id == id).firstOrNull;
    if (match == null) {
      throw const NotFoundFailure();
    }
    return match;
  }

  @override
  Future<List<MasterService>> getMasterServices(String masterId) async {
    // No [_assertAuthenticated] gate: this hits the PUBLIC endpoint keyed on the
    // [masterId] PATH parameter (not the JWT principal), so it must work even
    // when [_masterId] is empty (the CLIENT-safe provider passes '').
    try {
      final res = await _serviceApi.getMasterServices(masterId: masterId);
      final list = res.data?.data;
      if (list == null) {
        // See [listMyServices] — a 200 with a null `data` envelope is a
        // malformed success, never an empty catalogue, so it must reach the
        // caller's error branch rather than render as "this master offers no
        // services". For the public profile this matters more, not less: the
        // silent-empty version showed a CLIENT a services-less master page
        // built from a response that never arrived.
        if (kDebugMode) {
          log(
            'getMasterServices($masterId): '
            'ApiResponseListMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return list.map(MasterServiceMapper.fromDto).toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterServices($masterId) failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<MasterService> create(MasterServiceCreate input) async {
    _assertAuthenticated();
    try {
      final request = MasterServiceMapper.toCreateRequest(input);
      final res = await _serviceApi.addIndependentMasterService(
        createServiceDefinitionRequest: request,
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'create: ApiResponseMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterServiceMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'create failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapServiceWriteException(e);
    }
  }

  @override
  Future<List<MasterService>> bulkCreate(
    List<MasterServiceBulkItem> items,
  ) async {
    _assertAuthenticated();
    if (items.isEmpty) return const [];

    // Build the wire body by hand: the generated client has no bulk operation,
    // so we serialise each item to the shape the backend expects. Mode-
    // conditional price fields are omitted (not null) when not applicable so the
    // backend receives only the relevant subset, mirroring the generated
    // serializer's null-omission behaviour.
    final body = <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final item in items) _bulkItemToJson(item),
      ],
    };

    // Phase 315 D2 — dispatch by PATH STRING ONLY. The body builder above is
    // shared verbatim between both branches (BulkCreateServicesRequest is the
    // same DTO on both endpoints), and the raw-_dio.post shape is unchanged —
    // swapping either branch onto the generated client is explicitly deferred
    // (see the interface doc comment).
    final t = target;
    // Same encode-AND-REJECT requirement as [_listForSalonMaster] — this raw
    // path also bypasses the generated client's automatic encoding, and
    // [Uri.encodeComponent] on its own lets a bare `..` through into Dio's
    // `normalizePath()`. Built before the `try` below, so [_pathSegment]'s
    // rejection propagates untouched by the DioException handlers.
    final path = t is SalonMasterTarget
        ? '/api/v1/salons/${_pathSegment(t.salonId, 'salonId')}/masters/'
              '${_pathSegment(t.masterId, 'masterId')}/services/bulk'
        : '/api/v1/independent-masters/me/services/bulk';

    try {
      // Path note: the generated client's relative paths all begin with
      // `/api/v1/...` (e.g. `r'/api/v1/independent-masters/me/services'`), and
      // `AppConfig.baseUrl` is normalised to NEVER carry the `/api/v1` prefix.
      // So the raw path MUST include `/api/v1` to match the generated calls —
      // omitting it would 404. (This is the inverse of the "double-prefix"
      // trap: here the prefix lives on the path, not the base URL.)
      final res = await _dio.post<Object?>(path, data: body);

      // The response envelope is ApiResponse<List<MasterServiceResponse>> — the
      // same shape `getMyServices()` parses. Deserialize each element with the
      // generated serializers, then map through the existing DTO→domain mapper.
      final raw = res.data;
      final dataList = (raw is Map<String, Object?>) ? raw['data'] : null;
      if (dataList is! List) {
        if (kDebugMode) {
          log(
            'bulkCreate: response `data` is not a list (got '
            '${dataList.runtimeType})',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return dataList
          .map((Object? element) {
            final dto = standardSerializers.deserializeWith(
              MasterServiceResponse.serializer,
              element,
            );
            if (dto == null) {
              throw const ServerFailure(statusCode: null);
            }
            return MasterServiceMapper.fromDto(dto);
          })
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'bulkCreate failed: ${e.type} ${e.response?.statusCode} '
          '(${items.length} items)',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapBulkCreateException(e);
    }
  }

  /// Serialises one [MasterServiceBulkItem] to the wire JSON the bulk endpoint
  /// expects, emitting only the mode-appropriate price fields.
  Map<String, Object?> _bulkItemToJson(MasterServiceBulkItem item) {
    final json = <String, Object?>{
      'serviceTypeId': item.serviceTypeId,
      'durationMinutes': item.durationMinutes,
      'priceType': switch (item.priceType) {
        ServicePriceType.fixed => 'FIXED',
        ServicePriceType.range => 'RANGE',
      },
    };
    switch (item.priceType) {
      case ServicePriceType.fixed:
        json['price'] = item.price;
      case ServicePriceType.range:
        json['priceMin'] = item.priceMin;
        json['priceMax'] = item.priceMax;
    }
    return json;
  }

  /// Maps a [DioException] from the bulk-setup POST to a typed [Failure].
  ///
  ///   - **409** → [ServiceDuplicateFailure]. Since `beautica-backend` c5e420f
  ///     made bulk create ADDITIVE, 409 on this endpoint means exactly ONE
  ///     thing: `data.code == DUPLICATE_SERVICE` — one item names a service the
  ///     master already offers. The whole batch is rolled back, so nothing was
  ///     written.
  ///   - **503** → [BulkSetupBusyFailure] (the per-master advisory lock was held
  ///     past the backend's 3 s ceiling). Transient and safe to retry.
  ///   - **429** → [ServiceRateLimitedFailure] (the per-master bulk bucket,
  ///     10/min, is exhausted). Reachable in ordinary use because the 503 branch
  ///     hands the master an explicit retry action.
  ///   - **400** with `data.code == "SERVICE_PRICE_SHAPE_MISMATCH"` (salon
  ///     target only) → [ServicePriceShapeMismatchFailure], carrying the
  ///     salon's governing shape (phase 315 D3). Discriminated on the typed
  ///     code, NEVER on the bare 400 — any other 400 on this path is an
  ///     ordinary validation failure and must keep mapping to
  ///     [ValidationFailure] below.
  ///   - **400/422** (any other body) → [ValidationFailure] (includes the
  ///     in-batch duplicate service-type-id case and the per-item
  ///     `items[i].field` errors).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// Both status checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached (it maps a non-auth 409 to a
  /// generic [ServerFailure] and a 503 to a generic 5xx [ServerFailure], neither
  /// of which carries the specific copy or the retry semantics), so we re-map by
  /// status code here.
  ///
  /// REMOVED (2026-08-04): the former `MasterAlreadyHasServicesFailure` branch
  /// for a non-`DUPLICATE_SERVICE` 409. That server condition — "bulk setup is
  /// only available for a master with no active services" — was DELETED
  /// backend-side when bulk create became additive. Keeping it as a defensive
  /// branch would have been actively harmful, not merely dead: it renders
  /// "you already have services" copy and routes the master AWAY from the screen
  /// without saving, so any future unrelated 409 would be mistranslated into a
  /// confident, wrong explanation plus a forced navigation. An unmodelled 409
  /// now falls through to the honest generic server error instead.
  Failure _mapBulkCreateException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409 && _isDuplicateService(e)) {
      // `serviceName` is null on the bulk envelope, so [ServiceDuplicateFailure]
      // renders its plain "already in your menu" message.
      return _extractDuplicateService(e);
    }
    // Phase 315 D3 — checked BEFORE the generic 400/422 → ValidationFailure
    // fallthrough in `_mapDioException`, and gated on the TYPED code, never on
    // the bare 400: any other 400 on this path must keep mapping to
    // ValidationFailure (pinned by a dedicated negative test).
    if (statusCode == 400 && _isPriceShapeMismatch(e)) {
      return _extractPriceShapeMismatch(e);
    }
    // Decoded by STATUS CODE alone — the 503 body is deliberately generic
    // (`data: null`, non-machine-readable `message`), and there is no
    // `Retry-After` header to honour.
    if (statusCode == 503) return BulkSetupBusyFailure(cause: e);
    // 429 must be re-mapped by STATUS CODE here for the same reason 409 and 503
    // are: the interceptor has no generic-429 branch, so an unmapped throttle
    // reaches `_mapDioException`'s `badResponse` default and becomes
    // `ServerFailure(statusCode: 429)` — the generic "server error, try again"
    // copy, which is the one instruction guaranteed to fail while the bucket is
    // closed.
    if (statusCode == 429) return _rateLimited(e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Builds a [ServiceRateLimitedFailure] from a 429, threading the server's
  /// `Retry-After` through so the copy can name the wait.
  ServiceRateLimitedFailure _rateLimited(DioException e) =>
      ServiceRateLimitedFailure(
        retryAfterSeconds: _extractRetryAfterSeconds(e),
        cause: e,
      );

  /// Parses the `Retry-After` response header (RFC 7231 §7.1.3, integer-seconds
  /// form only — the backend always emits an integer, never an HTTP-date).
  ///
  /// Returns `null` when the header is absent, unparsable, negative, or beyond
  /// [_maxUxCooldownSeconds]; the copy then drops the countdown and says "wait a
  /// moment" instead. The ceiling is a UX guard AND an overflow guard: a rogue
  /// or misconfigured backend sending `Retry-After: 999999999` must never render
  /// a multi-year wait. Mirrors `HttpScheduleRepository._extractRetryAfterSeconds`
  /// and `ErrorMapperInterceptor._extractRetryAfterSecondsNullable`.
  int? _extractRetryAfterSeconds(DioException e) {
    final raw = e.response?.headers.value('retry-after');
    if (raw == null) return null;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0 || parsed > _maxUxCooldownSeconds) {
      return null;
    }
    return parsed;
  }

  /// 10 min — above this a countdown stops being useful information.
  static const int _maxUxCooldownSeconds = 600;

  /// `true` when [e] is a 409 whose body is the
  /// `{ "data": { "code": "DUPLICATE_SERVICE" } }` envelope — the service is
  /// already in the master's menu (or a DB unique-index race caught a concurrent
  /// add). Hand-decoded from the raw JSON body (this code is not part of the
  /// generated client), mirroring
  /// `HttpAppointmentRepository._isDuplicateService`.
  bool _isDuplicateService(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'DUPLICATE_SERVICE';
  }

  /// Builds a [ServiceDuplicateFailure] from a 409 `DUPLICATE_SERVICE` body,
  /// threading through the two nullable diagnostic fields. Both `serviceName`
  /// (null on the bulk path) and `existingServiceDefId` (null on a DB
  /// unique-index race) are read defensively — a non-string value degrades to
  /// null so [ServiceDuplicateFailure.userMessage] still renders its plain copy.
  /// Precondition: [_isDuplicateService] returned `true` for [e].
  ServiceDuplicateFailure _extractDuplicateService(DioException e) {
    String? readString(Object? value) => value is String ? value : null;
    final body = e.response?.data;
    final data = (body is Map<String, dynamic>) ? body['data'] : null;
    final map = (data is Map<String, dynamic>)
        ? data
        : const <String, dynamic>{};
    return ServiceDuplicateFailure(
      serviceName: readString(map['serviceName']),
      existingServiceDefId: readString(map['existingServiceDefId']),
      cause: e,
    );
  }

  /// `true` when [e] is a 400 whose body is the
  /// `{ "data": { "code": "SERVICE_PRICE_SHAPE_MISMATCH" } }` envelope
  /// (phase 315 D3) — a batch item's price shape cannot be represented on the
  /// salon's already-reused service definition. Hand-decoded from the raw
  /// JSON body, mirroring [_isDuplicateService].
  bool _isPriceShapeMismatch(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'SERVICE_PRICE_SHAPE_MISMATCH';
  }

  /// Builds a [ServicePriceShapeMismatchFailure] from a 400
  /// `SERVICE_PRICE_SHAPE_MISMATCH` body, threading through the salon's
  /// governing shape. `salonPriceType` defaults to [ServicePriceType.fixed]
  /// only when the wire value is neither `"FIXED"` nor `"RANGE"` (a malformed
  /// body must still resolve to a value — the field is non-nullable on the
  /// failure). `salonPriceMin` / `salonPriceMax` are read defensively — a
  /// non-numeric value degrades to `null` rather than throwing.
  /// Precondition: [_isPriceShapeMismatch] returned `true` for [e].
  ServicePriceShapeMismatchFailure _extractPriceShapeMismatch(DioException e) {
    String? readString(Object? value) => value is String ? value : null;
    double? readDouble(Object? value) => switch (value) {
      num n => n.toDouble(),
      _ => null,
    };
    final body = e.response?.data;
    final data = (body is Map<String, dynamic>) ? body['data'] : null;
    final map = (data is Map<String, dynamic>)
        ? data
        : const <String, dynamic>{};
    final salonPriceType = switch (map['salonPriceType']) {
      'RANGE' => ServicePriceType.range,
      _ => ServicePriceType.fixed,
    };
    return ServicePriceShapeMismatchFailure(
      serviceName: readString(map['serviceName']),
      existingServiceDefId: readString(map['existingServiceDefId']),
      salonPriceType: salonPriceType,
      salonPriceMin: readDouble(map['salonPriceMin']),
      salonPriceMax: readDouble(map['salonPriceMax']),
      cause: e,
    );
  }

  /// Maps a [DioException] from a service-catalog WRITE (`create` / `update` /
  /// `deactivate`) to a typed [Failure], distinguishing the two statuses the
  /// generic mapping mistranslates:
  ///   - **409** with `data.code == "DUPLICATE_SERVICE"` →
  ///     [ServiceDuplicateFailure] (the service is already in the master's menu).
  ///   - **429** → [ServiceRateLimitedFailure] (the per-master single-write
  ///     bucket, 60/min, is exhausted).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// Both decodes run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached (it maps a non-auth 409 to a
  /// generic [ServerFailure] and has no 429 branch at all), so we hand-decode
  /// here to surface the friendly message — mirroring
  /// [_mapCategoryRequestException].
  Failure _mapServiceWriteException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409 && _isDuplicateService(e)) {
      return _extractDuplicateService(e);
    }
    if (statusCode == 429) return _rateLimited(e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  @override
  Future<MasterService> update(
    String serviceDefId,
    MasterServiceUpdate patch, {
    required String assignmentId,
  }) async {
    _assertAuthenticated();
    final request = MasterServiceMapper.toUpdateRequest(patch);
    try {
      // PATCH /api/v1/services/{serviceDefId} — the backend's update endpoint
      // keys on the service-definition id, NOT the assignment id. Uses the
      // generated client (UpdateServiceDefinitionRequest now exists after the
      // OpenAPI regen), so no hand-written Dio path is needed.
      final res = await _serviceApi.updateServiceDefinition(
        serviceDefId: serviceDefId,
        updateServiceDefinitionRequest: request,
      );
      // The update endpoint returns a ServiceDefinitionResponse (not a
      // MasterServiceResponse) — it carries no assignment id, so we thread the
      // original assignmentId through to keep MasterService.id stable.
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'update: response data is null for serviceDefId=$serviceDefId',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterServiceMapper.fromServiceDefinitionDto(
        dto,
        assignmentId: assignmentId,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'update failed: ${e.type} ${e.response?.statusCode} '
          'serviceDefId=$serviceDefId',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapServiceWriteException(e);
    }
  }

  @override
  Future<void> deactivate(String serviceDefId) async {
    _assertAuthenticated();
    // Phase 316 D1 — dispatch INSIDE this method rather than a parallel
    // public method or an `if (target != null)` at the call site: one seam,
    // so `service_edit_screen.dart`'s delete button retargets for free with
    // no fork to repeat there. Mirrors [listMyServices] / [bulkCreate].
    final t = target;
    if (t is SalonMasterTarget) {
      return _unassignFromSalonMaster(t, serviceDefId);
    }
    try {
      // DELETE /api/v1/services/{serviceDefId} — keyed on the service-definition
      // id, NOT the assignment id.
      await _serviceApi.deactivateServiceDefinition(serviceDefId: serviceDefId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'deactivate failed: ${e.type} ${e.response?.statusCode} '
          'serviceDefId=$serviceDefId',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      // Shares the write mapper with create/update: DELETE sits in the same
      // per-master 60/min write bucket, so an unmapped 429 here would render
      // the same wrong "server error" copy. The mapper's DUPLICATE_SERVICE
      // branch cannot fire on this endpoint (no such body), so routing through
      // it changes nothing else.
      throw _mapServiceWriteException(e);
    }
  }

  /// Unassigns [t.masterId] from the service identified by [serviceDefId] —
  /// the [SalonMasterTarget] arm of [deactivate] (phase 316 D1).
  ///
  /// Wraps
  /// `DELETE /api/v1/salons/{salonId}/masters/{masterId}/services/{serviceDefId}`
  /// (backend phase 307). Deactivates ONE `master_services` ROW — the shared
  /// service DEFINITION and every other master in the salon are untouched.
  /// This is the surgical counterpart to the null-target branch in
  /// [deactivate], which would instead deactivate the definition for the
  /// WHOLE salon (see this file's header and phase 316's "Why this is not
  /// optional").
  ///
  /// No generated binding exists for this exact path today — mirrors
  /// [_listForSalonMaster]'s and [bulkCreate]'s raw-`_dio` precedent: the
  /// `DELETE /salons/{s}/masters/{m}/services/{serviceDefId}` endpoint
  /// (backend phase 307) exists only on the unmerged
  /// `beautica-backend@feat/salon-owned-master-services` branch, so
  /// `ServiceControllerApi.unassignServiceFromMaster` — the binding phase
  /// 313's OpenAPI regen would generate — cannot be committed until that
  /// branch reaches `dev`. This method is implemented literally per phase
  /// 316's mandatory deviation and is exercised only against a mocked/faked
  /// Dio in tests; nothing in-app calls it yet (no salon UI exists before
  /// phase 317, which is BLOCKED on this method landing first).
  ///
  /// [serviceDefId] MUST be the service-DEFINITION id
  /// ([MasterService.serviceDefId]), NOT the assignment id
  /// ([MasterService.id]) — same contract [deactivate]'s null-target branch
  /// and [update] already carry. `service_edit_screen.dart:115-156` already
  /// passes `service.serviceDefId`, unchanged by this phase.
  Future<void> _unassignFromSalonMaster(
    SalonMasterTarget t,
    String serviceDefId,
  ) async {
    // [t.salonId] / [t.masterId] / [serviceDefId] ALL go through the shared
    // [_pathSegment] encoder — this raw path bypasses the generated client's
    // automatic encoding, so an id containing a path-significant character
    // (`/`, `?`, `#`) would otherwise silently retarget this DELETE on the
    // authenticated [_dio] instance, which carries the bearer token.
    //
    // Percent-encoding alone does NOT cover `..`/`.`: [Uri.encodeComponent]
    // leaves them verbatim and Dio's `normalizePath()` then collapses them —
    // `masters/../services/..` measurably degenerates to `/api/v1/salons/S/`,
    // adjacent to the delete-the-salon endpoint. [_pathSegment] REJECTS those
    // rather than sanitising; see its doc. This is why the comment that used
    // to sit here — claiming the encoding "neutralizes" `..` — was FALSE.
    //
    // [serviceDefId] is caller-supplied too (it flows from
    // `ServiceEditScreen`'s route argument), so it gets the same treatment as
    // the other two. Deliberately OUTSIDE the `try`: the rejection is a
    // programming error, not a transport fault, and must not be reshaped by
    // [_mapUnassignException]. Encoding a well-formed UUID is a no-op.
    final salonId = _pathSegment(t.salonId, 'salonId');
    final masterId = _pathSegment(t.masterId, 'masterId');
    final defId = _pathSegment(serviceDefId, 'serviceDefId');
    try {
      await _dio.delete<Object?>(
        '/api/v1/salons/$salonId/masters/$masterId/services/$defId',
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          '_unassignFromSalonMaster(${t.salonId}, ${t.masterId}, '
          '$serviceDefId) failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapUnassignException(e);
    }
  }

  /// Maps a [DioException] from [_unassignFromSalonMaster] to a typed
  /// [Failure] (phase 316 D2):
  ///   - **409** → [ServiceUnassignBlockedFailure] — future CONFIRMED
  ///     bookings block the unassign; nothing was written. No count is parsed
  ///     out of the body (D3 — it is a plain English `String`, not a
  ///     structured payload), so this check is on STATUS CODE ALONE, unlike
  ///     [_isDuplicateService] / [_isPriceShapeMismatch].
  ///   - **429** → [ServiceRateLimitedFailure] — shares the per-master
  ///     single-write bucket [_mapServiceWriteException] uses.
  ///   - **404** → falls through to [_mapDioException], which already maps it
  ///     to [NotFoundFailure] (no active assignment for this pair, backend
  ///     phase 307 D7 — typically a second tap after a first one raced with a
  ///     stale list). No special-casing needed here.
  ///   - **403** → falls through to [_mapDioException] with NO special
  ///     handling (D2): the route guard makes an unauthorised salon target
  ///     unreachable, and a repository that pretends otherwise would be lying
  ///     about its guarantees.
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// The 409/429 checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may already have attached (it maps a non-auth
  /// 409 to a generic [ServerFailure] and has no 429 branch at all), mirroring
  /// [_mapServiceWriteException] / [_mapBulkCreateException].
  Failure _mapUnassignException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) return const ServiceUnassignBlockedFailure();
    if (statusCode == 429) return _rateLimited(e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  @override
  Future<List<ServiceCategoryOption>> fetchApprovedCategories() async {
    try {
      final res = await _categoryApi.listApproved();
      final list = res.data?.data;
      if (list == null) {
        if (kDebugMode) {
          log(
            'fetchApprovedCategories: '
            'ApiResponseListApprovedCategoryResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        return const [];
      }
      return MasterServiceMapper.fromApprovedCategoryList(list);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'fetchApprovedCategories failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> requestCategory({
    required String name,
    required String displayName,
    String? initialServiceName,
  }) async {
    try {
      // The optional initial service name is attached only when
      // non-null/non-empty (mirrors the suggestServiceType description-omission
      // pattern); the generated model omits a null `initialServiceName` key.
      final initial = initialServiceName?.trim();
      final request = CreateCategoryRequestRequest(
        (b) => b
          ..name = name
          ..displayName = displayName
          ..initialServiceName = (initial == null || initial.isEmpty)
              ? null
              : initial,
      );
      await _categoryApi.submitRequest(createCategoryRequestRequest: request);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'requestCategory failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapCategoryRequestException(e);
    }
  }

  @override
  Future<List<ServiceTypeOption>> fetchServiceTypes(String categoryName) async {
    try {
      // The 200 response is now a single-shape
      // ApiResponseListPlatformServiceTypeResponse (the legacy oneOf alternate
      // was removed backend-side — the legacy operation is @Hidden). Read
      // `data` directly, mirroring [fetchApprovedCategories].
      final res = await _catalogApi.getServiceTypesByPlatformCategory(
        categoryName: categoryName,
      );
      final list = res.data?.data;
      if (list == null) {
        if (kDebugMode) {
          log(
            'fetchServiceTypes($categoryName): '
            'ApiResponseListPlatformServiceTypeResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        return const [];
      }
      return ServiceTypeMapper.fromDtoList(list);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'fetchServiceTypes($categoryName) failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> suggestServiceType({
    required String categoryName,
    required String name,
    String? description,
  }) async {
    try {
      // Sends the System-B `categoryName` slug (per backend 16.7) — NOT a
      // categoryId UUID. The generated SuggestServiceTypeRequest exposes
      // `name`, `categoryName`, and an optional `description`; the description
      // is only attached when non-null/non-empty (the serializer omits a null).
      final desc = description?.trim();
      final request = SuggestServiceTypeRequest(
        (b) => b
          ..name = name
          ..categoryName = categoryName
          ..description = (desc == null || desc.isEmpty) ? null : desc,
      );
      await _catalogApi.suggestServiceType(suggestServiceTypeRequest: request);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'suggestServiceType failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapServiceTypeSuggestionException(e);
    }
  }

  /// Maps a [DioException] from `POST /service-categories/requests` to a typed
  /// [Failure], distinguishing the two category-specific HTTP statuses:
  ///   - **409** → [CategoryAlreadyExistsFailure] (already exists/pending).
  ///   - **429** → [CategoryRequestThrottledFailure] (rate-limited, 5/hr).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// The 409/429 status checks run BEFORE deferring to any [Failure] already
  /// attached by [ErrorMapperInterceptor]. The interceptor maps a non-auth
  /// 409 to a generic [ServerFailure] and an unmatched 429 to
  /// [UnknownFailure] — neither of which carries the category-specific copy —
  /// so we re-map by status code here to surface the friendly messages.
  Failure _mapCategoryRequestException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) return CategoryAlreadyExistsFailure(cause: e);
    if (statusCode == 429) return CategoryRequestThrottledFailure(cause: e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Maps a [DioException] from `POST /service-types/suggest` to a typed
  /// [Failure]:
  ///   - **400/422** → [ValidationFailure] (malformed name/description). If
  ///     [ErrorMapperInterceptor] already attached a [ValidationFailure] (with
  ///     parsed field errors), that instance is preferred so inline field-level
  ///     messages survive.
  ///   - **429** → [CategoryRequestThrottledFailure] (rate-limited). Reuses the
  ///     existing throttle failure / copy shared with the category-request flow.
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// The status checks run BEFORE deferring to any [Failure] already attached by
  /// the interceptor for the 429 case (the interceptor maps an unmatched 429 to
  /// [UnknownFailure], which lacks the throttle copy), so we re-map by status
  /// code here to surface the friendly message.
  Failure _mapServiceTypeSuggestionException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 429) return CategoryRequestThrottledFailure(cause: e);
    // Prefer an interceptor-attached ValidationFailure (it carries the parsed
    // fieldErrors used for inline name/description messages).
    if (e.error is Failure) return e.error as Failure;
    if (statusCode == 400 || statusCode == 422) {
      return ValidationFailure(fieldErrors: const {}, cause: e);
    }
    return _mapDioException(e);
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`,
  /// that instance is re-thrown directly. Otherwise the Dio exception type and
  /// HTTP status code are inspected to produce the most appropriate subtype.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    final statusCode = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
        if (statusCode == 400 || statusCode == 422) {
          return ValidationFailure(fieldErrors: const {}, cause: e);
        }
        if (statusCode == 404) return NotFoundFailure(cause: e);
        return ServerFailure(statusCode: statusCode, cause: e);
      // A TLS / certificate-validation failure is a transport-layer security
      // problem, NOT a transient 5xx. Classifying it as a [ServerFailure] would
      // make a man-in-the-middle / broken-trust-chain error indistinguishable
      // from a retryable backend hiccup — the UI would invite the user to
      // "try again" against a connection that should not be trusted. Map it
      // alongside the connectivity failures ([NetworkFailure]) so it surfaces as
      // a connection problem and never looks like a recoverable server error.
      // (This only changes error CLASSIFICATION; certificate validation itself
      // is unchanged — it stays enforced by the Dio/HttpClient trust chain.)
      case DioExceptionType.badCertificate:
        return NetworkFailure(cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}

/// The retarget seam: whose services [serviceRepositoryProvider] operates on.
///
/// Returns `null` — the INDEPENDENT_MASTER's own services — everywhere except
/// inside the `ProviderScope` phase 317 wraps around the salon-target route
/// subtree, which overrides this with a [SalonMasterTarget].
///
/// It is a SEPARATE provider rather than a parameter on
/// [serviceRepositoryProvider] on purpose. That provider is `keepAlive: true`
/// and read from a dozen places; making it a `family` keyed by target would
/// change every one of those call sites, and a `keepAlive` family leaks one
/// repository instance per master forever. Watching an overridable value here
/// keeps every existing `ref.read(serviceRepositoryProvider)` byte-identical.
///
/// Override ONLY via `ProviderScope(overrides: [...])`. No notifier, no
/// setter, no `ref.read(...).state = ...`: the scope IS the widget subtree, so
/// it unwinds on pop. An imperative setter would leave the app pointed at a
/// master after the owner navigates away — the exact bug a `keepAlive` list
/// provider hides until someone reopens `/services` and sees a stranger's menu.
///
/// Phase 317 — declares `dependencies: []` explicitly. It is not required
/// (a provider with no watches of its own is scopable without it), but it is
/// declared as INTENT: this is the root of the scoped chain, and the four
/// `dependencies:` declarations below all point back here.
@Riverpod(keepAlive: true, dependencies: [])
ServiceTarget? serviceTarget(Ref ref) => null;

/// Provides the [ServiceRepository] singleton backed by the authenticated Dio,
/// the generated [ServiceControllerApi], and the current master's UUID from
/// [masterProfileProvider].
///
/// As of Phase 16.9 the owner list endpoint
/// (`GET /api/v1/independent-masters/me/services`) derives the master from the
/// JWT principal, so [_masterId] is no longer sent as a path parameter. It is
/// still watched here so the repository is re-created once the master profile
/// resolves and so [_assertAuthenticated] can fail fast on an unready session.
/// The value remains the Master-row UUID (from MasterDetailResponse.masterId),
/// NOT the User UUID — User.id != Master.id.
///
/// Both this provider and [masterProfileProvider] are [keepAlive: true], so
/// the watch is stable. The repository is re-created whenever the master
/// profile loads or changes (e.g. on first login after the profile resolves).
///
/// Override in tests with a mocktail mock — never construct
/// [HttpServiceRepository] directly in production or test code.
///
/// ⚠️ SCOPED-TARGET CONTRACT — READ BEFORE TOUCHING `dependencies:` BELOW.
/// (Historically the "PHASE 317 BLOCKER" comment. Phase 317 landed the
/// cascade on 2026-09-10; what follows is the resulting contract, not a
/// blocker.)
///
/// This provider declares `dependencies: [serviceTarget]`, which is what makes
/// a [serviceTargetProvider] override installed in a NESTED [ProviderScope]
/// actually reach it. Riverpod 3 only re-creates a provider in a child scope
/// when that provider — and every provider that watches it, transitively —
/// declares the scoped dependency, so the declaration CASCADES: every
/// dependent carries its own (`masterServiceCatalogProvider`,
/// `servicesListProvider`, `serviceByIdProvider`, `serviceTypesProvider`,
/// `serviceSetupProvider`). Removing any ONE of them silently re-roots that
/// branch of the chain in release AOT, because the guard assert
/// (`riverpod-3.1.0/.../element.dart:922`) is `kDebugMode`-gated and
/// `riverpod_lint` was removed on 2026-08-18. Do not drop a declaration
/// "because nothing complains".
///
/// ⛔ A ROOT-LEVEL OVERRIDE IS NOT AN OPTION — DO NOT SHIP ONE.
/// The phase-314 tests use one at ROOT because a unit test's
/// `ProviderContainer` IS the root and is disposed in `addTearDown`. That is a
/// test FIXTURE, never a pattern to copy into production code. A root override
/// is PROCESS-LIFETIME: it unwinds on nothing — not on `pop`, not on a tab
/// switch, not on logout — so an app that installs one stays pointed at a
/// named salon master until the process dies. It would therefore retain a
/// CROSS-TENANT [SalonMasterTarget] across navigation AND across a session
/// change: log out, log in as somebody else, open /services, and the previous
/// account's salon master's menu is what loads. Note that the auth-boundary
/// watches do NOT save you here — this provider rebuilds on an identity change
/// (`sessionUserId` below) and `servicesListProvider` does too
/// (`services_list_notifier.dart:127`), but a rebuild simply RE-READS the root
/// override and gets the same stale target back. Only a widget-subtree
/// `ProviderScope` unwinds. The one production installation is the
/// `ShellRoute` scope in `app_router.dart` (`_SalonMasterServicesScope`).
///
/// ⛔ OVERRIDING `serviceRepositoryProvider` ITSELF IS ALSO NOT AN OPTION —
/// MEASURED DEAD (2026-09-10). The escape hatch this comment used to offer as
/// option (b) does not work: the scope's own widgets get the right repository,
/// but `masterServiceCatalogProvider` and `servicesListProvider` — which have
/// no scoped dependency of their own under that scheme — still resolve against
/// the ROOT and still carry `target: null`. Bit-for-bit the same failure the
/// cascade exists to fix. It is additionally inert to auth flips
/// (`overrideWithValue` freezes the value, defeating the `sessionUserId` watch
/// below) and would mean hand-rebuilding all five [HttpServiceRepository]
/// constructor arguments in a route builder — a second copy of this function
/// body, free to drift.
///
/// BLAST RADIUS OF THE CASCADE, MEASURED — NOT the "68 existing tests go red"
/// this comment used to claim. Exactly ONE test flipped:
/// `service_repository_provider_test.dart`'s nested-scope case, which was
/// written to flip. Zero incidental reds across `test/routing/`, `test/core/`,
/// `test/features/services|salon|master|booking/`, `test/golden/` and the two
/// service integration flows. Root reads, root `overrideWithValue(mock)` in
/// tests, `autoDispose` families, and unrelated nested `ProviderScope`s in
/// pump helpers are all unaffected — a nested scope that overrides nothing on
/// this chain does not fork it.
///
/// The auth-boundary half is DONE and independent of scoping:
/// [serviceRepositoryProvider] rebuilds on an identity change via the
/// `sessionUserId` watch below, `masterServiceCatalogProvider` via its own
/// (`master_service_catalog_provider.dart:162`), and `servicesListProvider`
/// via `services_list_notifier.dart:127`, which it needs independently because
/// the `.future` edge it reads coalesces. Under the cascade there is no
/// repository override at all — the scoped element is a genuine build of THIS
/// function body watching the ROOT `authProvider` — so scoping does not defeat
/// any of them.
///
/// The seam is no longer inert: `app_router.dart`\'s `_SalonMasterServicesShell`
/// constructs a [SalonMasterTarget] for the
/// `/salons/:salonId/manage/staff/:memberId/services**` subtree. Every OTHER
/// call site still resolves the root `null` target and is byte-identical to
/// its pre-phase-314 behaviour.
@Riverpod(keepAlive: true, dependencies: [serviceTarget])
ServiceRepository serviceRepository(Ref ref) {
  // masterId is the Master-row UUID (from MasterDetailResponse.masterId),
  // NOT the User UUID from the auth session. User.id != Master.id.
  // AsyncValue.value returns null when loading/error; ?? '' keeps the
  // _assertAuthenticated() guard intact until the profile resolves.
  // masterProfileProvider is also keepAlive: true, so this watch is stable.
  //
  // NARROWED to the id with `.select`, exactly as the `sessionUserId` line
  // below is narrowed via [authUserIdOrNull]. A bare
  // `ref.watch(masterProfileProvider)` renotifies on EVERY AsyncValue
  // transition — including the retained-value `Loading → Data` an invalidate
  // or a refresh produces — rebuilding this keepAlive repository and
  // cascading a refetch through `master_service_catalog_provider.dart:162`
  // (which since N2 is the app's only `listMyServices()` in a `build`, and
  // republishes to `servicesListProvider` from there)
  // (`project_riverpod_seamless_invalidate_gotcha`). The readiness contract
  // is UNCHANGED and still pinned: the selected String goes '' → masterId the
  // moment the profile resolves, which is a real value change, so the
  // repository is still rebuilt exactly once at that boundary
  // (`service_repository_provider_test`, `service_by_id_readiness_test`).
  // What is dropped is only the churn where the id did not move.
  //
  // ⚠️ CONDITIONAL ON PURPOSE — the watch happens ONLY on the null-target
  // (independent-master) arm. Under a [SalonMasterTarget] the acting user is
  // an owner or an admin and `_masterId` is PROVABLY UNUSED: it is read in
  // exactly one place, [_assertAuthenticated]'s `case null` arm (`:393`), and
  // the salon arm reads only `_sessionUserId` and `target`. Watching it
  // anyway costs two things, both measured:
  //
  //   • SECURITY/CORRECTNESS — `masterProfileProvider` fires
  //     `GET /masters/me`, which `MasterController`'s `@PreAuthorize`
  //     REFUSES for a SALON_ADMIN. Phase 317 admits SALON_ADMIN to the
  //     salon-target services subtree, so an unconditional watch is a
  //     GUARANTEED 403 — retried ~4× by `beauticaProviderRetry` — with the
  //     operator's bearer token, on every entry into the subtree.
  //   • PERF — for an owner who IS a master, the `'' → masterId` transition
  //     is a real value change that rebuilds this keepAlive repository, which
  //     refires `masterServiceCatalogProvider` and costs a SECOND
  //     `GET /salons/S/masters/M/services` plus an `AsyncLoading` flash.
  //
  // This is the exact hazard phase 312 identified and removed from the
  // SCHEDULE seam — see `schedule_repository_provider.dart:1-16`, which
  // documents the same 403 and the same remedy. The services seam
  // re-introduced it in phase 317 and this restores parity.
  //
  // A conditional `ref.watch` is legal riverpod: dependencies are recollected
  // on every build, and a dependency dropped between builds is unsubscribed.
  // The null-target path is BYTE-IDENTICAL to before (same select, same
  // `?? ''`), which the untouched `service_repository_provider_test` and
  // `service_by_id_readiness_test` readiness rows pin.
  final ServiceTarget? target = ref.watch(serviceTargetProvider);
  final String masterId = target == null
      ? ref.watch(
          masterProfileProvider.select((profile) => profile.value?.id ?? ''),
        )
      : '';
  return HttpServiceRepository(
    serviceApi: ref.watch(serviceApiProvider),
    categoryApi: ref.watch(categoryRequestApiProvider),
    catalogApi: ref.watch(serviceCatalogApiProvider),
    // Raw authenticated Dio (full interceptor chain) for the bulk-setup POST,
    // which the generated ServiceControllerApi does not yet expose.
    dio: ref.watch(dioProvider),
    masterId: masterId,
    // Phase 314 — the retarget seam. `null` outside phase 317's ProviderScope,
    // so on every call site but the salon subtree this argument changes
    // nothing. Hoisted above (it now also gates the `masterProfileProvider`
    // watch); still a `ref.watch`, still the same single dependency edge.
    target: target,
    // Session-readiness evidence for the salon arm of _assertAuthenticated.
    // NARROWED to the signed-in identity on purpose: a bare
    // `ref.watch(authProvider)` renotifies on every silent token refresh
    // (`refresh_interceptor.dart` → `AuthNotifier.setAccessToken`), which
    // would churn this keepAlive repository — see [authUserIdOrNull]'s doc and
    // `project_bare_auth_watch_destroys_state`.
    //
    // ⚠️ CORRECTED (audit cycle 2, item C). This line used to claim it added
    // "NO new dependency edge" because `masterProfileProvider` — watched above
    // — watches `authProvider.select(authUserIdOrNull)` itself
    // (`master_profile_notifier.dart:56`). That holds ONLY on the null-target
    // arm. Since F1 made the `masterProfileProvider` watch CONDITIONAL, under
    // a [SalonMasterTarget] this IS a genuine new edge — and it must be: the
    // salon arm has no other input to `_assertAuthenticated`, and it is the
    // one that would otherwise go stale across a session change. The edge is
    // correctly narrowed (identity only, not the whole session), so it
    // renotifies on a real sign-in change and on nothing else. The null-target
    // arm is unaffected either way — there the edge is still a duplicate of
    // one `masterProfileProvider` already holds.
    sessionUserId: ref.watch(authProvider.select(authUserIdOrNull)) ?? '',
  );
}

/// Provides a CLIENT-safe [ServiceRepository] for PUBLIC reads only.
///
/// Used by the public master profile (Phase 13.5) to fetch the target master's
/// active services (stat tile count + the read-only service-categories
/// section) via [ServiceRepository.getMasterServices]. Unlike
/// [serviceRepositoryProvider] it does NOT `ref.watch(masterProfileProvider)`:
/// a CLIENT has no master profile, and dragging that master-only provider in
/// would fire `GET /api/v1/masters/me` (403 for a CLIENT) and trigger Riverpod's
/// retry storm — the same footgun the [approvedCategories] provider avoids by
/// sourcing the API directly. The [_masterId] readiness guard is passed empty
/// (`''`) on purpose: only [getMasterServices] (which hits the public,
/// path-parameterised endpoint and never calls `_assertAuthenticated`) is used
/// through this handle; the owner-only methods would correctly throw
/// [UnauthorizedFailure].
@Riverpod(keepAlive: true)
ServiceRepository publicServiceRepository(Ref ref) => HttpServiceRepository(
  serviceApi: ref.watch(serviceApiProvider),
  categoryApi: ref.watch(categoryRequestApiProvider),
  catalogApi: ref.watch(serviceCatalogApiProvider),
  dio: ref.watch(dioProvider),
  masterId: '',
);

/// Provides the generated [ServiceControllerApi] singleton.
///
/// Same Dio instance and serializers as the other API providers in
/// `core/network/api_client_provider.dart`. Kept alive to avoid re-construction
/// on every provider read.
@Riverpod(keepAlive: true)
ServiceControllerApi serviceApi(Ref ref) =>
    ServiceControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [CategoryRequestControllerApi] singleton.
///
/// Drives the approved-category picker (`GET /service-categories/approved`)
/// and the suggestion submission (`POST /service-categories/requests`). Same
/// authenticated Dio + serializers as the other API providers. Kept alive to
/// avoid re-construction on every provider read.
@Riverpod(keepAlive: true)
CategoryRequestControllerApi categoryRequestApi(Ref ref) =>
    CategoryRequestControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [ServiceCatalogControllerApi] singleton.
///
/// Drives the platform service-catalog lookups — specifically the second-level
/// service-type picker (`GET /service-catalog/service-types?categoryName=...`).
/// Same authenticated Dio + serializers as the other API providers. Kept alive
/// to avoid re-construction on every provider read.
@Riverpod(keepAlive: true)
ServiceCatalogControllerApi serviceCatalogApi(Ref ref) =>
    ServiceCatalogControllerApi(ref.watch(dioProvider), standardSerializers);

/// Async list of approved service categories for the service-form picker.
///
/// Watched by the category chip selector in `service_form.dart` and by the
/// services-list cards (slug → display-name resolution). The list is small and
/// changes rarely, so the provider is [keepAlive: true] — the value is cached
/// in the root container and shared across the create and edit screens rather
/// than re-fetched on every watch.
///
/// Because the cache is long-lived, an admin approving a category out-of-band
/// would otherwise go unseen until a cold restart. The services-list screen
/// therefore invalidates this provider explicitly so the picker stays fresh:
///   • on first entry (post-frame callback in `ServicesListScreen.initState`);
///   • on return from the create / edit / request-category flows (the screen
///     awaits each `context.push(...)` and invalidates on pop-back — the
///     /services route is kept alive, so `initState` does not re-fire there);
///   • on pull-to-refresh (alongside the services reload).
/// A successful [ServiceRepository.requestCategory] does NOT itself add a row:
/// a freshly-requested category is PENDING admin review and only appears once
/// an admin approves it and one of the refresh paths above re-fetches.
///
/// On error, the picker row shows a compact retry affordance that calls
/// `ref.invalidate(approvedCategoriesProvider)` — the rest of the form stays
/// usable (category is optional).
/// Sourced directly from [categoryRequestApiProvider] (which depends only on
/// [dioProvider], NOT on the master-only [masterProfileProvider]) so that
/// CLIENT-side callers — e.g. the discovery search `_ServiceTypeGrid` — never
/// transitively drag in `GET /api/v1/masters/me` (a master-only endpoint that
/// 403s for a CLIENT and then gets retried ~4× by Riverpod's backoff). The
/// returned list mirrors [ServiceRepository.fetchApprovedCategories] exactly
/// (same `MasterServiceMapper.fromApprovedCategoryList` mapping + null/empty
/// handling), so master-side callers are unaffected.
@Riverpod(keepAlive: true)
Future<List<ServiceCategoryOption>> approvedCategories(Ref ref) async {
  final res = await ref.watch(categoryRequestApiProvider).listApproved();
  final list = res.data?.data;
  if (list == null) {
    return const [];
  }
  return MasterServiceMapper.fromApprovedCategoryList(list);
}
