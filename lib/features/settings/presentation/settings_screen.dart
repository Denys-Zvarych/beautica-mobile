// Account page («Акаунт») — reached from the master settings hub's Account row.
// A richer account surface: a Мова (language → "Українська") placeholder row and
// a Сповіщення (notifications) toggle placeholder.
//
// No Save button — each control acts immediately (the placeholders show a hint).
//
// Logout is not surfaced here — it lives on the settings hub (the canonical
// logout entry point).
//
// Phase 21.13 — optional owner-only «Видалити салон» row. Additive: both
// [salonId] and [showDeleteSalon] default so every existing caller
// (`const SettingsScreen()`, or `context.push(RouteNames.settings)` with no
// `extra`) renders EXACTLY as before. The row itself fails closed — it only
// renders when BOTH `showDeleteSalon` is true AND `salonId` is non-null, so
// a caller that asks for the row without a target never gets a delete button
// with nothing to delete. REUSE-FIRST: the delete flow itself is NOT
// reimplemented here — it delegates to `runDeleteSalonFlow`
// (`features/salon/presentation/delete_salon_flow.dart`), the same function
// `SalonSettingsScreen` (Phase 21.2) was rewired onto in this same change.
//
// Relocation (2026-09-08) — «Видалити акаунт» row, at the very bottom, below
// the delete-salon block. It used to sit on the CLIENT settings HUB
// (`client_settings_hub_screen.dart`), which was the wrong screen — that
// hub's own title is «Налаштування»; THIS page (`accountTitle` = «Акаунт») is
// the «Акаунт» screen the row belongs on. `DELETE /api/v1/users/me` is
// allowed server-side for CLIENT, SALON_ADMIN, SALON_MASTER, and
// INDEPENDENT_MASTER (403 for SALON_OWNER, deliberately — an owner owns a
// salon with staff beneath them), and this screen is shared across roles
// (reached by CLIENT via the hub's row-account, by both master roles via the
// master/salon-master settings hub, and by SALON_ADMIN via their own-profile
// tune button), so the row is gated behind [_showDeleteAccountRow] — the
// [canSelfDeleteAccountProvider] selector (`features/auth/presentation/
// auth_selectors.dart`), a sibling of [isSalonOwnerProvider] above using the
// same hardened idiom. [isClientProvider] is NOT reused here — widened
// 2026-09-08 (SALON_ADMIN / SALON_MASTER / INDEPENDENT_MASTER reachability)
// to a purpose-built capability selector instead of repurposing the
// role-identity one. REUSE-FIRST: the flow itself is untouched structurally
// — [runDeleteAccountFlow] (`features/settings/presentation/
// delete_account_flow.dart`), moved here verbatim from the hub along with
// its two-`ValueNotifier` flag pair (`inFlight` / `loading` — see that
// file's header doc for why they are NOT merged into one). It gained one
// additive parameter, `confirmBody`, so this screen can supply role-aware
// dialog copy — see [_deleteAccountConfirmBody]: a master's upcoming
// bookings belong to their CLIENTS, not to them, so the CLIENT-authored
// default text would misstate whose bookings are cancelled.
//
// Security: screenshot protection acquired via the app-wide
// ScreenProtectionManager (ref-counted; active in non-debug builds).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// account_screen.dart` — ported with real l10n.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/icons/app_icon.dart';
import '../../../core/icons/beautica_asset_icons.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../features/auth/domain/auth_session.dart';
import '../../../features/auth/domain/user_role.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../features/auth/presentation/auth_selectors.dart';
import '../../../features/master/presentation/widgets/section_scaffold.dart';
import '../../../features/master/presentation/widgets/settings_row.dart';
import '../../../features/salon/presentation/delete_salon_flow.dart';
import '../../../features/settings/presentation/delete_account_flow.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';

/// Account settings page — VelvetTouch neumorphic design.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.salonId, this.showDeleteSalon = false});

  /// Backend Salon-row UUID the owner-only «Видалити салон» row targets.
  /// `null` (the default) means the row never renders, regardless of
  /// [showDeleteSalon].
  final String? salonId;

  /// Whether to render the destructive «Видалити салон» row below a hairline
  /// divider. Defaults to `false` so every existing caller is unaffected.
  /// The row still fails closed on a null [salonId] — see this file's header
  /// doc.
  final bool showDeleteSalon;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // language
  late final CurvedAnimation _anim2; // notifications
  late final CurvedAnimation _anim3; // change password
  late final CurvedAnimation _anim4; // delete-salon divider (Phase 21.13)
  late final CurvedAnimation _anim5; // delete-salon row (Phase 21.13)
  late final CurvedAnimation _anim6; // delete-account divider (relocated)
  late final CurvedAnimation _anim7; // delete-account row (relocated)

  // Delete-account re-entrancy guard, shared with [runDeleteAccountFlow].
  // Never bound to a widget — see `delete_account_flow.dart`'s flag-lifetime
  // doc. Relocated here verbatim from `client_settings_hub_screen.dart`.
  final ValueNotifier<bool> _deletingAccount = ValueNotifier<bool>(false);
  // Delete-account UI-visible loading flag — drives `SettingsRow(loading:)`.
  // Flips true after consent, immediately before the network call.
  final ValueNotifier<bool> _deletingAccountLoading = ValueNotifier<bool>(
    false,
  );

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws ("widget is about to or has been
  // unmounted"). Hold the keepAlive manager reference instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.40);
    _anim1 = _curve(0.08, 0.50);
    _anim2 = _curve(0.16, 0.58);
    _anim3 = _curve(0.24, 0.66);
    _anim4 = _curve(0.30, 0.74);
    _anim5 = _curve(0.36, 0.82);
    _anim6 = _curve(0.42, 0.90);
    _anim7 = _curve(0.48, 0.98);
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _screenProtection.release();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _anim5.dispose();
    _anim6.dispose();
    _anim7.dispose();
    _controller.dispose();
    _deletingAccount.dispose();
    _deletingAccountLoading.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _showLanguageSoon() {
    showInfoSnack(context, AppLocalizations.of(context).accountLanguageSoon);
  }

  /// True while the initial change-password OTP request is in flight — guards
  /// against a double-tap firing two `request-otp` calls before navigation.
  bool _requestingChangePasswordOtp = false;

  /// Beautica OTP task Phase B5 — sends the FIRST OTP via the authenticated
  /// `requestChangePasswordOtp()` call, then navigates to the OTP entry
  /// screen. Mirrors `ForgotPasswordRequestScreen._submit()`, which likewise
  /// sends the code before navigating — `ResetOtpVerificationScreen` never
  /// sends the first code itself, only resends on the user's explicit tap.
  ///
  /// A failure (e.g. the per-account cooldown 429) shows an error snack and
  /// does NOT navigate, so the user is never dropped onto an OTP screen for a
  /// code that was never actually sent.
  Future<void> _openChangePassword() async {
    if (_requestingChangePasswordOtp) return;
    setState(() => _requestingChangePasswordOtp = true);

    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(authProvider.notifier).requestChangePasswordOtp();
      if (!mounted) return;
      setState(() => _requestingChangePasswordOtp = false);
      await context.push(RouteNames.changePassword);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestingChangePasswordOtp = false);
      final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
      showErrorSnack(context, message);
    }
  }

  /// True while the owner-only delete-salon call is in flight.
  bool _deletingSalon = false;

  /// Phase 21.13 — fails closed: the row (and its divider) only render when
  /// the caller BOTH asked for it AND supplied a target AND the current
  /// session is an authenticated SALON_OWNER. `showDeleteSalon: true` with a
  /// null [SettingsScreen.salonId] must never surface a delete button with
  /// nothing to delete, and — unlike the first two conjuncts, which are
  /// caller-supplied navigation state — this last one is derived from the
  /// session so a caller passing `showDeleteSalon: true` for a non-owner
  /// (CLIENT / master / admin) can never surface the row. Shares the
  /// promoted [isSalonOwnerProvider] with `SalonSettingsScreen.build` and
  /// `MySalonsScreen.build` (`features/auth/presentation/auth_selectors
  /// .dart`) rather than a third copy of the inline `authProvider.select`
  /// derivation — see that provider's doc for the stale-`.value`-through-
  /// `AsyncError` hardening. Fails closed, never open.
  bool get _showDeleteSalonRow {
    final bool isOwner = ref.watch(isSalonOwnerProvider);
    return widget.showDeleteSalon && widget.salonId != null && isOwner;
  }

  /// REUSE-FIRST: delegates to the SAME confirm→delete→feedback flow
  /// `SalonSettingsScreen` (Phase 21.2) uses — see
  /// `features/salon/presentation/delete_salon_flow.dart`. Not reachable
  /// unless [_showDeleteSalonRow] is true, so `widget.salonId!` is safe here.
  Future<void> _deleteSalon() => runDeleteSalonFlow(
    context: context,
    ref: ref,
    salonId: widget.salonId!,
    setLoading: (bool loading) => setState(() => _deletingSalon = loading),
  );

  /// Relocated (2026-09-08) — unlike [_showDeleteSalonRow] this row needs no
  /// caller-supplied opt-in or target id: `DELETE /api/v1/users/me` always
  /// targets "me", so the session role alone decides. Derived the SAME way
  /// as [_showDeleteSalonRow] — watching a selector built with the hardened,
  /// `hasError`-checked idiom [isSalonOwnerProvider] was promoted from —
  /// but via [canSelfDeleteAccountProvider] (`auth_selectors.dart`), not
  /// [isClientProvider]: widened 2026-09-08 so SALON_ADMIN, SALON_MASTER,
  /// and INDEPENDENT_MASTER also reach the row, matching the backend's own
  /// `@PreAuthorize` role list. Fails closed on SALON_OWNER and every
  /// unauthenticated / unsettled / errored session.
  bool get _showDeleteAccountRow => ref.watch(canSelfDeleteAccountProvider);

  /// Role-aware confirm-dialog body for [runDeleteAccountFlow]. A CLIENT's
  /// upcoming bookings are their own; a SALON_MASTER / INDEPENDENT_MASTER's
  /// upcoming bookings belong to their CLIENTS, so the CLIENT-authored
  /// default (`deleteAccountConfirmBody`, "your upcoming bookings will be
  /// cancelled") is factually wrong for a master and is swapped for
  /// `deleteAccountConfirmBodyMaster`. SALON_ADMIN gets a third variant,
  /// `deleteAccountConfirmBodyAdmin`, that drops the bookings sentence
  /// entirely: an admin has no calendar of their own (D3) and the backend's
  /// `StaffAccountSelfDeletionService` never checks or cancels a booking for
  /// that role, so neither the client nor the master sentence is true for
  /// them. `ref.read`, not `ref.watch` — this is a one-shot lookup at tap
  /// time inside an action, not a value the build method needs to react to
  /// (the row itself is already gated on [_showDeleteAccountRow], so a
  /// SALON_OWNER — who has no self-delete copy of their own — can never
  /// reach this getter; the exhaustive `switch` falls back to the CLIENT
  /// string for that unreachable case rather than throwing).
  String _deleteAccountConfirmBody(AppLocalizations l10n) {
    final role = ref.read(currentUserProvider)?.role;
    return switch (role) {
      UserRole.salonMaster ||
      UserRole.independentMaster => l10n.deleteAccountConfirmBodyMaster,
      UserRole.salonAdmin => l10n.deleteAccountConfirmBodyAdmin,
      UserRole.client ||
      UserRole.salonOwner ||
      null => l10n.deleteAccountConfirmBody,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SectionScaffold(
      title: l10n.accountTitle,
      backKey: const Key('btn-back-account'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          // /settings is reachable by any authenticated role (CLIENT via the
          // Home Hub burger; INDEPENDENT_MASTER via the master menu). Resolve
          // the fallback destination from the authenticated session so that a
          // CLIENT with an empty navigator stack returns to /home rather than
          // being sent to /master/menu (a master-only surface that the router
          // gate would immediately redirect away from anyway, causing a flash).
          final session = ref.read(authProvider);
          final fallback = session.value is Authenticated
              ? roleHomePath((session.value! as Authenticated).user.role)
              : RouteNames.login;
          context.go(fallback);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(l10n.accountSubheading, style: VelvetText.body()),
            ),
          ),
          _reveal(
            _anim1,
            SettingsRow(
              key: const Key('row-language'),
              icon: Icons.language_rounded,
              label: l10n.accountLanguageLabel,
              value: l10n.accountLanguageValue,
              onTap: _showLanguageSoon,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim2,
            SettingsToggleRow(
              key: const Key('row-notifications'),
              switchKey: const Key('switch-notifications'),
              icon: Icons.notifications_none_rounded,
              // Match the top-bar idle bell (BellButton): the dotless
              // `notificationPlain` SVG, tinted + sized to the settings-row
              // glyph spec (19 px, accentDeep) so it sits identically.
              iconWidget: const AppIcon(
                BeauticaAssetIcons.notificationPlain,
                size: 19,
                color: BrandColors.accentDeep,
              ),
              label: l10n.accountNotificationsLabel,
              subtitle: l10n.accountNotificationsSubtitle,
              initialValue: true,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          // Beautica OTP task Phase B5 — "Change password" entry point. Opens
          // the SAME generalized ResetOtpVerificationScreen the forgot-password
          // flow uses (RouteNames.changePassword), bound to the authenticated
          // requestChangePasswordOtp() call instead.
          _reveal(
            _anim3,
            SettingsRow(
              key: const Key('row-change-password'),
              icon: Icons.lock_outline_rounded,
              label: l10n.changePasswordRowLabel,
              // mobile-perf MEDIUM: surface the in-flight OTP request visually
              // (dimmed row + spinner instead of the chevron) so a slow
              // network doesn't read as an unresponsive tap, and a second tap
              // is visibly — not silently — ignored.
              loading: _requestingChangePasswordOtp,
              onTap: _openChangePassword,
            ),
          ),
          // Phase 21.13 — owner-only «Видалити салон», additive and fails
          // closed (see [_showDeleteSalonRow]). Divider styling matches
          // `SalonSettingsScreen`'s own terminal-group divider verbatim
          // (thickness 0.6, accent @ ~22%, VelvetSpacing.lg vertical pad) —
          // read, don't invent.
          if (_showDeleteSalonRow) ...<Widget>[
            _reveal(
              _anim4,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
                child: Divider(
                  key: Key('account-settings-delete-salon-divider'),
                  thickness: 0.6,
                  color: Color(0x38B89A7A), // accent @ ~22%
                ),
              ),
            ),
            _reveal(
              _anim5,
              SettingsRow(
                key: const Key('row-delete-salon'),
                icon: Icons.delete_outline_rounded,
                label: l10n.deleteSalonAction,
                destructive: true,
                showChevron: false,
                loading: _deletingSalon,
                onTap: _deleteSalon,
              ),
            ),
          ],
          // Relocated (2026-09-08) — «Видалити акаунт», last row on the
          // page. Reachable by CLIENT, SALON_ADMIN, SALON_MASTER, and
          // INDEPENDENT_MASTER; fails closed on SALON_OWNER and every
          // unauthenticated / unsettled / errored session — see
          // [_showDeleteAccountRow]. A SALON_OWNER (who also owns a salon,
          // hence [_showDeleteSalonRow]) sees delete-salon first,
          // delete-account never — the two rows are not mutually exclusive
          // in general, just in practice, since no role today satisfies
          // both gates at once.
          //
          // Divider styling matches the delete-salon divider above verbatim
          // (thickness 0.6, accent @ ~22%, VelvetSpacing.lg vertical pad) —
          // read, don't invent.
          //
          // No `IgnorePointer` around the sibling rows while this call is in
          // flight: unlike the hub it was moved off (which froze every row
          // during the delete), this screen's OWN pre-existing destructive
          // row (`row-delete-salon` above) never froze its siblings either —
          // matching that established, already-shipped pattern on this same
          // screen takes precedence over reintroducing the hub's freeze.
          if (_showDeleteAccountRow) ...<Widget>[
            _reveal(
              _anim6,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
                child: Divider(
                  key: Key('account-settings-delete-account-divider'),
                  thickness: 0.6,
                  color: Color(0x38B89A7A), // accent @ ~22%
                ),
              ),
            ),
            _reveal(
              _anim7,
              ValueListenableBuilder<bool>(
                valueListenable: _deletingAccountLoading,
                builder: (context, deletingAccountLoading, _) => SettingsRow(
                  key: const Key('row-delete-account'),
                  icon: Icons.delete_outline_rounded,
                  label: l10n.settingsHubDeleteAccount,
                  destructive: true,
                  showChevron: false,
                  loading: deletingAccountLoading,
                  onTap: () => runDeleteAccountFlow(
                    context,
                    ref,
                    inFlight: _deletingAccount,
                    loading: _deletingAccountLoading,
                    confirmBody: _deleteAccountConfirmBody(l10n),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
