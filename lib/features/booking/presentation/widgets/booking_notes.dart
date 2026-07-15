/// Phase 14.3 — the note system. «Деталі запису» ONLY — no note text appears
/// on the `BookingCard` list row at any status.
///
/// Notes run to 1000 characters, and a scanned list row is not where you
/// read someone's paragraph. The card keeps the status badge (so the client
/// still sees *that* a booking was cancelled and *by whom*); the words
/// themselves live on the page you open to read them.
///
/// ## The rule the whole file exists to enforce
///
/// **Depth is authorship.** The only recessed element anywhere in this
/// feature is a note *somebody else wrote to you* ([InboundNote]). Your own
/// words come back with no container at all ([OutboundNote]) — a hairline
/// margin rule and the text. In a language where everything is extruded, a
/// sunken panel reads as something set INTO the surface: words that arrived.
///
/// This distinction becomes load-bearing on «Деталі запису» because **a
/// booking can carry a sent note and a received note at the same time** — a
/// client books with «без ароматизаторів — алергія», the salon later
/// cancels with «майстер захворів». Both are on screen, both are Ukrainian
/// prose in the same voice-neutral font, and the client must know instantly
/// which words are theirs and which arrived — the container says so before
/// either heading is read.
///
/// ## ⚠ PORTER, READ THIS FIRST — `providerComment` is NOT `CancellationReason`
///
/// Every note rendered here is [Booking.clientComment],
/// [Booking.clientCancellationNote] or [Booking.providerComment] — all three
/// FREE TEXT a human typed. The backend ALSO carries `CancellationReason`, a
/// machine-facing **enum** (`CLIENT_NO_SHOW`, `PROVIDER_UNAVAILABLE`, …) that
/// is a taxonomy code and is NEVER rendered to a human. If a note on screen
/// ever reads `PROVIDER_UNAVAILABLE`, the wrong field was bound. No field
/// consumed by this file is ever an enum.
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';

/// Which note a booking carries, who wrote it, and which way it points.
///
/// A booking may carry BOTH [clientBriefFor] (what the client asked for, at
/// booking) and [forStatus] (what happened, later) at once — see
/// [BookingNotes] for how they are shown together, chronologically.
class BookingNoteSpec {
  const BookingNoteSpec({
    required this.text,
    required this.heading,
    required this.icon,
    required this.accent,
    required this.inbound,
  });

  /// The note itself — always free text a human typed. Never an enum.
  final String text;

  /// Names the author, in the app's own neutral voice: «Коментар салону».
  final String heading;

  final IconData icon;
  final Color accent;

  /// `true` when someone else wrote this TO the client (provider → client) —
  /// picks the recessed-well [InboundNote] container. `false` for the
  /// client's own words handed back — the hairline-rule [OutboundNote].
  final bool inbound;

  /// The note attached to the booking's OUTCOME — the provider's words (on a
  /// cancellation or a no-show), or the client's own cancellation note.
  ///
  /// **ONE heading for `providerComment`, whatever the status** — it varies
  /// only by WHO wrote it (an independent master vs a salon —
  /// [BookingDisplayX.providerGenitive]), never by what kind of statement it
  /// is. Splitting the heading by status (an earlier draft tried «Причина
  /// від салону» on DECLINED vs «Коментар салону» on NOT_COMPLETED) would be
  /// the app editorialising about the note instead of just attributing it.
  ///
  /// The status still shapes the note in the two ways that carry no
  /// editorial judgement: the GLYPH (the provider's own mark on a
  /// cancellation; a quote mark on a no-show account) and the ACCENT (error
  /// red when something was taken from you; deep coffee, never red, for a
  /// no-show) — both mirror [BookingStatusVisual]'s vocabulary.
  static BookingNoteSpec? forStatus(Booking b, AppLocalizations l10n) {
    switch (b.status) {
      // The provider cancelled. Backend requires this note, so in practice
      // it is always present.
      case BookingStatus.declined:
        final String? text = b.providerComment;
        if (text == null) return null;
        return BookingNoteSpec(
          text: text,
          heading: l10n.bookingNoteHeadingProviderComment(b.providerGenitive),
          icon: b.atSalon
              ? Icons.storefront_rounded
              : Icons.content_cut_rounded,
          accent: BrandColors.error,
          inbound: true,
        );

      // The provider's account of the no-show, in their own words. Also
      // backend-required. Deep coffee, not red.
      case BookingStatus.notCompleted:
        final String? text = b.providerComment;
        if (text == null) return null;
        return BookingNoteSpec(
          text: text,
          heading: l10n.bookingNoteHeadingProviderComment(b.providerGenitive),
          icon: Icons.format_quote_rounded,
          accent: BrandColors.textSecondary,
          inbound: true,
        );

      // The client's own words, echoed back. OPTIONAL — null is ordinary (a
      // silent self-cancellation).
      case BookingStatus.cancelled:
        final String? text = b.clientCancellationNote;
        if (text == null) return null;
        return BookingNoteSpec(
          text: text,
          heading: l10n.bookingNoteHeadingYourReason,
          icon: Icons.subdirectory_arrow_right_rounded,
          accent: BrandColors.muted,
          inbound: false,
        );

      case BookingStatus.pending:
      case BookingStatus.confirmed:
      case BookingStatus.completed:
        return null;
    }
  }

  /// The note the client typed **at booking time** — «без ароматизаторів»,
  /// «буду з дитиною», «алергія на гель» — [Booking.clientComment].
  ///
  /// Already saved by the backend and already collected by
  /// `BookingCommentField` on the booking flow — this only renders it.
  /// Outbound, always: the client's own words, so they get the margin rule
  /// and no container, exactly like their cancellation note.
  static BookingNoteSpec? clientBriefFor(Booking b, AppLocalizations l10n) {
    final String? text = b.clientComment;
    if (text == null) return null;
    return BookingNoteSpec(
      text: text,
      heading: l10n.bookingNoteHeadingYourWishes,
      icon: Icons.subdirectory_arrow_right_rounded,
      accent: BrandColors.muted,
      inbound: false,
    );
  }
}

/// A note somebody else wrote **to** the client — the provider's reason for
/// cancelling, or their account of a no-show.
///
/// A recessed well — the only recessed element on any booking surface. See
/// the library doc: depth is authorship.
class InboundNote extends StatelessWidget {
  const InboundNote({super.key, required this.spec, this.maxLines = 6});

  final BookingNoteSpec spec;

  /// Clamp depth — 6 lines here (the page you opened *to read the thing*
  /// should not make you tap twice), vs the card's old 3 (now removed
  /// entirely — no note text renders on the card at any status).
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.bookingNoteSemantics(spec.heading, spec.text),
      excludeSemantics: true,
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(spec.icon, size: 12, color: spec.accent),
                  const SizedBox(width: VelvetSpacing.xs - 2),
                  Flexible(
                    child: Text(
                      spec.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.label().copyWith(color: spec.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VelvetSpacing.xs - 2),
              ClampedNote(
                text: spec.text,
                style: VelvetText.body(),
                maxLines: maxLines,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The client's **own** words, handed back to them — their cancellation
/// note, or the brief they typed when booking.
///
/// No container: a hairline margin rule and the words — marginalia, not a
/// message. Set beside an [InboundNote] it is unmistakably the quieter
/// object, and that difference IS the answer to "who cancelled this?" —
/// before colour, glyph or copy are read at all.
class OutboundNote extends StatelessWidget {
  const OutboundNote({super.key, required this.spec, this.maxLines = 6});

  final BookingNoteSpec spec;

  /// See [InboundNote.maxLines].
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.bookingNoteSemantics(spec.heading, spec.text),
      excludeSemantics: true,
      // The margin rule is a left Border, not a stretched Row child sized by
      // IntrinsicHeight — [ClampedNote] measures its text with a
      // LayoutBuilder, and a LayoutBuilder cannot answer an intrinsic query
      // (it asserts). A Border grows with the box for free.
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        padding: const EdgeInsets.only(left: VelvetSpacing.xs),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 2,
              color: BrandColors.faint.withValues(alpha: 0.75),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(spec.heading, style: VelvetText.label()),
            const SizedBox(height: 2),
            ClampedNote(
              text: spec.text,
              style: VelvetText.body(),
              maxLines: maxLines,
            ),
          ],
        ),
      ),
    );
  }
}

/// Note text clamped to [maxLines], with an inline show-more/show-less
/// toggle that appears ONLY when the text actually overflows — an inert
/// toggle is a small lie.
class ClampedNote extends StatefulWidget {
  const ClampedNote({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 6,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<ClampedNote> createState() => _ClampedNoteState();
}

class _ClampedNoteState extends State<ClampedNote> {
  bool _expanded = false;

  // Cached overflow measurement, keyed on the inputs that can actually change
  // it (text, style, maxLines, width). The expand/collapse `setState` touches
  // none of these, so it reuses the cache instead of re-running a full
  // `TextPainter.layout` on every toggle rebuild.
  bool? _overflows;
  String? _measuredText;
  TextStyle? _measuredStyle;
  int? _measuredMaxLines;
  double? _measuredWidth;

  bool _measureOverflow(BuildContext context, double maxWidth) {
    final bool? cached = _overflows;
    if (cached != null &&
        _measuredText == widget.text &&
        _measuredStyle == widget.style &&
        _measuredMaxLines == widget.maxLines &&
        _measuredWidth == maxWidth) {
      return cached;
    }

    // Measure at the real width so the toggle is never offered on a note that
    // already fits.
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    final bool overflows = painter.didExceedMaxLines;
    painter.dispose();

    _overflows = overflows;
    _measuredText = widget.text;
    _measuredStyle = widget.style;
    _measuredMaxLines = widget.maxLines;
    _measuredWidth = maxWidth;
    return overflows;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool overflows = _measureOverflow(context, constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSize(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                style: widget.style,
                maxLines: _expanded ? null : widget.maxLines,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
            if (overflows) ...<Widget>[
              const SizedBox(height: 2),
              _NoteToggle(
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The expand/collapse control for a clamped note. Its own tap target, so it
/// wins the gesture arena against a card's full-body tap where applicable.
class _NoteToggle extends StatelessWidget {
  const _NoteToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String label = expanded
        ? l10n.bookingNoteShowLess
        : l10n.bookingNoteShowMore;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.link(),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: BrandColors.accentDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every note a booking carries, in the order they were written — the
/// client's brief from the moment of booking, then whatever happened
/// afterwards. Renders NOTHING (a zero-height box) when the booking has
/// neither — see [has].
class BookingNotes extends StatelessWidget {
  const BookingNotes({super.key, required this.booking});

  final Booking booking;

  /// `true` when [booking] has anything at all to say. Callers use it to
  /// decide whether to emit the block into a list at all.
  static bool has(Booking b, AppLocalizations l10n) =>
      BookingNoteSpec.clientBriefFor(b, l10n) != null ||
      BookingNoteSpec.forStatus(b, l10n) != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Chronological: what the client asked for AT BOOKING, then what
    // happened.
    final BookingNoteSpec? brief = BookingNoteSpec.clientBriefFor(
      booking,
      l10n,
    );
    final BookingNoteSpec? outcome = BookingNoteSpec.forStatus(booking, l10n);

    final List<Widget> blocks = <Widget>[
      if (brief != null) OutboundNote(spec: brief),
      if (outcome != null)
        outcome.inbound
            ? InboundNote(spec: outcome)
            : OutboundNote(spec: outcome),
    ];
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < blocks.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: VelvetSpacing.sm),
          blocks[i],
        ],
      ],
    );
  }
}
