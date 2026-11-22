// M510 — client card / «Рейтинг клієнта» text helpers.
//
// 2026-11-21 (user: "fonts too big"): the preview's parameterised
// `comfortaa(size)` / `nunito(size)` helpers are GONE — every text on the card
// and the rating page uses the app's standard [VelvetText] tokens, the same
// ones the matching element uses elsewhere (name = profile display name,
// section titles = profile section labels, visit rows = master booking card,
// rating summary = `RatingSummaryCard`).

/// «4,9» — one decimal, Ukrainian comma.
String formatClientRatingAvg(double avg) =>
    avg.toStringAsFixed(1).replaceAll('.', ',');
