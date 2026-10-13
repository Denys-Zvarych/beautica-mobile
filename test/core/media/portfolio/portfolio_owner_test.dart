// Phase 403 audit S2 — `PortfolioOwner.toString()` is redacted (Riverpod
// copies a family argument's `toString()` into provider names and error
// messages), while equality / hashCode stay VALUE-based (family keys).

import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:flutter_test/flutter_test.dart';

const String _salonId = 'salon-3f2a9c';
const String _masterId = 'master-7b1e44';

void main() {
  test('toString never embeds the salon id', () {
    final String s = const PortfolioOwner.salon(_salonId).toString();
    expect(s, isNot(contains(_salonId)));
    expect(s, 'PortfolioOwner.salon(<redacted>)');
  });

  test('toString never embeds the master id', () {
    final String s = const PortfolioOwner.masterSelf(_masterId).toString();
    expect(s, isNot(contains(_masterId)));
    expect(s, 'PortfolioOwner.masterSelf(<redacted>)');
  });

  test('the family provider name carries no id either', () {
    expect(
      portfolioProvider(const PortfolioOwner.salon(_salonId)).toString(),
      isNot(contains(_salonId)),
    );
  });

  test('equality and hashCode stay value-based', () {
    // Non-const instances, so `identical` cannot stand in for `==`.
    final PortfolioOwner a = PortfolioOwner.salon(_salonId.substring(0));
    final PortfolioOwner b = PortfolioOwner.salon('salon-3f2a9c'.toString());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const PortfolioOwner.salon('other')));
    expect(
      const PortfolioOwner.salon('x'),
      isNot(const PortfolioOwner.masterSelf('x')),
    );
    expect(
      portfolioProvider(a),
      portfolioProvider(b),
      reason: 'equal owners key the same family member',
    );
  });
}
