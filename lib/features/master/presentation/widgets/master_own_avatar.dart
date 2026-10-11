// Phase 367 audit (perf LOW) — PROMOTED, not copied, out of
// `salon_master_profile_screen.dart`'s private `_SalonMasterOwnAvatar`
// (REUSE-FIRST): the independent-master «Мій профіль» needed the identical
// narrow-watch own avatar, so both screens now render this one widget.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/media/upload/avatar_editor_binding.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';

/// A master's identity-card own-avatar editor, fed by a NARROW watch of
/// `masterProfileProvider`'s `avatarUrl` ([masterAvatarUrlOrNull]).
///
/// The host screen watches the profile through [MasterProfileIgnoringAvatar]
/// (or a loader selecting through [masterIgnoringAvatar]), so it never
/// rebuilds for the photo — this widget is the one place the photo is read.
/// An upload / remove patches `masterProfileProvider` in place; only this
/// widget rebuilds, the rest of the loaded body stays mounted. Kept OFF the
/// session user's avatar (`useSessionImage: false`): the master row is the
/// profile screens' source of truth for the photo.
class MasterOwnAvatar extends ConsumerWidget {
  const MasterOwnAvatar({
    super.key,
    required this.initials,
    this.editorKey = const Key('avatar-editor'),
  });

  /// The monogram shown when there is no photo.
  final String initials;

  /// Key of the inner `NeumorphicAvatarEditor` — see
  /// [SelfAvatarEditor.editorKey].
  final Key editorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SelfAvatarEditor(
      initials: initials,
      imageUrl: watchMasterAvatarUrl(ref),
      useSessionImage: false,
      editorKey: editorKey,
    );
  }
}

/// Watches ONLY the cached master's avatar URL — for a
/// `buildAvatarEditor(watchImageUrl: ...)` hook or a widget like
/// [MasterOwnAvatar].
String? watchMasterAvatarUrl(WidgetRef ref) =>
    ref.watch(masterProfileProvider.select(masterAvatarUrlOrNull));
