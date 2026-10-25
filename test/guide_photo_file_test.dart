import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_photo_file.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('gps leaves a jpeg and the date stays', () async {
    final latitude = [
      0x30,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      9,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0x24,
      0,
      0,
      0,
      1,
      0,
      0,
      0
    ];
    final original = _jpeg(little: true);
    expect(_contains(original, latitude), isTrue);

    final stripped = (await photoWithoutLocation(original))!;
    expect(identical(stripped, original), isFalse);
    expect(_contains(stripped, latitude), isFalse);
    expect(_contains(stripped, '2024:01:02 03:04:05'.codeUnits), isTrue);

    final tags = await readExifFromBytes(stripped);
    expect(tags['GPS GPSLatitude'], isNull);
    expect(tags['GPS GPSLongitude'], isNull);
    expect(tags['Image DateTime'].toString(), '2024:01:02 03:04:05');
    expect(
      getLatitudeFromExif(tags['GPS GPSLatitudeRef'], tags['GPS GPSLatitude']),
      0,
    );
    expect(
      guidePhotoPosition(
        getLatitudeFromExif(
            tags['GPS GPSLatitudeRef'], tags['GPS GPSLatitude']),
        getLongitudeFromExif(
          tags['GPS GPSLongitudeRef'],
          tags['GPS GPSLongitude'],
        ),
      ),
      isNull,
    );

    final before = await readExifFromBytes(original);
    expect(
      getLatitudeFromExif(
        before['GPS GPSLatitudeRef'],
        before['GPS GPSLatitude'],
      ),
      closeTo(48.16, 0.001),
    );
  });

  test('a big-endian gps directory is removed too', () async {
    final original = _jpeg(little: false);
    final tags = await readExifFromBytes(original);
    expect(tags['GPS GPSLatitude'], isNotNull);
    final stripped = (await photoWithoutLocation(original))!;
    final after = await readExifFromBytes(stripped);
    expect(after['GPS GPSLatitude'], isNull);
    expect(after['Image DateTime'].toString(), '2024:01:02 03:04:05');
  });

  test('a jpeg without gps is left byte for byte', () async {
    final plain = _jpeg(little: true, gps: false);
    expect(identical(await photoWithoutLocation(plain), plain), isTrue);
    final entropy = Uint8List.fromList([
      0xFF,
      0xD8,
      0xFF,
      0xDA,
      0x00,
      0x08,
      0x01,
      0x01,
      0x00,
      0x00,
      0x3F,
      0x00,
      0x00,
      0x11,
      0xFF,
      0x00,
      0x22,
      0xFF,
      0xD9,
    ]);
    expect(identical(await photoWithoutLocation(entropy), entropy), isTrue);
  });

  test('restart markers stay inside the scan', () async {
    final entropy = Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, //
      0x11, 0xFF, 0xD0, //
      0x22, 0xFF, 0xD1, //
      0x33, 0xFF, 0xD7, //
      0x44, 0xFF, 0x00, //
      0x55, 0xFF, 0xD9,
    ]);
    expect(identical(await photoWithoutLocation(entropy), entropy), isTrue);
  });

  test('a photo that cannot be cleaned is not returned', () async {
    expect(await photoWithoutLocation(Uint8List.fromList([1, 2, 3])), isNull);
    expect(
      await photoWithoutLocation(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x20])),
      isNull,
    );
    expect(
      await photoWithoutLocation(Uint8List.fromList([
        0,
        0,
        0,
        16,
        ...'ftyp'.codeUnits,
        ...'heic'.codeUnits,
        0,
        0,
        0,
        0,
      ])),
      isNull,
    );
  });

  test('only the photo-picker cache is deleted after the copy', () async {
    final root = await Directory.systemTemp.createTemp('guide-pick-test');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}/guide-pick')..createSync();
    final shot = File('${cache.path}/shot.jpg')
      ..writeAsBytesSync(_jpeg(little: true));
    final kept = File('${root.path}/kept.jpg');
    await copyGuidePhotoWithoutGps(shot.path, kept.path);
    expect(shot.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
    final tags = await readExifFromBytes(await kept.readAsBytes());
    expect(tags['GPS GPSLatitude'], isNull);
    expect(tags['Image DateTime'].toString(), '2024:01:02 03:04:05');

    final camera = File('${root.path}/camera.jpg')
      ..writeAsBytesSync(_jpeg(little: true));
    final stored = File('${root.path}/stored.jpg');
    await copyGuidePhotoWithoutGps(camera.path, stored.path);
    expect(camera.existsSync(), isTrue);
    expect(guidePickCachePath(shot.path), isTrue);
    expect(guidePickCachePath(camera.path), isFalse);
    expect(guidePickCachePath('${root.path}/guide-pick'), isFalse);
  });

  test('app13 and a maker note lose their place', () async {
    const place = 'GPSLatitude>48.1600N';
    final app13 = _withSegment(
      _jpeg(little: true, gps: false),
      _app13(place),
    );
    final fromApp13 = (await photoWithoutLocation(app13))!;
    expect(_contains(fromApp13, place.codeUnits), isFalse);
    expect(_contains(fromApp13, '2024:01:02 03:04:05'.codeUnits), isTrue);

    final noted = _jpegWithMakerNote(place);
    expect(_contains(noted, place.codeUnits), isTrue);
    final fromNote = (await photoWithoutLocation(noted))!;
    expect(_contains(fromNote, place.codeUnits), isFalse);
    expect(_contains(fromNote, '2024:01:02 03:04:05'.codeUnits), isTrue);
    final tags = await readExifFromBytes(fromNote);
    expect(tags['Image DateTime'].toString(), '2024:01:02 03:04:05');
  });

  test('a gain map after the picture loses its place', () async {
    const place = 'GPSLatitude>48.1600N';
    final gain = _jpeg(little: true);
    final picture = Uint8List.fromList([
      ..._jpeg(little: false, gps: false),
      ...gain,
      ...place.codeUnits,
    ]);
    expect(_contains(picture, _latitude), isTrue);
    expect(_contains(picture, place.codeUnits), isTrue);

    final stripped = await photoWithoutLocation(picture);
    expect(stripped, isNotNull);
    expect(_contains(stripped!, _latitude), isFalse);
    expect(_contains(stripped, place.codeUnits), isFalse);
    expect(_contains(stripped, '2024:01:02 03:04:05'.codeUnits), isTrue);
    final tags = await readExifFromBytes(stripped);
    expect(tags['GPS GPSLatitude'], isNull);
    expect(tags['Image DateTime'].toString(), '2024:01:02 03:04:05');
  });

  test('xmp and a nested thumbnail lose their place', () async {
    const place = 'GPSLatitude>48,9.6000N';
    final xmp = _withSegment(
      _jpeg(little: true, gps: false),
      _xmp(place),
    );
    final fromXmp = await photoWithoutLocation(xmp);
    expect(fromXmp, isNotNull);
    expect(_contains(fromXmp!, place.codeUnits), isFalse);
    expect(_contains(fromXmp, '2024:01:02 03:04:05'.codeUnits), isTrue);
    final xmpTags = await readExifFromBytes(fromXmp);
    expect(xmpTags['Image DateTime'].toString(), '2024:01:02 03:04:05');

    final nested = _jpegWithThumbnail(_jpeg(little: true));
    expect(_contains(nested, _latitude), isTrue);
    final fromThumb = await photoWithoutLocation(nested);
    expect(fromThumb, isNotNull);
    expect(_contains(fromThumb!, _latitude), isFalse);
    expect(_contains(fromThumb, '2024:01:02 03:04:05'.codeUnits), isTrue);
  });

  test('a png is re-encoded without its text', () async {
    final png = base64Decode(_pngWithGps);
    expect(_contains(png, 'GPSLatitude'.codeUnits), isTrue);
    final jpeg = await photoWithoutLocation(png);
    expect(jpeg, isNotNull);
    expect(jpeg![0], 0xFF);
    expect(jpeg[1], 0xD8);
    expect(_contains(jpeg, 'GPSLatitude'.codeUnits), isFalse);
    expect(_contains(jpeg, 'IHDR'.codeUnits), isFalse);
  });

  test('a photo whose place cannot be removed is not written', () async {
    final root = await Directory.systemTemp.createTemp('guide-strip-fail');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}/guide-pick')..createSync();
    final shot = File('${cache.path}/shot.bin')..writeAsBytesSync([1, 2, 3, 4]);
    final dest = File('${root.path}/out.jpg');
    await expectLater(
      copyGuidePhotoWithoutGps(shot.path, dest.path),
      throwsA(isA<StateError>()),
    );
    expect(dest.existsSync(), isFalse);
    expect(shot.existsSync(), isFalse);

    final camera = File('${root.path}/camera.bin')
      ..writeAsBytesSync([1, 2, 3, 4]);
    await expectLater(
      copyGuidePhotoWithoutGps(camera.path, dest.path),
      throwsA(isA<StateError>()),
    );
    expect(camera.existsSync(), isTrue);
    expect(dest.existsSync(), isFalse);
  });

  test('a discarded shot deletes the path the capture created', () async {
    final root = await Directory.systemTemp.createTemp('guide-discard');
    addTearDown(() => root.delete(recursive: true));
    final nested = Directory('${root.path}/cache/9f0c')
      ..createSync(recursive: true);
    final shot = File('${nested.path}/shot.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final tmp = Directory('${root.path}/tmp')..createSync();
    final other = File('${tmp.path}/shot.jpg')..writeAsBytesSync([5, 6]);
    await deleteDiscardedShot(shot.path);
    expect(shot.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });
}

bool _contains(List<int> bytes, List<int> needle) {
  if (needle.isEmpty || needle.length > bytes.length) return false;
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return true;
  }
  return false;
}

Uint8List _jpeg({required bool little, bool gps = true}) {
  final tiff = _tiff(little: little, gps: gps);
  final payload = <int>[
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif\0\0
    ...tiff,
  ];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
    0xFF,
    0xD9,
  ]);
}

Uint8List _tiff({required bool little, required bool gps}) {
  final bytes = BytesBuilder();
  void u16(int value) {
    if (little) {
      bytes.addByte(value & 0xFF);
      bytes.addByte((value >> 8) & 0xFF);
    } else {
      bytes.addByte((value >> 8) & 0xFF);
      bytes.addByte(value & 0xFF);
    }
  }

  void u32(int value) {
    if (little) {
      bytes.addByte(value & 0xFF);
      bytes.addByte((value >> 8) & 0xFF);
      bytes.addByte((value >> 16) & 0xFF);
      bytes.addByte((value >> 24) & 0xFF);
    } else {
      bytes.addByte((value >> 24) & 0xFF);
      bytes.addByte((value >> 16) & 0xFF);
      bytes.addByte((value >> 8) & 0xFF);
      bytes.addByte(value & 0xFF);
    }
  }

  bytes.addByte(little ? 0x49 : 0x4D);
  bytes.addByte(little ? 0x49 : 0x4D);
  u16(42);
  u32(8);

  final dateAt = gps ? 38 : 26;
  u16(gps ? 2 : 1);
  u16(0x0132);
  u16(2);
  u32(20);
  u32(dateAt);
  if (gps) {
    u16(0x8825);
    u16(4);
    u32(1);
    u32(58);
  }
  u32(0);

  if (!gps) {
    expect(bytes.length, dateAt);
  }
  bytes.add('2024:01:02 03:04:05'.codeUnits);
  bytes.addByte(0);
  if (!gps) return bytes.toBytes();

  expect(bytes.length, 58);
  final latAt = 112;
  final lonAt = 136;
  u16(4);
  u16(1);
  u16(2);
  u32(2);
  bytes.add('N'.codeUnits);
  bytes.add([0, 0, 0]);
  u16(2);
  u16(5);
  u32(3);
  u32(latAt);
  u16(3);
  u16(2);
  u32(2);
  bytes.add('E'.codeUnits);
  bytes.add([0, 0, 0]);
  u16(4);
  u16(5);
  u32(3);
  u32(lonAt);
  u32(0);
  expect(bytes.length, latAt);
  for (final part in [48, 1, 9, 1, 36, 1, 17, 1, 6, 1, 18, 1]) {
    u32(part);
  }
  return bytes.toBytes();
}

const _latitude = [
  0x30,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  9,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0x24,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
];

Uint8List _app13(String body) {
  final payload = body.codeUnits;
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xED,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
  ]);
}

/// EXIF whose MakerNote, inside the Exif IFD, carries [place].
Uint8List _jpegWithMakerNote(String place) {
  final note = place.codeUnits;
  final bytes = BytesBuilder();
  void u16(int value) {
    bytes.addByte(value & 0xFF);
    bytes.addByte((value >> 8) & 0xFF);
  }

  void u32(int value) {
    bytes.addByte(value & 0xFF);
    bytes.addByte((value >> 8) & 0xFF);
    bytes.addByte((value >> 16) & 0xFF);
    bytes.addByte((value >> 24) & 0xFF);
  }

  bytes.addByte(0x49);
  bytes.addByte(0x49);
  u16(42);
  u32(8);
  u16(2);
  u16(0x0132);
  u16(2);
  u32(20);
  u32(38);
  u16(0x8769);
  u16(4);
  u32(1);
  u32(58);
  u32(0);
  bytes.add('2024:01:02 03:04:05'.codeUnits);
  bytes.addByte(0);
  expect(bytes.length, 58);
  u16(1);
  u16(0x927C);
  u16(7);
  u32(note.length);
  u32(76);
  u32(0);
  expect(bytes.length, 76);
  bytes.add(note);
  final payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...bytes.toBytes()];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
    0xFF,
    0xD9,
  ]);
}

Uint8List _xmp(String body) {
  final payload = [
    ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
    0,
    ...body.codeUnits,
  ];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
  ]);
}

Uint8List _withSegment(Uint8List jpeg, Uint8List segment) {
  return Uint8List.fromList([
    ...jpeg.sublist(0, jpeg.length - 2),
    ...segment,
    0xFF,
    0xD9,
  ]);
}

Uint8List _jpegWithThumbnail(Uint8List thumbnail) {
  final bytes = BytesBuilder();
  void u16(int value) {
    bytes.addByte(value & 0xFF);
    bytes.addByte((value >> 8) & 0xFF);
  }

  void u32(int value) {
    bytes.addByte(value & 0xFF);
    bytes.addByte((value >> 8) & 0xFF);
    bytes.addByte((value >> 16) & 0xFF);
    bytes.addByte((value >> 24) & 0xFF);
  }

  bytes.addByte(0x49);
  bytes.addByte(0x49);
  u16(42);
  u32(8);
  u16(1);
  u16(0x0132);
  u16(2);
  u32(20);
  u32(26);
  u32(46);
  bytes.add('2024:01:02 03:04:05'.codeUnits);
  bytes.addByte(0);
  u16(2);
  u16(0x0201);
  u16(4);
  u32(1);
  u32(76);
  u16(0x0202);
  u16(4);
  u32(1);
  u32(thumbnail.length);
  u32(0);
  bytes.add(thumbnail);
  final payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...bytes.toBytes()];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
    0xFF,
    0xD9,
  ]);
}

const _pngWithGps =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAHnRFWHRDb21tZW50AEdQU0xhdGl0dWRlPjQ4LDkuNjAwME5ThumwAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';
