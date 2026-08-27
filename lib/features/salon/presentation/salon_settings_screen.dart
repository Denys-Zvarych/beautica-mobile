// Phase 21.2 — Salon settings (owner/admin), the 2-row entry surface the
// management profile's top-right `Icons.tune_rounded` cover control opens.
//
// NAMING/SCOPE NOTE: the approved preview at
// `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_settings_screen.dart` sketches a much larger multi-row hub («Мої
// салони», «Про салон», «Локація», «Контакти», «Надіслані запрошення»,
// «Загальне», «Допомога», «Вийти»). That full hub is Phase 21.9's job and
// SUPERSEDES this screen — Phase 21.2 (this file) builds only the 2-row
// version its own phase doc specifies:
//   «Редагувати профіль» (nav) → divider → «Видалити салон» (destructive,
//   owner-only — row AND divider both suppressed for an admin viewer).
// This screen/route is not phase-suffixed so 21.9 can EXTEND it in place
// rather than replace it.
//
// Shell: reuses the production `SectionScaffold` + `SettingsRow` widgets
// (`features/master/presentation/widgets/`) — the SAME shared building
// blocks `SettingsHubScreen` uses — rather than recreating the preview's own
// bespoke `_SettingsTopBar`/`_SettingsRow` (REUSE-FIRST).
//
// «Редагувати профіль» pops back to the management profile screen with a
// `true` result so it can toggle edit mode on — mirrors production's
// close-and-signal idiom (`context.pop(true)`), see
// `SalonManagementProfileScreen._openSettings`.
//
// «Видалити салон» opens [DeleteSalonDialog]; on confirm it calls
// `SalonManagementProfile.deleteSalon()` and, on success, pops back to the
// role home (there is no "Мої салони" hub yet — Phase 21.1 is unbuilt — so
// this is the safest landing spot for both an owner and an admin).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../../master/presentation/widgets/settings_row.dart';
import '../application/salon_management_profile_notifier.dart';
import 'widgets/delete_salon_dialog.dart';

/// The salon settings page — «Редагувати профіль» + (owner-only) «Видалити
/// салон».
class SalonSettingsScreen extends ConsumerStatefulWidget {
  const SalonSettingsScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this settings page manages.
  final String salonId;

  @override
  ConsumerState<SalonSettingsScreen> createState() =>
      _SalonSettingsScreenState();
}

class _SalonSettingsScreenState extends ConsumerState<SalonSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // edit profile
  late final CurvedAnimation _anim1; // hairline
  late final CurvedAnimation _anim2; // delete salon

  bool _deleting = false;

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim0 = _curve(0.00, 0.55);
    _anim1 = _curve(0.20, 0.75);
    _anim2 = _curve(0.35, 0.92);
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
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.salonManage(widget.salonId));
    }
  }

  /// «Редагувати профіль» — pops back to the management profile with a
  /// `true` result, signalling it to toggle edit mode on.
  void _editProfile() {
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(RouteNames.salonManage(widget.salonId));
    }
  }

  Future<void> _deleteSalon() async {
    final l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteSalonDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .deleteSalon();
    if (!mounted) return;

    if (failure != null) {
      setState(() => _deleting = false);
      showErrorSnack(context, failure.userMessage(context));
      return;
    }

    showSuccessSnack(context, l10n.deleteSalonSuccess);
    // No «Мої салони» hub yet (Phase 21.1 unbuilt) — the safest landing spot
    // for either role is the auth-derived role home.
    final session = ref.read(authProvider).value;
    context.go(session is Authenticated ? '/' : RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isOwner = ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> s) =>
            s.value is Authenticated &&
            (s.value! as Authenticated).user.role == UserRole.salonOwner,
      ),
    );

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-salon-settings'),
      onBack: _close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            SettingsRow(
              key: const Key('row-salon-edit-profile'),
              icon: Icons.edit_outlined,
              label: l10n.salonSettingsEditProfile,
              onTap: _editProfile,
            ),
          ),

          // Terminal group — owner-only. Both the hairline AND the row are
          // suppressed for an admin viewer (they can never delete a salon —
          // locked product decision, `SalonController.java:104`).
          if (isOwner) ...<Widget>[
            _reveal(
              _anim1,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
                child: Divider(
                  key: Key('salon-settings-divider'),
                  thickness: 0.6,
                  color: Color(0x38B89A7A), // accent @ ~22%
                ),
              ),
            ),
            _reveal(
              _anim2,
              SettingsRow(
                key: const Key('row-salon-delete'),
                icon: Icons.delete_outline_rounded,
                label: l10n.deleteSalonAction,
                destructive: true,
                showChevron: false,
                loading: _deleting,
                onTap: _deleteSalon,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
