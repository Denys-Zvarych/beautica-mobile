// M510 — the card's phone control: the chip content ([PhoneLink]) and the
// call / copy sheet ([showPhoneSheet]), ClientCardVariants `PhoneLink` +
// `showPhoneSheet`.
//
//   «Зателефонувати» → `openExternalUri(canonicalTelUri(phone))` — the booking
//   detail's `_callGuest` precedent (strict tel allow-list, generic error snack
//   on failure). «Скопіювати номер» → clipboard + «Номер скопійовано».
//
// The sheet is the shipped VelvetTouch sheet (`showVelvetSheet` →
// `showModalBottomSheetOnce`, `VelvetSheetChrome`, `VelvetSheetOptionRow`).
// The number is NEVER logged.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/utils/open_external_uri.dart';
import 'package:beautica_mobile/shared/utils/phone_uri.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';

const Key kPhoneSheetCallKey = Key('client-phone-sheet-call');
const Key kPhoneSheetCopyKey = Key('client-phone-sheet-copy');

/// The chip content: a call glyph and the number.
class PhoneLink extends StatelessWidget {
  const PhoneLink({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.call_rounded, size: 16, color: BrandColors.accentDeep),
        const SizedBox(width: 6),
        Flexible(
          // DISPLAY only: the UA input mask («+380 67 123 45 67»), the same
          // transform the add-phone field and the booking detail apply.
          child: Text(
            UaPhoneInputFormatter.display(phone),
            style: clientBody(
              14,
              weight: FontWeight.w700,
              color: BrandColors.accentDeep,
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the call / copy sheet for [phone]. [clipboard] is the app's one
/// clipboard writer (`clipboardServiceProvider`).
Future<void> showPhoneSheet(
  BuildContext context,
  String phone, {
  required ClipboardService clipboard,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showVelvetSheet<void>(
    context,
    builder: (BuildContext sheet) => VelvetSheetChrome(
      // DISPLAY only — call / copy below keep the canonical [phone].
      title: UaPhoneInputFormatter.display(phone),
      children: <Widget>[
        VelvetSheetOptionRow(
          tapKey: kPhoneSheetCallKey,
          label: l10n.clientCall,
          leading: const Icon(
            Icons.call_rounded,
            size: 20,
            color: BrandColors.accentDeep,
          ),
          onTap: () {
            Navigator.of(sheet).pop();
            openExternalUri(
              context,
              canonicalTelUri(phone),
              errorMessage: l10n.errUnknown,
              mode: LaunchMode.platformDefault,
              logName: 'feature.clients.card',
            );
          },
        ),
        VelvetSheetOptionRow(
          tapKey: kPhoneSheetCopyKey,
          label: l10n.clientCopyPhone,
          leading: const Icon(
            Icons.copy_rounded,
            size: 20,
            color: BrandColors.accentDeep,
          ),
          onTap: () async {
            Navigator.of(sheet).pop();
            final bool copied = await clipboard.copyText(
              phone.replaceAll(' ', ''),
            );
            if (!context.mounted) return;
            if (copied) {
              showSuccessSnack(context, l10n.clientPhoneCopied);
            } else {
              showErrorSnack(context, l10n.errUnknown);
            }
          },
        ),
      ],
    ),
  );
}
