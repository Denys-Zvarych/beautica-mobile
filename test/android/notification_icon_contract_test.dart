import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// File-scan guard for the FCM notification small icon
/// (fix/notification-small-icon).
///
/// Bug: no `default_notification_icon` meta-data, so FCM-rendered pushes
/// (app backgrounded / killed) fell back to the opaque launcher icon, which
/// Android masks by ALPHA into a white square.
///
/// The tray rendering itself cannot be asserted in a widget or Patrol test;
/// the manual device smoke covers the visual. This contract pins every config
/// link that makes the icon render: manifest meta-data -> drawable that is an
/// alpha-only white silhouette -> tint color -> shrink-keep rule.
///
/// Files are parsed with a real XML parser (package:xml), so comments are
/// ignored, quote style / attribute order / line breaks do not matter, and
/// `android:` / `tools:` attributes are looked up by namespace URI.
const String _main = 'android/app/src/main';
const String _manifestPath = '$_main/AndroidManifest.xml';
const String _drawablePath = '$_main/res/drawable/ic_stat_beautica.xml';
const String _colorsPath = '$_main/res/values/colors.xml';
const String _keepPath = '$_main/res/raw/keep.xml';

const String _androidNs = 'http://schemas.android.com/apk/res/android';
const String _toolsNs = 'http://schemas.android.com/tools';
const String _aaptNs = 'http://schemas.android.com/aapt';

const String _iconKey =
    'com.google.firebase.messaging.default_notification_icon';
const String _colorKey =
    'com.google.firebase.messaging.default_notification_color';

XmlDocument _parse(String p) {
  final File f = File(p);
  if (!f.existsSync()) throw StateError('missing $p');
  return XmlDocument.parse(f.readAsStringSync());
}

String? _android(XmlElement e, String name) =>
    e.getAttribute(name, namespace: _androidNs);

/// The single `<application>` element of the manifest.
XmlElement _application(XmlDocument manifest) {
  final List<XmlElement> apps = manifest.rootElement
      .findElements('application')
      .toList();
  expect(apps, hasLength(1), reason: 'exactly one <application> element');
  return apps.single;
}

/// `android:resource` of every `<meta-data android:name="key">` in [elements].
List<String> _metaDataResources(Iterable<XmlElement> elements, String key) {
  return elements
      .where(
        (XmlElement e) =>
            e.name.local == 'meta-data' && _android(e, 'name') == key,
      )
      .map((XmlElement e) => _android(e, 'resource') ?? '<no android:resource>')
      .toList();
}

bool _isWhite(String v) {
  final String c = v.trim().toUpperCase();
  return c == '#FFF' ||
      c == '#FFFFFF' ||
      c == '#FFFFFFFF' ||
      c == '@ANDROID:COLOR/WHITE';
}

void main() {
  final XmlDocument manifest = _parse(_manifestPath);
  final XmlDocument drawable = _parse(_drawablePath);
  final XmlDocument colors = _parse(_colorsPath);
  final XmlDocument keep = _parse(_keepPath);

  group('AndroidManifest FCM meta-data', () {
    test('default_notification_icon is declared inside <application> '
        'pointing at @drawable/ic_stat_beautica', () {
      expect(
        _metaDataResources(_application(manifest).childElements, _iconKey),
        <String>['@drawable/ic_stat_beautica'],
      );
    });

    test('default_notification_color is declared inside <application> '
        'pointing at @color/notification_accent', () {
      expect(
        _metaDataResources(_application(manifest).childElements, _colorKey),
        <String>['@color/notification_accent'],
      );
    });

    test('neither key is declared outside <application> (e.g. in an '
        '<activity>) where FCM would never read it', () {
      final XmlElement app = _application(manifest);
      for (final String key in <String>[_iconKey, _colorKey]) {
        final List<XmlElement> all = manifest.descendantElements
            .where(
              (XmlElement e) =>
                  e.name.local == 'meta-data' && _android(e, 'name') == key,
            )
            .toList();
        expect(all, hasLength(1), reason: '$key declared exactly once');
        expect(
          all.single.parentElement,
          same(app),
          reason: '$key must be a direct child of <application>',
        );
      }
    });
  });

  group('ic_stat_beautica drawable is an alpha-only white silhouette', () {
    test('root element is a 24dp x 24dp <vector>', () {
      final XmlElement root = drawable.rootElement;
      expect(root.name.local, 'vector', reason: 'root must be <vector>');
      expect(_android(root, 'width'), '24dp');
      expect(_android(root, 'height'), '24dp');
    });

    test('has at least one <path> and every fill/stroke color is white', () {
      final List<XmlElement> all = drawable.rootElement.descendantElements
          .toList();
      expect(all.where((XmlElement e) => e.name.local == 'path'), isNotEmpty);
      final List<String> colorsUsed = <String>[
        for (final XmlElement e in <XmlElement>[drawable.rootElement, ...all])
          for (final String a in <String>['fillColor', 'strokeColor'])
            ?_android(e, a),
      ];
      expect(colorsUsed, isNotEmpty, reason: 'path must declare a fillColor');
      for (final String c in colorsUsed) {
        expect(_isWhite(c), isTrue, reason: 'non-white color "$c"');
      }
    });

    test('has no gradient, tint, or partial-alpha attribute', () {
      final List<XmlElement> all = <XmlElement>[
        drawable.rootElement,
        ...drawable.rootElement.descendantElements,
      ];
      expect(all.where((XmlElement e) => e.name.local == 'gradient'), isEmpty);
      expect(
        all.where(
          (XmlElement e) =>
              e.name.namespaceUri == _aaptNs || e.name.qualified == 'aapt:attr',
        ),
        isEmpty,
      );
      for (final XmlElement e in all) {
        for (final String a in <String>[
          'tint',
          'alpha',
          'fillAlpha',
          'strokeAlpha',
        ]) {
          expect(
            _android(e, a),
            isNull,
            reason: 'android:$a on <${e.name.qualified}>',
          );
        }
      }
    });

    test('is the only ic_stat_beautica in any source set (no colored '
        'density PNG or flavor override shadows it)', () {
      final List<String> hits = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => f.path)
          .where(
            (String p) =>
                !p.contains('/build/') &&
                RegExp(r'/ic_stat_beautica\.[a-z]+$').hasMatch(p),
          )
          .toList();
      expect(hits, <String>[_drawablePath]);
    });
  });

  test('notification_accent color is defined as VelvetTouch camel', () {
    final List<String> values = colors.rootElement
        .findElements('color')
        .where(
          (XmlElement e) => e.getAttribute('name') == 'notification_accent',
        )
        .map((XmlElement e) => e.innerText.trim())
        .toList();
    expect(values, <String>['#B89A7A']);
  });

  test('raw/keep.xml pins both manifest-only resources against '
      'release resource shrinking', () {
    final String? attr = keep.rootElement.getAttribute(
      'keep',
      namespace: _toolsNs,
    );
    if (attr == null) fail('keep.xml must declare tools:keep');
    final Set<String> kept = attr
        .split(',')
        .map((String s) => s.trim())
        .toSet();
    expect(
      kept,
      containsAll(<String>[
        '@drawable/ic_stat_beautica',
        '@color/notification_accent',
      ]),
    );
  });
}
