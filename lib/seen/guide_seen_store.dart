import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_location.dart';
import 'package:abherbs_flutter/data/guide_photo_file.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/seen/guide_private_photos.dart';
import 'package:abherbs_flutter/seen/guide_seen.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/foundation.dart';

final Set<String> _countryFillIds = {};

/// Writes a country onto private rows that have coordinates and none yet.
/// [uid] is the account the snapshot was read for. A later account is left
/// alone. The Seen date line reads that field. A lookup that finds nothing
/// is not retried until the next launch.
Future<void> fillGuideSeenCountries(Object? value, String uid) async {
  if (uid.isEmpty || guideNotebookUser()?.uid != uid) return;
  final gaps = [
    for (final gap in guideSeenCountryGaps(value))
      if (_countryFillIds.add(gap.id)) gap,
  ];
  if (gaps.isEmpty) return;
  try {
    var next = 0;
    Future<void> worker() async {
      while (next < gaps.length) {
        final gap = gaps[next];
        next++;
        await _storeCountry(uid, gap);
      }
    }

    final width = gaps.length < 3 ? gaps.length : 3;
    await Future.wait([for (var i = 0; i < width; i++) worker()]);
  } finally {
    for (final gap in gaps) {
      _countryFillIds.remove(gap.id);
    }
  }
}

/// The country written onto the date row, or null when the account changed
/// or the find was already gone. A missing date node aborts, so the lookup
/// cannot recreate a country-only row.
Future<String?> _storeCountry(String uid, GuideSeenCountryGap gap) async {
  if (guideNotebookUser()?.uid != uid) return null;
  try {
    final code = await guideCountryCode(gap.latitude, gap.longitude);
    if (code == null || guideNotebookUser()?.uid != uid) return null;
    final root = privateObservationsReference.child(uid);
    final dateRef = root
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .child(gap.id);
    final result = await dateRef.runTransaction((value) {
      if (value is! Map) return Transaction.abort();
      final next = Map<Object?, Object?>.from(value);
      next[observationCountry] = code;
      return Transaction.success(next);
    });
    if (!result.committed || guideNotebookUser()?.uid != uid) return null;
    await _patchPrivatePlant(
      root,
      gap.plant,
      gap.id,
      {observationCountry: code},
    );
    return code;
  } catch (error) {
    debugPrint('guide seen country ${gap.id}: $error');
    return null;
  }
}

/// Publishes one confirmed find for review. The note stays on the private
/// row. Returns false when there is no account, no photo, or the write fails.
Future<bool> shareGuideFind(String id) async {
  try {
    final user = Auth.appUser;
    if (user == null || id.isEmpty) return false;
    final root = privateObservationsReference.child(user.uid);
    final dateRef = root
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .child(id);
    final event = await dateRef.once();
    final raw = event.snapshot.value;
    if (raw is! Map) return false;
    final observation =
        Observation.fromJson(id, Map<dynamic, dynamic>.from(raw));
    observation.photoPaths = _photoPaths(raw[observationPhotoPaths]);
    if (!observation.confirmed || observation.plant.isEmpty) return false;
    if (observation.photoPaths.isEmpty) return false;
    for (final path in observation.photoPaths) {
      if (path is! String || !await _uploadPhoto(path)) return false;
    }
    observation.note = '';
    observation.candidates = [];
    observation.status = firebaseValueReview;
    if (guideRowCountry(observation.country) == null) {
      final code = await _storeCountry(
        user.uid,
        GuideSeenCountryGap(
          id: observation.id,
          plant: observation.plant,
          latitude: observation.latitude,
          longitude: observation.longitude,
        ),
      );
      if (code != null) observation.country = code;
    }
    final json = observation.toJson();
    final plant = observation.plant;
    await publicObservationsReference
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .child(observation.id)
        .set(json);
    await publicObservationsReference
        .child(firebaseObservationsByPlant)
        .child(guideObservationPlantKey(plant))
        .child(firebaseAttributeList)
        .child(observation.id)
        .set(json);
    final patch = {observationStatus: firebaseValueReview};
    await dateRef.update(patch);
    await _patchPrivatePlant(root, plant, observation.id, patch);
    return true;
  } catch (error) {
    debugPrint('guide seen share: $error');
    return false;
  }
}

/// Removes a find from Seen, including its photo on this phone and in
/// private storage. A find that was sent (in review, shared, or not
/// accepted) also leaves the public record and its public photo.
Future<bool> deleteGuideSeenFind({
  required String id,
  required String plant,
  required GuideSeenShare share,
}) async {
  try {
    if (share != GuideSeenShare.none) {
      final user = Auth.appUser;
      if (user == null || id.isEmpty) return false;
      final event = await privateObservationsReference
          .child(user.uid)
          .child(firebaseObservationsByDate)
          .child(firebaseAttributeList)
          .child(id)
          .once();
      final raw = event.snapshot.value;
      if (raw is Map) {
        await _deletePublicPhotos(_photoPaths(raw[observationPhotoPaths]));
      }
      await publicObservationsReference
          .child(firebaseObservationsByDate)
          .child(firebaseAttributeList)
          .child(id)
          .remove();
      await _removePublicPlant(plant, id);
    }
    await deleteGuideCameraFind(id: id, plant: plant);
    return true;
  } catch (error) {
    debugPrint('guide seen delete: $error');
    return false;
  }
}

/// Removes a find from Sightings. The private row stays, marked private.
Future<bool> withdrawGuideFind({
  required String id,
  required String plant,
}) async {
  try {
    final user = Auth.appUser;
    if (user == null || id.isEmpty) return false;
    await publicObservationsReference
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .child(id)
        .remove();
    await _removePublicPlant(plant, id);
    final patch = {observationStatus: observationStatusPrivate};
    final root = privateObservationsReference.child(user.uid);
    await root
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .child(id)
        .update(patch);
    await _patchPrivatePlant(root, plant, id, patch);
    return true;
  } catch (error) {
    debugPrint('guide seen withdraw: $error');
    return false;
  }
}

/// Camera finds use a sanitized plant key. Manual finds use the Latin name.
/// For an ordinary binomial the two are the same.
Set<String> _plantKeys(String plant) {
  return {
    if (plant.isNotEmpty) plant,
    if (guideObservationPlantKey(plant).isNotEmpty)
      guideObservationPlantKey(plant),
  };
}

Future<void> _patchPrivatePlant(
  DatabaseReference root,
  String plant,
  String id,
  Map<String, Object> patch,
) async {
  for (final key in _plantKeys(plant)) {
    final ref = root
        .child(firebaseObservationsByPlant)
        .child(key)
        .child(firebaseAttributeList)
        .child(id);
    final event = await ref.once();
    if (event.snapshot.exists) await ref.update(patch);
  }
}

Future<void> _removePublicPlant(String plant, String id) async {
  for (final key in _plantKeys(plant)) {
    await publicObservationsReference
        .child(firebaseObservationsByPlant)
        .child(key)
        .child(firebaseAttributeList)
        .child(id)
        .remove();
  }
}

Future<void> _deletePublicPhotos(List<String> paths) async {
  for (final path in paths) {
    if (!path.startsWith(storageObservations)) continue;
    try {
      await firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
          .ref()
          .child(path)
          .delete();
    } on firebase_storage.FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        debugPrint('guide seen public photo $path: $error');
      }
    } catch (error) {
      debugPrint('guide seen public photo $path: $error');
    }
  }
}

List<String> _photoPaths(dynamic raw) {
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

Future<bool> _uploadPhoto(String path) async {
  var file = await Offline.getLocalFile(path);
  file ??= await fetchGuidePrivatePhoto(path);
  if (file == null) return _publicObjectExists(path);
  try {
    final ref =
        firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
            .ref()
            .child(path);
    final bytes = await photoWithoutLocation(await file.readAsBytes());
    if (bytes == null) {
      debugPrint(
          'guide seen photo $path: location metadata could not be removed');
      return false;
    }
    await ref.putData(
      bytes,
      firebase_storage.SettableMetadata(
        contentType: 'image/jpeg',
      ),
    );
    return true;
  } catch (error) {
    debugPrint('guide seen photo $path: $error');
    return false;
  }
}

/// A photo already published has no local file on a second phone. Sharing
/// again can keep that object. A path outside Storage is not one.
Future<bool> _publicObjectExists(String path) async {
  if (!path.startsWith(storageObservations)) return false;
  try {
    await firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
        .ref()
        .child(path)
        .getMetadata();
    return true;
  } catch (error) {
    debugPrint('guide seen photo $path: $error');
    return false;
  }
}
