// Phase 071 QA — ImagePickGatewayImpl.compress on the wire.
//
// The service asserts `keepExif:false` against a fake; this pins the REAL
// gateway: the plugin receives format=JPEG and keepExif=false, so the strip
// invariant holds below the seam too.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_image_compress_platform_interface/flutter_image_compress_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_image_compress_common/flutter_image_compress_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<MethodCall> calls;
  late FlutterImageCompressPlatform previous;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wire');
    calls = <MethodCall>[];
    previous = FlutterImageCompressPlatform.instance;
    FlutterImageCompressCommon.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_image_compress'),
          (MethodCall c) async {
            calls.add(c);
            return c.method == 'compressWithFileAndGetFile'
                ? (c.arguments as List<Object?>)[4]
                : null;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_image_compress'),
          null,
        );
    FlutterImageCompressPlatform.instance = previous;
    tmp.deleteSync(recursive: true);
  });

  test(
    'compress sends JPEG (index 0) + keepExif=false to the plugin',
    () async {
      final File src = File('${tmp.path}/in.jpg')
        ..writeAsBytesSync(<int>[1, 2]);
      final String target = '${tmp.path}/out.jpg';

      final String? out = await ImagePickGatewayImpl().compress(
        src.path,
        target,
        maxWidth: 1024,
        maxHeight: 1024,
        quality: 85,
        keepExif: false,
      );

      expect(out, target);
      final MethodCall call = calls.singleWhere(
        (MethodCall c) => c.method == 'compressWithFileAndGetFile',
      );
      final List<Object?> args = call.arguments as List<Object?>;
      expect(args[1], 1024); // minWidth
      expect(args[2], 1024); // minHeight
      expect(args[3], 85); // quality
      expect(args[7], 0); // CompressFormat.jpeg
      expect(args[8], false); // keepExif
    },
  );
}
