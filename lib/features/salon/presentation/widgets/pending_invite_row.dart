// Phase 21.11 — One outbound, not-yet-accepted staff invitation.
//
// Transcribed from the approved preview
// `docs/signup-designs/SalonManagementDesign/lib/widgets/salon_widgets.dart`
// (`PendingInviteRow`, `:513`): a recessed well holding a camel-tinted
// circular mail glyph, the recipient address (ellipsised), a [RoleChip] +
// "надіслано …" meta line, and a destructive «Скасувати» ghost text button.
// `VelvetColors.*` → `BrandColors.*`; the preview's inline type-size
// `.copyWith`s become the equivalent production `VelvetText` tokens (the
// `forbid_inline_fontsize.sh` ratchet forbids inline sizes under
// `lib/features/**`, and production's scale already renders these roles one
// step smaller than the preview's).
//
// SHARED BY TWO SCREENS — this is why it is a top-level widget in
// `presentation/widgets/` rather than a `_`-private class:
// [SalonPendingInvitesScreen] (the dedicated list) and [InviteStaffScreen]
// (the same block appended under its form, exactly as the preview shows it).
// One widget, one fix, both surfaces.
//
// REUSE-FIRST: the role badge is the SHIPPED [RoleChip]
// (`features/master/presentation/widgets/profile_avatar.dart`) — the same
// recessed pill the master profile and the salon staff profile already use —
// not a salon-local copy of the preview's own `RoleChip`. Nothing existing
// covered the row itself: `SettingsRow` is a navigational chevron row with no
// trailing action slot, and the staff-roster `SalonMasterCard` is a grid tile
// with an avatar. Hence a new widget here, deliberately.
//
// The row NEVER renders a token or an invite link — the backend's
// `PendingInviteResponse` carries no secret material (see [PendingInvite]).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';

import '../../../master/presentation/widgets/profile_avatar.dart';
import '../../domain/pending_invite.dart';
import '../../domain/salon_staff_member.dart';

/// Widget key of the «Скасувати» action on the row for [inviteId] — stable
/// across both consuming screens so widget tests address one row
/// unambiguously.
Key pendingInviteCancelKey(String inviteId) =>
    Key('pending-invite-cancel-$inviteId');

/// Widget key of the whole row for [inviteId].
///
/// BELONGS ON THE [PendingInviteRow] ITSELF, at the call site — never on some
/// widget one level down inside its `build`. A keyless child in a list is
/// matched to its old element BY INDEX, so keying only the inner
/// [NeumorphicInset] made every row after a mid-list removal hit a key
/// mismatch one level down: Flutter deactivated and re-inflated that row's
/// whole subtree instead of updating it in place. Both consumers
/// ([SalonPendingInvitesScreen], [InviteStaffScreen]) pass it, and
/// [PendingInviteRow.build] asserts they did.
Key pendingInviteRowKey(String inviteId) => Key('pending-invite-$inviteId');

/// A single pending invitation: address + role + «Скасувати».
class PendingInviteRow extends StatelessWidget {
  const PendingInviteRow({
    super.key,
    required this.invite,
    required this.onCancel,
    this.cancelling = false,
    this.failed = false,
  });

  final PendingInvite invite;

  /// Invoked by «Скасувати». Ignored while [cancelling] is true (the row
  /// swaps the label for a spinner and stops accepting taps).
  final VoidCallback onCancel;

  /// True while this row's `DELETE` is in flight.
  final bool cancelling;

  /// True when the last cancel attempt for this row failed — raises the
  /// in-row error chip beneath the meta line. Tapping «Скасувати» again
  /// clears it and retries.
  final bool failed;

  /// The glyph paired with each role in the [RoleChip], matching the invite
  /// form's own role-toggle icons so the two surfaces read as one system.
  static IconData _roleIcon(SalonStaffRole role) => switch (role) {
    SalonStaffRole.admin => Icons.admin_panel_settings_outlined,
    SalonStaffRole.master => Icons.brush_outlined,
  };

  static String _roleLabel(SalonStaffRole role, AppLocalizations l10n) =>
      switch (role) {
        SalonStaffRole.admin => l10n.inviteStaffRoleAdmin,
        SalonStaffRole.master => l10n.inviteStaffRoleMaster,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    assert(
      key == pendingInviteRowKey(invite.inviteId),
      'PendingInviteRow must be constructed with '
      'key: pendingInviteRowKey(invite.inviteId) — see that function\'s doc '
      'for why the key belongs here and not one level down.',
    );
    return NeumorphicInset(
      radius: VelvetRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md - 2),
        child: Row(
          children: <Widget>[
            const _InviteGlyph(),
            const SizedBox(width: VelvetSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    invite.recipientEmail,
                    style: VelvetText.bodyStrong(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: VelvetSpacing.xs - 1),
                  Row(
                    children: <Widget>[
                      RoleChip(
                        label: _roleLabel(invite.role, l10n),
                        icon: _roleIcon(invite.role),
                      ),
                      const SizedBox(width: VelvetSpacing.sm),
                      Flexible(
                        child: Text(
                          // `now` DELIBERATELY left at its default. The
                          // `clockProvider` sweep this used to propose is
                          // DECLINED, not deferred — Phase 284 D2
                          // (`docs/mobile-phases/
                          // phase-284-relative-date-dst-safe-day-arithmetic.md`)
                          // records the reasoning and the seam that replaces
                          // it. Do not re-raise it here.
                          l10n.salonPendingInvitesSentAgo(
                            formatRelativeDate(l10n, invite.createdAt),
                          ),
                          style: VelvetText.feedbackMutedSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (failed) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.xs + 2),
                    _CancelFailedChip(
                      message: l10n.salonPendingInvitesCancelError,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: VelvetSpacing.xs),
            _CancelAction(
              cancelKey: pendingInviteCancelKey(invite.inviteId),
              label: l10n.salonPendingInvitesCancelCta,
              semanticLabel: l10n.salonPendingInvitesCancelSemanticLabel(
                invite.recipientEmail,
              ),
              busy: cancelling,
              onCancel: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// The camel-tinted circular mail glyph that opens the row.
class _InviteGlyph extends StatelessWidget {
  const _InviteGlyph();

  static const double _extent = 40;

  // Hoisted — a `withValues` call per build would allocate a Color on every
  // rebuild of every row (`NeumorphicButton._ctaDisabledStyle` precedent).
  static final BoxDecoration _decoration = BoxDecoration(
    shape: BoxShape.circle,
    color: BrandColors.accent.withValues(alpha: 0.14),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _extent,
      width: _extent,
      decoration: _decoration,
      child: const Icon(
        Icons.mark_email_unread_outlined,
        size: 19,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

/// «Скасувати» — a destructive ghost text action that swaps its label for an
/// in-row spinner of the SAME footprint while the `DELETE` is in flight, so
/// the row never reflows mid-cancel.
class _CancelAction extends StatelessWidget {
  const _CancelAction({
    required this.cancelKey,
    required this.label,
    required this.semanticLabel,
    required this.busy,
    required this.onCancel,
  });

  final Key cancelKey;
  final String label;
  final String semanticLabel;
  final bool busy;
  final VoidCallback onCancel;

  static const double _spinnerExtent = 15;
  static const double _spinnerStroke = 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: cancelKey,
      button: true,
      enabled: !busy,
      label: semanticLabel,
      child: GestureDetector(
        onTap: busy ? null : onCancel,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xs),
          child: busy
              // mobile-perf LOW fix — `CircularProgressIndicator` carries no
              // boundary of its own, so its per-frame repaint climbed to the
              // row's `NeumorphicInset` layer and re-rasterised that row's
              // `_InsetShadowPainter` for the whole DELETE. Same class of fix
              // as `_RoleToggle`'s own animation boundary
              // (`invite_staff_screen.dart`) and `NeumorphicButton`'s press
              // animation. Sits ABOVE the fixed-extent `SizedBox` so the
              // boundary's own layer is a stable 15x15 — nothing outside it
              // ever needs to repaint while the spinner ticks.
              ? const RepaintBoundary(
                  child: SizedBox(
                    height: _spinnerExtent,
                    width: _spinnerExtent,
                    child: CircularProgressIndicator(
                      strokeWidth: _spinnerStroke,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        BrandColors.error,
                      ),
                    ),
                  ),
                )
              : Text(label, style: VelvetText.linkDestructive),
        ),
      ),
    );
  }
}

/// The in-row failure chip — a quiet error-tinted pill that keeps a failed
/// cancel scoped to the row it belongs to instead of blanking the list.
class _CancelFailedChip extends StatelessWidget {
  const _CancelFailedChip({required this.message});

  final String message;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.error.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _decoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: VelvetSpacing.xs - 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 13,
              color: BrandColors.error,
            ),
            const SizedBox(width: VelvetSpacing.xs),
            Flexible(
              child: Text(
                message,
                style: VelvetText.feedbackError12,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
