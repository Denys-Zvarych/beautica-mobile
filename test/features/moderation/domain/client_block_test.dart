// Phase 425 (mobile-security LOW) — ClientBlock.toString is redacting: id +
// kind only, never the name, avatar URL or masked phone.

import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toString prints id + kind only', () {
    final ClientBlock block = ClientBlock(
      id: 'blk-7',
      kind: ClientBlockKind.guest,
      displayName: 'Ірина Савчук',
      avatarUrl: 'https://cdn.test/secret-avatar.jpg',
      maskedPhone: '+380 •• ••• 12 34',
      createdAt: DateTime.utc(2026, 10, 28),
    );

    final String out = block.toString();

    expect(out, 'ClientBlock(id: blk-7, kind: GUEST)');
    expect(out, isNot(contains('Ірина')));
    expect(out, isNot(contains('Савчук')));
    expect(out, isNot(contains('12 34')));
    expect(out, isNot(contains('secret-avatar')));
    expect('$block', out, reason: 'string interpolation goes through it too');
  });

  test('a CLIENT row has no masked phone', () {
    final ClientBlock block = ClientBlock(
      id: 'blk-8',
      kind: ClientBlockKind.client,
      displayName: 'Олена',
      createdAt: DateTime.utc(2026, 10, 28),
    );
    expect(block.maskedPhone, isNull);
    expect(block.toString(), 'ClientBlock(id: blk-8, kind: CLIENT)');
  });
}
