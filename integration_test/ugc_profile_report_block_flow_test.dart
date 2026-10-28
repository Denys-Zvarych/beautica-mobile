// Phase 425 (Step 2.7 Rule 3b) — fake-backed E2E for profile «⋯» reports,
// provider → client blocks from «Деталі запису», and the neutral
// BOOKING_UNAVAILABLE banner, through the REAL router + screens.
//
// Seams overridden (and only these):
//   • `contentReportRepositoryProvider` → `FakeContentReportRepository`
//     (asserts the exact report request).
//   • `clientBlockRepositoryProvider` → `FakeClientBlockRepository` (records
//     the exact repository calls; the same flows on the REAL `/blocks` wire
//     live in `ugc_blocked_clients_flow_test.dart`).
//   • `appointmentApiProvider` → the REAL generated `AppointmentControllerApi`
//     over a dedicated Dio whose ONLY route is `POST /api/v1/appointments` →
//     409 `BOOKING_UNAVAILABLE`, so the REAL `HttpAppointmentRepository`
//     409 decode + the REAL submit notifier + confirm screens are on the path.
//
//   (a) CLIENT: public master profile → «⋯» (right of the heart) → report sheet
//       with the profile subject → {MASTER_PROFILE, master id}; same for the
//       salon cover → {SALON_PROFILE, salon id}.
//   (b) INDEPENDENT_MASTER: client strip «⋯» → «Заблокувати клієнта» →
//       confirm dialog → block → success snack + booking detail re-fetched.
//       SALON_OWNER: report + block rows. SALON_MASTER: report only, which
//       sends {CLIENT_PROFILE, client id}. SALON_MASTER on a guest booking: no
//       «⋯» (an independent master on the same guest booking gets block-only).
//       CLIENT on their own booking: no «⋯» (clients never block).
//   (c) CLIENT booking create (independent visit + salon) 409
//       BOOKING_UNAVAILABLE → the neutral banner with the SERVER text, one
//       POST only, no generic error card, no conflict dialog.
//
// Runs headless: `flutter test integration_test/
// ugc_profile_report_block_flow_test.dart -d flutter-tester`.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_counterparty_header.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/velvet_banner.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/features/moderation/support/fake_client_block_repository.dart';
import '../test/features/moderation/support/fake_content_report_repository.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

final Finder _sheet = find.byType(ReportSheet);
final Finder _clientMore = find.byKey(BookingCounterpartyHeader.clientMoreKey);
final Finder _actions = find.byType(ClientActionsSheet);

/// The backend's own neutral wording — deliberately NOT the app's
/// `bookingErrUnavailable` fallback («майстра/салону»), so the banner can only
/// show it if the server `message` reached the screen as-is.
const String _kServerUnavailable = 'Запис до цього майстра зараз недоступний';

Future<void> _pickAndSubmit(WidgetTester tester, ReportReason reason) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(ReportSheet.reasonKey(reason)),
  );
  await AppHarness.settle(tester);
  await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
  await AppHarness.settle(tester);
  // By label — the CTA's AnimatedScale root swallows tap-by-key.
  await tester.tap(
    find.descendant(
      of: find.byKey(ReportSheet.submitKey),
      matching: find.text(_l10n.reportSubmit),
    ),
  );
  await AppHarness.settle(tester);
}

void _expectSnack(String text) => expect(
  find.descendant(of: find.byType(VelvetSnack), matching: find.text(text)),
  findsOneWidget,
);

Future<GoRouter> _bootDetail(
  WidgetTester tester,
  FakeBackend fb, {
  required UserRole role,
  required String path,
  FakeClientBlockRepository? blocks,
  FakeContentReportRepository? reports,
}) async {
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    extraOverrides: <Object>[
      clientBlockRepositoryProvider.overrideWithValue(
        blocks ?? FakeClientBlockRepository(),
      ),
      contentReportRepositoryProvider.overrideWithValue(
        reports ?? FakeContentReportRepository(),
      ),
    ],
  );
  await AppHarness.loginAs(tester, fb, role);
  unawaited(router.push(path));
  await AppHarness.settle(tester);
  expect(find.byType(BookingDetailScreen), findsOneWidget);
  return router;
}

/// A dedicated Dio whose ONLY route is `POST /api/v1/appointments` → 409
/// `BOOKING_UNAVAILABLE`; [onPost] counts each hit. Carries the production
/// `ErrorMapperInterceptor`, as `FakeBackend.dio` does.
Dio _unavailableAppointmentsDio(void Function() onPost) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  final DioAdapter adapter = DioAdapter(dio: dio);
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(ErrorMapperInterceptor());
  adapter.onRoute(
    '/api/v1/appointments',
    (server) => server.replyCallback(409, (_) {
      onPost();
      return <String, dynamic>{
        'success': false,
        'message': _kServerUnavailable,
        'data': <String, dynamic>{'code': 'BOOKING_UNAVAILABLE'},
      };
    }),
    request: const Request(method: RequestMethods.post, data: Matchers.any),
  );
  return dio;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── (a) profile «⋯» → report ───────────────────────────────────────────────

  testWidgets('CLIENT on a public master profile: «⋯» sits right of the '
      'heart and opens the report sheet directly with the profile subject → '
      '{MASTER_PROFILE, master id}; success snack, profile stays', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final FakeContentReportRepository repo = FakeContentReportRepository();
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        contentReportRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('public-master-profile-about-tab')),
    );
    await AppHarness.settle(tester);

    final Finder more = find.byKey(PublicMasterProfileScreen.reportKey);
    final Finder heart = find.byKey(const Key('public-master-favorite-toggle'));
    expect(more, findsOneWidget);
    expect(heart, findsOneWidget);
    expect(tester.getCenter(heart).dx, lessThan(tester.getCenter(more).dx));

    await AppHarness.tapVisible(tester, more);
    await AppHarness.settle(tester);
    expect(_sheet, findsOneWidget);
    expect(_actions, findsNothing, reason: 'no actions sheet for a client');
    expect(
      find.descendant(
        of: _sheet,
        // i18n-finder-ok: fixture provider name (locale-invariant data)
        matching: find.text(_l10n.reportSubjectProfile('Софія Бондар')),
      ),
      findsOneWidget,
    );

    await _pickAndSubmit(tester, ReportReason.spam);

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.masterProfile,
        targetId: 'master-aaa',
        reason: ReportReason.spam,
      ),
    );
    expect(_sheet, findsNothing);
    _expectSnack(_l10n.reportSent);
    expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
    AppHarness.expectLocation(
      router,
      RouteNames.masterPublicProfile('master-aaa'),
    );
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('CLIENT on a public salon profile: the cover «⋯» sits right of '
      'the heart and reports {SALON_PROFILE, salon id} with the salon name '
      'as subject', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
      final FakeContentReportRepository repo = FakeContentReportRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          contentReportRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
      final Finder more = find.byKey(PublicSalonProfileScreen.reportKey);
      await AppHarness.pumpUntilFound(tester, more);
      await AppHarness.settle(tester);

      final Finder heart = find.byKey(const Key('salon-favorite-toggle'));
      expect(heart, findsOneWidget);
      expect(tester.getCenter(heart).dx, lessThan(tester.getCenter(more).dx));

      await AppHarness.tapVisible(tester, more);
      await AppHarness.settle(tester);
      expect(_sheet, findsOneWidget);
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text(
            _l10n.reportSubjectProfile('Студія Краси «Камелія»'),
          ),
        ),
        findsOneWidget,
      );

      await _pickAndSubmit(tester, ReportReason.offensive);

      expect(
        repo.requests.single,
        const ContentReportRequest(
          targetType: ReportTargetType.salonProfile,
          targetId: 'salon-xyz',
          reason: ReportReason.offensive,
        ),
      );
      expect(_sheet, findsNothing);
      _expectSnack(_l10n.reportSent);
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
      AppHarness.expectLocation(
        router,
        RouteNames.salonPublicProfile('salon-xyz'),
      );
      await pumpPastVelvetSnack(tester);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── (b) booking detail client strip «⋯» ───────────────────────────────────

  testWidgets('INDEPENDENT_MASTER blocks the client: «⋯» → «Заблокувати '
      'клієнта» → confirm dialog → block(booking-1) → success snack and the '
      'booking detail is re-fetched', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    final FakeClientBlockRepository blocks = FakeClientBlockRepository();
    await _bootDetail(
      tester,
      fb,
      role: UserRole.independentMaster,
      path: RouteNames.masterBookingDetail('booking-1'),
      blocks: blocks,
    );
    final String name = '${fb.clientFirstName} ${fb.clientLastName}';

    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);
    expect(_actions, findsOneWidget);
    expect(
      find.descendant(of: _actions, matching: find.text(name)),
      findsOneWidget,
    );
    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);

    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.blockKey),
    );
    await AppHarness.settle(tester);
    expect(find.byType(BlockClientDialog), findsOneWidget);
    expect(find.text(_l10n.blockDialogTitle(name)), findsOneWidget);
    expect(find.text(_l10n.blockDialogBody), findsOneWidget);
    expect(blocks.calls, isEmpty, reason: 'nothing sent before confirming');

    final int detailCallsBefore = fb.getBookingDetailCalls;
    await tester.tap(
      find.descendant(
        of: find.byKey(BlockClientDialog.confirmKey),
        matching: find.text(_l10n.blockDialogConfirm),
      ),
    );
    await AppHarness.settle(tester);

    expect(blocks.calls, <String>['block:booking-1']);
    expect(blocks.stored, hasLength(1));
    expect(find.byType(BlockClientDialog), findsNothing);
    _expectSnack(_l10n.clientBlockedSnack);
    expect(
      fb.getBookingDetailCalls,
      greaterThan(detailCallsBefore),
      reason: 'D6 — the booking detail is invalidated after a block',
    );
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('INDEPENDENT_MASTER backs out of the block dialog: nothing is '
      'sent, no snack', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    final FakeClientBlockRepository blocks = FakeClientBlockRepository();
    await _bootDetail(
      tester,
      fb,
      role: UserRole.independentMaster,
      path: RouteNames.masterBookingDetail('booking-1'),
      blocks: blocks,
    );
    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.blockKey),
    );
    await AppHarness.settle(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(BlockClientDialog.dismissKey),
    );
    await AppHarness.settle(tester);

    expect(find.byType(BlockClientDialog), findsNothing);
    expect(blocks.calls, isEmpty);
    expect(find.byType(VelvetSnack), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('SALON_OWNER on a registered-client booking: the sheet offers '
      'report AND block', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
    await _bootDetail(
      tester,
      fb,
      role: UserRole.salonOwner,
      path: RouteNames.salonStaffBookingDetail('booking-1'),
    );
    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);

    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('SALON_MASTER on a registered-client booking: report only (no '
      'block row); reporting sends {CLIENT_PROFILE, client id}', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonMaster;
    final FakeContentReportRepository reports = FakeContentReportRepository();
    final FakeClientBlockRepository blocks = FakeClientBlockRepository();
    await _bootDetail(
      tester,
      fb,
      role: UserRole.salonMaster,
      path: RouteNames.salonMasterBookingDetail('booking-1'),
      reports: reports,
      blocks: blocks,
    );
    final String name = '${fb.clientFirstName} ${fb.clientLastName}';

    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);
    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
    expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);

    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.reportKey),
    );
    await AppHarness.settle(tester);
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(
        of: _sheet,
        matching: find.text(_l10n.reportSubjectClient(name)),
      ),
      findsOneWidget,
    );
    await _pickAndSubmit(tester, ReportReason.offensive);

    expect(
      reports.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.clientProfile,
        targetId: 'client-1',
        reason: ReportReason.offensive,
      ),
    );
    expect(blocks.calls, isEmpty);
    _expectSnack(_l10n.reportSent);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('guest booking: SALON_MASTER gets NO «⋯» (nothing to report, '
      'cannot block)', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.salonMaster
      ..bookingClientIsGuest = true;
    await _bootDetail(
      tester,
      fb,
      role: UserRole.salonMaster,
      path: RouteNames.salonMasterBookingDetail('booking-1'),
    );
    await AppHarness.settle(tester);

    expect(find.byType(BookingCounterpartyHeader), findsOneWidget);
    expect(_clientMore, findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('guest booking (positive control): INDEPENDENT_MASTER gets «⋯» '
      'with block only — no report row for a guest', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientIsGuest = true;
    await _bootDetail(
      tester,
      fb,
      role: UserRole.independentMaster,
      path: RouteNames.masterBookingDetail('booking-1'),
    );
    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);

    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('guest booking the server marks NOT blockable (walk-in / erased '
      'guest, backend 397 clientBlockable=false): INDEPENDENT_MASTER gets no '
      '«⋯» at all', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientIsGuest = true
      ..bookingClientBlockable = false;
    await _bootDetail(
      tester,
      fb,
      role: UserRole.independentMaster,
      path: RouteNames.masterBookingDetail('booking-1'),
    );
    await AppHarness.settle(tester);

    expect(find.byType(BookingCounterpartyHeader), findsOneWidget);
    expect(_clientMore, findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('a blocked client: «Розблокувати клієнта» sends ONE DELETE of '
      'clientBlockId — no POST', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientBlockId = 'block-1';
    final FakeClientBlockRepository blocks = FakeClientBlockRepository();
    await _bootDetail(
      tester,
      fb,
      role: UserRole.independentMaster,
      path: RouteNames.masterBookingDetail('booking-1'),
      blocks: blocks,
    );
    await AppHarness.pumpUntilFound(tester, _clientMore);
    await AppHarness.tapVisible(tester, _clientMore);
    await AppHarness.settle(tester);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);

    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.unblockKey),
    );
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
    await AppHarness.settle(tester);

    expect(blocks.calls, <String>['unblock:block-1']);
    _expectSnack(_l10n.clientUnblockedSnack);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('CLIENT on their own booking detail: no «⋯» anywhere — clients '
      'never block', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    await _bootDetail(
      tester,
      fb,
      role: UserRole.client,
      path: RouteNames.bookingDetail('booking-1'),
    );
    await AppHarness.settle(tester);

    expect(find.byType(BookingCounterpartyHeader), findsOneWidget);
    expect(_clientMore, findsNothing);
    expect(find.text(_l10n.clientActionBlock), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── (c) 409 BOOKING_UNAVAILABLE ───────────────────────────────────────────

  testWidgets('CLIENT independent visit: the create 409s BOOKING_UNAVAILABLE '
      '→ the neutral banner with the SERVER text, one POST, no generic error '
      'card, no conflict dialog, still on confirm', (tester) async {
    int posts = 0;
    final Dio dio = _unavailableAppointmentsDio(() => posts++);
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        appointmentApiProvider.overrideWithValue(
          AppointmentControllerApi(dio, beauticaSerializers),
        ),
      ],
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    const MasterService svc = MasterService(
      id: 'pub-assign-1',
      serviceDefId: 'def-pub-assign-1',
      name: 'Манікюр з покриттям',
      durationMinutes: 90,
      priceMin: 500,
      priceDisplay: '500 ₴',
      category: 'NAILS',
    );
    const Master master = Master(
      id: 'master-aaa',
      firstName: 'Софія',
      lastName: 'Бондар',
      city: 'Київ',
      reviewCount: 0,
      type: MasterType.independentMaster,
    );
    unawaited(
      router.push(
        RouteNames.bookingConfirm,
        extra: BookingConfirmArgs(
          masterId: 'master-aaa',
          master: master,
          services: const <MasterService>[svc],
          startAt: kFixedNow.add(const Duration(days: 1, hours: 10)),
          idempotencyKey: 'itest-unavailable',
        ),
      ),
    );
    await AppHarness.settle(tester);
    expect(find.byType(BookingConfirmScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
    await AppHarness.settle(tester);

    final Finder banner = find.byKey(const Key('booking-unavailable-banner'));
    expect(banner, findsOneWidget);
    expect(tester.widget<VelvetBanner>(banner).message, _kServerUnavailable);
    expect(find.text(_kServerUnavailable), findsOneWidget);
    expect(posts, 1, reason: 'not transient — no automatic retry');
    expect(find.byKey(const Key('booking-confirm-submit-error')), findsNothing);
    expect(
      find.byKey(const Key('client-booking-conflict-dialog')),
      findsNothing,
    );
    expect(find.byType(BookingConfirmScreen), findsOneWidget);
    AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('CLIENT salon booking: the create 409s BOOKING_UNAVAILABLE → '
      'the same neutral banner with the SERVER text, one POST, no generic '
      'error card', (tester) async {
    await mockNetworkImagesFor(() async {
      int posts = 0;
      final Dio dio = _unavailableAppointmentsDio(() => posts++);
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentApiProvider.overrideWithValue(
            AppointmentControllerApi(dio, beauticaSerializers),
          ),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      unawaited(
        router.push(
          RouteNames.salonBookingConfirm,
          extra: SalonBookingConfirmArgs(
            salonId: 'salon-xyz',
            appointments: <SalonBookingAppointment>[
              SalonBookingAppointment(
                schedule: const SalonMasterSchedule(
                  masterId: 'm-one',
                  firstName: 'Олена',
                  lastName: 'Майстер',
                  type: MasterType.salonMaster,
                  services: <SalonCatalogService>[
                    SalonCatalogService(
                      id: 'svc-m-one',
                      name: 'Манікюр',
                      durationLabel: '1 год',
                      priceDisplay: '500 ₴',
                      durationMinutes: 60,
                      priceType: ServicePriceType.fixed,
                      priceMin: 500,
                    ),
                  ],
                  orderedMasterServiceIds: <String>['assign-m-one'],
                ),
                startAt: kFixedNow.add(const Duration(days: 1, hours: 10)),
                idempotencyKey: 'idem-m-one',
              ),
            ],
          ),
        ),
      );
      await AppHarness.settle(tester);
      expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await AppHarness.settle(tester);

      final Finder banner = find.byKey(const Key('booking-unavailable-banner'));
      expect(banner, findsOneWidget);
      expect(tester.widget<VelvetBanner>(banner).message, _kServerUnavailable);
      expect(posts, 1);
      expect(find.byKey(const Key('salon-confirm-submit-error')), findsNothing);
      expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
      AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
