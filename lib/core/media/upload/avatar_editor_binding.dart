// Phase 367 (9.6) — the own-avatar editor binding, PROMOTED out of the Phase
// 073 master «Особисті дані» screen (`personal_info_edit_screen.dart`'s private
// `_onAvatarTap` / `_onAvatarRetry` / `_recoverLostAvatar` / `_precacheAvatar`
// / `_showAvatarResult` / `_buildAvatarEditor`). REUSE-FIRST: one binding,
// every own-profile surface, every role — a fix here reaches all of them.
//
// Two shapes of the SAME code:
//   • [AvatarEditorBinding] — a `ConsumerState` mixin, for a screen that must
//     keep the controller alive and start recovery from its own `initState`
//     (the master edit screen does so BEFORE its profile has loaded);
//   • [SelfAvatarEditor] — a drop-in widget built on that mixin, for every
//     other own-profile surface (identity cards, client hub / passport, the
//     client / admin / owner «Особисті дані»).
//
// The badge is ALWAYS live: a tap opens the 071 source sheet, then the 073
// flow (pick, crop 1:1, progress, retry, remove). Read-only surfaces (another
// person, a public card) must not use this — they render `ProfileAvatar`.
//
// Own avatar only: the controller targets `UploadTarget.selfAvatar()`; there
// is no way to point this at another user.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

/// The signed-in user's own avatar URL, or `null` (no photo / not signed in).
/// A `.select` narrowing: a token refresh does not rebuild the avatar.
String? authUserAvatarUrlOrNull(AsyncValue<AuthSession> session) =>
    switch (session.value) {
      Authenticated(:final user) => user.avatarUrl,
      Unauthenticated() || null => null,
    };

/// Watches ONLY the signed-in user's own avatar URL — the one narrow session
/// avatar watch, shared by [SelfAvatarEditor] and any
/// [AvatarEditorBinding.buildAvatarEditor] `watchImageUrl` hook, so an upload
/// rebuilds just the editor that calls it.
String? watchSessionAvatarUrl(WidgetRef ref) =>
    ref.watch(authProvider.select(authUserAvatarUrlOrNull));

/// The monogram an avatar shows without a photo: the first letter of each of
/// the first two words of [displayName], upper-cased («Олена Ковальчук» →
/// «ОК»); `?` when there is none.
String avatarMonogram(String? displayName) {
  final List<String> words = (displayName ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return '?';
  return words.map((String w) => w[0].toUpperCase()).join();
}

/// The own-avatar editor wiring for a [ConsumerState] (see the file header).
mixin AvatarEditorBinding<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Call from `initState`. Keeps the (autoDispose) controller alive for the
  /// host's whole life — a recovery can start an upload before the editor is
  /// built, and an unwatched controller would be disposed, cancelling it —
  /// then, when [recoverLostPick], resumes an Android process-death pick
  /// post-frame (needs l10n).
  ///
  /// Only the «Особисті дані» edit screens recover (Phase 073 behaviour): the
  /// probe is a secure-storage read + clear, and running it on every profile
  /// / hub mount would put keystore I/O on each landing for a case (the OS
  /// killing the app mid-pick) that is rare. A pick lost from a profile card
  /// is resumed the next time the user opens «Особисті дані» — the pending
  /// tag is per user + kind, so it is never resumed for someone else.
  @protected
  void initAvatarEditorBinding({bool recoverLostPick = true}) {
    ref.listenManual<AvatarUploadState>(
      avatarUploadControllerProvider,
      (_, _) {},
    );
    if (recoverLostPick) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostAvatar());
    }
  }

  /// The shared tap / retry / recovery / snack flow, bound to the own-avatar
  /// controller ([MediaEditActions], promoted out of this mixin in Phase 369).
  MediaEditActions get _actions => MediaEditActions(
    host: this,
    readState: () => ref.read(avatarUploadControllerProvider),
    readFlow: () => ref.read(avatarUploadControllerProvider.notifier),
    kind: MediaKind.avatar,
    precache: _precacheAvatar,
    updatedMessage: (AppLocalizations l10n) => l10n.avatarUpdated,
    removedMessage: (AppLocalizations l10n) => l10n.avatarRemoved,
  );

  Future<void> _recoverLostAvatar() => _actions.recoverLost();

  /// Warms the image cache with the new remote avatar (decoded at the size the
  /// editor requests) so releasing the local preview does not flash.
  Future<void> _precacheAvatar(String url) async {
    if (!mounted) return;
    await precacheRemoteImage(
      context,
      url,
      NeumorphicAvatarEditor.discSize,
      NeumorphicAvatarEditor.discSize,
    );
  }

  /// The failed-state retry target: re-sends the SAME photo (no picker).
  Future<void> _onAvatarRetry() => _actions.retry();

  Future<void> _onAvatarTap(String? currentUrl) => _actions.tap(currentUrl);

  /// Maps the controller state onto the 072 editor states. [initials] is read
  /// on every editor rebuild (it may follow live name input). [badgeOnRing]
  /// is forwarded to [NeumorphicAvatarEditor.badgeOnRing].
  ///
  /// [watchImageUrl] (optional, Phase 367 audit perf LOW) — when set, the
  /// photo URL is watched INSIDE the editor's own `Consumer` through it
  /// (e.g. [watchSessionAvatarUrl]) and [imageUrl] is ignored, so an upload /
  /// remove rebuilds only the editor, never the host screen. Without it the
  /// editor renders [imageUrl] exactly as before.
  @protected
  Widget buildAvatarEditor({
    String? imageUrl,
    required String Function() initials,
    Key editorKey = const Key('avatar-editor'),
    bool badgeOnRing = false,
    String? Function(WidgetRef ref)? watchImageUrl,
  }) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AvatarUploadState upload = ref.watch(
          avatarUploadControllerProvider,
        );
        final String? url = watchImageUrl != null
            ? watchImageUrl(ref)
            : imageUrl;
        final String monogram = initials();
        void onTap() => _onAvatarTap(url);
        return switch (upload) {
          AvatarUploading(:final progress, :final previewFile) =>
            NeumorphicAvatarEditor(
              key: editorKey,
              state: AvatarEditState.picking,
              initials: monogram,
              badgeOnRing: badgeOnRing,
              onTap: onTap,
              imageUrl: url,
              previewFile: previewFile,
              progress: progress,
            ),
          AvatarRemoving() => NeumorphicAvatarEditor(
            key: editorKey,
            state: AvatarEditState.picking,
            initials: monogram,
            badgeOnRing: badgeOnRing,
            onTap: onTap,
            imageUrl: url,
          ),
          // The failed upload's photo stays visible under the retry target;
          // `loaded` is the only state that renders a photo + overlay.
          AvatarFailed(:final previewFile) => NeumorphicAvatarEditor(
            key: editorKey,
            state: AvatarEditState.loaded,
            initials: monogram,
            badgeOnRing: badgeOnRing,
            onTap: onTap,
            imageUrl: url,
            previewFile: previewFile,
            uploadFailed: true,
            onRetry: _onAvatarRetry,
          ),
          AvatarIdle() => NeumorphicAvatarEditor(
            key: editorKey,
            state: url != null
                ? AvatarEditState.loaded
                : AvatarEditState.pristine,
            initials: monogram,
            badgeOnRing: badgeOnRing,
            onTap: onTap,
            imageUrl: url,
          ),
        };
      },
    );
  }
}

/// The signed-in user's OWN avatar with the live camera badge — the one
/// avatar treatment for every own-profile surface of every role.
///
/// [imageUrl] defaults to the session user's `avatarUrl` (patched in place on
/// upload / remove), so callers normally pass only [initials]. [editorKey]
/// keys the inner [NeumorphicAvatarEditor]; each surface passes its own so
/// two surfaces alive at once (a profile under its pushed edit screen) never
/// share a key.
///
/// Layout: every caller places this at the START of a header row with a text
/// column after it. The badge sits ON the ring's lower-right arc
/// ([NeumorphicAvatarEditor.badgeOnRing]), so the layout box is the 104 dp
/// ring, and the box carries its own [textGap] trailing gutter — ring→text
/// 16 dp, exactly the pre-367 `ProfileAvatar` + `VelvetSpacing.md` geometry.
/// The first 367 port used the overhanging badge with NO gutter: the badge
/// and its 12 dp-blur shadow touched the text column's pin / salon rows
/// wherever that column grew down to it (320–360 dp, text ×1.3); a plain
/// gutter there would have cost the column 16 dp it does not have at 320 ×
/// 1.3 (the address split clips). One rule here gives every role's header the
/// same look; callers add no spacer of their own.
class SelfAvatarEditor extends ConsumerStatefulWidget {
  const SelfAvatarEditor({
    super.key,
    required this.initials,
    this.imageUrl,
    this.useSessionImage = true,
    this.editorKey = const Key('avatar-editor'),
  });

  /// The monogram shown when there is no photo.
  final String initials;

  /// An explicit photo URL; only read when [useSessionImage] is `false`.
  final String? imageUrl;

  /// Read the photo from the session user (the default) instead of
  /// [imageUrl].
  final bool useSessionImage;

  /// Key of the inner [NeumorphicAvatarEditor].
  final Key editorKey;

  /// Trailing gutter between the ring box (and the badge, flush with its
  /// right edge) and the text beside it: clears the badge's 12 dp shadow blur
  /// with room to spare — the pre-367 avatar→text `VelvetSpacing.md`.
  static const double textGap = VelvetSpacing.md;

  @override
  ConsumerState<SelfAvatarEditor> createState() => _SelfAvatarEditorState();
}

class _SelfAvatarEditorState extends ConsumerState<SelfAvatarEditor>
    with AvatarEditorBinding<SelfAvatarEditor> {
  @override
  void initState() {
    super.initState();
    // Profile / hub surfaces do not probe for a lost pick — see
    // [AvatarEditorBinding.initAvatarEditorBinding].
    initAvatarEditorBinding(recoverLostPick: false);
  }

  @override
  Widget build(BuildContext context) {
    final String? url = widget.useSessionImage
        ? watchSessionAvatarUrl(ref)
        : widget.imageUrl;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: SelfAvatarEditor.textGap),
      child: buildAvatarEditor(
        imageUrl: url,
        initials: () => widget.initials,
        editorKey: widget.editorKey,
        badgeOnRing: true,
      ),
    );
  }
}

/// The photo-editor tap flow — source sheet → change / remove → snack, plus
/// the failed-state retry and the Android lost-pick recovery — for ANY
/// upload controller built on `MediaUploadFlow`.
///
/// PROMOTED (Phase 369) out of [AvatarEditorBinding]'s private
/// `_onAvatarTap` / `_onAvatarRetry` / `_recoverLostAvatar` /
/// `_showAvatarResult` so the salon logo and cover editors run the SAME code
/// as the own-avatar editor (REUSE-FIRST: one flow, one fix, every photo
/// editor). The avatar binding behaves exactly as before.
///
/// [host] supplies `mounted` / `context` (checked after every await);
/// [readState] / [readFlow] read the controller lazily, only while mounted.
final class MediaEditActions {
  const MediaEditActions({
    required this.host,
    required this.readState,
    required this.readFlow,
    required this.kind,
    required this.precache,
    required this.updatedMessage,
    required this.removedMessage,
  });

  /// The editor's [State].
  final State host;

  /// The controller's current state.
  final AvatarUploadState Function() readState;

  /// The controller itself.
  final MediaUploadFlow Function() readFlow;

  /// The media kind (picks the native crop screen's title).
  final MediaKind kind;

  /// Warms the image cache with the new remote photo.
  final AvatarPrecache precache;

  /// Success snack after an upload.
  final String Function(AppLocalizations l10n) updatedMessage;

  /// Success snack after a removal.
  final String Function(AppLocalizations l10n) removedMessage;

  CropLabels _labels() =>
      CropLabels.forKind(AppLocalizations.of(host.context), kind);

  /// The editor tap: ignored while an upload / removal is in flight (a FAILED
  /// upload may be replaced: the tap opens the sheet for a new photo).
  /// [currentUrl] offers «Видалити фото» only when there is a photo.
  Future<void> tap(String? currentUrl) async {
    if (!host.mounted) return;
    final AvatarUploadState current = readState();
    if (current is AvatarUploading || current is AvatarRemoving) return;
    final ImageSourceChoice? choice = await showImageSourceSheet(
      host.context,
      canRemove: currentUrl != null,
    );
    if (choice == null || !host.mounted) return;
    final CropLabels labels = _labels();
    final MediaUploadFlow flow = readFlow();
    final AvatarChangeResult result = choice == ImageSourceChoice.remove
        ? await flow.remove()
        : await flow.change(choice, labels: labels, precache: precache);
    showResult(result, choice);
  }

  /// The failed-state retry target: re-sends the SAME photo (no picker).
  Future<void> retry() async {
    if (!host.mounted) return;
    final AvatarChangeResult result = await readFlow().retry(
      precache: precache,
    );
    showResult(result, ImageSourceChoice.gallery);
  }

  /// Resumes an Android process-death pick of THIS target (the flow drains
  /// anyone else's).
  Future<void> recoverLost() async {
    if (!host.mounted) return;
    final CropLabels labels = _labels();
    final AvatarChangeResult result = await readFlow().recoverLost(
      labels: labels,
      precache: precache,
    );
    showResult(result, ImageSourceChoice.gallery);
  }

  /// The success / failure snack for [result].
  void showResult(AvatarChangeResult result, ImageSourceChoice choice) {
    if (!host.mounted) return;
    final BuildContext context = host.context;
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (result) {
      case AvatarChangeCancelled():
        return;
      case AvatarChangeSucceeded():
        showSuccessSnack(
          context,
          choice == ImageSourceChoice.remove
              ? removedMessage(l10n)
              : updatedMessage(l10n),
        );
      case AvatarChangeFailed(:final failure):
        // The controller keeps the failed photo in [AvatarFailed]; the editor
        // shows it with the retry target.
        showErrorSnack(context, failure.message(l10n));
    }
  }
}
