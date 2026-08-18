// Phase 2.11 — Email Verification Screen (VelvetTouch neumorphic redesign).
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/verify_email_screen.dart
//
// VelvetTouch tokens (locked — ARCHITECTURE-mobile.md § 9 VelvetTouch table):
//   Auth background  : BrandColors.base via AuthScaffold (NO painter/gradient/BackdropFilter)
//   Logo tile radius : VelvetRadii.logoTile (24)
//   OTP cell radius  : VelvetRadii.field  (16)
//   OTP cell shadow  : VelvetShadows.extrudedSmall
//   CTA button       : NeumorphicButton (core/widgets/neumorphic.dart)
//   Error banner     : AuthBanner (features/auth/presentation/widgets/auth_scaffold.dart)
//
// Widget test keys:
//   ValueKey('verify_code_input') — hidden TextField (single entry for all 6 digits)
//   ValueKey('verify_submit')     — NeumorphicButton CTA
//   ValueKey('verify_resend')     — GestureDetector resend link
//   ValueKey('auth_scaffold_back') — top-left back button (AuthScaffold overlay, Test 6)

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/util/mask_email.dart';
import '../../../shared/validators/server_field_error_banner.dart';
import '../../master/data/master_repository.dart';
import '../../salon/data/salon_repository.dart';
import '../../user/data/user_repository.dart';
import '../domain/user_role.dart';
import '../state/pending_locality.dart';
import '../state/pending_locality_store.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_code_field.dart';
import 'widgets/otp_resend_row.dart';

// ---------------------------------------------------------------------------
// Cooldown duration after a successful resend (seconds).
// ---------------------------------------------------------------------------

const _kResendCooldownSeconds = 30;
const _kOtpLength = 6;

// ---------------------------------------------------------------------------
// Provider — survives widget reconstruction within the same ProviderScope so
// that a hot-reload or OS-triggered State recreation cannot reset a completed
// OTP verification step and replay a consumed code.
//
// autoDispose: true — resets when the user navigates away from the
// verification flow entirely (ProviderScope removes the listener).
// ---------------------------------------------------------------------------

/// Notifier that holds the "OTP accepted" flag for the verification flow.
///
/// Stored outside [_VerificationScreenState] so that widget reconstruction
/// (hot-reload, OS activity recreation) cannot reset the flag and cause
/// [_submit] to re-call `verifyEmail` with an already-consumed OTP code.
///
/// `autoDispose` via the provider declaration ensures the flag resets when
/// the user leaves the verification flow entirely (no active listeners).
final class _EmailVerifiedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markVerified() => state = true;
}

final _emailVerifiedProvider =
    NotifierProvider.autoDispose<_EmailVerifiedNotifier, bool>(
      _EmailVerifiedNotifier.new,
    );

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Email verification screen — Phase 2.11 VelvetTouch redesign.
///
/// Accepts [email] via the constructor (passed from RegisterScreen via
/// [GoRouter] extra). If no email is available (e.g. deep-link edge case),
/// an empty string is used — the masked display degrades gracefully.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key, required this.email});

  /// The email address that the OTP was sent to, passed as GoRouter extra.
  final String email;

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  // ── OTP state ─────────────────────────────────────────────────────────────

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  String get _otp => _codeController.text;
  bool get _isOtpComplete => _otp.length == 6;

  // ── Cooldown timer — owned by OtpResendRow; parent holds a key to reset it ──
  //
  // Fix 2B: when _saveProviderProfile() fails after the OTP is already consumed
  // the user must be able to request a new code immediately (their OTP is gone).
  // Calling _resendRowKey.currentState?.resetCooldown() from _submit's catch
  // drives the countdown back to 0 without any cross-widget setState coupling.
  final GlobalKey<OtpResendRowState> _resendRowKey =
      GlobalKey<OtpResendRowState>();

  // ── Error / flow state ───────────────────────────────────────────────────

  /// Inline error message shown below the OTP row.
  String? _inlineError;

  /// Optional label for the action button inside the inline error banner.
  ///
  /// Set to non-null (together with [_inlineErrorAction]) when the error
  /// carries a recovery action — e.g. "Увійти" after INVALID_CODE so the user
  /// can navigate to login instead of retrying the consumed OTP.
  String? _inlineErrorActionLabel;

  /// Callback for the action button inside the inline error banner.
  VoidCallback? _inlineErrorAction;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_isOtpComplete) return;
    final l10n = AppLocalizations.of(context);

    try {
      // Skip re-verification when the code was already accepted but the
      // post-verification provider save failed (Defect 8 retry path): the OTP
      // is consumed, so only retry the save.
      //
      // _emailVerifiedProvider survives widget reconstruction (hot-reload / OS
      // activity recreation) so this guard is reliable across State rebuilds.
      if (!ref.read(_emailVerifiedProvider)) {
        await ref
            .read(authProvider.notifier)
            .verifyEmail(email: widget.email, otp: _otp);
        if (!mounted) return;
        ref.read(_emailVerifiedProvider.notifier).markVerified();
      }

      // Defect 8 — a session token now exists, so persist the provider's
      // locality/address that was stashed in the draft on Step 3. This is the
      // FIRST point the auth-required PATCH /independent-masters/me and
      // POST /salons calls can succeed. A failure here surfaces a real inline
      // error (not silent) and keeps the user on this screen so they can retry.
      await _saveProviderProfile(l10n);
      if (!mounted) return;

      if (kDebugMode) {
        log(
          'Verification screen: navigating to done',
          name: 'auth.verification',
          level: 800,
        );
      }
      context.go(RouteNames.done);
    } catch (e) {
      if (!mounted) return;
      // Fix 2B: if the post-OTP profile save failed (_emailVerifiedProvider is
      // true, meaning the OTP was consumed but the PATCH /independent-masters/me
      // call threw), the user needs to request a new code before they can
      // retry — reset the resend cooldown immediately so they are not blocked
      // by the 30-second window.
      if (ref.read(_emailVerifiedProvider)) {
        _resendRowKey.currentState?.resetCooldown();
      }
      _setInlineError(e, l10n);
    }
  }

  /// Persists the user's locality/address after verification.
  ///
  /// Reads the stashed Step 3 slice from the keepAlive register draft and calls
  /// the role-appropriate endpoint:
  ///   INDEPENDENT_MASTER → PATCH /independent-masters/me  (provider profile)
  ///   SALON_OWNER        → POST  /salons                   (creates the salon)
  ///   CLIENT             → PATCH /users/me                 (user row only —
  ///                         RegisterRequest silently drops these fields, so
  ///                         this is the FIRST point they reach the DB).
  ///   SALON_ADMIN / _MASTER → no-op (invite flow, no Step 3).
  ///
  /// Rethrows the typed [Failure] on error so [_submit]'s catch surfaces it as
  /// a real inline message (Defect 8 — never silent).
  Future<void> _saveProviderProfile(AppLocalizations l10n) async {
    // Resolve the locality slice. Prefer the in-memory draft, but fall back to
    // the durable blob that Step 3 stashed in secure storage — the draft is
    // routinely lost while the user backgrounds the app to read the OTP email
    // (or is OS-killed under memory pressure), in which case the keepAlive
    // provider is back to its initial `null`. Without this fallback the locality
    // PATCH silently never runs (the original silent-data-loss defect).
    final _ResolvedLocality? locality = await _resolveLocality();

    // No draft AND no durable blob → genuine deep-link edge case (e.g. user
    // tapped the email link on a different device). Nothing to persist.
    if (locality == null) return;

    final cityId = locality.cityId;
    final bool isCityMissing = cityId == null || cityId.isEmpty;

    if (isCityMissing) {
      switch (locality.role) {
        case UserRole.independentMaster:
        case UserRole.salonOwner:
          // Provider roles require a city — the Step 3 address wizard is
          // mandatory for them and the PATCH / POST cannot succeed without it.
          // A missing city here means the state was lost AND the durable blob
          // could not supply it — surface a typed failure so the user can go
          // back to Step 3, instead of silently creating a located-less account.
          throw const ProviderMissingCityFailure();
        case UserRole.client:
          // De-silence the lost-draft case: if the user provably chose a city
          // (the blob recorded localityProvided == true) but we still cannot
          // resolve it, the durable blob was unexpectedly missing/corrupt. Do
          // NOT block /done, but log it (debug-only, ids only) so the loss is
          // not invisible. A genuine CLIENT skip (localityProvided == false)
          // stays a silent no-op — the legitimate path.
          if (locality.localityProvided && kDebugMode) {
            log(
              'CLIENT chose a city on Step 3 but locality could not be '
              'persisted (durable blob missing/corrupt); skipping PATCH',
              name: 'auth.verification',
              level: 900,
            );
          }
          return;
        case UserRole.salonAdmin:
        case UserRole.salonMaster:
          // Invite-flow roles never run Step 3.
          return;
      }
    }

    final districtId = locality.districtId;

    switch (locality.role) {
      case UserRole.independentMaster:
        await ref
            .read(masterRepositoryProvider)
            .updateLocality(
              cityId: cityId,
              districtId: districtId,
              street: locality.street,
              buildingNo: locality.buildingNo,
              locationNote: locality.locationNote,
            );
      case UserRole.salonOwner:
        await ref
            .read(salonRepositoryProvider)
            .create(
              dto: SalonCreateDto(
                name: locality.salonName,
                cityId: cityId,
                districtId: districtId,
                street: locality.street,
                buildingNo: locality.buildingNo,
                locationNote: locality.locationNote,
                phone: locality.phone,
              ),
            );
      case UserRole.client:
        // CLIENT has no provider profile, but locality must still be persisted
        // — the register endpoint drops these fields (RegisterRequest doesn't
        // declare them), so PATCH /users/me is the FIRST point they reach the
        // DB. Mirrors the INDEPENDENT_MASTER branch above.
        await ref
            .read(userRepositoryProvider)
            .updateLocality(
              cityId: cityId,
              districtId: districtId,
              street: locality.street,
              buildingNo: locality.buildingNo,
              locationNote: locality.locationNote,
            );
      case UserRole.salonAdmin:
      case UserRole.salonMaster:
        // Invite-flow roles never run the Step 3 wizard.
        return;
    }
  }

  /// Resolves the locality slice to persist, preferring the in-memory draft and
  /// falling back to the durable [PendingLocality] blob keyed by [widget.email].
  ///
  /// Returns `null` only when BOTH the draft and the durable blob are absent
  /// (true deep-link edge case). When the draft exists but is missing a city,
  /// the durable blob is consulted so a partially-lost draft can still recover
  /// the city the user chose.
  Future<_ResolvedLocality?> _resolveLocality() async {
    final draft = ref.read(registerDraftProvider);
    final bool draftHasCity =
        draft != null && draft.cityId != null && draft.cityId!.isNotEmpty;

    // Fast path — the draft survived and carries a city.
    if (draftHasCity) {
      return _ResolvedLocality(
        role: draft.role,
        localityProvided: true,
        cityId: draft.cityId,
        districtId: draft.districtId,
        street: draft.street,
        buildingNo: draft.buildingNo,
        locationNote: draft.locationNote,
        salonName: draft.salonName,
        phone: draft.phone,
      );
    }

    // Either the draft is gone, or it lost its city — consult the durable blob.
    // The blob is documented as email-keyed: only consume it when its email
    // matches the address currently being verified, compared trimmed +
    // case-insensitively. This closes the cross-account PII bleed where a blob
    // stashed by user A (abandoned before OTP) would otherwise be applied onto
    // user B, who reached /verification via the login EMAIL_NOT_VERIFIED path.
    final PendingLocality? pending = await _readPendingLocality();
    final bool pendingMatchesEmail =
        pending != null &&
        pending.email.trim().toLowerCase() == widget.email.trim().toLowerCase();
    if (pendingMatchesEmail) {
      return _ResolvedLocality(
        role: pending.role,
        localityProvided: pending.localityProvided,
        cityId: pending.cityId,
        districtId: pending.districtId,
        street: pending.street,
        buildingNo: pending.buildingNo,
        locationNote: pending.locationNote,
        salonName: pending.salonName,
        phone: pending.phone,
      );
    }

    // A blob exists but belongs to a DIFFERENT email — best-effort clear it so
    // stale cross-account PII does not linger in secure storage. We never apply
    // it to this account.
    if (pending != null) {
      unawaited(ref.read(pendingLocalityStoreProvider).clear());
    }

    // No blob — fall back to whatever the draft holds (may be a genuine CLIENT
    // skip with no city), or null when there is no draft at all.
    if (draft == null) return null;
    return _ResolvedLocality(
      role: draft.role,
      // No durable blob recorded a city → treat as a genuine skip, not a loss.
      localityProvided: false,
      cityId: draft.cityId,
      districtId: draft.districtId,
      street: draft.street,
      buildingNo: draft.buildingNo,
      locationNote: draft.locationNote,
      salonName: draft.salonName,
      phone: draft.phone,
    );
  }

  /// Reads the durable blob, tolerating storage failures (returns `null`).
  Future<PendingLocality?> _readPendingLocality() async {
    try {
      return await ref.read(pendingLocalityStoreProvider).read();
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to read pending locality (tolerated): ${e.runtimeType}',
          name: 'auth.verification',
          level: 900,
        );
      }
      return null;
    }
  }

  /// Callback passed to [OtpResendRow]. Returns the cooldown seconds the row
  /// should display, or null to leave the row's cooldown unchanged (generic
  /// error — allow immediate retry).
  ///
  /// M-Sec-1 (2026-05-20): Side-effects (clearing OTP, clearing the inline
  /// error) fire AFTER the await succeeds, never before.
  Future<int?> _resend() async {
    final l10n = AppLocalizations.of(context);

    try {
      await ref.read(authProvider.notifier).resendCode(email: widget.email);

      if (!mounted) return _kResendCooldownSeconds;

      // Success path — safely clear the OTP and the inline error (including
      // any recovery action from a previous INVALID_CODE / throttle banner).
      _codeController.clear();
      setState(() {
        _inlineError = null;
        _inlineErrorActionLabel = null;
        _inlineErrorAction = null;
      });

      if (kDebugMode) {
        log('Resend code dispatched', name: 'auth.verification', level: 800);
      }

      return _kResendCooldownSeconds;
    } on ResendThrottledFailure catch (throttle) {
      if (!mounted) return throttle.retryAfterSeconds;
      // Throttle errors have no recovery action — clear any stale action from a
      // previous INVALID_CODE banner to avoid a dangling "Увійти" button.
      setState(() {
        _inlineError = throttle.userMessage(context);
        _inlineErrorActionLabel = null;
        _inlineErrorAction = null;
      });
      return throttle.retryAfterSeconds;
    } catch (e) {
      if (!mounted) return null;
      _setInlineError(e, l10n);
      return null; // No cooldown on generic error — allow immediate retry.
    }
  }

  /// Sets [_inlineError], [_inlineErrorActionLabel], and [_inlineErrorAction]
  /// based on [error].
  ///
  /// For [VerificationFailure] with [VerificationErrorCode.invalidCode]:
  ///   - Shows "Невірний або вже використаний код. Спробуйте увійти."
  ///   - Adds an "Увійти" action that navigates to the login screen so the user
  ///     can log in if the account was already verified (the backend returns the
  ///     same INVALID_CODE for a consumed code as for a genuinely wrong one).
  ///
  /// For [VerificationFailure] with [VerificationErrorCode.alreadyVerified]:
  ///   - Shows "Цей акаунт вже підтверджено. Увійдіть." with the same action.
  ///
  /// All other failures show their [Failure.userMessage] with no action.
  void _setInlineError(Object? error, AppLocalizations l10n) {
    String message;
    String? actionLabel;
    VoidCallback? action;

    if (error is VerificationFailure &&
        (error.code == VerificationErrorCode.invalidCode ||
            error.code == VerificationErrorCode.alreadyVerified)) {
      message = error.code == VerificationErrorCode.alreadyVerified
          ? l10n.verificationErrAlreadyVerified
          : l10n.verificationErrInvalidCodeWithLoginHint;
      actionLabel = l10n.verificationGoToLogin;
      action = () => context.go(RouteNames.login);
    } else if (error is ValidationFailure) {
      // Post-OTP provider save (salon create / locality update) rejected one or
      // more register step 2/3 fields. Surface the failed field name(s)
      // instead of collapsing to the generic banner — never the backend's raw
      // per-field message (mobile-security, 2026-08 — see
      // `buildFieldErrorBanner`'s doc). The offending fields live on a
      // previous step, so the user must go back and fix them.
      final banner = buildFieldErrorBanner(error.fieldErrors, l10n);
      message = banner ?? error.userMessage(context);
    } else if (error is UnimplementedError) {
      message = l10n.verificationServiceUnavailable;
    } else if (error is Failure) {
      message = error.userMessage(context);
    } else {
      message = l10n.verificationServiceUnavailable;
    }

    // Defensive catch-all (mirrors master_edit_screen.dart empty-message guard):
    // a non-VerificationFailure that drifts at runtime (interceptor path miss,
    // 500, network) — or a Failure whose userMessage somehow resolves to a
    // blank/whitespace string — must NEVER produce a silent submit. Fall back
    // to a guaranteed non-empty generic banner so the user always sees an error.
    if (message.trim().isEmpty) {
      message = l10n.errUnknown;
    }

    setState(() {
      _inlineError = message;
      _inlineErrorActionLabel = actionLabel;
      _inlineErrorAction = action;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(authProvider.select((s) => s.isLoading));
    // Keep _emailVerifiedProvider alive for the widget's entire lifetime.
    // Without this watch the autoDispose provider resets to false between the
    // two submit taps (Defect 8 retry path), causing verifyEmail to be called
    // again on re-submit even though the OTP was already consumed.
    // The value itself is not needed in build() — only the subscription matters.
    ref.watch(_emailVerifiedProvider);
    final maskedEmail = maskEmail(widget.email);

    // Fix A (MEDIUM-1): ValueListenableBuilder scopes OTP-cell AND submit-button
    // rebuilds to the controller's value. The parent _VerificationScreenState
    // never calls setState on a keystroke.
    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerStep3),
      bottomBar: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _codeController,
        builder:
            (BuildContext context, TextEditingValue value, Widget? child) =>
                NeumorphicButton(
                  key: const ValueKey<String>('verify_submit'),
                  label: l10n.verificationConfirmBtn,
                  loading: isLoading,
                  onPressed: (value.text.length == _kOtpLength && !isLoading)
                      ? _submit
                      : null,
                ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Email icon tile ───────────────────────────────────────────────
          Center(
            child: Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.all(
                  Radius.circular(VelvetRadii.logoTile),
                ),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: BrandColors.accent,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          // ── Heading ───────────────────────────────────────────────────────
          Text(
            l10n.verificationHeadline,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // ── Email description ─────────────────────────────────────────────
          Text.rich(
            TextSpan(
              style: VelvetText.body(),
              children: <InlineSpan>[
                TextSpan(text: '${l10n.verificationCardDesc}\n'),
                TextSpan(text: maskedEmail, style: VelvetText.bodyStrong()),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.xl),
          // ── OTP field — rebuild scoped to controller value ─────────────────
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _codeController,
            builder: (context, value, child) => OtpCodeField(
              controller: _codeController,
              focusNode: _codeFocus,
              length: _kOtpLength,
              fieldKey: const ValueKey<String>('verify_code_input'),
              semanticsLabel: 'Код підтвердження, $_kOtpLength цифр',
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
          // ── Resend row — owns its own cooldown timer (Fix B / MEDIUM-2) ────
          OtpResendRow(
            key: _resendRowKey,
            onResend: _resend,
            initialCooldown: _kResendCooldownSeconds,
            resendKey: const ValueKey<String>('verify_resend'),
            promptText: l10n.verificationResendPrompt,
            resendLabel: l10n.verificationResendBtn,
            resendTimerLabel: (int seconds) =>
                l10n.verificationResendTimer('$seconds с'),
          ),
          // ── Inline error banner ───────────────────────────────────────────
          // [_inlineErrorActionLabel] and [_inlineErrorAction] are non-null when
          // the error includes a recovery CTA (e.g. "Увійти" for INVALID_CODE /
          // ALREADY_VERIFIED so the user can navigate to login directly).
          if (_inlineError != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            AuthBanner(
              icon: Icons.error_outline_rounded,
              color: BrandColors.error,
              message: _inlineError!,
              actionLabel: _inlineErrorActionLabel,
              onAction: _inlineErrorAction,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resolved locality — the effective slice to persist after OTP, sourced from
// either the in-memory draft or the durable [PendingLocality] blob.
// ---------------------------------------------------------------------------

final class _ResolvedLocality {
  const _ResolvedLocality({
    required this.role,
    required this.localityProvided,
    required this.cityId,
    required this.districtId,
    required this.street,
    required this.buildingNo,
    required this.locationNote,
    required this.salonName,
    required this.phone,
  });

  final UserRole role;

  /// `true` when the user provably chose a city on Step 3 (de-silences the
  /// lost-draft case for CLIENT). `false` for a genuine CLIENT skip.
  final bool localityProvided;

  final String? cityId;
  final String? districtId;
  final String street;
  final String buildingNo;
  final String locationNote;
  final String salonName;
  final String phone;
}
