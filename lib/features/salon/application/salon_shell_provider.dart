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

/// The IN-SCREEN «Про салон»/«Команда»/«Послуги»/«Відгуки» sub-tab index of
/// [SalonManagementProfileScreen] while it is hosted by the Salon Shell.
///
/// Generated provider name: `salonManageTabProvider` (a family — call it with
/// the target salon id).
///
/// A companion to [SalonShell], not a replacement: the two indices address
/// DIFFERENT rows (a 4-item bottom nav vs a 4-item in-screen switcher) whose
/// values only partly overlap, so they stay separate pieces of state that
/// [SalonShellScreen] reconciles in one place. The shell mounts the profile
/// screen TWICE in one `IndexedStack` (nav slot 0 «Салон» and slot 2
/// «Команда»); both instances read THIS provider, which is what makes the
/// in-screen row and the bottom nav one shared selection.
///
/// Family-keyed on `salonId` and `autoDispose`, mirroring [SalonShell]
/// exactly — a different salon, or a fresh shell visit, starts on 0.
@riverpod
class SalonManageTab extends _$SalonManageTab {
  @override
  int build(String salonId) => 0;

  /// Selects sub-tab [index].
  void select(int index) => state = index;
}
