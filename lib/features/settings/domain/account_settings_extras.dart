// Phase 21.13 — navigation payload for `RouteNames.settings`.
//
// The shared account page (`SettingsScreen`) is pushed from several hubs
// (client menu, master menu, and — this phase — a salon owner's «Загальне»
// row). Every existing caller pushes with NO `extra` at all
// (`context.push(RouteNames.settings)`), which must keep resolving to
// `state.extra == null` and therefore the screen's all-`false`/`null`
// defaults — see `app_router.dart`'s `/settings` registration.
//
// Deliberately NOT carrying `showLogout` / `showHelp`: every caller this
// phase's doc lists passes `false` for both, and `SettingsScreen`'s own
// header documents logout as living only on the settings hub (the canonical
// logout entry point) — see `phase-135-21.13-account-settings-screen.md`'s
// scope decision. Do not add fields with no consumer.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_settings_extras.freezed.dart';

/// Navigation extra for `RouteNames.settings`, carrying the owner-only
/// «Видалити салон» row's target.
@freezed
abstract class AccountSettingsExtras with _$AccountSettingsExtras {
  const factory AccountSettingsExtras({
    /// Backend Salon-row UUID the delete action targets. `null` means the
    /// row never renders, regardless of [showDeleteSalon].
    String? salonId,

    /// Whether to render the destructive «Видалити салон» row below a
    /// hairline divider. Fails closed: the row also requires [salonId] to be
    /// non-null before it renders — see `SettingsScreen`'s own doc.
    @Default(false) bool showDeleteSalon,
  }) = _AccountSettingsExtras;
}
