// Contract-drift regression net (2026-06-02) — service screens, UI half.
//
// WHY THIS FILE EXISTS
// --------------------
// service_repository_contract_test.dart proves the REAL repository maps every
// server response to the right Failure. This file proves the matching UI half:
// the create / edit / delete SCREENS, driven through the REAL repository over a
// faked socket (with the REAL ErrorMapperInterceptor), surface the right
// user-visible feedback — a success SnackBar on 2xx, an error SnackBar on every
// 4xx/5xx/network failure — and NEVER a silent dead state (the class of bug that
// shipped: a Save that does nothing visible).
//
// Unlike service_create_screen_test.dart (which mocks the repository), here the
// production HttpServiceRepository + generated ServiceControllerApi + real
// interceptor all run; only the HTTP socket is faked. So a backend response the
// app mishandles surfaces as a wrong/absent SnackBar and fails the test.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_create_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'widgets/select_dropdown_test_helpers.dart';

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
  priceDisplay: '500 грн',
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
    'priceDisplay': '500 грн',
    'serviceDefinition': <String, dynamic>{
      'id': _serviceDefId,
      'name': 'Манікюр',
      'category': 'MANICURE',
      'baseDurationMinutes': 60,
      'priceType': 'FIXED',
      'priceMin': 500,
      'priceDisplay': '500 грн',
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
    'priceDisplay': '650 грн',
    'isActive': true,
  },
};

const Map<String, dynamic> _okVoid = <String, dynamic>{
  'success': true,
  'data': null,
  'message': 'ok',
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
      overrides: [
        serviceRepositoryProvider.overrideWithValue(repo),
        masterProfileProvider.overrideWith(_StubMasterProfile.new),
        // Seed the list so serviceByIdProvider can resolve via the cache and
        // the category picker has data without hitting the socket.
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

// Fill the create form with a valid FIXED service and select the category chip.
Future<void> _fillValidCreateForm(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('field-service-name')),
      matching: find.byType(TextField),
    ),
    'Манікюр',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('field-service-duration')),
      matching: find.byType(TextField),
    ),
    '60',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('pricing-fixed-amount')),
      matching: find.byType(TextField),
    ),
    '500',
  );
  // Select the category via the dropdown (open menu → tap option → settle).
  await selectCategoryOption(tester, 'MANICURE');
  // Service type is MANDATORY on create — select one (for the chosen category)
  // via the form State so the submit is not blocked by the required-type check.
  final dynamic formState = tester.state(find.byType(ServiceForm));
  formState.onServiceTypeSelected(
    const ServiceTypeOption(
      id: 'stype-manicure',
      slug: 'MANICURE_A',
      nameUk: 'Класичний манікюр',
      categoryName: 'MANICURE',
    ),
  );
  await tester.pump();
}

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
  // CREATE — success + each failure surfaces the right SnackBar
  // =========================================================================
  group('ServiceCreateScreen — real-transport feedback contract', () {
    testWidgets('POSITIVE: 200 → success SnackBar shown, screen reacts', (
      tester,
    ) async {
      final h = _wireRepo();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(200, _createOkEnvelope()),
        data: Matchers.any,
      );

      await _pump(tester, const ServiceCreateScreen(), h.repo);
      await _fillValidCreateForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceCreateScreen);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.serviceCreatedSuccess), findsOneWidget);
    });

    testWidgets(
      'NEGATIVE: 400 with a recognised field error → INLINE on the field, no '
      'generic SnackBar (hardened 2026-06-03)',
      (tester) async {
        final h = _wireRepo();
        h.adapter.onPost(
          _createPath,
          (s) => s.reply(400, {
            'success': false,
            'errors': {'name': 'already exists'},
          }),
          data: Matchers.any,
        );

        await _pump(tester, const ServiceCreateScreen(), h.repo);
        await _fillValidCreateForm(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        final l10n = _l10n(tester, ServiceCreateScreen);
        // The backend field error is now surfaced inline on the name input
        // instead of being collapsed into the generic errValidation SnackBar.
        expect(find.text('already exists'), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(ServiceCreateScreen), findsOneWidget);
      },
    );

    testWidgets(
      'NEGATIVE: 400 with EMPTY errors map on CREATE → inline type-mismatch '
      'feedback (mandatory type + dirty category trips the 16.5 safety net; '
      'still non-silent, screen not popped)',
      (tester) async {
        final h = _wireRepo();
        h.adapter.onPost(
          _createPath,
          (s) => s.reply(400, {'success': false, 'message': 'Bad request'}),
          data: Matchers.any,
        );

        await _pump(tester, const ServiceCreateScreen(), h.repo);
        await _fillValidCreateForm(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        // CONTRACT CHANGE: service type is now MANDATORY on create, so the form
        // ALWAYS carries a selected type and a dirty category (null → MANICURE).
        // An empty-errors 400 (no `errors` map) is therefore attributed by the
        // Phase-16.5 category-mismatch safety net and surfaced INLINE on the
        // service-type field rather than via the generic SnackBar. The Save
        // still never dies silently and the screen is not popped.
        // (Backlog note: an unrelated business 400 is mislabeled as a type
        // mismatch on create — flagged to mobile-backlog as a product-behavior
        // question.)
        final l10n = _l10n(tester, ServiceCreateScreen);
        expect(find.byKey(const Key('error-service-type')), findsOneWidget);
        expect(find.text(l10n.serviceTypeCategoryMismatch), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(ServiceCreateScreen), findsOneWidget);
      },
    );

    testWidgets('NEGATIVE: 500 → server-error SnackBar, screen not popped', (
      tester,
    ) async {
      final h = _wireRepo();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await _pump(tester, const ServiceCreateScreen(), h.repo);
      await _fillValidCreateForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceCreateScreen);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.errServer), findsOneWidget);
      expect(find.byType(ServiceCreateScreen), findsOneWidget);
    });

    testWidgets('NEGATIVE: network timeout → network-error SnackBar', (
      tester,
    ) async {
      final h = _wireRepo();
      h.adapter.onPost(
        _createPath,
        (s) => s.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: _createPath),
          ),
        ),
        data: Matchers.any,
      );

      await _pump(tester, const ServiceCreateScreen(), h.repo);
      await _fillValidCreateForm(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      final l10n = _l10n(tester, ServiceCreateScreen);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.errNetwork), findsOneWidget);
    });
  });

  // =========================================================================
  // EDIT — success + failure feedback (cache-hit seeds the form)
  // =========================================================================
  group('ServiceEditScreen — real-transport feedback contract', () {
    testWidgets('POSITIVE: 200 → update success SnackBar', (tester) async {
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
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.serviceUpdatedSuccess), findsOneWidget);
    });

    testWidgets('NEGATIVE: 404 (stale serviceDefId) → not-found SnackBar, '
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
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.errNotFound), findsOneWidget);
      expect(find.byType(ServiceEditScreen), findsOneWidget);
    });

    testWidgets('NEGATIVE: 500 → server-error SnackBar', (tester) async {
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
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.errServer), findsOneWidget);
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

      // No error SnackBar — a clean delete shows no failure feedback.
      // (Screen pops in a real router; here Navigator.maybePop is a no-op since
      // it is the root route, so the screen remains but with NO error SnackBar.)
      final l10n = _l10n(tester, ServiceEditScreen);
      expect(find.text(l10n.errServer), findsNothing);
      expect(find.text(l10n.errNotFound), findsNothing);
      expect(find.text(l10n.errUnknown), findsNothing);
    });

    testWidgets('NEGATIVE: delete confirm → 409 conflict → error SnackBar', (
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
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.errServer), findsOneWidget);
      expect(find.byType(ServiceEditScreen), findsOneWidget);
    });
  });
}
