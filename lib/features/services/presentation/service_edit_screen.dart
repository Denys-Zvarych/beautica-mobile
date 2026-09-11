// Phase 5.4 — Service edit screen.
//
// Loads the target service via [serviceByIdProvider] (cache-first). When data
// is available, wraps [ServiceForm] in the same EditScaffold chrome used by
// [MasterEditScreen]: fixed top bar (cancel icon + centred title), scrollable
// form body, [ServicePhotoSlot] above the fields.
//
// On successful save:
//   1. Calls [ServiceRepository.update] via [serviceRepositoryProvider].
//   2. Invalidates BOTH cached catalogue views (the «Мої послуги» list and
//      the «Мої записи» «Послуга» filter universe) via
//      [invalidateMasterServiceCatalogues], so both refresh on pop.
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
import 'package:beautica_mobile/features/services/presentation/widgets/delete_service_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_invalidation.dart';

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
  showErrorSnack(context, message);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Service edit screen for INDEPENDENT_MASTER (Phase 5.4).
///
/// Receives [id] from the `/services/:id/edit` path parameter via [app_router].
class ServiceEditScreen extends ConsumerStatefulWidget {
  const ServiceEditScreen({super.key, required this.id, this.writable = true});

  /// Backend UUID for the master-service assignment record.
  final String id;

  /// Phase 320 (D1) — additive, defaults to `true` so every existing caller
  /// renders exactly as today. `false` removes the delete icon and the save
  /// action, and renders the form's fields read-only (D3). No route passes
  /// `false` yet — that lands in phase 321.
  final bool writable;

  @override
  ConsumerState<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends ConsumerState<ServiceEditScreen> {
  static const _tag = 'feature.services.edit_screen';

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

  /// Re-entrancy guard for [_onDelete] (mobile-perf LOW, phase 316).
  ///
  /// Held for the WHOLE flow — confirmation dialog included — not just the
  /// `deactivate` await. Once the dialog pops, the delete icon behind it is
  /// hit-testable again while the DELETE is still in flight, so a double tap
  /// used to open a second dialog and issue a second DELETE. By then the
  /// backend has already deactivated (independent master) / unassigned (salon
  /// target) the row, so the second call answers `404` → [NotFoundFailure] →
  /// an error snackbar for an operation that SUCCEEDED. Phase 316 D2 names
  /// this exact race: a `404` here means "already gone" and must not alarm.
  ///
  /// Mirrors `services_list_notifier.dart`'s `_refreshing` guard rather than
  /// inventing a second mechanism. Cleared in a `finally` so neither an error
  /// path nor a cancelled dialog can latch it permanently.
  bool _deleting = false;

  /// Shows the [DeleteServiceDialog] and, if confirmed, deactivates the service.
  ///
  /// On success the service catalogues are invalidated and the edit screen is
  /// popped. On failure a snackbar is shown via
  /// [_showServiceEditFailureSnackbar] — EXCEPT for a
  /// [ServiceUnassignBlockedFailure] (a salon-target unassign refused because
  /// the master still has a future CONFIRMED booking), which instead re-shows
  /// [DeleteServiceDialog] with `blocked: true` (phase 319 D3). That refusal
  /// path does no optimistic removal and no catalogue invalidation — nothing
  /// was written, the list is still correct — and offers no navigation to the
  /// blocking bookings (backend phase 308 stays deferred; the refusal is
  /// final).
  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    MasterService service,
    AppLocalizations l10n,
  ) async {
    if (_deleting) return;
    _deleting = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const DeleteServiceDialog(),
      );
      if (confirmed != true || !context.mounted) return;
      // Capture the repository BEFORE any invalidation so the DELETE runs
      // against a stable auth/master snapshot: serviceRepositoryProvider
      // watches masterProfileProvider (narrowed to the master id) and the auth
      // provider the interceptor reads, and rebuilding it mid-compose can send
      // the request tokenless → false 401 ("Сесія завершилась"). Read once,
      // then invalidate only AFTER the await completes.
      final repository = ref.read(serviceRepositoryProvider);
      // Backend keys DELETE /api/v1/services/{serviceDefId} on the
      // service-definition id, NOT the assignment id (service.id). With a
      // SalonMasterTarget in scope the repository dispatches to the per-master
      // unassign endpoint instead (phase 316 D1) — same call, same argument.
      await repository.deactivate(service.serviceDefId);
      if (context.mounted) _popServiceEditScreen(context);
      // Invalidate AFTER the delete await completes (and after pop, so
      // ServicesListScreen is active and listening when the re-fetch arrives).
      // ref outlives the frame.
      //
      // This is the COMPLETE fan-out: the two catalogue views are the only
      // cached state a service delete can falsify. masterProfileProvider is
      // deliberately NOT invalidated here (mobile-perf MEDIUM, phase 316) —
      // [Master] carries no service-derived field (see `master.dart`), and the
      // profile screen's services section and stat tile watch
      // `servicesListProvider` directly (`master_profile_screen.dart:505,746`),
      // which the call above already invalidates. A profile invalidation would
      // therefore buy a redundant `GET /masters/me` plus an AsyncLoading churn
      // through every keepAlive dependent (repositories, schedule scope, nav
      // header) — and with a salon target it would refetch the OPERATOR's
      // profile, never the unassigned master's, so it cannot even be right.
      // Same reasoning `working_hours_notifier.dart` already documents for the
      // weekly-schedule write.
      invalidateMasterServiceCatalogues(ref);
    } on ServiceUnassignBlockedFailure {
      // Reactive refusal (phase 319 D3, mirroring backend phase 307 D4 /
      // mobile phase 316 D4): the master still has a future CONFIRMED
      // booking for this service. NOTHING was written — do not pop, do not
      // invalidate servicesListProvider (no optimistic removal), and offer
      // no shortcut to the blocking bookings (phase 308 stays deferred). The
      // dialog it re-shows uses the SAME `showDialog` call site as the
      // confirmation prompt above; its resolved value is discarded — the
      // blocked variant's sole action is a dismiss, never a retry.
      if (kDebugMode) {
        log(
          'ServiceEditScreen: unassign blocked (future booking) for '
          'id=${service.id}',
          name: _tag,
          level: 900,
        );
      }
      if (context.mounted) {
        await showDialog<bool>(
          context: context,
          builder: (_) => const DeleteServiceDialog(blocked: true),
        );
      }
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
    } finally {
      _deleting = false;
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
        writable: widget.writable,
        onSave: (MasterServiceCreate input) async {
          // Build the pricing patch block — all four price fields must be
          // sent together when the price is being updated (backend rule).
          final patch = MasterServiceUpdate(
            name: input.name,
            durationMinutes: input.durationMinutes,
            priceType: input.priceType,
            price: input.price,
            priceMin: input.priceMin,
            priceMax: input.priceMax,
            category: input.category,
            // Thread the chosen service type through the PATCH so a type change
            // actually persists. Previously this was dropped, so the picker was
            // editable in the UI but silently lost on save (M4 API-contract).
            serviceTypeId: input.serviceTypeId,
          );
          // Backend keys PATCH /api/v1/services/{serviceDefId} on the
          // service-definition id; the assignment id (service.id) is threaded
          // through so the returned domain object keeps a stable id.
          await ref
              .read(serviceRepositoryProvider)
              .update(service.serviceDefId, patch, assignmentId: service.id);
          if (context.mounted) {
            showSuccessSnack(context, l10n.serviceUpdatedSuccess);
            _popServiceEditScreen(context);
          }
          // Invalidate AFTER pop so ServicesListScreen is active and
          // listening when the re-fetch arrives. ref outlives the frame.
          //
          // This is the COMPLETE fan-out, and it mirrors `_onDelete`'s: the two
          // catalogue views are the only cached state a service EDIT can
          // falsify. `masterProfileProvider` is deliberately NOT invalidated
          // here (mobile-perf LOW, phase 316) — a rename / reprice /
          // recategorize moves no field on [Master] (`master.dart` carries none
          // that is service-derived), and the profile screen's services stat
          // tile and category section both watch `servicesListProvider`
          // directly (`master_profile_screen.dart:505,746`), which the call
          // above already invalidates. Invalidating the profile would buy a
          // redundant `GET /masters/me` and — because `serviceRepositoryProvider`
          // watches it — an AsyncLoading churn through every keepAlive
          // dependent, for a value that cannot have changed. Same reasoning
          // `working_hours_notifier.dart` documents for the weekly-schedule
          // write, and the same trim `_onDelete` carries, so the two writes on
          // this screen no longer fan out asymmetrically.
          invalidateMasterServiceCatalogues(ref);
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
    this.writable = true,
  });

  final MasterService service;
  final AppLocalizations l10n;
  final Future<void> Function(MasterServiceCreate input) onSave;
  final void Function(Object error) onError;

  /// Called when the master taps the destructive delete icon button in the top
  /// bar and the dialog has been shown. Handed off to [_ServiceEditScreenState]
  /// which owns the `ref` needed to call the repository and invalidate providers.
  final Future<void> Function(MasterService service) onDelete;

  /// Phase 320 (D1/D3) — additive, defaults to `true`. `false` hides the
  /// delete icon (not disabled — D3) and renders [ServiceForm] read-only.
  final bool writable;

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

  // PERF MEDIUM-1 fix: Pre-built Animation<Offset> instances so _reveal() never
  // allocates a new Tween+_AnimatedEvaluation on each build frame during the
  // 1000 ms entrance animation. Pattern mirrors _MasterProfileScreenState
  // (_slide0.._slide5) in master_profile_screen.dart.
  late final Animation<Offset> _photoSlide;
  late final Animation<Offset> _formSlide;

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
    // Derive the slide animations once from their parent CurvedAnimation.
    // Animation<Offset> instances do not own resources and need no dispose().
    const slideBegin = Offset(0, 0.04);
    _photoSlide = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_photoCurve);
    _formSlide = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_formCurve);
  }

  @override
  void dispose() {
    _photoCurve.dispose();
    _formCurve.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// Wraps [child] in a staggered fade-up animation.
  ///
  /// [fadeAnim] drives opacity; [slideAnim] is the pre-built [Animation<Offset>]
  /// that drives the vertical offset. Both are initialised once in [initState]
  /// — no heap allocations occur during build frames.
  Widget _reveal(
    Animation<double> fadeAnim,
    Animation<Offset> slideAnim,
    Widget child,
  ) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(position: slideAnim, child: child),
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
                    // Phase 320 (D3): hidden, not disabled, when read-only —
                    // the backend 403s every write path for this viewer, so a
                    // greyed delete icon would promise an action it cannot
                    // perform.
                    if (widget.writable)
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
                      _photoSlide,
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
                      _formSlide,
                      ServiceForm(
                        key: Key('service-edit-form-${widget.service.id}'),
                        initial: widget.service,
                        submitLabel: l10n.servicesSaveChanges,
                        readOnly: !widget.writable,
                        onSubmit: (MasterServiceCreate input) async {
                          try {
                            await widget.onSave(input);
                          } on ValidationFailure {
                            // Per-field backend errors are mapped inline by
                            // ServiceForm. Rethrow so the form can claim them;
                            // it shows a generic snackbar itself when no field
                            // matches, so onError is not invoked for 400s.
                            rethrow;
                          } on ServiceDuplicateFailure {
                            // Backend 409 DUPLICATE_SERVICE is mapped inline by
                            // ServiceForm onto the service-type field. Rethrow
                            // so it can claim it — routing it to onError would
                            // show a transient snackbar and leave the offending
                            // field unflagged, so the user re-hits the same 409.
                            rethrow;
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
