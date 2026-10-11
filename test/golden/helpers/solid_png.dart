// A tiny opaque solid-colour PNG for goldens that need a LOADED remote image
// that is visibly distinct from the widget's fallback. (The shared
// `kTransparentPng` fixture is invisible, so it cannot prove an image rendered.)

import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

const int _kSide = 4;

/// An opaque [_kSide]x[_kSide] PNG filled with the given RGB.
Uint8List solidPng(int r, int g, int b) {
  final BytesBuilder raw = BytesBuilder();
  for (int y = 0; y < _kSide; y++) {
    raw.addByte(0); // filter: none
    for (int x = 0; x < _kSide; x++) {
      raw
        ..addByte(r)
        ..addByte(g)
        ..addByte(b);
    }
  }
  final Uint8List ihdr = Uint8List(13);
  final ByteData h = ByteData.view(ihdr.buffer);
  h.setUint32(0, _kSide);
  h.setUint32(4, _kSide);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: RGB
  final BytesBuilder png = BytesBuilder()
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(png, 'IHDR', ihdr);
  _chunk(png, 'IDAT', Uint8List.fromList(ZLibCodec().encode(raw.toBytes())));
  _chunk(png, 'IEND', Uint8List(0));
  return png.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);
  final ByteData len = ByteData(4)..setUint32(0, data.length);
  out
    ..add(len.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data);
  final ByteData crc = ByteData(4)
    ..setUint32(0, _crc32(<int>[...typeBytes, ...data]));
  out.add(crc.buffer.asUint8List());
}

int _crc32(List<int> bytes) {
  int c = 0xFFFFFFFF;
  for (final int b in bytes) {
    c ^= b;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return c ^ 0xFFFFFFFF;
}
