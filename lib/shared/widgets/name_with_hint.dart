// Phase 469 — a one-line service name with an optional « · {hint}» suffix.
//
// Shared by `ServiceInfo` (services list card, `service_category_list.dart`)
// so the hint layout lives in one place.
//
// Phase 470 — also the client booking surfaces (catalogue tile, salon
// accordion row, selected-services shelf, booking recap). Additive params
// only: [nameKey] keeps a caller's existing test key on the name `Text`, and
// [singleLine] `false` reproduces the recap's wrapping name line.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Unicode First Strong Isolate / Pop Directional Isolate. The name and the
/// hint are both owner-supplied, so each is bidi-isolated wherever they share
/// one paragraph — a stray RTL mark in either can never reorder the other.
/// (In single-line mode the name and hint are separate `Text` paragraphs, so
/// the name is already isolated by construction and stays a plain string.)
const String _fsi = '\u2068';
const String _pdi = '\u2069';

/// A service name. With a non-null [hint] it appends « · {hint}» in
/// [hintStyle]. In single-line mode the hint is laid out FIRST (an inflexible
/// `Row` child) at its natural width capped at [_hintMaxFraction] of the row;
/// the name takes what is left. Both ellipsize instead of overflowing.
///
/// With [hint] `null` it is exactly one `Text(name, maxLines: 1, ellipsis)`
/// (or, with [singleLine] `false`, one plain wrapping `Text(name)`).
///
/// Single-line mode with a hint builds a [LayoutBuilder], so it must NOT sit
/// under an [IntrinsicHeight] / [IntrinsicWidth] (or anything else that asks
/// for intrinsic dimensions) — `LayoutBuilder` cannot report them and throws.
class NameWithHint extends StatelessWidget {
  const NameWithHint({
    super.key,
    required this.name,
    required this.nameStyle,
    this.hint,
    this.hintStyle,
    this.nameKey,
    this.singleLine = true,
  });

  final String name;
  final TextStyle nameStyle;
  final String? hint;

  /// Falls back to [nameStyle] when `null`.
  final TextStyle? hintStyle;

  /// Key for the name `Text` itself (callers that measure / read it).
  final Key? nameKey;

  /// `true` (default): one ellipsizing line. `false`: the name wraps freely
  /// and the hint flows inline after it as one rich paragraph.
  final bool singleLine;

  static const double _hintMaxFraction = 0.5;

  /// [text] wrapped in FSI … PDI — exactly the text the suffix interpolates
  /// (and, in wrapping mode, the name before it).
  static String isolate(String text) => '$_fsi$text$_pdi';

  @override
  Widget build(BuildContext context) {
    final String? h = hint;
    final bool hasHint = h != null && h.isNotEmpty;
    final String? suffix = hasHint
        ? AppLocalizations.of(context).serviceNameHintSuffix(isolate(h))
        : null;
    if (!singleLine) {
      if (suffix == null) return Text(name, key: nameKey, style: nameStyle);
      return Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: isolate(name)),
            TextSpan(text: suffix, style: hintStyle ?? nameStyle),
          ],
        ),
        key: nameKey,
        style: nameStyle,
      );
    }
    final Text nameText = Text(
      name,
      key: nameKey,
      style: nameStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (suffix == null) return nameText;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Row(
          children: <Widget>[
            Flexible(child: nameText),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _hintMaxFraction,
              ),
              child: Text(
                suffix,
                key: const Key('service-name-hint'),
                style: hintStyle ?? nameStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
