import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Bytes with location metadata removed, or null when this file cannot prove
/// they are clean.
///
/// A JPEG keeps its bytes: EXIF GPS, MakerNote, XMP, APP13, and the embedded
/// thumbnail are removed in place. Anything else is decoded with the
/// platform codec and written as a new JPEG, or refused. Callers must not
/// send the original bytes on null. The place and the date are read from
/// the original first.
Future<Uint8List?> photoWithoutLocation(Uint8List bytes) async {
  try {
    if (_isJpeg(bytes)) return _jpegWithoutLocation(bytes);
    return await _jpegFromCodec(bytes);
  } catch (_) {
    return null;
  }
}

/// The photo-picker cache. Other camera files stay where they are.
bool guidePickCachePath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.length >= 2 && parts[parts.length - 2] == 'guide-pick';
}

/// Writes [from] to [to] without location metadata, then deletes a
/// photo-picker cache file. Throws when the location could not be removed,
/// and does not write the original bytes.
Future<void> copyGuidePhotoWithoutGps(String from, String to) async {
  final stripped = await photoWithoutLocation(await File(from).readAsBytes());
  if (stripped == null) {
    await deleteGuidePickCache(from);
    throw StateError('photo location could not be removed');
  }
  await File(to).writeAsBytes(stripped);
  await deleteGuidePickCache(from);
}

/// Drops a file left in `cacheDir/guide-pick` after it has been copied.
Future<void> deleteGuidePickCache(String path) async {
  if (!guidePickCachePath(path)) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// Drops the file this capture created. The place is still in it until a
/// find is saved. Unlink happens before this returns, so the next frame
/// cannot open the file.
Future<void> deleteDiscardedShot(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  return Future<void>.value();
}

class _Scrub {
  bool changed = false;
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}

bool _isJpeg(Uint8List bytes) {
  return bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;
}

Uint8List? _jpegWithoutLocation(Uint8List bytes) {
  final copy = Uint8List.fromList(bytes);
  final scrub = _Scrub();
  if (!_scrubJpeg(copy, 0, copy.length, 0, scrub)) return null;
  return scrub.changed ? copy : bytes;
}

bool _scrubJpeg(
  Uint8List bytes,
  int start,
  int end,
  int depth,
  _Scrub scrub,
) {
  if (depth > 4) return false;
  if (end - start < 4 || bytes[start] != 0xFF || bytes[start + 1] != 0xD8) {
    return false;
  }
  var i = start + 2;
  while (i < end) {
    if (bytes[i] != 0xFF) return false;
    while (i < end && bytes[i] == 0xFF) {
      i++;
    }
    if (i >= end) return false;
    final marker = bytes[i];
    i++;
    if (marker == 0xD9) {
      // A gain map or a motion photo follows this marker and can carry the
      // place. The picture ends here.
      if (i < end) _blank(bytes, i, end, scrub);
      return true;
    }
    if (marker == 0x00) return false;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (i + 2 > end) return false;
    final length = (bytes[i] << 8) | bytes[i + 1];
    if (length < 2 || i + length > end) return false;
    if (marker == 0xDA) {
      i += length;
      final next = _skipEntropy(bytes, i, end);
      if (next < 0) return false;
      i = next;
      continue;
    }
    final payload = i + 2;
    final segEnd = i + length;
    if (marker == 0xE1 && _isExifHeader(bytes, payload, segEnd)) {
      if (!_scrubTiff(bytes, payload + 6, segEnd, depth, scrub)) return false;
    } else if (marker == 0xE1 && _isXmpHeader(bytes, payload, segEnd)) {
      _blankXmp(bytes, payload, segEnd, scrub);
    } else if (marker == 0xED) {
      _blank(bytes, payload, segEnd, scrub);
    }
    i = segEnd;
  }
  return false;
}

int _skipEntropy(Uint8List bytes, int i, int end) {
  while (i < end) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = i;
    var j = i;
    while (j < end && bytes[j] == 0xFF) {
      j++;
    }
    if (j >= end) return -1;
    final kind = bytes[j];
    // Stuffed 0xFF and restart markers sit inside the scan. Treating a
    // restart as the next segment makes the walker fail the JPEG.
    if (kind == 0x00 || (kind >= 0xD0 && kind <= 0xD7)) {
      i = j + 1;
      continue;
    }
    return marker;
  }
  return -1;
}

bool _isExifHeader(Uint8List bytes, int start, int end) {
  const header = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  return _startsWith(bytes, start, end, header);
}

bool _isXmpHeader(Uint8List bytes, int start, int end) {
  return _startsWith(bytes, start, end, _xmpStandard) ||
      _startsWith(bytes, start, end, _xmpExtended);
}

const _xmpStandard = [
  0x68, 0x74, 0x74, 0x70, 0x3A, 0x2F, 0x2F, 0x6E, 0x73, 0x2E, 0x61, 0x64, //
  0x6F, 0x62, 0x65, 0x2E, 0x63, 0x6F, 0x6D, 0x2F, 0x78, 0x61, 0x70, 0x2F, //
  0x31, 0x2E, 0x30, 0x2F, 0x00,
];

const _xmpExtended = [
  0x68, 0x74, 0x74, 0x70, 0x3A, 0x2F, 0x2F, 0x6E, 0x73, 0x2E, 0x61, 0x64, //
  0x6F, 0x62, 0x65, 0x2E, 0x63, 0x6F, 0x6D, 0x2F, 0x78, 0x6D, 0x70, 0x2F, //
  0x65, 0x78, 0x74, 0x65, 0x6E, 0x73, 0x69, 0x6F, 0x6E, 0x2F, 0x00,
];

bool _startsWith(Uint8List bytes, int start, int end, List<int> header) {
  if (start + header.length > end) return false;
  for (var i = 0; i < header.length; i++) {
    if (bytes[start + i] != header[i]) return false;
  }
  return true;
}

void _blankXmp(Uint8List bytes, int payload, int segEnd, _Scrub scrub) {
  final header = _startsWith(bytes, payload, segEnd, _xmpStandard)
      ? _xmpStandard.length
      : _xmpExtended.length;
  _blank(bytes, payload + header, segEnd, scrub);
}

void _blank(Uint8List bytes, int start, int end, _Scrub scrub) {
  for (var i = start; i < end; i++) {
    if (bytes[i] != 0x20) {
      bytes[i] = 0x20;
      scrub.changed = true;
    }
  }
}

bool _scrubTiff(
  Uint8List bytes,
  int tiff,
  int limit,
  int depth,
  _Scrub scrub,
) {
  if (tiff + 8 > limit) return false;
  final little = bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
  final big = bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D;
  if (!little && !big) return false;

  int u16(int offset) {
    final b0 = bytes[offset];
    final b1 = bytes[offset + 1];
    return little ? (b1 << 8) | b0 : (b0 << 8) | b1;
  }

  int u32(int offset) {
    final b0 = bytes[offset];
    final b1 = bytes[offset + 1];
    final b2 = bytes[offset + 2];
    final b3 = bytes[offset + 3];
    return little
        ? (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        : (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

  if (u16(tiff + 2) != 42) return false;
  final thumbs = <_Range>[];
  final seen = <int>{};

  bool walk(int ifd, int hops) {
    if (hops > 16 || ifd < tiff || ifd + 2 > limit || !seen.add(ifd)) {
      return false;
    }
    final count = u16(ifd);
    final entries = ifd + 2;
    final nextAt = entries + count * 12;
    if (count > 256 || nextAt + 4 > limit) return false;
    int? jpegOff;
    int? jpegLen;
    final subs = <int>[];
    for (var n = 0; n < count; n++) {
      final entry = entries + n * 12;
      final tag = u16(entry);
      if (tag == 0x8825) {
        final gps = tiff + u32(entry + 8);
        _wipeIfd(bytes, tiff, gps, limit, u16, u32);
        for (var b = 0; b < 12; b++) {
          bytes[entry + b] = 0;
        }
        scrub.changed = true;
      } else if (tag == 0x02BC || tag == 0x927C) {
        final zeroed = _zeroValue(bytes, tiff, entry, limit, u16, u32);
        if (zeroed == null) return false;
        var changed = zeroed;
        for (var b = 0; b < 12; b++) {
          if (bytes[entry + b] != 0) {
            bytes[entry + b] = 0;
            changed = true;
          }
        }
        if (changed) scrub.changed = true;
      } else if (tag == 0x014A || tag == 0x8769) {
        final offsets = _entryLongs(bytes, tiff, entry, limit, u16, u32);
        if (offsets == null) return false;
        subs.addAll(offsets);
      } else if (tag == 0x0201) {
        jpegOff = _singleLong(entry, u16, u32);
      } else if (tag == 0x0202) {
        jpegLen = _singleLong(entry, u16, u32);
      }
    }
    if (jpegOff != null && jpegLen != null && jpegLen > 0) {
      final thumbStart = tiff + jpegOff;
      final thumbEnd = thumbStart + jpegLen;
      if (thumbStart < tiff || thumbEnd > bytes.length) return false;
      thumbs.add(_Range(thumbStart, thumbEnd));
    }
    final next = u32(nextAt);
    if (next != 0 && !walk(tiff + next, hops + 1)) return false;
    for (final sub in subs) {
      if (sub != 0 && !walk(tiff + sub, hops + 1)) return false;
    }
    return true;
  }

  if (!walk(tiff + u32(tiff + 4), 0)) return false;
  for (final thumb in thumbs) {
    if (thumb.end - thumb.start < 2) continue;
    if (bytes[thumb.start] != 0xFF || bytes[thumb.start + 1] != 0xD8) continue;
    if (!_scrubJpeg(bytes, thumb.start, thumb.end, depth + 1, scrub)) {
      return false;
    }
  }
  return true;
}

int? _singleLong(
  int entry,
  int Function(int offset) u16,
  int Function(int offset) u32,
) {
  final type = u16(entry + 2);
  final count = u32(entry + 4);
  if (count != 1 || (type != 3 && type != 4)) return null;
  return type == 3 ? u16(entry + 8) : u32(entry + 8);
}

List<int>? _entryLongs(
  Uint8List bytes,
  int tiff,
  int entry,
  int limit,
  int Function(int offset) u16,
  int Function(int offset) u32,
) {
  final type = u16(entry + 2);
  final count = u32(entry + 4);
  if (count == 0 || count > 8 || (type != 3 && type != 4)) return null;
  if (count == 1) {
    final value = _singleLong(entry, u16, u32);
    return value == null ? null : [value];
  }
  final width = type == 3 ? 2 : 4;
  final size = width * count;
  if (size <= 4) {
    if (type == 3 && count == 2) {
      return [u16(entry + 8), u16(entry + 10)];
    }
    return null;
  }
  final at = tiff + u32(entry + 8);
  if (at < tiff || at + size > limit) return null;
  return [
    for (var n = 0; n < count; n++)
      type == 3 ? u16(at + n * 2) : u32(at + n * 4),
  ];
}

/// Null when the value sits outside the TIFF and could not be cleared.
bool? _zeroValue(
  Uint8List bytes,
  int tiff,
  int entry,
  int limit,
  int Function(int offset) u16,
  int Function(int offset) u32,
) {
  final size = _typeSize(u16(entry + 2)) * u32(entry + 4);
  if (size <= 0 || size > limit) return null;
  if (size <= 4) {
    var changed = false;
    for (var b = 0; b < 4; b++) {
      if (bytes[entry + 8 + b] != 0) {
        bytes[entry + 8 + b] = 0;
        changed = true;
      }
    }
    return changed;
  }
  final value = tiff + u32(entry + 8);
  if (value < tiff || value + size > limit) return null;
  var changed = false;
  for (var b = 0; b < size; b++) {
    if (bytes[value + b] != 0) {
      bytes[value + b] = 0;
      changed = true;
    }
  }
  return changed;
}

void _wipeIfd(
  Uint8List bytes,
  int tiff,
  int ifd,
  int limit,
  int Function(int offset) u16,
  int Function(int offset) u32,
) {
  if (ifd < tiff || ifd + 2 > limit) return;
  final count = u16(ifd);
  final entries = ifd + 2;
  final nextAt = entries + count * 12;
  if (count > 256 || nextAt + 4 > limit) return;
  for (var n = 0; n < count; n++) {
    final entry = entries + n * 12;
    final size = _typeSize(u16(entry + 2)) * u32(entry + 4);
    if (size <= 4 || size > limit) continue;
    final value = tiff + u32(entry + 8);
    if (value < tiff || value + size > limit) continue;
    for (var b = 0; b < size; b++) {
      bytes[value + b] = 0;
    }
  }
  for (var b = ifd; b < nextAt + 4; b++) {
    bytes[b] = 0;
  }
}

int _typeSize(int type) {
  switch (type) {
    case 1:
    case 2:
    case 6:
    case 7:
      return 1;
    case 3:
    case 8:
      return 2;
    case 4:
    case 9:
    case 11:
      return 4;
    case 5:
    case 10:
    case 12:
      return 8;
    default:
      return 0;
  }
}

/// Pixels only. A PNG, WebP, or HEIC the codec cannot read is refused.
Future<Uint8List?> _jpegFromCodec(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      if (image.width <= 0 || image.height <= 0) return null;
      final raw = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (raw == null) return null;
      final pixels = raw.buffer.asUint8List(
        raw.offsetInBytes,
        raw.lengthInBytes,
      );
      final picture = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: pixels.buffer,
        bytesOffset: pixels.offsetInBytes,
        numChannels: 4,
      );
      final encoded = img.encodeJpg(picture, quality: 90);
      if (encoded.length < 4 || encoded[0] != 0xFF || encoded[1] != 0xD8) {
        return null;
      }
      return encoded;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
