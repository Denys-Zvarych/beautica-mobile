// Phase 361 — pixel lock for the «Мої салони» hub header (back · title · bell).
//
// The hub's private `_BellButton` mirror was deleted in favour of the promoted
// shared `NotificationBellButton`. This golden was captured BEFORE that
// rewire (against the private mirror) and re-run unchanged AFTER it: with
// `hasUnread == false` the header must stay pixel-identical.
//
// The unread variant is covered by `notification_bell_button_golden_test.dart`
// and by the connected-bell widget tests.

import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';

import 'helpers/golden_pump.dart';

class _StubMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'salon-1', name: 'Вельвет', isPrimary: true),
  ];
}

void main() {
  const double width = 360;

  goldenTest(
    'my_salons hub header (dotless bell)',
    fileName: 'my_salons_hub_header_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 640)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: <Object>[mySalonsProvider.overrideWith(_StubMySalons.new)],
    ),
    builder: () => const MySalonsScreen(),
  );
}
