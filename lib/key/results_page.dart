import 'dart:async';

import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/key/habitat_page.dart';
import 'package:abherbs_flutter/key/petal_page.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:abherbs_flutter/shell/review_prompt.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// A family or genus, on the same page as the key's result list.
/// The future completes when that page is closed.
Future<void> openGuideTaxonList(
  BuildContext context, {
  required String listPath,
  required String backLabel,
  String? title,
  required void Function(BuildContext context, String name) onOpenPlant,
  required Future<void> Function(BuildContext context) onTryPhoto,
}) {
  final latin = guideListLatin(listPath);
  final given = title?.trim() ?? '';
  final language = Localizations.localeOf(context).languageCode;
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideListRouteName),
      builder: (context) => GuideResultsPage(
        colorId: '',
        habitatId: null,
        petalId: '',
        listTitle: given.isEmpty ? latin : given,
        listBackLabel: backLabel,
        listLatin: latin.isEmpty ? null : latin,
        loadListTitle:
            given.isEmpty ? () => loadGuideTaxonTitle(latin, language) : null,
        loadResults: (_) => loadGuideListedPlants(
          rootReference.child(listPath),
          language,
        ),
        loadPrefs: () async => const GuideResultPrefs(),
        savePrefs: (_) async {},
        loadSeen: loadGuideSeenNames,
        loadRegionCounts: () async => const {},
        locate: () async => null,
        onOpenPlant: onOpenPlant,
        onTryPhoto: onTryPhoto,
      ),
    ),
  );
}

Future<void> guideOpenLocationSettings() async {
  await openAppSettings();
}

class GuideResultsPage extends StatefulWidget {
  final String colorId;
  final String? habitatId;
  final String petalId;
  final List<GuideResultPlant>? initialPlants;
  final GuideResultPrefs? initialPrefs;
  final Set<String>? initialSeen;
  final Map<String, int>? initialRegionCounts;
  final bool? showAd;
  final WidgetBuilder? adBuilder;
  final int? month;
  final Future<List<GuideResultPlant>> Function(String? regionId) loadResults;
  final Future<GuideResultPrefs> Function() loadPrefs;
  final Future<void> Function(GuideResultPrefs prefs) savePrefs;
  final Future<Set<String>> Function() loadSeen;
  final Future<Map<String, int>> Function() loadRegionCounts;
  final Future<String?> Function() locate;
  final Future<void> Function() openLocationSettings;
  final void Function(BuildContext context, String name) onOpenPlant;
  final Future<void> Function(BuildContext context) onTryPhoto;

  /// Set for a family or genus. The key's pills, region, and wild chip stay off.
  final String? listTitle;
  final String? listBackLabel;
  final String? listLatin;
  final String? listEmpty;
  final Future<String?> Function()? loadListTitle;

  const GuideResultsPage({
    super.key,
    required this.colorId,
    required this.habitatId,
    required this.petalId,
    required this.loadResults,
    required this.loadPrefs,
    required this.savePrefs,
    required this.loadSeen,
    required this.loadRegionCounts,
    required this.locate,
    required this.onOpenPlant,
    required this.onTryPhoto,
    this.openLocationSettings = guideOpenLocationSettings,
    this.initialPlants,
    this.initialPrefs,
    this.initialSeen,
    this.initialRegionCounts,
    this.showAd,
    this.adBuilder,
    this.month,
    this.listTitle,
    this.listBackLabel,
    this.listLatin,
    this.listEmpty,
    this.loadListTitle,
  });

  @override
  State<GuideResultsPage> createState() => _GuideResultsPageState();
}

class _GuideResultsPageState extends State<GuideResultsPage> {
  GuideResultPrefs _prefs = const GuideResultPrefs();
  List<GuideResultPlant>? _plants;
  Set<String> _seen = {};
  Map<String, int> _regionCounts = {};
  bool _plates = false;
  bool _loading = false;
  bool _failed = false;
  bool _prefsReady = false;
  bool _reviewNoted = false;
  int _ticket = 0;
  String? _listTitle;

  bool get _isList => widget.listTitle != null;

  @override
  void initState() {
    super.initState();
    Purchases.namesRevision.addListener(_onPlan);
    _listTitle = widget.listTitle;
    final plants = widget.initialPlants;
    final prefs = widget.initialPrefs;
    if (plants != null && prefs != null) {
      _plants = plants;
      _prefs = prefs;
      _seen = widget.initialSeen ?? {};
      _regionCounts = widget.initialRegionCounts ?? {};
      _prefsReady = true;
      _noteKeySuccess(plants);
    } else {
      _load();
    }
    _refineTitle();
  }

  @override
  void dispose() {
    Purchases.namesRevision.removeListener(_onPlan);
    super.dispose();
  }

  void _onPlan() {
    if (mounted) setState(() {});
  }

  void _refineTitle() {
    final load = widget.loadListTitle;
    if (load == null) return;
    load().then((name) {
      if (!mounted || name == null) return;
      final shown = name.trim();
      if (shown.isEmpty || shown == _listTitle) return;
      setState(() => _listTitle = shown);
    });
  }

  /// Family, genus, and editorial lists stay clear. The key's result list
  /// keeps one banner after the third row, or at the end when the list is
  /// shorter than that.
  bool get _showAd => !_isList && (widget.showAd ?? Purchases.showsAds());

  int get _month => widget.month ?? DateTime.now().month;

  bool _reviewStillHere() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return route?.isCurrent ?? false;
  }

  /// The key's list is on screen. A family or genus list is not a finished key.
  void _noteKeySuccess(List<GuideResultPlant> plants, {bool? wildOnly}) {
    if (_reviewNoted || _isList) return;
    final shown = arrangeGuideResults(
      plants,
      month: _month,
      wildOnly: wildOnly ?? _prefs.wildOnly,
    );
    if (shown.plants.isEmpty) return;
    _reviewNoted = true;
    unawaited(ReviewPrompt.note(stillHere: _reviewStillHere));
  }

  GuideResultList get _arranged {
    return arrangeGuideResults(
      _plants ?? const [],
      month: _month,
      wildOnly: _isList ? false : _prefs.wildOnly,
    );
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    if (_isList) {
      if (mounted) setState(() => _prefsReady = true);
      await Future.wait([
        _loadList(null, ticket),
        _loadSeen(ticket),
      ]);
      return;
    }
    try {
      final prefs = widget.initialPrefs ?? await widget.loadPrefs();
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _prefs = prefs;
        _prefsReady = true;
      });
      await Future.wait([
        _loadList(prefs.regionId, ticket),
        _loadSeen(ticket),
        _loadCounts(ticket),
      ]);
    } catch (error) {
      debugPrint('guide results: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _prefsReady = true;
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadList(String? regionId, int ticket) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final plants = await widget.loadResults(regionId);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _plants = plants;
        _loading = false;
      });
      _noteKeySuccess(plants);
      if (!_isList) {
        final shown = arrangeGuideResults(
          plants,
          month: _month,
          wildOnly: _prefs.wildOnly,
        );
        unawaited(GuideAnalytics.filterResult(
          color: widget.colorId,
          habitat: widget.habitatId ?? '',
          petal: widget.petalId,
          count: shown.plants.length,
        ));
      }
    } catch (error) {
      debugPrint('guide results list: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _loading = false;
        _failed = _plants == null;
      });
      if (_plants != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).guide_results_failed)),
        );
      }
    }
  }

  Future<void> _loadSeen(int ticket) async {
    try {
      final seen = await widget.loadSeen();
      if (!mounted || ticket != _ticket) return;
      setState(() => _seen = seen);
    } catch (error) {
      debugPrint('guide results seen: $error');
    }
  }

  Future<void> _loadCounts(int ticket) async {
    try {
      final counts = await widget.loadRegionCounts();
      if (!mounted || ticket != _ticket) return;
      setState(() => _regionCounts = counts);
    } catch (error) {
      debugPrint('guide results regions: $error');
    }
  }

  Future<void> _reload(String? regionId) async {
    final ticket = ++_ticket;
    await _loadList(regionId, ticket);
  }

  void _remember(GuideResultPrefs prefs) {
    setState(() => _prefs = prefs);
    widget.savePrefs(prefs);
  }

  void _setRegion(String? regionId, {required bool fromLocation}) {
    _remember(_prefs.copyWith(
      regionId: regionId,
      clearRegion: regionId == null,
      fromLocation: fromLocation,
    ));
    _reload(regionId);
  }

  Future<void> _useLocation(BuildContext sheetContext) async {
    if (_prefs.locationRefused) {
      await widget.openLocationSettings();
      return;
    }
    try {
      final regionId = await widget.locate();
      if (!mounted) return;
      if (regionId == null || regionId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).guide_location_unknown)),
        );
        return;
      }
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      _remember(_prefs.copyWith(
        regionId: regionId,
        fromLocation: true,
        locationRefused: false,
      ));
      _reload(regionId);
    } on GuideLocationRefused {
      if (!mounted) return;
      _remember(_prefs.copyWith(locationRefused: true));
    } catch (error) {
      debugPrint('guide location: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_location_unknown)),
      );
    }
  }

  void _openRegions() {
    final strings = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var showAll = false;
        return GuideTheme(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final anyCount = _regionCounts[''];
              return _RegionSheet(
                title: strings.guide_region_title,
                body: anyCount == null
                    ? strings.guide_region_body_plain
                    : strings.guide_region_body(
                        guidePlantPhrase(context, anyCount),
                      ),
                locationTitle: strings.guide_use_location,
                locationBody: _prefs.locationRefused
                    ? strings.guide_location_refused
                    : strings.guide_location_kept,
                anyRegion: strings.guide_any_region,
                allRegions: strings.guide_all_regions,
                selectedId: _prefs.regionId,
                counts: _regionCounts,
                showAll: showAll,
                regionName: (id) => getFilterDistributionValue(context, id),
                groupName: (index) => _groupName(strings, index),
                onLocation: () async {
                  await _useLocation(sheetContext);
                  if (sheetContext.mounted) setSheetState(() {});
                },
                onAny: () {
                  Navigator.pop(sheetContext);
                  _setRegion(null, fromLocation: false);
                },
                onRegion: (id) {
                  Navigator.pop(sheetContext);
                  _setRegion(id, fromLocation: false);
                },
                onShowAll: () => setSheetState(() => showAll = true),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final arranged = _arranged;
    final seenCount = guideSeenInList(arranged.plants, _seen);
    final regionName = _prefs.regionId == null
        ? null
        : getFilterDistributionValue(context, _prefs.regionId);
    return GuideKeyScaffold(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isList)
                  _listHead(strings, arranged.plants.length, seenCount)
                else ...[
                  GuideBackButton(label: strings.guide_back_petals),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        GuideFilterPill(
                          label: guideCap(
                            getFilterColorValue(context, widget.colorId),
                          ),
                          leading: _ColorDot(colorId: widget.colorId),
                          onPressed: () => popGuideKeyToFind(context),
                        ),
                        if (widget.habitatId != null)
                          GuideFilterPill(
                            label: guideCap(
                              guideHabitatName(strings, widget.habitatId!),
                            ),
                            onPressed: () => popGuideKeyToHabitat(context),
                          ),
                        if (widget.petalId.isNotEmpty)
                          GuideFilterPill(
                            label:
                                guidePetalTrailLabel(strings, widget.petalId),
                            onPressed: () => Navigator.maybePop(context),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_prefsReady)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _CountLine(
                        count: arranged.plants.length,
                        caption: _caption(
                          strings,
                          arranged.plants.length,
                          regionName,
                          seenCount,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (_prefsReady && !_isList)
            SliverPersistentHeader(
              pinned: true,
              delegate: _FilterBarDelegate(
                child: _FilterBar(
                  region: regionName ?? strings.guide_any_region,
                  regionSet: _prefs.regionId != null,
                  fromLocation: _prefs.fromLocation,
                  wildOnly: _prefs.wildOnly,
                  wildLabel: _prefs.wildOnly
                      ? strings.guide_wild_only
                      : strings.guide_wild_and_garden,
                  onRegion: _openRegions,
                  onWild: () {
                    final next = _prefs.copyWith(wildOnly: !_prefs.wildOnly);
                    _remember(next);
                    final plants = _plants;
                    if (plants != null) {
                      _noteKeySuccess(plants, wildOnly: next.wildOnly);
                    }
                  },
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_plants == null && _loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: colors.moss,
                      ),
                    ),
                  )
                else if (_plants == null && _failed)
                  _Retry(onRetry: _load)
                else if (_plants != null &&
                    _plants!.isEmpty &&
                    widget.listEmpty != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(
                      widget.listEmpty!,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: colors.ink2,
                      ),
                    ),
                  )
                else
                  ..._grid(strings, arranged),
                if (_plants != null) _footer(strings),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHead(S strings, int count, int seenCount) {
    final colors = GuideColors.of(context);
    final title = _listTitle ?? widget.listTitle ?? '';
    final latin = widget.listLatin;
    final showLatin = latin != null &&
        latin.isNotEmpty &&
        latin.toLowerCase() != title.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GuideBackButton(
          label: widget.listBackLabel ?? strings.guide_back,
        ),
        GuideFoldLeading(
          child: (context) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: GuideType.serif,
                    fontWeight: FontWeight.w500,
                    fontSize: 28,
                    height: 1.1,
                    color: colors.ink,
                  ),
                ),
                if (showLatin)
                  Text(
                    latin,
                    style: GuideType.latin(colors).copyWith(
                      fontSize: 15,
                      height: 1.3,
                      color: colors.ink3,
                    ),
                  ),
                if (_prefsReady) ...[
                  const SizedBox(height: 10),
                  _CountLine(
                    count: count,
                    caption: _caption(strings, count, null, seenCount),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _caption(
    S strings,
    int plantCount,
    String? regionName,
    int seenCount,
  ) {
    final plants = regionName == null || regionName.isEmpty
        ? strings.guide_results_plants(plantCount)
        : strings.guide_results_plants_in(plantCount, regionName);
    if (seenCount <= 0) return plants;
    return strings.guide_results_seen_suffix(plants, seenCount);
  }

  List<Widget> _grid(S strings, GuideResultList arranged) {
    final window = GuideWindow.of(context);
    final size = MediaQuery.sizeOf(context);
    // Open iPhone Duo landscape is a tablet at about 951 points, short of
    // the 1000-point wide bar. The grid still uses four columns, the same
    // count a wide iPad uses. Portrait stays at three.
    final landscapeTablet = window.tablet && size.width > size.height;
    final columns = GuideFold.across(
      context,
      window.columns(phone: 2, tablet: landscapeTablet ? 4 : 3, wide: 4),
    );
    final slots = guideResultSlots(
      arranged,
      showAd: _showAd,
      columns: columns,
    );
    final rows = <Widget>[];
    final pending = <GuideResultPlant>[];
    void flush() {
      if (pending.isEmpty) return;
      rows.add(_row(List<GuideResultPlant>.of(pending), columns));
      pending.clear();
    }

    for (final slot in slots) {
      if (slot is GuideMonthSlot) {
        flush();
        rows.add(_monthRow(strings, slot));
      } else if (slot is GuideAdSlot) {
        flush();
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: widget.adBuilder?.call(context) ?? AppBannerAd(),
        ));
      } else if (slot is GuidePlantSlot) {
        pending.add(slot.plant);
        if (pending.length == columns) flush();
      }
    }
    flush();
    return rows;
  }

  Widget _monthRow(S strings, GuideMonthSlot slot) {
    final colors = GuideColors.of(context);
    final label = !slot.inFlower
        ? strings.guide_other_months(slot.count)
        : slot.count > 0
            ? strings.guide_in_flower_now(slot.count)
            : '';
    Widget heading() {
      return Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
          color: colors.ink3,
        ),
      );
    }

    Widget switcher() {
      return GuideViewSwitch(
        photos: strings.guide_photos,
        plates: strings.guide_plates,
        platesOn: _plates,
        onPhotos: () => setState(() => _plates = false),
        onPlates: () => setState(() => _plates = true),
      );
    }

    // The sliver insets this row by 20. The label stays on the left page
    // and the photo switch stays on the right.
    return Padding(
      padding: EdgeInsets.only(top: slot.inFlower ? 0 : 8, bottom: 6),
      child: GuideFoldSplit(
        originX: 20,
        crossAxisAlignment: CrossAxisAlignment.center,
        unsplit: Row(
          children: [
            Expanded(child: heading()),
            if (slot.controls) switcher(),
          ],
        ),
        leading: heading(),
        trailing: slot.controls
            ? Align(
                alignment: AlignmentDirectional.centerEnd,
                child: switcher(),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _row(List<GuideResultPlant> plants, int columns) {
    // The sliver already insets the row by 20.
    return GuideFoldRow(
      columns: columns,
      originX: 20,
      padding: const EdgeInsets.only(bottom: 14),
      children: [for (final plant in plants) _cell(plant)],
    );
  }

  Widget _cell(GuideResultPlant plant) {
    final colors = GuideColors.of(context);
    final seen = _seen.contains(plant.name);
    final path = _plates ? plant.platePath : plant.photoPath;
    final vernacular = distinctVernacular(plant.label, plant.name);
    return InkWell(
      onTap: () => widget.onOpenPlant(context, plant.name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: _plates ? 2 / 3 : 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GuidePhoto(
                  path: path,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  radius: 10,
                  fit: _plates ? BoxFit.contain : BoxFit.cover,
                  background: _plates ? const Color(0xFFF1E8D6) : colors.paper2,
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          Text(
            vernacular ?? plant.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: vernacular != null
                ? TextStyle(
                    fontFamily: GuideType.serif,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    height: 1.15,
                    color: colors.ink,
                  )
                : GuideType.latin(colors).copyWith(fontSize: 16, height: 1.15),
          ),
          if (vernacular != null)
            Text(
              plant.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GuideType.latin(colors).copyWith(
                fontSize: 13,
                height: 1.2,
                color: colors.ink3,
              ),
            ),
          if (seen)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                S.of(context).guide_seen_mark,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.moss,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(S strings) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: colors.ink3,
          ),
          children: [
            TextSpan(text: strings.guide_results_missing),
            const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => widget.onTryPhoto(context),
                child: Text(
                  strings.guide_search_try_photo,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: colors.moss,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _groupName(S strings, int index) {
  switch (index) {
    case 0:
      return strings.europe;
    case 1:
      return strings.africa;
    case 2:
      return strings.asia_temperate;
    case 3:
      return strings.asia_tropical;
    case 4:
      return strings.australasia;
    case 5:
      return strings.pacific;
    case 6:
      return strings.northern_america;
    case 7:
      return strings.southern_america;
    default:
      return strings.guide_region_antarctic;
  }
}

class _CountLine extends StatelessWidget {
  final int count;
  final String caption;

  const _CountLine({required this.count, required this.caption});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Text.rich(
      TextSpan(
        text: '$count',
        style: TextStyle(
          fontFamily: GuideType.serif,
          fontWeight: FontWeight.w500,
          fontSize: 30,
          letterSpacing: -0.6,
          height: 1,
          color: colors.ink,
        ),
        children: [
          TextSpan(
            text: ' $caption',
            style: TextStyle(
              fontFamily: GuideType.sans,
              fontWeight: FontWeight.w400,
              fontSize: 14,
              letterSpacing: 0,
              height: 1.3,
              color: colors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String region;
  final bool regionSet;
  final bool fromLocation;
  final bool wildOnly;
  final String wildLabel;
  final VoidCallback onRegion;
  final VoidCallback onWild;

  const _FilterBar({
    required this.region,
    required this.regionSet,
    required this.fromLocation,
    required this.wildOnly,
    required this.wildLabel,
    required this.onRegion,
    required this.onWild,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ColoredBox(
      color: colors.paper,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ChoiceChip(
                label: region,
                selected: regionSet,
                pin: fromLocation,
                chevron: true,
                onPressed: onRegion,
              ),
              const SizedBox(width: 8),
              _ChoiceChip(
                label: wildLabel,
                selected: wildOnly,
                onPressed: onWild,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool pin;
  final bool chevron;
  final VoidCallback onPressed;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.pin = false,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final foreground = selected ? Colors.white : colors.ink;
    return Material(
      color: selected ? colors.mossFill : colors.cream,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? colors.mossFill : colors.rule,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pin) ...[
                  Icon(Icons.place, size: 14, color: foreground),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (chevron) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 16, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _FilterBarDelegate({required this.child});

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_FilterBarDelegate oldDelegate) => true;
}

class _Retry extends StatelessWidget {
  final VoidCallback onRetry;

  const _Retry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(
            strings.guide_results_failed,
            style: TextStyle(color: colors.ink2),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(strings.guide_results_retry),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String colorId;

  const _ColorDot({required this.colorId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: guideSwatchColor(colorId),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
    );
  }
}

class _RegionSheet extends StatelessWidget {
  final String title;
  final String body;
  final String locationTitle;
  final String locationBody;
  final String anyRegion;
  final String allRegions;
  final String? selectedId;
  final Map<String, int> counts;
  final bool showAll;
  final String Function(String id) regionName;
  final String Function(int index) groupName;
  final VoidCallback onLocation;
  final VoidCallback onAny;
  final ValueChanged<String> onRegion;
  final VoidCallback onShowAll;

  const _RegionSheet({
    required this.title,
    required this.body,
    required this.locationTitle,
    required this.locationBody,
    required this.anyRegion,
    required this.allRegions,
    required this.selectedId,
    required this.counts,
    required this.showAll,
    required this.regionName,
    required this.groupName,
    required this.onLocation,
    required this.onAny,
    required this.onRegion,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final tablet = GuideWindow.of(context).tablet;
    final screen = MediaQuery.sizeOf(context).height;
    final height =
        tablet ? (screen * 0.88 < 680 ? screen * 0.88 : 680.0) : screen * 0.86;
    return Align(
      alignment: tablet ? Alignment.center : Alignment.bottomCenter,
      child: Padding(
        padding: tablet ? const EdgeInsets.all(32) : EdgeInsets.zero,
        child: Material(
          color: colors.paper,
          borderRadius: tablet
              ? BorderRadius.circular(22)
              : const BorderRadius.vertical(top: Radius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tablet ? 520 : double.infinity,
              maxHeight: height,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
              children: [
                if (!tablet) ...[
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.rule,
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                      ),
                      child: SizedBox(width: 40, height: 5),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: GuideType.serif,
                    fontWeight: FontWeight.w500,
                    fontSize: 23,
                    height: 1.12,
                    letterSpacing: -0.2,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.ink2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _LocationButton(
                  title: locationTitle,
                  body: locationBody,
                  onPressed: onLocation,
                ),
                _RadioRow(
                  label: anyRegion,
                  count: counts[''],
                  selected: selectedId == null,
                  onPressed: onAny,
                ),
                if (!showAll) ...[
                  for (final id in guideFeaturedRegionIds)
                    _RadioRow(
                      label: regionName(id),
                      count: counts[id],
                      selected: selectedId == id,
                      onPressed: () => onRegion(id),
                    ),
                  InkWell(
                    onTap: onShowAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Text(
                        allRegions,
                        style: TextStyle(
                          color: colors.moss,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ] else
                  for (var i = 0; i < guideRegionGroups.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 2),
                      child: Text(
                        groupName(i).toUpperCase(),
                        style: GuideType.eyebrow(colors),
                      ),
                    ),
                    for (final id in guideRegionGroups[i])
                      _RadioRow(
                        label: regionName(id),
                        count: counts[id],
                        selected: selectedId == id,
                        onPressed: () => onRegion(id),
                      ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback onPressed;

  const _LocationButton({
    required this.title,
    required this.body,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.place, color: colors.moss, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onPressed;

  const _RadioRow({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return InkWell(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.moss : colors.ink3,
                    width: selected ? 6 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              if (count != null)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.ink3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
