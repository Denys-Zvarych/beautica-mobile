import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/app_theme.dart';

/// Beautica mobile entry point.
///
/// Phase 1.1 — wires [ProviderScope] (Riverpod root) and the Material 3
/// theme factories ([lightTheme], [darkTheme]) seeded from the brand
/// palette. Phase 1.2 adds the Manrope type scale (see `app_theme.dart`)
/// and pins [GoogleFonts.config.allowRuntimeFetching] to debug-only —
/// release builds must rely on the cached/bundled font (Phase 11 will
/// move Manrope into `assets/fonts/` for fully offline release builds).
/// The router (`go_router`), localization delegates, and feature screens
/// land in Phase 1.4 / 1.3 — until then [BeauticaApp] renders the default
/// `flutter create` counter so the widget smoke test stays meaningful as a
/// proof-of-life signal for the build pipeline.
void main() {
  GoogleFonts.config.allowRuntimeFetching = kDebugMode;
  runApp(const ProviderScope(child: BeauticaApp()));
}

class BeauticaApp extends StatelessWidget {
  const BeauticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beautica',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      home: const _BootstrapHome(),
    );
  }
}

/// Placeholder home screen — Phase 1.4 swaps this out for the router.
class _BootstrapHome extends StatefulWidget {
  const _BootstrapHome();

  @override
  State<_BootstrapHome> createState() => _BootstrapHomeState();
}

class _BootstrapHomeState extends State<_BootstrapHome> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() => _counter++);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        title: const Text('Beautica'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Phase 0 — bootstrap'),
            Text('$_counter', style: theme.textTheme.headlineMedium),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('bootstrap_increment_fab'),
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        backgroundColor: theme.colorScheme.secondary,
        foregroundColor: theme.colorScheme.onSecondary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
