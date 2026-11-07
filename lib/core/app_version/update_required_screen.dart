// Phase 438 — «Оновіть додаток», the full-screen forced-update gate.
//
// Ported literally from the approved preview
// `docs/signup-designs/UpdateRequired/lib/screens/update_required_screen.dart`.
// Swaps: preview tokens → production `BrandColors` / `VelvetText` /
// `VelvetSpacing`; the simulated 700 ms Play launch → [openStoreListing]
// (`market://` first, then the validated `play.google.com` URL); inline copy →
// `AppLocalizations`. The preview's gallery chip is preview chrome and is NOT
// ported.
//
// No app bar, no back, no bottom nav. The gate is mounted by
// [UpdateGateOverlay] in the `MaterialApp.router` builder, ABOVE the router's
// Navigator, so there is no route for `PopScope` to veto: system back is
// handled by this screen's [WidgetsBindingObserver.didPopRoute], which exits
// the app (`SystemNavigator.pop`, spec decision 4) and never reveals the app
// behind the gate. `PopScope(canPop: false)` stays as in the preview for the
// case the screen is ever hosted under a route.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../theme/brand_colors.dart';
import '../theme/velvet_geometry.dart';
import '../theme/velvet_text.dart';
import '../widgets/neumorphic.dart';
import 'store_link.dart';
import 'update_gate_provider.dart';
import 'update_mark.dart';

/// Returns [UpdateRequiredScreen] instead of [child] while
/// [updateGateProvider] is [UpdateGateRequired]; otherwise [child] unchanged.
///
/// Watches ONLY [updateGateProvider] — never the auth state and never the
/// router — so a verdict change rebuilds this subtree alone.
class UpdateGateOverlay extends ConsumerWidget {
  const UpdateGateOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(updateGateProvider)) {
      UpdateGateOk() => child,
      UpdateGateRequired(
        :final String packageName,
        :final String installedVersion,
        :final String storeUrl,
      ) =>
        UpdateRequiredScreen(
          packageName: packageName,
          installedVersion: installedVersion,
          storeUrl: storeUrl,
        ),
    };
  }
}

/// The blocking «Оновіть додаток» screen.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key = screenKey,
    required this.packageName,
    required this.installedVersion,
    required this.storeUrl,
    this.launcher = launchUrl,
  });

  static const Key screenKey = Key('update-required-screen');
  static const Key buttonKey = Key('update-required-button');
  static const Key playErrorKey = Key('update-required-play-error');
  static const Key installedVersionKey = Key(
    'update-required-installed-version',
  );

  /// The installed application id. Informational only: the `market://`
  /// target is the sanitized listing's id (see [openStoreListing]), never
  /// this — a staging build's id has no Play listing.
  final String packageName;

  /// The installed semver, shown under the CTA.
  final String installedVersion;

  /// The backend's listing URL — opened only if it passes
  /// [sanitizedStoreUri].
  final String storeUrl;

  /// `url_launcher`'s [launchUrl] in production.
  final StoreUrlLauncher launcher;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final CurvedAnimation _textIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _textSlide = Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(_textIn);
  bool _playError = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textIn.dispose();
    _intro.dispose();
    super.dispose();
  }

  /// System back on the gate exits the app (spec decision 4).
  @override
  Future<bool> didPopRoute() async {
    await SystemNavigator.pop();
    return true;
  }

  Future<void> _openPlay() async {
    setState(() {
      _opening = true;
      _playError = false;
    });
    final bool launched = await openStoreListing(
      storeUrl: widget.storeUrl,
      launcher: widget.launcher,
    );
    if (!mounted) return;
    setState(() {
      _opening = false;
      _playError = !launched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: BrandColors.base,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.lg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: <Widget>[
                            const Spacer(flex: 3),
                            const SizedBox(height: VelvetSpacing.lg),
                            UpdateMark(progress: _intro),
                            const SizedBox(height: VelvetSpacing.xl),
                            // dim-decorative: one-shot intro fade; rests at 1.
                            FadeTransition(
                              opacity: _textIn,
                              child: SlideTransition(
                                position: _textSlide,
                                child: Column(
                                  children: <Widget>[
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        l10n.updateRequiredTitle,
                                        textAlign: TextAlign.center,
                                        style: VelvetText.headingLg,
                                      ),
                                    ),
                                    const SizedBox(height: VelvetSpacing.md),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 300,
                                      ),
                                      child: Text(
                                        l10n.updateRequiredBody,
                                        textAlign: TextAlign.center,
                                        style: VelvetText.updateGateBody,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(flex: 4),
                            const SizedBox(height: VelvetSpacing.xl),
                            _PlayErrorNotice(
                              visible: _playError && !_opening,
                              text: l10n.updateRequiredPlayError,
                            ),
                            // dim-decorative: one-shot intro fade; rests at 1.
                            FadeTransition(
                              opacity: _textIn,
                              child: NeumorphicButton(
                                key: UpdateRequiredScreen.buttonKey,
                                label: l10n.updateRequiredButton,
                                loading: _opening,
                                onPressed: _openPlay,
                              ),
                            ),
                            const SizedBox(height: VelvetSpacing.md),
                            Text(
                              l10n.updateRequiredInstalledVersion(
                                widget.installedVersion,
                              ),
                              key: UpdateRequiredScreen.installedVersionKey,
                              textAlign: TextAlign.center,
                              style: VelvetText.label(),
                            ),
                            const SizedBox(height: VelvetSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Inline, recessed notice above the CTA for when Play cannot be opened.
/// Color is always paired with an icon + text. Announced as a live region.
class _PlayErrorNotice extends StatelessWidget {
  const _PlayErrorNotice({required this.visible, required this.text});

  final bool visible;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      // dim-decorative: show/hide cross-fade; rests at 0 (removed) or 1.
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: !visible
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: UpdateRequiredScreen.playErrorKey,
                padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
                child: Semantics(
                  liveRegion: true,
                  child: NeumorphicInset(
                    radius: VelvetRadii.field,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: VelvetSpacing.md,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: BrandColors.error,
                          ),
                          const SizedBox(width: VelvetSpacing.sm + 2),
                          Expanded(
                            child: Text(
                              text,
                              style: VelvetText.updateGateNotice,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
