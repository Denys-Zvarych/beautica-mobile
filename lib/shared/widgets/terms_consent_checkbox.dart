// Phase 443 — required terms + privacy consent checkbox (Google Play UGC).
//
// PROMOTED (REUSE-FIRST), not copied: the rich-text line, its two
// [TapGestureRecognizer]s and `_openLegal` used to live inside
// `register_step_1_screen.dart` (`step1_terms_line`). They now live here and
// both sign-up surfaces use this one widget:
//   - lib/features/auth/presentation/register_step_1_screen.dart
//   - lib/features/auth/presentation/accept_invite_screen.dart
//
// One tick covers both documents (D1). The whole row is a >= 48 dp tap target
// that toggles the box; the two inline links open the public website's legal
// pages externally and do NOT toggle (the innermost span recognizer wins the
// gesture arena over the row's tap).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/velvet_geometry.dart';
import '../../core/theme/velvet_text.dart';
import '../../l10n/app_localizations.dart';
import '../utils/open_external_uri.dart';
import '../utils/public_web_links.dart';

/// Minimum tap-target extent of the consent row (Material a11y guideline).
const double _kMinTapTarget = 48;

/// Corner radius of the checkbox glyph — soft, matching the rounded
/// VelvetTouch field/button language at checkbox scale.
const double _kBoxRadius = 6;

/// Required «Я приймаю Умови використання та Політику конфіденційності»
/// checkbox shown before account creation.
///
/// [idPrefix] namespaces the inner keys / semantics identifiers so each host
/// screen keeps stable test hooks:
///   `<idPrefix>_terms_checkbox`, `<idPrefix>_terms_row`,
///   `<idPrefix>_terms_line`, `<idPrefix>_terms_link`,
///   `<idPrefix>_privacy_link`.
class TermsConsentCheckbox extends StatefulWidget {
  const TermsConsentCheckbox({
    required this.value,
    required this.onChanged,
    this.idPrefix = 'terms_consent',
    this.enabled = true,
    super.key,
  });

  /// Whether the consent is currently ticked.
  final bool value;

  /// Called with the new value when the user toggles the box or the row.
  final ValueChanged<bool> onChanged;

  /// Prefix for inner keys and semantics identifiers (see class doc).
  final String idPrefix;

  /// When `false` the box cannot be toggled (e.g. while a submit is in
  /// flight). The links stay tappable.
  final bool enabled;

  @override
  State<TermsConsentCheckbox> createState() => _TermsConsentCheckboxState();
}

class _TermsConsentCheckboxState extends State<TermsConsentCheckbox> {
  // Created once with the State (never in build) and disposed in [dispose].
  final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer();
  final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _termsRecognizer.onTap = () => _openLegal(PublicWebLinks.terms);
    _privacyRecognizer.onTap = () => _openLegal(PublicWebLinks.privacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  void _openLegal(Uri uri) {
    openExternalUri(
      context,
      uri,
      errorMessage: AppLocalizations.of(context).externalLinkOpenError,
      logName: 'shared.terms_consent',
    );
  }

  void _toggle() {
    if (!widget.enabled) return;
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String p = widget.idPrefix;

    return GestureDetector(
      key: ValueKey<String>('${p}_terms_row'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _toggle : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kMinTapTarget),
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: _kMinTapTarget,
              child: Checkbox(
                key: ValueKey<String>('${p}_terms_checkbox'),
                value: widget.value,
                onChanged: widget.enabled
                    ? (bool? v) => widget.onChanged(v ?? false)
                    : null,
                semanticLabel: l10n.termsConsentCheckboxLabel,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                activeColor: BrandColors.accent,
                checkColor: BrandColors.accentDeep,
                fillColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) =>
                      states.contains(WidgetState.selected)
                      ? BrandColors.accent
                      : Colors.transparent,
                ),
                side: WidgetStateBorderSide.resolveWith(
                  (Set<WidgetState> states) => BorderSide(
                    color: states.contains(WidgetState.selected)
                        ? BrandColors.accent
                        : BrandColors.accentDeep,
                    width: 1.5,
                  ),
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(_kBoxRadius)),
                ),
              ),
            ),
            const SizedBox(width: VelvetSpacing.xs),
            Expanded(
              child: Text.rich(
                key: ValueKey<String>('${p}_terms_line'),
                TextSpan(
                  style: VelvetText.feedback(BrandColors.muted),
                  children: <InlineSpan>[
                    TextSpan(text: l10n.registerTermsPrefix),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: l10n.registerTermsTerms,
                      style: VelvetText.linkSmall,
                      recognizer: _termsRecognizer,
                      semanticsIdentifier: '${p}_terms_link',
                    ),
                    TextSpan(text: l10n.registerTermsConjunction),
                    TextSpan(
                      text: l10n.registerTermsPrivacy,
                      style: VelvetText.linkSmall,
                      recognizer: _privacyRecognizer,
                      semanticsIdentifier: '${p}_privacy_link',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
