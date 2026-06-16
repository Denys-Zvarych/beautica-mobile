// Phase 15.2 — Master Schedule slot tints.
//
// Transcribed VERBATIM from the approved preview
// `docs/signup-designs/MasterSchedule/lib/theme/slot_colors.dart`.
//
// These are the ONLY non-token colours in the schedule screen — three
// desaturated tints (sage / dusty-rose / recessed taupe) that read as tints OF
// the warm Velvet Touch base rather than foreign accent hues. Each [SlotState]
// pairs a fill, a border and an accent (text) colour so the state NEVER relies
// on hue alone (the legend + per-cell label reinforce it; cf. mobile-qa
// colour-only-signal rule).
//
// Deviation from the preview: the human-facing `legend` label is NOT defined
// here (the preview hard-coded the Ukrainian string). Production routes those
// strings through `AppLocalizations` (see `slotStateLabel` in
// `day_schedule.dart`) to satisfy `no_raw_ui_strings`. The colour values are
// byte-for-byte identical to the approved preview.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';

/// The three schedule slot states. This screen defines *when the master works*
/// — it never shows client bookings. Each state maps to the availability model:
///
///  • [available]   — a 30-min slot inside a working interval: the master IS
///                    working then. Green, soft and desaturated to sit on the
///                    taupe base.
///  • [timeOff]     — a per-date Time-Off override (OVERRIDE_DAY_OFF) that
///                    closes a slot inside an otherwise working day. Pink.
///  • [unavailable] — outside every working interval for the day (the template
///                    or override does not cover it, or it is a day off / a
///                    NO_SCHEDULE gap). Grey.
///
/// Colours are intentionally low-chroma so they read as tints OF the warm base
/// rather than as foreign accent hues. Each pairs a fill, a border and a text
/// colour so the state never relies on hue alone (legend + label reinforce it).
enum SlotState {
  available,
  timeOff,
  unavailable;

  Color get fill => switch (this) {
    SlotState.available => const Color(0xFFE4E7D8), // soft sage tint
    SlotState.timeOff => const Color(0xFFEEDADB), // soft dusty-rose tint
    SlotState.unavailable => const Color(0xFFDED5C7), // recessed taupe
  };

  Color get border => switch (this) {
    SlotState.available => const Color(0xFFBFC9A6),
    SlotState.timeOff => const Color(0xFFD9B6B8),
    SlotState.unavailable => const Color(0xFFCBBEA9),
  };

  Color get accent => switch (this) {
    SlotState.available => const Color(0xFF5C7A4A), // == BrandColors.success
    SlotState.timeOff => const Color(0xFFB0452F), // == BrandColors.error
    SlotState.unavailable => BrandColors.faint,
  };
}
