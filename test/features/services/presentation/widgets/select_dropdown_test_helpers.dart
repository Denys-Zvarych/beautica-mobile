// Phase 16.6 — shared interaction helpers for driving the searchable single-
// select dropdowns that replaced the category / service-type chip rows on
// [ServiceForm].
//
// The dropdown options now live inside a modal bottom sheet rather than inline
// chips. To keep the existing suites green WITHOUT weakening any assertion, the
// SETUP/interaction is funnelled through these helpers: open the field's menu,
// then tap the option (which still carries the same `chip-category-<wire>` /
// `chip-service-type-<id>` key the old chip used). Selecting an option pops the
// sheet, so a `pumpAndSettle()` follows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the category dropdown menu (taps the closed field) and waits for the
/// sheet to settle. After this, option rows keyed `chip-category-<wire>` and
/// the `chip-category-suggest` footer are in the tree.
Future<void> openCategoryMenu(WidgetTester tester) async {
  await tester.pumpAndSettle(); // resolve approvedCategoriesProvider first
  await tester.ensureVisible(find.byKey(const Key('select-category-field')));
  await tester.tap(find.byKey(const Key('select-category-field')));
  await tester.pumpAndSettle();
}

/// Opens the category menu and taps the option for [wire], then settles (the
/// sheet closes on selection). Equivalent to the old single chip tap.
Future<void> selectCategoryOption(WidgetTester tester, String wire) async {
  await openCategoryMenu(tester);
  final option = find.byKey(Key('chip-category-$wire'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

/// Opens the service-type dropdown menu (taps the closed field) and settles.
/// After this, option rows keyed `chip-service-type-<id>` are in the tree.
Future<void> openServiceTypeMenu(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('select-service-type-field')),
  );
  await tester.tap(find.byKey(const Key('select-service-type-field')));
  await tester.pumpAndSettle();
}

/// Opens the service-type menu and taps the option for [id], then settles.
Future<void> selectServiceTypeOption(WidgetTester tester, String id) async {
  await openServiceTypeMenu(tester);
  final option = find.byKey(Key('chip-service-type-$id'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}
