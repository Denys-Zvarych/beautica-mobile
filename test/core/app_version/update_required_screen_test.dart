// Phase 438 — UpdateRequiredScreen + UpdateGateOverlay (the builder gate).
//
// Pumped exactly where production mounts it: inside `MaterialApp.router`'s
// `builder`, ABOVE the router's Navigator — so the screen must render and
// handle back without any route / Overlay ancestor.

import 'package:beautica_mobile/core/app_version/store_link.dart';
import 'package:beautica_mobile/core/app_version/update_gate_provider.dart';
import 'package:beautica_mobile/core/app_version/update_mark.dart';
import 'package:beautica_mobile/core/app_version/update_required_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

const Key _appKey = Key('behind-the-gate');

final class _FixedGate extends UpdateGate {
  _FixedGate(this._state);

  final UpdateGateState _state;

  @override
  UpdateGateState build() => _state;
}

/// Counts the listeners registered on a stand-in for the intro controller.
final class _CountingAnimation extends Animation<double> {
  int listeners = 0;
  int statusListeners = 0;

  @override
  double get value => 1;

  @override
  AnimationStatus get status => AnimationStatus.completed;

  @override
  void addListener(VoidCallback listener) => listeners++;

  @override
  void removeListener(VoidCallback listener) => listeners--;

  @override
  void addStatusListener(AnimationStatusListener listener) => statusListeners++;

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      statusListeners--;
}

const UpdateGateState _required = UpdateGateState.required(
  packageName: 'com.beautica.app',
  installedVersion: '1.5.0',
  storeUrl: 'https://play.google.com/store/apps/details?id=com.beautica.app',
);

GoRouter _router() => GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(key: _appKey, body: Text('app')),
    ),
  ],
);

/// The production placement: the overlay wraps the router's child.
Widget _app(UpdateGateState state) => ProviderScope(
  overrides: [updateGateProvider.overrideWith(() => _FixedGate(state))],
  child: MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
    routerConfig: _router(),
    builder: (BuildContext context, Widget? child) =>
        UpdateGateOverlay(child: child ?? const SizedBox.shrink()),
  ),
);

Widget _screen(StoreUrlLauncher launcher) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('uk'),
  home: UpdateRequiredScreen(
    // A STAGING install: its id has no Play listing, so the market:// target
    // must come from the sanitized store URL, never from this.
    packageName: 'com.beautica.app.staging',
    installedVersion: '1.5.0',
    storeUrl: 'https://evil.example/apk',
    launcher: launcher,
  ),
);

void main() {
  final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));

  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('UpdateGateOverlay in the MaterialApp.router builder', () {
    testWidgets('ok → the app renders, no gate', (tester) async {
      await tester.pumpWidget(_app(const UpdateGateState.ok()));
      await tester.pumpAndSettle();
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(UpdateRequiredScreen.screenKey), findsNothing);
    });

    testWidgets('required → ONLY the gate: title, body, CTA, installed '
        'version; the app is not in the tree', (tester) async {
      await tester.pumpWidget(_app(_required));
      await tester.pumpAndSettle();

      expect(find.byKey(UpdateRequiredScreen.screenKey), findsOneWidget);
      expect(find.byKey(_appKey), findsNothing);
      expect(find.text(uk.updateRequiredTitle), findsOneWidget);
      expect(find.text(uk.updateRequiredBody), findsOneWidget);
      expect(find.text(uk.updateRequiredButton), findsOneWidget);
      expect(
        find.text(uk.updateRequiredInstalledVersion('1.5.0')),
        findsOneWidget,
      );
      expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsNothing);
    });

    testWidgets('system back exits the app (SystemNavigator.pop) and never '
        'reveals the app', (tester) async {
      final List<String> platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(_required));
      await tester.pumpAndSettle();

      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // The framework's own fallback ALSO calls SystemNavigator.pop when no
      // observer handles the pop — but then returns false. `handled` is what
      // pins the screen's didPopRoute override (removing it fails here).
      expect(
        handled,
        isTrue,
        reason: 'the gate itself must handle back, not the framework fallback',
      );
      expect(
        platformCalls.where((String m) => m == 'SystemNavigator.pop'),
        hasLength(1),
      );
      expect(find.byKey(UpdateRequiredScreen.screenKey), findsOneWidget);
      expect(find.byKey(_appKey), findsNothing);
    });
  });

  group('«Оновити»', () {
    testWidgets('opens market:// first, externally, for the PROD listing id '
        '(not the installed staging package)', (tester) async {
      final List<(Uri, LaunchMode)> calls = <(Uri, LaunchMode)>[];
      await tester.pumpWidget(
        _screen((
          Uri uri, {
          LaunchMode mode = LaunchMode.platformDefault,
        }) async {
          calls.add((uri, mode));
          return true;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();

      expect(
        calls.single.$1.toString(),
        'market://details?id=com.beautica.app',
      );
      expect(calls.single.$2, LaunchMode.externalApplication);
      expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsNothing);
    });

    testWidgets('both targets fail → the inline Play error; a tampered '
        'storeUrl is replaced by the prod Play URL', (tester) async {
      final List<Uri> calls = <Uri>[];
      await tester.pumpWidget(
        _screen((
          Uri uri, {
          LaunchMode mode = LaunchMode.platformDefault,
        }) async {
          calls.add(uri);
          return false;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();

      expect(calls.map((Uri u) => u.toString()), <String>[
        'market://details?id=com.beautica.app',
        kPlayStoreFallbackUrl,
      ]);
      expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsOneWidget);
      expect(find.text(uk.updateRequiredPlayError), findsOneWidget);
    });

    testWidgets('a retry that succeeds clears the error', (tester) async {
      bool succeed = false;
      await tester.pumpWidget(
        _screen(
          (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
              succeed,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsOneWidget);

      succeed = true;
      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsNothing);
    });
  });

  group('animation objects are built once, not per build', () {
    testWidgets('the screen reuses ONE text-in animation across rebuilds', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(
          (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
              false,
        ),
      );
      await tester.pumpAndSettle();
      Animation<double> titleOpacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text(uk.updateRequiredTitle),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity;
      final Animation<double> before = titleOpacity();

      // Each «Оновити» tap rebuilds the screen twice (opening → error).
      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();

      expect(identical(titleOpacity(), before), isTrue);
    });

    testWidgets('UpdateMark registers no extra listener on progress per '
        'rebuild', (tester) async {
      final _CountingAnimation progress = _CountingAnimation();
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return Center(child: UpdateMark(progress: progress));
            },
          ),
        ),
      );
      final (int, int) first = (progress.listeners, progress.statusListeners);
      for (int i = 0; i < 3; i++) {
        rebuild(() {});
        await tester.pump();
      }
      expect((progress.listeners, progress.statusListeners), first);
    });
  });

  testWidgets('reduced motion renders the final frame at once', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _screen(
          (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
              true,
        ),
      ),
    );
    await tester.pump();
    final FadeTransition title = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text(uk.updateRequiredTitle),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(title.opacity.value, 1);
  });

  testWidgets('no overflow on a short screen at 1.3× text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 480),
          textScaler: TextScaler.linear(1.3),
        ),
        child: _screen(
          (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
              false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(UpdateRequiredScreen.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsOneWidget);
  });
}
