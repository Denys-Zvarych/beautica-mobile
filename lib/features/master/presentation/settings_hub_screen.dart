// Master profile settings hub — the pushed screen the top-right menu icon on the
// profile opens. A close affordance + centred "Налаштування" title, then a
// vertical stack of tappable neumorphic rows. Each navigational row pushes its
// own section edit page; the logout row sits apart as the terminal action and
// raises the real logout confirm dialog (see [runLogoutFlow]).
//
// frontend-design craft within VelvetTouch: the rows reveal on load as one
// orchestrated staggered fade-up, and the destructive logout is separated from
// the navigational group by a quiet hairline + extra space so the eye reads it
// as a different *kind* of action — not just another row.
//
// Animation: a single 1000 ms controller drives staggered fade+translate
// reveals. CurvedAnimation instances are pre-built in initState — zero
// allocations in build(); a static Tween<Offset> is reused across reveals.
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// settings_hub_screen.dart` — ported 1:1, swapping the preview's imperative
// route pushes for go_router pushes and the placeholder logout for the
// production flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/settings/presentation/logout_action.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'widgets/section_scaffold.dart';
import 'widgets/settings_row.dart';

/// The settings hub reached from the master profile menu icon.
//
// Reused VERBATIM by the SALON_MASTER own-profile settings hub
// (`RouteNames.salonMasterSettings`, `/staff/settings`) via four additive
// params — every existing (INDEPENDENT_MASTER) call site passes none of them
// and renders EXACTLY as before:
//   * [showLocation]     — SALON_MASTER has no personal location to manage
//     (works from the salon's address, which is the salon's to edit, not
//     theirs); the row is omitted entirely rather than disabled, since it
//     names a concept that does not apply to the role at all.
//   * [contactsEnabled] / [contactsRoute] — SALON_MASTER's «Контакти» row IS
//     live (2026-09-01): it pushes [contactsRoute], which for this role is
//     `RouteNames.salonMasterEditContacts` — the SAME [ContactsEditScreen]
//     widget INDEPENDENT_MASTER's row pushes, but with its additive
//     `showInstagram: false` param, since SALON_MASTER contacts are
//     phone-only by product decision (no Instagram, no location, for this
//     role — Instagram belongs to the master's own public presence, which a
//     salon-employed master does not separately manage). `contactsEnabled`
//     itself stays general-purpose (`false` renders the row PRESENT BUT
//     DISABLED with a «незабаром» trailing value, following the
//     `StaffSettingsScreen` «Перевести в майстри» precedent — never a fake
//     success, never silently dropped) for any future role that genuinely has
//     no contacts destination yet.
//   * [personalInfoRoute] / [fallbackHomeRoute] — the «Особисті дані» row's
//     push target and the hub's own onBack no-pop fallback, so the SAME
//     [SettingsRow] destinations resolve per-role without forking the hub.
class SettingsHubScreen extends ConsumerStatefulWidget {
  const SettingsHubScreen({
    super.key,
    this.showLocation = true,
    this.contactsEnabled = true,
    this.contactsRoute = RouteNames.masterEditContacts,
    this.personalInfoRoute = RouteNames.masterEditPersonal,
    this.fallbackHomeRoute = RouteNames.masterProfile,
  });

  /// Whether the «Локація» row renders. Defaults to `true` (INDEPENDENT_
  /// MASTER, every pre-existing call site).
  final bool showLocation;

  /// Whether the «Контакти» row is a live push target. `false` renders it
  /// PRESENT BUT DISABLED with a «незабаром» trailing value — see the class
  /// doc. Defaults to `true` (INDEPENDENT_MASTER, unaffected).
  final bool contactsEnabled;

  /// Push target for the «Контакти» row when [contactsEnabled] is `true`.
  /// Defaults to [RouteNames.masterEditContacts] (INDEPENDENT_MASTER,
  /// unaffected).
  final String contactsRoute;

  /// Push target for the «Особисті дані» row. Defaults to
  /// [RouteNames.masterEditPersonal] (INDEPENDENT_MASTER, unaffected).
  final String personalInfoRoute;

  /// `onBack`'s no-pop fallback destination (reached only when this hub is
  /// somehow the FIRST route in its stack — e.g. a deep link). Defaults to
  /// [RouteNames.masterProfile] (INDEPENDENT_MASTER, unaffected).
  final String fallbackHomeRoute;

  @override
  ConsumerState<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends ConsumerState<SettingsHubScreen>
    with SingleTickerProviderStateMixin {
  // Logout re-entrancy guard, shared with [runLogoutFlow]. Never bound to a
  // widget — see `logout_action.dart`'s flag-lifetime doc.
  final ValueNotifier<bool> _loggingOut = ValueNotifier<bool>(false);
  // Logout UI-visible loading flag — drives `SettingsRow(loading:)` only.
  // Flips true after consent, immediately before the network call.
  final ValueNotifier<bool> _loggingOutLoading = ValueNotifier<bool>(false);

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // personal
  late final CurvedAnimation _anim2; // contacts
  late final CurvedAnimation _anim3; // location
  late final CurvedAnimation _anim4; // account
  late final CurvedAnimation _anim5; // help / contact-us
  late final CurvedAnimation _anim6; // hairline
  late final CurvedAnimation _anim7; // logout

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _anim0 = _curve(0.00, 0.40);
    _anim1 = _curve(0.06, 0.50);
    _anim2 = _curve(0.14, 0.58);
    _anim3 = _curve(0.22, 0.66);
    _anim4 = _curve(0.30, 0.74);
    _anim5 = _curve(0.36, 0.78); // help / contact-us
    _anim6 = _curve(0.44, 0.84); // hairline
    _anim7 = _curve(0.50, 0.92); // logout
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _anim5.dispose();
    _anim6.dispose();
    _anim7.dispose();
    _controller.dispose();
    _loggingOut.dispose();
    _loggingOutLoading.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-hub'),
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(widget.fallbackHomeRoute);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(l10n.settingsHubSubheading, style: VelvetText.body()),
            ),
          ),

          // Navigational group.
          _reveal(
            _anim1,
            SettingsRow(
              key: const Key('row-personal'),
              icon: Icons.person_outline_rounded,
              label: l10n.settingsHubPersonal,
              onTap: () => context.push(widget.personalInfoRoute),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim2,
            widget.contactsEnabled
                ? SettingsRow(
                    key: const Key('row-contacts'),
                    icon: Icons.call_outlined,
                    label: l10n.settingsHubContacts,
                    onTap: () => context.push(widget.contactsRoute),
                  )
                : SettingsRow(
                    key: const Key('row-contacts'),
                    icon: Icons.call_outlined,
                    label: l10n.settingsHubContacts,
                    // This caller has no contacts-edit destination —
                    // present but visibly inert, never a fake success. No
                    // current call site passes `contactsEnabled: false`
                    // (SALON_MASTER's «Контакти» is live — see the class
                    // doc); kept general-purpose for a future role that
                    // genuinely has none yet.
                    enabled: false,
                    showChevron: false,
                    value: l10n.settingsHubContactsSoon,
                    onTap: () {},
                  ),
          ),
          if (widget.showLocation) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            _reveal(
              _anim3,
              SettingsRow(
                key: const Key('row-location'),
                icon: Icons.location_on_outlined,
                iconWidget: const AppIcon(
                  BeauticaAssetIcons.locationMarker,
                  size: 19,
                  color: BrandColors.accentDeep,
                ),
                label: l10n.settingsHubLocation,
                onTap: () => context.push(RouteNames.masterEditLocation),
              ),
            ),
          ],
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim4,
            SettingsRow(
              key: const Key('row-account'),
              icon: Icons.settings_outlined,
              label: l10n.settingsHubAccount,
              onTap: () => context.push(RouteNames.settings),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),

          // Help / contact-us — the last navigational row. It reads naturally
          // at the bottom of the nav group and stays clear of the destructive
          // logout below the rule.
          _reveal(
            _anim5,
            SettingsRow(
              key: const Key('row-help'),
              icon: Icons.help_outline_rounded,
              label: l10n.settingsHubHelp,
              onTap: () => context.push(RouteNames.contactSupport),
            ),
          ),

          // Separation before the terminal action.
          _reveal(
            _anim6,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Divider(
                thickness: 0.6,
                color: BrandColors.accent.withValues(alpha: 0.22),
              ),
            ),
          ),

          // Terminal / destructive action — set apart.
          //
          // mobile-perf consistency fix (2026-09-08) — wired to
          // `SettingsRow`'s EXISTING `loading` param via `_loggingOut`, the
          // same one-line pattern the CLIENT settings hub's logout row and
          // the sibling delete-salon/delete-account rows already use
          // (dims the row, swaps the chevron for a spinner, absorbs taps
          // for the duration of the network call).
          _reveal(
            _anim7,
            ValueListenableBuilder<bool>(
              valueListenable: _loggingOutLoading,
              builder: (context, loggingOutLoading, _) => SettingsRow(
                key: const Key('row-logout'),
                icon: Icons.logout_rounded,
                label: l10n.logout,
                destructive: true,
                showChevron: false,
                loading: loggingOutLoading,
                onTap: () => runLogoutFlow(
                  context,
                  ref,
                  inFlight: _loggingOut,
                  loading: _loggingOutLoading,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
