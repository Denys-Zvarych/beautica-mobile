// Phase 231 — widget suite for [MasterArchiveScreen] (the master «Архів»
// page).
//
// Mirrors `master_bookings_filter_wiring_test.dart`'s isolation discipline —
// a real `GoRouter`, a mocktail [BookingRepository], `_NoOpScreenProtection`,
// and `masterServiceCatalogProvider` overridden directly (no real Dio
// reachable from this tree). Covers:
//   * all 4 async states (loading / data / error / empty — both true-empty
//     and filter-empty);
//   * the default request sends BOTH `partition: HISTORY` and the legacy
//     status set (end-to-end through the real screen, not just the
//     notifier);
//   * the reused `BookingsFilterSheet`'s «Підтверджено» row, applied with NO
//     new UI, narrows the visible list to exactly the `awaitingClosure` rows
//     (fixture carries a non-awaiting row too, so the assertion is not
//     vacuous);
//   * the «Виконано» CTA renders ONLY on `awaitingClosure` rows, opens the
//     SAME `CompleteBookingDialog`, and on confirm calls
//     `BookingRepository.completeBooking` with the tapped row's id;
//   * RE-ENTRANCY: a second tap fired while the WRITE is still pending
//     (dialog already dismissed) does not open a second dialog or fire a
//     second write — see that test's own note on why the dialog-open window
//     itself is not independently reachable via a real tap in this layout;
//   * the header back arrow pops the route (go_router `context.pop`, no
//     `Navigator`).
//
// `booking.appointmentId` is `null` on every fixture in this file — the
// appointment-child branch (`AppointmentRepository.completeAppointment`)
// mirrors `booking_detail_screen.dart`'s own identical branch verbatim and
// is not re-proven here.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  required String id,
  required BookingStatus status,
  bool awaitingClosure = false,
}) => Booking(
  id: id,
  masterId: 'm-$id',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Ковальчук',
  serviceId: 's-$id',
  serviceName: 'Манікюр з покриттям',
  durationMinutes: 60,
  price: 500,
  // A fixed PAST literal — this screen is HISTORY-scoped by construction
  // (HISTORY ⊇ PAST), and a fixed past instant can never drift into
  // "upcoming" (see
  // `test/helpers/booking_fixture_dates.dart`'s header on why a FUTURE
  // fixture needs the relative helper but a PAST one does not).
  startAt: DateTime.utc(2000, 1, 1, 10),
  endAt: DateTime.utc(2000, 1, 1, 11),
  status: status,
  canReview: false,
  awaitingClosure: awaitingClosure,
);

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingPartition.past);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
  });

  void stubList(List<Booking> items) {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        partition: any(named: 'partition'),
        serviceIds: any(named: 'serviceIds'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
      ),
    ).thenAnswer((_) async => _page(items));
  }

  /// Stubs a DIFFERENT raw server page per requested `page` index, ONLY for
  /// the request the «Підтверджено» filter sends (`statuses == {confirmed}`).
  /// Every OTHER request — critically, the screen's own initial UNFILTERED
  /// landing fetch, which every test in this group also triggers via
  /// [pump] before it ever applies a filter — gets back a single, harmless
  /// empty page (`hasMore == false`), so it can never grow a trailing
  /// `MyBookingsLoadMoreSpinner` of its own and race the scenario under
  /// test: that spinner's `CircularProgressIndicator` starts an
  /// indeterminate animation unconditionally in `initState` (unlike
  /// `BookingsSkeleton`'s guarded `postFrameCallback`) and never stops on
  /// its own, so an incidental one on the UNFILTERED fetch would make a
  /// perfectly ordinary `pumpAndSettle()` (e.g. right after the route push
  /// transition) hang exactly like it would on `BookingsSkeleton` — see
  /// [pump]'s own note above.
  void stubConfirmedFilterPages(
    Map<int, List<Booking>> byPage, {
    required int totalPages,
  }) {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        partition: any(named: 'partition'),
        serviceIds: any(named: 'serviceIds'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final Set<BookingStatus>? statuses =
          invocation.namedArguments[#statuses] as Set<BookingStatus>?;
      final bool isConfirmedFilterRequest =
          statuses != null &&
          statuses.length == 1 &&
          statuses.single == BookingStatus.confirmed;
      if (!isConfirmedFilterRequest) {
        return _page(const <Booking>[]);
      }
      final int page = invocation.namedArguments[#page] as int;
      final List<Booking> items = byPage[page] ?? const <Booking>[];
      return PageResponse<Booking>(
        items: items,
        page: page,
        totalPages: totalPages,
        totalElements: byPage.values.fold<int>(0, (int a, l) => a + l.length),
      );
    });
  }

  /// mobile-qa MEDIUM fix (2026-08-16) — stubs an EFFECTIVELY UNBOUNDED
  /// «Підтверджено» filtered stream: every raw page comes back with ZERO
  /// rows (the predicate never matches) and `hasMore: true` forever
  /// (`totalPages: 999`) — the shape needed to drive
  /// [_MasterArchiveScreenState._autoContinueAttempts] all the way to
  /// exhaustion without hand-authoring one page per attempt. Every OTHER
  /// (non-filter) request gets back one harmless empty page, mirroring
  /// [stubConfirmedFilterPages]'s identical reasoning for why the screen's
  /// own unfiltered landing fetch must never grow its own spinner.
  ///
  /// Returns the list of PAGE INDICES requested under the confirmed
  /// filter, in call order — the load-bearing observable for the whole
  /// cap-boundary group below: a regression to unbounded auto-continue
  /// scheduling shows up here as a list that keeps growing past the
  /// expected length, not merely as a widget that eventually happens to
  /// look right.
  List<int> stubUnboundedEmptyConfirmedFilter() {
    final List<int> filteredPageRequests = <int>[];
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        partition: any(named: 'partition'),
        serviceIds: any(named: 'serviceIds'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final Set<BookingStatus>? statuses =
          invocation.namedArguments[#statuses] as Set<BookingStatus>?;
      final bool isConfirmedFilterRequest =
          statuses != null &&
          statuses.length == 1 &&
          statuses.single == BookingStatus.confirmed;
      if (!isConfirmedFilterRequest) {
        return _page(const <Booking>[]);
      }
      final int page = invocation.namedArguments[#page] as int;
      filteredPageRequests.add(page);
      return PageResponse<Booking>(
        items: const <Booking>[],
        page: page,
        totalPages: 999,
        totalElements: 0,
      );
    });
    return filteredPageRequests;
  }

  /// Pumps `MasterArchiveScreen` behind a stub `/from` route, so the back
  /// arrow (`context.pop`) has somewhere real to land.
  Future<void> pump(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/from',
      routes: <RouteBase>[
        GoRoute(
          path: '/from',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            key: const Key('from-stub'),
            body: TextButton(
              key: const Key('open-archive'),
              onPressed: () => context.push('/archive'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/archive',
          builder: (BuildContext context, GoRouterState state) =>
              const MasterArchiveScreen(),
        ),
        // A probe standing in for `LeaveClientFeedbackScreen` at the SAME
        // path `RouteNames.clientReview` builds — proves the «Відгук» slot
        // pushes the real route rather than merely calling some callback.
        //
        // Registered as a plain top-level `GoRoute`, which is now what
        // `app_router.dart` ACTUALLY does (mobile-qa MEDIUM/finding-1 fix,
        // 2026-08-16): `review` used to be nested under a
        // `masterBookingDetail`-shaped parent there, which made go_router
        // insert that ancestor's own match into every push and silently
        // mount a shadow `BookingDetailScreen` underneath — including on
        // THIS archive→review path, where popping then landed on the
        // shadow detail screen instead of back on the archive list. See
        // `app_router.dart`'s `review` route registration comment for the
        // full investigation. This isolated probe only proves the PUSH call
        // itself is correct (id, path); it does NOT exercise the ancestor-
        // insertion question — `master_archive_screen_test.dart`'s own
        // «real route topology» group below does, against the real
        // `BookingDetailScreen` + `LeaveClientFeedbackScreen` widgets.
        GoRoute(
          path: '/master/bookings/:bookingId/review',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            key: Key('review-probe-${state.pathParameters['bookingId']}'),
          ),
        ),
      ],
    );

    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
      ],
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-archive')));
    await tester.pump();
    // Pump UNTIL the pushed screen itself lands in the tree, rather than
    // guessing the push transition's duration — deliberately NOT
    // `pumpAndSettle`: `BookingsSkeleton`'s loading state runs a PERPETUAL
    // `repeat(reverse: true)` animation controller, so `pumpAndSettle` never
    // returns while the fetch is still pending (which every gated/
    // loading-state test in this file relies on). `pumpUntilFound` waits
    // exactly as long as the transition takes and no longer. Callers that
    // need the resolved data settle explicitly afterwards.
    await tester.pumpUntilFound(find.byKey(const Key('master-archive-screen')));
  }

  group('async states', () {
    testWidgets('shows the skeleton while the first page is in flight', (
      WidgetTester tester,
    ) async {
      final Completer<PageResponse<Booking>> gate =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) => gate.future);

      await pump(tester);

      expect(find.byKey(const Key('master-archive-skeleton')), findsOneWidget);
      gate.complete(_page(const <Booking>[]));
      await tester.pumpAndSettle();
    });

    testWidgets('renders every fetched row', (WidgetTester tester) async {
      stubList(<Booking>[
        _booking(id: 'b1', status: BookingStatus.completed),
        _booking(
          id: 'b2',
          status: BookingStatus.confirmed,
          awaitingClosure: true,
        ),
      ]);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('b1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('b2')), findsOneWidget);
    });

    testWidgets('a repository failure renders the error state with retry', (
      WidgetTester tester,
    ) async {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => throw Exception('boom'));

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error_retry')), findsOneWidget);
    });

    testWidgets('the TRUE-empty state (no bookings, no filter) shows no '
        'clear-filters CTA', (WidgetTester tester) async {
      stubList(const <Booking>[]);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-archive-empty')), findsOneWidget);
      expect(
        find.byKey(const Key('master-archive-clear-filters')),
        findsNothing,
      );
    });
  });

  group('mobile-security LOW (2026-08-16) — the REAL, newly-live 400 failure '
      'mode of the HISTORY cutover (a pre-81e8166 backend 400s on the '
      'unrecognised `HISTORY` partition value — see '
      '`booking_partition.dart`\'s HARD SEQUENCING HAZARD doc), NOT the '
      'generic `Exception(\'boom\')` UnknownFailure path the async-states '
      'group above covers', () {
    testWidgets(
      'renders the localized errValidation copy — never raw server text, '
      'never an exception string — and shows neither the skeleton nor '
      'the empty state',
      (WidgetTester tester) async {
        // `HttpBookingRepository` never leaks a raw `DioException` to a
        // caller — `booking_repository.dart`'s own file header: "Every
        // method either resolves successfully or throws a [Failure]
        // subclass". A live 400 first passes through
        // `ErrorMapperInterceptor`, whose generic 400/422 rule
        // (`error_mapper_interceptor.dart` ~L170) maps it to
        // `ValidationFailure`; `_mapDioException`'s
        // `if (e.error is Failure) return e.error as Failure;` guard then
        // passes that straight through unchanged. THAT typed value —
        // not a bare `DioException` — is what this mock (standing in for
        // the whole repository, so neither the interceptor nor
        // `_mapDioException` ever runs) must reproduce to test the
        // SCREEN honestly. Stubbing a raw `DioException` here instead
        // would misrepresent the repository's own documented contract
        // AND would actually render `errUnknown`
        // (`MyBookingsErrorState`'s `error is Failure` check would be
        // false for a bare `DioException`) — a DIFFERENT bug than the
        // one this test exists to pin.
        //
        // `cause`/`serverMessage` carry the REAL body a modern Spring
        // Boot default error controller returns for a
        // `MethodArgumentTypeMismatchException` — `{timestamp, status,
        // error, message, path}`, NOT the app's own `{success, data,
        // message}` envelope (same "unrecognised shape" as
        // `error_mapper_interceptor_test.dart`'s "missing errors key"
        // case) — so `fieldErrors` comes back empty exactly as the real
        // interceptor would produce, and the raw `message` is embedded
        // as a concrete string this test can assert is NEVER shown.
        const String rawServerMessage =
            "Failed to convert value of type 'java.lang.String' to "
            "required type 'com.beautica.booking.BookingPartition'; "
            "Failed to convert from type [java.lang.String] to type "
            "[@org.springframework.web.bind.annotation.RequestParam "
            "com.beautica.booking.BookingPartition] for value [HISTORY]";
        final RequestOptions opts = RequestOptions(path: '/api/v1/bookings/me');
        final DioException dioError = DioException(
          requestOptions: opts,
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: opts,
            statusCode: 400,
            data: const <String, dynamic>{
              // Decorative Spring error-envelope filler, never parsed by
              // any code under test — `ValidationFailure` is constructed
              // directly below and `MyBookingsErrorState` only ever reads
              // `Failure.userMessage`, never `cause` or this map.
              // future-date-ok: not a wall-clock comparison of any kind
              'timestamp': '2026-08-16T10:00:00.000+00:00',
              'status': 400,
              'error': 'Bad Request',
              'message': rawServerMessage,
              'path': '/api/v1/bookings/me',
            },
          ),
        );
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
          ),
        ).thenAnswer(
          (_) async => throw ValidationFailure(
            fieldErrors: const <String, String>{},
            serverMessage: rawServerMessage,
            cause: dioError,
          ),
        );

        await pump(tester);
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(MasterArchiveScreen)),
        );

        expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
        expect(
          find.text(l10n.errValidation),
          findsOneWidget,
          reason:
              'the 400-from-an-unrecognised-partition-value failure must '
              'degrade to the SAME localized validation copy every other '
              'ValidationFailure renders — never a raw server string',
        );
        expect(
          find.text(rawServerMessage),
          findsNothing,
          reason:
              'the raw Spring exception message must never reach the '
              'UI verbatim — that is exactly the leak this test guards '
              'against',
        );
        expect(find.byKey(const Key('master-archive-skeleton')), findsNothing);
        expect(
          find.byKey(const Key('master-archive-empty')),
          findsNothing,
          reason:
              'a blank list would read to the master as "no history" — '
              'exactly the misreading this whole HISTORY cutover exists '
              'to fix; the error must render as an ERROR, never as an '
              'empty result',
        );
      },
    );
  });

  group('default request — partition: BookingPartition.history PLUS the '
      'legacy status set, unconditionally', () {
    testWidgets(
      'the landing fetch sends BOTH params together — asserted on the '
      'CAPTURED request',
      (WidgetTester tester) async {
        stubList(const <Booking>[]);

        await pump(tester);
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.getMyBookings(
            statuses: captureAny(named: 'statuses'),
            partition: captureAny(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).captured;
        final Set<BookingStatus>? sentStatuses =
            captured[0] as Set<BookingStatus>?;
        final BookingPartition? sentPartition =
            captured[1] as BookingPartition?;

        expect(sentPartition, BookingPartition.history);
        expect(sentPartition?.wireValue, 'HISTORY');
        expect(sentStatuses, const <BookingStatus>{
          BookingStatus.completed,
          BookingStatus.notCompleted,
          BookingStatus.cancelled,
          BookingStatus.declined,
        });
      },
    );
  });

  group('auto-continue past a raw page with zero filter matches '
      '(mobile-perf HIGH-1/2)', () {
    // Deliberately no `pumpAndSettle()` once the FILTERED request's own
    // `hasMore` can be `true` (i.e. from the filter-apply tap onward until
    // a match or exhaustion is confirmed): the trailing
    // `MyBookingsLoadMoreSpinner` / the auto-continue branch's own spinner
    // wraps a plain `CircularProgressIndicator`, whose indeterminate
    // animation starts unconditionally in `initState` (unlike
    // `BookingsSkeleton`'s guarded `postFrameCallback`) and never stops on
    // its own — `pumpAndSettle` would hang exactly like it would on
    // `BookingsSkeleton` (see `pump()`'s own note above).
    // [stubConfirmedFilterPages] keeps the screen's own initial UNFILTERED
    // landing fetch innocuous (single empty page), so `pumpAndSettle()` IS
    // safe immediately after [pump] (needed to let the route's push
    // transition finish before the filter button is hit-testable) — only
    // the FILTERED request drives `hasMore: true`.
    Future<void> applyConfirmedFilter(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-confirmed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
      await tester.pump();
    }

    testWidgets(
      'a first raw page with ZERO rows matching the active filter, plus '
      'hasMore, is NOT the terminal empty state — the screen keeps '
      'fetching and surfaces the match from the next raw page',
      (WidgetTester tester) async {
        // Page 0: a COMPLETED row only — invisible under the «Підтверджено»
        // filter. totalPages: 2, so hasMore is true after this page.
        // Page 1: the CONFIRMED/awaitingClosure row the filter is meant to
        // surface — totalPages: 2 makes this the LAST page (hasMore false).
        stubConfirmedFilterPages(<int, List<Booking>>{
          0: <Booking>[_booking(id: 'done', status: BookingStatus.completed)],
          1: <Booking>[
            _booking(
              id: 'awaiting',
              status: BookingStatus.confirmed,
              awaitingClosure: true,
            ),
          ],
        }, totalPages: 2);

        await pump(tester);
        await tester.pumpAndSettle();
        await applyConfirmedFilter(tester);

        // Must NOT settle on the terminal empty state while a raw page
        // remains — that is finding HIGH-1 itself.
        await tester.pumpUntilFound(
          find.byKey(const ValueKey<String>('awaiting')),
        );

        expect(
          find.byKey(const ValueKey<String>('awaiting')),
          findsOneWidget,
          reason: 'the match on the SECOND raw page must render',
        );
        expect(
          find.byKey(const Key('master-archive-empty')),
          findsNothing,
          reason:
              'the terminal empty state must never have shown while a '
              'raw page with a potential match was still unfetched',
        );
        expect(
          find.byKey(const Key('master-archive-auto-continue')),
          findsNothing,
          reason: 'the auto-continue branch must have resolved by now',
        );
      },
    );

    testWidgets(
      'the empty-but-hasMore branch attaches the scroll controller too — '
      'not just the non-empty list',
      (WidgetTester tester) async {
        // Gated per-page (rather than [stubConfirmedFilterPages]'s
        // immediately-resolving pages) so this test can pause DETERMINISTICALLY
        // in the auto-continue branch — with only a microtask-speed fetch,
        // that branch can be genuinely transient (page 0 resolves, the
        // scheduled `loadMore()` fires on the very next frame, page 1
        // resolves) and racy to catch with a plain poll.
        final Completer<PageResponse<Booking>> page0Gate =
            Completer<PageResponse<Booking>>();
        final Completer<PageResponse<Booking>> page1Gate =
            Completer<PageResponse<Booking>>();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
          ),
        ).thenAnswer((Invocation invocation) {
          final Set<BookingStatus>? statuses =
              invocation.namedArguments[#statuses] as Set<BookingStatus>?;
          final bool isConfirmedFilterRequest =
              statuses != null &&
              statuses.length == 1 &&
              statuses.single == BookingStatus.confirmed;
          if (!isConfirmedFilterRequest) {
            return Future<PageResponse<Booking>>.value(
              _page(const <Booking>[]),
            );
          }
          final int page = invocation.namedArguments[#page] as int;
          return page == 0 ? page0Gate.future : page1Gate.future;
        });

        await pump(tester);
        await tester.pumpAndSettle();
        await applyConfirmedFilter(tester);

        page0Gate.complete(
          PageResponse<Booking>(
            items: <Booking>[
              _booking(id: 'done', status: BookingStatus.completed),
            ],
            page: 0,
            totalPages: 2,
            totalElements: 2,
          ),
        );
        // Page 0 resolved but only to a filter-invisible row, and page 1 is
        // still gated — the screen must be sitting in the auto-continue
        // branch right now, not stuck on loading and not skipped past it.
        await tester.pumpUntilFound(
          find.byKey(const Key('master-archive-auto-continue')),
        );

        final ListView autoContinueListView = tester.widget<ListView>(
          find.byKey(const Key('master-archive-auto-continue')),
        );
        expect(
          autoContinueListView.controller,
          isNotNull,
          reason:
              'the empty-but-hasMore branch must stay scrollable too '
              '(mobile-perf HIGH-2)',
        );

        page1Gate.complete(
          PageResponse<Booking>(
            items: <Booking>[
              _booking(
                id: 'awaiting',
                status: BookingStatus.confirmed,
                awaitingClosure: true,
              ),
            ],
            page: 1,
            totalPages: 2,
            totalElements: 2,
          ),
        );
        await tester.pumpUntilFound(
          find.byKey(const ValueKey<String>('awaiting')),
        );
      },
    );

    testWidgets('the loading branch attaches the scroll controller too', (
      WidgetTester tester,
    ) async {
      final Completer<PageResponse<Booking>> gate =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) => gate.future);

      await pump(tester);

      final ListView loadingListView = tester.widget<ListView>(
        find.byKey(const Key('master-archive-skeleton')),
      );
      expect(
        loadingListView.controller,
        isNotNull,
        reason: 'a scroll/pull gesture must be live even while loading',
      );

      gate.complete(_page(const <Booking>[]));
      await tester.pumpAndSettle();
    });

    testWidgets('the error branch attaches the scroll controller too', (
      WidgetTester tester,
    ) async {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => throw Exception('boom'));

      await pump(tester);
      await tester.pumpAndSettle();

      final ListView errorListView = tester.widget<ListView>(
        find.ancestor(
          of: find.byKey(const Key('my_bookings_error')),
          matching: find.byType(ListView),
        ),
      );
      expect(errorListView.controller, isNotNull);
    });

    testWidgets(
      'the terminal empty state attaches the scroll controller too, and '
      'still shows once the raw pages are EXHAUSTED (hasMore == false) '
      'with zero filter matches — the fix must not regress into never '
      'showing an empty state at all',
      (WidgetTester tester) async {
        // Single raw page (totalPages: 1 → hasMore false immediately),
        // containing only a COMPLETED row — invisible under the
        // «Підтверджено» filter, and nothing left to fetch.
        stubConfirmedFilterPages(<int, List<Booking>>{
          0: <Booking>[_booking(id: 'done', status: BookingStatus.completed)],
        }, totalPages: 1);

        await pump(tester);
        await tester.pumpAndSettle();

        await applyConfirmedFilter(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('master-archive-empty')), findsOneWidget);
        expect(
          find.byKey(const Key('master-archive-clear-filters')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-archive-auto-continue')),
          findsNothing,
        );

        final ListView emptyListView = tester.widget<ListView>(
          find.ancestor(
            of: find.byKey(const Key('master-archive-empty')),
            matching: find.byType(ListView),
          ),
        );
        expect(emptyListView.controller, isNotNull);
      },
    );

    // ── mobile-qa MEDIUM fix (2026-08-16) — the CAP BOUNDARY itself ────────
    //
    // Every case above resolves within ONE automatic attempt (a match on
    // raw page 2). None of them ever drive the filter through enough
    // consecutive zero-match raw pages to reach
    // [_MasterArchiveScreenState._kMaxAutoContinueAttempts] (3) — the
    // fallback a master actually hits when a narrow filter needs MORE than
    // 3 raw pages before a match (or exhaustion) surfaces. That is this
    // page's own core use case for the «Підтверджено» filter (the master
    // scanning back through old, mostly-COMPLETED history for the rare
    // still-open row), so leaving the cap itself unpinned was a real gap,
    // not a theoretical one.
    testWidgets('the automatic burst stops at EXACTLY 3 attempts and shows the '
        'manual «Завантажити ще» CTA — not the terminal empty state, and '
        'not an unbounded scheduling loop', (WidgetTester tester) async {
      final List<int> filteredPageRequests =
          stubUnboundedEmptyConfirmedFilter();

      await pump(tester);
      await tester.pumpAndSettle();
      await applyConfirmedFilter(tester);

      // Deterministically ride out all 3 automatic attempts to the cap —
      // NOT `pumpAndSettle` beforehand: the interim scanning spinner is
      // an INDETERMINATE `CircularProgressIndicator` (see this group's
      // own file-level note above) and would hang it.
      await tester.pumpUntilFound(
        find.byKey(const Key('master-archive-continue')),
      );

      expect(
        filteredPageRequests,
        <int>[0, 1, 2, 3],
        reason:
            'page 0 (the filter-apply fetch) plus EXACTLY 3 automatic '
            'continuations — a regression to unbounded scheduling would '
            'keep this list growing past 3; a regression that stops '
            'scheduling too early would leave it short. Asserted '
            'against the REPOSITORY call log, not just the rendered '
            'output, so a bug that renders the right widget by '
            'coincidence still fails loudly here.',
      );
      expect(
        find.byKey(const Key('master-archive-load-more')),
        findsOneWidget,
        reason:
            'the manual CTA — the master\'s way back in once the '
            'automatic budget is spent',
      );
      expect(
        find.byKey(const Key('master-archive-empty')),
        findsNothing,
        reason:
            'hasMore is still true here — the terminal empty state '
            'would be WRONG, a raw page may still hold a match the '
            'master has to ask for manually',
      );

      // Prove the stop is genuine, not a coincidence of timing: settle
      // fully now that the cap state (`_ArchiveContinueState` — a
      // static widget, no ticker) is showing, and confirm NOTHING
      // further was requested.
      await tester.pumpAndSettle();
      expect(
        filteredPageRequests,
        <int>[0, 1, 2, 3],
        reason:
            'no further post-frame callback may still be scheduled '
            'after the cap — a 5th entry here would mean the budget '
            'check was bypassed, not merely rendered around',
      );
    });

    testWidgets('tapping «Завантажити ще» RE-ARMS a fresh bounded burst (the '
        'counter resets to 0, up to 3 MORE automatic attempts) — not one '
        'lone call, and not a resumed UNBOUNDED loop', (
      WidgetTester tester,
    ) async {
      final List<int> filteredPageRequests =
          stubUnboundedEmptyConfirmedFilter();

      await pump(tester);
      await tester.pumpAndSettle();
      await applyConfirmedFilter(tester);
      await tester.pumpUntilFound(
        find.byKey(const Key('master-archive-continue')),
      );
      expect(filteredPageRequests, <int>[0, 1, 2, 3]);

      await tester.tap(find.byKey(const Key('master-archive-load-more')));
      await tester.pump();

      // `onLoadMore` resets [_MasterArchiveScreenState._autoContinueAttempts]
      // to 0 in the SAME `setState` that fires the tap's own manual
      // `loadMore()` — so the cap state unmounts (losing
      // `master-archive-continue`) while a FRESH 3-attempt burst runs,
      // then remounts once THAT one is spent too. Bracketing gone→found
      // catches this deterministically regardless of exactly how many
      // frames the burst takes.
      await tester.pumpUntilGone(
        find.byKey(const Key('master-archive-continue')),
      );
      await tester.pumpUntilFound(
        find.byKey(const Key('master-archive-continue')),
      );

      expect(
        filteredPageRequests,
        <int>[0, 1, 2, 3, 4, 5, 6, 7],
        reason:
            'the tap\'s own manual fetch (page 4) PLUS a fresh '
            '3-attempt automatic burst (pages 5-7) — a broken re-arm '
            'that fired only the tap\'s own call would stop at '
            '[0,1,2,3,4]; a broken re-arm that resumed an UNBOUNDED '
            'loop instead of a fresh BOUNDED one would keep growing '
            'past 7',
      );

      await tester.pumpAndSettle();
      expect(
        filteredPageRequests,
        <int>[0, 1, 2, 3, 4, 5, 6, 7],
        reason:
            'the SECOND cap must hold too — no drift into an unbounded '
            'loop on a repeated exhaustion',
      );
    });

    testWidgets(
      'pull-to-refresh ALSO resets the auto-continue counter — pinning '
      'the reset path so it is not dead code',
      (WidgetTester tester) async {
        final List<int> filteredPageRequests =
            stubUnboundedEmptyConfirmedFilter();

        await pump(tester);
        await tester.pumpAndSettle();
        await applyConfirmedFilter(tester);
        await tester.pumpUntilFound(
          find.byKey(const Key('master-archive-continue')),
        );
        expect(filteredPageRequests, <int>[0, 1, 2, 3]);

        // `RefreshIndicatorState.show()` is the standard deterministic way
        // to drive a pull-to-refresh in a widget test without simulating a
        // drag gesture. Deliberately NOT awaited directly — its own Future
        // only resolves once `_refresh()`'s fetch AND the indicator's
        // retract animation both complete, and the auto-continue burst
        // that follows keeps an INDETERMINATE spinner mounted in between
        // (same hang risk this whole group avoids `pumpAndSettle` for).
        // `pumpUntilGone`/`pumpUntilFound` below pump real frames on their
        // own, which is all `show()` needs to make progress.
        unawaited(
          tester
              .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
              .show(),
        );

        await tester.pumpUntilGone(
          find.byKey(const Key('master-archive-continue')),
        );
        await tester.pumpUntilFound(
          find.byKey(const Key('master-archive-continue')),
        );

        expect(
          filteredPageRequests,
          <int>[0, 1, 2, 3, 0, 1, 2, 3],
          reason:
              '`_refresh()` re-fetches page 0 fresh — the SAME page '
              'index again, proving a genuine refetch happened rather '
              'than a resumed stale burst — AND resets the local attempt '
              'counter. Without that reset this would stop dead after '
              'the lone refetch (`[...,0]`) instead of running a full '
              'SECOND 3-attempt burst (`[...,0,1,2,3]`) — the observable '
              'difference that proves the reset path is not dead code.',
        );
      },
    );
  });

  group(
    '«Підтверджено» filter row = «Потребують закриття», with NO new UI',
    () {
      testWidgets(
        'ticking ONLY «Підтверджено» in the reused BookingsFilterSheet '
        'narrows the visible list to exactly the awaitingClosure row — a '
        'non-awaiting row in the fixture proves this is not vacuous',
        (WidgetTester tester) async {
          stubList(<Booking>[
            _booking(
              id: 'awaiting',
              status: BookingStatus.confirmed,
              awaitingClosure: true,
            ),
            _booking(id: 'done', status: BookingStatus.completed),
          ]);

          await pump(tester);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('awaiting')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey<String>('done')), findsOneWidget);

          await tester.tap(
            find.byKey(const Key('master-bookings-filter-button')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('master-bookings-filter-status-confirmed')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('master-bookings-filter-apply')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey<String>('awaiting')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey<String>('done')), findsNothing);
        },
      );
    },
  );

  group('«Виконано» close action', () {
    testWidgets(
      'renders ONLY on the awaitingClosure row, never on a plain COMPLETED '
      'row',
      (WidgetTester tester) async {
        stubList(<Booking>[
          _booking(
            id: 'awaiting',
            status: BookingStatus.confirmed,
            awaitingClosure: true,
          ),
          _booking(id: 'done', status: BookingStatus.completed),
        ]);

        await pump(tester);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-booking-card-complete-awaiting')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-booking-card-complete-done')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tap → CompleteBookingDialog (non-appointment copy) → confirm → calls '
      'completeBooking with the tapped booking\'s id',
      (WidgetTester tester) async {
        stubList(<Booking>[
          _booking(
            id: 'awaiting',
            status: BookingStatus.confirmed,
            awaitingClosure: true,
          ),
        ]);
        when(() => repo.completeBooking('awaiting')).thenAnswer((_) async {});

        await pump(tester);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('master-booking-card-complete-awaiting')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('complete-booking-dialog')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await tester.pumpAndSettle();

        verify(() => repo.completeBooking('awaiting')).called(1);
      },
    );

    testWidgets(
      'RE-ENTRANCY: a second tap fired while the WRITE is still in flight '
      '(dialog already dismissed, button visible again) is ignored — the '
      'guard spans the write, not just the dialog',
      (WidgetTester tester) async {
        // A raw double-tap on the SAME frame cannot reach this button twice
        // in practice: `showDialog`'s route insertion covers it before any
        // further pump can occur (empirically confirmed while authoring this
        // suite), so the physically-reachable re-entrancy window is AFTER
        // the dialog is dismissed but WHILE the write it kicked off is still
        // pending — exactly `booking_cancel_navigation.dart`'s own
        // "the write phase was the one part of the flow ... un-guarded"
        // finding, restated for this screen. Gate the write itself to open
        // that window on demand.
        stubList(<Booking>[
          _booking(
            id: 'awaiting',
            status: BookingStatus.confirmed,
            awaitingClosure: true,
          ),
        ]);
        final Completer<void> gate = Completer<void>();
        when(
          () => repo.completeBooking('awaiting'),
        ).thenAnswer((_) => gate.future);

        await pump(tester);
        await tester.pumpAndSettle();

        final Finder closeButton = find.byKey(
          const Key('master-booking-card-complete-awaiting'),
        );
        await tester.tap(closeButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await tester.pump();
        // Pump UNTIL the dialog's own exit transition finishes leaving the
        // tree, rather than guessing a fixed duration — deliberately NOT
        // `pumpAndSettle` (the write is still pending on `gate`, so nothing
        // else settles).
        await tester.pumpUntilGone(
          find.byKey(const Key('complete-booking-dialog')),
        );

        expect(
          find.byKey(const Key('complete-booking-dialog')),
          findsNothing,
          reason:
              'the dialog must already be gone — the button is visible '
              'and physically tappable again at this point',
        );

        // Second tap DURING the still-pending write. MUTATION NOTE: at this
        // point the row's `NeumorphicButton(loading: closing, onPressed:
        // closing ? null : onComplete)` is ALSO watching the same in-flight
        // flag, so this specific tap is discriminated by the WIDGET disable
        // — mutating away the standalone `if (ref.read(
        // masterArchiveInFlightProvider)) return;` synchronous check inside
        // `_confirmComplete` alone does NOT turn this assertion red, because
        // that check is unreachable from a real tap once the button is
        // already disabled by the same watched flag. That check remains
        // defense-in-depth for a caller that could reach `_confirmComplete`
        // without going through this disabled button (mirrors
        // `startBookingCancel`'s own "reads it FIRST … rather than relying
        // on the UI alone" reasoning) — this widget test proves the
        // END-TO-END outcome (one write, one dialog, ever), not that one
        // specific internal line fired.
        await tester.tap(closeButton);
        await tester.pump();

        expect(
          find.byKey(const Key('complete-booking-dialog')),
          findsNothing,
          reason:
              'a broken guard would let this second tap open a SECOND '
              'confirmation dialog while the first write is still pending',
        );

        gate.complete();
        await tester.pumpAndSettle();

        verify(() => repo.completeBooking('awaiting')).called(1);
      },
    );

    testWidgets(
      'backing out of the dialog (tapping «Скасувати») writes nothing',
      (WidgetTester tester) async {
        stubList(<Booking>[
          _booking(
            id: 'awaiting',
            status: BookingStatus.confirmed,
            awaitingClosure: true,
          ),
        ]);

        await pump(tester);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('master-booking-card-complete-awaiting')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('complete-booking-keep')));
        await tester.pumpAndSettle();

        verifyNever(() => repo.completeBooking(any()));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2026-08-16 — `_confirmComplete` migrated from a hand-rolled
  // `ref.invalidate(masterArchiveProvider); ref.invalidate(bookingsDayProvider);`
  // pair to the shared `invalidateBookingViewsAfterProviderClose` helper
  // (`booking_calendar_invalidation.dart`) — this screen's OWN close action
  // already invalidated both correctly by hand; this group pins that the
  // migration preserved the observable behaviour exactly, on both targets.
  // The archive-list half is already implicit in the existing «Виконано»
  // tests above (the screen watches `masterArchiveProvider` directly, so a
  // dropped invalidation would leave the closed row's card still showing
  // «Виконано»/spinner state) — this group's own contribution is the
  // `bookingsDayProvider` half, which nothing above establishes a live
  // subscription to.
  // -------------------------------------------------------------------------

  group('day-timeline invalidation survives the shared-helper migration '
      '(2026-08-16)', () {
    void stubDayList(_MockBookingRepository repo) {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
    }

    testWidgets('a successful «Виконано» close refetches an actively-watched '
        'bookingsDayProvider family member for the booking\'s day', (
      WidgetTester tester,
    ) async {
      final Booking booking = _booking(
        id: 'awaiting',
        status: BookingStatus.confirmed,
        awaitingClosure: true,
      );
      stubList(<Booking>[booking]);
      stubDayList(repo);
      when(() => repo.completeBooking('awaiting')).thenAnswer((_) async {});

      await pump(tester);
      await tester.pumpAndSettle();

      // Mirrors `booking_detail_provider_footer_test.dart`'s identical
      // "day-list invalidation on success" group: a LIVE subscription on
      // the plain empty-status day-list member for this booking's day,
      // standing in for whatever screen underneath keeps it warm.
      final BookingsDayQuery dayQuery = BookingsDayQuery.of(
        day: booking.startAt,
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MasterArchiveScreen)),
      );
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
          .listen(bookingsDayProvider(dayQuery), (_, _) {});
      addTearDown(sub.close);
      await container.read(bookingsDayProvider(dayQuery).future);

      await tester.tap(
        find.byKey(const Key('master-booking-card-complete-awaiting')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2); // initial watch fetch + the post-complete refetch.
    });
  });

  group('«Відгук» review action', () {
    testWidgets('renders ONLY on a COMPLETED row, never on an awaitingClosure '
        'CONFIRMED row — a fixture carrying both proves this is not vacuous', (
      WidgetTester tester,
    ) async {
      stubList(<Booking>[
        _booking(
          id: 'awaiting',
          status: BookingStatus.confirmed,
          awaitingClosure: true,
        ),
        _booking(id: 'done', status: BookingStatus.completed),
      ]);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-booking-card-review-done')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-review-awaiting')),
        findsNothing,
      );
      // The «Виконано» / «Відгук» pairing is mutually exclusive by
      // construction (`Booking.awaitingClosure` requires
      // `status == confirmed`; the review slot requires
      // `status == completed`) — pinned here alongside the review
      // assertions above, on the SAME two-row fixture, so a future change
      // to either gate that let both render on one row would turn one of
      // these four expectations red.
      expect(
        find.byKey(const Key('master-booking-card-complete-awaiting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-complete-done')),
        findsNothing,
      );
    });

    testWidgets(
      "tap pushes RouteNames.clientReview with the tapped row's own booking "
      'id — via a real context.push, not a bare callback assertion',
      (WidgetTester tester) async {
        stubList(<Booking>[
          _booking(id: 'done', status: BookingStatus.completed),
        ]);
        // `_openReview` prefetches `bookingDetailProvider('done')` (finding-2
        // fix) before pushing, which calls this on the shared mock —
        // unstubbed, mocktail throws `MissingStubError`. The probe route
        // never reads the result, so any resolved `Booking` is fine here.
        when(() => repo.getBookingById(any())).thenAnswer(
          (_) async => _booking(id: 'done', status: BookingStatus.completed),
        );

        await pump(tester);
        await tester.pumpAndSettle();

        expect(
          RouteNames.clientReview('done'),
          '/master/bookings/done/review',
          reason:
              'sanity-check the route this test drives through actually is '
              'the one MasterArchiveScreen calls',
        );

        await tester.tap(
          find.byKey(const Key('master-booking-card-review-done')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('review-probe-done')), findsOneWidget);
      },
    );
  });

  group('navigation', () {
    testWidgets('the back arrow pops the route', (WidgetTester tester) async {
      stubList(const <Booking>[]);

      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('master-archive-screen')), findsOneWidget);

      await tester.tap(find.byKey(const Key('master-archive-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('from-stub')), findsOneWidget);
      expect(find.byKey(const Key('master-archive-screen')), findsNothing);
    });
  });

  group('«Відгук» real route topology (regression guard — finding 1 & 2)', () {
    // Mirrors `app_router.dart`'s ACTUAL registration, not a simplified
    // stand-in: `archive` nested as a real child of the `masterBookings`
    // tab-root (exactly like production — the archive DOES legitimately
    // inherit that ancestor), `:bookingId` a sibling child rendering the
    // REAL `BookingDetailScreen`, and `review` registered as a STANDALONE
    // top-level route — NOT nested under `:bookingId`. This is the shape
    // that would go RED if a future change reintroduced nesting review
    // under the detail route (see `app_router.dart`'s `review` route
    // registration comment for why that silently mounts a shadow
    // `BookingDetailScreen`).
    Future<void> pumpRealTopology(
      WidgetTester tester, {
      required Booking archiveRow,
      required void Function() bumpFetchCount,
    }) async {
      stubList(<Booking>[archiveRow]);

      final GoRouter router = GoRouter(
        // Straight to the archive location so go_router computes the full
        // ancestor + leaf match list ONCE, at parse time — pushing it as a
        // second step after an initial `masterBookings` location would
        // insert a SECOND, redundant `masterBookings` match (ancestor-
        // insertion applies per-push, not de-duplicated across an existing
        // stack), which is beside the point of this test.
        initialLocation: RouteNames.masterBookingsArchive,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.masterBookings,
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(key: Key('master-bookings-tab-root-stub')),
            routes: <RouteBase>[
              GoRoute(
                path: 'archive',
                builder: (BuildContext context, GoRouterState state) =>
                    const MasterArchiveScreen(),
              ),
              GoRoute(
                path: ':bookingId',
                builder: (BuildContext context, GoRouterState state) =>
                    BookingDetailScreen(
                      bookingId: state.pathParameters['bookingId']!,
                    ),
              ),
            ],
          ),
          // STANDALONE — a sibling of `masterBookings`, exactly matching
          // `app_router.dart`'s real registration; deliberately NOT nested
          // under the `:bookingId` route above.
          GoRoute(
            path: '/master/bookings/:bookingId/review',
            builder: (BuildContext context, GoRouterState state) =>
                LeaveClientFeedbackScreen(
                  bookingId: state.pathParameters['bookingId']!,
                ),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          masterServiceCatalogProvider.overrideWith(
            (ref) async => const <MasterService>[],
          ),
          bookingDetailProvider(archiveRow.id).overrideWith((ref) async {
            bumpFetchCount();
            return archiveRow;
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-archive-screen')), findsOneWidget);
    }

    testWidgets('tapping «Відгук» from an archive row lands on '
        'LeaveClientFeedbackScreen, NEVER mounts a shadow BookingDetailScreen, '
        'prefetches bookingDetailProvider with exactly ONE network fetch, and '
        'popping returns to the ARCHIVE list — not a detail screen', (
      WidgetTester tester,
    ) async {
      final Booking booking = _booking(
        id: 'done',
        status: BookingStatus.completed,
      );
      int fetchCount = 0;
      await pumpRealTopology(
        tester,
        archiveRow: booking,
        bumpFetchCount: () => fetchCount++,
      );

      expect(
        find.byType(BookingDetailScreen),
        findsNothing,
        reason: 'no detail screen was ever navigated to on this path',
      );
      expect(fetchCount, 0, reason: 'no prefetch has fired yet');

      await tester.tap(
        find.byKey(const Key('master-booking-card-review-done')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      expect(
        find.byType(BookingDetailScreen),
        findsNothing,
        reason:
            'REGRESSION GUARD (finding 1): nesting `review` under the '
            'detail route would silently mount BookingDetailScreen '
            'underneath via go_router\'s ancestor-match insertion — this '
            'must never happen on the archive entry path',
      );
      expect(
        fetchCount,
        1,
        reason:
            'the archive list is fed by GET /bookings/me, which never '
            'warms bookingDetailProvider — `_openReview` must prefetch it '
            'exactly once, via `listenManual` (NOT a bare `ref.read(...'
            'future)`, which would not survive the navigation — proven RED '
            'first), so the round trip overlaps the push transition AND '
            'LeaveClientFeedbackScreen\'s own `ref.watch` reuses the SAME '
            'element instead of firing an independent second GET',
      );

      await tester.tap(find.byKey(const Key('leave-client-feedback-back')));
      await tester.pumpAndSettle();

      expect(
        find.byType(LeaveClientFeedbackScreen),
        findsNothing,
        reason: 'popped away from the review screen',
      );
      expect(
        find.byType(BookingDetailScreen),
        findsNothing,
        reason:
            'REGRESSION GUARD (finding 1): pop must not land on a '
            'shadow detail screen',
      );
      expect(
        find.byKey(const Key('master-archive-screen')),
        findsOneWidget,
        reason:
            'REGRESSION GUARD (finding 1): popping the review screen must '
            'return to the ARCHIVE list the master actually came from',
      );
    });
  });
}
