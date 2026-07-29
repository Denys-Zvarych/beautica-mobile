/// «У цей день у вас N записів» — the confirmation a master sees when the day
/// off (or the narrowed working hours) they are about to save would cancel
/// bookings that clients have already made (2026-07-26 design).
///
/// Ported from the approved preview
/// `docs/signup-designs/DayOffConflictDialog/lib/widgets/day_off_conflict_dialog.dart`.
///
/// ## What this dialog is for
///
/// The master already decided to take the day. This is not asking them to
/// reconsider; it is making sure they *see the people* the decision lands on
/// before it lands. So the dialog leads with the count, shows every affected
/// booking by name and time, states the consequence in one plain sentence,
/// and then asks once.
///
/// ## What is deliberately NOT here
///
/// * **No note / reason / comment field.** Locked product decision
///   (2026-07-26): a master gives no reason for taking a day off — there is
///   no `providerComment` field on this write at all.
/// * **No per-booking action.** There is no "keep this one". The change is
///   all-or-nothing, so no row is tappable and no row has a control on it.
/// * **No price.** The master is weighing people and times, not revenue.
/// * **No promise of a client notification.** Unlike the preview fixture
///   copy, the shipped consequence note does NOT say the client "receives a
///   notification" — the backend's 2026-07-26 design (D6) sends none for
///   this path; only the booking's status changes. Promising one here would
///   be simply false.
///
/// ## Backing out is the safe path
///
/// `barrierDismissible: true`, the OS back gesture, and «Залишити як є» all
/// resolve to `null`. **Nothing is cancelled unless the master deliberately
/// taps the brick-red button** — every reflex is safe, only intent is
/// destructive.
///
/// ## Chrome
///
/// Mirrors the shipped modal shell 1:1 (`CancelBookingDialog` /
/// `CategoryRequestDialog`): a transparent [Dialog], `insetPadding` (h: lg,
/// v: xl), a `maxWidth: 420` [ConstrainedBox], one [NeumorphicCard] surface,
/// a centred badge circle, a title, a muted subline, then a primary pill over
/// a centred quiet action. No new modal chrome is invented here — only the
/// [ConflictTrough] inside it is new.
library;

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/schedule_model.dart';
import 'conflict_trough.dart';

const String _tag = 'feature.schedule.dayOffConflict';

/// Everything [DayOffConflictDialog] needs to render — the change that was
/// checked, plus the server's [check] result. Combines the [check] (data
/// only — see [OverrideConflictCheck]'s doc) with the change metadata the
/// preview's `DayOffConflict` fixture baked directly into Ukrainian string
/// getters; this app keeps all of that copy in `AppLocalizations` instead
/// (the `no_raw_ui_strings` CI gate), so this class carries only DATA.
class DayOffConflictPreview {
  const DayOffConflictPreview({
    required this.kind,
    required this.from,
    required this.to,
    required this.check,
    this.hoursLabel,
  });

  final DayOffChangeKind kind;

  /// First / last affected calendar date (inclusive). Equal for a single day.
  final DateTime from;
  final DateTime to;

  /// The new working window, e.g. `10:00–15:00`. Only set for
  /// [DayOffChangeKind.narrowedHours] — see
  /// [ScheduleOverride.narrowedHoursLabel].
  final String? hoursLabel;

  final OverrideConflictCheck check;

  /// The AUTHORITATIVE conflict count for every header/CTA phrase in this
  /// dialog. Per [OverrideConflictCheck]'s own doc, `totalCount` — not
  /// `conflicts.length` — is the number that stays correct when the server
  /// caps the returned preview ROWS at `MAX_PREVIEW_RESULTS`
  /// (`check.truncated == true`): `totalCount` is still exact whenever
  /// `check.isCountExact` is true, it is simply larger than the row count.
  /// Reading `conflicts.length` here would silently undercount — a master
  /// with 8 real conflicts but a 5-row preview would see a confident,
  /// wrong "5 записів". `conflicts.length` remains the right value for the
  /// SEPARATE "shown" note ([AppLocalizations.dayOffConflictTruncatedNote]),
  /// which is deliberately about the row count, not the true total.
  int get count => check.totalCount;
}

/// Opens the conflict confirmation.
///
/// Resolves to `true` when the master confirmed — the caller then saves the
/// schedule change with `cancelOverlapping: true`. Resolves to `null` on
/// every other exit (quiet action, scrim tap, back gesture), which means *do
/// nothing at all* — not even the underlying schedule change is saved.
Future<bool?> showDayOffConflictDialog(
  BuildContext context,
  DayOffConflictPreview preview,
) {
  if (kDebugMode) {
    log(
      'show conflict dialog: kind=${preview.kind} count=${preview.count} '
      'exact=${preview.check.isCountExact}',
      name: _tag,
      level: 800,
    );
  }
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    builder: (_) => DayOffConflictDialog(preview: preview),
  );
}

class DayOffConflictDialog extends StatefulWidget {
  const DayOffConflictDialog({super.key, required this.preview});

  final DayOffConflictPreview preview;

  @override
  State<DayOffConflictDialog> createState() => _DayOffConflictDialogState();
}

class _DayOffConflictDialogState extends State<DayOffConflictDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  /// Rows past this index share the last slice, so a twenty-row list still
  /// finishes assembling inside the same 460 ms as a one-row list.
  static const int _maxStaggeredRows = 8;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    // Drive from after the first frame rather than from initState: on the
    // first frame the controller can still read 0.0, which — since the whole
    // card is wrapped in the entrance — would flash an empty dialog. A
    // post-frame start guarantees a real tick exists first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool animationsOff =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (animationsOff) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// One row's staggered fade-up slice.
  Widget _revealRow(int index, Widget child) {
    final int i = index > _maxStaggeredRows ? _maxStaggeredRows : index;
    final double start = (0.30 + i * 0.055).clamp(0.0, 0.80);
    final double end = (start + 0.30).clamp(0.0, 1.0);
    final Animation<double> curved = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? c) {
        final double t = curved.value.clamp(0.0, 1.0);
        // Floor the painted opacity so a stalled ticker can never leave a row
        // completely invisible.
        return Opacity(
          opacity: (0.06 + t * 0.94).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: c),
        );
      },
      child: child,
    );
  }

  String _countPhrase(AppLocalizations l10n, DayOffConflictPreview p) {
    return p.check.isCountExact
        ? l10n.dayOffConflictCountPhrase(p.count)
        : l10n.dayOffConflictCountPhraseApprox(p.count);
  }

  String _title(AppLocalizations l10n, DayOffConflictPreview p) {
    final String countPhrase = _countPhrase(l10n, p);
    switch (p.kind) {
      case DayOffChangeKind.singleDay:
        return l10n.dayOffConflictTitleSingleDay(countPhrase);
      case DayOffChangeKind.dateRange:
        return l10n.dayOffConflictTitleRange(countPhrase);
      case DayOffChangeKind.narrowedHours:
        return l10n.dayOffConflictTitleNarrowedHours(countPhrase);
    }
  }

  String _subline(AppLocalizations l10n, DayOffConflictPreview p) {
    switch (p.kind) {
      case DayOffChangeKind.singleDay:
        return l10n.dayOffConflictSublineDayOff(formatFullDate(p.from));
      case DayOffChangeKind.dateRange:
        final int days = p.to.difference(p.from).inDays + 1;
        final String range =
            '${formatFullDate(p.from)} – ${formatFullDate(p.to)}';
        return '${l10n.dayOffConflictSublineDayOff(range)} · '
            '${l10n.dayOffConflictSublineDayCount(days)}';
      case DayOffChangeKind.narrowedHours:
        return l10n.dayOffConflictSublineNarrowedHours(
          formatFullDate(p.from),
          p.hoursLabel ?? '',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DayOffConflictPreview p = widget.preview;
    final int n = p.count;

    // The trough takes a share of the viewport rather than a flat cap: on a
    // short phone that keeps the count sentence above it on screen, and on a
    // tall one it still stops well short of turning the dialog into a page.
    final double troughMax = (MediaQuery.sizeOf(context).height * 0.36).clamp(
      132.0,
      ConflictTrough.maxTroughHeight,
    );

    return _DialogShell(
      entrance: _entrance,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Everything above the actions lives in ONE scroll region.
          //
          // The trough scrolls its own rows; this outer list exists purely
          // so that a narrow screen — where a three-line title plus a
          // five-line subline plus the trough genuinely do not fit —
          // degrades into a scroll instead of an overflow. It shrink-wraps,
          // so on every ordinary phone it never scrolls at all.
          //
          // The two actions sit OUTSIDE it on purpose: a destructive confirm
          // and its escape hatch must never be something you have to scroll
          // to find.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: <Widget>[
                const Center(child: _DestructiveBadge()),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  _title(l10n, p),
                  textAlign: TextAlign.center,
                  style: VelvetText.headingLg,
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  _subline(l10n, p),
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),
                Text(
                  l10n.dayOffConflictTroughCaption(n),
                  style: VelvetText.label(),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                ConflictTrough(
                  key: const Key('day-off-conflict-trough'),
                  conflicts: p.check.conflicts,
                  spansMultipleDates: p.check.spansMultipleDates,
                  reveal: _revealRow,
                  maxHeight: troughMax,
                ),
                if (p.check.truncated) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    l10n.dayOffConflictTruncatedNote(p.check.conflicts.length),
                    style: VelvetText.feedbackMutedSm,
                  ),
                ],
                const SizedBox(height: VelvetSpacing.sm),
                _ConsequenceNote(count: n),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          DestructiveButton(
            key: const Key('day-off-conflict-confirm'),
            label: l10n.dayOffConflictConfirmCta(n),
            onPressed: () => dismissOverlay<bool>(context, true),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          QuietAction(
            key: const Key('day-off-conflict-keep'),
            label: l10n.dayOffConflictKeepCta,
            onPressed: () => dismissOverlay(context),
          ),
        ],
      ),
    );
  }
}

/// The conflict check itself failed — network down, or the backend refused.
///
/// The same shell, minus the list: there is nothing to show, so the dialog
/// does not pretend there is. It states what did not happen and offers the
/// two moves that exist. It does **not** offer to save anyway — saving blind
/// is precisely the outcome this whole flow exists to prevent.
///
/// Resolves to `true` when the master taps retry (the caller re-runs the
/// conflict check), `null` on any way of backing out — same "do nothing"
/// contract as [showDayOffConflictDialog].
Future<bool?> showDayOffCheckErrorDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    builder: (_) => const DayOffCheckErrorDialog(),
  );
}

class DayOffCheckErrorDialog extends StatefulWidget {
  const DayOffCheckErrorDialog({super.key});

  @override
  State<DayOffCheckErrorDialog> createState() => _DayOffCheckErrorDialogState();
}

class _DayOffCheckErrorDialogState extends State<DayOffCheckErrorDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool animationsOff =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (animationsOff) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _DialogShell(
      entrance: _entrance,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: <Widget>[
                const Center(
                  child: _DestructiveBadge(icon: Icons.wifi_off_rounded),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  l10n.dayOffCheckErrorTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.headingLg,
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.dayOffCheckErrorBody,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicButton(
            key: const Key('day-off-check-retry'),
            label: l10n.dayOffCheckErrorRetryCta,
            icon: Icons.refresh_rounded,
            onPressed: () => dismissOverlay<bool>(context, true),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          QuietAction(
            key: const Key('day-off-check-keep'),
            label: l10n.dayOffConflictKeepCta,
            onPressed: () => dismissOverlay(context),
          ),
        ],
      ),
    );
  }
}

/// The shared modal shell: transparent [Dialog] → height/width cap → entrance
/// (scale + fade) → one bordered [NeumorphicCard].
///
/// The height cap is what keeps a twenty-booking dialog a dialog: the card is
/// never taller than 82% of the viewport, so the [Flexible] trough inside it
/// gives up space instead of the buttons sliding off the bottom.
class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.entrance, required this.child});

  final AnimationController entrance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> curved = CurvedAnimation(
      parent: entrance,
      curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xl,
      ),
      child: AnimatedBuilder(
        animation: curved,
        builder: (BuildContext context, Widget? c) {
          final double t = curved.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: (0.08 + t * 0.92).clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.94 + t * 0.06, child: c),
          );
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: NeumorphicCard(
            key: const Key('day-off-conflict-dialog'),
            showBorder: true,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The badge circle. `ClientBookingConflictDialog`-family dialogs elsewhere
/// deliberately use a *camel* circle for a routine scheduling clash; this
/// dialog **is** a destructive state — a person's appointment disappears —
/// so it takes the red, exactly the line those dialogs draw.
class _DestructiveBadge extends StatelessWidget {
  const _DestructiveBadge({this.icon = Icons.event_busy_rounded});

  final IconData icon;

  static const double _diameter = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: BrandColors.error, size: 26),
    );
  }
}

/// The consequence, in one sentence, in the client's vocabulary.
///
/// «Скасовано» is quoted because it is the literal word the client will read
/// on their own «Мої записи» card. Muted, glyph-led, placed under the list:
/// by the time the eye reaches it the master already knows *who*, and this
/// only has to answer *and then what*.
class _ConsequenceNote extends StatelessWidget {
  const _ConsequenceNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: BrandColors.muted,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm - 4),
        Expanded(
          child: Text(
            l10n.dayOffConflictConsequenceNote(count),
            style: VelvetText.feedbackMutedSm,
          ),
        ),
      ],
    );
  }
}

// ── Destructive confirm + safe back-out ─────────────────────────────────────

/// The destructive confirm pill — **the only saturated `error` surface in
/// this dialog.**
///
/// [BrandColors.error] (`#B0452F`) is a warm brick that shares the palette's
/// red-dominant, low-chroma warmth rather than a bolted-on Material red, so
/// it sits inside the Warm Mocha family rather than shouting over it. Colour
/// is never the only signal: the pill also carries an `event_busy` glyph and
/// a label that names the object («Так, скасувати записи»).
///
/// The lift ([VelvetShadows.destructiveLift]) is non-offset and
/// alpha-attenuated — see that constant's doc for the Impeller-GLES
/// corner-sliver rationale. Motion mirrors [NeumorphicButton]:
/// `AnimatedScale(0.97)` on press.
class DestructiveButton extends StatefulWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.event_busy_rounded,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;

  @override
  State<DestructiveButton> createState() => _DestructiveButtonState();
}

class _DestructiveButtonState extends State<DestructiveButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed!.call();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: VelvetSizes.cta,
            decoration: BoxDecoration(
              color: BrandColors.error,
              borderRadius: BorderRadius.circular(VelvetRadii.button),
              boxShadow: _pressed || !_enabled
                  ? null
                  : VelvetShadows.destructiveLift,
            ),
            alignment: Alignment.center,
            child: widget.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: BrandColors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(widget.icon, size: 18, color: BrandColors.white),
                      const SizedBox(width: VelvetSpacing.sm),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.cta(),
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

/// The safe way out — a quiet, full-width text action with a real 48 dp
/// target.
///
/// This dialog is the one screen in the app where «Скасувати» is genuinely
/// ambiguous: it means both *cancel the bookings* and *cancel this action*,
/// and a master reading fast would have to guess which. So the destructive
/// button names its object («…скасувати записи») and the back-out never uses
/// the verb at all — «Залишити як є» says plainly that nothing moves.
class QuietAction extends StatelessWidget {
  const QuietAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 48,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.accentDeep,
            overlayColor: BrandColors.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VelvetRadii.button),
            ),
          ),
          child: Text(
            label,
            style: VelvetText.feedback(BrandColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
