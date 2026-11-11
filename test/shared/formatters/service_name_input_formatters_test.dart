// Audit NEW (feat/duplicate-services) — [serviceNameInputFormatters], the
// client mirror of the backend `ServiceNameConstraints.NAME_REGEX`.

import 'package:beautica_mobile/shared/formatters/service_name_input_formatters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [input] through the formatter chain as one paste into an empty field.
String _format(String input) {
  TextEditingValue value = TextEditingValue(
    text: input,
    selection: TextSelection.collapsed(offset: input.length),
  );
  for (final TextInputFormatter f in serviceNameInputFormatters) {
    value = f.formatEditUpdate(TextEditingValue.empty, value);
  }
  return value.text;
}

void main() {
  group('allow-list keeps', () {
    test('letters of any script and digits', () {
      expect(_format('Манікюр 2'), 'Манікюр 2');
      expect(_format('Nails éè 3D'), 'Nails éè 3D');
      expect(_format('ქართული'), 'ქართული');
    });

    test('a combining mark: decomposed «й» keeps U+0306', () {
      const String decomposed = 'Ча\u0438\u0306'; // «Чай», «й» = «и» + U+0306
      final String out = _format(decomposed);
      expect(out, decomposed);
      expect(out.codeUnits.last, 0x0306);
    });

    test('«№» and every allowed punctuation mark', () {
      const String punct = "- – — . , ' ’ ʼ ( ) + / & « » \" № : % ! ?";
      expect(_format(punct), punct);
      expect(_format('Пакет №2: 50%!'), 'Пакет №2: 50%!');
    });
  });

  group('strips', () {
    test('emoji', () {
      expect(_format('Манікюр 💅✨'), 'Манікюр ');
    });

    test('symbols outside the list', () {
      expect(
        _format(r'a@b#c$d^e*f=g~h<i>j[k]l{m}n|o\p_q;r`s'),
        'abcdefghijklmnopqrs',
      );
      expect(_format('©®™€₴°§'), '');
    });

    test('the four Hangul fillers (Lo letters that render blank)', () {
      expect(_format('a\u115Fb\u1160c\u3164d\uFFA0e'), 'abcde');
    });

    test('control characters and non-space whitespace', () {
      expect(_format('a\tb\nc\u200Bd'), 'abcd');
    });
  });

  test('the list is unmodifiable', () {
    expect(
      () => serviceNameInputFormatters.add(
        FilteringTextInputFormatter.digitsOnly,
      ),
      throwsUnsupportedError,
    );
  });
}
