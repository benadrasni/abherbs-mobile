import 'dart:async';

import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/data/plant_translation.dart';
import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:abherbs_flutter/seen/guide_private_photos.dart';
import 'package:abherbs_flutter/data/guide_favorites.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/search/guide_search.dart';
import 'package:abherbs_flutter/seen/guide_seen.dart';
import 'package:abherbs_flutter/seen/guide_stats.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/widgets.dart';

/// Families opens first. All lists on Find switches to [lists].
enum GuideBookSegment { families, genera, lists }

class GuideListCover {
  final String title;
  final String? photoPath;
  final List<String> thumbs;
  final DatabaseReference path;
  final bool isNew;
  final int count;
  final int? year;
  final int? yearFrom;
  final DateTime? latest;

  /// True when the list has a campaign `sourceUrl`.
  final bool hasSource;

  /// Extra classifier, such as a country epithet. Year values count too.
  final String parameter;

  /// True when plant values are state names rather than years.
  final bool labeled;

  /// The signed-in account's favorite flowers. Not an editorial list.
  final bool isFavorite;

  GuideListCover({
    required this.title,
    required this.photoPath,
    required this.path,
    required this.isNew,
    required this.count,
    this.thumbs = const [],
    this.year,
    this.yearFrom,
    this.latest,
    this.hasSource = false,
    this.parameter = '',
    this.labeled = false,
    this.isFavorite = false,
  });
}

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

const guideHabitatRouteName = 'GuideHabitat';
const guidePetalRouteName = 'GuidePetal';
const guideResultsRouteName = 'GuideResults';
const guideListRouteName = 'GuideList';
const guideSpeciesRouteName = 'GuideSpecies';
const guidePersonRouteName = 'GuidePerson';
const guideLanguageRouteName = 'GuideLanguage';
const guideFieldGuideRouteName = 'GuideFieldGuide';
const guideOfflineRouteName = 'GuideOffline';
const guideStatsRouteName = 'GuideStats';
const guideSearchRouteName = 'GuideSearch';
const guideCameraRouteName = 'GuideCamera';
const guideOutsideRouteName = 'GuideOutside';
const guideCustomRouteName = 'GuideCustom';

/// How a custom list opens. Year values use the timeline. State names use
/// that same list, labeled and ordered by state. New in the book groups
/// recent additions by date. Everything else uses the result grid.
enum GuideCustomLayout { fresh, grid, years }

GuideCustomLayout guideCustomLayout(GuideListCover cover) {
  if (cover.isNew) return GuideCustomLayout.fresh;
  if (cover.year != null || cover.labeled) return GuideCustomLayout.years;
  return GuideCustomLayout.grid;
}

/// Newest days of `lists_custom/new`, kept whole while the plant count
/// stays inside this band. A day is shortened only when leaving it whole
/// would pass the maximum before the minimum is met.
const guideNewPlantMin = 15;
const guideNewPlantMax = 25;

/// Tab actions for the field-guide shell. A pushed page cannot see the
/// shell's inherited widgets, so it calls these.
class GuideTabs {
  /// The shell tab under any pushed page. The landscape rail reads it.
  static int index = 0;
  static void Function(int index)? show;
  static VoidCallback? showSeen;
  static VoidCallback? refreshSeen;

  /// Opens Person. The shell sets this; a rail on a pushed page calls it.
  static void Function(BuildContext context)? openPerson;

  /// Unconfirmed finds waiting on Seen. The shell writes this. Every bottom
  /// bar reads it, including bars on pages pushed over the shell.
  static final ValueNotifier<int> unconfirmed = ValueNotifier(0);
}

/// Leaves the key, or a custom list, and opens a shell tab. Find stays
/// selected while the key is open; tapping Find, Book, or Seen returns to
/// that tab.
void leaveGuideKeyForTab(BuildContext context, int index) {
  GuideTabs.show?.call(index);
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guideCustomRouteName && !guideIsKeyRoute(name);
  });
}

/// Opens a shell tab and drops every page pushed over it.
void guideRailSelect(BuildContext context, int index) {
  GuideTabs.show?.call(index);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Person in the landscape rail. A page already on Person stays there.
void guideRailPerson(BuildContext context) {
  final navigator = Navigator.of(context);
  if (ModalRoute.of(context)?.settings.name == guidePersonRouteName) return;
  var found = false;
  navigator.popUntil((route) {
    if (route.settings.name == guidePersonRouteName) found = true;
    return route.isFirst || found;
  });
  if (!found) GuideTabs.openPerson?.call(navigator.context);
}

bool guideIsKeyRoute(String? name) {
  return name == guideHabitatRouteName ||
      name == guidePetalRouteName ||
      name == guideResultsRouteName;
}

void popGuideKeyToFind(BuildContext context) {
  Navigator.popUntil(context, (route) => !guideIsKeyRoute(route.settings.name));
}

/// The key on the camera returns to Find, including when search or the key
/// is still underneath.
void leaveGuideCameraForFind(BuildContext context) {
  GuideTabs.show?.call(0);
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guideCameraRouteName &&
        name != guideOutsideRouteName &&
        name != guideSearchRouteName &&
        !guideIsKeyRoute(name);
  });
}

void popGuideKeyToHabitat(BuildContext context) {
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guidePetalRouteName && name != guideResultsRouteName;
  });
}

/// v3 habitat codes, in the order the key shows them.
const guideHabitatIds = ['4', '1', '7', '8', '3', '9', '5', '10'];
const guidePetalIds = ['1', '2', '3', '4'];

Future<Map<String, int>> loadColorCounts() async {
  const ids = ['1', '2', '3', '4', '5'];
  final keys = [for (final id in ids) guideFilterKey(colorId: id)];
  final counts = await _indexCounts(keys, 'guide color counts');
  if (counts != null) {
    return {
      for (final id in ids) id: counts[guideFilterKey(colorId: id)] ?? 0,
    };
  }
  final plants = await loadGuideKeyPlants();
  return {
    for (final id in ids) id: guideKeyCount(plants, colorId: id),
  };
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
  if (!await _guideOnPhoneOnly()) {
    try {
      final snapshot = await guideServerGet(listsV3Reference.child(key))
          .timeout(_guideIndexWait);
      final ids = guideResultIds(snapshot.value);
      // An answer that is present and empty is the real list.
      if (ids.isEmpty) return [];
      final plants = await Future.wait(
        ids.map((id) => _guideResultPlant(id, lang)),
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
  final labels = await _phoneLabelsFor(lang);
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

/// Plants on a family or genus list. Same headers as the key's result list.
Future<List<GuideResultPlant>> loadGuideListedPlants(
  DatabaseReference path,
  String languageCode,
) async {
  final read = await guideReadOrPack(
    () async => (await path.once()).snapshot.value,
    () => _phoneListBody(path),
    label: 'guide list ${path.path}',
  );
  final ids = guideResultIds(read.value);
  if (ids.isEmpty) return const [];
  final lang = getLanguageCode(languageCode);
  final plants = await Future.wait(ids.map((id) {
    return _catalogPlant(id, lang, phoneOnly: read.fromPhone);
  }));
  return plants.whereType<GuideResultPlant>().toList();
}

/// Book cover for the signed-in account's favorites. Null when signed out
/// or when nothing is marked. Thumbs follow numeric plant id order.
Future<GuideListCover?> loadGuideFavoriteCover(String languageCode) async {
  final user = Auth.appUser;
  if (user == null) return null;
  final ids = guideFavoriteIds.value.toList()..sort(_compareFavoriteIds);
  if (ids.isEmpty) return null;
  final lang = getLanguageCode(languageCode);
  final phoneOnly = await _guideOnPhoneOnly();
  final thumbs = <String>[];
  for (final id in ids.take(4)) {
    final plant = await _catalogPlant(id, lang, phoneOnly: phoneOnly);
    final path = plant?.photoPath;
    if (path != null && path.isNotEmpty) thumbs.add(path);
  }
  return GuideListCover(
    title: '',
    photoPath: thumbs.isEmpty ? null : thumbs.first,
    thumbs: thumbs,
    path: usersReference.child(user.uid).child(firebaseAttributeFavorite),
    isNew: false,
    count: ids.length,
    isFavorite: true,
  );
}

int _compareFavoriteIds(String a, String b) {
  final left = int.tryParse(a);
  final right = int.tryParse(b);
  if (left != null && right != null) return left.compareTo(right);
  return a.compareTo(b);
}

Future<String?> loadGuideTaxonTitle(String latin, String languageCode) async {
  if (latin.isEmpty) return null;
  final lang = getLanguageCode(languageCode);
  try {
    final event =
        await translationsTaxonomyReference.child(lang).child(latin).once();
    return guideTaxonVernacular(event.snapshot.value, latin);
  } catch (error) {
    debugPrint('guide list title $latin: $error');
    return null;
  }
}

/// Header for one catalog id. [Query.get] so a plant added after
/// `plants_headers_v3` was cached on disk is not read back as missing.
Future<GuideResultPlant?> _guideResultPlant(String id, String language) async {
  try {
    final snapshot = await guideServerGet(headersV3Reference.child(id))
        .timeout(_guideIndexWait);
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
        await guideServerGet(listsReference.child(id)).timeout(_guideIndexWait);
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
    ).timeout(_guideIndexWait);
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
    ).timeout(_guideIndexWait);
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

/// In flower this month, and seen, for each genus. Flowering months are cached.
/// Seen is read again on every call.
Future<Map<String, GuideGenusNote>> loadGuideGenusNotes(
  List<GuideSearchTaxon> genera, {
  int? month,
}) async {
  if (genera.isEmpty) return {};
  final blooms = await _loadHeaderBlooms();
  final seen = await loadGuideSeenNames();
  final now = month ?? DateTime.now().month;
  return {
    for (final genus in genera)
      genus.latinName: countGuideGenusNote(
        plantIds: genus.plantIds,
        blooms: blooms,
        seen: seen,
        month: now,
      ),
  };
}

Future<Map<String, GuideHeaderBloom>> _bloomsFromKeyPlants() async {
  final plants = await _keyPlantsById();
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

Future<Map<String, GuideHeaderBloom>> _loadHeaderBlooms() {
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

Future<Set<String>> loadGuideSeenNames() async {
  final user = guideNotebookUser();
  if (user == null) return {};
  try {
    final ref = privateObservationsReference
        .child(user.uid)
        .child(firebaseObservationsByPlant);
    final value = await _guideChildValue(
      ref,
      phoneOnly: await _guideOnPhoneOnly(),
    );
    if (value is! Map) return {};
    return value.keys.map((key) => key.toString()).toSet();
  } catch (error) {
    debugPrint('guide seen names: $error');
    return {};
  }
}

Future<Map<String, int>> loadGuideRegionCounts({
  required String colorId,
  String? habitatId,
  required String petalId,
}) async {
  final ids = ['', ...guideAllRegionIds];
  if (!await _guideOnPhoneOnly()) {
    try {
      final entries = await Future.wait(ids.map((id) async {
        final key = guideFilterKey(
          colorId: colorId,
          habitatId: habitatId,
          petalId: petalId,
          regionId: id.isEmpty ? null : id,
        );
        final snapshot = await guideServerGet(countsV3Reference.child(key))
            .timeout(_guideIndexWait);
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

/// How long a key index may take before the copy already on the phone is used.
/// `.once()` on a node that was never downloaded does not finish in flight mode.
/// Dead wi-fi still reports an interface, so the same limit applies there.
const _guideIndexWait = Duration(seconds: 4);

/// True when the phone reports no network. A check that throws counts as
/// online, so a working connection still reads the indexes.
Future<bool> _guideOnPhoneOnly() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.every((item) => item == ConnectivityResult.none);
  } catch (error) {
    debugPrint('guide connectivity: $error');
    return false;
  }
}

/// A server read, or the pack already on the phone.
///
/// [fromPhone] is set when that pack was used. The pack is a stored list, a
/// language entry, or key-plant headers, not another get of the node that waited.
@visibleForTesting
Future<({T value, bool fromPhone})> guideReadOrPack<T>(
  Future<T> Function() online,
  Future<T> Function() pack, {
  bool? phoneOnly,
  Duration wait = _guideIndexWait,
  String label = 'guide read',
}) async {
  if (!(phoneOnly ?? await _guideOnPhoneOnly())) {
    try {
      return (value: await online().timeout(wait), fromPhone: false);
    } catch (error) {
      debugPrint('$label: $error');
    }
  }
  return (value: await pack(), fromPhone: true);
}

/// Local copy when [phoneOnly]. Otherwise one `.once()`, then the caller's pack.
Future<dynamic> _guideChildValue(
  DatabaseReference ref, {
  required bool phoneOnly,
}) async {
  if (phoneOnly) {
    final snapshot = await guideServerGet(ref).timeout(_guideIndexWait);
    return snapshot.value;
  }
  final event = await ref.once().timeout(_guideIndexWait);
  return event.snapshot.value;
}

/// `lists_custom/by language/{code}/{title}/list`.
///
/// The language node is one stored value. A get of the list child is a
/// different query and waits on the network while the phone is offline.
@visibleForTesting
({String code, String title})? guideCustomListAddress(String path) {
  var text = path;
  if (text.startsWith('/')) text = text.substring(1);
  final parts = text.split('/');
  if (parts.length != 5) return null;
  if (parts[0] != firebaseListsCustom) return null;
  if (parts[1] != 'by language') return null;
  if (parts[4] != firebaseAttributeList) return null;
  if (parts[2].isEmpty || parts[3].isEmpty) return null;
  return (code: parts[2], title: parts[3]);
}

bool _isApgListPath(String path) {
  var text = path;
  if (text.startsWith('/')) text = text.substring(1);
  return text.startsWith('$firebaseAPGIV/');
}

final Map<String, Map<dynamic, dynamic>> _listsByLanguage = {};

Future<Map<dynamic, dynamic>?> _customListEntry(
    String code, String title) async {
  var lists = _listsByLanguage[code];
  if (lists == null) {
    final value = await _guideChildValue(
      listsCustomReference.child('by language').child(code),
      phoneOnly: true,
    );
    if (value is! Map) return null;
    lists = value;
    _listsByLanguage[code] = lists;
  }
  final entry = lists[title];
  if (entry is! Map) return null;
  return entry;
}

/// The list body. A stored language entry or APG tree answers without a
/// child get. Anything else, such as favorites, is its own stored node.
Future<dynamic> _phoneListBody(DatabaseReference path) async {
  final address = guideCustomListAddress(path.path);
  if (address != null) {
    final entry = await _customListEntry(address.code, address.title);
    if (entry != null) return entry[firebaseAttributeList];
  }
  if (_isApgListPath(path.path)) {
    try {
      await ensureGuideApgLists();
    } catch (error) {
      debugPrint('guide apg lists: $error');
    }
    final node = guideApgListNode(path.path);
    if (node != null) return node;
  }
  return _guideChildValue(path, phoneOnly: true);
}

Map<String, GuideKeyPlant>? _keyById;
Future<Map<String, GuideKeyPlant>>? _keyByIdLoad;

Future<Map<String, GuideKeyPlant>> _keyPlantsById() {
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

Future<Map<String, String>> _phoneLabelsFor(String language) {
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
      .timeout(_guideIndexWait);
  return guideLabelsFromSnapshot(snapshot.value);
}

Future<GuideResultPlant?> _catalogPlant(
  String id,
  String language, {
  required bool phoneOnly,
}) async {
  if (!phoneOnly) {
    try {
      return await _guideResultPlant(id, language) ??
          await _guideHeaderPlant(id, language);
    } on TimeoutException {
      debugPrint('guide catalog $id: timed out');
    }
  }
  final plants = await _keyPlantsById();
  final plant = plants[id];
  if (plant == null) return null;
  final labels = await _phoneLabelsFor(language);
  final label = guideResultLabel(
    plant.name,
    stored: labels,
    cached: translationCache[plant.name],
  );
  return plant.toResult(label: label);
}

/// The v3 count index, or null when the phone should answer from headers.
Future<Map<String, int>?> _indexCounts(List<String> keys, String label) async {
  if (await _guideOnPhoneOnly()) return null;
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
        .timeout(_guideIndexWait);
    return MapEntry(key, _asInt(snapshot.value));
  }));
  return Map.fromEntries(entries);
}

Future<List<GuideKeyPlant>>? _keyPlants;

/// Headers fetched for the offline pack. Cached for this session.
Future<List<GuideKeyPlant>> loadGuideKeyPlants() {
  return _keyPlants ??= _readKeyPlants();
}

Future<List<GuideKeyPlant>> _readKeyPlants() async {
  try {
    final snapshot =
        await guideServerGet(headersV3Reference).timeout(_guideIndexWait);
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

Future<List<GuideListCover>> loadGuideLists(String languageCode) async {
  final chosen = await _languageLists(languageCode);
  final pending = <_PendingCover>[];

  chosen.lists.forEach((key, raw) {
    if (raw is! Map) return;
    final body = readGuideList(
      raw[firebaseAttributeList],
      genera: raw[firebaseAttributeGenera],
    );
    if (body.count == 0) return;
    pending.add(_PendingCover(
      coverId: body.coverId,
      coverGenus: body.coverGenus,
      thumbIds: body.thumbIds,
      cover: GuideListCover(
        title: key.toString(),
        photoPath: null,
        path: listsCustomReference
            .child('by language')
            .child(chosen.code)
            .child(key.toString())
            .child(firebaseAttributeList),
        isNew: false,
        count: body.count,
        year: body.year,
        yearFrom: body.yearFrom,
        hasSource: _listHasSource(raw),
        parameter: _listParameter(raw),
        labeled: body.labeled,
      ),
    ));
  });

  // A slow "new" query must not throw away the language lists already read.
  _Newest? newest;
  try {
    newest = await _newestAddition();
  } catch (error) {
    debugPrint('guide lists new: $error');
  }
  if (newest != null) {
    pending.add(_PendingCover(
      coverId: newest.coverId,
      thumbIds: newest.thumbIds,
      cover: GuideListCover(
        title: '',
        photoPath: null,
        path: listsCustomReference
            .child('new')
            .child(newest.dateKey)
            .child(firebaseAttributeList),
        isNew: true,
        count: newest.count,
        latest: newest.date,
      ),
    ));
  }

  final photoIds = <String>{
    for (final item in pending) ...item.thumbIds,
    for (final item in pending)
      if (item.coverId != null) item.coverId!,
  };
  final photos = await _headerPhotos(photoIds);
  final genusPhotos = await _genusCoverPhotos(pending, chosen.code);
  final covers = pending.map((item) {
    final cover = item.cover;
    final photo = item.coverId != null
        ? photos[item.coverId]
        : genusPhotos[item.coverGenus];
    final thumbs = [
      for (final id in item.thumbIds)
        if (photos[id] != null) photos[id]!,
    ];
    return GuideListCover(
      title: cover.title,
      photoPath: photo,
      thumbs: thumbs,
      path: cover.path,
      isNew: cover.isNew,
      count: cover.count,
      year: cover.year,
      yearFrom: cover.yearFrom,
      latest: cover.latest,
      hasSource: cover.hasSource,
      parameter: cover.parameter,
      labeled: cover.labeled,
    );
  }).toList();

  covers.sort(compareGuideLists);
  return covers;
}

class _PendingCover {
  final String? coverId;
  final String? coverGenus;
  final List<String> thumbIds;
  final GuideListCover cover;

  _PendingCover({
    required this.coverId,
    required this.thumbIds,
    required this.cover,
    this.coverGenus,
  });
}

/// One catalog species stands for a genus on a list card or a genus row.
///
/// The picture is that species’ photo or plate. A genus with no catalog
/// species, such as Yucca, has no picture.
const Map<String, String> _genusSampleIds = {
  'Crataegus': '145',
  'Iris': '757',
  'Lupinus': '643',
  'Magnolia': '664',
  'Malus': '339',
  'Paeonia': '810',
  'Rosa': '996',
  'Viola': '1090',
};

@visibleForTesting
String? guideGenusSampleId(String genus, List<String> plantIds) {
  final wanted = _genusSampleIds[genus];
  if (wanted != null && (plantIds.isEmpty || plantIds.contains(wanted))) {
    return wanted;
  }
  if (plantIds.isNotEmpty) return plantIds.first;
  return null;
}

/// Species photo for a genus cover. A genus the book does not list has none.
Future<Map<String, String>> _genusCoverPhotos(
  List<_PendingCover> pending,
  String languageCode,
) async {
  final wanted = {
    for (final item in pending)
      if (item.coverGenus != null) item.coverGenus!,
  };
  if (wanted.isEmpty) return const {};
  final idsByGenus = <String, List<String>>{};
  try {
    final book = await loadGuideBookTaxa(languageCode);
    for (final taxon in book.genera) {
      if (wanted.contains(taxon.latinName)) {
        idsByGenus[taxon.latinName] = taxon.plantIds;
      }
    }
  } catch (error) {
    debugPrint('guide genus cover: $error');
  }
  final photos = <String, String>{};
  final phoneOnly = await _guideOnPhoneOnly();
  await Future.wait(wanted.map((genus) async {
    try {
      final id = guideGenusSampleId(genus, idsByGenus[genus] ?? const []);
      if (id == null) return;
      final plant = await _catalogPlant(id, languageCode, phoneOnly: phoneOnly);
      final path = plant?.photoPath ?? plant?.platePath;
      if (path != null && path.isNotEmpty) photos[genus] = path;
    } catch (error) {
      debugPrint('guide genus cover $genus: $error');
    }
  }));
  return photos;
}

/// The signed-in account, or the anonymous guest while that is the only
/// account. A missing Firebase app yields null.
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
  final phoneOnly = await _guideOnPhoneOnly();

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
  final phoneOnly = await _guideOnPhoneOnly();
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
  final offline = phoneOnly ?? await _guideOnPhoneOnly();
  final labelFuture = _seenLabel(name, languageCode, phoneOnly: offline);
  final photoFuture = _seenPhoto(
    name,
    needsPhoto: needsPhoto,
    needsCover: needsCover,
    phoneOnly: offline,
  );
  final inBookFuture = _plantInBook(name, phoneOnly: offline);
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
  final photos = await _bookPhotoMap();
  if (photos == null) return const _SeenRead.unknown();
  return _SeenRead.known(photos[name]);
}

/// `plants_headers_v3` photo for [name], or null when the headers are not
/// on the phone. Cached for the session.
Future<String?> guideBookPhoto(String name) async {
  final photos = await _bookPhotoMap();
  return photos?[name];
}

Map<String, String?>? _bookPhotos;

Future<Map<String, String?>?> _bookPhotoMap() async {
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

Future<_SeenRead> _seenLabel(
  String name,
  String languageCode, {
  required bool phoneOnly,
}) async {
  final cached = translationCache[name];
  if (cached != null && cached.isNotEmpty) return _SeenRead.known(cached);
  try {
    final value = await _guideChildValue(
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
    final photos = await _bookPhotoMap();
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
Future<bool?> _plantInBook(String name, {bool phoneOnly = false}) async {
  if (_plantInBookCache[name] == true) return true;
  if (phoneOnly) {
    final photos = await _bookPhotoMap();
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

bool _listHasSource(Map raw) {
  final source = raw[firebaseAttributeSourceUrl];
  return source is String && source.trim().isNotEmpty;
}

String _listParameter(Map raw) {
  final value = raw['parameter'];
  if (value is! String) return '';
  return value.trim();
}

/// New in the book, then sourced lists, then lists with a year or another
/// parameter, then the title. A parameter sorts ahead of the title inside
/// its group, so two country lists follow the parameter.
@visibleForTesting
int guideListRank(GuideListCover cover) {
  if (cover.isFavorite) return -1;
  if (cover.isNew) return 0;
  if (cover.hasSource) return 1;
  if (cover.year != null || cover.parameter.isNotEmpty) return 2;
  return 3;
}

String _guideListSortKey(GuideListCover cover) {
  if (cover.parameter.isNotEmpty) return cover.parameter.toLowerCase();
  return cover.title.toLowerCase();
}

@visibleForTesting
int compareGuideLists(GuideListCover a, GuideListCover b) {
  final byRank = guideListRank(a).compareTo(guideListRank(b));
  if (byRank != 0) return byRank;
  final byKey = _guideListSortKey(a).compareTo(_guideListSortKey(b));
  if (byKey != 0) return byKey;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

@visibleForTesting
class GuideListBody {
  final int count;
  final String? coverId;
  final int? year;
  final int? yearFrom;
  final List<String> thumbIds;
  final bool labeled;

  /// Set when the alphabetically first state, or the newest year, is a genus.
  final String? coverGenus;

  GuideListBody(
    this.count,
    this.coverId,
    this.year, {
    this.yearFrom,
    this.thumbIds = const [],
    this.labeled = false,
    this.coverGenus,
  });
}

/// One genus designation. [state] and [year] are both null for membership.
class GuideGenusMark {
  final String genus;
  final String? state;
  final int? year;

  const GuideGenusMark(this.genus, {this.state, this.year});
}

/// A genus name. Numeric keys stay out so they can never be plant ids.
bool guideGenusKey(String key) {
  final text = key.trim();
  if (text.isEmpty) return false;
  if (int.tryParse(text) != null) return false;
  return RegExp(r'[A-Za-z]').hasMatch(text);
}

/// Genus designations beside `list`. Same values as a plant: one state, a
/// map of states, a year, or membership.
@visibleForTesting
List<GuideGenusMark> readGuideGenusMarks(dynamic genera) {
  if (genera is! Map) return const [];
  final pending = <MapEntry<String, dynamic>>[];
  genera.forEach((key, value) {
    if (value == null || value == false) return;
    if (value is String && value.trim().isEmpty) return;
    if (value is Map && value.isEmpty) return;
    final name = key.toString().trim();
    if (!guideGenusKey(name)) return;
    pending.add(MapEntry(name, value));
  });
  pending.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  final marks = <GuideGenusMark>[];
  for (final entry in pending) {
    final states = customListStates(entry.value);
    if (states.isNotEmpty) {
      for (final state in states) {
        marks.add(GuideGenusMark(entry.key, state: state));
      }
      continue;
    }
    final year = customListYear(entry.value);
    if (year != null) {
      marks.add(GuideGenusMark(entry.key, year: year));
      continue;
    }
    marks.add(GuideGenusMark(entry.key));
  }
  return marks;
}

@visibleForTesting
GuideListBody readGuideList(dynamic list, {dynamic genera}) {
  final entries = <MapEntry<String, dynamic>>[];
  if (list is List) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] != null) entries.add(MapEntry(i.toString(), list[i]));
    }
  } else if (list is Map) {
    list.forEach((key, value) {
      if (value != null) entries.add(MapEntry(key.toString(), value));
    });
  }
  entries.sort((a, b) {
    final na = int.tryParse(a.key);
    final nb = int.tryParse(b.key);
    if (na != null && nb != null) return na.compareTo(nb);
    return a.key.compareTo(b.key);
  });

  final order = <String, int>{
    for (var i = 0; i < entries.length; i++) entries[i].key: i,
  };
  final marks = <MapEntry<String, String>>[];
  for (final entry in entries) {
    for (final state in customListStates(entry.value)) {
      marks.add(MapEntry(entry.key, state));
    }
  }
  final genusMarks = readGuideGenusMarks(genera);
  final genusStates = [
    for (final mark in genusMarks)
      if (mark.state != null) mark,
  ];
  // A membership list stays a grid. Genus states must not hide those plants.
  final stateList =
      marks.isNotEmpty || (genusStates.isNotEmpty && entries.isEmpty);
  if (stateList) {
    final ranked = <_RankedState>[];
    for (final mark in marks) {
      ranked.add(_RankedState(
        id: mark.key,
        state: mark.value,
        order: order[mark.key] ?? 0,
      ));
    }
    for (var i = 0; i < genusStates.length; i++) {
      final mark = genusStates[i];
      ranked.add(_RankedState(
        genus: mark.genus,
        state: mark.state!,
        order: marks.length + i,
      ));
    }
    ranked.sort((a, b) {
      final byState = a.state.toLowerCase().compareTo(b.state.toLowerCase());
      if (byState != 0) return byState;
      final aGenus = a.genus != null;
      final bGenus = b.genus != null;
      if (aGenus != bGenus) return aGenus ? 1 : -1;
      return a.order.compareTo(b.order);
    });
    final seen = <String>{};
    final thumbs = <String>[];
    for (final mark in ranked) {
      final id = mark.id;
      if (id == null || !seen.add(id)) continue;
      thumbs.add(id);
      if (thumbs.length == 4) break;
    }
    final first = ranked.first;
    return GuideListBody(
      marks.length + genusMarks.length,
      first.id,
      null,
      thumbIds: thumbs,
      labeled: true,
      coverGenus: first.genus,
    );
  }

  String? coverId;
  String? coverGenus;
  int? latestYear;
  int? oldestYear;
  final dated = <MapEntry<String, int>>[];
  for (final entry in entries) {
    coverId ??= entry.key;
    final year = customListYear(entry.value);
    if (year == null) continue;
    dated.add(MapEntry(entry.key, year));
    if (latestYear == null || year > latestYear) {
      latestYear = year;
      coverId = entry.key;
      coverGenus = null;
    }
    if (oldestYear == null || year < oldestYear) oldestYear = year;
  }
  for (final mark in genusMarks) {
    final year = mark.year;
    if (year == null) continue;
    if (latestYear == null || year > latestYear) {
      latestYear = year;
      coverId = null;
      coverGenus = mark.genus;
    }
    if (oldestYear == null || year < oldestYear) oldestYear = year;
  }
  dated.sort((a, b) {
    final byYear = b.value.compareTo(a.value);
    if (byYear != 0) return byYear;
    return order[a.key]!.compareTo(order[b.key]!);
  });
  final source = dated.isEmpty
      ? entries.map((entry) => entry.key)
      : dated.map((entry) => entry.key);
  return GuideListBody(
    entries.length + genusMarks.length,
    coverId,
    latestYear,
    yearFrom: oldestYear,
    thumbIds: source.take(4).toList(),
    coverGenus: coverGenus,
  );
}

class _RankedState {
  final String? id;
  final String? genus;
  final String state;
  final int order;

  _RankedState({
    required this.state,
    required this.order,
    this.id,
    this.genus,
  });
}

class _Newest {
  final String dateKey;
  final DateTime? date;
  final int count;
  final String? coverId;
  final List<String> thumbIds;

  _Newest(
    this.dateKey,
    this.date,
    this.count,
    this.coverId,
    this.thumbIds,
  );
}

/// One dated drop under `lists_custom/new`, before the plants are loaded.
class GuideNewDrop {
  final String dateKey;
  final DateTime? date;
  final List<String> ids;

  const GuideNewDrop(this.dateKey, this.date, this.ids);
}

/// Plants added on one day, newest day first on the New in the book page.
class GuideNewDay {
  final String dateKey;
  final DateTime? date;
  final List<GuideResultPlant> plants;

  const GuideNewDay({
    required this.dateKey,
    required this.date,
    required this.plants,
  });
}

/// A year-list row. One plant keeps the later year when the list names it once.
///
/// A genus row leaves [plant] null. [genusPath] is empty when the book walk
/// has no species in that genus, and the row does not open.
class GuideYearEntry {
  final int? year;
  final GuideResultPlant? plant;

  /// Set when the list value is a state name. The card shows this instead of [year].
  final String? mark;
  final String? genus;
  final String? genusFamily;
  final String? genusPath;

  /// Photo and plate of the one species that stands for this genus.
  final String? genusPhotoPath;
  final String? genusPlatePath;

  /// Vernacular of [genus] in the list language. Null when none is stored,
  /// or when it repeats the Latin name in the same case.
  final String? genusVernacular;

  const GuideYearEntry({
    this.year,
    this.plant,
    this.mark,
    this.genus,
    this.genusFamily,
    this.genusPath,
    this.genusPhotoPath,
    this.genusPlatePath,
    this.genusVernacular,
  });
}

class GuideYearList {
  final List<GuideYearEntry> entries;
  final String? sourceUrl;

  const GuideYearList({required this.entries, required this.sourceUrl});
}

class GuideYearId {
  final String id;
  final int year;

  const GuideYearId(this.id, this.year);
}

class GuideStateId {
  final String id;
  final String state;

  const GuideStateId(this.id, this.state);
}

@visibleForTesting
List<GuideNewDrop> readGuideNewDrops(dynamic value) {
  if (value is! Map) return const [];
  final drops = <GuideNewDrop>[];
  value.forEach((key, raw) {
    if (raw is! Map) return;
    final dateKey = key.toString();
    DateTime? date;
    try {
      date = DateTime.parse(dateKey);
    } catch (_) {
      return;
    }
    final ids = guideResultIds(raw[firebaseAttributeList]);
    if (ids.isEmpty) return;
    drops.add(GuideNewDrop(dateKey, date, ids));
  });
  drops.sort((a, b) => b.dateKey.compareTo(a.dateKey));
  return drops;
}

@visibleForTesting
List<GuideNewDrop> selectGuideNewDrops(List<GuideNewDrop> newestFirst) {
  final chosen = <GuideNewDrop>[];
  var count = 0;
  for (final drop in newestFirst) {
    final next = count + drop.ids.length;
    if (count >= guideNewPlantMin && next > guideNewPlantMax) break;
    if (next <= guideNewPlantMax) {
      chosen.add(drop);
      count = next;
      continue;
    }
    final room = guideNewPlantMax - count;
    final ids = drop.ids.length <= room
        ? drop.ids
        : drop.ids.sublist(drop.ids.length - room);
    chosen.add(GuideNewDrop(drop.dateKey, drop.date, ids));
    break;
  }
  return chosen;
}

@visibleForTesting
List<GuideYearId> readGuideYearIds(dynamic list) {
  final entries = <MapEntry<String, dynamic>>[];
  if (list is List) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] != null) entries.add(MapEntry(i.toString(), list[i]));
    }
  } else if (list is Map) {
    list.forEach((key, value) {
      if (value != null) entries.add(MapEntry(key.toString(), value));
    });
  }
  entries.sort((a, b) {
    final na = int.tryParse(a.key);
    final nb = int.tryParse(b.key);
    if (na != null && nb != null) return na.compareTo(nb);
    return a.key.compareTo(b.key);
  });
  final dated = <GuideYearId>[];
  for (final entry in entries) {
    final year = customListYear(entry.value);
    if (year == null) continue;
    dated.add(GuideYearId(entry.key, year));
  }
  final order = {for (var i = 0; i < dated.length; i++) dated[i].id: i};
  dated.sort((a, b) {
    final byYear = b.year.compareTo(a.year);
    if (byYear != 0) return byYear;
    return order[a.id]!.compareTo(order[b.id]!);
  });
  return dated;
}

/// One timeline row before the plant or the genus plate is loaded.
class GuideTimelineRow {
  final String? id;
  final String? genus;
  final String? state;
  final int? year;

  const GuideTimelineRow({this.id, this.genus, this.state, this.year});
}

class _TimelineRank {
  final GuideTimelineRow row;
  final int index;
  final bool genus;

  const _TimelineRank(this.row, this.index, {this.genus = false});
}

/// State rows, then year rows, then membership genera. A year list keeps
/// its species order and folds genus years into it. Membership species are
/// not rows here: those stay on the result grid.
@visibleForTesting
List<GuideTimelineRow> readGuideTimeline(dynamic list, [dynamic genera]) {
  final speciesYears = readGuideYearIds(list);
  final speciesStates =
      speciesYears.isEmpty ? readGuideStateIds(list) : const <GuideStateId>[];
  final genusMarks = readGuideGenusMarks(genera);
  final stateMode = speciesStates.isNotEmpty ||
      (speciesYears.isEmpty && genusMarks.any((mark) => mark.state != null));
  if (stateMode) {
    final ranked = <_TimelineRank>[];
    for (var i = 0; i < speciesStates.length; i++) {
      final row = speciesStates[i];
      ranked.add(_TimelineRank(
        GuideTimelineRow(id: row.id, state: row.state),
        i,
      ));
    }
    var genusIndex = speciesStates.length;
    for (final mark in genusMarks) {
      final state = mark.state;
      if (state == null) continue;
      ranked.add(_TimelineRank(
        GuideTimelineRow(genus: mark.genus, state: state),
        genusIndex++,
      ));
    }
    ranked.sort((a, b) {
      final byState =
          a.row.state!.toLowerCase().compareTo(b.row.state!.toLowerCase());
      if (byState != 0) return byState;
      return a.index.compareTo(b.index);
    });
    return [
      for (final rank in ranked) rank.row,
      ..._genusTimelineTail(genusMarks, includeYears: true),
    ];
  }
  final ranked = <_TimelineRank>[];
  for (var i = 0; i < speciesYears.length; i++) {
    final row = speciesYears[i];
    ranked.add(_TimelineRank(
      GuideTimelineRow(id: row.id, year: row.year),
      i,
    ));
  }
  var genusIndex = speciesYears.length;
  for (final mark in genusMarks) {
    final year = mark.year;
    if (year == null) continue;
    ranked.add(_TimelineRank(
      GuideTimelineRow(genus: mark.genus, year: year),
      genusIndex++,
      genus: true,
    ));
  }
  ranked.sort((a, b) {
    final byYear = b.row.year!.compareTo(a.row.year!);
    if (byYear != 0) return byYear;
    if (a.genus != b.genus) return a.genus ? 1 : -1;
    return a.index.compareTo(b.index);
  });
  final states = [
    for (final mark in genusMarks)
      if (mark.state != null) mark,
  ]..sort((a, b) {
      final byState = a.state!.toLowerCase().compareTo(b.state!.toLowerCase());
      if (byState != 0) return byState;
      return a.genus.toLowerCase().compareTo(b.genus.toLowerCase());
    });
  return [
    for (final rank in ranked) rank.row,
    for (final mark in states)
      GuideTimelineRow(genus: mark.genus, state: mark.state),
    ..._genusTimelineTail(genusMarks, includeYears: false),
  ];
}

List<GuideTimelineRow> _genusTimelineTail(
  List<GuideGenusMark> marks, {
  required bool includeYears,
}) {
  final tail = <GuideTimelineRow>[];
  if (includeYears) {
    final dated = [
      for (final mark in marks)
        if (mark.year != null) mark,
    ]..sort((a, b) {
        final byYear = b.year!.compareTo(a.year!);
        if (byYear != 0) return byYear;
        return a.genus.toLowerCase().compareTo(b.genus.toLowerCase());
      });
    for (final mark in dated) {
      tail.add(GuideTimelineRow(genus: mark.genus, year: mark.year));
    }
  }
  final plain = [
    for (final mark in marks)
      if (mark.state == null && mark.year == null) mark,
  ]..sort((a, b) => a.genus.toLowerCase().compareTo(b.genus.toLowerCase()));
  for (final mark in plain) {
    tail.add(GuideTimelineRow(genus: mark.genus));
  }
  return tail;
}

/// State names on a list, alphabetical. One species can name more than one state.
@visibleForTesting
List<GuideStateId> readGuideStateIds(dynamic list) {
  final entries = <MapEntry<String, dynamic>>[];
  if (list is List) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] != null) entries.add(MapEntry(i.toString(), list[i]));
    }
  } else if (list is Map) {
    list.forEach((key, value) {
      if (value != null) entries.add(MapEntry(key.toString(), value));
    });
  }
  entries.sort((a, b) {
    final na = int.tryParse(a.key);
    final nb = int.tryParse(b.key);
    if (na != null && nb != null) return na.compareTo(nb);
    return a.key.compareTo(b.key);
  });
  final order = {for (var i = 0; i < entries.length; i++) entries[i].key: i};
  final marked = <GuideStateId>[];
  for (final entry in entries) {
    for (final state in customListStates(entry.value)) {
      marked.add(GuideStateId(entry.key, state));
    }
  }
  marked.sort((a, b) {
    final byState = a.state.toLowerCase().compareTo(b.state.toLowerCase());
    if (byState != 0) return byState;
    return order[a.id]!.compareTo(order[b.id]!);
  });
  return marked;
}

/// Host shown next to a year list, without the scheme.
String guideSourceHost(String url) {
  final uri = Uri.tryParse(url.trim());
  var host = (uri == null || uri.host.isEmpty) ? url.trim() : uri.host;
  if (host.startsWith('www.')) host = host.substring(4);
  return host;
}

Future<_Newest?> _newestAddition() async {
  final drops = await _selectedNewDrops();
  if (drops.isEmpty) return null;
  final ids = [for (final drop in drops) ...drop.ids];
  final newest = drops.first;
  return _Newest(
    newest.dateKey,
    newest.date,
    ids.length,
    ids.isEmpty ? null : ids.first,
    ids.take(4).toList(),
  );
}

/// Newest days of `lists_custom/new` inside the 15 to 25 plant window.
///
/// No network reads the on-disk copy. The server read stops after
/// [_guideIndexWait] and throws when it does not finish. There is no other copy.
Future<List<GuideNewDrop>> _selectedNewDrops() async {
  final snapshot = await listsCustomReference
      .child('new')
      .orderByKey()
      .limitToLast(guideNewPlantMax)
      .get()
      .timeout(_guideIndexWait);
  return selectGuideNewDrops(readGuideNewDrops(snapshot.value));
}

Future<List<GuideNewDay>> loadGuideNewDays(String languageCode) async {
  final drops = await _selectedNewDrops();
  if (drops.isEmpty) return const [];
  final lang = getLanguageCode(languageCode);
  final phoneOnly = await _guideOnPhoneOnly();
  final days = <GuideNewDay>[];
  for (final drop in drops) {
    final plants = await Future.wait(drop.ids.map((id) async {
      return _catalogPlant(id, lang, phoneOnly: phoneOnly);
    }));
    days.add(GuideNewDay(
      dateKey: drop.dateKey,
      date: drop.date,
      plants: plants.whereType<GuideResultPlant>().toList(),
    ));
  }
  return days;
}

typedef _YearBody = ({dynamic list, String? sourceUrl, dynamic genera});

/// Genera uses get() so a node published after the last open is not hidden
/// by an old disk copy. The source stays on once(). No network uses the disk copy.
Future<dynamic> _yearChild(
  DatabaseReference ref, {
  required bool phone,
  required bool genera,
}) async {
  if (phone) return _guideChildValue(ref, phoneOnly: true);
  if (genera) {
    return (await guideServerGet(ref).timeout(_guideIndexWait)).value;
  }
  return (await ref.once().timeout(_guideIndexWait)).snapshot.value;
}

Future<_YearBody> _yearSides(
  dynamic list,
  DatabaseReference path, {
  required bool phone,
}) async {
  String? sourceUrl;
  dynamic genera;
  final parent = path.parent;
  if (parent != null) {
    try {
      final value = await _yearChild(
        parent.child(firebaseAttributeSourceUrl),
        phone: phone,
        genera: false,
      );
      if (value is String && value.isNotEmpty) sourceUrl = value;
    } catch (error) {
      debugPrint('guide year source: $error');
    }
    try {
      genera = await _yearChild(
        parent.child(firebaseAttributeGenera),
        phone: phone,
        genera: true,
      );
    } catch (error) {
      debugPrint('guide genera: $error');
    }
  }
  return (list: list, sourceUrl: sourceUrl, genera: genera);
}

/// Stored language entry, or the on-disk children when the phone has no network.
Future<_YearBody> _yearOnPhone(DatabaseReference path) async {
  final address = guideCustomListAddress(path.path);
  final onPhone = await _guideOnPhoneOnly();
  if (address != null &&
      (_listsByLanguage.containsKey(address.code) || onPhone)) {
    final stored = await _customListEntry(address.code, address.title);
    if (stored != null) {
      final source = stored[firebaseAttributeSourceUrl];
      return (
        list: stored[firebaseAttributeList],
        sourceUrl: source is String && source.isNotEmpty ? source : null,
        genera: stored[firebaseAttributeGenera],
      );
    }
  }
  if (!onPhone) throw StateError('no pack');
  return _yearSides(
    await _guideChildValue(path, phoneOnly: true),
    path,
    phone: true,
  );
}

Future<GuideYearList> loadGuideYearList(
  DatabaseReference path,
  String languageCode,
) async {
  final read = await guideReadOrPack<Object?>(
    () async => (await path.once()).snapshot.value,
    () => _yearOnPhone(path),
    label: 'guide year list',
  );
  final body = read.fromPhone
      ? read.value as _YearBody
      : await _yearSides(read.value, path, phone: false);
  final rows = readGuideTimeline(body.list, body.genera);
  if (rows.isEmpty) {
    return GuideYearList(entries: const [], sourceUrl: body.sourceUrl);
  }
  final lang = getLanguageCode(languageCode);
  final generaByName = <String, GuideSearchTaxon>{};
  if (rows.any((row) => row.genus != null)) {
    try {
      final book = await loadGuideBookTaxa(lang);
      for (final taxon in book.genera) {
        generaByName[taxon.latinName] = taxon;
      }
    } catch (error) {
      debugPrint('guide genus rows: $error');
    }
  }
  final sampleLoads = <String, Future<GuideResultPlant?>>{};
  final entries = await Future.wait(rows.map((row) async {
    final genus = row.genus;
    if (genus != null) {
      final taxon = generaByName[genus];
      final sampleId = guideGenusSampleId(genus, taxon?.plantIds ?? const []);
      GuideResultPlant? sample;
      if (sampleId != null) {
        sample = await sampleLoads.putIfAbsent(sampleId, () async {
          return _catalogPlant(sampleId, lang, phoneOnly: read.fromPhone);
        });
      }
      return GuideYearEntry(
        year: row.year,
        mark: row.state,
        genus: genus,
        genusFamily: taxon?.illustrationFamily ?? '',
        genusPath: taxon?.listPath ?? '',
        genusPhotoPath: sample?.photoPath,
        genusPlatePath: sample?.platePath,
        genusVernacular: guideTaxonVernacular(taxon?.vernaculars, genus),
      );
    }
    final id = row.id;
    if (id == null) return null;
    final plant = await _catalogPlant(id, lang, phoneOnly: read.fromPhone);
    if (plant == null) return null;
    return GuideYearEntry(
      year: row.year ?? 0,
      mark: row.state,
      plant: plant,
    );
  }));
  return GuideYearList(
    entries: entries.whereType<GuideYearEntry>().toList(),
    sourceUrl: body.sourceUrl,
  );
}

class _LanguageLists {
  final String code;
  final Map<dynamic, dynamic> lists;

  _LanguageLists(this.code, this.lists);
}

/// Language node already in memory, or on disk when the phone has no network.
Future<dynamic> _languageListPack(String code, DatabaseReference ref) async {
  final stored = _listsByLanguage[code];
  if (stored != null) return stored;
  if (await _guideOnPhoneOnly()) return _guideChildValue(ref, phoneOnly: true);
  throw StateError('no pack');
}

/// Lists for this language only. A missing node is an empty set.
/// English lists are not a substitute. `get()` reads the server, so a genera
/// child published after the last open is not hidden by an old disk copy.
Future<_LanguageLists> _languageLists(String languageCode) async {
  final code = getLanguageCode(languageCode);
  final ref = listsCustomReference.child('by language').child(code);
  final read = await guideReadOrPack(
    () async => (await guideServerGet(ref)).value,
    () => _languageListPack(code, ref),
    label: 'guide language lists',
  );
  final value = read.value;
  if (value is Map) {
    _listsByLanguage[code] = value;
    return _LanguageLists(code, value);
  }
  return _LanguageLists(code, {});
}

Future<Map<String, String>> _packHeaderPhotos(Set<String> ids) async {
  try {
    final plants = await _keyPlantsById();
    final photos = <String, String>{};
    for (final id in ids) {
      final path = plants[id]?.photoPath;
      if (path != null && path.isNotEmpty) photos[id] = path;
    }
    return photos;
  } catch (error) {
    debugPrint('guide photos: $error');
    return const {};
  }
}

Future<Map<String, String>> _headerPhotos(Set<String> ids) async {
  if (await _guideOnPhoneOnly()) return _packHeaderPhotos(ids);
  final photos = <String, String>{};
  await Future.wait(ids.map((id) async {
    try {
      final snapshot = await guideServerGet(
        listsReference.child(id).child(firebaseAttributeUrl),
      ).timeout(_guideIndexWait);
      final url = snapshot.value;
      if (url is String && url.isNotEmpty) {
        photos[id] = storagePhotos + url;
      }
    } catch (error) {
      debugPrint('guide photo $id: $error');
    }
  }));
  if (photos.length >= ids.length) return photos;
  final packed = await _packHeaderPhotos(ids);
  packed.forEach((id, path) => photos.putIfAbsent(id, () => path));
  return photos;
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
        final value = await _guideChildValue(
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
      final value = await _guideChildValue(
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

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

Future<GuideSpecies?> loadGuideSpecies(String name, String languageCode) async {
  final lang = getLanguageCode(languageCode);
  final onPhone = await _guideOnPhoneOnly();
  // Started with the plant read. A missing translation must not hold the page
  // open past its own timeout. A private find that is not on the phone must
  // not hold it either: the disk copy answers at once, and a server wait does not.
  final translation = _guideTranslation(lang, name);
  final seen = onPhone
      ? _guideSpeciesSeen(name).timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => null,
        )
      : _guideSpeciesSeen(name);
  final DataSnapshot snapshot;
  try {
    snapshot = await guideServerGet(plantsReference.child(name))
        .timeout(_guideIndexWait);
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
  await root
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .child(observation.id)
      .set(json);
  await root
      .child(firebaseObservationsByPlant)
      .child(draft.plant)
      .child(firebaseAttributeList)
      .child(observation.id)
      .set(json);
  unawaited(syncGuidePrivatePhotos(onlyId: observation.id));
}

Future<PlantTranslation> _guideTranslation(String lang, String name) async {
  try {
    final snapshot = await guideServerGet(
      translationsReference.child(lang).child(name),
    ).timeout(_guideIndexWait);
    final raw = snapshot.value;
    final local = raw is Map
        ? PlantTranslation.fromJson(Map<dynamic, dynamic>.from(raw))
        : PlantTranslation();
    if (lang == languageEnglish || local.isTranslated()) return local;
    try {
      final english = await guideServerGet(
        translationsReference.child(languageEnglish).child(name),
      ).timeout(_guideIndexWait);
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
  } catch (error) {
    debugPrint('guide species translation $name: $error');
    return PlantTranslation();
  }
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
      ).timeout(_guideIndexWait);
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
    ).timeout(_guideIndexWait);
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
    ).timeout(_guideIndexWait);
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
