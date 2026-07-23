// Phase 14.16/14.18 — the camel/mocha avatar-gradient palette cycled by
// per-master position across the salon booking flow's step-3 "Час" slides
// (`SalonTimeScreen`), step-4 confirmation, and success recap.
//
// Promoted from `SalonTimeScreen`'s former private per-file copy to ONE shared
// source so the confirmation + success screens render each master's avatar
// with the EXACT gradient the "Час" slide showed for the same slider
// position — no drift. The only camel/mocha placeholder set anywhere in the
// app (no master-photo pipeline is wired yet), matching the treatment
// `SalonMasterSummary` cards use elsewhere.

import 'package:flutter/painting.dart';

const List<List<Color>> _kSalonAvatarGradients = <List<Color>>[
  <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
  <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
  <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
  <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
  <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
  <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
];

/// The avatar gradient for the master at [index] (their slider position),
/// cycled so any master count stays within the fixed palette.
List<Color> salonAvatarGradient(int index) =>
    _kSalonAvatarGradients[index % _kSalonAvatarGradients.length];
