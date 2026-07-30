// Phase 221 — tap-to-expand affordance for the identity card's location note.
//
// `Master.locationNote` accepts up to 1000 characters (backend
// `@Size(max = 1000)`, `TEXT` column) — entrance/floor instructions like
// "Вхід у двір з боку вулиці Хрещатик, повз кав'ярню на розі…". Phase 219 (A)
// clamped it to `maxLines: 3` so it can no longer collapse to a single
// ellipsized line or grow the identity card unboundedly tall, but a 3-line
// clamp on a 1000-char field WILL still truncate real notes. This widget adds
// a «більше» / «згорнути» toggle so the full note stays reachable without
// permanently reserving the height for it.
//
// Mirrors the `ClampedNote` pattern already shipped in
// `lib/features/booking/presentation/widgets/booking_notes.dart` (LayoutBuilder
// + TextPainter `didExceedMaxLines` measurement, cached across rebuilds that
// don't change text/style/width) — NOT re-imported directly because
// `booking_notes.dart` lives in a different feature's `presentation/` layer,
// and this codebase's architecture forbids cross-feature `presentation/`
// imports (only `domain/` and `shared/` cross feature boundaries). A shared
// extraction is a reasonable follow-up once a THIRD call site appears (see the
// DRY house rule — two occurrences don't yet meet the "extract to `shared/`"
// bar) — tracked as a mobile-dev backlog note, not done here to keep this
// change's diff scoped to the master feature.
//
// frontend-design guidance (Phase 221): the toggle is a QUIET metadata
// affordance, not a CTA — same 11 sp size as the note it extends, camel
// (`BrandColors.accent` via `VelvetText.linkAccent`) rather than mocha
// (`VelvetText.link()`, reserved for primary links/CTAs elsewhere in this
// system), no icon, no underline, flush-left with the note above it.
//
// Phase 221 audit fix (mobile-security MEDIUM): `widget.text` is
// provider-authored free text with no character-class validation at the
// backend, so it is run through `sanitizeDisplayText` (strips Unicode bidi
// override/format + zero-width controls — see `master_text_sanitizer.dart`)
// before EITHER the `TextPainter` overflow measurement or the rendered
// `Text` sees it. Both paths must consume the identical sanitized string —
// measuring the raw string while rendering the sanitized one (or vice versa)
// would desync the overflow decision from what's actually on screen.
//
// Phase 221 audit fix (mobile-perf LOW): the expand/collapse `AnimatedSize`
// gets its own `RepaintBoundary` here. Both call sites
// (`master_profile_screen.dart` / `public_master_profile_screen.dart`) nest
// this widget inside a shared `_revealWith`/`_reveal`-provided
// `RepaintBoundary` that also covers the identity card's `ProfileAvatar` —
// whose `CustomPaint` (`_CircleInsetPainter`) uses an expensive
// `MaskFilter.blur`. Without a boundary of its own, every one of the ~13
// frames of the note's 220 ms expand/collapse forces that single shared
// layer to repaint, which re-runs the avatar's blur paint too even though
// only the note's text is changing size. Isolating the animating subtree in
// its own layer confines those repaints to just this widget. This is NOT a
// redundant boundary: today there is no `RepaintBoundary` between the
// animating `AnimatedSize` and the shared card-level one, so this is a new
// isolation point, not a duplicate of an existing one.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'master_text_sanitizer.dart';

/// The identity card's location-note row: clamped to [maxLines] with a
/// «більше»/«згорнути» toggle that appears ONLY when the note actually
/// overflows that budget — an inert toggle on a short note is a small lie.
class MasterLocationNote extends StatefulWidget {
  const MasterLocationNote({super.key, required this.text, this.maxLines = 3});

  /// The note text — up to 1000 chars per the backend contract.
  final String text;

  /// Collapsed-state line budget (Phase 219 (A) — matches the plain `Text`
  /// this widget replaces).
  final int maxLines;

  @override
  State<MasterLocationNote> createState() => _MasterLocationNoteState();
}

class _MasterLocationNoteState extends State<MasterLocationNote> {
  bool _expanded = false;

  // Sanitized once per `widget.text` change (not per `build()`, which also
  // runs on the toggle-triggered `setState`) — see `initState`/
  // `didUpdateWidget` below. This is the SINGLE source of truth consumed by
  // both the `TextPainter` overflow measurement and the rendered `Text`;
  // deliberately not a second independent cache alongside `_measuredText`
  // below, which still exists to skip the (separate, more expensive)
  // `TextPainter.layout` call itself.
  late String _sanitizedText;

  // Cached overflow measurement, keyed on the inputs that can actually change
  // it. The expand/collapse `setState` touches none of these, so it reuses
  // the cache instead of re-running a `TextPainter.layout` on every toggle.
  bool? _overflows;
  String? _measuredText;
  int? _measuredMaxLines;
  double? _measuredWidth;
  TextScaler? _measuredTextScaler;

  @override
  void initState() {
    super.initState();
    _sanitizedText = sanitizeDisplayText(widget.text);
  }

  @override
  void didUpdateWidget(covariant MasterLocationNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _sanitizedText = sanitizeDisplayText(widget.text);
    }
  }

  bool _measureOverflow(BuildContext context, double maxWidth, String text) {
    // mobile-qa fix (Phase 219/220/221 audit): the RENDERED `Text` below
    // honours the ambient `MediaQuery.textScalerOf(context)` automatically —
    // but a bare `TextPainter` defaults to `TextScaler.noScaling` unless told
    // otherwise. Without passing it explicitly here, this measurement always
    // evaluated as if the system font scale were 1.0×, so a note that
    // genuinely overflows 3 lines ONLY at a larger accessibility text scale
    // (a borderline note that fits fine at 1.0×) was silently clipped by the
    // `overflow: TextOverflow.ellipsis` below with NO expand affordance ever
    // appearing — unreachable content at exactly the text scale where users
    // most need the escape hatch.
    final TextScaler textScaler = MediaQuery.textScalerOf(context);

    // `text` is already the SANITIZED string (`_sanitizedText`, computed once
    // in `initState`/`didUpdateWidget`) — the cache key must track that, not
    // `widget.text`, or a raw-vs-sanitized mismatch between two rebuilds
    // could return a stale overflow verdict for text the `TextPainter` never
    // actually measured.
    final bool? cached = _overflows;
    if (cached != null &&
        _measuredText == text &&
        _measuredMaxLines == widget.maxLines &&
        _measuredWidth == maxWidth &&
        _measuredTextScaler == textScaler) {
      return cached;
    }

    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: VelvetText.feedbackMutedNote),
      maxLines: widget.maxLines,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final bool overflows = painter.didExceedMaxLines;
    painter.dispose();

    _overflows = overflows;
    _measuredTextScaler = textScaler;
    _measuredText = text;
    _measuredMaxLines = widget.maxLines;
    _measuredWidth = maxWidth;
    return overflows;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool overflows = _measureOverflow(
          context,
          constraints.maxWidth,
          _sanitizedText,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // RepaintBoundary isolates the animating note from the shared
            // card-level boundary (see the class-level doc comment above)
            // so the identity card's blurred `ProfileAvatar` does not
            // repaint on every expand/collapse frame.
            RepaintBoundary(
              child: AnimatedSize(
                // Matches the codebase's established accordion expand/collapse
                // timing (services_list_screen.dart / salon_services_accordion
                // .dart AnimatedSize) so this reads as the same motion language.
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: Text(
                  _sanitizedText,
                  // Pre-cached static (11 sp variant) avoids a per-frame
                  // copyWith call.
                  style: VelvetText.feedbackMutedNote,
                  maxLines: _expanded ? null : widget.maxLines,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
            ),
            if (overflows) ...<Widget>[
              const SizedBox(height: 2),
              _NoteExpandToggle(
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

/// The «більше» / «згорнути» tap target — its own hit area so it wins the
/// gesture arena against any ancestor tap handler.
class _NoteExpandToggle extends StatelessWidget {
  const _NoteExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = expanded
        ? l10n.masterLocationNoteShowLess
        : l10n.masterLocationNoteShowMore;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const Key('master-profile-location-note-toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Invisible tap-target padding — does not affect the visible
          // spacing rhythm (matches the note's existing 2 dp gap above it).
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.linkAccent,
          ),
        ),
      ),
    );
  }
}
