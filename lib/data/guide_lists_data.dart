import 'dart:async';

import 'package:abherbs_flutter/data/guide_catalog.dart';
import 'package:abherbs_flutter/data/guide_favorites.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/data/guide_rtdb.dart';
import 'package:abherbs_flutter/data/guide_seen_data.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/search/guide_search.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

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
    return guideCatalogPlant(id, lang, phoneOnly: read.fromPhone);
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
  final phoneOnly = await guideOnPhoneOnly();
  final thumbs = <String>[];
  for (final id in ids.take(4)) {
    final plant = await guideCatalogPlant(id, lang, phoneOnly: phoneOnly);
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

/// In flower this month, and seen, for each genus. Flowering months are cached.
/// Seen is read again on every call.
Future<Map<String, GuideGenusNote>> loadGuideGenusNotes(
  List<GuideSearchTaxon> genera, {
  int? month,
}) async {
  if (genera.isEmpty) return {};
  final blooms = await guideLoadHeaderBlooms();
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
    final value = await guideChildValue(
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
  return guideChildValue(path, phoneOnly: true);
}

/// Language lists plus whether the new-plants read threw.
///
/// [freshFailed] is set only when that query throws. An empty
/// `lists_custom/new` is a finished read and leaves the flag false.
class GuideListsRead {
  final List<GuideListCover> covers;
  final bool freshFailed;

  const GuideListsRead(this.covers, {this.freshFailed = false});
}

/// Puts [fresh] into [lists] when this read is the one that found it.
///
/// A list that already has New in the book is left as it is. A null cover
/// is an empty `lists_custom/new`.
List<GuideListCover> guideListsWithFresh(
  List<GuideListCover> lists,
  GuideListCover? fresh,
) {
  if (fresh == null || !fresh.isNew) return lists;
  if (lists.any((cover) => cover.isNew)) return lists;
  return [...lists, fresh]..sort(compareGuideLists);
}

Future<GuideListsRead> loadGuideLists(String languageCode) async {
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
  var freshFailed = false;
  try {
    final newest = await _newestAddition();
    if (newest != null) pending.add(_pendingFresh(newest));
  } catch (error) {
    freshFailed = true;
    debugPrint('guide lists new: $error');
  }

  final covers = await _coversFromPending(pending, chosen.code);
  return GuideListsRead(covers, freshFailed: freshFailed);
}

/// New in the book on its own. Throws when the read does not finish.
/// Null when `lists_custom/new` is empty.
Future<GuideListCover?> loadGuideFreshCover() async {
  final newest = await _newestAddition();
  if (newest == null) return null;
  final covers = await _coversFromPending([_pendingFresh(newest)], '');
  return covers.isEmpty ? null : covers.first;
}

_PendingCover _pendingFresh(_Newest newest) {
  return _PendingCover(
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
  );
}

Future<List<GuideListCover>> _coversFromPending(
  List<_PendingCover> pending,
  String languageCode,
) async {
  final photoIds = <String>{
    for (final item in pending) ...item.thumbIds,
    for (final item in pending)
      if (item.coverId != null) item.coverId!,
  };
  final photos = await _headerPhotos(photoIds);
  final genusPhotos = await _genusCoverPhotos(pending, languageCode);
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
  final phoneOnly = await guideOnPhoneOnly();
  await Future.wait(wanted.map((genus) async {
    try {
      final id = guideGenusSampleId(genus, idsByGenus[genus] ?? const []);
      if (id == null) return;
      final plant = await guideCatalogPlant(id, languageCode, phoneOnly: phoneOnly);
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
/// [guideIndexWait] and throws when it does not finish. There is no other copy.
Future<List<GuideNewDrop>> _selectedNewDrops() async {
  final snapshot = await listsCustomReference
      .child('new')
      .orderByKey()
      .limitToLast(guideNewPlantMax)
      .get()
      .timeout(guideIndexWait);
  return selectGuideNewDrops(readGuideNewDrops(snapshot.value));
}

Future<List<GuideNewDay>> loadGuideNewDays(String languageCode) async {
  final drops = await _selectedNewDrops();
  if (drops.isEmpty) return const [];
  final lang = getLanguageCode(languageCode);
  final phoneOnly = await guideOnPhoneOnly();
  final days = <GuideNewDay>[];
  for (final drop in drops) {
    final plants = await Future.wait(drop.ids.map((id) async {
      return guideCatalogPlant(id, lang, phoneOnly: phoneOnly);
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
  if (phone) return guideChildValue(ref, phoneOnly: true);
  if (genera) {
    return (await guideServerGet(ref).timeout(guideIndexWait)).value;
  }
  return (await ref.once().timeout(guideIndexWait)).snapshot.value;
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
  final onPhone = await guideOnPhoneOnly();
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
    await guideChildValue(path, phoneOnly: true),
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
          return guideCatalogPlant(sampleId, lang, phoneOnly: read.fromPhone);
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
    final plant = await guideCatalogPlant(id, lang, phoneOnly: read.fromPhone);
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
  if (await guideOnPhoneOnly()) return guideChildValue(ref, phoneOnly: true);
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
    final plants = await guideKeyPlantsById();
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
  if (await guideOnPhoneOnly()) return _packHeaderPhotos(ids);
  final photos = <String, String>{};
  await Future.wait(ids.map((id) async {
    try {
      final snapshot = await guideServerGet(
        listsReference.child(id).child(firebaseAttributeUrl),
      ).timeout(guideIndexWait);
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
