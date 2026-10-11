// F1 regression: the app theme must never request an unbundled Nunito weight.
//
// `GoogleFonts.nunitoTextTheme()` with no base wraps ThemeData.light()'s M3
// 2021 typography, whose titleMedium / titleSmall / labelLarge / labelMedium /
// labelSmall are w500. Nunito-Medium.ttf is not bundled and runtime fetching
// is off, so google_fonts throws an unawaited async error and those roles
// silently fall back to the system font.

import 'dart:async';

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Map<String, TextStyle?> _roles(TextTheme t) => <String, TextStyle?>{
  'displayLarge': t.displayLarge,
  'displayMedium': t.displayMedium,
  'displaySmall': t.displaySmall,
  'headlineLarge': t.headlineLarge,
  'headlineMedium': t.headlineMedium,
  'headlineSmall': t.headlineSmall,
  'titleLarge': t.titleLarge,
  'titleMedium': t.titleMedium,
  'titleSmall': t.titleSmall,
  'bodyLarge': t.bodyLarge,
  'bodyMedium': t.bodyMedium,
  'bodySmall': t.bodySmall,
  'labelLarge': t.labelLarge,
  'labelMedium': t.labelMedium,
  'labelSmall': t.labelSmall,
};

Future<ThemeData> _effectiveTheme(WidgetTester tester) async {
  // MaterialApp runs ThemeData.localize, which merges the M3 geometry (the
  // w500 title/label roles) UNDER the app textTheme. That merged theme is what
  // widgets actually read — velvetTheme().textTheme alone has no weights.
  late ThemeData captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: velvetTheme(),
      home: Builder(
        builder: (BuildContext c) {
          captured = Theme.of(c);
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

List<String> _unbundled(TextTheme t, Set<int> bundled) {
  final List<String> bad = <String>[];
  for (final MapEntry<String, TextStyle?> e in _roles(t).entries) {
    final TextStyle? s = e.value;
    final String family = s?.fontFamily ?? '';
    if (!family.startsWith('Nunito')) continue;
    final int w = (s?.fontWeight ?? FontWeight.w400).value;
    if (!bundled.contains(w)) bad.add('${e.key}: $family w$w');
  }
  return bad;
}

void main() {
  const Set<int> bundledNunito = <int>{400, 600, 700, 800};

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'effective textTheme: no Nunito role requests an unbundled weight',
    (WidgetTester tester) async {
      final ThemeData theme = await _effectiveTheme(tester);
      final List<String> bad = _unbundled(theme.textTheme, bundledNunito);
      expect(bad, isEmpty, reason: 'unbundled: $bad');
    },
  );

  testWidgets(
    'effective primaryTextTheme: no Nunito role requests an unbundled weight',
    (WidgetTester tester) async {
      final ThemeData theme = await _effectiveTheme(tester);
      final List<String> bad = _unbundled(
        theme.primaryTextTheme,
        bundledNunito,
      );
      expect(bad, isEmpty, reason: 'unbundled: $bad');
    },
  );

  testWidgets('every Material text role resolves to a bundled Nunito weight', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = await _effectiveTheme(tester);
    for (final MapEntry<String, TextStyle?> e in _roles(
      theme.textTheme,
    ).entries) {
      expect(
        e.value?.fontFamily,
        startsWith('Nunito'),
        reason: '${e.key} must not fall back to the system font',
      );
    }
  });

  testWidgets('theme build queues no failing google_fonts load', (
    WidgetTester tester,
  ) async {
    final List<Object> errors = <Object>[];
    await runZonedGuarded(() async {
      await _effectiveTheme(tester);
      await GoogleFonts.pendingFonts();
    }, (Object e, StackTrace _) => errors.add(e));
    expect(errors, isEmpty, reason: 'google_fonts load errors: $errors');
  });
}
