// Контакти — the contact slice of the retired monolithic edit form: Телефон
// (required, UaPhoneInputFormatter, privacy helper note) and Instagram
// (optional, `@` prefix). A pinned "Зберегти" CTA sits at the bottom.
//
// CRITICAL correctness constraint — do NOT clear sibling fields:
//   [MasterRepository.updateMyProfile] always sends firstName/lastName/bio/
//   instagram, and an empty string CLEARS the field server-side. This page only
//   edits phone + instagram, so on save it builds the FULL [MasterUpdate] from
//   the current cached [masterProfileProvider] master, overlaying ONLY phone +
//   instagram and preserving the cached firstName/lastName/bio. Otherwise Save
//   would wipe the name and bio.
//
// Save flow: validate → updateMyProfile(merged) → invalidate
// masterProfileProvider → saved VelvetSnack → pop.
//
// Phone onChanged only setState when the error actually changes (avoids a
// full-card rebuild per keystroke).
//
// Security: ScreenProtector active in release builds (PII-bearing screen).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// contacts_edit_screen.dart` — ported with the real notifier + repository.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';

import 'master_profile_notifier.dart';
import 'master_role_routes.dart';
import 'widgets/section_scaffold.dart';

/// Contacts edit page (phone + instagram).
//
// Reused VERBATIM by the SALON_MASTER contacts edit
// (`RouteNames.salonMasterEditContacts`, `/staff/edit/contacts`) via one
// additive param — every existing (INDEPENDENT_MASTER) call site passes none
// of it and renders EXACTLY as before:
//   * [showInstagram] — SALON_MASTER contacts are phone-only (product
//     decision: no Instagram, no location, for this role). `false` hides the
//     field, its validator, and its dirty-tracking, and the save overlay
//     preserves the cached Instagram verbatim instead of sending the (never
//     rendered, never edited) controller text — see [_save]. The field is
//     never sent as empty, which would CLEAR it server-side for a role that
//     simply cannot see it.
//
// The post-save `context.go` and the onBack no-pop fallback resolve their
// destination from `cached.type` via the shared `masterHomeRouteFor`/
// `masterMenuRouteFor` (`master_role_routes.dart`) rather than hardcoding the
// INDEPENDENT_MASTER route — same pattern as `personal_info_edit_screen.dart`,
// which faced the identical multi-role-reuse need first.
class ContactsEditScreen extends ConsumerStatefulWidget {
  const ContactsEditScreen({super.key, this.showInstagram = true});

  /// Whether the «Instagram» field renders. Defaults to `true`
  /// (INDEPENDENT_MASTER, every pre-existing call site, unaffected).
  final bool showInstagram;

  @override
  ConsumerState<ContactsEditScreen> createState() => _ContactsEditScreenState();
}

class _ContactsEditScreenState extends ConsumerState<ContactsEditScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _phone;
  late final TextEditingController _instagram;

  bool _initialized = false;

  String _origPhone = '';
  String _origInstagram = '';

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errPhone;
  String? _errInstagram;

  // PERF (P2): drives the Save button's enabled state in isolation so typing
  // does not setState the whole form (and its reveal animation wrappers).
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  static const int _phoneMax = 20;

  // Pre-built static RegExps — allocated once, never inside build or validate.
  static final RegExp _phoneAllowedChars = RegExp(r'^[+\d\s\-()]*$');
  static final RegExp _instagramHandle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');
  static final RegExp _instagramUrl = RegExp(
    r'^https://(?:www\.)?instagram\.com/[A-Za-z0-9._/]{1,60}$',
  );

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // phone
  late final CurvedAnimation _anim2; // instagram
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws ("widget is about to or has been
  // unmounted"). Hold the keepAlive manager reference instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM-1/-2: ref-counted screenshot + iOS app-switcher-snapshot guard.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.42);
    _anim1 = _curve(0.08, 0.52);
    _anim2 = _curve(0.18, 0.62);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(Master master) {
    if (_initialized) return;
    _initialized = true;

    _origPhone = master.phoneNumber ?? '';
    _origInstagram = master.instagram ?? '';

    _phone = TextEditingController(text: _origPhone);
    _instagram = TextEditingController(text: _origInstagram);

    for (final c in _dirtyTrackedControllers) {
      c.addListener(_onFormChanged);
    }

    _controller.forward();
  }

  @override
  void dispose() {
    _screenProtection.release();
    if (_initialized) {
      for (final c in _dirtyTrackedControllers) {
        c.removeListener(_onFormChanged);
      }
      for (final c in _editableControllers) {
        c.dispose();
      }
    }
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _animFooter.dispose();
    _controller.dispose();
    _dirty.dispose();
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_phone, _instagram];

  // Controllers whose changes drive the dirty flag. Instagram is excluded
  // when [ContactsEditScreen.showInstagram] is false — the field is not
  // rendered so it can never be edited, and the save overlay always
  // preserves the cached value regardless (see [_save]).
  List<TextEditingController> get _dirtyTrackedControllers =>
      widget.showInstagram
      ? <TextEditingController>[_phone, _instagram]
      : <TextEditingController>[_phone];

  // PERF (P2): recompute the dirty flag only — no setState, so the form subtree
  // and its animation wrappers are not rebuilt on every keystroke.
  void _onFormChanged() {
    _dirty.value = _isDirty;
  }

  bool get _isDirty =>
      _initialized &&
      (_phone.text.trim() != _origPhone ||
          (widget.showInstagram && _instagram.text.trim() != _origInstagram));

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _clearServerError(String fieldName) {
    if (_fieldErrors.containsKey(fieldName)) {
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(
          Map<String, String>.from(_fieldErrors)..remove(fieldName),
        );
      });
    }
  }

  String? _validatePhone(String? v) {
    final serverErr = _fieldErrors['phoneNumber'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errPhoneRequired;
    }
    if (v.trim().length > _phoneMax) {
      return AppLocalizations.of(context).errPhoneTooLongEdit;
    }
    if (!_phoneAllowedChars.hasMatch(v.trim())) {
      return AppLocalizations.of(context).errPhoneInvalidEdit;
    }
    return null;
  }

  String? _validateInstagram(String? v) {
    final serverErr = _fieldErrors['instagram'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) return null; // optional
    if (!_instagramHandle.hasMatch(v.trim()) &&
        !_instagramUrl.hasMatch(v.trim())) {
      return AppLocalizations.of(context).masterEditInstagramError;
    }
    return null;
  }

  bool _validateAndUpdateErrors() {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _errPhone = _validatePhone(_phone.text);
      _errInstagram = widget.showInstagram
          ? _validateInstagram(_instagram.text)
          : null;
    });
    return ok;
  }

  Future<void> _save(Master cached) async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errPhone = null;
      _errInstagram = null;
    });

    if (!_validateAndUpdateErrors()) {
      if (mounted) {
        showErrorSnack(
          context,
          AppLocalizations.of(context).editValidationSummary,
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      // CRITICAL: merge phone + instagram onto the cached name + bio so the
      // PATCH never clears the firstName/lastName/bio fields this page does not
      // edit. When [ContactsEditScreen.showInstagram] is false the Instagram
      // field is never rendered/edited — send the cached value verbatim so a
      // SALON_MASTER's phone-only save never clears it.
      //
      // `masterType: cached.type` also picks the endpoint that actually
      // admits the caller's role — see [HttpMasterRepository.updateMyProfile]'s
      // doc. Without it, this shared screen sent every SALON_MASTER save to
      // the INDEPENDENT_MASTER-only endpoint, which 403'd.
      await ref
          .read(masterRepositoryProvider)
          .updateMyProfile(
            MasterUpdate(
              firstName: cached.firstName,
              lastName: cached.lastName,
              bio: cached.bio ?? '',
              contactPhone: _phone.text.trim(),
              instagram: widget.showInstagram
                  ? _instagram.text.trim()
                  : (cached.instagram ?? ''),
              // Preserve the cached professional title — this page does not
              // edit it; passing '' would clear it server-side.
              professionalTitle: cached.professionalTitle ?? '',
              masterType: cached.type,
            ),
          );

      if (!mounted) return;
      ref.invalidate(masterProfileProvider);
      showSuccessSnack(context, AppLocalizations.of(context).savedSnackbar);
      context.go(masterHomeRouteFor(cached.type));
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateAndUpdateErrors();
      if (f.fieldErrors.isEmpty) {
        // Localized only — the raw backend serverMessage can be
        // untranslated/technical and must not reach this VelvetSnack
        // (mobile-security, 2026-08). f.userMessage() already returns the
        // localized errValidation copy for ValidationFailure.
        showErrorSnack(context, f.userMessage(context));
      }
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'contacts save unexpected error',
          name: 'feature.master.edit.contacts',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      showErrorSnack(context, AppLocalizations.of(context).errUnknown);
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final masterAsync = ref.watch(masterProfileProvider);
    masterAsync.whenData<void>(_maybeInit);

    final cached = masterAsync.value;
    if (!_initialized || cached == null) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SectionScaffold(
      title: l10n.contactsTitle,
      backKey: const Key('btn-back-contacts'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(masterMenuRouteFor(cached.type));
        }
      },
      footer: _reveal(
        _animFooter,
        ValueListenableBuilder<bool>(
          valueListenable: _dirty,
          builder: (context, dirty, _) => NeumorphicButton(
            key: const Key('btn-save-contacts'),
            label: l10n.masterSaveButton,
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: (!_saving && dirty) ? () => _save(cached) : null,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _reveal(
              _anim0,
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.lg,
                ),
                child: Text(l10n.contactsSubheading, style: VelvetText.body()),
              ),
            ),
            _reveal(
              _anim1,
              FormField<String>(
                key: const Key('field-phone'),
                initialValue: _phone.text,
                validator: (_) => _validatePhone(_phone.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.phoneLabel,
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const <UaPhoneInputFormatter>[
                      UaPhoneInputFormatter(),
                    ],
                    hint: '+380 __ ___ __ __',
                    errorText: _errPhone,
                    helperText: l10n.phonePrivacyNote,
                    onChanged: (v) {
                      _clearServerError('phoneNumber');
                      field.didChange(v);
                      final next = _validatePhone(_phone.text);
                      if (next != _errPhone) {
                        setState(() => _errPhone = next);
                      }
                    },
                  );
                },
              ),
            ),
            if (widget.showInstagram) ...<Widget>[
              const SizedBox(height: VelvetSpacing.lg),
              _reveal(
                _anim2,
                FormField<String>(
                  key: const Key('field-instagram'),
                  initialValue: _instagram.text,
                  validator: (_) => _validateInstagram(_instagram.text),
                  builder: (FormFieldState<String> field) {
                    return VelvetField(
                      label: l10n.instagramLabel,
                      controller: _instagram,
                      enabled: !_saving,
                      optional: true,
                      prefixText: '@',
                      hint: l10n.masterEditInstagramHint,
                      errorText: _errInstagram,
                      onChanged: (v) {
                        _clearServerError('instagram');
                        field.didChange(v);
                        final next = _validateInstagram(_instagram.text);
                        if (next != _errInstagram) {
                          setState(() => _errInstagram = next);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
