// NeumorphicAvatarEditor goldens — phase 072. The pristine / loaded(no URL) /
// picking(null) baselines are the SEED of today's render and must never move.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/widgets.dart';

import 'helpers/photo_state_golden.dart';

Widget _editor(AvatarEditState state) =>
    NeumorphicAvatarEditor(state: state, initials: 'ДЗ', onTap: () {});

void main() {
  registerPhotoGoldenMedia();

  photoGolden(
    'avatar_editor_pristine',
    () => _editor(AvatarEditState.pristine),
  );
  photoGolden('avatar_editor_loaded', () => _editor(AvatarEditState.loaded));
  photoGolden(
    'avatar_editor_picking_indeterminate',
    () => _editor(AvatarEditState.picking),
    settle: false,
  );

  // --- phase 072 additive states -------------------------------------------
  photoGolden(
    'avatar_editor_loaded_url',
    () => NeumorphicAvatarEditor(
      state: AvatarEditState.loaded,
      initials: 'ДЗ',
      onTap: () {},
      imageUrl: kGoldenAllowedUrl,
    ),
  );
  for (final ({String name, double value, bool settle}) c
      in <({String name, double value, bool settle})>[
        (name: '0', value: 0.0, settle: true),
        (name: '40', value: 0.4, settle: true),
        // 1.0 renders the INDETERMINATE ring (not yet confirmed by the server).
        (name: '100_indeterminate', value: 1.0, settle: false),
      ]) {
    photoGolden(
      'avatar_editor_picking_${c.name}',
      () => NeumorphicAvatarEditor(
        state: AvatarEditState.picking,
        initials: 'ДЗ',
        onTap: () {},
        progress: c.value,
      ),
      settle: c.settle,
    );
  }
  photoGolden(
    'avatar_editor_failed',
    () => NeumorphicAvatarEditor(
      state: AvatarEditState.loaded,
      initials: 'ДЗ',
      onTap: () {},
      uploadFailed: true,
      onRetry: () {},
    ),
  );
}
