import 'dart:async';

import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/data/guide_rtdb.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter/foundation.dart';

/// Header for one catalog id. [Query.get] so a plant added after
/// `plants_headers_v3` was cached on disk is not read back as missing.
Future<GuideResultPlant?> guideResultPlant(String id, String language) async {
  try {
    final snapshot = await guideServerGet(headersV3Reference.child(id))
        .timeout(guideIndexWait);
    final value = snapshot.value;
    if (value is! Map) return null;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return null;
    final label = await _resultLabel(language, name);
    final plate = await _resultPlate(name);
    return readGuideResultHeader(id, value, label: label, platePath: plate);
  } on TimeoutException {
    rethrow;
  } catch (error) {
    debugPrint('guide result $id: $error');
    return null;
  }
}

Future<GuideResultPlant?> _guideHeaderPlant(String id, String language) async {
  try {
    final snapshot =
        await guideServerGet(listsReference.child(id)).timeout(guideIndexWait);
    final value = snapshot.value;
    if (value is! Map) return null;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return null;
    final label = await _resultLabel(language, name);
    final plate = await _resultPlate(name);
    return readGuideResultHeader(id, value, label: label, platePath: plate);
  } on TimeoutException {
    rethrow;
  } catch (error) {
    debugPrint('guide list header $id: $error');
    return null;
  }
}

Future<String?> _resultLabel(String language, String name) async {
  final cached = translationCache[name];
  if (cached != null && cached.isNotEmpty) return cached;
  try {
    final snapshot = await guideServerGet(
      translationsReference
          .child(language)
          .child(name)
          .child(firebaseAttributeLabel),
    ).timeout(guideIndexWait);
    final value = snapshot.value;
    if (value is String && value.isNotEmpty) {
      translationCache[name] = value;
      return value;
    }
  } catch (error) {
    debugPrint('guide result label $name: $error');
  }
  return null;
}

Future<String?> _resultPlate(String name) async {
  try {
    final snapshot = await guideServerGet(
      plantsReference.child(name).child('illustrationUrl'),
    ).timeout(guideIndexWait);
    final value = snapshot.value;
    if (value is String && value.isNotEmpty) return value;
  } catch (error) {
    debugPrint('guide result plate $name: $error');
  }
  return null;
}

/// Flowering months. A failed read is not stored, so the next call tries again.
@visibleForTesting
class GuideBloomCache {
  Map<String, GuideHeaderBloom>? stored;

  Future<Map<String, GuideHeaderBloom>> read(
    Future<Map<String, GuideHeaderBloom>> Function() load,
  ) {
    final ready = stored;
    if (ready != null) return Future.value(ready);
    return load().then((map) {
      stored = map;
      return map;
    });
  }
}

final _bloomCache = GuideBloomCache();

Future<Map<String, GuideHeaderBloom>> _bloomsFromKeyPlants() async {
  final plants = await guideKeyPlantsById();
  return {
    for (final plant in plants.values)
      plant.id: GuideHeaderBloom(
        plant.name,
        plant.floweringFrom,
        plant.floweringTo,
      ),
  };
}

@visibleForTesting
Map<String, GuideHeaderBloom> guideBloomsFromSnapshot(dynamic raw) {
  final blooms = readGuideHeaderBlooms(raw);
  if (blooms.isEmpty) throw StateError('plants_headers_v3 is empty');
  return blooms;
}

Future<Map<String, GuideHeaderBloom>> guideLoadHeaderBlooms() {
  return _bloomCache.read(() {
    return guideReadOrPack(
      () async => guideBloomsFromSnapshot(
        (await headersV3Reference.once()).snapshot.value,
      ),
      _bloomsFromKeyPlants,
      label: 'guide blooms',
    ).then((read) => read.value);
  });
}

Map<String, GuideKeyPlant>? _keyById;
Future<Map<String, GuideKeyPlant>>? _keyByIdLoad;

Future<Map<String, GuideKeyPlant>> guideKeyPlantsById() {
  final ready = _keyById;
  if (ready != null) return Future.value(ready);
  final pending = _keyByIdLoad;
  if (pending != null) return pending;
  final load = _loadKeyPlantsById();
  _keyByIdLoad = load;
  return load.whenComplete(() {
    if (identical(_keyByIdLoad, load)) _keyByIdLoad = null;
  });
}

Future<Map<String, GuideKeyPlant>> _loadKeyPlantsById() async {
  final plants = await loadGuideKeyPlants();
  final map = {for (final plant in plants) plant.id: plant};
  _keyById = map;
  return map;
}

/// Per-language labels. A second request joins the load. A failure is not stored.
@visibleForTesting
class GuideLabelCache {
  final Map<String, Map<String, String>> _cached = {};
  final Map<String, Future<Map<String, String>>> _loading = {};

  Future<Map<String, String>> labels(
    String language,
    Future<Map<String, String>> Function(String language) read,
  ) {
    final cached = _cached[language];
    if (cached != null) return Future.value(cached);
    final pending = _loading[language];
    if (pending != null) return pending;
    final load = read(language).then((map) {
      _cached[language] = map;
      return map;
    });
    _loading[language] = load;
    load.whenComplete(() {
      if (identical(_loading[language], load)) _loading.remove(language);
    }).ignore();
    return load;
  }
}

final _phoneLabelCache = GuideLabelCache();

Future<Map<String, String>> guidePhoneLabelsFor(String language) {
  return _phoneLabelCache.labels(language, _loadPhoneLabels).then(
    (map) => map,
    onError: (Object error, StackTrace _) {
      debugPrint('guide labels: $error');
      return const <String, String>{};
    },
  );
}

@visibleForTesting
Map<String, String> guideLabelsFromSnapshot(dynamic value) {
  if (value is! Map) throw StateError('guide labels');
  final map = <String, String>{};
  value.forEach((key, raw) {
    if (raw is! Map) return;
    final label = raw[firebaseAttributeLabel];
    if (label is String && label.isNotEmpty) map[key.toString()] = label;
  });
  return map;
}

Future<Map<String, String>> _loadPhoneLabels(String language) async {
  final snapshot = await guideServerGet(translationsReference.child(language))
      .timeout(guideIndexWait);
  return guideLabelsFromSnapshot(snapshot.value);
}

Future<GuideResultPlant?> guideCatalogPlant(
  String id,
  String language, {
  required bool phoneOnly,
}) async {
  if (!phoneOnly) {
    try {
      return await guideResultPlant(id, language) ??
          await _guideHeaderPlant(id, language);
    } on TimeoutException {
      debugPrint('guide catalog $id: timed out');
    }
  }
  final plants = await guideKeyPlantsById();
  final plant = plants[id];
  if (plant == null) return null;
  final labels = await guidePhoneLabelsFor(language);
  final label = guideResultLabel(
    plant.name,
    stored: labels,
    cached: translationCache[plant.name],
  );
  return plant.toResult(label: label);
}

Future<List<GuideKeyPlant>>? _keyPlants;

/// Headers fetched for the offline pack. Cached for this session.
Future<List<GuideKeyPlant>> loadGuideKeyPlants() {
  return _keyPlants ??= _readKeyPlants();
}

Future<List<GuideKeyPlant>> _readKeyPlants() async {
  try {
    final snapshot =
        await guideServerGet(headersV3Reference).timeout(guideIndexWait);
    final plants = readGuideKeyPlants(snapshot.value);
    if (plants.isEmpty) {
      throw StateError('plants_headers_v3 is empty');
    }
    unawaited(guideKeepSynced(headersV3Reference, true));
    return plants;
  } catch (error) {
    _keyPlants = null;
    _keyById = null;
    rethrow;
  }
}

/// `plants_headers_v3` photo for [name], or null when the headers are not
/// on the phone. Cached for the session.
Future<String?> guideBookPhoto(String name) async {
  final photos = await guideBookPhotoMap();
  return photos?[name];
}

Map<String, String?>? _bookPhotos;

Future<Map<String, String?>?> guideBookPhotoMap() async {
  final known = _bookPhotos;
  if (known != null) return known;
  try {
    final plants = await loadGuideKeyPlants();
    final photos = <String, String?>{
      for (final plant in plants) plant.name: plant.photoPath,
    };
    _bookPhotos = photos;
    return photos;
  } catch (error) {
    debugPrint('guide book photo: $error');
    return null;
  }
}

final Map<String, bool> _plantInBookCache = {};

/// Session memory for a `plants_v2` id.
///
/// Presence stays. A miss does not: Seen would keep "Not in the book"
/// after the species is published. A failed read is null and is not stored.
/// When [cache] already holds this name, [read] is ignored.
@visibleForTesting
bool? guideRememberPlantInBook(
  Map<String, bool> cache,
  String name,
  bool? read,
) {
  if (cache[name] == true) return true;
  if (read == null) return null;
  if (read) cache[name] = true;
  return read;
}

/// Null when the read failed. That failure is left out of the cache.
///
/// [Query.get] reads the server while online. [Query.once] would finish
/// from the on-disk copy, so a name looked up before it was published
/// stays missing. Disk persistence is on in `main`.
Future<bool?> guidePlantInBook(String name, {bool phoneOnly = false}) async {
  if (_plantInBookCache[name] == true) return true;
  if (phoneOnly) {
    final photos = await guideBookPhotoMap();
    if (photos == null) return null;
    return guideRememberPlantInBook(
      _plantInBookCache,
      name,
      photos.containsKey(name),
    );
  }
  try {
    final snapshot = await guideServerGet(
      plantsReference.child(name).child('id'),
    );
    final value = snapshot.value;
    final inBook = value != null && value.toString().isNotEmpty;
    return guideRememberPlantInBook(_plantInBookCache, name, inBook);
  } catch (error) {
    debugPrint('guide seen plant $name: $error');
    return null;
  }
}
