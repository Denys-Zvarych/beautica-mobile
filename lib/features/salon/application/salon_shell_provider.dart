// Phase 21.8 — Salon Shell tab-index state.
//
// Family-keyed on `salonId` so switching to a DIFFERENT salon (a future
// multi-salon owner picking a different card from the My Salons hub) resets
// to tab 0 («Салон») instead of carrying over whatever tab was open in the
// previous salon's shell. `autoDispose` (the `@riverpod` default, no
// `keepAlive`) so the index never leaks across sessions — a fresh shell visit
// always starts on «Салон».

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'salon_shell_provider.g.dart';

/// The Salon Shell's currently-selected bottom-nav tab index.
///
/// Generated provider name: `salonShellProvider` (a family — call it with the
/// target salon id, e.g. `salonShellProvider(salonId)`).
@riverpod
class SalonShell extends _$SalonShell {
  @override
  int build(String salonId) => 0;

  /// Selects tab [index]. Called by [SalonBottomNav]'s `onSelect`.
  void select(int index) => state = index;
}
