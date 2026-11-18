import 'package:abherbs_flutter/data/utils.dart';
import 'package:diacritic/diacritic.dart';

/// Thrown when the person refuses this phone's location.
class GuideLocationRefused implements Exception {
  const GuideLocationRefused();
}

/// The language's stored vernacular, then a label already read this session.
/// An empty store leaves the Latin name on the card.
String? guideResultLabel(
  String name, {
  required Map<String, String> stored,
  String? cached,
}) {
  final fromStore = stored[name]?.trim();
  if (fromStore != null && fromStore.isNotEmpty) return fromStore;
  final memory = cached?.trim();
  if (memory != null && memory.isNotEmpty) return memory;
  return null;
}

/// A vernacular title, or null when [label] is missing or is the Latin name.
String? distinctVernacular(String? label, String latin) {
  final value = label?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.toLowerCase() == latin.toLowerCase()) return null;
  return value;
}

/// A plant on the key's result list, before flowering order is applied.
class GuideResultPlant {
  final String id;
  final String name;
  final String? label;
  final String? photoPath;
  final String? platePath;
  final int floweringFrom;
  final int floweringTo;
  final bool cultivated;

  const GuideResultPlant({
    required this.id,
    required this.name,
    required this.label,
    required this.photoPath,
    required this.platePath,
    required this.floweringFrom,
    required this.floweringTo,
    required this.cultivated,
  });

  String get shownName => distinctVernacular(label, name) ?? name;
}

class GuideResultList {
  final List<GuideResultPlant> plants;
  final int inFlowerCount;

  const GuideResultList({required this.plants, required this.inFlowerCount});
}

class GuideResultPrefs {
  final String? regionId;
  final bool fromLocation;
  final bool wildOnly;
  final bool locationRefused;

  const GuideResultPrefs({
    this.regionId,
    this.fromLocation = false,
    this.wildOnly = false,
    this.locationRefused = false,
  });

  GuideResultPrefs copyWith({
    String? regionId,
    bool clearRegion = false,
    bool? fromLocation,
    bool? wildOnly,
    bool? locationRefused,
  }) {
    return GuideResultPrefs(
      regionId: clearRegion ? null : (regionId ?? this.regionId),
      fromLocation: fromLocation ?? this.fromLocation,
      wildOnly: wildOnly ?? this.wildOnly,
      locationRefused: locationRefused ?? this.locationRefused,
    );
  }
}

class GuideMonthSlot {
  final bool inFlower;
  final int count;
  final bool controls;

  const GuideMonthSlot({
    required this.inFlower,
    required this.count,
    required this.controls,
  });
}

class GuidePlantSlot {
  final GuideResultPlant plant;

  const GuidePlantSlot(this.plant);
}

class GuideAdSlot {
  const GuideAdSlot();
}

/// Europe first, then the three United States regions the mockup shows
/// before the rest of the level-2 list.
const guideFeaturedRegionIds = [
  '10',
  '11',
  '12',
  '13',
  '14',
  '75',
  '77',
  '78',
];

const guideRegionGroups = <List<String>>[
  ['10', '11', '12', '13', '14'],
  ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29'],
  ['30', '31', '32', '33', '34', '35', '36', '37', '38'],
  ['40', '41', '42', '43'],
  ['50', '51'],
  ['60', '61', '62', '63'],
  ['70', '71', '72', '73', '74', '75', '76', '77', '78', '79'],
  ['80', '81', '82', '83', '84', '85'],
  ['90', '91'],
];

List<String> get guideAllRegionIds => [
      for (final group in guideRegionGroups) ...group,
    ];

bool guideInFlower(int from, int to, int month) {
  if (from < 1 || from > 12 || to < 1 || to > 12) return false;
  if (month < 1 || month > 12) return false;
  if (from <= to) return month >= from && month <= to;
  return month >= from || month <= to;
}

String guideResultSortKey(GuideResultPlant plant) {
  return removeDiacritics(plant.shownName).toLowerCase();
}

int compareGuideResultNames(GuideResultPlant a, GuideResultPlant b) {
  final byName = guideResultSortKey(a).compareTo(guideResultSortKey(b));
  if (byName != 0) return byName;
  return a.name.compareTo(b.name);
}

GuideResultList arrangeGuideResults(
  Iterable<GuideResultPlant> plants, {
  required int month,
  required bool wildOnly,
}) {
  final visible = [
    for (final plant in plants)
      if (!wildOnly || !plant.cultivated) plant,
  ];
  final now = visible
      .where((plant) => guideInFlower(
            plant.floweringFrom,
            plant.floweringTo,
            month,
          ))
      .toList()
    ..sort(compareGuideResultNames);
  final later = visible
      .where((plant) => !guideInFlower(
            plant.floweringFrom,
            plant.floweringTo,
            month,
          ))
      .toList()
    ..sort(compareGuideResultNames);
  return GuideResultList(
    plants: [...now, ...later],
    inFlowerCount: now.length,
  );
}

/// One banner, after the third row of [columns] plants.
///
/// A short last row of the in-flower section counts as a row. A short last
/// row of other months does not. When the list never reaches that third row,
/// the banner goes after the last plant.
List<Object> guideResultSlots(
  GuideResultList list, {
  required bool showAd,
  int columns = 2,
}) {
  if (list.plants.isEmpty) return const [];
  final slots = <Object>[
    GuideMonthSlot(
      inFlower: true,
      count: list.inFlowerCount,
      controls: true,
    ),
  ];
  var inRow = 0;
  var rows = 0;
  var placed = false;

  void closeRow({required bool countShort}) {
    if (inRow == 0) return;
    if (inRow == columns || countShort) {
      rows++;
      if (showAd && !placed && rows == 3) {
        slots.add(const GuideAdSlot());
        placed = true;
      }
    }
    inRow = 0;
  }

  for (var i = 0; i < list.plants.length; i++) {
    final otherMonths = i == list.inFlowerCount && list.inFlowerCount > 0;
    if (otherMonths) {
      closeRow(countShort: true);
      slots.add(GuideMonthSlot(
        inFlower: false,
        count: list.plants.length - list.inFlowerCount,
        controls: false,
      ));
    }
    slots.add(GuidePlantSlot(list.plants[i]));
    inRow++;
    if (inRow == columns) closeRow(countShort: false);
  }
  closeRow(countShort: list.inFlowerCount == list.plants.length);
  if (showAd && !placed) slots.add(const GuideAdSlot());
  return slots;
}

List<String> guideResultIds(dynamic value) {
  final ids = <String>[];
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      if (value[i] != null) ids.add('$i');
    }
  } else if (value is Map) {
    value.forEach((key, item) {
      if (item != null) ids.add(key.toString());
    });
  }
  ids.sort((a, b) {
    final left = int.tryParse(a);
    final right = int.tryParse(b);
    if (left != null && right != null) return left.compareTo(right);
    return a.compareTo(b);
  });
  return ids;
}

/// Latin name at the end of an APG list path (`…/Bellis/list`).
String guideListLatin(String listPath) {
  final parts = [
    for (final part in listPath.split('/'))
      if (part.isNotEmpty) part,
  ];
  if (parts.isEmpty) return '';
  if (parts.last == firebaseAttributeList && parts.length >= 2) {
    return parts[parts.length - 2];
  }
  return parts.last;
}

GuideResultPlant? readGuideResultHeader(
  String id,
  dynamic value, {
  String? label,
  String? platePath,
}) {
  if (value is! Map) return null;
  final name = value[firebaseAttributeName];
  if (name is! String || name.isEmpty) return null;
  final vernacular = label != null && label.isNotEmpty ? label : null;
  return GuideResultPlant(
    id: id,
    name: name,
    label: vernacular,
    photoPath: guideStoragePath(value[firebaseAttributeUrl]),
    platePath: guideStoragePath(platePath),
    floweringFrom: guideResultInt(value['floweringFrom']),
    floweringTo: guideResultInt(value['floweringTo']),
    cultivated: value['cultivated'] == true,
  );
}

String? guideStoragePath(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  if (value.startsWith('http') || value.startsWith(storagePhotos)) return value;
  return storagePhotos + value;
}

int guideResultInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

/// Flowering months and the Latin name for one catalog id.
class GuideHeaderBloom {
  final String name;
  final int floweringFrom;
  final int floweringTo;

  const GuideHeaderBloom(this.name, this.floweringFrom, this.floweringTo);
}

/// How many species in a genus are in flower, and how many the person has seen.
class GuideGenusNote {
  final int inFlower;
  final int seen;

  const GuideGenusNote({required this.inFlower, required this.seen});

  bool get isEmpty => inFlower <= 0 && seen <= 0;
}

/// `plants_headers_v3` as a list or a map, keyed by catalog id.
Map<String, GuideHeaderBloom> readGuideHeaderBlooms(dynamic raw) {
  final blooms = <String, GuideHeaderBloom>{};
  void add(String id, dynamic value) {
    if (value is! Map) return;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return;
    blooms[id] = GuideHeaderBloom(
      name,
      guideResultInt(value['floweringFrom']),
      guideResultInt(value['floweringTo']),
    );
  }

  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add('$i', raw[i]);
    }
  } else if (raw is Map) {
    raw.forEach((key, value) => add(key.toString(), value));
  }
  return blooms;
}

/// One `plants_headers_v3` row, enough to answer the key without the
/// generated count and list indexes.
class GuideKeyPlant {
  final String id;
  final String name;
  final Set<String> colors;
  final Set<String> habitats;
  final Set<String> petals;
  final Set<String> regions;

  /// Conifer key. Empty means this plant stays in the flower key.
  final Set<String> leaves;
  final Set<String> cones;
  final String? photoPath;
  final int floweringFrom;
  final int floweringTo;
  final bool cultivated;

  const GuideKeyPlant({
    required this.id,
    required this.name,
    required this.colors,
    required this.habitats,
    required this.petals,
    required this.regions,
    this.leaves = const {},
    this.cones = const {},
    required this.photoPath,
    required this.floweringFrom,
    required this.floweringTo,
    required this.cultivated,
  });

  GuideResultPlant toResult({String? label, String? platePath}) {
    final vernacular = label?.trim();
    return GuideResultPlant(
      id: id,
      name: name,
      label: vernacular != null && vernacular.isNotEmpty ? vernacular : null,
      photoPath: photoPath,
      platePath: guideStoragePath(platePath),
      floweringFrom: floweringFrom,
      floweringTo: floweringTo,
      cultivated: cultivated,
    );
  }
}

/// Codes stored as a list, or as the map Realtime Database uses for an array.
Set<String> guideFilterCodes(dynamic raw) {
  final codes = <String>{};
  void add(dynamic value) {
    if (value is int) {
      codes.add('$value');
    } else if (value is num && value == value.roundToDouble()) {
      codes.add('${value.toInt()}');
    } else if (value is String && value.isNotEmpty) {
      codes.add(value);
    }
  }

  if (raw is List) {
    for (final value in raw) {
      add(value);
    }
  } else if (raw is Map) {
    raw.forEach((_, value) => add(value));
  }
  return codes;
}

/// `plants_headers_v3` as a list or a map, keyed by catalog id.
List<GuideKeyPlant> readGuideKeyPlants(dynamic raw) {
  final plants = <GuideKeyPlant>[];
  void add(String id, dynamic value) {
    if (value is! Map) return;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return;
    plants.add(GuideKeyPlant(
      id: id,
      name: name,
      colors: guideFilterCodes(value['filterColor']),
      habitats: guideFilterCodes(value['filterHabitat']),
      petals: guideFilterCodes(value['filterPetal']),
      regions: guideFilterCodes(value['filterDistribution']),
      leaves: guideFilterCodes(value['filterLeaf']),
      cones: guideFilterCodes(value['filterCone']),
      photoPath: guideStoragePath(value[firebaseAttributeUrl]),
      floweringFrom: guideResultInt(value['floweringFrom']),
      floweringTo: guideResultInt(value['floweringTo']),
      cultivated: value['cultivated'] == true,
    ));
  }

  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add('$i', raw[i]);
    }
  } else if (raw is Map) {
    raw.forEach((key, value) => add(key.toString(), value));
  }
  return plants;
}

bool guideKeySelected(Set<String> values, String? id) {
  if (id == null || id.isEmpty) return true;
  return values.contains(id);
}

bool guideKeyPlantMatches(
  GuideKeyPlant plant, {
  String? colorId,
  String? habitatId,
  String? petalId,
  String? regionId,
}) {
  // A plant with a leaf code is a conifer and stays out of the flower key.
  if (plant.leaves.isNotEmpty) return false;
  return guideKeySelected(plant.colors, colorId) &&
      guideKeySelected(plant.habitats, habitatId) &&
      guideKeySelected(plant.petals, petalId) &&
      guideKeySelected(plant.regions, regionId);
}

/// The conifer key. A plant with no leaf code is a flower and stays out.
bool guideConiferMatches(
  GuideKeyPlant plant, {
  String? leafId,
  String? habitatId,
  String? coneId,
  String? regionId,
}) {
  if (plant.leaves.isEmpty) return false;
  return guideKeySelected(plant.leaves, leafId) &&
      guideKeySelected(plant.habitats, habitatId) &&
      guideKeySelected(plant.cones, coneId) &&
      guideKeySelected(plant.regions, regionId);
}

int guideConiferCount(
  Iterable<GuideKeyPlant> plants, {
  String? leafId,
  String? habitatId,
  String? coneId,
  String? regionId,
}) {
  var count = 0;
  for (final plant in plants) {
    if (guideConiferMatches(
      plant,
      leafId: leafId,
      habitatId: habitatId,
      coneId: coneId,
      regionId: regionId,
    )) {
      count++;
    }
  }
  return count;
}

/// Conifers that pass the key, in catalog-id order.
List<GuideKeyPlant> guideConiferList(
  Iterable<GuideKeyPlant> plants, {
  String? leafId,
  String? habitatId,
  String? coneId,
  String? regionId,
}) {
  final matched = [
    for (final plant in plants)
      if (guideConiferMatches(
        plant,
        leafId: leafId,
        habitatId: habitatId,
        coneId: coneId,
        regionId: regionId,
      ))
        plant,
  ];
  matched.sort((a, b) {
    final left = int.tryParse(a.id);
    final right = int.tryParse(b.id);
    if (left != null && right != null) return left.compareTo(right);
    return a.id.compareTo(b.id);
  });
  return matched;
}

int guideKeyCount(
  Iterable<GuideKeyPlant> plants, {
  String? colorId,
  String? habitatId,
  String? petalId,
  String? regionId,
}) {
  var count = 0;
  for (final plant in plants) {
    if (guideKeyPlantMatches(
      plant,
      colorId: colorId,
      habitatId: habitatId,
      petalId: petalId,
      regionId: regionId,
    )) {
      count++;
    }
  }
  return count;
}

/// Plants that pass the key, in catalog-id order. The same order as
/// `lists_4_v3`.
List<GuideKeyPlant> guideKeyMatches(
  Iterable<GuideKeyPlant> plants, {
  String? colorId,
  String? habitatId,
  String? petalId,
  String? regionId,
}) {
  final matched = [
    for (final plant in plants)
      if (guideKeyPlantMatches(
        plant,
        colorId: colorId,
        habitatId: habitatId,
        petalId: petalId,
        regionId: regionId,
      ))
        plant,
  ];
  matched.sort((a, b) {
    final left = int.tryParse(a.id);
    final right = int.tryParse(b.id);
    if (left != null && right != null) return left.compareTo(right);
    return a.id.compareTo(b.id);
  });
  return matched;
}

GuideGenusNote countGuideGenusNote({
  required Iterable<String> plantIds,
  required Map<String, GuideHeaderBloom> blooms,
  required Set<String> seen,
  required int month,
}) {
  var inFlower = 0;
  var seenCount = 0;
  for (final id in plantIds) {
    final bloom = blooms[id];
    if (bloom == null) continue;
    if (guideInFlower(bloom.floweringFrom, bloom.floweringTo, month)) {
      inFlower++;
    }
    if (seen.contains(bloom.name)) seenCount++;
  }
  return GuideGenusNote(inFlower: inFlower, seen: seenCount);
}

int guideSeenInList(Iterable<GuideResultPlant> plants, Set<String> seen) {
  var count = 0;
  for (final plant in plants) {
    if (seen.contains(plant.name)) count++;
  }
  return count;
}

/// ISO country, and an administrative area when a country spans floristic
/// regions. Coordinates cover splits a place name cannot (Turkey in Europe,
/// the Canaries, Sinai, New Guinea).
String? guideRegionForPlace({
  String? countryCode,
  String? adminArea,
  double? latitude,
  double? longitude,
}) {
  final country = countryCode?.trim().toUpperCase();
  if (country == null || country.isEmpty) return null;
  final code = country == 'UK' ? 'GB' : country;
  if (latitude != null &&
      longitude != null &&
      _inBox(latitude, longitude, 44.2, 46.3, 32.3, 36.8)) {
    return '14';
  }
  if (code == 'RU') {
    return _russia(latitude, longitude);
  }
  if (code == 'US') return _named(_usRegions, adminArea);
  if (code == 'CA') return _named(_caRegions, adminArea);
  if (latitude != null && longitude != null) {
    final split = _splitCountry(code, latitude, longitude);
    if (split != null) return split;
  }
  return _countries[code];
}

String? _russia(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return null;
  if (_inBox(latitude, longitude, 54.3, 55.5, 19.4, 23.0)) return '14';
  if (_inBox(latitude, longitude, 41.2, 46.0, 37.0, 50.2)) return '33';
  if (longitude < 60) return '14';
  if (longitude >= 140) return '31';
  if (longitude >= 127 && latitude < 58) return '31';
  return '30';
}

String? _splitCountry(String code, double latitude, double longitude) {
  switch (code) {
    case 'TR':
      return longitude < 29 && latitude > 40.5 ? '13' : '34';
    case 'ES':
      return latitude < 29.5 && longitude < -13 ? '21' : '12';
    case 'PT':
      if (longitude < -20) return '21';
      if (latitude > 32 &&
          latitude < 33.5 &&
          longitude < -16 &&
          longitude > -17.5) {
        return '21';
      }
      return '12';
    case 'EG':
      return longitude > 32.5 && latitude < 31.2 ? '34' : '20';
    case 'IN':
      return latitude < 14 && longitude > 92 ? '41' : '40';
    case 'ID':
      return longitude >= 131 && latitude < 2 && latitude > -10 ? '43' : '42';
    default:
      return null;
  }
}

bool _inBox(
  double latitude,
  double longitude,
  double south,
  double north,
  double west,
  double east,
) {
  return latitude >= south &&
      latitude <= north &&
      longitude >= west &&
      longitude <= east;
}

String? _named(Map<String, String> regions, String? adminArea) {
  if (adminArea == null || adminArea.trim().isEmpty) return null;
  return regions[guidePlaceKey(adminArea)];
}

String guidePlaceKey(String value) {
  return removeDiacritics(value).toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
}

const _countries = <String, String>{
  'ES': '12',
  'PT': '12',
  'TR': '34',
  'EG': '20',
  'IN': '40',
  'ID': '42',
  'AT': '11',
  'BE': '11',
  'LU': '11',
  'LI': '11',
  'CH': '11',
  'DE': '11',
  'CZ': '11',
  'SK': '11',
  'HU': '11',
  'NL': '11',
  'PL': '11',
  'DK': '10',
  'FI': '10',
  'FO': '10',
  'IS': '10',
  'NO': '10',
  'SE': '10',
  'SJ': '10',
  'AX': '10',
  'GB': '10',
  'IE': '10',
  'IM': '10',
  'FR': '12',
  'MC': '12',
  'AD': '12',
  'GI': '12',
  'GG': '12',
  'JE': '12',
  'IT': '13',
  'VA': '13',
  'SM': '13',
  'MT': '13',
  'GR': '13',
  'EL': '13',
  'AL': '13',
  'BG': '13',
  'RO': '13',
  'SI': '13',
  'HR': '13',
  'BA': '13',
  'RS': '13',
  'ME': '13',
  'MK': '13',
  'XK': '13',
  'EE': '14',
  'LV': '14',
  'LT': '14',
  'BY': '14',
  'UA': '14',
  'MD': '14',
  'DZ': '20',
  'LY': '20',
  'MA': '20',
  'TN': '20',
  'EH': '20',
  'CV': '21',
  'BJ': '22',
  'BF': '22',
  'GM': '22',
  'GH': '22',
  'GW': '22',
  'GN': '22',
  'CI': '22',
  'LR': '22',
  'ML': '22',
  'MR': '22',
  'NG': '22',
  'NE': '22',
  'SN': '22',
  'SL': '22',
  'TG': '22',
  'BI': '23',
  'CF': '23',
  'CM': '23',
  'CG': '23',
  'GQ': '23',
  'GA': '23',
  'ST': '23',
  'RW': '23',
  'CD': '23',
  'TD': '24',
  'DJ': '24',
  'ER': '24',
  'ET': '24',
  'SO': '24',
  'SD': '24',
  'SS': '24',
  'KE': '25',
  'TZ': '25',
  'UG': '25',
  'AO': '26',
  'MW': '26',
  'MZ': '26',
  'ZM': '26',
  'ZW': '26',
  'BW': '27',
  'LS': '27',
  'NA': '27',
  'SZ': '27',
  'ZA': '27',
  'SH': '28',
  'KM': '29',
  'YT': '29',
  'MU': '29',
  'MG': '29',
  'RE': '29',
  'SC': '29',
  'IO': '29',
  'KZ': '32',
  'KG': '32',
  'TM': '32',
  'TJ': '32',
  'UZ': '32',
  'AM': '33',
  'AZ': '33',
  'GE': '33',
  'AF': '34',
  'CY': '34',
  'IR': '34',
  'IQ': '34',
  'LB': '34',
  'SY': '34',
  'JO': '34',
  'IL': '34',
  'PS': '34',
  'BH': '35',
  'QA': '35',
  'AE': '35',
  'KW': '35',
  'OM': '35',
  'SA': '35',
  'YE': '35',
  'CN': '36',
  'HK': '36',
  'MO': '36',
  'MN': '37',
  'JP': '38',
  'KP': '38',
  'KR': '38',
  'TW': '38',
  'BD': '40',
  'BT': '40',
  'MV': '40',
  'NP': '40',
  'PK': '40',
  'LK': '40',
  'KH': '41',
  'LA': '41',
  'MM': '41',
  'TH': '41',
  'VN': '41',
  'BN': '42',
  'TL': '42',
  'MY': '42',
  'SG': '42',
  'PH': '42',
  'CX': '42',
  'CC': '42',
  'PG': '43',
  'SB': '43',
  'AU': '50',
  'NF': '50',
  'NZ': '51',
  'FJ': '60',
  'NR': '60',
  'NU': '60',
  'NC': '60',
  'WS': '60',
  'AS': '60',
  'TK': '60',
  'TO': '60',
  'TV': '60',
  'VU': '60',
  'WF': '60',
  'KI': '60',
  'CK': '61',
  'PF': '61',
  'PN': '61',
  'FM': '62',
  'PW': '62',
  'GU': '62',
  'MP': '62',
  'MH': '62',
  'GL': '70',
  'MX': '79',
  'PM': '72',
  'BZ': '80',
  'CR': '80',
  'SV': '80',
  'GT': '80',
  'HN': '80',
  'NI': '80',
  'PA': '80',
  'AW': '81',
  'BS': '81',
  'BM': '81',
  'KY': '81',
  'CU': '81',
  'DO': '81',
  'HT': '81',
  'JM': '81',
  'PR': '81',
  'TT': '81',
  'VG': '81',
  'VI': '81',
  'AG': '81',
  'AI': '81',
  'MS': '81',
  'KN': '81',
  'BL': '81',
  'MF': '81',
  'SX': '81',
  'BQ': '81',
  'CW': '81',
  'GP': '81',
  'MQ': '81',
  'BB': '81',
  'DM': '81',
  'GD': '81',
  'LC': '81',
  'VC': '81',
  'TC': '81',
  'GF': '82',
  'GY': '82',
  'SR': '82',
  'VE': '82',
  'BO': '83',
  'CO': '83',
  'EC': '83',
  'PE': '83',
  'BR': '84',
  'AR': '85',
  'CL': '85',
  'PY': '85',
  'UY': '85',
  'FK': '90',
  'GS': '90',
  'BV': '90',
  'HM': '90',
  'TF': '90',
  'AQ': '91',
};

const _usRegions = <String, String>{
  'ak': '70',
  'alaska': '70',
  'hi': '63',
  'hawaii': '63',
  'wa': '73',
  'washington': '73',
  'or': '73',
  'oregon': '73',
  'id': '73',
  'idaho': '73',
  'mt': '73',
  'montana': '73',
  'wy': '73',
  'wyoming': '73',
  'co': '73',
  'colorado': '73',
  'il': '74',
  'illinois': '74',
  'ia': '74',
  'iowa': '74',
  'ks': '74',
  'kansas': '74',
  'mn': '74',
  'minnesota': '74',
  'mo': '74',
  'missouri': '74',
  'ne': '74',
  'nebraska': '74',
  'nd': '74',
  'northdakota': '74',
  'ok': '74',
  'oklahoma': '74',
  'sd': '74',
  'southdakota': '74',
  'wi': '74',
  'wisconsin': '74',
  'ct': '75',
  'connecticut': '75',
  'in': '75',
  'indiana': '75',
  'me': '75',
  'maine': '75',
  'ma': '75',
  'massachusetts': '75',
  'mi': '75',
  'michigan': '75',
  'nh': '75',
  'newhampshire': '75',
  'nj': '75',
  'newjersey': '75',
  'ny': '75',
  'newyork': '75',
  'oh': '75',
  'ohio': '75',
  'pa': '75',
  'pennsylvania': '75',
  'ri': '75',
  'rhodeisland': '75',
  'vt': '75',
  'vermont': '75',
  'wv': '75',
  'westvirginia': '75',
  'az': '76',
  'arizona': '76',
  'ca': '76',
  'california': '76',
  'nv': '76',
  'nevada': '76',
  'ut': '76',
  'utah': '76',
  'nm': '77',
  'newmexico': '77',
  'tx': '77',
  'texas': '77',
  'al': '78',
  'alabama': '78',
  'ar': '78',
  'arkansas': '78',
  'de': '78',
  'delaware': '78',
  'fl': '78',
  'florida': '78',
  'ga': '78',
  'georgia': '78',
  'ky': '78',
  'kentucky': '78',
  'la': '78',
  'louisiana': '78',
  'md': '78',
  'maryland': '78',
  'ms': '78',
  'mississippi': '78',
  'nc': '78',
  'northcarolina': '78',
  'sc': '78',
  'southcarolina': '78',
  'tn': '78',
  'tennessee': '78',
  'va': '78',
  'virginia': '78',
  'dc': '78',
  'districtofcolumbia': '78',
  'washingtondc': '78',
};

const _caRegions = <String, String>{
  'yt': '70',
  'yukon': '70',
  'nt': '70',
  'northwestterritories': '70',
  'nu': '70',
  'nunavut': '70',
  'bc': '71',
  'britishcolumbia': '71',
  'ab': '71',
  'alberta': '71',
  'sk': '71',
  'saskatchewan': '71',
  'mb': '71',
  'manitoba': '71',
  'on': '72',
  'ontario': '72',
  'qc': '72',
  'quebec': '72',
  'nb': '72',
  'newbrunswick': '72',
  'ns': '72',
  'novascotia': '72',
  'pe': '72',
  'princeedwardisland': '72',
  'nl': '72',
  'newfoundlandandlabrador': '72',
  'newfoundland': '72',
  'labrador': '72',
};
