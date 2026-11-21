import 'dart:async';

import 'package:abherbs_flutter/data/guide_catalog.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/data/guide_rtdb.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:flutter/foundation.dart';

/// v3 habitat codes, in the order the key shows them.
const guideHabitatIds = ['4', '1', '7', '8', '3', '9', '5', '10'];
const guidePetalIds = ['1', '2', '3', '4'];
const guideLeafIds = ['1', '2', '3', '4', '5'];
const guideConeIds = ['1', '2', '3'];

class GuideColorCounts {
  final Map<String, int> byColor;

  /// Plants in the book, each once. The empty color key, not the sum of
  /// the five swatches: a flower can carry more than one color.
  final int total;

  const GuideColorCounts({required this.byColor, required this.total});
}

Future<GuideColorCounts> loadColorCounts() async {
  const ids = ['1', '2', '3', '4', '5'];
  final totalKey = guideFilterKey();
  final keys = [
    totalKey,
    for (final id in ids) guideFilterKey(colorId: id),
  ];
  final counts = await _indexCounts(keys, 'guide color counts');
  if (counts != null) {
    return GuideColorCounts(
      byColor: {
        for (final id in ids) id: counts[guideFilterKey(colorId: id)] ?? 0,
      },
      total: counts[totalKey] ?? 0,
    );
  }
  final plants = await loadGuideKeyPlants();
  return GuideColorCounts(
    byColor: {
      for (final id in ids) id: guideKeyCount(plants, colorId: id),
    },
    total: guideKeyCount(plants),
  );
}

String guideFilterKey({
  String? colorId,
  String? habitatId,
  String? petalId,
  String? regionId,
}) {
  return getFilterKey({
    if (colorId != null && colorId.isNotEmpty) filterColor: colorId,
    if (habitatId != null && habitatId.isNotEmpty) filterHabitat: habitatId,
    if (petalId != null && petalId.isNotEmpty) filterPetal: petalId,
    if (regionId != null && regionId.isNotEmpty) filterDistribution: regionId,
  });
}

class GuideHabitatCounts {
  final int total;
  final Map<String, int> byHabitat;

  const GuideHabitatCounts({required this.total, required this.byHabitat});
}

Future<GuideHabitatCounts> loadHabitatCounts(String colorId) async {
  final keys = [
    guideFilterKey(colorId: colorId),
    for (final id in guideHabitatIds)
      guideFilterKey(colorId: colorId, habitatId: id),
  ];
  final counts = await _indexCounts(keys, 'guide habitat counts');
  if (counts != null) {
    return GuideHabitatCounts(
      total: counts[guideFilterKey(colorId: colorId)] ?? 0,
      byHabitat: {
        for (final id in guideHabitatIds)
          id: counts[guideFilterKey(colorId: colorId, habitatId: id)] ?? 0,
      },
    );
  }
  final plants = await loadGuideKeyPlants();
  return GuideHabitatCounts(
    total: guideKeyCount(plants, colorId: colorId),
    byHabitat: {
      for (final id in guideHabitatIds)
        id: guideKeyCount(plants, colorId: colorId, habitatId: id),
    },
  );
}

class GuidePetalCounts {
  final int total;
  final Map<String, int> byPetal;

  const GuidePetalCounts({required this.total, required this.byPetal});
}

/// Counts for the petal step. [GuidePetalCounts.total] is every plant in this
/// color and place, counted once. [GuidePetalCounts.byPetal] is the four tiles.
GuidePetalCounts guidePetalCountsFromPlants(
  Iterable<GuideKeyPlant> plants, {
  required String colorId,
  String? habitatId,
}) {
  return GuidePetalCounts(
    total: guideKeyCount(
      plants,
      colorId: colorId,
      habitatId: habitatId,
      petalId: '',
    ),
    byPetal: {
      for (final id in guidePetalIds)
        id: guideKeyCount(
          plants,
          colorId: colorId,
          habitatId: habitatId,
          petalId: id,
        ),
    },
  );
}

Future<GuidePetalCounts> loadPetalCounts(
  String colorId,
  String? habitatId,
) async {
  final totalKey = guideFilterKey(colorId: colorId, habitatId: habitatId);
  final keys = [
    totalKey,
    for (final id in guidePetalIds)
      guideFilterKey(colorId: colorId, habitatId: habitatId, petalId: id),
  ];
  final counts = await _indexCounts(keys, 'guide petal counts');
  if (counts != null) {
    return GuidePetalCounts(
      total: counts[totalKey] ?? 0,
      byPetal: {
        for (final id in guidePetalIds)
          id: counts[guideFilterKey(
                colorId: colorId,
                habitatId: habitatId,
                petalId: id,
              )] ??
              0,
      },
    );
  }
  return guidePetalCountsFromPlants(
    await loadGuideKeyPlants(),
    colorId: colorId,
    habitatId: habitatId,
  );
}

class GuideLeafCounts {
  final int total;
  final Map<String, int> byLeaf;

  const GuideLeafCounts({required this.total, required this.byLeaf});
}

/// Leaf counts for the conifer key. Headers only: there is no leaf index.
Future<GuideLeafCounts> loadLeafCounts() async {
  final plants = await loadGuideKeyPlants();
  return GuideLeafCounts(
    total: guideConiferCount(plants),
    byLeaf: {
      for (final id in guideLeafIds)
        id: guideConiferCount(plants, leafId: id),
    },
  );
}

Future<GuideHabitatCounts> loadConiferHabitatCounts(String leafId) async {
  final plants = await loadGuideKeyPlants();
  return GuideHabitatCounts(
    total: guideConiferCount(plants, leafId: leafId),
    byHabitat: {
      for (final id in guideHabitatIds)
        id: guideConiferCount(plants, leafId: leafId, habitatId: id),
    },
  );
}

class GuideConeCounts {
  final int total;
  final Map<String, int> byCone;

  const GuideConeCounts({required this.total, required this.byCone});
}

Future<GuideConeCounts> loadConeCounts(
  String leafId,
  String? habitatId,
) async {
  final plants = await loadGuideKeyPlants();
  return GuideConeCounts(
    total: guideConiferCount(
      plants,
      leafId: leafId,
      habitatId: habitatId,
    ),
    byCone: {
      for (final id in guideConeIds)
        id: guideConiferCount(
          plants,
          leafId: leafId,
          habitatId: habitatId,
          coneId: id,
        ),
    },
  );
}

Future<List<GuideResultPlant>> loadConiferResults({
  required String leafId,
  String? habitatId,
  required String coneId,
  String? regionId,
  required String languageCode,
}) async {
  final matched = guideConiferList(
    await loadGuideKeyPlants(),
    leafId: leafId,
    habitatId: habitatId,
    coneId: coneId,
    regionId: regionId,
  );
  final lang = getLanguageCode(languageCode);
  final labels = await guidePhoneLabelsFor(lang);
  return [
    for (final plant in matched)
      plant.toResult(
        label: guideResultLabel(
          plant.name,
          stored: labels,
          cached: translationCache[plant.name],
        ),
      ),
  ];
}

Future<Map<String, int>> loadConiferRegionCounts({
  required String leafId,
  String? habitatId,
  required String coneId,
}) async {
  final plants = await loadGuideKeyPlants();
  final ids = ['', ...guideAllRegionIds];
  return {
    for (final id in ids)
      id: guideConiferCount(
        plants,
        leafId: leafId,
        habitatId: habitatId,
        coneId: coneId,
        regionId: id.isEmpty ? null : id,
      ),
  };
}

Future<List<GuideResultPlant>> loadGuideResults({
  required String colorId,
  String? habitatId,
  required String petalId,
  String? regionId,
  required String languageCode,
}) async {
  final key = guideFilterKey(
    colorId: colorId,
    habitatId: habitatId,
    petalId: petalId,
    regionId: regionId,
  );
  final lang = getLanguageCode(languageCode);
  if (!await guideOnPhoneOnly()) {
    try {
      final snapshot = await guideServerGet(listsV3Reference.child(key))
          .timeout(guideIndexWait);
      final ids = guideResultIds(snapshot.value);
      // An answer that is present and empty is the real list.
      if (ids.isEmpty) return [];
      final plants = await Future.wait(
        ids.map((id) => guideResultPlant(id, lang)),
      );
      return plants.whereType<GuideResultPlant>().toList();
    } catch (error) {
      debugPrint('guide results $key: $error');
    }
  }
  // The list index and the per-plant labels are not in the offline pack.
  // Headers already name the plant and point at the photo stored on the phone.
  final matched = guideKeyMatches(
    await loadGuideKeyPlants(),
    colorId: colorId,
    habitatId: habitatId,
    petalId: petalId,
    regionId: regionId,
  );
  final labels = await guidePhoneLabelsFor(lang);
  return [
    for (final plant in matched)
      plant.toResult(
        label: guideResultLabel(
          plant.name,
          stored: labels,
          cached: translationCache[plant.name],
        ),
      ),
  ];
}

Future<Map<String, int>> loadGuideRegionCounts({
  required String colorId,
  String? habitatId,
  required String petalId,
}) async {
  final ids = ['', ...guideAllRegionIds];
  if (!await guideOnPhoneOnly()) {
    try {
      final entries = await Future.wait(ids.map((id) async {
        final key = guideFilterKey(
          colorId: colorId,
          habitatId: habitatId,
          petalId: petalId,
          regionId: id.isEmpty ? null : id,
        );
        final snapshot = await guideServerGet(countsV3Reference.child(key))
            .timeout(guideIndexWait);
        return MapEntry(id, guideResultInt(snapshot.value));
      }));
      return Map.fromEntries(entries);
    } catch (error) {
      debugPrint('guide region counts: $error');
    }
  }
  final plants = await loadGuideKeyPlants();
  return {
    for (final id in ids)
      id: guideKeyCount(
        plants,
        colorId: colorId,
        habitatId: habitatId,
        petalId: petalId,
        regionId: id.isEmpty ? null : id,
      ),
  };
}

Future<GuideResultPrefs> loadGuideResultPrefs() async {
  final region = await Prefs.getStringF(keyGuideRegion, '');
  final fromLocation = await Prefs.getBoolF(keyGuideRegionFromLocation, false);
  final wildOnly = await Prefs.getBoolF(keyGuideWildOnly, false);
  final refused = await Prefs.getBoolF(keyGuideLocationRefused, false);
  final regionId = region.isEmpty ? null : region;
  return GuideResultPrefs(
    regionId: regionId,
    fromLocation: fromLocation && regionId != null,
    wildOnly: wildOnly,
    locationRefused: refused,
  );
}

Future<void> saveGuideResultPrefs(GuideResultPrefs prefs) async {
  final regionId = prefs.regionId;
  if (regionId == null || regionId.isEmpty) {
    await Prefs.remove(keyGuideRegion);
  } else {
    await Prefs.setString(keyGuideRegion, regionId);
  }
  await Prefs.setBool(keyGuideRegionFromLocation, prefs.fromLocation);
  await Prefs.setBool(keyGuideWildOnly, prefs.wildOnly);
  await Prefs.setBool(keyGuideLocationRefused, prefs.locationRefused);
}

/// The v3 count index, or null when the phone should answer from headers.
Future<Map<String, int>?> _indexCounts(List<String> keys, String label) async {
  if (await guideOnPhoneOnly()) return null;
  try {
    return await _loadV3Counts(keys);
  } catch (error) {
    debugPrint('$label: $error');
    return null;
  }
}

Future<Map<String, int>> _loadV3Counts(List<String> keys) async {
  final entries = await Future.wait(keys.map((key) async {
    final snapshot = await guideServerGet(countsV3Reference.child(key))
        .timeout(guideIndexWait);
    return MapEntry(key, _asInt(snapshot.value));
  }));
  return Map.fromEntries(entries);
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
