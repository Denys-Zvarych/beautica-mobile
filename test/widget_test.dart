// Phase 1.4 — top-level smoke test: BeauticaApp boots without crashing.
//
// The Phase 0 counter scaffold (_BootstrapHome) was removed when
// MaterialApp.router + go_router landed in Phase 1.4. This test verifies
// that ProviderScope + MaterialApp.router initialises without throwing an
// exception. It does NOT assert the specific route — that is covered by
// test/routing/app_router_test.dart and test/routing/auth_redirect_test.dart.
//
// [secureStorageProvider] and [authRepositoryProvider] are overridden so
// that [authProvider] resolves without platform channels or network I/O.
// [pumpAndSettle] is intentionally avoided here: both [SplashScreen]'s
// [CircularProgressIndicator] and [LoadingSkeleton]'s [FadeTransition] run
// continuous animations that prevent it from ever returning.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes/fake_auth_repository.dart';
import 'helpers/fakes/fake_secure_storage.dart';

void main() {
  testWidgets('BeauticaApp boots without crashing', (
    WidgetTester tester,
  ) async {
    // Empty storage → authProvider resolves to Unauthenticated.
    // No platform channels or network calls are exercised.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        ],
        child: const BeauticaApp(),
      ),
    );

    // Single pump resolves the first frame.
    // Enough to verify the widget tree builds and the router initialises.
    await tester.pump();

    // The app has rendered at least one Scaffold (SplashScreen or LoginScreen
    // depending on how quickly authProvider resolves). Either way the app is up.
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });
}
