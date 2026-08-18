// Phase G — [WishlistEntryLabels.bookCtaLabel].
//
// Pins the ONE thing `wishlist_rebook.dart`'s Phase G correction depends on
// for its copy: the filled CTA reads «Записатись» for a MASTER row (unchanged)
// and «Обрати майстра» for a SALON row (new — tapping it does not book
// anything by itself, it opens the salon's masters tab filtered to the
// performing masters). Both wish-list surfaces (compact card + full row) call
// this rather than branching on `sourceType` themselves — see the extension's
// own doc comment.
//
// Layer: pure unit — no widget pump needed; `AppLocalizations` is resolved
// directly via the generated `lookupAppLocalizations`, same pattern as
// `login_screen_test.dart` / `pricing_field_test.dart`.

import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_entry_labels.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const WishlistService _masterEntry = WishlistService(
  masterServiceId: 'ms-1',
  masterId: 'm-1',
  serviceName: 'Манікюр',
  masterName: 'Олена Ковальчук',
  durationMinutes: 60,
  priceDisplay: '600 ₴',
);

const WishlistService _salonEntry = WishlistService(
  sourceType: WishlistSourceType.salon,
  salonId: 's-1',
  salonName: 'Салон «Вельвет»',
  serviceDefId: 'svc-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  priceDisplay: '600 ₴',
);

void main() {
  group('bookCtaLabel', () {
    test('a MASTER row keeps the existing wishlistBookCta label', () {
      expect(_masterEntry.bookCtaLabel(_l10n), _l10n.wishlistBookCta);
      expect(_masterEntry.bookCtaLabel(_l10n), 'Записатись');
    });

    test('a SALON row uses wishlistChooseMasterCta, NOT wishlistBookCta — '
        'tapping it does not book anything by itself', () {
      expect(_salonEntry.bookCtaLabel(_l10n), _l10n.wishlistChooseMasterCta);
      expect(_salonEntry.bookCtaLabel(_l10n), 'Обрати майстра');
      expect(_salonEntry.bookCtaLabel(_l10n), isNot(_l10n.wishlistBookCta));
    });
  });
}
