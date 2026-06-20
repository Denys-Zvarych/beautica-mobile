// CLIENT Локація — the location slice of the client profile: a three-level
// locality cascade (Область → Місто → Район, district required only when a
// chosen city subdivides). A pinned "Зберегти" CTA sits at the bottom.
//
// For a CLIENT only the locality (oblast → city → district) is meaningful, so
// the free-text address fields (Вулиця / Будинок / Примітка) are NOT shown,
// collected, validated, or sent — the backend preserves any existing address
// values because the PATCH omits those keys.
//
// 1:1 transcription of the master [LocationEditScreen] with the approved CLIENT
// modifications:
//   • City is OPTIONAL — the master's "city required when editing address" rule
//     is DROPPED. A CLIENT may save with no city selected (the backend's
//     validateClientLocality permits a null city for clients).
//   • The free-text address fields are omitted entirely (client-only change).
//   • District is required ONLY when a city with districts is chosen.
//   • Save goes through [ClientProfileRepository.updateMyProfile] with
//     `touchesLocation: true` (PATCH /users/me) — the same endpoint as the other
//     client edit screens — sending the locality slice with a possibly-null
//     cityId and no address keys.
//
// Pre-population: the User profile carries oblastId / cityId / districtId, so the
// cascade seeds its oblast selection directly from user.oblastId and loads just
// that one oblast's cities to resolve the city/district objects — a single
// targeted fetch, not a scan of every oblast. The cascade seed runs
// asynchronously in a microtask so setState is never called during build.
//
// Security: ScreenProtector active in release builds (PII-bearing screen).

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
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';

/// CLIENT location edit page (optional locality cascade only).
class ClientLocationEditScreen extends ConsumerStatefulWidget {
  const ClientLocationEditScreen({super.key});

  @override
  ConsumerState<ClientLocationEditScreen> createState() =>
      _ClientLocationEditScreenState();
}

class _ClientLocationEditScreenState
    extends ConsumerState<ClientLocationEditScreen>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;

  Oblast? _selectedOblast;
  City? _selectedCity;
  CityDistrict? _selectedDistrict;

  String? _origCityId;
  String? _origOblastId;
  String? _origDistrictId;

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errDistrict;

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading + cascade
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x rule).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.46);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(User user) {
    if (_initialized) return;
    _initialized = true;

    _origOblastId = user.oblastId;
    _origCityId = user.cityId;
    _origDistrictId = user.districtId;

    _controller.forward();

    if (user.oblastId != null) {
      Future.microtask(() => _prePopulateLocality(user));
    }
  }

  /// Resolves the [Oblast], [City] and [CityDistrict] objects from the cached
  /// oblastId / cityId / districtId.
  ///
  /// The User profile carries the oblastId directly, so the oblast is matched in
  /// the oblast list by id and only that one oblast's cities are fetched to
  /// resolve the city (and, if it subdivides, the district) — a single targeted
  /// fetch rather than a scan of every oblast's city list.
  Future<void> _prePopulateLocality(User user) async {
    Oblast? matchedOblast;
    City? matchedCity;
    CityDistrict? matchedDistrict;

    try {
      final oblastId = user.oblastId;
      if (oblastId != null) {
        final oblasts = await ref.read(oblastListProvider.future);
        for (final o in oblasts) {
          if (o.id == oblastId) {
            matchedOblast = o;
            break;
          }
        }

        final cityId = user.cityId;
        if (matchedOblast != null && cityId != null) {
          final cities = await ref.read(cityListProvider(oblastId).future);
          for (final c in cities) {
            if (c.id == cityId) {
              matchedCity = c;
              break;
            }
          }

          final districtId = user.districtId;
          if (districtId != null &&
              matchedCity != null &&
              matchedCity.hasDistricts) {
            final districts = await ref.read(
              districtListProvider(matchedCity.id).future,
            );
            for (final d in districts) {
              if (d.id == districtId) {
                matchedDistrict = d;
                break;
              }
            }
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'Locality pre-population failed — cascade will be empty',
          name: 'feature.client.edit.location',
          level: 800,
          error: e,
          stackTrace: st,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedOblast = matchedOblast;
      _selectedCity = matchedCity;
      _selectedDistrict = matchedDistrict;
      _origOblastId = matchedOblast?.id;
      _origCityId = matchedCity?.id;
      _origDistrictId = matchedDistrict?.id;
    });
  }

  @override
  void dispose() {
    _screenProtection.release();
    _anim0.dispose();
    _animFooter.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _initialized &&
      (_selectedOblast?.id != _origOblastId ||
          _selectedCity?.id != _origCityId ||
          _selectedDistrict?.id != _origDistrictId);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  /// Returns true when the locality section is valid for a CLIENT.
  ///
  /// CLIENT modification vs master: the city is OPTIONAL (no "city required"
  /// rule). The ONLY local rule is that a district must be chosen when the
  /// selected city subdivides into districts. A server `district` field error
  /// takes precedence and short-circuits to invalid.
  bool _validateLocation() {
    final l10n = AppLocalizations.of(context);

    final serverDistrict = _fieldErrors['district'];
    if (serverDistrict != null) {
      setState(() => _errDistrict = serverDistrict);
      return false;
    }

    final citySelected = _selectedCity != null;
    final cityHasDistricts = _selectedCity?.hasDistricts ?? false;

    // District is required only when a city WITH districts is chosen.
    final String? errDistrict =
        (citySelected && cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;

    setState(() => _errDistrict = errDistrict);

    return errDistrict == null;
  }

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errDistrict = null;
    });

    if (!_validateLocation()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-summary'),
            content: Text(AppLocalizations.of(context).editValidationSummary),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      // CLIENT location is OPTIONAL — send the locality slice with a
      // possibly-null cityId (touchesLocation flags the repository to send the
      // locality keys exactly as carried, null included). The free-text address
      // keys (street / buildingNo / locationNote) are deliberately NOT passed,
      // so the PATCH omits them and the backend preserves any existing values.
      // Name + phone are untouched and preserved server-side too.
      await ref
          .read(clientProfileRepositoryProvider)
          .updateMyProfile(
            ClientProfileUpdate(
              touchesLocation: true,
              cityId: _selectedCity?.id,
              districtId: _selectedDistrict?.id,
            ),
          );

      if (!mounted) return;
      // Re-fetch the session User so clientProfile (derived from authProvider)
      // re-derives the fresh city; then invalidate the edit-seed + profile
      // providers so they re-read from the now-current session.
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      ref.invalidate(clientEditProfileProvider);
      ref.invalidate(clientProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('snackbar-saved'),
          content: Text(AppLocalizations.of(context).savedSnackbar),
        ),
      );
      context.go(RouteNames.clientHome);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateLocation();
      if (f.fieldErrors.isEmpty) {
        final serverMessage = f.serverMessage?.trim();
        final text = (serverMessage != null && serverMessage.isNotEmpty)
            ? serverMessage
            : AppLocalizations.of(context).errValidation;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-error'),
            content: Text(text),
          ),
        );
      }
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(f.userMessage(context))));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'client location save unexpected error',
          name: 'feature.client.edit.location',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).errUnknown)),
      );
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final profileAsync = ref.watch(clientEditProfileProvider);
    profileAsync.whenData<void>(_maybeInit);

    if (!_initialized) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SectionScaffold(
      title: l10n.locationTitle,
      backKey: const Key('btn-back-location'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.clientMenu);
        }
      },
      footer: _reveal(
        _animFooter,
        NeumorphicButton(
          key: const Key('btn-save-location'),
          label: l10n.masterSaveButton,
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: (!_saving && _isDirty) ? _save : null,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.lg,
                  ),
                  child: Text(
                    l10n.locationSubheading,
                    style: VelvetText.body(),
                  ),
                ),
                LocalityCascade(
                  key: const Key('location-cascade'),
                  selectedOblast: _selectedOblast,
                  selectedCity: _selectedCity,
                  selectedDistrict: _selectedDistrict,
                  // District is required (when shown) only because the city has
                  // districts; the city itself is optional for a CLIENT.
                  districtRequired: true,
                  districtError: _errDistrict,
                  onOblast: (oblast) {
                    setState(() {
                      _selectedOblast = oblast;
                      _selectedCity = null;
                      _selectedDistrict = null;
                      _errDistrict = null;
                    });
                  },
                  onCity: (city) {
                    setState(() {
                      _selectedCity = city;
                      _selectedDistrict = null;
                      _errDistrict = null;
                    });
                  },
                  onDistrict: (district) {
                    setState(() {
                      _selectedDistrict = district;
                      if (district != null) _errDistrict = null;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
