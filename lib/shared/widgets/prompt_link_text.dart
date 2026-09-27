// PromptLinkText — "prompt + tappable link" line, baseline-aligned.
//
// Shared by every auth "prompt, then link" row (login «Немає акаунту?
// Зареєструватись», the OTP «Не отримали код? Надіслати знову» row). Both
// used to lay the two parts out as sibling boxes (a top-aligned Wrap on login,
// a centre-aligned Row in OtpResendRow). Because VelvetText.body() carries
// `height: 1.5` (18 px line box) and VelvetText.link() carries none (~15 px),
// box alignment never lands the two on the same baseline: the link sat
// ~1.5 px high on login and ~0.5 px high on the OTP row, and the Row also
// overflowed at 320 dp / 1.3× during the countdown.
//
// Here the prompt and link are ONE paragraph: the link rides in a
// WidgetSpan with PlaceholderAlignment.baseline, so both share the alphabetic
// baseline, and the paragraph reflows onto a second line at narrow widths /
// large text scale instead of overflowing. The link stays its own widget so it
// keeps its test key and its own (nullable = disabled) tap target.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// [prompt] in [VelvetText.body] followed by a tappable [linkLabel], sharing
/// one alphabetic baseline and wrapping as a single paragraph.
///
/// [linkKey] is applied to the link's [GestureDetector] — tests find and tap
/// the link through it. A `null` [onTap] disables the link (no tap handler);
/// callers convey the disabled look through [linkStyle].
class PromptLinkText extends StatelessWidget {
  const PromptLinkText({
    super.key,
    required this.prompt,
    required this.linkLabel,
    required this.linkKey,
    required this.onTap,
    this.linkStyle,
  });

  /// Leading prompt (e.g. «Немає акаунту?»).
  final String prompt;

  /// Link label (e.g. «Зареєструватись», or a live countdown).
  final String linkLabel;

  /// Key on the link's [GestureDetector].
  final Key linkKey;

  /// Tap handler; `null` disables the link.
  final VoidCallback? onTap;

  /// Link style; defaults to [VelvetText.link].
  final TextStyle? linkStyle;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = linkStyle ?? VelvetText.link();
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: prompt, style: VelvetText.body()),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            // Sizes RichText's auto-scale factor off the link's own font size
            // (matters under Android's non-linear text scaling).
            style: style,
            child: GestureDetector(
              key: linkKey,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.only(left: VelvetSpacing.xs),
                // RichText already scales a WidgetSpan child by the ambient
                // text scale (a transform); letting this Text scale too would
                // apply it twice (1.3× → 1.69×).
                child: Text(
                  linkLabel,
                  style: style,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
