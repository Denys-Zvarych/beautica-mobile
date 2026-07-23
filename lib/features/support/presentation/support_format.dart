// Byte-size formatting for the support attachment tray.
//
// Pure presentation helper — formats a byte count as a compact "1.3 МБ" style
// string. The unit suffixes (Б / КБ / МБ) are Ukrainian abbreviations baked
// into the VelvetTouch design copy; they are NOT translated per-locale here
// because they are universal SI-style abbreviations shown only in the UA-first
// attachment tray. Should EN-locale unit abbreviations ever be required, route
// these through l10n with a {value}{unit} placeholder pattern.

/// Formats [bytes] as a compact human-readable size, e.g. `842 КБ`, `1.3 МБ`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  final double kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} КБ';
  final double mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} МБ';
}
