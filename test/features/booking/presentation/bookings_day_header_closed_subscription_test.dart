// DAY-family twin of `bookings_week_header_closed_subscription_test.dart`.
// Same prod crash mechanism (Sentry, 1.9.0+12) through `bookingsDayProvider` /
// `DayKeepAliveLru`; RED without `lru.forget` in `BookingsDayNotifier.build`'s
// `ref.onDispose`.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

const User _master = User(
  id: 'master-1',
  email: 'master@example.test',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _master, accessToken: 'token-1');
}

/// Empty day; counts calls so the test can show the return-trip refetch.
class _EmptyDayRepository implements BookingRepository {
  int calls = 0;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
    bool asMaster = false,
  }) async {
    calls++;
    return const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 0,
      totalElements: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Host: [covered] = the bookings route is under an opaque route (Navigator
/// turns its TickerMode off → Riverpod pauses the Consumer); [onScreen] =
/// the bookings screen is mounted at all (`go` elsewhere unmounts it);
/// [tick] = an unrelated parent rebuild (the `StatefulElement.update` chain
/// in the Sentry stack).
class _Host extends StatefulWidget {
  const _Host({super.key, required this.query});

  final BookingsDayQuery query;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool covered = false;
  bool onScreen = true;
  int tick = 0;
  WidgetRef? invalidatorRef;

  void update(VoidCallback f) => setState(f);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          // The covering route's own Consumer — runs the real invalidation.
          Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              invalidatorRef = ref;
              return const SizedBox.shrink();
            },
          ),
          TickerMode(
            enabled: !covered,
            child: onScreen
                ? Consumer(
                    // Same shape as `header`: a fresh `Consumer` widget
                    // per parent build, watching `bookingsDayProvider`.
                    builder: (BuildContext context, WidgetRef ref, Widget? _) {
                      final BookingsDayState? day = ref
                          .watch(bookingsDayProvider(widget.query))
                          .value;
                      return Text('day:${day != null} tick:$tick');
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

Future<void> _frames(WidgetTester tester, [int n = 4]) async {
  for (int i = 0; i < n; i++) {
    await tester.pump();
  }
}

void main() {
  initBeauticaTimeZones();

  testWidgets(
    'day header Consumer survives invalidate-while-covered → leave → return '
    '(no closed ProviderSubscription read)',
    (WidgetTester tester) async {
      final _EmptyDayRepository repo = _EmptyDayRepository();
      final ProviderContainer container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(_FixedAuthNotifier.new),
        ].cast(),
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      // A FILTERED day: not one of the hand-built keys the fan-out eagerly
      // re-reads, so the production path is a plain invalidate of a
      // watched-but-paused member (the crash shape).
      final BookingsDayQuery query = BookingsDayQuery.of(
        day: DateTime(2026, 11, 11),
        statuses: <BookingStatus>{BookingStatus.values.first},
      );
      final GlobalKey<_HostState> host = GlobalKey<_HostState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _Host(key: host, query: query),
        ),
      );
      await _frames(tester);
      expect(find.text('day:true tick:0'), findsOneWidget);

      // 1. Cover /master/bookings (booking detail / reschedule flow).
      host.currentState!.update(() => host.currentState!.covered = true);
      await _frames(tester);

      // 2. The flow's real day fan-out while covered: the day IS watched
      //    (paused); the PRODUCTION reschedule fan-out (the one
      //    `booking_confirm_screen` calls) invalidates it and does NOT evict.
      invalidateBookingsDayAfterAppointmentItemReschedule(
        host.currentState!.invalidatorRef!,
        affectedDays: <DateTime>{query.day},
      );
      await _frames(tester);

      // 3. `go(/master/profile)` — the bookings screen is replaced.
      host.currentState!.update(() => host.currentState!.onScreen = false);
      await _frames(tester);

      // 4. Back to /master/bookings — a fresh Consumer watches the day.
      host.currentState!.update(() {
        host.currentState!
          ..onScreen = true
          ..covered = false;
      });
      await _frames(tester);
      expect(find.text('day:true tick:0'), findsOneWidget);

      // 5. Any later parent rebuild (the Sentry `StatefulElement.update`
      //    chain) re-runs the header builder's `ref.watch`.
      host.currentState!.update(() => host.currentState!.tick++);
      await _frames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('day:true tick:1'), findsOneWidget);
    },
  );
}
