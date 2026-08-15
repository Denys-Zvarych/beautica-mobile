import 'dart:collection';

import 'package:flutter/material.dart';

/// Beautica brand palette — VelvetTouch design system (2026-05-23).
///
/// Transcribed verbatim from the approved preview app in
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
/// Only the outer class name was kept as [BrandColors] for source
/// compatibility with existing call sites; every constant name and hex
/// value is a 1:1 copy of [VelvetColors] from the design source.
///
/// Light-mode neumorphic ("soft UI") palette: a single warm-taupe base
/// tone with depth communicated exclusively through paired light/dark
/// shadows. Color is reserved for the camel/mocha accent family and for
/// semantic feedback (always paired with icon + text).
abstract final class BrandColors {
  /// Page + surface base — all neumorphic surfaces share this exact warm
  /// taupe tone. Never pure white so both highlight and shadow read clearly.
  static const Color base = Color(0xFFE6DDD0);

  /// Primary camel accent — CTA gradient base, focus rings, active states.
  static const Color accent = Color(0xFFB89A7A);

  /// Deeper mocha — dark end of the CTA gradient and pressed accents.
  static const Color accentDeep = Color(0xFF6A4A28);

  /// Latte mid-tone — light end of the CTA gradient.
  static const Color accentLatte = Color(0xFF8A6840);

  /// Slightly lifted camel — logo mark only.
  static const Color accentLogo = Color(0xFFC4A988);

  /// Primary text — warm espresso brown, ~7:1 on [base], WCAG AA+.
  static const Color text = Color(0xFF4A3322);

  /// Secondary / body-supporting text (warm coffee brown).
  static const Color textSecondary = Color(0xFF6E5743);

  /// Muted labels (field labels). Use at >= 12 px bold.
  static const Color muted = Color(0xFF9A8367);

  /// De-emphasized calendar-weekend text (Sat/Sun captions + day numbers).
  ///
  /// mobile-security MEDIUM (calendar-consolidation audit): [muted] measures
  /// only 2.69:1 on [base] — well under WCAG AA's 4.5:1 floor for normal
  /// text — so it cannot legally carry the weekend cue, which the D3 fix
  /// (see `shared/widgets/calendar_grid.dart`) applies to ACTIVE, tappable
  /// day-number and caption text.
  ///
  /// mobile-security LOW (re-audit, same fix): a FIRST pass at this token
  /// (`#745C47`) searched the wrong axis. Against a light base the *lighter*
  /// a warm-neutral tone gets the *lower* its contrast falls, so "more
  /// de-emphasized" and "still >= 4.5:1" pull in opposite directions on the
  /// `muted` → [textSecondary] LIGHTNESS axis — the legal band between the
  /// AA floor and [textSecondary]'s own 5.03:1 is a sliver, and `#745C47`
  /// sat right at its edge: CIE Lab ΔE76 versus [textSecondary] was only
  /// ~2.2, essentially at the ~2.3 just-noticeable-difference threshold, so
  /// the weekend cue the user actually asked for ("put these columns into
  /// gray colour") was very likely invisible in practice even though it
  /// cleared AA on paper.
  ///
  /// The fix moves to the HUE/CHROMA axis instead: [weekendMuted] is
  /// [textSecondary]'s warm-neutral RGB desaturated toward true gray, at the
  /// same darkness (never lighter — darkness is free contrast on a light
  /// base, so de-emphasis has to come from dropping chroma, not from washing
  /// out). `#5F5A55` measures 5.07:1 on [base] — a wider AA margin than
  /// [textSecondary]'s own 5.03:1, since it is no lighter — while sitting a
  /// CIE Lab ΔE76 of ~12.8 away from [textSecondary] (comfortably clear of
  /// the ~2.3 JND floor), and its own tiny residual warm cast (Lab a≈+1,
  /// b≈+3.6, versus [textSecondary]'s a≈+6.4, b≈+15.2) keeps it inside this
  /// palette's warm-neutral family rather than reading as a cold blue-gray.
  /// See `test/shared/widgets/calendar_grid_contrast_test.dart` for the
  /// computed pin on both properties.
  ///
  /// Deliberately NOT a widening of [muted] itself: [muted] stays reserved
  /// for genuinely inactive/disabled states, where WCAG 1.4.3's "inactive
  /// user interface component" exemption is what makes the low contrast
  /// legal in the first place (see call sites' own comments for the
  /// per-state exemption determination) — a day that is merely a *weekend*
  /// is not inactive, so it needs a token that is legal on its own, not an
  /// exemption.
  static const Color weekendMuted = Color(0xFF5F5A55);

  /// Column-spanning tint behind Saturday/Sunday in the master's expanded
  /// «Мої записи» month calendar (`BookingsMonthCalendarPanel`, via
  /// `MonthCalendar.showWeekendColumnBand`) — the weekend cue moved from the
  /// day NUMBER (see [weekendMuted]'s D3 history) to the whole column, per
  /// explicit user request ("put whole weekend columns into grey / other
  /// colour ... not grey day numbers"): inside the band the day numbers now
  /// render at the same colour as any other day ([accentDeep]/[textSecondary]/
  /// [faint], never [weekendMuted]) — the band alone carries the signal.
  ///
  /// SECOND DERIVATION (2026-08-15, explicit user request: "change the
  /// weekend column fill color into light grey") — the hue/chroma-shifted
  /// warm-sand value this token originally held (`#F0DBC0`) was correct on
  /// its own terms (see the retained history below) but was never grey, so
  /// it stopped matching the ask outright. Grey means near-zero CIE Lab
  /// chroma (a≈0, b≈0), which rules out the old "shift [base]'s hue/chroma
  /// toward [shadowDarkCard]" recipe entirely — that recipe's whole point
  /// was to STAY warm. This value is instead a pure neutral: `#E8E8E8`, Lab
  /// (L≈92.00, a≈0.00, b≈0.00).
  ///
  /// The neutral axis turned out to have a floor a naive "desaturate [base]
  /// in place" reading misses: holding L AT [base]'s own L≈88.49 while
  /// dropping a/b to 0 gives ΔE76 vs [base] of only ~7.52 — [base]'s own
  /// residual chroma (a≈0.87, b≈7.47) is almost the entire distance being
  /// measured, so sitting at the same lightness fails this codebase's own
  /// >= 8.0 perceptibility bar (see `_kMinPerceptibleDeltaE` in
  /// `test/shared/widgets/calendar_grid_contrast_test.dart`) by removing the
  /// one component (chroma) that theory relies on to create distance, while
  /// contributing nothing back on the L axis. Neutral grey NEEDS a lightness
  /// offset from [base] to clear ΔE 8 — there is no shortcut around it.
  ///
  /// That offset could go darker or lighter; darker was tried first and
  /// rejected. A darker neutral grey clearing ΔE >= 8 (L <~85.75, e.g.
  /// `#D4D4D4`/`#D6D6D6`) DROPS contrast for every dark foreground that
  /// lands on the band, because WCAG contrast against a light background
  /// rises with the background's OWN luminance — darkening the band erodes
  /// exactly the margin the foregrounds need. At `#D6D6D6` [textSecondary]
  /// measures ~4.65:1 and [weekendMuted] ~4.69:1: both still clear AA's
  /// 4.5:1, but by a sliver thin enough that any future foreground or token
  /// tweak could tip one under. Going LIGHTER than [base] instead makes both
  /// numbers move the same direction: distance from [base] and contrast
  /// margin both increase together, because a lighter background is both
  /// further from [base] on the L axis (more ΔE) and further from the dark
  /// foregrounds (more contrast) at once — no trade-off to balance. `#E8E8E8`
  /// sits on that side, L≈92.00 versus [base]'s L≈88.49 — only ~3.5 lighter,
  /// which is why it still reads as a subtle wash rather than a highlight,
  /// while comfortably clearing both bars (measured below).
  ///
  /// A residual-warm-chroma variant (mirroring how [weekendMuted] keeps a
  /// trace of its own hue) was also tried and rejected for the opposite
  /// reason to the darker-grey path: at this same L, giving the grey back
  /// even ~2 units of [base]'s own b (its warm axis) pulls it BACK toward
  /// [base] in Lab space and measurably shrinks ΔE76 (e.g. L≈91.3 with
  /// a≈-0.03/b≈2.18 measures ΔE76≈6.08 versus the pure-neutral ΔE76≈8.30 at
  /// the same L) — because [base] itself already sits on the warm axis, any
  /// warmth added back to the "grey" moves it toward [base], not away from
  /// it. Unlike [weekendMuted] (whose neighbour, [textSecondary], is ALSO
  /// warm, so a shared residual hue does not cost distance), [weekendColumn]
  /// is being measured against [base] itself — so here, staying perfectly
  /// neutral is what maximises both the "reads as grey" property the user
  /// asked for AND the measured distance. `#E8E8E8` is therefore exactly
  /// neutral (a=0, b=0), not warm-tinted.
  ///
  /// Measured (see `test/shared/widgets/calendar_grid_contrast_test.dart`):
  /// CIE Lab ΔE76 vs [base] = **8.30** (clears the >= 8.0 floor with real
  /// margin, not sitting on the edge like the rejected darker options).
  /// Contrast on the band: [accentDeep] **6.53:1**, [textSecondary]
  /// **5.52:1**, [weekendMuted] **5.56:1** — all clear WCAG AA's 4.5:1 floor
  /// by more than a full point of headroom.
  ///
  /// Retained history (still true, from the first derivation): a pure
  /// alpha-blend toward [shadowDarkCard] was rejected because it DARKENS as
  /// well as tints, so contrast against dark text erodes with every step
  /// toward a visible band — the lesson generalises to this derivation too
  /// (it is exactly why the darker-neutral option above was also rejected).
  /// The weekend cue lives on the whole COLUMN, not the day number, per the
  /// same user request recorded on [MonthCalendar.showWeekendColumnBand]'s
  /// call site — inside the band the day numbers keep rendering
  /// [accentDeep]/[textSecondary]/[faint] like any other day; the band alone
  /// carries the signal.
  static const Color weekendColumn = Color(0xFFE8E8E8);

  /// Input placeholder text.
  static const Color placeholder = Color(0xFFAD9A82);

  /// Faint hairlines / disabled glyphs.
  static const Color faint = Color(0xFFBCAB95);

  /// Cream — text/glyphs that sit on the camel/mocha CTA fill.
  static const Color white = Color(0xFFF5EDE0);

  // ---------------------------------------------------------------------------
  // Neumorphic shadow tones (on the warm-taupe base)
  // ---------------------------------------------------------------------------

  /// Warm highlight — top-left lift. Creamy near-white, stays warm family.
  static const Color shadowLightStrong = Color(0xFFFFFBF4);

  /// Warm taupe-brown card shadow — bottom-right recess.
  static const Color shadowDarkCard = Color(0xFFC4B49E);

  /// Warm taupe-brown button shadow — slightly deeper than the card.
  static const Color shadowDarkButton = Color(0xFFC0AF98);

  // ---------------------------------------------------------------------------
  // Semantic feedback (both >=4.5:1 on [base]; always paired with icon+text)
  // ---------------------------------------------------------------------------

  /// Error state — validation failures, cancellation.
  static const Color error = Color(0xFFB0452F);

  /// Success state — positive confirmation.
  static const Color success = Color(0xFF5C7A4A);

  /// Material 3 seed — used for [ColorScheme.fromSeed].
  static const Color seed = accentDeep;
}

/// A small, fixed palette of two-colour gradients for client-avatar circles
/// (`MasterBookingCard`'s `_ClientAvatar`, transcribed from the design's
/// `_ClientAvatar` at `booking_widgets.dart:295-331`). Every pair is drawn
/// from hues already in [BrandColors] so a client's avatar can never drift
/// outside the locked VelvetTouch palette — see [forKey] for how a client
/// maps onto one.
abstract final class ClientAvatarGradients {
  static const List<List<Color>> _palette = <List<Color>>[
    <Color>[BrandColors.accentLogo, BrandColors.accentDeep],
    <Color>[BrandColors.accent, BrandColors.accentLatte],
    <Color>[BrandColors.placeholder, BrandColors.textSecondary],
    <Color>[BrandColors.faint, BrandColors.muted],
    <Color>[BrandColors.accentLatte, BrandColors.text],
    <Color>[BrandColors.accent, BrandColors.accentDeep],
  ];

  /// mobile-perf MEDIUM-2 (Phase 7.10 timeline audit): memoizes [forKey]'s
  /// rolling-hash walk. `MasterBookingCard` now calls [forKey] once per card
  /// lifetime (see its `_MasterBookingCardState._avatarGradient`), but this
  /// cache stays as a second line of defence for any other caller that
  /// re-resolves the same client key across many rebuilds (e.g. a scrolling
  /// list that doesn't hold a stable `State`) — bounded by [_kMaxCachedKeys],
  /// never by rebuild count.
  ///
  /// Ceiling on distinct memoized keys (mobile-perf LOW-6, 2026-07-20): the
  /// map above previously grew for the whole process lifetime, one entry per
  /// distinct client key any caller ever resolved — in practice small (a
  /// master's own client roster) but with no enforced bound. High enough that
  /// a realistic session's client list never evicts a genuinely revisited
  /// key. A `LinkedHashMap` iterates in insertion order, so [forKey] below
  /// always evicts the OLDEST entry once the cap is exceeded — a simpler
  /// cap-and-evict than `DayKeepAliveLru`'s (`bookings_day_notifier.dart`)
  /// `KeepAliveLink` bookkeeping, which this doesn't need: nothing here holds
  /// a Riverpod disposal handle, only a plain memory ceiling.
  static const int _kMaxCachedKeys = 500;

  /// Test-only mirror of [_kMaxCachedKeys] — lets the eviction regression
  /// test assert against the real cap instead of a second hard-coded copy of
  /// the number that could silently drift out of sync with it.
  @visibleForTesting
  static const int debugMaxCachedKeys = _kMaxCachedKeys;

  /// Test-only window onto [_kMaxCachedKeys] — the eviction regression test
  /// (`client_avatar_gradients_test.dart`) needs to assert the cache actually
  /// stays bounded, which is unobservable from outside this library any
  /// other way: [_palette] entries are themselves fixed `const` object
  /// references, so evicting and recomputing a key yields an
  /// `identical`-equal result either way — the cap can silently regress to
  /// "unbounded" without any value-level assertion ever failing.
  @visibleForTesting
  static int get debugCacheLength => _cache.length;

  static final LinkedHashMap<String, List<Color>> _cache =
      LinkedHashMap<String, List<Color>>();

  /// Deterministically maps [key] — a stable client identity, e.g.
  /// `booking.clientId`, falling back to the client's display name (or, for a
  /// nameless guest booking, the booking id) when no account id exists — onto
  /// one of [_palette]'s gradients. Same key, same gradient, every time.
  ///
  /// Hashed with a plain polynomial rolling hash over [key]'s UTF-16 code
  /// units rather than Dart's own `String.hashCode`: the language spec does
  /// NOT guarantee `hashCode` is stable across process runs, so relying on it
  /// here would risk a client's avatar gradient silently changing between app
  /// opens — defeating the whole point of a deterministic mapping. The
  /// `& 0x7fffffff` mask keeps every intermediate value a non-negative
  /// fixed-width int on every compile target (VM, JS, Wasm).
  static List<Color> forKey(String key) {
    final List<Color>? cached = _cache[key];
    if (cached != null) return cached;
    int hash = 0;
    for (final int unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final List<Color> resolved = _palette[hash % _palette.length];
    // Bound the cache (mobile-perf LOW-6) before inserting the new entry —
    // `LinkedHashMap.keys.first` is the OLDEST insertion once every hit above
    // already short-circuited without touching insertion order.
    if (_cache.length >= _kMaxCachedKeys) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = resolved;
    return resolved;
  }
}
