import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncError, AsyncValue;

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart'
    show PendingPortfolioUpload;
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show kPortfolioMaxPhotos;
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/prompt_link_text.dart';

/// The shared placeholder "Портфоліо" rail — a section label (optionally
/// paired with a «Всі фото» link) above a horizontal row of gradient
/// placeholder photo tiles.
///
/// REUSE-FIRST — this is the PROMOTION of what used to be two hand-copied
/// private implementations:
///   - `_PortfolioPlaceholderTile` + its inline rail Column, formerly in
///     `features/master/presentation/master_profile_screen.dart` (the
///     master's own editable profile — this is the canonical shape, the one
///     the header-row «Всі фото» link comes from);
///   - `_PortfolioTile` + its inline rail Column, formerly in
///     `features/master/presentation/public_master_profile_screen.dart` (the
///     read-only client-facing view — it omitted the «Всі фото» link, which
///     [onSeeAll] now models as an optional param instead of a fork).
/// The two tile classes were byte-for-byte identical but for the static glyph
/// field's name (`_glyphColor` vs `_photoGlyph`) — no visual difference; this
/// file keeps the master version's name.
///
/// Phase 404 (9.9, D1) — REAL photos, additively. Three optional params, all
/// defaulting to "off", so a caller passing none of them renders the
/// byte-identical placeholder rail (golden-pinned):
///   • [photos] — `null` (default) → the [count] gradient placeholders, also
///     what a caller shows while its portfolio read is LOADING; a list → one
///     [PortfolioTile] per photo, in list order, built lazily and capped at
///     the newest [kPortfolioMaxPhotos] ([count] is ignored);
///   • [hideWhenEmpty] — an EMPTY [photos] list renders nothing at all
///     (public surfaces: a client never sees an empty portfolio section);
///     otherwise an empty list shows the label + [AppLocalizations.portfolioEmptyOwn];
///   • [onRetry] — non-null → the read FAILED: label + an inline
///     «Не вдалося завантажити фото. Спробувати знову» line (owner surfaces;
///     public surfaces hide the section on error instead).
/// The rail itself reads no provider — wiring lives at the call sites.
///
/// Phase 405 (9.10, D1/D2/D6) — EDITOR affordances, additively. All default
/// to "off", so every read-only caller (the public master / salon profiles,
/// the staff profile) renders exactly as before (golden-pinned). They only
/// take effect on the real-photo path ([photos] non-null):
///   • [onAdd] — a leading [PortfolioAddTile]; hidden once
///     `photos + pending >= kPortfolioMaxPhotos`, inert (hourglass) while an
///     upload is in flight (the controller runs one at a time);
///   • [onDelete] — a small remove badge on every real tile (D8: every photo,
///     whoever uploaded it — [PortfolioPhoto] has no uploader);
///   • [pending] — uploads not yet stored, after the add tile: the local
///     photo + the shared upload ring, or the shared failed/retry overlay
///     ([onRetryPending]) with a discard badge ([onDiscardPending]);
///   • [showCount] — «Портфоліо · n/30» (n = stored + pending).
/// Only owner-context screens may pass them — pinned by
/// `test/core/media/portfolio/portfolio_owner_call_sites_test.dart`.
class PortfolioRail extends StatelessWidget {
  const PortfolioRail({
    super.key,
    this.railKey,
    this.onSeeAll,
    this.count = 6,
    this.photos,
    this.hideWhenEmpty = false,
    this.onRetry,
    this.onAdd,
    this.onDelete,
    this.pending,
    this.onRetryPending,
    this.onDiscardPending,
    this.showCount = false,
  });

  /// Maps a portfolio read onto the rail — the ONE place the D2 state
  /// mapping lives, shared by every real-photo call site:
  ///   • a value (incl. a refetch holding the previous list) → [photos];
  ///   • loading with no value → the placeholder tiles (existing look);
  ///   • error with no value → [onRetry] non-null: the inline retry line
  ///     (owner surfaces); [onRetry] null: nothing (public surfaces);
  ///   • [hideWhenEmpty] → an empty list renders nothing (public surfaces).
  factory PortfolioRail.fromAsync(
    AsyncValue<List<PortfolioPhoto>> async, {
    Key? key,
    Key? railKey,
    bool hideWhenEmpty = false,
    VoidCallback? onRetry,
    VoidCallback? onAdd,
    ValueChanged<PortfolioPhoto>? onDelete,
    List<PendingPortfolioUpload>? pending,
    ValueChanged<PendingPortfolioUpload>? onRetryPending,
    ValueChanged<PendingPortfolioUpload>? onDiscardPending,
    bool showCount = false,
  }) {
    final List<PortfolioPhoto>? value = async.value;
    if (value != null) {
      // Phase 405 — the editor affordances ride only on a settled list: the
      // add tile needs a count to enforce the cap against.
      return PortfolioRail(
        key: key,
        railKey: railKey,
        photos: value,
        hideWhenEmpty: hideWhenEmpty,
        onAdd: onAdd,
        onDelete: onDelete,
        pending: pending,
        onRetryPending: onRetryPending,
        onDiscardPending: onDiscardPending,
        showCount: showCount,
      );
    }
    if (async is AsyncError<List<PortfolioPhoto>>) {
      return onRetry == null
          // Public surface: hide the section — an empty list + hide flag is
          // exactly the rail's "render nothing" branch.
          ? PortfolioRail(
              key: key,
              railKey: railKey,
              photos: const <PortfolioPhoto>[],
              hideWhenEmpty: true,
            )
          : PortfolioRail(key: key, railKey: railKey, onRetry: onRetry);
    }
    return PortfolioRail(key: key, railKey: railKey);
  }

  /// Applied to the outer [Column] wrapping the whole section (header row +
  /// tile rail). Lets a screen pin a stable widget-tree key for
  /// golden/integration tests without this widget imposing one of its own —
  /// e.g. `public_master_profile_screen.dart` keeps
  /// `Key('public-master-profile-portfolio')`.
  final Key? railKey;

  /// Tapped when the «Всі фото» link is pressed. When null (the default),
  /// the link is omitted entirely and only the section label renders — used
  /// by the read-only public master profile, which has no gallery route.
  final VoidCallback? onSeeAll;

  /// Number of placeholder tiles to render. Defaults to 6, matching every
  /// current caller.
  final int count;

  /// The real portfolio, newest first. `null` → placeholder path (above).
  final List<PortfolioPhoto>? photos;

  /// When true, an empty [photos] list renders `SizedBox.shrink()`.
  final bool hideWhenEmpty;

  /// Non-null → render the inline load-error line with this retry link.
  final VoidCallback? onRetry;

  /// Phase 405 — non-null → leading [PortfolioAddTile] (below the cap).
  final VoidCallback? onAdd;

  /// Phase 405 — non-null → a remove badge on every real photo tile.
  final ValueChanged<PortfolioPhoto>? onDelete;

  /// Phase 405 — uploads not yet in [photos], shown after the add tile.
  final List<PendingPortfolioUpload>? pending;

  /// Phase 405 — the failed pending tile's retry target.
  final ValueChanged<PendingPortfolioUpload>? onRetryPending;

  /// Phase 405 — the failed pending tile's discard badge.
  final ValueChanged<PendingPortfolioUpload>? onDiscardPending;

  /// Phase 405 (D6) — label reads «Портфоліо · n/[kPortfolioMaxPhotos]».
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final VoidCallback? seeAll = onSeeAll;
    final VoidCallback? retry = onRetry;
    final List<PortfolioPhoto>? real = photos;
    if (retry == null && real != null && real.isEmpty && hideWhenEmpty) {
      return const SizedBox.shrink();
    }
    final List<PendingPortfolioUpload> queued = real == null
        ? const <PendingPortfolioUpload>[]
        : (pending ?? const <PendingPortfolioUpload>[]);
    final int shown = real == null
        ? 0
        : math.min(real.length, kPortfolioMaxPhotos);
    final VoidCallback? add = onAdd;
    // The cap counts pending uploads too (a failed one lands on retry) —
    // the same rule the controller's pre-check applies.
    final bool showAdd =
        real != null &&
        add != null &&
        real.length + queued.length < kPortfolioMaxPhotos;
    final String label = showCount && real != null
        ? l10n.portfolioLabelWithCount(
            shown + queued.length,
            kPortfolioMaxPhotos,
          )
        : l10n.masterPortfolioLabel;
    return Column(
      key: railKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
          child: seeAll == null
              ? Text(label, style: VelvetText.sectionLabel())
              : Row(
                  children: <Widget>[
                    Text(
                      l10n.masterPortfolioLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: seeAll,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(l10n.masterAllPhotos, style: VelvetText.link()),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: BrandColors.accentDeep,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        if (retry != null)
          Padding(
            key: const Key('portfolio-rail-error'),
            padding: const EdgeInsets.only(left: 4),
            child: PromptLinkText(
              prompt: l10n.portfolioLoadError,
              linkLabel: l10n.retryLabel,
              linkKey: const Key('portfolio-rail-retry'),
              onTap: retry,
            ),
          )
        else if (real != null && real.isEmpty && !showAdd && queued.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              l10n.portfolioEmptyOwn,
              key: const Key('portfolio-rail-empty'),
              style: VelvetText.feedback(BrandColors.muted),
            ),
          )
        else if (real != null && (showAdd || queued.isNotEmpty))
          // Phase 405 — the EDITOR rail: [add] [pending…] [photos…]. Same
          // lazy list + geometry as the read-only branch below; the empty
          // hint (if any) sits above the add tile.
          ..._editorRail(
            l10n,
            real: real,
            shown: shown,
            queued: queued,
            add: showAdd ? add : null,
          )
        else if (real != null)
          // Phase 404 audit R1/R2 — LAZY, unlike the fixed 6-tile placeholder
          // branch below: a real portfolio can hold up to
          // [kPortfolioMaxPhotos] network tiles, and an eager Row started every
          // fetch + decode the moment the tab opened. `ListView.separated`
          // builds only the tiles in (and `cacheExtent` around) the viewport.
          // Same geometry as the Row it replaces: 72px tiles, `md` gaps, no
          // trailing gap, zero padding — so on-screen pixels are unchanged.
          // A horizontal list inside the profile's vertical scroll view does
          // not compete for drags: each scrollable claims only its own axis.
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              // R2 — render at most the product cap. The server may return
              // more (up to 50); the list is newest-first, so the first
              // [kPortfolioMaxPhotos] are the newest.
              itemCount: math.min(real.length, kPortfolioMaxPhotos),
              separatorBuilder: (BuildContext _, int _) =>
                  const SizedBox(width: VelvetSpacing.md),
              itemBuilder: (BuildContext _, int i) => _photoTile(real, i),
            ),
          )
        else
          SizedBox(
            height: 72,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Matches the BouncingScrollPhysics convention used by the outer
              // vertical scroll in profile_scaffold.dart.
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < count; i++) ...<Widget>[
                    PortfolioTile(index: i),
                    if (i < count - 1) const SizedBox(width: VelvetSpacing.md),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  static const Key _addTileKey = Key('portfolio-add-tile');
  static Key _pendingKey(String id) => Key('portfolio-pending-$id');
  static Key _photoKey(String id) => Key('portfolio-photo-$id');

  /// One real photo tile; carries the remove badge when [onDelete] is set.
  Widget _photoTile(List<PortfolioPhoto> real, int i) {
    final PortfolioPhoto photo = real[i];
    final ValueChanged<PortfolioPhoto>? delete = onDelete;
    return PortfolioTile(
      key: _photoKey(photo.id),
      index: i,
      imageUrl: photo.url,
      decodeToCover: true,
      onRemove: delete == null ? null : () => delete(photo),
      removeKey: Key('portfolio-photo-delete-${photo.id}'),
    );
  }

  List<Widget> _editorRail(
    AppLocalizations l10n, {
    required List<PortfolioPhoto> real,
    required int shown,
    required List<PendingPortfolioUpload> queued,
    required VoidCallback? add,
  }) {
    final int lead = add == null ? 0 : 1;
    final bool busy = queued.any((PendingPortfolioUpload p) => p.isUploading);
    final ValueChanged<PendingPortfolioUpload>? retryPending = onRetryPending;
    final ValueChanged<PendingPortfolioUpload>? discardPending =
        onDiscardPending;
    // 405 audit P1 — every item is keyed (add / pending / photo), so map each
    // key back to its CURRENT item index: an insert (a new pending tile) or a
    // removal (it lands / a delete) then MOVES the existing elements instead
    // of rebuilding every later visible tile from scratch (no image flash).
    final Map<Key, int> itemIndexByKey = <Key, int>{
      if (add != null) _addTileKey: 0,
      for (int q = 0; q < queued.length; q++)
        _pendingKey(queued[q].id): lead + q,
      for (int i = 0; i < shown; i++)
        _photoKey(real[i].id): lead + queued.length + i,
    };
    return <Widget>[
      if (real.isEmpty && queued.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.sm),
          child: Text(
            l10n.portfolioEmptyOwn,
            key: const Key('portfolio-rail-empty'),
            style: VelvetText.feedback(BrandColors.muted),
          ),
        ),
      SizedBox(
        height: PortfolioTile.size,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: lead + queued.length + shown,
          // Item (not child) indices — `.separated` maps them past the
          // separators itself.
          findItemIndexCallback: (Key key) => itemIndexByKey[key],
          separatorBuilder: (BuildContext _, int _) =>
              const SizedBox(width: VelvetSpacing.md),
          itemBuilder: (BuildContext _, int i) {
            if (add != null && i == 0) {
              return PortfolioAddTile(key: _addTileKey, onTap: add, busy: busy);
            }
            final int q = i - lead;
            if (q < queued.length) {
              final PendingPortfolioUpload p = queued[q];
              return PortfolioTile(
                key: _pendingKey(p.id),
                index: q,
                previewFile: p.file,
                uploading: p.isUploading,
                progress: p.progress,
                uploadFailed: !p.isUploading,
                onRetry: retryPending == null ? null : () => retryPending(p),
                onRemove: p.isUploading || discardPending == null
                    ? null
                    : () => discardPending(p),
                removeKey: Key('portfolio-pending-discard-${p.id}'),
                removeSemanticLabel: l10n.portfolioDiscardUploadSemantics,
              );
            }
            return _photoTile(real, q - queued.length);
          },
        ),
      ),
    ];
  }
}

/// Phase 405 (9.10, D1/D2) — the leading «add photo» tile of an editor's
/// [PortfolioRail]: a 72×72 INSET well on the page tone, where every photo
/// tile is RAISED — an empty slot pressed into the surface, waiting to be
/// filled. Mocha `add_a_photo` glyph; [busy] (an upload in flight) swaps it
/// for an hourglass and makes the tile inert.
///
/// NOT built on `AnimatedScale` (a scale root breaks tap-by-key in tests):
/// press feedback is the well deepening its tint.
class PortfolioAddTile extends StatefulWidget {
  const PortfolioAddTile({super.key, required this.onTap, this.busy = false});

  /// Opens the image-source sheet. Never called while [busy].
  final VoidCallback onTap;

  /// An upload is in flight — inert, hourglass glyph.
  final bool busy;

  @override
  State<PortfolioAddTile> createState() => _PortfolioAddTileState();
}

class _PortfolioAddTileState extends State<PortfolioAddTile> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = widget.busy;
    return Semantics(
      button: true,
      enabled: !busy,
      label: AppLocalizations.of(context).portfolioAddPhoto,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: busy ? null : (_) => _setPressed(true),
        onTapCancel: busy ? null : () => _setPressed(false),
        onTapUp: busy
            ? null
            : (_) {
                _setPressed(false);
                widget.onTap();
              },
        child: SizedBox(
          height: PortfolioTile.size,
          width: PortfolioTile.size,
          child: NeumorphicInset(
            focused: _pressed,
            child: Center(
              child: Icon(
                busy ? Icons.hourglass_top_rounded : Icons.add_a_photo_outlined,
                size: 24,
                color: busy ? BrandColors.muted : BrandColors.accentDeep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small remove badge on a portfolio tile's top-right corner: a cream
/// disc with a mocha cross, lifted by the tile's own shadow pair. The hit
/// area is larger than the disc (it sits inside the 72 dp tile).
class _TileRemoveBadge extends StatelessWidget {
  const _TileRemoveBadge({
    required this.tapKey,
    required this.label,
    required this.onTap,
  });

  final Key tapKey;
  final String label;
  final VoidCallback onTap;

  static const double _hit = 32;
  static const double _disc = 22;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: tapKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _hit,
          width: _hit,
          child: Align(
            alignment: const Alignment(0.4, -0.4),
            child: Container(
              height: _disc,
              width: _disc,
              decoration: const BoxDecoration(
                color: BrandColors.white,
                shape: BoxShape.circle,
                boxShadow: _kTileLift,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: BrandColors.accentDeep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised photo tile's paired light/dark lift (also the remove badge's).
const List<BoxShadow> _kTileLift = <BoxShadow>[
  BoxShadow(
    color: BrandColors.shadowDarkButton,
    offset: Offset(2, 2),
    blurRadius: 5,
    spreadRadius: -1,
  ),
  BoxShadow(
    color: BrandColors.shadowLightStrong,
    offset: Offset(-2, -2),
    blurRadius: 5,
    spreadRadius: -1,
  ),
];

/// Raised 72×72 tile with a camel-mocha gradient fill.
///
/// [imageUrl] `null` (default) → the gradient placeholder, unchanged.
/// Set (phase 404, D1) → the photo, via the shared allow-listed
/// [RemoteImage], clipped to the same [VelvetRadii.field] corner and laid
/// over the gradient — so the gradient is the loading fill, and the glyph on
/// the gradient is the error / disallowed-URL fallback.
///
/// Phase 405 (9.10, D1) — editor states, additively (all off by default, so
/// every pre-405 tile renders byte-identically):
///   • [previewFile] — a PENDING upload: the local scratch photo (via
///     [LocalPreviewImage], never a URL) under the shared upload vocabulary —
///     [uploading] → [UploadProgressOverlay] ([progress]), [uploadFailed] →
///     [UploadFailedOverlay] with [onRetry];
///   • [onRemove] — a small remove badge in the top-right corner, keyed
///     [removeKey] (delete a stored photo / discard a failed upload).
class PortfolioTile extends StatefulWidget {
  const PortfolioTile({
    super.key,
    required this.index,
    this.imageUrl,
    this.decodeToCover = false,
    this.previewFile,
    this.uploading = false,
    this.progress,
    this.uploadFailed = false,
    this.onRetry,
    this.onRemove,
    this.removeKey,
    this.removeSemanticLabel,
  });

  /// The tile's side, in dp.
  static const double size = 72;

  final int index;

  /// The real photo URL, or `null` for the placeholder.
  final String? imageUrl;

  /// Forwarded to [RemoteImage.decodeToCover]: decode the photo so its SHORT
  /// side covers the 72px box (sharp `BoxFit.cover` for non-square photos).
  /// `false` (default) keeps [RemoteImage]'s fit-in-box decode. Ignored for
  /// the placeholder ([imageUrl] null).
  final bool decodeToCover;

  /// Phase 405 — a pending upload's local photo (takes precedence over
  /// [imageUrl]).
  final File? previewFile;

  /// Phase 405 — [previewFile] is uploading: progress ring overlay.
  final bool uploading;

  /// Phase 405 — 0.0–1.0 send progress (`>= 1` → indeterminate).
  final double? progress;

  /// Phase 405 — [previewFile] failed to upload: retry overlay.
  final bool uploadFailed;

  /// Phase 405 — the failed overlay's retry target.
  final VoidCallback? onRetry;

  /// Phase 405 — non-null → the top-right remove badge.
  final VoidCallback? onRemove;

  /// Phase 405 — key of the remove badge's tap target.
  final Key? removeKey;

  /// Phase 405 — the remove badge's accessible name; defaults to
  /// «Видалити фото роботи n».
  final String? removeSemanticLabel;

  @override
  State<PortfolioTile> createState() => _PortfolioTileState();
}

class _PortfolioTileState extends State<PortfolioTile> {
  bool _pressed = false;

  static const List<List<Color>> _fills = <List<Color>>[
    <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
    <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
    <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
  ];

  static final Color _glyphColor = BrandColors.white.withValues(alpha: 0.65);

  static const double _size = PortfolioTile.size;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  Widget _pendingContent(File file, Widget glyph) {
    final VoidCallback? retry = widget.onRetry;
    return ClipRRect(
      borderRadius: _radius,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: LocalPreviewImage(
              file: file,
              width: _size,
              height: _size,
              fallback: glyph,
            ),
          ),
          if (widget.uploading)
            UploadProgressOverlay(progress: widget.progress)
          else if (widget.uploadFailed)
            UploadFailedOverlay(onRetry: retry),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> fill = _fills[widget.index % _fills.length];
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? url = widget.imageUrl;
    final File? preview = widget.previewFile;
    final Widget glyph = Center(
      child: Icon(Icons.photo_outlined, color: _glyphColor, size: 22),
    );
    final double? progress = widget.progress;
    final Widget tile = Semantics(
      label: preview != null && widget.uploading
          ? l10n.portfolioUploadingSemantics
          : url == null && preview == null
          ? l10n.masterPortfolioTileSemantics(widget.index + 1)
          : l10n.portfolioPhotoSemantics(widget.index + 1),
      value: preview != null && widget.uploading && progress != null
          ? UploadProgressSpinner.percentLabel(progress)
          : null,
      image: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            height: _size,
            width: _size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: fill,
              ),
              boxShadow: _pressed ? null : _kTileLift,
            ),
            child: preview != null
                ? _pendingContent(preview, glyph)
                : url == null
                ? glyph
                : RemoteImage(
                    url: url,
                    width: _size,
                    height: _size,
                    borderRadius: _radius,
                    excludeFromSemantics: true,
                    decodeToCover: widget.decodeToCover,
                    fallback: glyph,
                  ),
          ),
        ),
      ),
    );
    final VoidCallback? remove = widget.onRemove;
    if (remove == null) return tile;
    return SizedBox(
      height: _size,
      width: _size,
      child: Stack(
        children: <Widget>[
          tile,
          Positioned(
            top: 0,
            right: 0,
            child: _TileRemoveBadge(
              tapKey:
                  widget.removeKey ??
                  Key('portfolio-tile-remove-${widget.index}'),
              label:
                  widget.removeSemanticLabel ??
                  l10n.portfolioDeletePhotoSemantics(widget.index + 1),
              onTap: remove,
            ),
          ),
        ],
      ),
    );
  }
}
