// Contract-drift regression net (2026-06-02) — service screens, UI half.
//
// WHY THIS FILE EXISTS
// --------------------
// service_repository_contract_test.dart proves the REAL repository maps every
// server response to the right Failure. This file proves the matching UI half:
// the create / edit / delete SCREENS, driven through the REAL repository over a
// faked socket (with the REAL ErrorMapperInterceptor), surface the right
// user-visible feedback — a success VelvetSnack on 2xx, an error VelvetSnack on
// every 4xx/5xx/network failure — and NEVER a silent dead state (the class of
// bug that shipped: a Save that does nothing visible).
//
// Here the production HttpServiceRepository + generated ServiceControllerApi +
// real interceptor all run; only the HTTP socket is faked. So a backend response
// the app mishandles surfaces as a wrong/absent VelvetSnack and fails the test.
//
// Scope note (2026-08-04): the CREATE half of this file was removed with
// `ServiceCreateScreen` — see the comment in `main()` for where that coverage
// moved. What remains is the EDIT + DELETE surface.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const _baseUrl = 'http://localhost:8080';
const _masterId = 'master-1';
const _serviceDefId = 'def-7';
const _assignmentId = 'svc-7';
const _createPath = '/api/v1/independent-masters/me/services';
const _mutatePath = '/api/v1/services/$_serviceDefId';

// ---------------------------------------------------------------------------
// Domain fixture used by the edit screen (seeds serviceByIdProvider cache hit).
// ---------------------------------------------------------------------------
const _editTarget = MasterService(
  id: _assignmentId,
  serviceDefId: _serviceDefId,
  name: 'Манікюр',
  category: 'MANICURE',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

Map<String, dynamic> _createOkEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'id': _assignmentId,
    'masterId': _masterId,
    'effectiveDurationMinutes': 60,
    'isActive': true,
    'priceType': 'FIXED',
    'priceMin': 500,
    'priceDisplay': '500 ₴',
    'serviceDefinition': <String, dynamic>{
      'id': _serviceDefId,
      'name': 'Манікюр',
      'category': 'MANICURE',
      'baseDurationMinutes': 60,
      'priceType': 'FIXED',
      'priceMin': 500,
      'priceDisplay': '500 ₴',
      'isActive': true,
    },
  },
};

Map<String, dynamic> _updateOkEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'id': _serviceDefId,
    'name': 'Манікюр PRO',
    'category': 'MANICURE',
    'baseDurationMinutes': 90,
    'priceType': 'FIXED',
    'priceMin': 650,
    'priceDisplay': '650 ₴',
    'isActive': true,
  },
};

const Map<String, dynamic> _okVoid = <String, dynamic>{
  'success': true,
  'data': null,
  'message': 'ok',
};

/// `GET /api/v1/independent-masters/me/services` — the LIST envelope, holding
/// exactly the one assignment the edit tests target.
///
/// Needed because [serviceById] is only nominally "cache-first". Its cache read
/// is `ref.read(servicesListProvider).value`, and on the edit screen's FIRST
/// build that provider has not resolved yet (its `build()` is async, so it is
/// still `AsyncLoading` and `.value` is null) — so the very first attempt is
/// ALWAYS a cache MISS and always falls through to
/// `ServiceRepository.getMyService(id)`, which issues this request. That is the
/// real production path on a cold mount, so the fake socket has to answer it.
///
/// It went unnoticed until 2026-07-31 because Riverpod's blanket retry used to
/// paper over it: attempt 1 hit the unstubbed route and threw, and by the time
/// the automatic retry ran, `servicesListProvider` HAD resolved, so attempt 2
/// took the cache path and the form appeared. Once the suite adopted the
/// production retry predicate (`beauticaProviderRetry`, which correctly does
/// not retry a deterministic failure) there was no second attempt, and all five
/// edit tests failed at the first `enterText` with "Bad state: No element".
/// Stubbing the route makes the test independent of the retry policy instead of
/// silently dependent on it.
Map<String, dynamic> _listOkEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <Map<String, dynamic>>[
    _createOkEnvelope()['data'] as Map<String, dynamic>,
  ],
};

// ---------------------------------------------------------------------------
// Stub master profile so serviceRepositoryProvider's masterId watch resolves
// (the repository itself is overridden, but other watchers stay quiet).
// ---------------------------------------------------------------------------
class _StubMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: _masterId,
    firstName: 'T',
    lastName: 'T',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// Builds a real Dio with the production ErrorMapperInterceptor + a faked
/// socket, plus a real HttpServiceRepository on top.
({Dio dio, DioAdapter adapter, HttpServiceRepository repo}) _wireRepo() {
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  dio.interceptors.add(ErrorMapperInterceptor());
  final adapter = DioAdapter(dio: dio);
  // Answer the cache-MISS fallback every edit-screen mount performs before
  // `servicesListProvider` has resolved — see [_listOkEnvelope]. Registered for
  // all tests in this file (not just the edit group): it is a GET, so it cannot
  // collide with the POST/PATCH/DELETE routes each test registers, and the
  // create group simply never issues it.
  adapter.onGet(_createPath, (s) => s.reply(200, _listOkEnvelope()));
  final repo = HttpServiceRepository(
    serviceApi: ServiceControllerApi(dio, standardSerializers),
    categoryApi: CategoryRequestControllerApi(dio, standardSerializers),
    catalogApi: ServiceCatalogControllerApi(dio, standardSerializers),
    dio: dio,
    masterId: _masterId,
  );
  return (dio: dio, adapter: adapter, repo: repo);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  HttpServiceRepository repo, {
  List<MasterService> cachedList = const <MasterService>[],
  List<ServiceCategoryOption> categories = const <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ],
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [
        serviceRepositoryProvider.overrideWithValue(repo),
        masterProfileProvider.overrideWith(_StubMasterProfile.new),
        // Seed the list so the category picker has data without hitting the
        // socket, and so serviceByIdProvider resolves from the cache on every
        // build AFTER the first. The FIRST build still misses (the stub's
        // `build()` is async, so `.value` is null at that instant) and goes to
        // the network — which is why `_wireRepo` stubs the GET list route.
        servicesListProvider.overrideWith(() => _StubServicesList(cachedList)),
        approvedCategoriesProvider.overrideWith((ref) async => categories),
        // The second-level service-type picker (_ServiceTypeChips) mounts as
        // soon as a category is selected/seeded and would otherwise drive a
        // real fetch over the faked socket (an unmatched route → DioException).
        // Override the provider with a calm empty list so this contract test
        // stays focused on the create/edit/delete endpoints under test.
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: screen,
      ),
    ),
  );
  await tester.pump();
}

class _StubServicesList extends ServicesList {
  _StubServicesList(this._seed);
  final List<MasterService> _seed;
  @override
  Future<List<MasterService>> build() async => _seed;
}

AppLocalizations _l10n(WidgetTester tester, Type screenType) =>
    AppLocalizations.of(tester.element(find.byType(screenType)));

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('btn-submit-service')));
  await tester.pump();
}

/// Mutates the (pre-populated) edit-form name so the form is dirty and the
/// PATCH carries a real change — mirrors a user editing a field.
Future<void> _editName(WidgetTester tester, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('field-service-name')),
      matching: find.byType(TextField),
    ),
    value,
  );
  await tester.pump();
}

void main() {
  // =========================================================================
  // CREATE group REMOVED (2026-08-04)
  // -------------------------------------------------------------------------
  // It drove `ServiceCreateScreen`, the single-create form, which was deleted
  // when both "add service" entry points collapsed onto the multi-select
  // `ServiceSetupScreen` (the backend made the bulk endpoint additive in
  // c5e420f). The screen no longer exists, so the group had nothing to drive.
  //
  // The transport-seam coverage it provided is NOT lost — it moved rather than
  // vanished:
  //   • the bulk write's per-status Failure mapping (409 DUPLICATE_SERVICE,
  //     the new 503, plain-409 fallthrough, 400 field errors) is pinned by
  //     `service_repository_bulk_create_test.dart` +
  //     `service_repository_bulk_create_contract_test.dart`;
  //   • the end-to-end "a duplicate never dies silently" journey is pinned by
  //     `integration_test/service_duplicate_flow_test.dart`, retargeted to the
  //     setup screen in the same change.
  // The EDIT group below is untouched: it exercises the create screen's
  // sibling (`ServiceEditScreen`) over the same real repository + real
  // interceptor + faked socket, and never referenced the deleted screen.
  // =========================================================================

  // =========================================================================
  // EDIT — success + failure feedback (cache-hit seeds the form)
  // =========================================================================
  group('ServiceEditScreen — real-transport feedback contract', () {
    testWidgets('POSITIVE: 200 → update success VelvetSnack', (tester) async {
      final h = _wireRepo();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(200, _updateOkEnvelope()),
        data: Matchers.any,
      );

      await _pump(
        tester,
        const ServiceEditScreen(id: _assignmentId),
        h.repo,
        cachedList: const [_editTarget],
      );
      await tester
          .pumpAndSettle(); // resolve serviceByIdProvider + entrance anim

      await _editName(tester, 'Манікюр PRO');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceEditScreen);
      expectVelvetSnack(
        l10n.serviceUpdatedSuccess,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('NEGATIVE: 404 (stale serviceDefId) → not-found VelvetSnack, '
        'screen stays', (tester) async {
      final h = _wireRepo();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(404, {'message': 'not found'}),
        data: Matchers.any,
      );

      await _pump(
        tester,
        const ServiceEditScreen(id: _assignmentId),
        h.repo,
        cachedList: const [_editTarget],
      );
      await tester.pumpAndSettle();

      await _editName(tester, 'Манікюр PRO');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceEditScreen);
      expectVelvetSnack(l10n.errNotFound, variant: VelvetSnackVariant.error);
      expect(find.byType(ServiceEditScreen), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('NEGATIVE: 500 → server-error VelvetSnack', (tester) async {
      final h = _wireRepo();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await _pump(
        tester,
        const ServiceEditScreen(id: _assignmentId),
        h.repo,
        cachedList: const [_editTarget],
      );
      await tester.pumpAndSettle();

      await _editName(tester, 'Манікюр PRO');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceEditScreen);
      expectVelvetSnack(l10n.errServer, variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });

    // ---- DELETE path on the edit screen ----
    testWidgets('POSITIVE: delete confirm → 200 → screen handles success', (
      tester,
    ) async {
      final h = _wireRepo();
      h.adapter.onDelete(_mutatePath, (s) => s.reply(200, _okVoid));

      await _pump(
        tester,
        const ServiceEditScreen(id: _assignmentId),
        h.repo,
        cachedList: const [_editTarget],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle(); // dialog opens

      // Confirm in the DeleteServiceDialog.
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // No error VelvetSnack — a clean delete shows no failure feedback.
      // (Screen pops in a real router; here Navigator.maybePop is a no-op since
      // it is the root route, so the screen remains but with NO error VelvetSnack.)
      final l10n = _l10n(tester, ServiceEditScreen);
      expect(find.text(l10n.errServer), findsNothing);
      expect(find.text(l10n.errNotFound), findsNothing);
      expect(find.text(l10n.errUnknown), findsNothing);
    });

    testWidgets('NEGATIVE: delete confirm → 409 conflict → error VelvetSnack', (
      tester,
    ) async {
      final h = _wireRepo();
      h.adapter.onDelete(
        _mutatePath,
        (s) => s.reply(409, {'message': 'has future bookings'}),
      );

      await _pump(
        tester,
        const ServiceEditScreen(id: _assignmentId),
        h.repo,
        cachedList: const [_editTarget],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pumpAndSettle();

      // 409 → ServerFailure(409) → errServer. Never a silent swallow.
      final l10n = _l10n(tester, ServiceEditScreen);
      expectVelvetSnack(l10n.errServer, variant: VelvetSnackVariant.error);
      expect(find.byType(ServiceEditScreen), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });
  });
}
