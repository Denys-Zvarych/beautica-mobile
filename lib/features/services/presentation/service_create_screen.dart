// Phase 5.3 — Service create screen.
//
// Renders the [ServiceForm] in an [EditScaffold]-style layout (fixed top bar,
// scrollable body, pinned CTA footer). On successful submit:
//   1. Calls [ServiceRepository.create] via [serviceRepositoryProvider].
//   2. Invalidates [servicesListProvider] so the list refreshes on pop.
//   3. Pops the screen via [context.pop] (go_router, raw navigator avoided).
//
// The [ServiceForm] handles its own loading state and propagates exceptions —
// this screen catches them and shows a [SnackBar] so the user can retry without
// losing their input.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter/foundation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';

/// Service create screen (INDEPENDENT_MASTER).
///
/// Wraps [ServiceForm] with the [EditScaffold]-style chrome: cancel icon
/// button top-left, centred title, scrollable form body. The form's CTA is
/// rendered inline (not pinned to the bottom) to keep the screen stateless
/// at this level.
class ServiceCreateScreen extends ConsumerStatefulWidget {
  const ServiceCreateScreen({super.key});

  @override
  ConsumerState<ServiceCreateScreen> createState() =>
      _ServiceCreateScreenState();
}

class _ServiceCreateScreenState extends ConsumerState<ServiceCreateScreen> {
  static const _tag = 'feature.services.create_screen';

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar — cancel button + centred title.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeumorphicIconButton(
                        key: const Key('btn-cancel-service-create'),
                        icon: Icons.close_rounded,
                        semanticLabel: l10n.masterCancelButton,
                        onTap: () => _popScreen(context),
                      ),
                    ),
                    Text(
                      l10n.servicesCreateTitle,
                      style: VelvetText.subheading(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable form body.
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.md,
                  VelvetSpacing.sm,
                  VelvetSpacing.md,
                  VelvetSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(
                      height: 140,
                      child: ServicePhotoSlot(
                        key: Key('service-create-photo-slot'),
                        // onTap is null — slot shows empty state; real picker is Phase 9.x.
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.sm),
                    ServiceForm(
                      onSubmit: (MasterServiceCreate input) async {
                        try {
                          await ref
                              .read(serviceRepositoryProvider)
                              .create(input);
                          if (context.mounted) {
                            final l10n = AppLocalizations.of(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.serviceCreatedSuccess),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _popScreen(context);
                          }
                          // Invalidate AFTER pop so ServicesListScreen is
                          // active and listening when the re-fetch arrives.
                          // ref remains valid because this ConsumerWidget's
                          // ref outlives the navigation frame.
                          ref.invalidate(servicesListProvider);
                          ref.invalidate(masterProfileProvider);
                        } on ValidationFailure {
                          // Per-field backend errors are mapped inline by
                          // ServiceForm itself (it catches ValidationFailure
                          // before this closure rethrows). Reaching here means
                          // the failure had NO field this form renders — show
                          // the generic snackbar fallback.
                          rethrow;
                        } catch (e) {
                          if (context.mounted) {
                            _showFailureSnackbar(context, e);
                          }
                        }
                      },
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

  /// Pops the current route, preferring [GoRouter.of(context).pop()] when
  /// inside a go_router-managed tree, and falling back to
  /// [Navigator.maybePop] otherwise (e.g. in widget tests that pump without
  /// a full GoRouter).
  static void _popScreen(BuildContext context) {
    // Check for GoRouter first. GoRouterHelper.canPop throws if there is no
    // GoRouter ancestor, so we guard with a try/catch.
    try {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
        return;
      }
    } catch (_) {
      // No GoRouter in the widget tree — fall through to Navigator.
    }
    Navigator.maybePop(context);
  }

  /// Maps a [Failure] to a localised snackbar message.
  ///
  /// Called by [ServiceForm] consumers that want to surface submission errors
  /// without coupling the form to [BuildContext]-dependent l10n.
  static void _showFailureSnackbar(BuildContext context, Object failure) {
    final l10n = AppLocalizations.of(context);
    final String message;
    if (failure is Failure) {
      message = failure.userMessage(context);
    } else {
      message = l10n.errUnknown;
    }
    if (kDebugMode) {
      log(
        'ServiceCreateScreen: submission error: $failure',
        name: _tag,
        level: 900,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
