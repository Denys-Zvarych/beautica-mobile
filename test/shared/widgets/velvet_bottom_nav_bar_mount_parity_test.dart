// mobile-debugger fix — VelvetBottomNavBar mounting-convention parity across
// the four master tab screens.
//
// ## The bug
//
// `VelvetBottomNavBar` is not a shell — every master tab screen builds its
// own instance. Before this fix, two compounding problems made it render
// differently (or not at all) depending which screen hosted it:
//
//   1. `ServicesListScreen` and `MasterScheduleScreen` never rendered the bar
//      at all — tapping Послуги or Графік made it vanish.
//   2. The two screens that DID render it (`MasterBookingsScreen` via
//      `Scaffold.bottomNavigationBar`, `MasterProfileScreen` via
//      `ProfileScaffold` nesting it as the LAST child of the body's own
//      `SafeArea`) mounted it through two DIFFERENT conventions, so on any
//      device with a non-zero bottom inset (gesture-nav home indicator) they
//      produced different heights: `Scaffold` only zeroes the bottom
//      `MediaQuery` padding it hands to `body` when `bottomNavigationBar` is
//      non-null, so `MasterBookingsScreen`'s bar (hosted in that slot) got
//      the REAL device inset for its own internal `SafeArea(top: false)` to
//      consume, while `MasterProfileScreen`'s bar — nested inside the body's
//      OWN outer `SafeArea` — saw that inset already stripped to zero by the
//      time it got there, and rendered at its bare `minHeight: 62` instead.
//
// Both problems are invisible at the default zero-inset `MediaQueryData`
// widget tests run under by default — that is exactly why they shipped. This
// suite pumps all four real screens under a NON-ZERO bottom inset (34,
// representative of a gesture-nav home indicator) and asserts the bar is
// found on every one of them, at the IDENTICAL rendered [Rect].
//
// ## The fix
//
// All four screens now mount `VelvetBottomNavBar` via the SAME convention:
// `Scaffold.bottomNavigationBar`, chosen (over nesting it inside the body's
// `SafeArea`) because it is what `Scaffold` already special-cases — supplying
// `bottomNavigationBar` is what makes `Scaffold` zero the body's bottom
// `MediaQuery` padding, so the bar's own internal `SafeArea(top: false)` is
// the ONE place the real device inset gets consumed, on every screen, with no
// double-counting. See `ProfileScaffold.bottomNavBar`'s doc comment and
// `VelvetBottomNavBar`'s own class doc for the same reasoning at the
// production call sites.
//
// ## Mutation coverage
//
// This file's own header documents a manual mutation check performed
// alongside authoring it: reverting `MasterProfileScreen` (via
// `ProfileScaffold`) back to nesting the bar inside the body's `SafeArea`
// reproduces a `Rect` mismatch and fails the "identical Rect" assertion
// below; restoring the fix makes it pass again. See the handoff report for
// the actual before/after command output.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Never-resolving fakes — the bar is static chrome rendered OUTSIDE every
// screen's AsyncValue switch, so a permanently-loading state is enough to
// pump each screen far enough to measure its bar without needing to satisfy
// every downstream data dependency.
// ---------------------------------------------------------------------------

class _LoadingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() => Completer<Master>().future;
}

class _LoadingServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Completer<List<MasterService>>().future;
}

class _LoadingEffectiveSchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleScope scope, ScheduleRange range) =>
      Completer<List<EffectiveDay>>().future;
}

class _LoadingWeeklySchedule extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build(ScheduleScope scope) =>
      Completer<List<WeeklySchedule>>().future;
}

class _FixedAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'u1',
      email: 'master@beautica.ua',
      role: UserRole.independentMaster,
      firstName: 'Тест',
      lastName: 'Майстер',
    ),
    accessToken: 'test-token',
  );
}

class _MockBookingRepository extends Mock implements BookingRepository {}

// ---------------------------------------------------------------------------
// Pump harness — plain MaterialApp (none of the four screens touch a
// GoRouter synchronously during build; every `context.push`/`context.go`
// call sits inside a tap callback), with a `builder:` MediaQuery override
// injecting a NON-ZERO bottom inset. This is deliberate: the mounting bug is
// invisible under the default zero-inset MediaQueryData every other widget
// test in this repo pumps under.
// ---------------------------------------------------------------------------

const double _bottomInset = 34;

Future<void> _pumpWithBottomInset(
  WidgetTester tester,
  Widget screen, {
  required List<Object> overrides,
}) async {
  installOverflowGuard();
  // A single test pumps FOUR different screens in sequence, each with a
  // different-length overrides list. Flutter would otherwise reuse the same
  // root ProviderScope Element across pumps (same widget type/position) and
  // Riverpod asserts overrides can be updated but never resized — a fresh
  // `Key` per pump forces a full unmount/remount instead.
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      key: UniqueKey(),
      overrides: overrides.cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(bottom: _bottomInset)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  // Pump (not settle) — several of these notifiers never resolve by design;
  // one frame is enough for the static chrome (the bar) to lay out.
  await tester.pump();
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  Future<void> pumpMasterProfile(WidgetTester tester) => _pumpWithBottomInset(
    tester,
    const MasterProfileScreen(),
    overrides: <Object>[
      authProvider.overrideWith(_FixedAuth.new),
      masterProfileProvider.overrideWith(_LoadingMasterProfile.new),
    ],
  );

  Future<void> pumpServices(WidgetTester tester) => _pumpWithBottomInset(
    tester,
    const ServicesListScreen(),
    overrides: <Object>[
      servicesListProvider.overrideWith(_LoadingServicesList.new),
    ],
  );

  Future<void> pumpBookings(WidgetTester tester) {
    final repo = _MockBookingRepository();
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) => Completer<PageResponse<Booking>>().future);
    return _pumpWithBottomInset(
      tester,
      const MasterBookingsScreen(),
      overrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
      ],
    );
  }

  Future<void> pumpSchedule(WidgetTester tester) => _pumpWithBottomInset(
    tester,
    const MasterScheduleScreen(),
    overrides: <Object>[
      authProvider.overrideWith(_FixedAuth.new),
      // Phase 312 — `MasterScheduleScreen` with no explicit `scope` now
      // resolves "me" through `ownScheduleScopeProvider`
      // (own_schedule_scope.dart), which for INDEPENDENT_MASTER watches
      // `masterProfileProvider` before this provider ever runs. Without this
      // override that reaches the REAL (unmocked) `HttpMasterRepository` and
      // leaves a pending Dio timer at teardown ("A Timer is still pending
      // even after the widget tree was disposed") — mirrors
      // `pumpMasterProfile`'s own override above.
      masterProfileProvider.overrideWith(_LoadingMasterProfile.new),
      effectiveScheduleProvider.overrideWith(_LoadingEffectiveSchedule.new),
      weeklyScheduleProvider.overrideWith(_LoadingWeeklySchedule.new),
    ],
  );

  testWidgets(
    'the bar renders on all four master tab screens under a non-zero bottom '
    'inset — the two screens that lacked it entirely (Послуги, Графік) '
    'before this fix',
    (tester) async {
      await pumpMasterProfile(tester);
      expect(
        find.byType(VelvetBottomNavBar),
        findsOneWidget,
        reason: 'MasterProfileScreen',
      );

      await pumpServices(tester);
      expect(
        find.byType(VelvetBottomNavBar),
        findsOneWidget,
        reason: 'ServicesListScreen — was missing the bar entirely',
      );

      await pumpBookings(tester);
      expect(
        find.byType(VelvetBottomNavBar),
        findsOneWidget,
        reason: 'MasterBookingsScreen',
      );

      await pumpSchedule(tester);
      expect(
        find.byType(VelvetBottomNavBar),
        findsOneWidget,
        reason: 'MasterScheduleScreen — was missing the bar entirely',
      );
    },
  );

  testWidgets(
    'the rendered bar Rect is IDENTICAL across all four master tab screens '
    'under a non-zero (34dp) bottom inset — the mismatch that is invisible '
    'at the default zero-inset MediaQueryData',
    (tester) async {
      await pumpMasterProfile(tester);
      final Rect profileRect = tester.getRect(find.byType(VelvetBottomNavBar));

      await pumpServices(tester);
      final Rect servicesRect = tester.getRect(find.byType(VelvetBottomNavBar));

      await pumpBookings(tester);
      final Rect bookingsRect = tester.getRect(find.byType(VelvetBottomNavBar));

      await pumpSchedule(tester);
      final Rect scheduleRect = tester.getRect(find.byType(VelvetBottomNavBar));

      expect(
        servicesRect,
        profileRect,
        reason:
            'ServicesListScreen\'s bar must occupy the exact same Rect as '
            'MasterProfileScreen\'s — a mismatch here means the two screens '
            'are mounting the bar through different conventions again.',
      );
      expect(
        bookingsRect,
        profileRect,
        reason:
            'MasterBookingsScreen\'s bar must occupy the exact same Rect as '
            'MasterProfileScreen\'s.',
      );
      expect(
        scheduleRect,
        profileRect,
        reason:
            'MasterScheduleScreen\'s bar must occupy the exact same Rect as '
            'MasterProfileScreen\'s — this is the screen the fix\'s own '
            'header specifically calls out as needing the body SafeArea not '
            'to double-consume the inset once bottomNavigationBar is set.',
      );
    },
  );
}
