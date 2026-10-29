import 'package:abherbs_flutter/offline/guide_media.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Decimal megabytes of pictures per species: photos, the unsuffixed plate
/// the app opens, and the range map. Mean of all 1,433 species in the
/// 2 Oct 2026 catalog (0.662 MB; one range map was missing). The page
/// treats 1,000 MB as 1 GB.
const guideOfflineMbPerPlant = 0.66;

class GuideOfflineGroup {
  final String id;
  final List<String> codes;

  const GuideOfflineGroup(this.id, this.codes);
}

/// Floristic packs. Antarctic is left out: no species lives only there.
const guideOfflineGroups = <GuideOfflineGroup>[
  GuideOfflineGroup('1', ['10', '11', '12', '13', '14']),
  GuideOfflineGroup(
      '2', ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29']),
  GuideOfflineGroup(
      '3', ['30', '31', '32', '33', '34', '35', '36', '37', '38']),
  GuideOfflineGroup('4', ['40', '41', '42', '43']),
  GuideOfflineGroup('5', ['50', '51']),
  GuideOfflineGroup('6', ['60', '61', '62', '63']),
  GuideOfflineGroup(
      '7', ['70', '71', '72', '73', '74', '75', '76', '77', '78', '79']),
  GuideOfflineGroup('8', ['80', '81', '82', '83', '84', '85']),
];

final Set<String> guideOfflinePackCodes = {
  for (final group in guideOfflineGroups) ...group.codes,
};

/// One entry per catalog plant: the level-2 codes where it occurs.
class GuideOfflineCatalog {
  final List<Set<String>> plants;

  /// Catalog id for each [plants] entry. Empty means the list index is the id.
  final List<int> ids;

  const GuideOfflineCatalog(this.plants, {this.ids = const []});

  int get total => plants.length;

  int idAt(int index) => ids.isEmpty ? index : ids[index];

  /// Level-2 codes for a catalog id. Null when the headers do not have it.
  Set<String>? regionsFor(int id) {
    for (var index = 0; index < plants.length; index++) {
      if (idAt(index) == id) return plants[index];
    }
    return null;
  }

  static const empty = GuideOfflineCatalog([]);
}

GuideOfflineCatalog readGuideOfflineCatalog(dynamic raw) {
  final plants = <Set<String>>[];
  final ids = <int>[];
  void add(int id, dynamic value) {
    if (value is! Map) return;
    final name = value[firebaseAttributeName];
    if (name is! String || name.isEmpty) return;
    plants.add(_codes(value['filterDistribution']));
    ids.add(id);
  }

  if (raw is List) {
    for (var index = 0; index < raw.length; index++) {
      add(index, raw[index]);
    }
  } else if (raw is Map) {
    final entries = <MapEntry<int, dynamic>>[];
    raw.forEach((key, value) {
      final id = int.tryParse(key.toString());
      if (id == null) return;
      entries.add(MapEntry(id, value));
    });
    entries.sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      add(entry.key, entry.value);
    }
  }
  return GuideOfflineCatalog(plants, ids: ids);
}

Set<String> _codes(dynamic raw) {
  final codes = <String>{};
  void add(dynamic value) {
    final code = _code(value);
    if (code != null) codes.add(code);
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

String? _code(dynamic value) {
  if (value is int) return '$value';
  if (value is num && value == value.roundToDouble()) return '${value.toInt()}';
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Null means the whole book. An empty set matches nothing.
int guideOfflineMatch(GuideOfflineCatalog catalog, Set<String>? codes) {
  if (codes == null) return catalog.total;
  if (codes.isEmpty) return 0;
  var count = 0;
  for (final plant in catalog.plants) {
    for (final code in plant) {
      if (codes.contains(code)) {
        count++;
        break;
      }
    }
  }
  return count;
}

Set<String>? guideOfflineUnion(Set<String>? a, Set<String>? b) {
  if (a == null || b == null) return null;
  return {...a, ...b};
}

/// Rounded picture size. At 1,000 MB and above the text is gigabytes.
class GuideOfflineSize {
  final bool gigabytes;
  final String amount;

  const GuideOfflineSize._(this.gigabytes, this.amount);

  static GuideOfflineSize of(int plants) {
    final mb = plants * guideOfflineMbPerPlant;
    if (mb >= 1000) {
      final tenths = (mb / 100).round();
      return GuideOfflineSize._(true, (tenths / 10).toStringAsFixed(1));
    }
    final rounded = (mb / 10).round() * 10;
    return GuideOfflineSize._(false, '$rounded');
  }

  /// Megabytes shown on a download bar. A gigabyte size stays in megabytes
  /// here so the bar can move in the same unit as the bytes already fetched.
  int get barMb {
    if (!gigabytes) return int.parse(amount);
    return (double.parse(amount) * 1000).round();
  }
}

/// Picture bytes for one update. Small updates stay in tenths of a megabyte
/// so a new plate does not round down to nothing.
class GuideOfflineBytes {
  final bool gigabytes;
  final String amount;

  const GuideOfflineBytes._(this.gigabytes, this.amount);

  static GuideOfflineBytes of(int bytes) {
    if (bytes <= 0) return const GuideOfflineBytes._(false, '0');
    final mb = bytes / 1000000;
    if (mb >= 1000) {
      final tenths = (mb / 100).round();
      return GuideOfflineBytes._(true, (tenths / 10).toStringAsFixed(1));
    }
    if (mb >= 1) return GuideOfflineBytes._(false, '${mb.round()}');
    final tenths = (mb * 10).round();
    final shown = tenths <= 0 ? 1 : tenths;
    return GuideOfflineBytes._(false, (shown / 10).toStringAsFixed(1));
  }
}

class GuideOfflineLabel {
  final bool everything;
  final String? regionId;
  final String? groupId;
  final int count;

  const GuideOfflineLabel._({
    required this.everything,
    required this.regionId,
    required this.groupId,
    required this.count,
  });

  const GuideOfflineLabel.everything()
      : this._(everything: true, regionId: null, groupId: null, count: 0);

  const GuideOfflineLabel.region(String id)
      : this._(everything: false, regionId: id, groupId: null, count: 1);

  const GuideOfflineLabel.group(String id)
      : this._(everything: false, regionId: null, groupId: id, count: 0);

  const GuideOfflineLabel.count(int count)
      : this._(
          everything: false,
          regionId: null,
          groupId: null,
          count: count,
        );
}

GuideOfflineLabel guideOfflineLabel(Set<String>? codes) {
  if (codes == null) return const GuideOfflineLabel.everything();
  if (codes.length == 1) return GuideOfflineLabel.region(codes.first);
  for (final group in guideOfflineGroups) {
    if (group.codes.length == codes.length &&
        group.codes.every(codes.contains)) {
      return GuideOfflineLabel.group(group.id);
    }
  }
  return GuideOfflineLabel.count(codes.length);
}

/// The level-2 code that holds most of a continent, when it is more than
/// three fifths of that continent's plants.
String? guideOfflineOverlap(GuideOfflineCatalog catalog, List<String> codes) {
  final all = guideOfflineMatch(catalog, codes.toSet());
  if (all <= 0) return null;
  String? best;
  var bestCount = 0;
  for (final code in codes) {
    final count = guideOfflineMatch(catalog, {code});
    if (count > bestCount) {
      bestCount = count;
      best = code;
    }
  }
  if (best != null && bestCount > all * 0.6) return best;
  return null;
}

class GuideOfflinePick {
  final bool everything;
  final Set<String> regions;

  const GuideOfflinePick({
    this.everything = false,
    this.regions = const {},
  });

  bool get chosen => everything || regions.isNotEmpty;

  Set<String>? get asCodes => everything ? null : regions;

  GuideOfflinePick toggleEverything() {
    return GuideOfflinePick(everything: !everything);
  }

  GuideOfflinePick toggleGroup(List<String> codes) {
    if (everything) return GuideOfflinePick(regions: codes.toSet());
    final next = {...regions};
    if (codes.every(next.contains)) {
      next.removeAll(codes);
    } else {
      next.addAll(codes);
    }
    return GuideOfflinePick(regions: next);
  }

  GuideOfflinePick toggleRegion(String code) {
    if (everything) return GuideOfflinePick(regions: {code});
    final next = {...regions};
    if (!next.add(code)) next.remove(code);
    return GuideOfflinePick(regions: next);
  }

  bool groupOn(List<String> codes) {
    return everything || (codes.isNotEmpty && codes.every(regions.contains));
  }

  bool groupMid(List<String> codes) {
    if (everything || groupOn(codes)) return false;
    return codes.any(regions.contains);
  }

  bool regionOn(String code) => everything || regions.contains(code);
}

class GuideOfflineStored {
  final bool everything;
  final Set<String> regions;

  const GuideOfflineStored({
    this.everything = false,
    this.regions = const {},
  });

  const GuideOfflineStored.everything() : this(everything: true);

  bool get isEmpty => !everything && regions.isEmpty;

  Set<String>? get asCodes =>
      everything ? null : (regions.isEmpty ? {} : regions);

  bool covers(String code) => everything || regions.contains(code);
}

/// True when this phone already keeps a pack. Book and its lists then open
/// from that copy, whether or not the phone has a connection.
bool guidePackOnPhone({
  required String packs,
  required bool classic,
  required String done,
}) {
  if (!guideOfflineStoredFrom(packs, classic: classic).isEmpty) return true;
  return offlineDoneParse(done).isNotEmpty;
}

GuideOfflineStored guideOfflineStoredFrom(
  String packs, {
  required bool classic,
}) {
  if (packs == 'all') return const GuideOfflineStored.everything();
  final regions = <String>{
    for (final part in packs.split(','))
      if (guideOfflinePackCodes.contains(part)) part,
  };
  if (regions.isNotEmpty) return GuideOfflineStored(regions: regions);
  if (classic) return const GuideOfflineStored.everything();
  return const GuideOfflineStored();
}

/// Plants this download still has to fetch. A plant in two selected regions
/// is one row. Plants already covered by a stored pack, or already fetched,
/// are left out. [requestCodes] null is the whole book. [storedCodes] null
/// means the whole book is already stored.
class GuideOfflineJobPlan {
  final Set<String>? codes;
  final List<int> pending;
  final int alreadyDone;
  final int total;

  const GuideOfflineJobPlan({
    required this.codes,
    required this.pending,
    required this.alreadyDone,
    required this.total,
  });
}

bool guideOfflineInPack(Set<String> plant, Set<String>? codes) {
  if (codes == null) return true;
  for (final code in plant) {
    if (codes.contains(code)) return true;
  }
  return false;
}

GuideOfflineJobPlan guideOfflinePlan({
  required GuideOfflineCatalog catalog,
  required Set<String>? requestCodes,
  required Set<String>? storedCodes,
  required Set<int> done,
}) {
  if (storedCodes == null) {
    return GuideOfflineJobPlan(
      codes: requestCodes,
      pending: const [],
      alreadyDone: 0,
      total: 0,
    );
  }
  final pending = <int>[];
  var alreadyDone = 0;
  for (var index = 0; index < catalog.plants.length; index++) {
    final plant = catalog.plants[index];
    if (!guideOfflineInPack(plant, requestCodes)) continue;
    if (storedCodes.isNotEmpty && guideOfflineInPack(plant, storedCodes)) {
      continue;
    }
    final id = catalog.idAt(index);
    if (done.contains(id)) {
      alreadyDone++;
      continue;
    }
    pending.add(id);
  }
  return GuideOfflineJobPlan(
    codes: requestCodes,
    pending: pending,
    alreadyDone: alreadyDone,
    total: alreadyDone + pending.length,
  );
}

GuideOfflineStored guideOfflineStore(
  GuideOfflineStored current,
  GuideOfflineRequest request,
) {
  if (current.everything || request.everything) {
    return const GuideOfflineStored.everything();
  }
  return GuideOfflineStored(regions: {...current.regions, ...request.regions});
}

String guideOfflinePacksValue(GuideOfflineStored stored) {
  if (stored.everything) return 'all';
  final codes = stored.regions.toList()..sort();
  return codes.join(',');
}

class GuideOfflineRequest {
  final bool everything;
  final Set<String> regions;
  final int added;
  final String title;

  const GuideOfflineRequest({
    required this.everything,
    required this.regions,
    required this.added,
    required this.title,
  });
}

class GuideOfflineJob {
  final String title;
  final int plants;
  final int doneMb;
  final int totalMb;
  final String? doneText;
  final String? totalText;

  const GuideOfflineJob({
    required this.title,
    required this.plants,
    required this.doneMb,
    required this.totalMb,
    this.doneText,
    this.totalText,
  });

  double get fraction {
    if (totalMb <= 0) return 0;
    return (doneMb / totalMb).clamp(0, 1).toDouble();
  }
}

enum GuideOfflineMenuKind { legacy, upsell, empty, book, stored }

class GuideOfflineHold {
  final bool canDownload;
  final bool everything;
  final int storedPlants;
  final int totalPlants;
  final List<String> regionIds;
  final int updateBytes;
  final int updatePlants;

  const GuideOfflineHold({
    required this.canDownload,
    required this.everything,
    required this.storedPlants,
    required this.totalPlants,
    this.regionIds = const [],
    this.updateBytes = 0,
    this.updatePlants = 0,
  });
}

GuideOfflineMenuKind guideOfflineMenuKind(GuideOfflineHold? hold) {
  if (hold == null) return GuideOfflineMenuKind.legacy;
  if (hold.everything) return GuideOfflineMenuKind.book;
  if (hold.regionIds.isNotEmpty || hold.storedPlants > 0) {
    return GuideOfflineMenuKind.stored;
  }
  if (!hold.canDownload) return GuideOfflineMenuKind.upsell;
  return GuideOfflineMenuKind.empty;
}

/// Plants still to fetch after the phone's mark, folded into one update.
/// [resumeMark] is the change-list count once every pending entry was
/// decided. It stays at [mark] when a new plant is not in the headers yet.
class GuideOfflineUpdate {
  final int mark;
  final int resumeMark;
  final List<GuideMediaJob> plants;

  const GuideOfflineUpdate({
    required this.mark,
    required this.resumeMark,
    this.plants = const [],
  });

  static const empty = GuideOfflineUpdate(mark: 0, resumeMark: 0);

  bool get hasWork => plants.isNotEmpty;

  int get bytes {
    var total = 0;
    for (final plant in plants) {
      total += plant.bytes;
    }
    return total;
  }
}

/// Entries at and after [mark]. A new plant is kept when it occurs in a
/// stored pack. Everything keeps every new plant. A picture change is kept
/// when that plant is already stored and still falls in the pack. The latest
/// stamp wins, so two edits of one plant download the net difference.
GuideOfflineUpdate guideOfflineUpdate({
  required GuideChangeLog log,
  required int mark,
  required GuideOfflineCatalog catalog,
  required Set<String>? storedCodes,
  required Map<int, GuideMediaStamp> stamps,
}) {
  if (storedCodes != null && storedCodes.isEmpty) {
    return GuideOfflineUpdate(mark: mark, resumeMark: mark);
  }
  final pending = [
    for (final change in log.changes)
      if (change.index >= mark && change.index < log.count) change,
  ];
  if (pending.isEmpty) {
    final resume = log.count < mark ? mark : log.count;
    return GuideOfflineUpdate(mark: mark, resumeMark: resume);
  }
  final latest = <int, GuideCatalogChange>{};
  for (final change in pending) {
    latest[change.plantId] = change;
  }
  var blocked = false;
  final plants = <GuideMediaJob>[];
  for (final change in latest.values) {
    final regions = catalog.regionsFor(change.plantId);
    final stored = stamps.containsKey(change.plantId);
    if (regions == null && storedCodes != null && !stored) {
      blocked = true;
      continue;
    }
    final inPack = storedCodes == null ||
        (regions != null && regions.any((code) => storedCodes.contains(code)));
    if (!inPack) continue;
    final diff = guideMediaDiff(stamps[change.plantId], change.stamp);
    if (diff.isEmpty) continue;
    plants.add(
      GuideMediaJob(
        id: change.plantId,
        added: !stored,
        stamp: change.stamp,
        download: diff.download,
        remove: diff.remove,
      ),
    );
  }
  plants.sort((a, b) => a.id.compareTo(b.id));
  return GuideOfflineUpdate(
    mark: mark,
    resumeMark: blocked ? mark : log.count,
    plants: plants,
  );
}

class GuideOfflineView {
  final GuideOfflineCatalog catalog;
  final bool canDownload;
  final GuideOfflineStored stored;
  final String? phoneRegionId;
  final GuideOfflineUpdate update;

  const GuideOfflineView({
    required this.catalog,
    required this.canDownload,
    required this.stored,
    required this.phoneRegionId,
    this.update = GuideOfflineUpdate.empty,
  });
}

/// A catalog read may take this long before the copy already on the phone
/// is used. `.get()` on a node that was never stored does not finish offline.
const _guideOfflineWait = Duration(seconds: 4);

Future<GuideOfflineView> loadGuideOffline() async {
  final snapshot = await headersV3Reference.get().timeout(_guideOfflineWait);
  final catalog = readGuideOfflineCatalog(snapshot.value);
  final packs = await Prefs.getStringF(keyGuideOfflinePacks, '');
  final classic = await Prefs.getBoolF(keyOffline, false);
  final stored = guideOfflineStoredFrom(packs, classic: classic);
  final guideRegion = await Prefs.getStringF(keyGuideRegion, '');
  final myRegion = guideRegion.isEmpty
      ? await Prefs.getStringF(keyMyRegion, '')
      : guideRegion;
  final phone = guideOfflinePackCodes.contains(myRegion) ? myRegion : null;
  await Prefs.setString(keyGuideOfflineTotal, '${catalog.total}');
  if (!stored.isEmpty) {
    final plants = guideOfflineMatch(
      catalog,
      stored.everything ? null : stored.regions,
    );
    await Prefs.setString(keyGuideOfflineStoredPlants, '$plants');
  }
  final update = await loadGuideOfflineUpdate(catalog, stored);
  return GuideOfflineView(
    catalog: catalog,
    canDownload: Purchases.hasFieldGuide() || Purchases.isOffline(),
    stored: stored,
    phoneRegionId: phone,
    update: update.hasWork ? update : GuideOfflineUpdate.empty,
  );
}

/// True when the phone reports no network. A check that throws counts as
/// online, so a working connection still reads the catalog.
Future<bool> _offlinePhoneOnly() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.every((item) => item == ConnectivityResult.none);
  } catch (error) {
    debugPrint('guide connectivity: $error');
    return false;
  }
}

/// Change-list entries after the phone's mark, for the packs already stored.
/// A denied or missing node leaves the line empty so Offline still opens.
/// With no network the change list is left unread: that `.get()` does not
/// finish, and Account would stay on its spinner.
Future<GuideOfflineUpdate> loadGuideOfflineUpdate(
  GuideOfflineCatalog catalog,
  GuideOfflineStored stored,
) async {
  if (stored.isEmpty) return GuideOfflineUpdate.empty;
  dynamic raw;
  try {
    if (await _offlinePhoneOnly()) return GuideOfflineUpdate.empty;
    raw = (await rootReference
            .child(firebaseCatalogChanges)
            .get()
            .timeout(_guideOfflineWait))
        .value;
  } catch (error) {
    debugPrint('catalog changes: $error');
    return GuideOfflineUpdate.empty;
  }
  final log = readGuideChangeLog(raw);
  final mark =
      int.tryParse(await Prefs.getStringF(keyGuideOfflineChange, '')) ?? 0;
  final stamps = await Offline.readStamps();
  final latest = <int, GuideMediaStamp>{};
  for (final change in log.changes) {
    if (change.index < mark || change.index >= log.count) continue;
    latest[change.plantId] = change.stamp;
  }
  for (final entry in latest.entries) {
    if (stamps.containsKey(entry.key)) continue;
    final disk = await Offline.stampFromDisk(entry.value);
    if (disk.files.isEmpty) continue;
    final diff = guideMediaDiff(disk, entry.value);
    if (diff.isEmpty) {
      await Offline.writeStamp(entry.key, entry.value);
      stamps[entry.key] = entry.value;
    } else {
      stamps[entry.key] = disk;
    }
  }
  final update = guideOfflineUpdate(
    log: log,
    mark: mark,
    catalog: catalog,
    storedCodes: stored.asCodes,
    stamps: stamps,
  );
  if (!update.hasWork && update.resumeMark > update.mark) {
    await Prefs.setString(keyGuideOfflineChange, '${update.resumeMark}');
  }
  return update;
}

Future<GuideOfflineHold> loadGuideOfflineHold() async {
  final packs = await Prefs.getStringF(keyGuideOfflinePacks, '');
  final classic = await Prefs.getBoolF(keyOffline, false);
  final stored = guideOfflineStoredFrom(packs, classic: classic);
  final total =
      int.tryParse(await Prefs.getStringF(keyGuideOfflineTotal, '')) ?? 0;
  final storedPlants =
      int.tryParse(await Prefs.getStringF(keyGuideOfflineStoredPlants, '')) ??
          0;
  final plants = stored.everything
      ? (storedPlants > 0 ? storedPlants : total)
      : storedPlants;
  final regions = stored.regions.toList()..sort();
  var updateBytes = 0;
  var updatePlants = 0;
  if (!stored.isEmpty) {
    try {
      final snapshot =
          await headersV3Reference.get().timeout(_guideOfflineWait);
      final catalog = readGuideOfflineCatalog(snapshot.value);
      final update = await loadGuideOfflineUpdate(catalog, stored);
      updateBytes = update.bytes;
      updatePlants = update.plants.length;
    } catch (error) {
      debugPrint('catalog changes: $error');
    }
  }
  return GuideOfflineHold(
    canDownload: Purchases.hasFieldGuide() || Purchases.isOffline(),
    everything: stored.everything,
    storedPlants: plants,
    totalPlants: total,
    regionIds: regions,
    updateBytes: updateBytes,
    updatePlants: updatePlants,
  );
}

enum GuideOfflineStart { started, needsWifi, skipped }

/// Starts the picture download for the whole book or for the regions in
/// [request]. A plant that already belongs to a stored pack is not fetched
/// again. Wi-Fi is required, and the pack is remembered only when the
/// download finishes.
Future<GuideOfflineStart> startGuideOfflineDownload({
  required GuideOfflineRequest request,
  required GuideOfflineCatalog catalog,
  required void Function(int done, int total) onProgress,
  required void Function() onFinished,
  required void Function() onFailed,
  Future<List<ConnectivityResult>> Function()? connectivity,
  GuideOfflineStored? stored,
  Set<int>? done,
  void Function(GuideOfflineJobPlan plan)? run,
}) async {
  if (request.added <= 0) return GuideOfflineStart.skipped;
  final storedState = stored ??
      guideOfflineStoredFrom(
        await Prefs.getStringF(keyGuideOfflinePacks, ''),
        classic: await Prefs.getBoolF(keyOffline, false),
      );
  final doneIds =
      done ?? offlineDoneParse(await Prefs.getStringF(keyGuideOfflineDone, ''));
  final plan = guideOfflinePlan(
    catalog: catalog,
    requestCodes: request.everything ? null : request.regions,
    storedCodes: storedState.asCodes,
    done: doneIds,
  );
  if (plan.total == 0) return GuideOfflineStart.skipped;
  if (plan.pending.isEmpty) {
    await _savePack(storedState, request, catalog);
    onFinished();
    return GuideOfflineStart.started;
  }
  final result = await (connectivity ?? Connectivity().checkConnectivity)();
  if (!result.contains(ConnectivityResult.wifi)) {
    return GuideOfflineStart.needsWifi;
  }
  // After the Wi-Fi check, so a refused start does not unpause an older job.
  final generation = Offline.claimDownload();
  final starter = run ??
      (GuideOfflineJobPlan plan) {
        Offline.downloadPack(
          plantIds: plan.pending,
          alreadyDone: plan.alreadyDone,
          total: plan.total,
          generation: generation,
          onPlant: (done, total) {
            if (!Offline.ownsDownload(generation)) return;
            onProgress(done, total);
          },
          onFinish: () {
            if (!Offline.ownsDownload(generation)) return;
            _savePack(storedState, request, catalog, generation: generation)
                .then((_) {
              if (!Offline.ownsDownload(generation)) return;
              onFinished();
            }).catchError((Object _) {
              if (Offline.ownsDownload(generation)) onFailed();
            });
          },
          onFail: () {
            if (!Offline.ownsDownload(generation)) return;
            onFailed();
          },
        );
      };
  starter(plan);
  return GuideOfflineStart.started;
}

/// Downloads one folded update. Wi-Fi is required. The mark moves forward
/// only when the download finishes. Pausing keeps the stamps of plants that
/// already finished, so the next open fetches the rest.
Future<GuideOfflineStart> startGuideOfflineUpdate({
  required GuideOfflineUpdate update,
  required void Function(int doneBytes, int totalBytes) onProgress,
  required void Function() onFinished,
  required void Function() onFailed,
  Future<List<ConnectivityResult>> Function()? connectivity,
  void Function()? run,
}) async {
  if (!update.hasWork) return GuideOfflineStart.skipped;
  final result = await (connectivity ?? Connectivity().checkConnectivity)();
  if (!result.contains(ConnectivityResult.wifi)) {
    return GuideOfflineStart.needsWifi;
  }
  final generation = Offline.claimDownload();
  final starter = run ??
      () {
        Offline.downloadChanges(
          plants: update.plants,
          generation: generation,
          onProgress: (done, total) {
            if (!Offline.ownsDownload(generation)) return;
            onProgress(done, total);
          },
          onFinish: () {
            if (!Offline.ownsDownload(generation)) return;
            Prefs.setString(keyGuideOfflineChange, '${update.resumeMark}')
                .then((_) {
              if (!Offline.ownsDownload(generation)) return;
              onFinished();
            }).catchError((Object _) {
              if (Offline.ownsDownload(generation)) onFailed();
            });
          },
          onFail: () {
            if (!Offline.ownsDownload(generation)) return;
            onFailed();
          },
        );
      };
  starter();
  return GuideOfflineStart.started;
}

Future<void> _savePack(
  GuideOfflineStored current,
  GuideOfflineRequest request,
  GuideOfflineCatalog catalog, {
  int? generation,
}) async {
  bool live() => generation == null || Offline.ownsDownload(generation);
  if (!live()) return;
  final next = guideOfflineStore(current, request);
  if (!live()) return;
  await Prefs.setString(keyGuideOfflinePacks, guideOfflinePacksValue(next));
  if (!live()) return;
  await Prefs.setBool(keyOffline, true);
  if (!live()) return;
  final plants = guideOfflineMatch(catalog, next.asCodes);
  if (!live()) return;
  await Prefs.setString(keyGuideOfflineStoredPlants, '$plants');
  if (!live()) return;
  Offline.downloadFinished = true;
}

Future<void> clearGuideOfflinePack() async {
  Offline.pauseDownload();
  await Prefs.remove(keyOffline);
  await Prefs.remove(keyGuideOfflinePacks);
  await Prefs.remove(keyGuideOfflineStoredPlants);
  Offline.onChange(false);
  await Offline.delete();
}
