// Phase 5.4 — Service edit screen.
//
// Loads the target service via [serviceByIdProvider] (cache-first). When data
// is available, wraps [ServiceForm] in the same EditScaffold chrome used by
// [MasterEditScreen]: fixed top bar (cancel icon + centred title), scrollable
// form body, [ServicePhotoSlot] above the fields.
//
// On successful save:
//   1. Calls [ServiceRepository.update] via [serviceRepositoryProvider].
//   2. Invalidates [servicesListProvider] so the list refreshes on pop.
//   3. Pops the screen via [GoRouter.of(context).pop()].
//
// Concurrency note: Optimistic UI is intentionally NOT used here. Concurrent
// edits to the same service are rare for a solo master — pessimistic save keeps
// state predictable.
//
// Design source: docs/signup-designs/ServiceEditForm/ — transcribed 1:1.
// Nav: pushed via context.push(RouteNames.serviceEdit(id)) from ServicesListScreen.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/service_by_id_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/delete_service_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// File-private navigation helpers (used by both the state and the loaded body).
// ---------------------------------------------------------------------------

void _popServiceEditScreen(BuildContext context) {
  try {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
  } catch (_) {}
  Navigator.maybePop(context);
}

void _showServiceEditFailureSnackbar(
  BuildContext context,
  Object failure,
  AppLocalizations l10n,
) {
  final String message = failure is Failure
      ? failure.userMessage(context)
      : l10n.errUnknown;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Service edit screen for INDEPENDENT_MASTER (Phase 5.4).
///
/// Receives [id] from the `/services/:id/edit` path parameter via [app_router].
class ServiceEditScreen extends ConsumerStatefulWidget {
  const ServiceEditScreen({super.key, required this.id});

  /// Backend UUID for the master-service assignment record.
  final String id;

  @override
  ConsumerState<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends ConsumerState<ServiceEditScreen> {
  static const _tag = 'feature.services.edit_screen';

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  /// Shows the [DeleteServiceDialog] and, if confirmed, deactivates the service.
  ///
  /// On success the services list is invalidated and the edit screen is popped.
  /// On failure a snackbar is shown via [_showServiceEditFailureSnackbar].
  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    MasterService service,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteServiceDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(serviceRepositoryProvider).deactivate(service.id);
      ref.invalidate(servicesListProvider);
      if (context.mounted) _popServiceEditScreen(context);
    } catch (e) {
      if (kDebugMode) {
        log(
          'ServiceEditScreen: deactivate error for id=${service.id} — $e',
          name: _tag,
          level: 900,
        );
      }
      if (context.mounted) {
        _showServiceEditFailureSnackbar(context, e, l10n);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncService = ref.watch(serviceByIdProvider(widget.id));

    return asyncService.when(
      loading: () => const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(
          child: CircularProgressIndicator(
            key: Key('edit_service_loading'),
            color: BrandColors.accentDeep,
          ),
        ),
      ),
      error: (Object e, _) {
        if (kDebugMode) {
          log(
            'ServiceEditScreen: load error for id=${widget.id} — $e',
            name: _tag,
            level: 900,
          );
        }
        final failure = e is Failure ? e : UnknownFailure(cause: e);
        return Scaffold(
          backgroundColor: BrandColors.base,
          body: ErrorState(
            key: const Key('service_edit_error_state'),
            failure: failure,
            onRetry: () => ref.invalidate(serviceByIdProvider(widget.id)),
          ),
        );
      },
      data: (MasterService service) => _EditBody(
        service: service,
        l10n: l10n,
        onSave: (MasterServiceCreate input) async {
          final patch = MasterServiceUpdate(
            name: input.name,
            durationMinutes: input.durationMinutes,
            price: input.price,
          );
          await ref.read(serviceRepositoryProvider).update(service.id, patch);
          ref.invalidate(servicesListProvider);
          if (context.mounted) _popServiceEditScreen(context);
        },
        onError: (Object e) {
          if (kDebugMode) {
            log(
              'ServiceEditScreen: save error for id=${widget.id} — $e',
              name: _tag,
              level: 900,
            );
          }
          if (context.mounted) {
            _showServiceEditFailureSnackbar(context, e, l10n);
          }
        },
        onDelete: (MasterService svc) => _onDelete(context, ref, svc, l10n),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body — EditScaffold chrome + ServicePhotoSlot + ServiceForm
// ---------------------------------------------------------------------------

class _EditBody extends StatefulWidget {
  const _EditBody({
    required this.service,
    required this.l10n,
    required this.onSave,
    required this.onError,
    required this.onDelete,
  });

  final MasterService service;
  final AppLocalizations l10n;
  final Future<void> Function(MasterServiceCreate input) onSave;
  final void Function(Object error) onError;

  /// Called when the master taps the destructive delete icon button in the top
  /// bar and the dialog has been shown. Handed off to [_ServiceEditScreenState]
  /// which owns the `ref` needed to call the repository and invalidate providers.
  final Future<void> Function(MasterService service) onDelete;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody>
    with SingleTickerProviderStateMixin {
  // Staggered entrance animation — mirrors the approved preview app's
  // orchestrated fade-up that builds the form rather than snapping it in flat.
  late final AnimationController _enter;
  late final CurvedAnimation _photoCurve;
  late final CurvedAnimation _formCurve;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    // Photo slot: 0.04 → 0.46; form: 0.0 → 1.0.
    _photoCurve = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.04, 0.46, curve: Curves.easeOutCubic),
    );
    _formCurve = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _photoCurve.dispose();
    _formCurve.dispose();
    _enter.dispose();
    super.dispose();
  }

  Widget _reveal(Animation<double> curve, Widget child) {
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar: cancel icon (left) + centred title.
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
                        key: const Key('btn-cancel-service-edit'),
                        icon: Icons.close_rounded,
                        semanticLabel: l10n.masterCancelButton,
                        onTap: () => _popServiceEditScreen(context),
                      ),
                    ),
                    Text(
                      l10n.servicesEditTitle,
                      style: VelvetText.subheading(),
                      textAlign: TextAlign.center,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: const Key('btn-delete-service'),
                        icon: const Icon(Icons.delete_outline),
                        color: Theme.of(context).colorScheme.error,
                        tooltip: l10n.deleteServiceTitle,
                        onPressed: () => widget.onDelete(widget.service),
                      ),
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
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                  VelvetSpacing.lg,
                  VelvetSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Cover-photo slot (placeholder tap — Phase 9.x wires real upload).
                    _reveal(
                      _photoCurve,
                      const ServicePhotoSlot(
                        key: Key('service-photo-slot'),
                        // imageUrl: widget.service.photoUrl (Phase 9.x)
                        // onTap is null → slot shows empty state, not interactive
                        // until Phase 9.x wires up the real picker.
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.lg),

                    // ServiceForm with pre-populated values + dirty-state badge.
                    _reveal(
                      _formCurve,
                      ServiceForm(
                        key: Key('service-edit-form-${widget.service.id}'),
                        initial: widget.service,
                        submitLabel: l10n.servicesSaveChanges,
                        onSubmit: (MasterServiceCreate input) async {
                          try {
                            await widget.onSave(input);
                          } catch (e) {
                            widget.onError(e);
                          }
                        },
                      ),
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
