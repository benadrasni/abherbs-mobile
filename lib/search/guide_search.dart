import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diacritic/diacritic.dart';
import 'package:flutter/foundation.dart';

const int guideSearchPlantLimit = 8;
const int guideSearchTaxonLimit = 4;

/// One indexed name pointing at a catalog id.
class GuideSearchName {
  final String folded;
  final int id;
  final bool label;

  const GuideSearchName(this.folded, this.id, this.label);
}

class GuideSearchTaxon {
  final String latinName;
  final List<String> vernaculars;
  final int count;
  final String listPath;
  final String illustrationFamily;

  /// Catalog ids on a genus list. Empty for families.
  final List<String> plantIds;

  const GuideSearchTaxon({
    required this.latinName,
    required this.vernaculars,
    required this.count,
    required this.listPath,
    required this.illustrationFamily,
    this.plantIds = const [],
  });
}

class GuideSearchPlant {
  final int id;
  final String latinKey;
  final String? labelKey;

  const GuideSearchPlant({
    required this.id,
    required this.latinKey,
    required this.labelKey,
  });
}

class GuideSearchIndex {
  final List<GuideSearchName> vernaculars;
  final List<GuideSearchName> latins;
  final Map<int, String> labelKeys;
  final Map<int, String> latinKeys;
  final List<GuideSearchTaxon> families;
  final List<GuideSearchTaxon> genera;

  const GuideSearchIndex({
    required this.vernaculars,
    required this.latins,
    required this.labelKeys,
    required this.latinKeys,
    required this.families,
    required this.genera,
  });

  static GuideSearchIndex parse({
    required dynamic vernacular,
    required dynamic latin,
    required dynamic apg,
    required dynamic taxonomyNames,
  }) {
    final vernaculars = <GuideSearchName>[];
    final latins = <GuideSearchName>[];
    final labelKeys = <int, String>{};
    final latinKeys = <int, String>{};
    _readNames(vernacular, vernaculars, labelKeys);
    _readNames(latin, latins, latinKeys);
    final families = <GuideSearchTaxon>[];
    final genera = <GuideSearchTaxon>[];
    _readTaxa(apg, taxonomyNames, families, genera);
    return GuideSearchIndex(
      vernaculars: vernaculars,
      latins: latins,
      labelKeys: labelKeys,
      latinKeys: latinKeys,
      families: families,
      genera: genera,
    );
  }
}

class GuideSearchResults {
  final List<GuideSearchPlant> plants;
  final List<GuideSearchTaxon> genera;
  final List<GuideSearchTaxon> families;

  const GuideSearchResults({
    required this.plants,
    required this.genera,
    required this.families,
  });

  bool get isEmpty => plants.isEmpty && genera.isEmpty && families.isEmpty;
}

class GuidePlantCard {
  final String? latinName;
  final String? label;
  final String? photoPath;

  const GuidePlantCard({this.latinName, this.label, this.photoPath});
}

String foldSearch(String value) {
  return removeDiacritics(value).toLowerCase().trim();
}

/// Accepted Latin names are stored lowercased in `search_v3/la`.
String displayLatin(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;
  final space = trimmed.indexOf(' ');
  final head = space <= 0 ? trimmed : trimmed.substring(0, space);
  if (head.isEmpty) return trimmed;
  final capped = head[0].toUpperCase() + head.substring(1);
  return space <= 0 ? capped : capped + trimmed.substring(space);
}

/// Lower rank wins: label exact, Latin exact, then prefixes, then contains.
GuideSearchResults queryGuideSearch(GuideSearchIndex index, String rawQuery) {
  final query = foldSearch(rawQuery);
  if (query.isEmpty) {
    return const GuideSearchResults(plants: [], genera: [], families: []);
  }

  final ranks = <int, int>{};
  void consider(GuideSearchName hit, int exact, int prefix, int contains) {
    if (!hit.folded.contains(query)) return;
    final rank = hit.folded == query
        ? exact
        : hit.folded.startsWith(query)
            ? prefix
            : contains;
    final current = ranks[hit.id];
    if (current == null || rank < current) ranks[hit.id] = rank;
  }

  for (final hit in index.vernaculars) {
    if (hit.label) {
      consider(hit, 0, 2, 4);
    } else {
      consider(hit, 4, 5, 6);
    }
  }
  for (final hit in index.latins) {
    if (hit.label) {
      consider(hit, 1, 3, 5);
    } else {
      consider(hit, 5, 6, 7);
    }
  }

  final ids = ranks.keys.where(index.latinKeys.containsKey).toList();
  ids.sort((a, b) {
    final byRank = ranks[a]!.compareTo(ranks[b]!);
    if (byRank != 0) return byRank;
    return index.latinKeys[a]!.compareTo(index.latinKeys[b]!);
  });

  return GuideSearchResults(
    plants: [
      for (final id in ids.take(guideSearchPlantLimit))
        GuideSearchPlant(
          id: id,
          latinKey: index.latinKeys[id]!,
          labelKey: index.labelKeys[id],
        ),
    ],
    genera: _matchTaxa(index.genera, query),
    families: _matchTaxa(index.families, query),
  );
}

List<GuideSearchTaxon> _matchTaxa(List<GuideSearchTaxon> taxa, String query) {
  bool matches(GuideSearchTaxon taxon) {
    if (foldSearch(taxon.latinName).contains(query)) return true;
    for (final name in taxon.vernaculars) {
      if (foldSearch(name).contains(query)) return true;
    }
    return false;
  }

  int rankOf(GuideSearchTaxon taxon) {
    final latin = foldSearch(taxon.latinName);
    if (latin == query) return 0;
    for (final name in taxon.vernaculars) {
      if (foldSearch(name) == query) return 0;
    }
    if (latin.startsWith(query)) return 1;
    for (final name in taxon.vernaculars) {
      if (foldSearch(name).startsWith(query)) return 1;
    }
    return 2;
  }

  final matched = taxa.where(matches).toList();
  matched.sort((a, b) {
    final byRank = rankOf(a).compareTo(rankOf(b));
    if (byRank != 0) return byRank;
    final byName = foldSearch(a.latinName).compareTo(foldSearch(b.latinName));
    if (byName != 0) return byName;
    return a.latinName.compareTo(b.latinName);
  });
  return matched.take(guideSearchTaxonLimit).toList();
}

void _readNames(
  dynamic raw,
  List<GuideSearchName> into,
  Map<int, String> labels,
) {
  if (raw is! Map) return;
  raw.forEach((key, value) {
    if (value is! Map) return;
    final text = key.toString();
    final folded = foldSearch(text);
    if (folded.isEmpty) return;
    final label = value[firebaseAttributeIsLabel] != null;
    for (final id in _ids(value[firebaseAttributeList])) {
      into.add(GuideSearchName(folded, id, label));
      if (label) labels.putIfAbsent(id, () => text);
    }
  });
}

Iterable<int> _ids(dynamic list) sync* {
  if (list is List) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] != null) yield i;
    }
  } else if (list is Map) {
    for (final key in list.keys) {
      if (list[key] == null) continue;
      final id = int.tryParse(key.toString());
      if (id != null) yield id;
    }
  }
}

void _readTaxa(
  dynamic apg,
  dynamic taxonomyNames,
  List<GuideSearchTaxon> families,
  List<GuideSearchTaxon> genera,
) {
  if (apg is! Map) return;
  final root = apg[firebaseRootTaxon];
  if (root is! Map) return;
  _walkTaxon(
    root,
    '$firebaseAPGIV/',
    firebaseRootTaxon,
    null,
    taxonomyNames,
    families,
    genera,
  );
}

void _walkTaxon(
  Map<dynamic, dynamic> node,
  String path,
  String name,
  String? family,
  dynamic taxonomyNames,
  List<GuideSearchTaxon> families,
  List<GuideSearchTaxon> genera,
) {
  final type = node[firebaseAPGType];
  final nextFamily = type == 'Familia' ? name : family;
  final count = _asInt(node[firebaseAttributeCount]);
  if ((type == 'Familia' || type == 'Genus') && count > 0) {
    final taxon = GuideSearchTaxon(
      latinName: name,
      vernaculars: _vernaculars(taxonomyNames, name),
      count: count,
      listPath: '$path$name/$firebaseAttributeList',
      illustrationFamily: nextFamily ?? '',
      plantIds: type == 'Genus'
          ? guideResultIds(node[firebaseAttributeList])
          : const [],
    );
    if (type == 'Familia') {
      families.add(taxon);
    } else {
      genera.add(taxon);
    }
  }
  node.forEach((key, value) {
    final child = key.toString();
    if (child == firebaseAPGType ||
        child == firebaseAttributeList ||
        child == firebaseAttributeCount ||
        child == firebaseAttributeFreebase) {
      return;
    }
    if (value is Map) {
      _walkTaxon(
        value,
        '$path$name/',
        child,
        nextFamily,
        taxonomyNames,
        families,
        genera,
      );
    }
  });
}

class GuideBookTaxa {
  final List<GuideSearchTaxon> families;
  final List<GuideSearchTaxon> genera;

  const GuideBookTaxa({required this.families, required this.genera});

  int get plants {
    var total = 0;
    for (final family in families) {
      total += family.count;
    }
    return total;
  }
}

/// The name a row shows: the first vernacular, or the Latin name.
String guideTaxonTitle(GuideSearchTaxon taxon) {
  for (final name in taxon.vernaculars) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return taxon.latinName;
}

@visibleForTesting
int compareGuideBookTaxa(GuideSearchTaxon a, GuideSearchTaxon b) {
  final byName = foldSearch(guideTaxonTitle(a)).compareTo(
    foldSearch(guideTaxonTitle(b)),
  );
  if (byName != 0) return byName;
  final byLatin = foldSearch(a.latinName).compareTo(foldSearch(b.latinName));
  if (byLatin != 0) return byLatin;
  return a.latinName.compareTo(b.latinName);
}

GuideBookTaxa guideBookTaxa(
  List<GuideSearchTaxon> families,
  List<GuideSearchTaxon> genera,
) {
  return GuideBookTaxa(
    families: [...families]..sort(compareGuideBookTaxa),
    genera: [...genera]..sort(compareGuideBookTaxa),
  );
}

String? guideFamilyIllustration(String family) {
  if (family.isEmpty) return null;
  return storageFamilies + family + defaultExtension;
}

final Map<String, GuideBookTaxa> _bookTaxa = {};
final Map<String, Future<GuideBookTaxa>> _bookLoads = {};

Future<GuideBookTaxa> loadGuideBookTaxa(String languageCode) {
  final lang = getLanguageCode(languageCode);
  final ready = _bookTaxa[lang];
  if (ready != null) return Future.value(ready);
  final pending = _bookLoads[lang];
  if (pending != null) return pending;
  final load = _fetchGuideBookTaxa(lang).then((taxa) {
    _bookTaxa[lang] = taxa;
    return taxa;
  });
  _bookLoads[lang] = load;
  return load.whenComplete(() {
    if (identical(_bookLoads[lang], load)) _bookLoads.remove(lang);
  });
}

/// `.once()` waits for the server and does not finish in flight mode.
const _guideBookWait = Duration(seconds: 4);

Future<bool> _bookOnPhoneOnly() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.every((item) => item == ConnectivityResult.none);
  } catch (error) {
    debugPrint('guide book connectivity: $error');
    return false;
  }
}

Future<GuideBookTaxa> _fetchGuideBookTaxa(String lang) async {
  final cached = peekGuideSearchIndex(lang);
  if (cached != null) return guideBookTaxa(cached.families, cached.genera);
  final taxonomyRef = translationsTaxonomyReference.child(lang);
  final phoneOnly = await _bookOnPhoneOnly();
  if (phoneOnly) {
    final snaps = await Future.wait([
      guideServerGet(apgIVReference).timeout(_guideBookWait),
      guideServerGet(taxonomyRef).timeout(_guideBookWait),
    ]);
    return _bookTaxaFrom(
      snaps[0].value,
      snaps[1].value,
      requireBody: true,
    );
  }
  try {
    await Future.wait([
      guideKeepSynced(apgIVReference, true),
      guideKeepSynced(taxonomyRef, true),
    ]).timeout(_guideBookWait);
  } catch (error) {
    debugPrint('guide book sync: $error');
  }
  // No second get. A dead network that still reports an interface does not
  // answer from disk, so the book page shows its error state.
  final events = await Future.wait([
    apgIVReference.once(),
    taxonomyRef.once(),
  ]).timeout(_guideBookWait);
  return _bookTaxaFrom(
    events[0].snapshot.value,
    events[1].snapshot.value,
    requireBody: false,
  );
}

GuideBookTaxa _bookTaxaFrom(
  dynamic apg,
  dynamic names, {
  required bool requireBody,
}) {
  final families = <GuideSearchTaxon>[];
  final genera = <GuideSearchTaxon>[];
  _readTaxa(apg, names, families, genera);
  _rememberApgLists(apg);
  if (requireBody && families.isEmpty && genera.isEmpty) {
    throw StateError('book is empty');
  }
  return guideBookTaxa(families, genera);
}

final Map<String, dynamic> _apgListNodes = {};
bool _apgListsReady = false;
Future<void>? _apgListLoad;

/// Plant-id node for an APG `…/list` path already read with the book.
/// Null when that tree is not on the phone yet, or the path is not a list.
dynamic guideApgListNode(String path) {
  var key = path;
  if (key.startsWith('/')) key = key.substring(1);
  return _apgListNodes[key];
}

/// Reads the family and genus lists from the copy of APG already on the phone.
/// A child `…/list` get waits on the network even when the tree is stored.
Future<void> ensureGuideApgLists() {
  if (_apgListsReady) return Future.value();
  final pending = _apgListLoad;
  if (pending != null) return pending;
  final load = _loadApgLists();
  _apgListLoad = load;
  return load.whenComplete(() {
    if (identical(_apgListLoad, load)) _apgListLoad = null;
  });
}

Future<void> _loadApgLists() async {
  final phoneOnly = await _bookOnPhoneOnly();
  if (!phoneOnly) return;
  final snapshot = await guideServerGet(apgIVReference).timeout(_guideBookWait);
  _rememberApgLists(snapshot.value);
}

void _rememberApgLists(dynamic apg) {
  _apgListNodes.clear();
  _apgListsReady = true;
  if (apg is! Map) return;
  void walk(dynamic node, String path) {
    if (node is! Map) return;
    if (node.containsKey(firebaseAttributeList)) {
      _apgListNodes['$path$firebaseAttributeList'] =
          node[firebaseAttributeList];
    }
    node.forEach((key, value) {
      final child = key.toString();
      if (child == firebaseAPGType ||
          child == firebaseAttributeList ||
          child == firebaseAttributeCount ||
          child == firebaseAttributeFreebase) {
        return;
      }
      if (value is Map) walk(value, '$path$child/');
    });
  }

  final root = apg[firebaseRootTaxon];
  if (root is Map) walk(root, '$firebaseAPGIV/$firebaseRootTaxon/');
}

@visibleForTesting
void debugRememberGuideApg(dynamic apg) {
  _rememberApgLists(apg);
}

@visibleForTesting
void debugResetGuideApgLists() {
  _apgListNodes.clear();
  _apgListsReady = false;
  _apgListLoad = null;
}

List<String> _vernaculars(dynamic dictionary, String taxon) {
  if (dictionary is! Map) return const [];
  final raw = dictionary[taxon];
  if (raw is String && raw.isNotEmpty) return [raw];
  if (raw is List) {
    return [
      for (final item in raw)
        if (item is String && item.isNotEmpty) item,
    ];
  }
  if (raw is Map) {
    final names = <String>[];
    raw.forEach((_, value) {
      if (value is String && value.isNotEmpty) names.add(value);
    });
    return names;
  }
  return const [];
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

final Map<String, GuideSearchIndex> _indexes = {};
final Map<String, Future<GuideSearchIndex>> _indexLoads = {};
final Map<String, GuidePlantCard> _cards = {};
final Map<String, Future<GuidePlantCard>> _cardLoads = {};

GuideSearchIndex? peekGuideSearchIndex(String languageCode) {
  return _indexes[getLanguageCode(languageCode)];
}

Future<GuideSearchIndex> loadGuideSearchIndex(String languageCode) {
  final lang = getLanguageCode(languageCode);
  final ready = _indexes[lang];
  if (ready != null) return Future.value(ready);
  final pending = _indexLoads[lang];
  if (pending != null) return pending;
  final load = _fetchGuideSearchIndex(lang).then((index) {
    _indexes[lang] = index;
    return index;
  });
  _indexLoads[lang] = load;
  return load.whenComplete(() {
    if (identical(_indexLoads[lang], load)) _indexLoads.remove(lang);
  });
}

Future<GuideSearchIndex> _fetchGuideSearchIndex(String lang) async {
  final vernacularRef = searchReference.child(lang);
  final latinRef = searchReference.child(languageLatin);
  final taxonomyRef = translationsTaxonomyReference.child(lang);
  await Future.wait([
    guideKeepSynced(vernacularRef, true),
    guideKeepSynced(latinRef, true),
    guideKeepSynced(apgIVReference, true),
    guideKeepSynced(taxonomyRef, true),
  ]);
  final events = await Future.wait([
    vernacularRef.once(),
    latinRef.once(),
    apgIVReference.once(),
    taxonomyRef.once(),
  ]);
  return GuideSearchIndex.parse(
    vernacular: events[0].snapshot.value,
    latin: events[1].snapshot.value,
    apg: events[2].snapshot.value,
    taxonomyNames: events[3].snapshot.value,
  );
}

Future<GuidePlantCard> loadGuidePlantCard(String languageCode, int id) {
  final lang = getLanguageCode(languageCode);
  final key = '$lang/$id';
  final ready = _cards[key];
  if (ready != null) return Future.value(ready);
  final pending = _cardLoads[key];
  if (pending != null) return pending;
  final load = _fetchGuidePlantCard(lang, id).then((card) {
    _cards[key] = card;
    return card;
  });
  _cardLoads[key] = load;
  return load.whenComplete(() {
    if (identical(_cardLoads[key], load)) _cardLoads.remove(key);
  });
}

Future<GuidePlantCard> _fetchGuidePlantCard(String lang, int id) async {
  final event = await listsReference.child('$id').once();
  final value = event.snapshot.value;
  String? name;
  String? photo;
  if (value is Map) {
    final rawName = value[firebaseAttributeName];
    if (rawName is String && rawName.isNotEmpty) name = rawName;
    final url = value[firebaseAttributeUrl];
    if (url is String && url.isNotEmpty) photo = storagePhotos + url;
  }
  String? label;
  if (name != null) {
    final labelEvent = await translationsReference
        .child(lang)
        .child(name)
        .child(firebaseAttributeLabel)
        .once();
    final raw = labelEvent.snapshot.value;
    if (raw is String && raw.isNotEmpty) label = raw;
  }
  return GuidePlantCard(latinName: name, label: label, photoPath: photo);
}
