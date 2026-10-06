// Phase 071 — on-device proof that a geotagged photo leaves the REAL
// pick pipeline (uCrop -> flutter_image_compress, production params) with no
// EXIF / GPS. `flutter test` cannot show this: uCrop and the native JPEG
// encoder are the thing under test.
//
// Self-contained: the geotagged JPEG is built IN the test (a natively encoded
// JPEG with a hand-built APP1 Exif segment spliced in), so no asset is pushed.
// Only the Photo Picker step is replaced (it is a system UI); crop + compress
// are the real `ImagePickGatewayImpl`. uCrop's Done is tapped natively.
//
// Load-bearing: the post-crop file MUST still carry GPS (otherwise the final
// assertion proves nothing), so a regression of the compress strip — e.g.
// `keepExif: true` — turns this red.
//
// Run: `patrol test --target integration_test/patrol/exif_strip_patrol_test.dart`

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:path_provider/path_provider.dart';

const int _sampleSide = 800;
const Duration _cropScreenTimeout = Duration(seconds: 60);

/// Real plugins; only the system picker UI is replaced by a seeded file. The
/// post-crop file is copied aside so the test can inspect it before the
/// service deletes its intermediates.
final class _SeededGateway implements ImagePickGateway {
  _SeededGateway({required this.seed, required this.cropCopy});

  final ImagePickGatewayImpl _real = ImagePickGatewayImpl();
  final String seed;
  final String cropCopy;

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async => seed;

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    final String? out = await _real.cropImage(
      sourcePath,
      spec: spec,
      quality: quality,
      labels: labels,
    );
    if (out != null) await File(out).copy(cropCopy);
    return out;
  }

  @override
  Future<String?> compress(
    String sourcePath,
    String targetPath, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
    required bool keepExif,
  }) => _real.compress(
    sourcePath,
    targetPath,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    quality: quality,
    keepExif: keepExif,
  );

  @override
  Future<String?> retrieveLostData() => _real.retrieveLostData();
}

/// A big-endian TIFF block: IFD0 -> GPS IFD with lat/lon refs + rationals.
Uint8List _geoTiff() {
  final ByteData b = ByteData(128);
  void u16(int o, int v) => b.setUint16(o, v);
  void u32(int o, int v) => b.setUint32(o, v);
  // Header: "MM", 42, IFD0 at 8.
  b.setUint8(0, 0x4D);
  b.setUint8(1, 0x4D);
  u16(2, 42);
  u32(4, 8);
  // IFD0: one entry — GPSInfo pointer (0x8825, LONG) -> GPS IFD at 26.
  u16(8, 1);
  u16(10, 0x8825);
  u16(12, 4);
  u32(14, 1);
  u32(18, 26);
  u32(22, 0);
  // GPS IFD: 4 entries.
  u16(26, 4);
  void entry(int i, int tag, int type, int count, int value) {
    final int o = 28 + i * 12;
    u16(o, tag);
    u16(o + 2, type);
    u32(o + 4, count);
    u32(o + 8, value);
  }

  entry(0, 1, 2, 2, 0x4E000000); // GPSLatitudeRef "N"
  entry(1, 2, 5, 3, 80); // GPSLatitude  -> rationals at 80
  entry(2, 3, 2, 2, 0x45000000); // GPSLongitudeRef "E"
  entry(3, 4, 5, 3, 104); // GPSLongitude -> rationals at 104
  u32(76, 0);
  // 50°27'0" N, 30°31'0" E (Kyiv).
  const List<int> lat = <int>[50, 1, 27, 1, 0, 1];
  const List<int> lon = <int>[30, 1, 31, 1, 0, 1];
  for (int i = 0; i < 6; i++) {
    u32(80 + i * 4, lat[i]);
    u32(104 + i * 4, lon[i]);
  }
  return b.buffer.asUint8List();
}

/// [jpeg] with an APP1 Exif segment (incl. GPS IFD) inserted after SOI.
Uint8List _withGeoExif(Uint8List jpeg) {
  final Uint8List tiff = _geoTiff();
  const List<int> header = <int>[0x45, 0x78, 0x69, 0x66, 0, 0]; // "Exif\0\0"
  final int segLen = 2 + header.length + tiff.length;
  final BytesBuilder out = BytesBuilder()
    ..add(jpeg.sublist(0, 2)) // SOI
    ..add(<int>[0xFF, 0xE1, segLen >> 8, segLen & 0xFF])
    ..add(header)
    ..add(tiff)
    ..add(jpeg.sublist(2));
  return out.toBytes();
}

Future<Uint8List> _plainJpeg() async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas canvas = Canvas(rec);
  const Rect r = Rect.fromLTWH(0, 0, 800, 800);
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
      ).createShader(r),
  );
  final ui.Image img = await rec.endRecording().toImage(
    _sampleSide,
    _sampleSide,
  );
  final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
  expect(png, isNotNull);
  return FlutterImageCompress.compressWithList(
    png!.buffer.asUint8List(),
    minWidth: _sampleSide,
    minHeight: _sampleSide,
    quality: 90,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
}

/// Header-level scan of the JPEG segments before the scan data (SOS).
({bool exifApp1, bool gps}) _inspect(Uint8List j) {
  expect(j.length, greaterThan(4));
  expect(j[0], 0xFF);
  expect(j[1], 0xD8, reason: 'not a JPEG');
  bool exif = false;
  bool gps = false;
  int i = 2;
  while (i + 4 <= j.length && j[i] == 0xFF) {
    final int marker = j[i + 1];
    if (marker == 0xDA || marker == 0xD9) break; // SOS / EOI
    final int len = (j[i + 2] << 8) | j[i + 3];
    final int s = i + 4; // payload start
    if (marker == 0xE1 &&
        len >= 8 &&
        s + 6 <= j.length &&
        String.fromCharCodes(j.sublist(s, s + 4)) == 'Exif' &&
        j[s + 4] == 0 &&
        j[s + 5] == 0) {
      exif = true;
      gps = gps || _tiffHasGps(Uint8List.sublistView(j, s + 6, i + 2 + len));
    }
    i += 2 + len;
  }
  return (exifApp1: exif, gps: gps);
}

bool _tiffHasGps(Uint8List t) {
  if (t.length < 14) return false;
  final Endian e = t[0] == 0x49 ? Endian.little : Endian.big;
  final ByteData d = ByteData.sublistView(t);
  final int ifd = d.getUint32(4, e);
  if (ifd + 2 > t.length) return false;
  final int n = d.getUint16(ifd, e);
  for (int k = 0; k < n; k++) {
    final int o = ifd + 2 + k * 12;
    if (o + 12 > t.length) return false;
    if (d.getUint16(o, e) == 0x8825) return true; // GPSInfo IFD pointer
  }
  return false;
}

void main() {
  patrolTest(
    'real crop and compress strip EXIF and GPS',
    // Android-only: uCrop is the Android crop screen driven natively here.
    skip: !Platform.isAndroid,
    config: const PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle),
    ($) async {
      final Directory tmp = await getTemporaryDirectory();
      final File seed = File('${tmp.path}/exif_probe_geo.jpg');
      final File cropCopy = File('${tmp.path}/exif_probe_crop.jpg');
      try {
        final Uint8List geo = await $.tester
            .runAsync(() async => _withGeoExif(await _plainJpeg()))
            .then((Uint8List? v) => v!);
        await seed.writeAsBytes(geo);
        // Self-check of the generator: the seed really is geotagged.
        final seedInfo = _inspect(geo);
        expect(seedInfo.exifApp1, isTrue, reason: 'seed lacks Exif APP1');
        expect(seedInfo.gps, isTrue, reason: 'seed lacks GPS IFD');

        await $.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('exif-probe'))),
        );

        final MediaPickService service = MediaPickService(
          _SeededGateway(seed: seed.path, cropCopy: cropCopy.path),
        );
        final Future<PickedImage?> pending = service.pick(
          MediaKind.servicePhoto,
          MediaPickSource.gallery,
          labels: const CropLabels(
            title: 'Crop',
            doneButton: 'Done',
            cancelButton: 'Cancel',
          ),
        );

        // uCrop's Done (the toolbar check) — native, waits for the element.
        await $.platform.android.tap(
          const AndroidSelector(
            resourceName: 'com.beautica.beautica_mobile:id/menu_crop',
          ),
          timeout: _cropScreenTimeout,
        );
        final PickedImage? result = await pending;
        expect(result, isNotNull);

        final cropped = _inspect(await cropCopy.readAsBytes());
        // Guard against a vacuous pass: uCrop carries GPS through, so the
        // compress pass is the ONLY thing that strips it.
        expect(
          cropped.gps,
          isTrue,
          reason:
              'post-crop file lost GPS by itself; test no longer proves '
              'the compress strip',
        );

        final Uint8List finalBytes = await result!.file.readAsBytes();
        final finalInfo = _inspect(finalBytes);
        expect(finalInfo.exifApp1, isFalse, reason: 'final has Exif APP1');
        expect(finalInfo.gps, isFalse, reason: 'final has GPS IFD');
        await service.discard(result);
      } finally {
        for (final File f in <File>[seed, cropCopy]) {
          if (f.existsSync()) f.deleteSync();
        }
      }
    },
  );
}
