// Phase 469 — a one-line service name with an optional « · {hint}» suffix.
//
// Shared by `ServiceInfo` (services list card) and `ServiceTile` (master
// profile) so the hint layout lives in one place.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// A single-line name. With a non-null [hint] it appends « · {hint}» in
/// [hintStyle]; the name keeps priority and the hint is capped at
/// [_hintMaxFraction] of the row so both ellipsize instead of overflowing.
///
/// With [hint] `null` it is exactly one `Text(name, maxLines: 1, ellipsis)`.
class NameWithHint extends StatelessWidget {
  const NameWithHint({
    super.key,
    required this.name,
    required this.nameStyle,
    this.hint,
    this.hintStyle,
  });

  final String name;
  final TextStyle nameStyle;
  final String? hint;

  /// Falls back to [nameStyle] when `null`.
  final TextStyle? hintStyle;

  static const double _hintMaxFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    final Text nameText = Text(
      name,
      style: nameStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final String? h = hint;
    if (h == null || h.isEmpty) return nameText;
    final String suffix = AppLocalizations.of(context).serviceNameHintSuffix(h);
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
