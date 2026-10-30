import 'dart:async';
import 'dart:io';

import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/plant.dart';
import 'package:abherbs_flutter/offline/guide_media.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Photos, the unsuffixed plate the app opens, and the range map.
/// `@400` and `@1600` are not fetched: the first is unused, and the second
/// is the same drawing as the unsuffixed file.
List<String> offlinePictureUrls({
  required List<String> photos,
  String? illustrationUrl,
  String? headerUrl,
}) {
  final urls = <String>[];
  void add(String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty || urls.contains(trimmed)) return;
    urls.add(trimmed);
  }

  for (final photo in photos) {
    add(photo);
  }
  add(illustrationUrl);
  add(_distributionUrl(illustrationUrl));
  add(headerUrl);
  return urls;
}

String? _distributionUrl(String? illustrationUrl) {
  if (illustrationUrl == null || illustrationUrl.isEmpty) return null;
  final slash = illustrationUrl.lastIndexOf('/');
  final file =
      slash >= 0 ? illustrationUrl.substring(slash + 1) : illustrationUrl;
  final dot = file.lastIndexOf('.');
  if (dot <= 0) return null;
  final prefix = slash >= 0 ? illustrationUrl.substring(0, slash + 1) : '';
  return prefix +
      file.substring(0, dot) +
      '_distribution' +
      file.substring(dot);
}

Set<int> offlineDoneParse(String raw) {
  final ids = <int>{};
  for (final part in raw.split(',')) {
    final id = int.tryParse(part.trim());
    if (id != null) ids.add(id);
  }
  return ids;
}

String offlineDoneFormat(Set<int> ids) {
  final list = ids.toList()..sort();
  return list.join(',');
}

class Offline {
  static bool downloadFinished = false;
  static bool downloadPaused = false;
  static int _generation = 0;

  /// Starts one download. An older job no longer owns its callbacks, so a
  /// second download does not resume the one that was paused.
  static int claimDownload() {
    _generation++;
    downloadPaused = false;
    return _generation;
  }

  /// Stops the current download. Its finish callback must not save the pack.
  static void pauseDownload() {
    _generation++;
    downloadPaused = true;
  }

  static bool ownsDownload(int generation) {
    return generation == _generation && !downloadPaused;
  }

  static var _httpClient = HttpClient();
  static String _rootPath = '';
  static bool _offline = false;
  static bool _downloadDB = false;
  static String _downloadDBDate = '';
  static List<bool> _keepSynced = [false, false, false, false];

  static void initialize() {
    getApplicationDocumentsDirectory().then((dir) {
      _rootPath = dir.path;
    });

    Prefs.getBoolF(keyOffline, false).then((value) {
      _offline = value;
      if (value) {
        Prefs.getStringF(keyOfflinePlant, '0').then((value) {
          rootReference
              .child(firebasePlantsToUpdate)
              .child(firebaseAttributeCount)
              .once()
              .then((event) {
            downloadFinished = event.snapshot.value == null ||
                int.parse(value) >= (event.snapshot.value as int);
          });
        }).catchError((_) {
          // deal with previous int shared preferences
          Prefs.getIntF(keyOfflinePlant, 0).then((value) {
            Prefs.setString(keyOfflinePlant, value.toString());
            rootReference
                .child(firebasePlantsToUpdate)
                .child(firebaseAttributeCount)
                .once()
                .then((event) {
              downloadFinished = event.snapshot.value == null ||
                  value >= (event.snapshot.value as int);
            });
          });
          Prefs.getIntF(keyOfflineFamily, 0).then((value) {
            Prefs.setString(keyOfflineFamily, value.toString());
          });
        });
        rootReference
            .child(firebaseVersions)
            .child(firebaseAttributeLastUpdate)
            .once()
            .then((event) {
          if (event.snapshot.value != null) {
            Prefs.getStringF(keyOfflineDB, '').then((value) {
              _downloadDBDate = event.snapshot.value as String;
              DateTime dbUpdate = DateTime.parse(_downloadDBDate);
              _downloadDB =
                  value.isEmpty || dbUpdate.isAfter(DateTime.parse(value));
            });
          }
        });
      } else {
        downloadFinished = false;
        _downloadDB = false;
      }
    });
  }

  static onChange(bool offline) {
    _offline = offline;
    _downloadDB = offline;
    downloadFinished = false;
    _keepSynced = [false, false, false, false];
  }

  static void finalizeDownloadDB() {
    if (_offline && _keepSynced.reduce((value, item) => value && item)) {
      Prefs.setString(keyOfflineDB, _downloadDBDate);
      _downloadDB = false;
    }
  }

  static Future<void> setKeepSynced(int section, bool value) async {
    if (!value || (_offline && _downloadDB && !_keepSynced[section - 1])) {
      var reference = FirebaseDatabase.instance.ref();
      switch (section) {
        case 1:
          await guideKeepSynced(reference.child(firebaseCountsV3), value);
          await guideKeepSynced(
            reference.child(firebaseFamiliesToUpdate),
            value,
          );
          await guideKeepSynced(
            reference.child(firebasePlantsToUpdate),
            value,
          );
          break;
        case 2:
          await guideKeepSynced(reference.child(firebaseListsV3), value);
          await guideKeepSynced(
            reference.child(firebasePlantHeadersV3),
            value,
          );
          // Families, genera, and the flower lists. The pictures stay with
          // the plants; these indexes are what Book opens.
          await guideKeepSynced(reference.child(firebaseAPGIV), value);
          await guideKeepSynced(reference.child(firebaseListsCustom), value);
          break;
        case 3:
          await guideKeepSynced(reference.child(firebasePlants), value);
          await guideKeepSynced(reference.child(firebaseSynonyms), value);
          var language =
              await Prefs.getStringListF(keyLanguageAndCountry, ['en', 'US']);
          final code = getLanguageCode(language[0]);
          await guideKeepSynced(
            reference.child(firebaseTranslations).child(code),
            value,
          );
          await guideKeepSynced(
            reference.child(firebaseTranslationsTaxonomy).child(language[0]),
            value,
          );
          if (code != languageEnglish) {
            await guideKeepSynced(
              reference.child(firebaseTranslations).child(languageEnglish),
              value,
            );
          }
          break;
        case 4:
          // A pack removal releases the search index an earlier build pinned.
          if (!value) {
            await guideKeepSynced(reference.child(firebaseAPGIV), false);
            await guideKeepSynced(reference.child(firebaseListsCustom), false);
            await guideKeepSynced(
              reference.child(firebaseSearch).child(languageLatin),
              false,
            );
            var language = await Prefs.getStringListF(
              keyLanguageAndCountry,
              ['en', 'US'],
            );
            await guideKeepSynced(
              reference.child(firebaseSearch).child(language[0]),
              false,
            );
          }
          break;
      }
      _keepSynced[section - 1] = value;
      _keepSynced[3] = value;
      finalizeDownloadDB();
    }
  }

  /// Pictures for [plantIds] only. [alreadyDone] plants in this pack are
  /// already on the phone, and [total] is the pack size the progress bar uses.
  /// [generation] is the job from [claimDownload]. A pause or a newer download
  /// drops this job's callbacks.
  static void downloadPack({
    required List<int> plantIds,
    required int alreadyDone,
    required int total,
    required void Function(int done, int total) onPlant,
    required void Function() onFinish,
    required void Function() onFail,
    required int generation,
  }) {
    if (!ownsDownload(generation)) return;
    unawaited(_runDownloadPack(
      plantIds: plantIds,
      alreadyDone: alreadyDone,
      total: total,
      onPlant: onPlant,
      onFinish: onFinish,
      onFail: onFail,
      generation: generation,
    ));
  }

  static Future<void> _runDownloadPack({
    required List<int> plantIds,
    required int alreadyDone,
    required int total,
    required void Function(int done, int total) onPlant,
    required void Function() onFinish,
    required void Function() onFail,
    required int generation,
  }) async {
    if (!ownsDownload(generation)) return;
    onChange(true);
    for (var i = 1; i <= 4; i++) {
      setKeepSynced(i, true);
    }
    if (!ownsDownload(generation)) return;
    if (alreadyDone > 0 && total > 0) onPlant(alreadyDone, total);
    try {
      final results = await Future.wait([
        downloadFamilies((_, __) {}, generation),
        _downloadPlantIds(plantIds, alreadyDone, total, onPlant, generation),
      ]);
      if (!ownsDownload(generation)) return;
      downloadFinished = results.every((item) => item);
      if (downloadFinished) {
        onFinish();
      } else {
        onFail();
      }
    } catch (error) {
      debugPrint('offline pack: $error');
      if (ownsDownload(generation)) onFail();
    }
  }

  static Future<bool> downloadFamilies(
    Function(int, int) onFamilyDownload,
    int generation,
  ) async {
    int position = int.parse(await Prefs.getStringF(keyOfflineFamily, '0'));
    if (!ownsDownload(generation)) return true;
    int familyTotal = await FirebaseDatabase.instance
        .ref()
        .child(firebaseFamiliesToUpdate)
        .child(firebaseAttributeCount)
        .once()
        .then((event) {
      return event.snapshot.value as int;
    });
    while (position < familyTotal) {
      if (!ownsDownload(generation)) return true;
      if (await _downloadFamilyIcon(position)) {
        if (!ownsDownload(generation)) return true;
        position++;
        Prefs.setString(keyOfflineFamily, position.toString());
        onFamilyDownload(position, familyTotal);
      } else {
        if (!ownsDownload(generation)) return true;
        return false;
      }
    }
    if (!ownsDownload(generation)) return true;
    onFamilyDownload(position, familyTotal);
    return true;
  }

  static Future<bool> _downloadFamilyIcon(int position) async {
    String family = await FirebaseDatabase.instance
        .ref()
        .child(firebaseFamiliesToUpdate)
        .child(firebaseAttributeList)
        .child(position.toString())
        .once()
        .then((event) {
      return event.snapshot.value as String;
    });
    if (family.isNotEmpty) {
      try {
        await _downloadFile(
          storageEndpoint + storageFamilies + family + defaultExtension,
          storageFamilies,
          family + defaultExtension,
        );
        return true;
      } catch (e) {
        FirebaseCrashlytics.instance.recordError(e, null,
            reason: 'Failed to download family icon $family');
      }
    }
    return false;
  }

  static Future<bool> _downloadPlantIds(
    List<int> plantIds,
    int alreadyDone,
    int total,
    void Function(int done, int total) onPlant,
    int generation,
  ) async {
    var finished = alreadyDone;
    for (final id in plantIds) {
      if (!ownsDownload(generation)) return true;
      if (!await _downloadPlantPhotos(id)) {
        if (!ownsDownload(generation)) return true;
        return false;
      }
      if (!ownsDownload(generation)) return true;
      finished++;
      await _rememberPlant(id);
      if (!ownsDownload(generation)) return true;
      onPlant(finished, total);
    }
    if (!ownsDownload(generation)) return true;
    onPlant(finished, total);
    return true;
  }

  static Set<int>? _done;

  static Future<void> _rememberPlant(int id) async {
    final ids = _done ??
        offlineDoneParse(await Prefs.getStringF(keyGuideOfflineDone, ''));
    ids.add(id);
    _done = ids;
    await Prefs.setString(keyGuideOfflineDone, offlineDoneFormat(ids));
  }

  static Future<void> clearDone() async {
    _done = <int>{};
    await Prefs.remove(keyGuideOfflineDone);
  }

  static Future<bool> _downloadPlantPhotos(int position) async {
    final header = await _plantHeader(position);
    if (header == null) return false;
    final event = await FirebaseDatabase.instance
        .ref()
        .child(firebasePlants)
        .child(header.name)
        .once();
    final value = event.snapshot.value;
    if (value is! Map) return false;
    final plant = Plant.fromJson(event.snapshot.key ?? '', value);
    if (plant.name.isEmpty) return false;
    final urls = offlinePictureUrls(
      photos: [
        for (final url in plant.photoUrls)
          if (url != null) url.toString(),
      ],
      illustrationUrl: plant.illustrationUrl,
      headerUrl: header.url,
    );
    if (urls.isEmpty) return false;
    final saved = <GuideMediaFile>[];
    for (final url in urls) {
      final optional = url.contains('_distribution.');
      try {
        final bytes = await _downloadBytes(
          storageEndpoint + storagePhotos + url,
          _photoDir(url),
          _photoName(url),
        );
        saved.add(
          GuideMediaFile(
            url: url,
            bytes: bytes.length,
            hash: guideMediaHash(bytes),
          ),
        );
      } catch (e) {
        if (optional) {
          debugPrint('offline map missing $url');
          continue;
        }
        FirebaseCrashlytics.instance
            .recordError(e, null, reason: 'Failed to download photo $url');
        return false;
      }
    }
    await writeStamp(
      position,
      guideMediaStampFromFiles(
        saved,
        plateUrl: plant.illustrationUrl,
      ),
    );
    return true;
  }

  /// Changed pictures for plants already in a pack. A missing map is skipped.
  /// Finished plants keep their new stamp so a pause does not fetch them again.
  static void downloadChanges({
    required List<GuideMediaJob> plants,
    required void Function(int doneBytes, int totalBytes) onProgress,
    required void Function() onFinish,
    required void Function() onFail,
    required int generation,
  }) {
    if (!ownsDownload(generation)) return;
    unawaited(_runDownloadChanges(
      plants: plants,
      onProgress: onProgress,
      onFinish: onFinish,
      onFail: onFail,
      generation: generation,
    ));
  }

  static Future<void> _runDownloadChanges({
    required List<GuideMediaJob> plants,
    required void Function(int doneBytes, int totalBytes) onProgress,
    required void Function() onFinish,
    required void Function() onFail,
    required int generation,
  }) async {
    if (!ownsDownload(generation)) return;
    onChange(true);
    for (var section = 1; section <= 4; section++) {
      setKeepSynced(section, true);
    }
    var total = 0;
    for (final plant in plants) {
      total += plant.bytes;
    }
    if (!ownsDownload(generation)) return;
    onProgress(0, total);
    try {
      final ok = await _downloadChanges(plants, total, onProgress, generation);
      if (!ownsDownload(generation)) return;
      if (ok) {
        downloadFinished = true;
        onFinish();
      } else {
        downloadFinished = false;
        onFail();
      }
    } catch (error) {
      debugPrint('offline changes: $error');
      if (ownsDownload(generation)) onFail();
    }
  }

  static Future<bool> _downloadChanges(
    List<GuideMediaJob> plants,
    int total,
    void Function(int doneBytes, int totalBytes) onProgress,
    int generation,
  ) async {
    var done = 0;
    for (final plant in plants) {
      if (!ownsDownload(generation)) return true;
      final saved = <GuideMediaFile>[];
      final fetching = {for (final file in plant.download) file.url};
      for (final file in plant.stamp.files) {
        if (!ownsDownload(generation)) return true;
        if (!fetching.contains(file.url)) {
          saved.add(file);
          continue;
        }
        try {
          final bytes = await _downloadBytes(
            storageEndpoint + storagePhotos + file.url,
            _photoDir(file.url),
            _photoName(file.url),
          );
          if (!ownsDownload(generation)) return true;
          saved.add(
            GuideMediaFile(
              url: file.url,
              bytes: bytes.length,
              hash: guideMediaHash(bytes),
            ),
          );
          done += file.bytes;
          onProgress(done, total);
        } catch (e) {
          if (!ownsDownload(generation)) return true;
          if (file.url.contains('_distribution.')) {
            debugPrint('offline map missing ${file.url}');
            continue;
          }
          FirebaseCrashlytics.instance.recordError(
            e,
            null,
            reason: 'Failed to download photo ${file.url}',
          );
          return false;
        }
      }
      if (!ownsDownload(generation)) return true;
      for (final url in plant.remove) {
        await _deleteUrl(url);
      }
      if (!ownsDownload(generation)) return true;
      await writeStamp(
        plant.id,
        guideMediaStampFromFiles(saved, plateUrl: plant.stamp.plate?.url),
      );
    }
    if (!ownsDownload(generation)) return true;
    onProgress(total, total);
    return true;
  }

  static Future<void> _deleteUrl(String url) async {
    await _ensureRoot();
    final file = File('$_rootPath/${_photoDir(url)}/${_photoName(url)}');
    if (await file.exists()) await file.delete();
  }

  static Future<_PlantHeader?> _plantHeader(int position) async {
    final v3 = await guideServerGet(
      headersV3Reference.child(position.toString()),
    );
    final header = _readHeader(v3.value);
    if (header != null) return header;
    final event = await FirebaseDatabase.instance
        .ref()
        .child(firebasePlantHeaders)
        .child(position.toString())
        .once();
    return _readHeader(event.snapshot.value);
  }

  static _PlantHeader? _readHeader(dynamic value) {
    if (value is! Map) return null;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return null;
    final url = value[firebaseAttributeUrl];
    return _PlantHeader(name, url is String && url.isNotEmpty ? url : null);
  }

  static String _photoDir(String url) {
    final slash = url.lastIndexOf('/');
    if (slash < 0) return storagePhotos;
    return storagePhotos + url.substring(0, slash);
  }

  static String _photoName(String url) {
    final slash = url.lastIndexOf('/');
    if (slash < 0) return url;
    return url.substring(slash + 1);
  }

  static Future<void> delete() async {
    setKeepSynced(1, false);
    setKeepSynced(2, false);
    setKeepSynced(3, false);
    setKeepSynced(4, false);
    if (_rootPath.isEmpty) {
      _rootPath = (await getApplicationDocumentsDirectory()).path;
    }
    Future<void> removeDirectory(String name) async {
      final directory = Directory('$_rootPath/$name');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }

    await Future.wait([
      removeDirectory(storageFamilies),
      removeDirectory(storagePhotos),
    ]);
    await Prefs.setString(keyOfflineFamily, '0');
    await Prefs.setString(keyOfflinePlant, '0');
    await Prefs.remove(keyOfflineDB);
    await Prefs.remove(keyGuideOfflineChange);
    await clearDone();
    await clearStamps();
  }

  static Future<List<int>> _downloadBytes(
    String url,
    String dir,
    String filename,
  ) async {
    var request = await _httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    if (response.statusCode != 200) {
      await response.drain();
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    var bytes = await consolidateHttpClientResponseBytes(response);
    await _ensureRoot();
    await Directory('$_rootPath/$dir').create(recursive: true);
    await File('$_rootPath/$dir/$filename').writeAsBytes(bytes);
    return bytes;
  }

  static Future<File> _downloadFile(
      String url, String dir, String filename) async {
    await _downloadBytes(url, dir, filename);
    return File('$_rootPath/$dir/$filename');
  }

  static Future<void> _ensureRoot() async {
    if (_rootPath.isEmpty) {
      _rootPath = (await getApplicationDocumentsDirectory()).path;
    }
  }

  static Future<File> _stampFile() async {
    await _ensureRoot();
    return File('$_rootPath/guide_offline_stamps.json');
  }

  static Future<Map<int, GuideMediaStamp>> readStamps() async {
    try {
      final file = await _stampFile();
      if (!await file.exists()) return {};
      return decodeGuideStamps(await file.readAsString());
    } catch (error) {
      debugPrint('offline stamps: $error');
      return {};
    }
  }

  static Future<void> writeStamp(int id, GuideMediaStamp stamp) async {
    final stamps = await readStamps();
    stamps[id] = stamp;
    final file = await _stampFile();
    await file.writeAsString(encodeGuideStamps(stamps));
  }

  static Future<void> clearStamps() async {
    try {
      final file = await _stampFile();
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('offline stamps: $error');
    }
  }

  /// Hash the pictures already in this plant's folder. Used when a pack was
  /// stored before stamps existed, so a later change does not fetch every file.
  static Future<GuideMediaStamp> stampFromDisk(GuideMediaStamp desired) async {
    await _ensureRoot();
    final dirs = <String>{};
    for (final file in desired.files) {
      dirs.add(_photoDir(file.url));
    }
    final found = <GuideMediaFile>[];
    for (final dir in dirs) {
      final directory = Directory('$_rootPath/$dir');
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.webp')) continue;
        if (name.contains('@400') || name.contains('@1600')) continue;
        final prefix = dir.startsWith(storagePhotos)
            ? dir.substring(storagePhotos.length)
            : '';
        final url = prefix.isEmpty ? name : '$prefix/$name';
        final bytes = await entity.readAsBytes();
        found.add(
          GuideMediaFile(
            url: url,
            bytes: bytes.length,
            hash: guideMediaHash(bytes),
          ),
        );
      }
    }
    return guideMediaStampFromFiles(found, plateUrl: desired.plate?.url);
  }

  static Future<File?> getLocalFile(String filename) async {
    if (_rootPath.isEmpty) {
      _rootPath = (await getApplicationDocumentsDirectory()).path;
    }
    final File file = File('$_rootPath/$filename');
    return file.exists().then((exists) {
      return exists ? file : null;
    });
  }
}

class _PlantHeader {
  final String name;
  final String? url;

  const _PlantHeader(this.name, this.url);
}
