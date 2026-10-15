// «Надіслати» on CategoryRequestDialog is single-flight.
//
// The CTA used to be guarded only by `loading: _submitting` /
// `onPressed: _submitting ? null : …`, which take effect on the NEXT rebuild:
// three taps landing in one frame each ran `_handleSubmit`, each POSTed a
// category request, and each success continuation then popped — the first
// pop closed the dialog, the next ones popped the SCREEN BENEATH it.
//
// Taps are fired WITHOUT a pump between them (a pump lets the rebuild-only
// disable kick in and hides the bug).
//
// Anti-vacuity (verified when written):
//   * swap the CTA back to `onPressed:` (no `onPressedAsync`) -> 3 requests;
//   * additionally drop `dismissOverlay`'s `isCurrent` check -> the host
//     screen under the dialog is popped as well.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('root')),
      routes: <RouteBase>[
        GoRoute(
          path: 'host',
          builder: (_, _) => Scaffold(
            key: const Key('host-screen'),
            body: Builder(
              builder: (BuildContext ctx) => ElevatedButton(
                key: const Key('trigger'),
                onPressed: () => showCategoryRequestDialog(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('«Надіслати» x3 with no pump between -> 1 request, dialog '
      'closes once, the screen beneath stays', (tester) async {
    final _MockServiceRepository repo = _MockServiceRepository();
    final Completer<void> request = Completer<void>();
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
        initialServiceName: any(named: 'initialServiceName'),
      ),
    ).thenAnswer((_) => request.future);

    final GoRouter router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    unawaited(router.push<void>('/host'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      'Нарощування вій',
    );
    await tester.pump();

    final Finder submit = find.byKey(const Key('btn-submit-suggest-category'));
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.tap(submit);

    verify(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
        initialServiceName: any(named: 'initialServiceName'),
      ),
    ).called(1);

    request.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CategoryRequestDialog), findsNothing);
    expect(
      find.byKey(const Key('host-screen')),
      findsOneWidget,
      reason: 'a second success pop must not pop the screen under the dialog',
    );
  });
}
