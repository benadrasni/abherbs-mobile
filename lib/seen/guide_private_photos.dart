import 'dart:io';

import 'package:abherbs_flutter/data/guide_photo_file.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What to upload for one find, and whether the private row can say every
/// photo is in the cloud. A lapsed plan uploads nothing and deletes nothing.
class GuidePrivatePhotoWork {
  final List<String> upload;
  final bool markCloud;

  const GuidePrivatePhotoWork({
    required this.upload,
    required this.markCloud,
  });
}

/// Storage object for a Seen photo, or null when [photoPath] is not this
/// account's file. The folder is the Latin name with spaces already turned
/// into underscores, in the book or not.
String? guidePrivateObjectPath(String photoPath, String uid) {
  if (uid.isEmpty) return null;
  final prefix = '$storageObservations$uid/';
  if (!photoPath.startsWith(prefix)) return null;
  final rest = photoPath.substring(prefix.length);
  if (rest.isEmpty || rest.startsWith('/') || rest.contains('..')) return null;
  return '$storagePrivate$uid/$rest';
}

String guidePrivateContentType(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'heic':
    case 'heif':
      return 'image/heic';
    default:
      return 'image/jpeg';
  }
}

List<String> guidePrivatePhotoList(dynamic raw) {
  final paths = <String>[];
  void add(dynamic value) {
    if (value is String && value.isNotEmpty) paths.add(value);
  }

  if (raw is List) {
    for (final item in raw) {
      add(item);
    }
  } else if (raw is Map) {
    final keys = raw.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      add(raw[key]);
    }
  }
  return paths;
}

/// [local] and [remote] say whether this phone has the file and whether this
/// session already put it. [cloud] is the row's `photoCloud` flag.
GuidePrivatePhotoWork guidePrivatePhotoWork({
  required bool fieldGuide,
  required String uid,
  required List<String> photoPaths,
  required bool cloud,
  required bool Function(String path) local,
  required bool Function(String path) remote,
}) {
  if (!fieldGuide || cloud) {
    return const GuidePrivatePhotoWork(upload: [], markCloud: false);
  }
  final mine = <String>[];
  for (final path in photoPaths) {
    if (guidePrivateObjectPath(path, uid) != null) mine.add(path);
  }
  if (mine.isEmpty) {
    return const GuidePrivatePhotoWork(upload: [], markCloud: false);
  }
  final upload = <String>[];
  var ready = 0;
  for (final path in mine) {
    if (remote(path)) {
      ready++;
      continue;
    }
    if (local(path)) {
      upload.add(path);
      ready++;
    }
  }
  return GuidePrivatePhotoWork(
    upload: upload,
    markCloud: ready == mine.length,
  );
}

final Set<String> _absent = {};
final Set<String> _putDone = {};
final Set<String> _skipped = {};
final Map<String, Future<File?>> _fetching = {};
final Set<String?> _pending = {};
bool _running = false;

/// A notebook change may be the upload finishing. The next image build tries
/// Storage again.
void guidePrivatePhotosChanged() {
  _absent.clear();
}

/// The find is going away. An upload already in flight must not mark it, and
/// must remove the object it just wrote.
void skipGuidePrivatePhoto(String id) {
  if (id.isNotEmpty) _skipped.add(id);
}

User? _notebookUser() {
  final signedIn = Auth.appUser;
  if (signedIn != null) return signedIn;
  try {
    return Auth.guestUser;
  } catch (_) {
    return null;
  }
}

FirebaseStorage _bucket() {
  return FirebaseStorage.instanceFor(bucket: storageBucket);
}

/// Downloads [path] into the app documents directory when it belongs to the
/// signed-in account. A missing object is remembered until the notebook
/// changes. A lapsed plan still downloads what was stored.
Future<File?> fetchGuidePrivatePhoto(String path) async {
  final uid = _notebookUser()?.uid;
  if (uid == null) return null;
  final object = guidePrivateObjectPath(path, uid);
  if (object == null || _absent.contains(path)) return null;
  final pending = _fetching[path];
  if (pending != null) return pending;
  final future = _fetch(path, object);
  _fetching[path] = future;
  try {
    return await future;
  } finally {
    _fetching.remove(path);
  }
}

Future<File?> _fetch(String path, String object) async {
  final existing = await Offline.getLocalFile(path);
  if (existing != null) return existing;
  final root = (await getApplicationDocumentsDirectory()).path;
  final dest = File('$root/$path');
  try {
    await dest.parent.create(recursive: true);
    await _bucket().ref().child(object).writeToFile(dest);
    if (await dest.exists() && await dest.length() > 0) return dest;
    if (await dest.exists()) await dest.delete();
    return null;
  } on FirebaseException catch (error) {
    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }
    if (error.code == 'object-not-found') {
      _absent.add(path);
    } else {
      debugPrint('guide private photo $path: $error');
    }
    return null;
  } catch (error) {
    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }
    debugPrint('guide private photo $path: $error');
    return null;
  }
}

void clearPendingPrivatePhotos() {
  _pending.clear();
}

/// Uploads this account's local Seen photos while those photos sync.
/// [onlyId] limits the pass to one find. A pass already running is followed
/// by another, so a save during the catch-up is not missed.
Future<void> syncGuidePrivatePhotos({String? onlyId}) async {
  if (!Purchases.syncsSeenPhotos()) return;
  if (_notebookUser()?.uid == null) return;
  _pending.add(onlyId);
  if (_running) return;
  _running = true;
  try {
    while (_pending.isNotEmpty) {
      if (!Purchases.syncsSeenPhotos()) return;
      final uid = _notebookUser()?.uid;
      if (uid == null) return;
      final ids = Set<String?>.of(_pending);
      _pending.clear();
      try {
        if (ids.contains(null)) {
          await _syncAll(uid);
        } else {
          for (final id in ids) {
            if (id != null) await _syncOne(uid, id);
          }
        }
      } catch (error) {
        debugPrint('guide private photos: $error');
      }
    }
  } finally {
    _running = false;
  }
}

Future<void> _syncAll(String uid) async {
  final event = await privateObservationsReference
      .child(uid)
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .once();
  final raw = event.snapshot.value;
  if (raw is! Map) return;
  for (final entry in raw.entries) {
    await _syncRow(uid, entry.key.toString(), entry.value);
  }
}

Future<void> _syncOne(String uid, String id) async {
  final event = await privateObservationsReference
      .child(uid)
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .child(id)
      .once();
  await _syncRow(uid, id, event.snapshot.value);
}

Future<void> _syncRow(String uid, String id, dynamic raw) async {
  if (!Purchases.syncsSeenPhotos() || _skipped.contains(id) || raw is! Map) {
    return;
  }
  try {
    final paths = guidePrivatePhotoList(raw[observationPhotoPaths]);
    final local = <String>{};
    for (final path in paths) {
      if (guidePrivateObjectPath(path, uid) == null) continue;
      if (await Offline.getLocalFile(path) != null) local.add(path);
    }
    final work = guidePrivatePhotoWork(
      fieldGuide: true,
      uid: uid,
      photoPaths: paths,
      cloud: raw[observationPhotoCloud] == true,
      local: local.contains,
      remote: _putDone.contains,
    );
    var failed = false;
    for (final path in work.upload) {
      if (_skipped.contains(id)) break;
      if (!await _put(path, uid)) failed = true;
    }
    if (_skipped.contains(id)) {
      await deleteGuidePrivatePhotos(paths);
      return;
    }
    if (!work.markCloud || failed) return;
    final plant = raw[observationPlant];
    await _markCloud(uid, id, plant is String ? plant : '');
  } catch (error) {
    debugPrint('guide private photo $id: $error');
  }
}

Future<bool> _put(String path, String uid) async {
  final object = guidePrivateObjectPath(path, uid);
  if (object == null) return false;
  final file = await Offline.getLocalFile(path);
  if (file == null) return false;
  try {
    final bytes = await photoWithoutLocation(await file.readAsBytes());
    if (bytes == null) {
      debugPrint(
        'guide private photo $path: location metadata could not be removed',
      );
      return false;
    }
    await _bucket().ref().child(object).putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
    _absent.remove(path);
    _putDone.add(path);
    return true;
  } catch (error) {
    debugPrint('guide private photo $path: $error');
    return false;
  }
}

Future<void> _markCloud(String uid, String id, String plant) async {
  final patch = {observationPhotoCloud: true};
  final root = privateObservationsReference.child(uid);
  await root
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .child(id)
      .update(patch);
  final keys = <String>{
    if (plant.isNotEmpty) plant,
    if (plant.isNotEmpty) guideObservationPlantKey(plant),
  };
  for (final key in keys) {
    final ref = root
        .child(firebaseObservationsByPlant)
        .child(key)
        .child(firebaseAttributeList)
        .child(id);
    final event = await ref.once();
    if (event.snapshot.exists) await ref.update(patch);
  }
}

/// Removes the private objects for these photo paths. The public Sighting
/// file, when there is one, stays.
Future<void> deleteGuidePrivatePhotos(Iterable<String> paths) async {
  final uid = _notebookUser()?.uid;
  if (uid == null) return;
  for (final path in paths) {
    _putDone.remove(path);
    _absent.remove(path);
    final object = guidePrivateObjectPath(path, uid);
    if (object == null) continue;
    try {
      await _bucket().ref().child(object).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        debugPrint('guide private delete $object: $error');
      }
    } catch (error) {
      debugPrint('guide private delete $object: $error');
    }
  }
}
