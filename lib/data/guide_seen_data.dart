import 'dart:async';

import 'package:abherbs_flutter/data/guide_catalog.dart';
import 'package:abherbs_flutter/data/guide_rtdb.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/seen/guide_private_photos.dart';
import 'package:abherbs_flutter/seen/guide_seen.dart';
import 'package:abherbs_flutter/seen/guide_stats.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/foundation.dart';

class GuideFind {
  final String name;
  final String? label;
  final DateTime when;
  final String? photoPath;

  /// Book photo. Shown when [photoPath] is not a file on this phone.
  final String? coverPath;

  /// False while a photo name is still waiting on Seen. A missing flag on
  /// an older row counts as confirmed.
  final bool confirmed;

  GuideFind({
    required this.name,
    required this.label,
    required this.when,
    required this.photoPath,
    this.coverPath,
    this.confirmed = true,
  });
}

Future<Set<String>> loadGuideSeenNames() async {
  final user = guideNotebookUser();
  if (user == null) return {};
  try {
    final ref = privateObservationsReference
        .child(user.uid)
        .child(firebaseObservationsByPlant);
    final value = await guideChildValue(
      ref,
      phoneOnly: await guideOnPhoneOnly(),
    );
    if (value is! Map) return {};
    return value.keys.map((key) => key.toString()).toSet();
  } catch (error) {
    debugPrint('guide seen names: $error');
    return {};
  }
}

User? guideNotebookUser() {
  final signedIn = Auth.appUser;
  if (signedIn != null) return signedIn;
  try {
    return Auth.guestUser;
  } catch (_) {
    return null;
  }
}

/// The notebook account, creating the anonymous guest when this install
/// does not have one yet. Signing out does not create another guest.
Future<User?> guideNotebookUserReady() async {
  final current = guideNotebookUser();
  if (current != null) return current;
  await Auth.startGuest();
  return guideNotebookUser();
}

/// Newest private finds for the Seen lately strip.
///
/// `order` is a negative timestamp, so an ascending `orderByChild` lists
/// newest first. [limit] has to read the start of that index.
///
/// [Query.get] reads the server while online. [Query.once] finishes from
/// the on-disk copy and then stops, so a find deleted on another device
/// stays in this strip until Seen is opened. Disk persistence is on in `main`.
Future<List<GuideFind>> loadRecentFinds(String languageCode,
    {int limit = 5}) async {
  final user = guideNotebookUser();
  if (user == null) return [];
  final snapshot = await privateObservationsReference
      .child(user.uid)
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .orderByChild(firebaseAttributeOrder)
      .limitToFirst(limit)
      .get();
  final value = snapshot.value;
  if (value is! Map) return [];
  final phoneOnly = await guideOnPhoneOnly();

  final rawFinds = <_RawFind>[];
  value.forEach((key, raw) {
    if (raw is! Map) return;
    final name = raw[observationPlant];
    if (name is! String || name.isEmpty) return;
    rawFinds.add(_RawFind(
      name,
      guideFindWhen(raw),
      _ownPhoto(raw),
      confirmed: guideFindConfirmed(raw),
    ));
  });
  rawFinds.sort((a, b) => b.when.compareTo(a.when));

  final lang = getLanguageCode(languageCode);
  return Future.wait(
    rawFinds.map((raw) => _decorateFind(raw, lang, phoneOnly: phoneOnly)),
  );
}

/// Every private find for the Seen notebook, newest first.
///
/// Statistics uses this one-shot read. The Seen page does not: its listener
/// already has the snapshot, and [decorateGuideSeen] fills the rest after
/// the rows are on screen. [Query.get] waits for the server so a stopped
/// listener cannot keep a row on "In review" after the status is `public`.
Future<List<GuideSeenFind>> loadGuideSeen(String languageCode) async {
  final user = guideNotebookUser();
  if (user == null) return [];
  final snapshot = await guideServerGet(
    privateObservationsReference
        .child(user.uid)
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList),
  );
  final value = snapshot.value;
  return decorateGuideSeen(
    guideSeenRows(value),
    languageCode,
    clouds: guideSeenCloudFlags(value),
  );
}

/// Vernaculars, catalog photos, and whether each photo can be shared.
/// A species that is in the book is remembered for the session. A miss is
/// not: the name can be published later. A failed lookup leaves the row
/// unknown so the next pass can try again. A `photoCloud` row does not
/// check Storage.
Future<List<GuideSeenFind>> decorateGuideSeen(
  List<GuideSeenFind> rows,
  String languageCode, {
  required Map<String, bool> clouds,
}) async {
  if (rows.isEmpty) return [];
  final lang = getLanguageCode(languageCode);
  final phoneOnly = await guideOnPhoneOnly();
  final faces = <String, _SeenFace>{};
  final attached = <String, bool>{};
  final names = rows.map((row) => row.name).toSet();
  await Future.wait([
    ...names.map((name) async {
      final needsPhoto = rows.any((row) => row.name == name && !row.ownPhoto);
      final needsCover = rows.any((row) => row.name == name && row.ownPhoto);
      faces[name] = await _seenFace(
        name,
        lang,
        needsPhoto: needsPhoto,
        needsCover: needsCover,
        phoneOnly: phoneOnly,
      );
    }),
    ...rows.map((row) async {
      attached[row.id] = await _photoAttached(
        row,
        cloud: clouds[row.id] ?? false,
        phoneOnly: phoneOnly,
      );
    }),
  ]);
  return [
    for (final row in rows)
      guideSeenApplyCatalog(
        row,
        label: faces[row.name]?.label.value,
        labelKnown: faces[row.name]?.label.known ?? false,
        catalogPhoto: faces[row.name]?.photo.value,
        photoKnown: faces[row.name]?.photo.known ?? false,
        inBook: faces[row.name]?.inBook,
        photoAttached: attached[row.id],
      ),
  ];
}

/// How many private finds are still unconfirmed. Used for the Seen tab badge
/// before the notebook itself is loaded.
Future<int> loadGuideUnconfirmedCount() async {
  final user = guideNotebookUser();
  if (user == null) return 0;
  final event = await privateObservationsReference
      .child(user.uid)
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .once();
  final value = event.snapshot.value;
  if (value is! Map) return 0;
  return countGuideUnconfirmedRows(value);
}

class _SeenRead {
  final String? value;
  final bool known;

  const _SeenRead.known(this.value) : known = true;
  const _SeenRead.unknown()
      : value = null,
        known = false;
}

class _SeenFace {
  final _SeenRead label;
  final _SeenRead photo;

  /// Null when the id read failed.
  final bool? inBook;

  const _SeenFace(this.label, this.photo, this.inBook);
}

Future<_SeenFace> _seenFace(
  String name,
  String languageCode, {
  required bool needsPhoto,
  bool needsCover = false,
  bool? phoneOnly,
}) async {
  final offline = phoneOnly ?? await guideOnPhoneOnly();
  final labelFuture = _seenLabel(name, languageCode, phoneOnly: offline);
  final photoFuture = _seenPhoto(
    name,
    needsPhoto: needsPhoto,
    needsCover: needsCover,
    phoneOnly: offline,
  );
  final inBookFuture = guidePlantInBook(name, phoneOnly: offline);
  return _SeenFace(await labelFuture, await photoFuture, await inBookFuture);
}

Future<_SeenRead> _seenPhoto(
  String name, {
  required bool needsPhoto,
  required bool needsCover,
  required bool phoneOnly,
}) async {
  if (needsPhoto) return _catalogPhoto(name, phoneOnly: phoneOnly);
  if (!needsCover) return const _SeenRead.known(null);
  // The observation file is a different path from the book photo. Headers
  // are already on the phone, so this does not wait on Storage.
  final photos = await guideBookPhotoMap();
  if (photos == null) return const _SeenRead.unknown();
  return _SeenRead.known(photos[name]);
}

Future<_SeenRead> _seenLabel(
  String name,
  String languageCode, {
  required bool phoneOnly,
}) async {
  final cached = translationCache[name];
  if (cached != null && cached.isNotEmpty) return _SeenRead.known(cached);
  try {
    final value = await guideChildValue(
      translationsReference
          .child(languageCode)
          .child(name)
          .child(firebaseAttributeLabel),
      phoneOnly: phoneOnly,
    );
    if (value is String && value.isNotEmpty) {
      translationCache[name] = value;
      return _SeenRead.known(value);
    }
    return const _SeenRead.known(null);
  } catch (error) {
    debugPrint('guide seen label $name: $error');
    return const _SeenRead.unknown();
  }
}

final Map<String, String?> _catalogPhotos = {};
final Set<String> _catalogPhotoFetched = {};

Future<_SeenRead> _catalogPhoto(String name, {required bool phoneOnly}) async {
  if (_catalogPhotoFetched.contains(name)) {
    return _SeenRead.known(_catalogPhotos[name]);
  }
  if (phoneOnly) {
    final photos = await guideBookPhotoMap();
    if (photos == null) return const _SeenRead.unknown();
    final path = photos[name];
    _catalogPhotoFetched.add(name);
    _catalogPhotos[name] = path;
    return _SeenRead.known(path);
  }
  try {
    final event = await plantsReference.child(name).child('photoUrls').once();
    final url = guideFirstText(event.snapshot.value);
    final path = url == null ? null : storagePhotos + url;
    _catalogPhotoFetched.add(name);
    _catalogPhotos[name] = path;
    return _SeenRead.known(path);
  } catch (error) {
    debugPrint('guide seen photo $name: $error');
    return const _SeenRead.unknown();
  }
}

/// Public Sightings: the stored aggregate, and years from the outdoor list.
///
/// The stats node is the headline. When it is missing, the same outdoor rows
/// supply the counts. Indoor rows are left out of the year chart either way.
Future<GuideSightingsLoad> loadGuideSightings() async {
  final stats = guideServerGet(
    publicObservationsReference.child(firebaseObservationsStats),
  );
  final list = guideServerGet(
    publicObservationsReference
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList),
  );
  final statsSnap = await stats;
  final listSnap = await list;
  final stored = guideSightingHeadline(statsSnap.value);
  return GuideSightingsLoad(
    headline: stored ?? guideSightingHeadlineFromRows(listSnap.value),
    years: guideSightingYears(listSnap.value),
  );
}

/// Vernacular, catalog photo, and whether the species is in the book.
/// [GuideStatFace.inBook] is null when that read failed.
Future<GuideStatFace> loadGuidePlantCard(
  String name,
  String languageCode,
) async {
  final lang = getLanguageCode(languageCode);
  final face = await _seenFace(name, lang, needsPhoto: true);
  return GuideStatFace(
    label: face.label.value,
    photoPath: face.photo.value,
    inBook: face.inBook,
  );
}

class _RawFind {
  final String name;
  final DateTime when;
  final String? photoPath;
  final bool confirmed;

  _RawFind(this.name, this.when, this.photoPath, {this.confirmed = true});
}

/// Missing [observationConfirmed] counts as confirmed, matching older rows
/// in the Seen notebook.
@visibleForTesting
bool guideFindConfirmed(Map raw) {
  final value = raw[observationConfirmed];
  return value is bool ? value : true;
}

Future<GuideFind> _decorateFind(
  _RawFind raw,
  String languageCode, {
  required bool phoneOnly,
}) async {
  var photo = raw.photoPath;
  final book = await guideBookPhoto(raw.name);
  if (photo == null) {
    if (book != null && await Offline.getLocalFile(book) != null) {
      photo = book;
    } else if (!phoneOnly) {
      try {
        final value = await guideChildValue(
          plantsReference.child(raw.name).child('photoUrls'),
          phoneOnly: false,
        );
        final url = guideFirstText(value);
        if (url != null) photo = storagePhotos + url;
      } catch (error) {
        debugPrint('guide find photo ${raw.name}: $error');
      }
    }
  }

  String? label = translationCache[raw.name];
  if (label == null || label.isEmpty) {
    try {
      final value = await guideChildValue(
        translationsReference
            .child(languageCode)
            .child(raw.name)
            .child(firebaseAttributeLabel),
        phoneOnly: phoneOnly,
      );
      if (value is String && value.isNotEmpty) {
        label = value;
        translationCache[raw.name] = value;
      } else {
        label = null;
      }
    } catch (error) {
      debugPrint('guide find label ${raw.name}: $error');
      label = null;
    }
  }

  return GuideFind(
    name: raw.name,
    label: label,
    when: raw.when,
    photoPath: photo,
    coverPath: book,
    confirmed: raw.confirmed,
  );
}

String? _ownPhoto(Map raw) {
  return guideFirstText(raw[observationPhotoPaths]);
}

/// A stored path is not a photo on a new phone. The file has to be here,
/// already in private Storage, or already published.
Future<bool> _photoAttached(
  GuideSeenFind row, {
  required bool cloud,
  required bool phoneOnly,
}) async {
  if (!row.ownPhoto) return false;
  final path = row.photoPath;
  if (path == null || path.isEmpty) return false;
  if (cloud) {
    return guideSeenPhotoAttached(local: false, cloud: true, published: false);
  }
  final local = await Offline.getLocalFile(path) != null;
  if (local) {
    return guideSeenPhotoAttached(local: true, cloud: false, published: false);
  }
  // Storage metadata does not finish in flight mode. The next Seen open
  // checks again.
  if (phoneOnly) return false;
  return guideSeenPhotoAttached(
    local: false,
    cloud: false,
    published: await _publishedObservationPhoto(path),
  );
}

final Map<String, bool> _publishedPhoto = {};

Future<bool> _publishedObservationPhoto(String path) async {
  if (!path.startsWith(storageObservations)) return false;
  final known = _publishedPhoto[path];
  if (known != null) return known;
  try {
    await firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
        .ref()
        .child(path)
        .getMetadata();
    return _publishedPhoto[path] = true;
  } on firebase_storage.FirebaseException catch (error) {
    if (error.code == 'object-not-found') {
      return _publishedPhoto[path] = false;
    }
    debugPrint('guide seen photo $path: $error');
    return false;
  } catch (error) {
    debugPrint('guide seen photo $path: $error');
    return false;
  }
}

@visibleForTesting
String? guideFirstText(dynamic raw) {
  if (raw is List) {
    for (final item in raw) {
      if (item != null && item.toString().isNotEmpty) return item.toString();
    }
  } else if (raw is Map) {
    final keys = raw.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      final item = raw[key];
      if (item != null && item.toString().isNotEmpty) return item.toString();
    }
  }
  return null;
}

@visibleForTesting
DateTime guideFindWhen(Map raw) {
  final date = raw[observationDate];
  if (date is Map) {
    final time = date[observationTime];
    if (time is int) return DateTime.fromMillisecondsSinceEpoch(time);
    if (time is num) return DateTime.fromMillisecondsSinceEpoch(time.toInt());
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

Future<void> saveGuideSeen(GuideSeenDraft draft) async {
  final user = await guideNotebookUserReady();
  if (user == null) {
    throw StateError('sign in to save a find');
  }
  final photoPath = draft.photoPath;
  if (photoPath == null || photoPath.isEmpty) {
    throw StateError('a find needs a photo from this device');
  }
  final millis = DateTime.now().millisecondsSinceEpoch;
  final observation = Observation(draft.plant);
  observation.id = '${user.uid}_$millis';
  observation.date = draft.when;
  observation.latitude = draft.latitude;
  observation.longitude = draft.longitude;
  observation.note = '';
  observation.photoPaths = [photoPath];
  observation.status = observationStatusPrivate;
  observation.order = -draft.when.millisecondsSinceEpoch;
  observation.confirmed = true;
  observation.source = observationSourceManual;
  observation.country = '';
  final json = observation.toJson();
  final root = privateObservationsReference.child(user.uid);
  final plantKey = guideObservationPlantKey(draft.plant);
  await root.update({
    '$firebaseObservationsByDate/$firebaseAttributeList/${observation.id}':
        json,
    '$firebaseObservationsByPlant/$plantKey/$firebaseAttributeList/${observation.id}':
        json,
  });
  unawaited(syncGuidePrivatePhotos(onlyId: observation.id));
}
