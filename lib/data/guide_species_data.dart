import 'dart:async';

import 'package:abherbs_flutter/data/guide_rtdb.dart';
import 'package:abherbs_flutter/data/guide_seen_data.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/plant_translation.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

Future<GuideSpecies?> loadGuideSpecies(String name, String languageCode) async {
  try {
    return await _loadGuideSpecies(name, languageCode);
  } on TimeoutException catch (error) {
    // The socket wait already ran. This covers a slow read after it is up.
    debugPrint('guide species $name: retry after $error');
    return _loadGuideSpecies(
      name,
      languageCode,
      wait: const Duration(seconds: 12),
    );
  }
}

Future<GuideSpecies?> _loadGuideSpecies(
  String name,
  String languageCode, {
  Duration wait = guideIndexWait,
}) async {
  final lang = getLanguageCode(languageCode);
  final onPhone = await guideOnPhoneOnly();
  if (onPhone) {
    // No interface, so a socket wait cannot finish. Drop a pending bounce.
    clearGuideDatabasePendingReconnect();
  } else {
    await guideDatabaseConnected();
  }
  // Started with the plant read. A missing translation must not hold the page
  // open past its own timeout. A private find that is not on the phone must
  // not hold it either: the disk copy answers at once, and a server wait does not.
  final translation = _guideTranslation(lang, name, wait: wait);
  final seen = onPhone
      ? _guideSpeciesSeen(name).timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => null,
        )
      : _guideSpeciesSeen(name);
  final DataSnapshot snapshot;
  try {
    snapshot = await guideServerGet(plantsReference.child(name)).timeout(wait);
  } catch (error) {
    debugPrint('guide species $name: $error');
    rethrow;
  }
  final raw = snapshot.value;
  if (!guidePlantRecord(raw)) {
    return null;
  }
  final plant = Map<dynamic, dynamic>.from(raw as Map);
  final latins = guideSpeciesTaxonLatins(plant['APGIV']);
  // Public sightings and family names are not in the offline pack.
  final vernaculars = onPhone
      ? Future<Map<String, String>>.value(const {})
      : _guideVernaculars(lang, latins);
  final sightings = onPhone
      ? Future<List<GuideSighting>>.value(const [])
      : _guideSightings(name);
  return assembleGuideSpecies(
    name: name,
    plant: plant,
    translation: await translation,
    vernaculars: await vernaculars,
    sightings: await sightings,
    seen: await seen,
  );
}

Future<PlantTranslation> _guideTranslation(
  String lang,
  String name, {
  Duration wait = guideIndexWait,
}) async {
  var local = PlantTranslation();
  try {
    final snapshot = await guideServerGet(
      translationsReference.child(lang).child(name),
    ).timeout(wait);
    final raw = snapshot.value;
    if (raw is Map) {
      local = PlantTranslation.fromJson(Map<dynamic, dynamic>.from(raw));
    }
  } catch (error) {
    debugPrint('guide species translation $name: $error');
  }
  if (lang == languageEnglish || local.hasAllBodyFields()) return local;
  try {
    final english = await guideServerGet(
      translationsReference.child(languageEnglish).child(name),
    ).timeout(wait);
    final fallback = english.value;
    if (fallback is Map) {
      local.fillMissingFrom(
        PlantTranslation.fromJson(Map<dynamic, dynamic>.from(fallback)),
      );
    }
  } catch (error) {
    debugPrint('guide species english $name: $error');
  }
  return local;
}

Future<Map<String, String>> _guideVernaculars(
  String lang,
  Set<String> latins,
) async {
  final vernaculars = <String, String>{};
  await Future.wait(latins.map((latin) async {
    try {
      final snapshot = await guideServerGet(
        translationsTaxonomyReference.child(lang).child(latin),
      ).timeout(guideIndexWait);
      final name = guideTaxonVernacular(snapshot.value, latin);
      if (name != null) vernaculars[latin] = name;
    } catch (error) {
      debugPrint('guide species taxon $latin: $error');
    }
  }));
  return vernaculars;
}

Future<List<GuideSighting>> _guideSightings(String name) async {
  try {
    final snapshot = await guideServerGet(
      publicObservationsReference
          .child(firebaseObservationsByPlant)
          .child(name)
          .child(firebaseAttributeList),
    ).timeout(guideIndexWait);
    return guideSightings(snapshot.value);
  } catch (error) {
    debugPrint('guide species sightings $name: $error');
    return const [];
  }
}

Future<GuideSpeciesSeen?> _guideSpeciesSeen(String name) async {
  final user = guideNotebookUser();
  if (user == null) return null;
  try {
    final snapshot = await guideServerGet(
      privateObservationsReference
          .child(user.uid)
          .child(firebaseObservationsByPlant)
          .child(name)
          .child(firebaseAttributeList),
    ).timeout(guideIndexWait);
    final value = snapshot.value;
    final Iterable<dynamic> rows;
    if (value is List) {
      rows = value;
    } else if (value is Map) {
      rows = value.values;
    } else {
      rows = const [];
    }
    return guideSpeciesSeen(rows);
  } catch (error) {
    debugPrint('guide species seen $name: $error');
    return null;
  }
}
