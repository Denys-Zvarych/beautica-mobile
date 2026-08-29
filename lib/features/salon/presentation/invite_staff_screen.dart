// Phase 21.4 — Invite Staff (form only).
//
// Reached from the salon management profile's «Персонал» tab «+» tile
// (`salon_management_profile_screen.dart`'s `_openInviteStaff`, wired this
// phase). A `SALON_OWNER`/`SALON_ADMIN` invites a new admin or master by
// email: a compact two-segment role toggle (Адміністратор | Майстер) with a
// one-line description of the selected role beneath it, then the invitee's
// email, then a primary «Надіслати запрошення» CTA.
//
// SCOPE — form only. The approved preview's own «Очікують підтвердження»
// pending-invites block is descoped to Phase 21.11 (backend Phase 23.1's
// `GET/DELETE /salons/{salonId}/invites/...` endpoints don't exist yet);
// the preview itself guards that block behind `if (pending.isNotEmpty)`, so
// this screen renders the empty-list branch — literal transcription, not a
// cut corner. The preview's own success DIALOG is likewise NOT ported:
// [_submit] uses the SAME `showSuccessSnack` + `context.pop()` pattern
// `RegisterSalonScreen._submit` already uses, for the same reason that
// screen substituted [SectionScaffold] for the preview's own `FormScaffold`
// — production siblings share one submit-feedback idiom rather than each
// screen inventing its own.
//
// REUSE-FIRST:
//   - [SectionScaffold] (Phase 21.10 family) — page chrome, back button,
//     pinned footer. Same substitution [RegisterSalonScreen]/
//     [SalonProfileEditScreen]/[SalonAddressEditScreen]/
//     [SalonContactsEditScreen] already made for their own preview source.
//   - [NeumorphicTextField] — the email field.
//   - [NeumorphicInset] + [NeumorphicButton] — the role-toggle track and the
//     submit CTA, exactly like every other production form.
//   - [validateEmail] — email validation (Phase 2.5 validator, unchanged).
//   - [showSuccessSnack]/[showErrorSnack]/[showInfoSnack] — feedback, same
//     mechanism [RegisterSalonScreen] uses.
//   - `SalonRepository.inviteStaff` / `InviteStaff.submit` — the write path;
//     no new Dio call site, no new `Failure` subtype.
//
// No segmented control exists anywhere else in `lib/` (verified) — [_RoleToggle]
// / [_RoleSegment] are written fresh, private to this screen, mirroring the
// `services_list_screen.dart` precedent for screen-private widgets (single
// consumer today; PROMOTE, never copy, if a second consumer appears later —
// see `RoleChip` in `profile_avatar.dart`, a non-interactive badge, which is
// NOT this toggle and was deliberately left untouched).
//
// Lifecycle guarding — mirrors [RegisterSalonScreen]'s own CRITICAL fix
// (autoDispose notifier element disposed mid-`await` → `UnmountedRefException`,
// plus the back-navigation-mid-submit variant through `PopScope`). See
// `invite_staff_notifier.dart`'s own header doc for why [InviteStaff.submit]
// itself cannot reproduce the exact crash this phase (no post-await `ref`
// call), and why the guarding is reproduced here anyway.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/validators/email_validator.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/invite_staff_notifier.dart';

/// The `SALON_OWNER`/`SALON_ADMIN`'s «Запросити персонал» form.
class InviteStaffScreen extends ConsumerStatefulWidget {
  const InviteStaffScreen({super.key, required this.salonId});

  final String salonId;

  @override
  ConsumerState<InviteStaffScreen> createState() => _InviteStaffScreenState();
}

class _InviteStaffScreenState extends ConsumerState<InviteStaffScreen> {
  final TextEditingController _emailCtrl = TextEditingController();

  UserRole _role = UserRole.salonMaster;
  bool _submitting = false;
  String? _errEmail;

  // mobile-perf LOW fix — the role-description caption's style is the SAME
  // Color/height on every build (never varies with `_role`, only the TEXT
  // does), so the `.copyWith` call was reallocating an identical TextStyle
  // every rebuild. Hoisted once, mirroring `NeumorphicButton`'s own
  // `_ctaDisabledStyle` precedent.
  static final TextStyle _roleDescriptionStyle = VelvetText.feedback(
    BrandColors.muted,
  ).copyWith(height: 1.35);

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String _roleDescription(AppLocalizations l10n) => switch (_role) {
    UserRole.salonAdmin => l10n.inviteStaffRoleAdminDescription,
    UserRole.salonMaster => l10n.inviteStaffRoleMasterDescription,
    UserRole.client || UserRole.salonOwner || UserRole.independentMaster => '',
  };

  /// Maps a submit [Failure] to the screen's own copy — 403/429 get distinct
  /// text, everything else falls back to the generic message. Deliberately
  /// NOT `failure.userMessage(context)`: [ServerFailure.userMessage] is a
  /// single generic "server error" string for every status code, so the
  /// per-status copy the architect's plan calls for is resolved here instead.
  ///
  /// mobile-qa CRITICAL fix (2026-08-29, caught only by the REAL end-to-end
  /// flow — a widget test that injects a `ServerFailure` directly into a
  /// fake repository can never catch this): [ErrorMapperInterceptor] only
  /// maps a handful of EXPLICITLY listed status codes to [ServerFailure]
  /// (401/404/409/5xx, plus 400/429 on two unrelated hard-coded paths) —
  /// this is DELIBERATE, locked behaviour (see
  /// `error_mapper_interceptor_test.dart`'s own
  /// `'HTTP 403 (unmapped status) → UnknownFailure'` and `'429 on a
  /// DIFFERENT path → UnknownFailure'` tests). A bare 403/429 from
  /// `POST /salons/{salonId}/invite` therefore arrives here as
  /// [UnknownFailure], NEVER [ServerFailure] — so the `is ServerFailure`
  /// check below was UNREACHABLE for both branches this method exists to
  /// special-case. The underlying [DioException]'s own
  /// `response?.statusCode` is still available via [Failure.cause] on
  /// EITHER failure shape, so read it from there instead of assuming a
  /// specific [Failure] subtype.
  String _errorMessage(Failure failure, AppLocalizations l10n) {
    final int? statusCode = switch (failure) {
      ServerFailure(:final statusCode) => statusCode,
      _ => switch (failure.cause) {
        DioException(:final response) => response?.statusCode,
        _ => null,
      },
    };
    switch (statusCode) {
      case 403:
        return l10n.inviteStaffErrorForbidden;
      case 429:
        return l10n.inviteStaffErrorRateLimited;
    }
    return l10n.inviteStaffErrorGeneric;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);

    final String? emailErr = validateEmail(_emailCtrl.text, l10n);
    if (emailErr != null) {
      setState(() => _errEmail = emailErr);
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    setState(() => _submitting = true);
    final Failure? failure = await ref
        .read(inviteStaffProvider.notifier)
        .submit(
          salonId: widget.salonId,
          email: _emailCtrl.text.trim(),
          role: _role,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (failure != null) {
      showErrorSnack(context, _errorMessage(failure, l10n));
      return;
    }
    showSuccessSnack(context, l10n.inviteStaffSuccess);
    context.pop();
  }

  /// Guards the top-bar back icon against the same reachable defect the
  /// enclosing `PopScope` guards for the system back gesture/hardware
  /// button — see [build]'s own doc. `PopScope.canPop` only governs
  /// SYSTEM-initiated pops, not this explicit imperative `context.pop()`.
  void _onBack() {
    if (_submitting) {
      showInfoSnack(
        context,
        AppLocalizations.of(context).inviteStaffSubmitInProgressHint,
      );
      return;
    }
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // `ref.watch(inviteStaffProvider)` — mirrors `RegisterSalonScreen`'s own
    // CRITICAL fix: registers this screen as a live listener of the
    // (autoDispose) `inviteStaffProvider` for the screen's whole lifetime, so
    // its element is never torn down mid-request regardless of how long
    // `POST /salons/{salonId}/invite` takes. `build()` returns `void` and
    // `submit()` never reassigns `state`, so this watch never fires a
    // rebuild after the first one.
    ref.watch(inviteStaffProvider);

    // mobile-qa-precedent fix (mirrors RegisterSalonScreen) — block the
    // SYSTEM back gesture/hardware button while a submit is in flight so the
    // screen stays mounted for the whole request; the top-bar icon needs its
    // own guard too (see [_onBack]) because `PopScope.canPop` does not cover
    // an explicit imperative `context.pop()` call.
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          showInfoSnack(context, l10n.inviteStaffSubmitInProgressHint);
        }
      },
      child: SectionScaffold(
        title: l10n.inviteStaffTitle,
        backSemanticLabel: l10n.inviteStaffBackSemanticLabel,
        onBack: _onBack,
        footer: NeumorphicButton(
          key: const Key('send_invite'),
          label: l10n.inviteStaffSubmitCta,
          icon: Icons.send_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(l10n.inviteStaffSubtitle, style: VelvetText.body()),
            ),
            Text(l10n.inviteStaffRoleSectionLabel, style: VelvetText.label()),
            const SizedBox(height: VelvetSpacing.sm),
            _RoleToggle(
              role: _role,
              onChanged: (UserRole r) => setState(() => _role = r),
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(_roleDescription(l10n), style: _roleDescriptionStyle),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            NeumorphicTextField(
              key: const ValueKey<String>('invite_email'),
              label: l10n.inviteStaffEmailLabel,
              controller: _emailCtrl,
              enabled: !_submitting,
              hintText: l10n.inviteStaffEmailHint,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              maxLength: 255,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              errorText: _errEmail,
              helperText: l10n.inviteStaffEmailHelper,
              onChanged: (String v) {
                final next = validateEmail(v, l10n);
                if (next != _errEmail) setState(() => _errEmail = next);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact two-segment role toggle (Адміністратор | Майстер) — a
/// recessed inset track holding both segments, with the active half a raised
/// camel-gradient pillow that slides between positions. Private to this
/// screen (REUSE-FIRST doc, this file's own header) — no other production
/// screen has a segmented control to reuse or promote this into yet.
class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.role, required this.onChanged});

  final UserRole role;
  final ValueChanged<UserRole> onChanged;

  static const double _height = 52;
  static const double _pad = VelvetSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NeumorphicInset(
      radius: VelvetRadii.button,
      child: Padding(
        padding: const EdgeInsets.all(_pad),
        child: SizedBox(
          height: _height - (_pad * 2),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double half = constraints.maxWidth / 2;
              // mobile-perf MEDIUM fix — the AnimatedAlign's sliding pillow
              // repaints every animation tick (240ms each toggle); without a
              // boundary that repaint propagates up into the surrounding
              // form's layer, same class of fix as `NeumorphicButton`'s own
              // press-animation `RepaintBoundary` (Phase 2.17 fix P1-2).
              return RepaintBoundary(
                child: Stack(
                  children: <Widget>[
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: role == UserRole.salonAdmin
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        width: half,
                        height: _height - (_pad * 2),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              BrandColors.accentLatte,
                              BrandColors.accentDeep,
                            ],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          boxShadow: VelvetShadows.extrudedSmall,
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        _RoleSegment(
                          selected: role == UserRole.salonAdmin,
                          icon: Icons.admin_panel_settings_outlined,
                          label: l10n.inviteStaffRoleAdmin,
                          onTap: () => onChanged(UserRole.salonAdmin),
                        ),
                        _RoleSegment(
                          selected: role == UserRole.salonMaster,
                          icon: Icons.brush_outlined,
                          label: l10n.inviteStaffRoleMaster,
                          onTap: () => onChanged(UserRole.salonMaster),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RoleSegment extends StatelessWidget {
  const _RoleSegment({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  // mobile-perf LOW fix — only two (selected/unselected) label styles ever
  // exist; `.copyWith` was reallocating one of these two on every rebuild
  // (each toggle animation frame included). Hoisted to the two static
  // variants and picked by `selected`, mirroring `NeumorphicButton`'s own
  // `_ctaDisabledStyle` precedent.
  static final TextStyle _selectedLabelStyle = VelvetText.cta().copyWith(
    color: BrandColors.white,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _unselectedLabelStyle = VelvetText.cta().copyWith(
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? BrandColors.white : BrandColors.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: VelvetSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: selected
                        ? _selectedLabelStyle
                        : _unselectedLabelStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
