// One outbound staff invitation, in any lifecycle state.
//
// Transcribed from the approved preview
// `docs/signup-designs/SalonManagementDesign/lib/widgets/salon_widgets.dart`
// (`PendingInviteRow`, `:513`): a recessed well holding a camel-tinted
// circular mail glyph, the recipient address, a [RoleChip] + "надіслано …"
// meta line, and a destructive «Скасувати» ghost text button.
// `VelvetColors.*` → `BrandColors.*`; the preview's inline type-size
// `.copyWith`s become the equivalent production `VelvetText` tokens (the
// `forbid_inline_fontsize.sh` ratchet forbids inline sizes under
// `lib/features/**`, and production's scale already renders these roles one
// step smaller than the preview's).
//
// LAYOUT — WHY THE META LINE IS NOT ONE ROW (the truncation fix)
// --------------------------------------------------------------
// The preview (and this widget until the history rework) put the role chip
// and the "надіслано …" caption on ONE `Row`, with the chip at its natural
// width and the caption the only `Flexible`. Every pixel of squeeze therefore
// landed on the caption, which ellipsised at `maxLines: 1` on a narrow
// screen — and the outer `Row` had already spent 40dp on the glyph plus an
// unbounded fixed width on «Скасувати» before the caption saw any of it. That
// is the reported "text is cut" defect. Adding a SECOND chip to that row
// would have made it strictly worse.
//
// Three independent fixes, each addressing one way the row ran out of width:
//   1. the email may wrap to a second line (`maxLines: 2`, soft-wrap) instead
//      of ellipsising the local part of a long address;
//   2. the chips sit in a [Wrap], so a role + status pair that cannot share
//      one run flows onto a second run rather than compressing;
//   3. the caption gets its OWN full-width line, so it is no longer the sole
//      shock absorber for everything above it.
// The cancel action moves up beside the email, where the row's fixed-width
// element and its most compressible element no longer compete.
//
// SHARED BY TWO SCREENS — this is why it is a top-level widget in
// `presentation/widgets/` rather than a `_`-private class:
// [SalonPendingInvitesScreen] (the dedicated history list) and
// [InviteStaffScreen] (the same block appended under its form, filtered to
// pending rows, exactly as the preview shows it). One widget, one fix, both
// surfaces.
//
// REUSE-FIRST: BOTH badges are the SHIPPED [RoleChip]
// (`features/master/presentation/widgets/profile_avatar.dart`) — the same
// recessed pill the master profile and the salon staff profile already use.
// The status chip is that widget plus its ADDITIVE `tint`, NOT a `_StatusChip`
// sibling: a private fork of a shipped pill drifts from it the first time the
// pill's geometry or type scale moves, and there was nothing to fork but a
// colour. Nothing existing covered the row itself: `SettingsRow` is a
// navigational chevron row with no trailing action slot, and the staff-roster
// `SalonMasterCard` is a grid tile with an avatar. Hence a widget here,
// deliberately.
//
// The row NEVER renders a token or an invite link — the backend's
// `SalonInviteResponse` carries no secret material (see [SalonInvite]).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';

import '../../../master/presentation/widgets/profile_avatar.dart';
import '../../domain/invite_status.dart';
import '../../domain/salon_invite.dart';
import '../../domain/salon_staff_member.dart';

/// Widget key of the «Скасувати» action on the row for [inviteId] — stable
/// across both consuming screens so widget tests address one row
/// unambiguously.
///
/// The action is RENDERED ONLY on a pending row, so this key finding nothing
/// is the correct assertion for every other status.
Key salonInviteCancelKey(String inviteId) =>
    Key('pending-invite-cancel-$inviteId');

/// Widget key of the whole row for [inviteId].
///
/// BELONGS ON THE [SalonInviteRow] ITSELF, at the call site — never on some
/// widget one level down inside its `build`. A keyless child in a list is
/// matched to its old element BY INDEX, so keying only the inner
/// [NeumorphicInset] made every row after a mid-list removal hit a key
/// mismatch one level down: Flutter deactivated and re-inflated that row's
/// whole subtree instead of updating it in place. Both consumers
/// ([SalonPendingInvitesScreen], [InviteStaffScreen]) pass it, and
/// [SalonInviteRow.build] asserts they did.
Key salonInviteRowKey(String inviteId) => Key('pending-invite-$inviteId');

/// A single sent invitation: address + role + status + «Скасувати».
class SalonInviteRow extends StatelessWidget {
  const SalonInviteRow({
    super.key,
    required this.invite,
    required this.onCancel,
    this.cancelling = false,
    this.failed = false,
  });

  final SalonInvite invite;

  /// Invoked by «Скасувати». Ignored while [cancelling] is true (the row
  /// swaps the label for a spinner and stops accepting taps), and never
  /// reachable at all unless the invite is [SalonInvite.isCancellable].
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

  /// One glyph per lifecycle stage, each naming what HAPPENED rather than
  /// decorating the colour: a clock for the wait, a tick for the join, a
  /// stopped timer for the elapsed window, a struck-through circle for the
  /// revocation.
  ///
  /// [InviteStatus.unknown] is unreachable here — [_statusChip] returns null
  /// before calling this — but is answered anyway so the switch stays
  /// exhaustive without a wildcard that would swallow a future case.
  static IconData _statusIcon(InviteStatus status) => switch (status) {
    InviteStatus.pending => Icons.schedule_rounded,
    InviteStatus.accepted => Icons.check_circle_outline_rounded,
    InviteStatus.expired => Icons.timer_off_outlined,
    InviteStatus.cancelled => Icons.do_not_disturb_on_outlined,
    InviteStatus.unknown => Icons.help_outline_rounded,
  };

  static String _statusLabel(InviteStatus status, AppLocalizations l10n) =>
      switch (status) {
        InviteStatus.pending => l10n.salonInvitesStatusPending,
        InviteStatus.accepted => l10n.salonInvitesStatusAccepted,
        InviteStatus.expired => l10n.salonInvitesStatusExpired,
        InviteStatus.cancelled => l10n.salonInvitesStatusCancelled,
        InviteStatus.unknown => '',
      };

  /// Pending returns null — it keeps [RoleChip]'s default mocha, so the
  /// terminal states are the only tinted pills on the screen and read as
  /// outcomes rather than as four equally-weighted colours.
  static Color? _statusTint(InviteStatus status) => switch (status) {
    InviteStatus.pending => null,
    InviteStatus.accepted => BrandColors.success,
    InviteStatus.expired => BrandColors.muted,
    InviteStatus.cancelled => BrandColors.error,
    InviteStatus.unknown => null,
  };

  /// The status pill, or null for [InviteStatus.unknown] — a state this build
  /// cannot name must render nothing rather than a placeholder that would
  /// mislabel it.
  Widget? _statusChip(AppLocalizations l10n) {
    if (invite.status == InviteStatus.unknown) return null;
    final String label = _statusLabel(invite.status, l10n);
    return Semantics(
      label: l10n.salonInvitesStatusSemanticLabel(label),
      excludeSemantics: true,
      child: RoleChip(
        label: label,
        icon: _statusIcon(invite.status),
        tint: _statusTint(invite.status),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    assert(
      key == salonInviteRowKey(invite.inviteId),
      'SalonInviteRow must be constructed with '
      'key: salonInviteRowKey(invite.inviteId) — see that function\'s doc '
      'for why the key belongs here and not one level down.',
    );
    final Widget? statusChip = _statusChip(l10n);
    return NeumorphicInset(
      radius: VelvetRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md - 2),
        child: Row(
          // `start`, not the default `center`: the email may now wrap to two
          // lines and the chips may wrap to two runs, so a centred glyph
          // would drift down the taller variants of this row.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _InviteGlyph(),
            const SizedBox(width: VelvetSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          invite.recipientEmail,
                          style: VelvetText.bodyStrong(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                      // ONLY on a pending row — omitted entirely, never
                      // rendered-and-disabled. `_CancelAction` is a
                      // `Semantics(button:)` node, so a disabled one would
                      // still be announced and focusable for an action the
                      // backend now 404s on every non-pending invite.
                      if (invite.isCancellable) ...<Widget>[
                        const SizedBox(width: VelvetSpacing.xs),
                        _CancelAction(
                          cancelKey: salonInviteCancelKey(invite.inviteId),
                          label: l10n.salonPendingInvitesCancelCta,
                          semanticLabel: l10n
                              .salonPendingInvitesCancelSemanticLabel(
                                invite.recipientEmail,
                              ),
                          busy: cancelling,
                          onCancel: onCancel,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.xs - 1),
                  Wrap(
                    spacing: VelvetSpacing.sm,
                    runSpacing: VelvetSpacing.xs,
                    children: <Widget>[
                      RoleChip(
                        label: _roleLabel(invite.role, l10n),
                        icon: _roleIcon(invite.role),
                      ),
                      ?statusChip,
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.xs),
                  _SentAgoCaption(createdAt: invite.createdAt),
                  if (failed) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.xs + 2),
                    _CancelFailedChip(
                      message: l10n.salonPendingInvitesCancelError,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The «надіслано N днів тому» caption, formatted ONCE per element and reused
/// across rebuilds (mobile-perf MEDIUM).
///
/// [formatRelativeDate] runs `kyivDayOf` → `toBeauticaTime` on `createdAt`, a
/// timezone transition-table binary search plus two `DateTime` allocations.
/// `_resolveTodayKyiv`'s 1-second cache covers only the `now` operand; the
/// `then` operand is uncached BY DESIGN (backlog `:191` / `:244` — "do NOT
/// memoise globally, fix at call sites"), so every rebuild of every row
/// re-ran the search. This is that call site, and this is the fix: a
/// per-element memo, invalidated only when the inputs it depends on actually
/// change.
///
/// Deliberately memoised LAZILY here rather than pre-computed into a caption
/// list beside `SalonInvitesState.invites`: both consuming screens build
/// their rows through a `SliverList.builder`, so an eager pass would format
/// all 200 history rows to render the ~6 on screen. Per element, the cost is
/// paid once for as long as the row stays mounted, on both surfaces, with no
/// state to plumb through either screen.
///
/// Two inputs, two invalidations: `createdAt` (a status flip keeps it, a
/// genuine new invite in this slot does not — [didUpdateWidget]) and the
/// [AppLocalizations] instance, which `Localizations` keeps stable per locale
/// and swaps on a locale change.
///
/// `now` IS STILL DELIBERATELY LEFT AT [formatRelativeDate]'s default — this
/// widget introduces no second clock. The `clockProvider` sweep that used to
/// be proposed here is DECLINED, not deferred: Phase 284 D2
/// (`docs/mobile-phases/phase-284-relative-date-dst-safe-day-arithmetic.md`)
/// records the reasoning and the seam that replaces it. Do not re-raise it.
class _SentAgoCaption extends StatefulWidget {
  const _SentAgoCaption({required this.createdAt});

  final DateTime createdAt;

  @override
  State<_SentAgoCaption> createState() => _SentAgoCaptionState();
}

class _SentAgoCaptionState extends State<_SentAgoCaption> {
  AppLocalizations? _formattedFor;
  String? _caption;

  @override
  void didUpdateWidget(covariant _SentAgoCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.createdAt != widget.createdAt) _caption = null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    String? caption = _caption;
    if (caption == null || !identical(l10n, _formattedFor)) {
      caption = l10n.salonPendingInvitesSentAgo(
        formatRelativeDate(l10n, widget.createdAt),
      );
      _caption = caption;
      _formattedFor = l10n;
    }
    return Text(
      caption,
      style: VelvetText.feedbackMutedSm,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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
