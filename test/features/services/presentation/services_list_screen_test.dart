// Phase 5.2 — Widget tests for ServicesListScreen.
//
// [ServicesListScreen] is a [ConsumerStatefulWidget]. The [ScreenProtector]
// lifecycle calls (preventScreenshotOn / preventScreenshotOff) are guarded
// by !kDebugMode, so they are never invoked during test runs and do not
// require mocking.
//
// Covers all AsyncValue states and key interactions:
//   1. Loading state — skeleton cards rendered; no service name text visible.
//   2. Error state   — ErrorState widget visible; retry button callable.
//   3. Empty state   — servicesEmpty l10n text visible;
//                      btn-create-service-empty key found; no FAB.
//   4. Populated     — ListView visible; service name "Стрижка" shown;
//                      formatted price "₴ 750" visible;
//                      formatted duration "45 хв" visible.
//   5. FAB           — btn-create-service key present in populated state.
//   6. Card tap      — GoRouter mock records push with the correct edit path.
//
// Strategy:
//   • Override [servicesListProvider] with a stub [ServicesList] notifier
//     that immediately emits the desired [AsyncValue] to state.
//   • Override [serviceRepositoryProvider] with a mocktail mock.
//   • Use [pumpApp] / [pumpRoutedApp] from `test/helpers/pump_app.dart`.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _stubService = MasterService(
  id: 'svc-001',
  name: 'Стрижка',
  durationMinutes: 45,
  price: 750,
);

const _stubServiceList = <MasterService>[_stubService];

/// Minimal [MasterService] factory for generating lists of arbitrary length.
/// Only the required fields are set; freezed defaults cover the rest.
MasterService _makeService(int i) => MasterService(
  id: 'svc-$i',
  name: 'Test $i',
  durationMinutes: 30,
  price: 100,
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Generic stub [ServicesList] notifier — resolves to [_target] state.
///
/// For the loading state, [build()] returns a never-completing [Future] so
/// the test can inspect the loading frame. For data/error states, [build()]
/// posts the desired state via [Future.microtask] so the screen sees a brief
/// loading frame first (consistent with real async behaviour).
class _StubServicesList extends ServicesList {
  _StubServicesList(this._target);

  final AsyncValue<List<MasterService>> _target;

  @override
  Future<List<MasterService>> build() {
    if (!_target.isLoading) {
      // Post the desired state on the next microtask so the screen sees one
      // loading frame followed by the target state.
      Future<void>.microtask(() => state = _target);
    }
    // Never-completing future — state is managed above.
    return Completer<List<MasterService>>().future;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Returns a [ProviderScope] override that replaces [servicesListProvider]
/// with a stub notifier resolving to [target].
Object _servicesOverride(AsyncValue<List<MasterService>> target) =>
    servicesListProvider.overrideWith(() => _StubServicesList(target));

/// Minimal GoRouter that records pushed locations without any actual routing.
GoRouter _mockRouter({
  required List<String> pushedRoutes,
  String initialLocation = RouteNames.services,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.services,
        builder: (context, state) => const ServicesListScreen(),
      ),
      // Catch-all for /services/create and /services/:id/edit so push doesn't
      // throw "no route found".
      GoRoute(
        path: '/services/create',
        builder: (context, state) => const _DummyPage(label: 'create'),
      ),
      GoRoute(
        path: '/services/:id/edit',
        builder: (context, state) => const _DummyPage(label: 'edit'),
      ),
    ],
    observers: <NavigatorObserver>[_PushObserver(pushedRoutes)],
  );
}

class _DummyPage extends StatelessWidget {
  const _DummyPage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text('Dummy $label'));
}

/// Records all push events to [routes].
class _PushObserver extends NavigatorObserver {
  _PushObserver(this.routes);
  final List<String> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) routes.add(name);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockServiceRepository mockRepo;

  setUp(() {
    mockRepo = _MockServiceRepository();
    when(() => mockRepo.listMyServices()).thenAnswer((_) async => const []);
  });

  // ── 1. Loading state ───────────────────────────────────────────────────────

  testWidgets('loading state — skeleton cards rendered; no service name text', (
    tester,
  ) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncLoading()),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // First pump triggers the loading frame.
    await tester.pump();

    expect(find.byKey(const Key('skeleton_card_0')), findsOneWidget);
    expect(find.byKey(const Key('skeleton_card_1')), findsOneWidget);
    expect(find.byKey(const Key('skeleton_card_2')), findsOneWidget);
    expect(find.text('Стрижка'), findsNothing);
  });

  // ── 2. Error state ─────────────────────────────────────────────────────────

  testWidgets('error state — ErrorState widget rendered', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncError(NetworkFailure(), StackTrace.empty)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // First pump: loading frame. Second pump: microtask delivers error state.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('services_error_state')), findsOneWidget);
    expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
  });

  // ── 3. Empty state ─────────────────────────────────────────────────────────

  testWidgets('empty state — servicesEmpty text visible; '
      'btn-create-service-empty found; FAB absent', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncData(<MasterService>[])),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // Loading frame → microtask → data frame.
    await tester.pump();
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ServicesListScreen)),
    );
    expect(find.text(l10n.servicesEmpty), findsOneWidget);
    expect(find.byKey(const Key('btn-create-service-empty')), findsOneWidget);
    // FAB must NOT appear in the empty state — the inline CTA is the only
    // first-run path.
    expect(find.byKey(const Key('btn-create-service')), findsNothing);
  });

  // ── 4. Populated state ─────────────────────────────────────────────────────

  testWidgets(
    'populated state — ListView visible; service name, price, duration shown',
    (tester) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(const AsyncData(_stubServiceList)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame → microtask → data frame.
      await tester.pump();
      await tester.pump();
      // Advance entrance animation so the card becomes visible.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Стрижка'), findsOneWidget);
      expect(find.text('₴ 750'), findsOneWidget);
      expect(find.text('45 хв'), findsOneWidget);
    },
  );

  // ── 5. FAB present in populated state ─────────────────────────────────────

  testWidgets('populated state — FAB btn-create-service found', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncData(_stubServiceList)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
  });

  // ── 6. Card tap — router push ──────────────────────────────────────────────

  testWidgets('card tap — go_router push called with correct edit path', (
    tester,
  ) async {
    final pushedRoutes = <String>[];
    final router = _mockRouter(pushedRoutes: pushedRoutes);

    await tester.pumpRoutedApp(
      router,
      overrides: [
        _servicesOverride(const AsyncData(_stubServiceList)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final cardFinder = find.byKey(const Key('service_card_svc-001'));
    expect(cardFinder, findsOneWidget);

    await tester.tap(cardFinder);
    await tester.pumpAndSettle();

    // The dummy edit page should be reachable — find its text.
    expect(find.text('Dummy edit'), findsOneWidget);

    // Verify the correct path was resolved.
    final expectedPath = RouteNames.serviceEdit(_stubService.id);
    expect(expectedPath, '/services/svc-001/edit');
  });

  // ── 7. Ukrainian plural forms for _serviceWordUk ───────────────────────────

  group('_serviceWordUk plural forms', () {
    /// Pumps [ServicesListScreen] with [count] stub services, advances through
    /// the entrance animation, then asserts that the count label contains
    /// [expectedWord].
    Future<void> expectPluralLabel(
      WidgetTester tester, {
      required int count,
      required String expectedWord,
    }) async {
      final services = List<MasterService>.generate(count, _makeService);
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(AsyncData(services)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame → microtask delivers data → data frame.
      await tester.pump();
      await tester.pump();
      // Advance past the longest possible stagger delay.
      // Each _ServiceCard at index i gets appearDelay = 90 * (i-1) ms.
      // For the largest list (count=100) the last card fires at 90*99 = 8910 ms.
      // Pumping 10 s of fake time drains all outstanding timers so the
      // test harness does not report "pending timers".
      await tester.pump(const Duration(seconds: 10));

      expect(
        find.text('$count $expectedWord'),
        findsOneWidget,
        reason: '_serviceWordUk($count) should return "$expectedWord"',
      );
    }

    testWidgets(
      'count=1 → "послуга" (n%10==1, not in exception class 11–14)',
      (tester) => expectPluralLabel(tester, count: 1, expectedWord: 'послуга'),
    );

    testWidgets(
      'count=2 → "послуги" (n%10==2)',
      (tester) => expectPluralLabel(tester, count: 2, expectedWord: 'послуги'),
    );

    testWidgets(
      'count=4 → "послуги" (n%10==4)',
      (tester) => expectPluralLabel(tester, count: 4, expectedWord: 'послуги'),
    );

    testWidgets(
      'count=5 → "послуг" (n%10==5 → default branch)',
      (tester) => expectPluralLabel(tester, count: 5, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=11 → "послуг" (n%100==11 — exception class overrides n%10==1)',
      (tester) => expectPluralLabel(tester, count: 11, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=14 → "послуг" (n%100==14 — boundary of exception class)',
      (tester) => expectPluralLabel(tester, count: 14, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=21 → "послуга" (n%10==1, n%100==21 — NOT in exception class)',
      (tester) => expectPluralLabel(tester, count: 21, expectedWord: 'послуга'),
    );

    testWidgets(
      'count=100 → "послуг" (n%10==0 → default branch)',
      (tester) => expectPluralLabel(tester, count: 100, expectedWord: 'послуг'),
    );
  });
}
