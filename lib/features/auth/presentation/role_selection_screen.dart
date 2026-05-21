// Phase 2.16 — Role selection screen (wizard entry gate).
//
// SOURCE OF TRUTH: docs/signup-designs/role-selection-page.html. The user
// picks one of three roles (Client / Salon Owner / Independent Master); the
// choice is written into `registerDraftProvider` via [start] and the wizard
// advances to `/register` (Step 1 — credentials).
//
// This screen is OUTSIDE the wizard ShellRoute — it has its own brand row +
// hero headline + login link, and does NOT show the 4-pill progress (the
// role-selection isn't one of the four pills; the pills only appear once
// the user is inside the wizard).
//
// Previously this view lived inside the monolithic register_screen.dart
// alongside the credentials form. Phase 2.16 splits the file: role-selection
// stays here, and credentials moves to `register_step_1_screen.dart`.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'auth_role_icons.dart';

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values, allocated once.
// ---------------------------------------------------------------------------

const _kRoleCardRadius = BorderRadius.all(Radius.circular(18));
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
  stops: [0.0, 0.6, 1.0],
);

const _kCtaShadow = [
  BoxShadow(color: Color(0x5B3A240C), blurRadius: 16, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x1FFFFFFF), blurRadius: 0, offset: Offset(0, -1)),
];

const _kCtaDecoration = BoxDecoration(
  gradient: _kCtaGradient,
  borderRadius: _kCtaRadius,
  boxShadow: _kCtaShadow,
);

const _kCtaTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.3,
);

const _kLoginPromptStyle = TextStyle(color: Color(0x4DFFFFFF), fontSize: 15);

const _kMonogramDecoration = BoxDecoration(
  color: Color(0x1AFFFFFF),
  borderRadius: BorderRadius.all(Radius.circular(10)),
  border: Border.fromBorderSide(BorderSide(color: Color(0x33FFFFFF), width: 1)),
);

// ---------------------------------------------------------------------------
// _IntentOption data class
// ---------------------------------------------------------------------------

class _IntentOption {
  const _IntentOption({required this.role, required this.glyph});

  final UserRole role;
  final AuthRoleGlyph glyph;
}

const List<_IntentOption> _kIntentOptions = [
  _IntentOption(role: UserRole.client, glyph: AuthRoleGlyph.client),
  _IntentOption(role: UserRole.salonOwner, glyph: AuthRoleGlyph.salonOwner),
  _IntentOption(
    role: UserRole.independentMaster,
    glyph: AuthRoleGlyph.independentMaster,
  ),
];

String _intentTitle(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentTitle,
      UserRole.salonOwner => l10n.intentSalonTitle,
      UserRole.client => l10n.intentClientTitle,
      _ => '',
    };

String _intentDesc(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentDesc,
      UserRole.salonOwner => l10n.intentSalonDesc,
      UserRole.client => l10n.intentClientDesc,
      _ => '',
    };

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  UserRole? _selectedRole;
  bool _ctaPressed = false;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }
    // Preselect the role from the draft when the user returns here via the
    // Step 1 "← Назад" link (the draft survives a single-step back). On a
    // fresh entry the draft is null, so _selectedRole stays null and Continue
    // stays disabled until the user picks.
    _selectedRole = ref.read(registerDraftProvider)?.role;
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    super.dispose();
  }

  void _selectRole(UserRole role) {
    setState(() => _selectedRole = role);
    if (kDebugMode) {
      log('Role selected: ${role.toWire}', name: 'auth.role', level: 800);
    }
  }

  void _continue() {
    final role = _selectedRole;
    if (role == null) return;
    ref.read(registerDraftProvider.notifier).start(role);
    context.go(RouteNames.register);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const _RoleBrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          _HeadlineBlock(l10n: l10n),
          const SizedBox(height: 20),
          _RoleSelectionField(
            key: const Key('field-role'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoleCard(
                  option: _kIntentOptions[0],
                  isSelected: _selectedRole == _kIntentOptions[0].role,
                  onTap: () => _selectRole(_kIntentOptions[0].role),
                  l10n: l10n,
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  option: _kIntentOptions[1],
                  isSelected: _selectedRole == _kIntentOptions[1].role,
                  onTap: () => _selectRole(_kIntentOptions[1].role),
                  l10n: l10n,
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  option: _kIntentOptions[2],
                  isSelected: _selectedRole == _kIntentOptions[2].role,
                  onTap: () => _selectRole(_kIntentOptions[2].role),
                  l10n: l10n,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _MochaCtaButton(
            buttonKey: const Key('btn-continue-role'),
            label: l10n.registerContinue,
            onPressed: _selectedRole != null ? _continue : null,
            onTapDown: () => setState(() => _ctaPressed = true),
            onTapUp: () => setState(() => _ctaPressed = false),
            onTapCancel: () => setState(() => _ctaPressed = false),
            isPressed: _ctaPressed,
          ),
          const SizedBox(height: 20),
          _LoginLinkRow(
            l10n: l10n,
            onTap: () {
              // Security (Phase 2.16 HIGH-1 / MEDIUM-security-1) — clear any
              // in-flight draft (e.g. the user came here from Step 1 via the
              // back link). The wizard hasn't filled credentials yet on this
              // screen, but the role choice itself is part of the draft and
              // must not survive a "let me log in instead" detour.
              ref.read(registerDraftProvider.notifier).reset();
              // Navigate unconditionally to login — never pop() back into the
              // wizard. Consistent with Step 1's login link.
              context.go(RouteNames.login);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleSelectionField — keyed wrapper (parity directive)
// ---------------------------------------------------------------------------

class _RoleSelectionField extends StatelessWidget {
  const _RoleSelectionField({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// ---------------------------------------------------------------------------
// _RoleCard
// ---------------------------------------------------------------------------

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.l10n,
  });

  final _IntentOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  // ── Pre-allocated decorations (MEDIUM-perf-2 HOIST) ────────────────────
  //
  // Each card animates over a 200 ms tween (~12 frames). Allocating two
  // `BoxDecoration` + two `Border.all` per build × 3 cards × 12 frames =
  // ~144 throwaway allocations per selection toggle. Hoisting them to
  // const top-level fields collapses that to zero allocations.

  /// Outer card surface — selected (camel-tinted fill + camel border).
  static const _kCardDecorSelected = BoxDecoration(
    color: Color(0x14B89A7A),
    borderRadius: _kRoleCardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x6BB89A7A), width: 1),
    ),
  );

  /// Outer card surface — unselected (white-8% fill + faint white border).
  static const _kCardDecorUnselected = BoxDecoration(
    color: Color(0x0EFFFFFF),
    borderRadius: _kRoleCardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x14FFFFFF), width: 1),
    ),
  );

  /// Inner glyph badge — selected.
  static const _kGlyphDecorSelected = BoxDecoration(
    color: Color(0x24B89A7A),
    borderRadius: BorderRadius.all(Radius.circular(13)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x59B89A7A), width: 1),
    ),
  );

  /// Inner glyph badge — unselected.
  static const _kGlyphDecorUnselected = BoxDecoration(
    color: Color(0x12FFFFFF),
    borderRadius: BorderRadius.all(Radius.circular(13)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1),
    ),
  );

  /// Trailing radio dot — selected (camel fill + camel border).
  static const _kRadioDecorSelected = BoxDecoration(
    color: BrandColors.camel,
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: BrandColors.camel, width: 1.5),
    ),
  );

  /// Trailing radio dot — unselected (transparent fill + faint border).
  static const _kRadioDecorUnselected = BoxDecoration(
    color: Colors.transparent,
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x26FFFFFF), width: 1.5),
    ),
  );

  // Text colors (single Color allocations, no decoration cost).
  static const _kTitleColorSelected = Colors.white;
  static const _kTitleColorUnselected = Color(0xE0FFFFFF);
  static const _kDescColorSelected = Color(0x6BFFFFFF);
  static const _kDescColorUnselected = Color(0x47FFFFFF);
  static const _kGlyphColorUnselected = Color(0x73FFFFFF);

  static const _kTitleBaseStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.14,
  );

  static const _kDescStyleBase = TextStyle(fontSize: 13.5, height: 1.45);

  static const _kCheckIcon = Icon(
    Icons.check,
    size: 12,
    color: Color(0xFF3A2810),
  );

  static const _kAnimDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final cardDecor = isSelected ? _kCardDecorSelected : _kCardDecorUnselected;
    final glyphDecor = isSelected
        ? _kGlyphDecorSelected
        : _kGlyphDecorUnselected;
    final radioDecor = isSelected
        ? _kRadioDecorSelected
        : _kRadioDecorUnselected;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${_intentTitle(option, l10n)}. ${_intentDesc(option, l10n)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: _kRoleCardRadius,
          child: AnimatedContainer(
            duration: _kAnimDuration,
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: cardDecor,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: _kAnimDuration,
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: glyphDecor,
                  child: AuthRoleIcon(
                    glyph: option.glyph,
                    color: isSelected
                        ? BrandColors.camel
                        : _kGlyphColorUnselected,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: _kAnimDuration,
                        style: _kTitleBaseStyle.copyWith(
                          color: isSelected
                              ? _kTitleColorSelected
                              : _kTitleColorUnselected,
                        ),
                        child: Text(_intentTitle(option, l10n)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _intentDesc(option, l10n),
                        style: _kDescStyleBase.copyWith(
                          color: isSelected
                              ? _kDescColorSelected
                              : _kDescColorUnselected,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedContainer(
                  duration: _kAnimDuration,
                  width: 22,
                  height: 22,
                  decoration: radioDecor,
                  child: isSelected ? _kCheckIcon : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MochaCtaButton — same DecoratedBox→ClipRRect→Material→InkWell pattern
// ---------------------------------------------------------------------------

class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.isPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      child: AnimatedScale(
        scale: isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: DecoratedBox(
          decoration: _kCtaDecoration,
          child: ClipRRect(
            borderRadius: _kCtaRadius,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                splashColor: const Color(0x14FFFFFF),
                highlightColor: const Color(0x0AFFFFFF),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Align(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(label, style: _kCtaTextStyle),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleBrandRow — monogram B + BEAUTICA
// ---------------------------------------------------------------------------

class _RoleBrandRow extends StatelessWidget {
  const _RoleBrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            child: DecoratedBox(
              decoration: _kMonogramDecoration,
              child: Center(
                child: Text(
                  // ignore: no_raw_ui_strings
                  // Single-letter brand monogram — exempt from l10n per
                  // mobile-backlog known-issue pattern §5.
                  'B',
                  style: TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: AppSpacing.xs),
        Text(
          // ignore: no_raw_ui_strings
          // Brand wordmark — exempt from l10n per mobile-backlog §5.
          'BEAUTICA',
          style: TextStyle(
            color: Color(0xEBFFFFFF),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _HeadlineBlock — role-selection headline (.headline + .sub-text)
// ---------------------------------------------------------------------------

class _HeadlineBlock extends StatelessWidget {
  const _HeadlineBlock({required this.l10n});

  final AppLocalizations l10n;

  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 34,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
      height: 1.22,
    ),
  );

  static final _kSubTextStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Color(0x59FFFFFF),
      fontSize: 15,
      height: 1.55,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: '${l10n.registerHeadline}\n',
            style: _kHeadlineStyle,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Text(l10n.registerHeadlineAccent, style: _kAccentStyle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(l10n.registerSubText, style: _kSubTextStyle),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _LoginLinkRow
// ---------------------------------------------------------------------------

class _LoginLinkRow extends StatelessWidget {
  const _LoginLinkRow({required this.l10n, required this.onTap});

  final AppLocalizations l10n;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l10n.registerHaveAccount, style: _kLoginPromptStyle),
        TextButton(
          key: const Key('btn-go-to-login-from-intent'),
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            disabledForegroundColor: BrandColors.camel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          child: Text(l10n.registerSignIn),
        ),
      ],
    );
  }
}
