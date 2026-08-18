// Phase 244 — `/schedule?date=yyyy-MM-dd` query-param parsing at the route
// layer (`app_router.dart`'s `RouteNames.masterSchedule` GoRoute builder).
//
// `parseApiDate`'s own bound-hardening (0001..9999 year, no month rollover)
// is unit-tested exhaustively in `test/shared/formatters/api_date_test.dart`
// — this file's job is the ONE thing that test cannot reach: that the
// ROUTE's own try/catch around it actually swallows both `FormatException`
// AND the defence-in-depth `ArgumentError` net and falls back to `null`
// (today) rather than crashing the screen. `MainActivity` is
// `exported="true"` (see `RouteNames.masterSchedule`'s doc), so this query
// param is attacker-controlled on a cold deep link — a route that let a
// malformed value propagate as an uncaught exception would crash the whole
// app from outside it.
//
// This mirrors `app_router.dart`'s `RouteNames.masterSchedule` builder body
// verbatim in a minimal router (the same pattern
// `master_bookings_screen_test.dart`'s `_pumpWithNavRoutes` and
// `master_schedule_screen_test.dart`'s `_routes()` already use for
// route-local tests) rather than standing up the full auth-redirect-gated
// `appRouter(ref)` — the auth/role gate itself is covered generically by
// `auth_redirect_test.dart` / `master_bookings_route_guard_test.dart`.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/pump_app.dart';

/// Fixed independent-master session — [MasterScheduleScreen] gates its edit
/// affordances on the real role resolver, so a settled session is required
/// for the screen to render past its loading gate.
class _FixedAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u1', email: 'm@b.c', role: UserRole.independentMaster),
    accessToken: 'tkn',
  );
}

/// No published hours anywhere — the emptiest possible resolved state, so
/// this file's assertions stay about the ROUTE's query-param handling, not
/// about any particular calendar content.
class _EmptySchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async =>
      const <EffectiveDay>[];
}

class _EmptyWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build() async => const <WeeklySchedule>[];
}

/// Verbatim mirror of `app_router.dart`'s `RouteNames.masterSchedule` builder
/// body — see this file's header for why it is duplicated rather than
/// exercised through the full `appRouter(ref)`.
DateTime? _parseDateQueryParam(String? raw) {
  if (raw == null) return null;
  try {
    return parseApiDate(raw);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

GoRouter _router({required String location}) => GoRouter(
  initialLocation: location,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterSchedule,
      builder: (BuildContext context, GoRouterState state) {
        final DateTime? initialDate = _parseDateQueryParam(
          state.uri.queryParameters['date'],
        );
        return MasterScheduleScreen(initialDate: initialDate);
      },
    ),
  ],
);

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(() => _FixedAuth()),
  effectiveScheduleProvider.overrideWith(() => _EmptySchedule()),
  weeklyScheduleProvider.overrideWith(() => _EmptyWeekly()),
];

void main() {
  testWidgets('a malformed ?date= value does not crash the route — it falls '
      'back to null (today), never propagating the exception', (
    WidgetTester tester,
  ) async {
    await tester.pumpRoutedApp(
      _router(location: '/schedule?date=not-a-date'),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'an attacker-controlled deep-link query param must never crash '
          'the app',
    );
    expect(find.byType(MasterScheduleScreen), findsOneWidget);
  });

  testWidgets(
    'the hardened out-of-range case (9999999999999-01-01) also falls back '
    'to null without crashing — the exact FormatException/ArgumentError '
    'distinction parseApiDate hardens against',
    (WidgetTester tester) async {
      await tester.pumpRoutedApp(
        _router(location: '/schedule?date=9999999999999-01-01'),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MasterScheduleScreen), findsOneWidget);
    },
  );

  testWidgets('an absent ?date= renders with a null initialDate, unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpRoutedApp(
      _router(location: '/schedule'),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<MasterScheduleScreen>(find.byType(MasterScheduleScreen))
          .initialDate,
      isNull,
    );
  });

  testWidgets('a well-formed ?date= parses through to initialDate', (
    WidgetTester tester,
  ) async {
    await tester.pumpRoutedApp(
      _router(location: '/schedule?date=2026-08-12'),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<MasterScheduleScreen>(find.byType(MasterScheduleScreen))
          .initialDate,
      DateTime(2026, 8, 12),
    );
  });
}
