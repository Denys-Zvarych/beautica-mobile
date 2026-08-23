// Phase 264 — WalkInGuestStepScreen: the FIRST screen of the routed walk-in
// chain (`/master/bookings/new`), replacing the old single-screen wizard's
// `client` step.
//
// REUSE-FIRST: this screen contains no new form. It is a thin
// `Scaffold` + [BookingTopBar] + [ClientStep] (unchanged, `booking_wizard_
// steps.dart:269`) — the exact widget the retiring wizard and the salon
// wizard both already use. [ClientStep] carries its own inline «Далі» CTA,
// so this screen needs no separate footer (mirrors the old wizard's
// `_buildBottomBar` returning `null` for the `client` step).
//
// D8 (phase-264) — this screen does NOT watch `masterProfileProvider`. Only
// the NEXT screen ([WalkInServiceStepScreen]) needs the master (it builds
// [BookingSlotPickerArgs.master]); watching it here would put a network
// error state in front of a pure form.
//
// D5 — forward navigation is `context.push`, never `context.go` or
// `pushReplacement`: popping back here from any later screen in the chain
// must land on this screen's LIVE `State`, with the three
// [TextEditingController]s (and their typed text) intact. See this class's
// own `State` for why the controllers are owned here, not by a provider.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/create_master_booking_request.dart' show WalkInGuest;
import 'widgets/booking_top_bar.dart';
import 'widgets/booking_wizard_steps.dart' show ClientStep, toE164UaPhone;

/// «Новий запис» step 1 — collects the walk-in guest's identity
/// (ім'я/прізвище/телефон) via the shared [ClientStep].
class WalkInGuestStepScreen extends ConsumerStatefulWidget {
  const WalkInGuestStepScreen({super.key});

  @override
  ConsumerState<WalkInGuestStepScreen> createState() =>
      _WalkInGuestStepScreenState();
}

class _WalkInGuestStepScreenState extends ConsumerState<WalkInGuestStepScreen> {
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// «Далі» — mints a [WalkInGuest] from the typed fields (normalising the
  /// phone through [toE164UaPhone], the same screen-boundary normaliser
  /// [ClientStep]'s own `_canAdvance` gate already used to enable this CTA)
  /// and pushes it as `extra` onto [RouteNames.masterBookingNewServices].
  ///
  /// `context.push`, never `context.go`/`pushReplacement` — D5 of the phase
  /// doc: this screen's `State` (and its controllers) must stay mounted
  /// underneath so a pop back from the service step — or any later screen —
  /// restores the typed text.
  void _onNext() {
    // Defensive — unreachable via the normal flow: `ClientStep`'s own
    // `_canAdvance` gate disables its «Далі» button until the phone
    // normalizes and both names are non-empty.
    final String? phone = toE164UaPhone(_phoneCtrl.text);
    if (phone == null) return;
    final String firstName = _firstNameCtrl.text.trim();
    final String lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) return;

    context.push(
      RouteNames.masterBookingNewServices,
      extra: WalkInGuest(name: firstName, surname: lastName, phone: phone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: l10n.masterCreateBookingTitle,
              backSemantics: l10n.registerBackStep,
              backKey: const Key('walk-in-guest-back'),
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ClientStep(
                firstNameCtrl: _firstNameCtrl,
                lastNameCtrl: _lastNameCtrl,
                phoneCtrl: _phoneCtrl,
                onNext: _onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
