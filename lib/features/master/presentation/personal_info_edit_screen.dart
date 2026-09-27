// Особисті дані — the personal-info slice of the retired monolithic edit form:
// avatar editor + "Змінити фото" caption, then Ім'я (required), Прізвище
// (required) and Про себе (multiline bio, max 2000, live counter). A pinned
// "Зберегти" CTA sits at the bottom.
//
// CRITICAL correctness constraint — do NOT clear sibling fields:
//   [MasterRepository.updateMyProfile] always sends firstName/lastName/bio/
//   instagram, and an empty string CLEARS the field server-side. This page only
//   edits name + bio, so on save it builds the FULL [MasterUpdate] from the
//   current cached [masterProfileProvider] master, overlaying ONLY firstName/
//   lastName/bio and preserving the cached phone + instagram. Otherwise Save
//   would wipe Instagram.
//
// Save flow: validate → updateMyProfile(merged) → invalidate
// masterProfileProvider → saved VelvetSnack → pop.
//
// Multi-role reuse (SALON_MASTER's own «Особисті дані», `/staff/edit/
// personal`): this screen is pushed by BOTH the INDEPENDENT_MASTER settings
// hub (`/master/edit/personal`) and the SALON_MASTER one (`/staff/edit/
// personal`) — same widget, same `MasterUpdate` shape. The backend has TWO
// single-role endpoints, not one shared one: `PATCH
// /independent-masters/me/profile` admits only INDEPENDENT_MASTER
// (`IndependentMasterController.java:93-94`) and `PATCH /masters/me/profile`
// admits only SALON_MASTER (`MasterController.java:486-487`) — the ONLY
// thing "admits both roles" is `UserService.updateMasterProfile`'s
// defence-in-depth role union, which neither `@PreAuthorize` alone
// satisfies. This save therefore passes `masterType: cached.type` (the
// ALREADY-LOADED [Master.type]) on the [MasterUpdate] it builds, so
// [HttpMasterRepository.updateMyProfile] PATCHes whichever endpoint the
// caller's actual role admits — see that method's doc for the branch (a
// bare unbranched call was a HIGH bug: every SALON_MASTER save 403'd).
// The post-save `context.go` and the onBack no-pop fallback separately
// resolve their destination from the SAME `cached.type` rather than
// hardcoding the INDEPENDENT_MASTER route — see the promoted
// `masterHomeRouteFor`/`masterMenuRouteFor` in `master_role_routes.dart`
// (shared with `contacts_edit_screen.dart`, which has the identical need).
// Mirrors the established `roleHomePath`-on-a-shared-screen pattern
// (`settings_screen.dart`'s own fallback).
//
// Server field errors: [ValidationFailure.fieldErrors] keyed by field name.
// Each validator checks the server error first, then the local rule.
//
// Avatar edit is deferred — tapping the camera badge shows a "Незабаром…"
// info VelvetSnack (photo upload ships later).
//
// Security: ScreenProtector active in release builds (PII-bearing screen).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// personal_info_edit_screen.dart` — ported with the real notifier + repository.

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
import 'package:beautica_mobile/shared/validators/name_validator.dart';

import 'master_profile_notifier.dart';
import 'master_role_routes.dart';
import 'widgets/section_scaffold.dart';

/// Personal-info edit page (firstName + lastName + bio).
class PersonalInfoEditScreen extends ConsumerStatefulWidget {
  const PersonalInfoEditScreen({super.key});

  @override
  ConsumerState<PersonalInfoEditScreen> createState() =>
      _PersonalInfoEditScreenState();
}

class _PersonalInfoEditScreenState extends ConsumerState<PersonalInfoEditScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _professionalTitle;
  late final TextEditingController _bio;

  bool _initialized = false;

  String _origFirstName = '';
  String _origLastName = '';
  String _origProfessionalTitle = '';
  String _origBio = '';

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errFirstName;
  String? _errLastName;
  String? _errProfessionalTitle;
  String? _errBio;

  // PERF (P2): drives the Save button's enabled state in isolation. Typing a
  // keystroke updates this notifier instead of calling setState(() {}) on the
  // whole form — so the per-field reveal animation wrappers (FadeTransition /
  // SlideTransition) are NOT rebuilt on every character. Only the footer
  // (wrapped in a ValueListenableBuilder) reacts to dirty-state flips.
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  static const int _bioMax = 2000;

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // avatar
  late final CurvedAnimation _anim1; // firstName
  late final CurvedAnimation _anim2; // lastName
  late final CurvedAnimation _anim3; // professionalTitle
  late final CurvedAnimation _anim4; // bio
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  static final TextStyle _changePhotoStyle = VelvetText.label().copyWith(
    color: BrandColors.accent,
    letterSpacing: 0.4,
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
      duration: const Duration(milliseconds: 1000),
    );
    _anim0 = _curve(0.00, 0.40);
    _anim1 = _curve(0.06, 0.48);
    _anim2 = _curve(0.14, 0.56);
    _anim3 = _curve(0.22, 0.64);
    _anim4 = _curve(0.30, 0.72);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(Master master) {
    if (_initialized) return;
    _initialized = true;

    _origFirstName = master.firstName;
    _origLastName = master.lastName;
    _origProfessionalTitle = master.professionalTitle ?? '';
    _origBio = master.bio ?? '';

    _firstName = TextEditingController(text: _origFirstName);
    _lastName = TextEditingController(text: _origLastName);
    _professionalTitle = TextEditingController(text: _origProfessionalTitle);
    _bio = TextEditingController(text: _origBio);

    for (final c in _editableControllers) {
      c.addListener(_onFormChanged);
    }

    _controller.forward();
  }

  @override
  void dispose() {
    _screenProtection.release();
    if (_initialized) {
      for (final c in _editableControllers) {
        c.removeListener(_onFormChanged);
        c.dispose();
      }
    }
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _animFooter.dispose();
    _controller.dispose();
    _dirty.dispose();
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_firstName, _lastName, _professionalTitle, _bio];

  // PERF (P2): recompute the dirty flag only — no setState, so the form subtree
  // and its animation wrappers are not rebuilt on every keystroke. The footer's
  // ValueListenableBuilder rebuilds just the Save button when the flag flips.
  void _onFormChanged() {
    _dirty.value = _isDirty;
  }

  bool get _isDirty =>
      _initialized &&
      (_firstName.text.trim() != _origFirstName ||
          _lastName.text.trim() != _origLastName ||
          _professionalTitle.text.trim() != _origProfessionalTitle ||
          _bio.text.trim() != _origBio);

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

  String? _validateFirstName(String? v) {
    final serverErr = _fieldErrors['firstName'];
    if (serverErr != null) return serverErr;
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) {
      return l10n.errNameRequired;
    }
    if (v.trim().length > 100) {
      return l10n.errNameTooLong;
    }
    if (nameContainsDigit(v)) {
      return l10n.errFirstNameHasDigit;
    }
    return null;
  }

  String? _validateLastName(String? v) {
    final serverErr = _fieldErrors['lastName'];
    if (serverErr != null) return serverErr;
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) {
      return l10n.errNameRequired;
    }
    if (v.trim().length > 100) {
      return l10n.errNameTooLong;
    }
    if (nameContainsDigit(v)) {
      return l10n.errLastNameHasDigit;
    }
    return null;
  }

  String? _validateProfessionalTitle(String? v) {
    final serverErr = _fieldErrors['professionalTitle'];
    if (serverErr != null) return serverErr;
    if (v != null && v.trim().length > 100) {
      return AppLocalizations.of(context).professionalTitleMaxLength;
    }
    return null;
  }

  String? _validateBio(String? v) {
    final serverErr = _fieldErrors['bio'];
    if (serverErr != null) return serverErr;
    if (v != null && v.length > _bioMax) {
      return AppLocalizations.of(context).errBioTooLong;
    }
    return null;
  }

  bool _validateAndUpdateErrors() {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _errFirstName = _validateFirstName(_firstName.text);
      _errLastName = _validateLastName(_lastName.text);
      _errProfessionalTitle = _validateProfessionalTitle(
        _professionalTitle.text,
      );
      _errBio = _validateBio(_bio.text);
    });
    return ok;
  }

  Future<void> _save(Master cached) async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errFirstName = null;
      _errLastName = null;
      _errProfessionalTitle = null;
      _errBio = null;
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
      // CRITICAL: merge name + professionalTitle + bio onto the cached phone +
      // instagram so the PATCH never clears the sibling contact fields this page
      // does not edit.
      await ref
          .read(masterRepositoryProvider)
          .updateMyProfile(
            MasterUpdate(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              professionalTitle: _professionalTitle.text.trim(),
              bio: _bio.text.trim(),
              contactPhone: cached.phoneNumber ?? '',
              instagram: cached.instagram ?? '',
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
          'personal-info save unexpected error',
          name: 'feature.master.edit.personal',
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

  void _onAvatarTap() {
    if (!mounted) return;
    showInfoSnack(context, AppLocalizations.of(context).snackbarAvatarSoon);
  }

  String _buildInitials() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    final a = first.isNotEmpty ? first[0].toUpperCase() : '';
    final b = last.isNotEmpty ? last[0].toUpperCase() : '';
    final initials = '$a$b'.trim();
    return initials.isEmpty ? '?' : initials;
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
      title: l10n.personalInfoTitle,
      backKey: const Key('btn-back-personal'),
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
            key: const Key('btn-save-personal'),
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
              Column(
                children: <Widget>[
                  Center(
                    // PERF (P2): only the avatar initials need to follow the
                    // name keystrokes, so listen to just the two name
                    // controllers here instead of rebuilding the whole form.
                    child: ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        _firstName,
                        _lastName,
                      ]),
                      builder: (context, _) => NeumorphicAvatarEditor(
                        state: AvatarEditState.pristine,
                        initials: _buildInitials(),
                        onTap: _onAvatarTap,
                      ),
                    ),
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  Text(
                    l10n.changePhotoCaption,
                    style: _changePhotoStyle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  Divider(
                    thickness: 0.6,
                    color: BrandColors.accent.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: VelvetSpacing.md),
                ],
              ),
            ),
            _reveal(
              _anim1,
              FormField<String>(
                key: const Key('field-firstName'),
                initialValue: _firstName.text,
                validator: (_) => _validateFirstName(_firstName.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.firstNameLabel,
                    controller: _firstName,
                    enabled: !_saving,
                    hint: l10n.registerFirstNamePlaceholder,
                    errorText: _errFirstName,
                    onChanged: (v) {
                      _clearServerError('firstName');
                      field.didChange(v);
                      final next = _validateFirstName(_firstName.text);
                      if (next != _errFirstName) {
                        setState(() => _errFirstName = next);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            _reveal(
              _anim2,
              FormField<String>(
                key: const Key('field-lastName'),
                initialValue: _lastName.text,
                validator: (_) => _validateLastName(_lastName.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.lastNameLabel,
                    controller: _lastName,
                    enabled: !_saving,
                    hint: l10n.registerLastNamePlaceholder,
                    errorText: _errLastName,
                    onChanged: (v) {
                      _clearServerError('lastName');
                      field.didChange(v);
                      final next = _validateLastName(_lastName.text);
                      if (next != _errLastName) {
                        setState(() => _errLastName = next);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            _reveal(
              _anim3,
              FormField<String>(
                key: const Key('field-professionalTitle'),
                initialValue: _professionalTitle.text,
                validator: (_) =>
                    _validateProfessionalTitle(_professionalTitle.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.professionalTitleLabel,
                    controller: _professionalTitle,
                    enabled: !_saving,
                    hint: l10n.professionalTitleHint,
                    maxLength: 100,
                    showCounter: true,
                    errorText: _errProfessionalTitle,
                    onChanged: (v) {
                      _clearServerError('professionalTitle');
                      field.didChange(v);
                      final next = _validateProfessionalTitle(
                        _professionalTitle.text,
                      );
                      if (next != _errProfessionalTitle) {
                        setState(() => _errProfessionalTitle = next);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            _reveal(
              _anim4,
              FormField<String>(
                key: const Key('field-bio'),
                initialValue: _bio.text,
                validator: (_) => _validateBio(_bio.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.bioLabel,
                    controller: _bio,
                    enabled: !_saving,
                    hint: l10n.masterEditBioHint,
                    maxLines: 5,
                    maxLength: _bioMax,
                    showCounter: true,
                    errorText: _errBio,
                    onChanged: (v) {
                      _clearServerError('bio');
                      field.didChange(v);
                      final next = _validateBio(_bio.text);
                      if (next != _errBio) {
                        setState(() => _errBio = next);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
