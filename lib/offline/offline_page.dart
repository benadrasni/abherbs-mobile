import 'dart:async';

import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/offline/guide_offline.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

const guideOfflineEverythingKey = Key('guide-offline-all');
const guideOfflineDownloadKey = Key('guide-offline-get');
const guideOfflineRemoveKey = Key('guide-offline-remove');
const guideOfflinePauseKey = Key('guide-offline-pause');

Key guideOfflineGroupKey(String id) => Key('guide-offline-group-$id');
Key guideOfflineRegionKey(String code) => Key('guide-offline-region-$code');
const guideOfflinePhoneKey = Key('guide-offline-phone');
const guideOfflineUpdateKey = Key('guide-offline-update');

/// Offline packs: the whole book, or a floristic region. Each row is the
/// plants and the space the pictures take. The phone's region is offered first.
class GuideOfflinePage extends StatefulWidget {
  final GuideOfflineView? view;
  final Future<GuideOfflineView> Function() load;
  final GuideOfflineJob? job;
  final Future<void> Function()? onFieldGuide;
  final Future<void> Function(GuideOfflineRequest request)? onDownload;
  final Future<void> Function()? onUpdate;
  final Future<void> Function()? onRemove;
  final Future<void> Function()? onPause;

  const GuideOfflinePage({
    super.key,
    this.view,
    this.load = loadGuideOffline,
    this.job,
    this.onFieldGuide,
    this.onDownload,
    this.onUpdate,
    this.onRemove,
    this.onPause,
  });

  @override
  State<GuideOfflinePage> createState() => _GuideOfflinePageState();
}

class _GuideOfflinePageState extends State<GuideOfflinePage> {
  GuideOfflineView? _view;
  GuideOfflinePick _pick = const GuideOfflinePick();
  GuideOfflineJob? _job;
  String? _open;
  bool _loading = true;
  bool _failed = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    if (widget.view == null) Purchases.namesRevision.addListener(_onPlan);
    _job = widget.job;
    final ready = widget.view;
    if (ready != null) {
      _view = ready;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    if (widget.view == null) Purchases.namesRevision.removeListener(_onPlan);
    super.dispose();
  }

  void _onPlan() => _applyDownloadRight();

  @override
  void didUpdateWidget(GuideOfflinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.job != oldWidget.job && _job == oldWidget.job) {
      _job = widget.job;
    }
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    try {
      final view = await widget.load();
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _view = view;
        _loading = false;
        _failed = false;
      });
    } catch (error) {
      debugPrint('guide offline: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _loading = false;
        _failed = _view == null;
      });
    }
  }

  Future<void> _download(GuideOfflineRequest request) async {
    if (request.added <= 0) return;
    final custom = widget.onDownload;
    if (custom != null) {
      await custom(request);
      return;
    }
    final view = _view;
    if (view == null) return;
    final size = GuideOfflineSize.of(request.added);
    var finished = false;
    final started = await startGuideOfflineDownload(
      request: request,
      catalog: view.catalog,
      onProgress: (done, total) {
        if (!mounted || total <= 0) return;
        setState(() {
          _job = GuideOfflineJob(
            title: request.title,
            plants: request.added,
            doneMb: (size.barMb * done / total).round(),
            totalMb: size.barMb,
          );
        });
      },
      onFinished: () {
        finished = true;
        _logPack(request, 'ok');
        if (!mounted) return;
        setState(() {
          _job = null;
          _pick = const GuideOfflinePick();
          final current = _view;
          if (current != null) {
            _view = GuideOfflineView(
              catalog: current.catalog,
              canDownload: true,
              stored: guideOfflineStore(current.stored, request),
              phoneRegionId: current.phoneRegionId,
              update: current.update,
            );
          }
        });
      },
      onFailed: () {
        _logPack(request, 'fail');
        if (!mounted) return;
        setState(() => _job = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).offline_download_fail)),
        );
      },
    );
    if (!mounted || finished) return;
    if (started == GuideOfflineStart.needsWifi) {
      _logPack(request, 'wifi');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_offline_wifi)),
      );
      return;
    }
    if (started == GuideOfflineStart.started && _job == null) {
      setState(() {
        _job = GuideOfflineJob(
          title: request.title,
          plants: request.added,
          doneMb: 0,
          totalMb: size.barMb,
        );
      });
    }
  }

  void _logPack(GuideOfflineRequest request, String result) {
    unawaited(GuideAnalytics.offlinePack(
      scope: guideAnalyticsOfflineScope(
        everything: request.everything,
        regions: request.regions.length,
      ),
      result: result,
    ));
  }

  Future<void> _pause() async {
    final custom = widget.onPause;
    if (custom != null) {
      await custom();
      return;
    }
    Offline.pauseDownload();
    if (mounted) setState(() => _job = null);
  }

  /// The sales page has closed. Unlock Download when the phone now owns a
  /// plan. The download itself waits for another tap.
  void _applyDownloadRight() {
    final view = _view;
    if (!mounted || view == null) return;
    final allowed = Purchases.hasFieldGuide() || Purchases.isOffline();
    if (allowed == view.canDownload) return;
    setState(() {
      _view = GuideOfflineView(
        catalog: view.catalog,
        canDownload: allowed,
        stored: view.stored,
        phoneRegionId: view.phoneRegionId,
        update: view.update,
      );
    });
  }

  Future<void> _remove() async {
    final custom = widget.onRemove;
    if (custom != null) {
      await custom();
      return;
    }
    final strings = S.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.guide_offline_title),
        content: Text(strings.offline_delete_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.yes),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await clearGuideOfflinePack();
    if (!mounted) return;
    setState(() {
      _job = null;
      final view = _view;
      if (view == null) return;
      _view = GuideOfflineView(
        catalog: view.catalog,
        canDownload: view.canDownload,
        stored: const GuideOfflineStored(),
        phoneRegionId: view.phoneRegionId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      child: Scaffold(
        body: guideWithRail(
          context,
          personOn: true,
          child: SafeArea(
            child: GuideReadable(child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuideBackButton(label: strings.guide_offline_back),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.moss,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final view = _view;
    if (_failed || view == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuideBackButton(label: strings.guide_offline_back),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.guide_offline_failed,
                    style: TextStyle(color: colors.ink2),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _failed = false;
                      });
                      unawaited(_load());
                    },
                    child: Text(strings.guide_results_retry),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return _content(context, view);
  }

  Widget _content(BuildContext context, GuideOfflineView view) {
    final strings = S.of(context);
    final colors = GuideColors.of(context);
    final storedCodes = view.stored.asCodes;
    final selected = _pick.asCodes;
    final haveCount = guideOfflineMatch(view.catalog, storedCodes);
    final added = guideOfflineMatch(
          view.catalog,
          guideOfflineUnion(storedCodes, selected),
        ) -
        haveCount;
    final job = _job;
    final phone = view.phoneRegionId;
    final showPhone = phone != null && !view.stored.covers(phone);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              GuideBackButton(label: strings.guide_offline_back),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.guide_person_field_guide.toUpperCase(),
                      style: GuideType.eyebrow(colors),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.guide_offline_title,
                      style: GuideType.question(colors),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.guide_offline_intro,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!view.canDownload) _Upsell(onPressed: widget.onFieldGuide),
              if (job != null)
                _JobCard(
                  job: job,
                  plants: _count(context, job.plants),
                  onPause: _pause,
                ),
              if (haveCount > 0)
                _KeptCard(
                  title: _label(context, guideOfflineLabel(storedCodes)),
                  detail: strings.guide_offline_kept(
                    _label(context, guideOfflineLabel(storedCodes)),
                    _count(context, haveCount),
                    _size(context, haveCount),
                  ),
                  onRemove: _remove,
                ),
              if (view.update.hasWork && job == null)
                _UpdateCard(
                  detail: strings.guide_offline_add(
                    _count(context, view.update.plants.length),
                    _byteSize(context, view.update.bytes),
                  ),
                  label: view.canDownload
                      ? strings.guide_offline_update
                      : strings.guide_person_field_guide,
                  onPressed: () => _onUpdate(context, view),
                ),
              _Pack(
                key: guideOfflineEverythingKey,
                on: _pick.everything,
                title: strings.guide_offline_everything,
                meta: _count(context, view.catalog.total),
                size: view.stored.everything
                    ? strings.guide_offline_on_phone
                    : _size(context, view.catalog.total),
                onPressed: () =>
                    setState(() => _pick = _pick.toggleEverything()),
              ),
              if (showPhone) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 6),
                  child: Text(
                    strings.guide_offline_where.toUpperCase(),
                    style: GuideType.eyebrow(colors),
                  ),
                ),
                _Pack(
                  key: guideOfflinePhoneKey,
                  on: _pick.regionOn(phone),
                  title: getFilterDistributionValue(context, phone),
                  meta: _count(
                    context,
                    guideOfflineMatch(view.catalog, {phone}),
                  ),
                  size: _size(
                    context,
                    guideOfflineMatch(view.catalog, {phone}),
                  ),
                  icon: Icons.place,
                  onPressed: () =>
                      setState(() => _pick = _pick.toggleRegion(phone)),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 2, 20, 8),
                  child: Text(
                    strings.guide_offline_phone_note(
                      _size(
                        context,
                        guideOfflineMatch(view.catalog, {phone}),
                      ),
                      _size(context, view.catalog.total),
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: colors.ink3,
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 4),
                child: Text(
                  strings.guide_offline_or_part.toUpperCase(),
                  style: GuideType.eyebrow(colors),
                ),
              ),
              for (final group in guideOfflineGroups)
                _Group(
                  group: group,
                  catalog: view.catalog,
                  pick: _pick,
                  stored: view.stored,
                  phone: phone,
                  open: _open == group.id,
                  name: _groupName(strings, group.id),
                  onToggle: () => setState(
                    () => _pick = _pick.toggleGroup(group.codes),
                  ),
                  onOpen: () => setState(
                    () => _open = _open == group.id ? null : group.id,
                  ),
                  onRegion: (code) => setState(
                    () => _pick = _pick.toggleRegion(code),
                  ),
                ),
            ],
          ),
        ),
        _Bar(
          view: view,
          pick: _pick,
          added: added,
          haveCount: haveCount,
          busy: job != null,
          onPressed: () => _onGet(context, view, added),
        ),
      ],
    );
  }

  Future<void> _onGet(
    BuildContext context,
    GuideOfflineView view,
    int added,
  ) async {
    if (!_pick.chosen || added <= 0) return;
    if (!view.canDownload) {
      await widget.onFieldGuide?.call();
      _applyDownloadRight();
      return;
    }
    final codes = _pick.asCodes;
    await _download(GuideOfflineRequest(
      everything: _pick.everything,
      regions: _pick.everything ? const {} : _pick.regions,
      added: added,
      title: _label(context, guideOfflineLabel(codes)),
    ));
  }

  Future<void> _onUpdate(BuildContext context, GuideOfflineView view) async {
    final update = view.update;
    if (!update.hasWork || _job != null) return;
    if (!view.canDownload) {
      await widget.onFieldGuide?.call();
      _applyDownloadRight();
      return;
    }
    final custom = widget.onUpdate;
    if (custom != null) {
      await custom();
      return;
    }
    final title = S.of(context).guide_offline_update;
    var finished = false;
    final started = await startGuideOfflineUpdate(
      update: update,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _job = GuideOfflineJob(
            title: title,
            plants: update.plants.length,
            doneMb: _mb(done),
            totalMb: _mb(total),
            doneText: _progressMb(done),
            totalText: _progressMb(total),
          );
        });
      },
      onFinished: () {
        finished = true;
        unawaited(GuideAnalytics.offlinePack(
          scope: guideAnalyticsOfflineScope(
            everything: false,
            regions: 0,
            update: true,
          ),
          result: 'ok',
        ));
        if (!mounted) return;
        setState(() => _job = null);
        _load();
      },
      onFailed: () {
        unawaited(GuideAnalytics.offlinePack(
          scope: guideAnalyticsOfflineScope(
            everything: false,
            regions: 0,
            update: true,
          ),
          result: 'fail',
        ));
        if (!mounted) return;
        setState(() => _job = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).offline_download_fail)),
        );
      },
    );
    if (!mounted || finished) return;
    if (started == GuideOfflineStart.needsWifi) {
      unawaited(GuideAnalytics.offlinePack(
        scope: guideAnalyticsOfflineScope(
          everything: false,
          regions: 0,
          update: true,
        ),
        result: 'wifi',
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_offline_wifi)),
      );
      return;
    }
    if (started == GuideOfflineStart.started && _job == null) {
      setState(() {
        _job = GuideOfflineJob(
          title: title,
          plants: update.plants.length,
          doneMb: 0,
          totalMb: _mb(update.bytes),
          doneText: _progressMb(0),
          totalText: _progressMb(update.bytes),
        );
      });
    }
  }
}

String _count(BuildContext context, int count) {
  return guidePlantPhrase(context, count);
}

int _mb(int bytes) {
  if (bytes <= 0) return 0;
  final mb = bytes / 1000000;
  if (mb < 1) return 1;
  return mb.round();
}

/// Megabytes for the progress line, which always says MB. The update card
/// uses [GuideOfflineBytes], so a large update can still read as gigabytes.
String _progressMb(int bytes) {
  if (bytes <= 0) return '0';
  final mb = bytes / 1000000;
  if (mb >= 1) return '${mb.round()}';
  final tenths = (mb * 10).round();
  final shown = tenths <= 0 ? 1 : tenths;
  return (shown / 10).toStringAsFixed(1);
}

String _byteSize(BuildContext context, int bytes) {
  final strings = S.of(context);
  final size = GuideOfflineBytes.of(bytes);
  return size.gigabytes
      ? strings.guide_offline_about_gb(size.amount)
      : strings.guide_offline_about_mb(size.amount);
}

String _size(BuildContext context, int plants) {
  final strings = S.of(context);
  if (plants == 0) {
    return strings.guide_offline_about_mb('0');
  }
  final size = GuideOfflineSize.of(plants);
  final amount = size.gigabytes
      ? size.amount
      : NumberFormat.decimalPattern(
          Localizations.localeOf(context).toString(),
        ).format(int.parse(size.amount));
  return size.gigabytes
      ? strings.guide_offline_about_gb(amount)
      : strings.guide_offline_about_mb(amount);
}

String _label(BuildContext context, GuideOfflineLabel label) {
  final strings = S.of(context);
  if (label.everything) return strings.guide_offline_everything;
  final region = label.regionId;
  if (region != null) return getFilterDistributionValue(context, region);
  final group = label.groupId;
  if (group != null) return _groupName(strings, group);
  return strings.guide_offline_regions(label.count);
}

String _groupName(S strings, String id) {
  switch (id) {
    case '1':
      return strings.europe;
    case '2':
      return strings.africa;
    case '3':
      return strings.asia_temperate;
    case '4':
      return strings.asia_tropical;
    case '5':
      return strings.australasia;
    case '6':
      return strings.pacific;
    case '7':
      return strings.northern_america;
    case '8':
      return strings.southern_america;
    default:
      return '';
  }
}

String guideOfflineMenuText(BuildContext context, GuideOfflineHold? hold) {
  final strings = S.of(context);
  switch (guideOfflineMenuKind(hold)) {
    case GuideOfflineMenuKind.legacy:
      return '';
    case GuideOfflineMenuKind.upsell:
      return strings.guide_offline_menu_upsell(_menuSize(context, hold));
    case GuideOfflineMenuKind.empty:
      return strings.guide_offline_menu_empty(_menuSize(context, hold));
    case GuideOfflineMenuKind.book:
      final plants = hold?.storedPlants ?? 0;
      final total = hold?.totalPlants ?? 0;
      final count = plants > 0 ? plants : total;
      if (count <= 0) {
        return _withUpdate(context, strings.guide_person_offline_on, hold);
      }
      return _withUpdate(
        context,
        strings.guide_offline_menu_book(_size(context, count)),
        hold,
      );
    case GuideOfflineMenuKind.stored:
      final current = hold;
      if (current == null) return strings.guide_person_offline_on;
      final title = current.regionIds.length == 1
          ? getFilterDistributionValue(context, current.regionIds.first)
          : _label(
              context,
              guideOfflineLabel(current.regionIds.toSet()),
            );
      final count = current.storedPlants;
      if (count <= 0) return _withUpdate(context, title, hold);
      return _withUpdate(
        context,
        strings.guide_offline_menu_stored(title, _size(context, count)),
        hold,
      );
  }
}

String _withUpdate(BuildContext context, String line, GuideOfflineHold? hold) {
  if (hold == null || hold.updatePlants <= 0) return line;
  final strings = S.of(context);
  final size = _byteSize(context, hold.updateBytes);
  if (line.isEmpty) return strings.guide_offline_update_size(size);
  return strings.guide_offline_menu_update(line, size);
}

String _menuSize(BuildContext context, GuideOfflineHold? hold) {
  final total = hold?.totalPlants ?? 0;
  if (total <= 0) return S.of(context).guide_offline_about_book;
  return _size(context, total);
}

class _Upsell extends StatelessWidget {
  final Future<void> Function()? onPressed;

  const _Upsell({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.guide_offline_upsell_title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                strings.guide_offline_upsell_body,
                style: TextStyle(color: colors.ink2, height: 1.35),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onPressed == null ? null : () => onPressed!(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.moss,
                  backgroundColor: colors.mossFill,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  strings.guide_offline_see,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final GuideOfflineJob job;
  final String plants;
  final Future<void> Function() onPause;

  const _JobCard({
    required this.job,
    required this.plants,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.guide_offline_downloading(job.title),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    key: guideOfflinePauseKey,
                    onPressed: onPause,
                    style: TextButton.styleFrom(foregroundColor: colors.moss),
                    child: Text(
                      strings.guide_offline_pause,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Text(
                strings.guide_offline_progress(
                  job.doneText ?? '${job.doneMb}',
                  job.totalText ?? '${job.totalMb}',
                  plants,
                ),
                style: TextStyle(fontSize: 13, color: colors.ink3),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: job.fraction,
                  minHeight: 8,
                  backgroundColor: colors.paper2,
                  color: colors.mossFill,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.guide_offline_progress_note,
                style: TextStyle(fontSize: 13, color: colors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeptCard extends StatelessWidget {
  final String title;
  final String detail;
  final Future<void> Function() onRemove;

  const _KeptCard({
    required this.title,
    required this.detail,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.guide_offline_on_phone,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.contains(title) ? detail : '$title · $detail',
                      style: TextStyle(fontSize: 13, color: colors.ink3),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: guideOfflineRemoveKey,
                onPressed: onRemove,
                style: TextButton.styleFrom(foregroundColor: colors.madder),
                child: Text(
                  strings.guide_offline_remove,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  final String detail;
  final String label;
  final Future<void> Function() onPressed;

  const _UpdateCard({
    required this.detail,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.guide_offline_update,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(fontSize: 13, color: colors.ink3),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: guideOfflineUpdateKey,
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: colors.mossFill,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pack extends StatelessWidget {
  final bool on;
  final String title;
  final String meta;
  final String size;
  final IconData? icon;
  final VoidCallback onPressed;

  const _Pack({
    super.key,
    required this.on,
    required this.title,
    required this.meta,
    required this.size,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: colors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: on ? colors.moss : colors.rule,
            width: on ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Box(on: on),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontFamily: GuideType.serif,
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            height: 1.15,
                            color: colors.ink,
                          ),
                          children: [
                            if (icon != null)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 4,
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 16,
                                    color: colors.moss,
                                  ),
                                ),
                              ),
                            TextSpan(text: title),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        style: TextStyle(fontSize: 13, color: colors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  size,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _Group extends StatelessWidget {
  final GuideOfflineGroup group;
  final GuideOfflineCatalog catalog;
  final GuideOfflinePick pick;
  final GuideOfflineStored stored;
  final String? phone;
  final bool open;
  final String name;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final ValueChanged<String> onRegion;

  const _Group({
    required this.group,
    required this.catalog,
    required this.pick,
    required this.stored,
    required this.phone,
    required this.open,
    required this.name,
    required this.onToggle,
    required this.onOpen,
    required this.onRegion,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final codes = group.codes.toSet();
    final count = guideOfflineMatch(catalog, codes);
    final on = pick.groupOn(group.codes);
    final mid = pick.groupMid(group.codes);
    final overlap = open ? guideOfflineOverlap(catalog, group.codes) : null;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.rule)),
          ),
          child: Row(
            children: [
              IconButton(
                key: guideOfflineGroupKey(group.id),
                onPressed: onToggle,
                tooltip: name,
                icon: _Box(on: on, mid: mid),
              ),
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _size(context, count),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: colors.ink,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              _count(context, count),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.ink3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          open ? Icons.expand_more : Icons.chevron_right,
                          color: colors.ink3,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (open)
          for (final code in group.codes)
            _RegionRow(
              code: code,
              catalog: catalog,
              on: pick.regionOn(code),
              stored: _storedRow(stored, code, catalog),
              here: code == phone,
              onPressed: () => onRegion(code),
            ),
        if (open && overlap != null)
          _Overlap(code: overlap, groupCount: count, catalog: catalog),
      ],
    );
  }
}

bool _storedRow(
  GuideOfflineStored stored,
  String code,
  GuideOfflineCatalog catalog,
) {
  if (stored.isEmpty) return false;
  if (stored.covers(code)) return true;
  final have = guideOfflineMatch(catalog, stored.asCodes);
  if (have <= 0) return false;
  final withCode = guideOfflineMatch(
    catalog,
    guideOfflineUnion(stored.asCodes, {code}),
  );
  return withCode == have;
}

class _RegionRow extends StatelessWidget {
  final String code;
  final GuideOfflineCatalog catalog;
  final bool on;
  final bool stored;
  final bool here;
  final VoidCallback onPressed;

  const _RegionRow({
    required this.code,
    required this.catalog,
    required this.on,
    required this.stored,
    required this.here,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final count = guideOfflineMatch(catalog, {code});
    return InkWell(
      key: guideOfflineRegionKey(code),
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.cream.withValues(alpha: 0.7),
            colors.paper,
          ),
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(36, 10, 16, 10),
          child: Row(
            children: [
              _Box(on: on),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getFilterDistributionValue(context, code),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (here || stored)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          here
                              ? strings.guide_offline_this_phone
                              : strings.guide_offline_on_phone,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: colors.moss,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _size(context, count),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _count(context, count),
                    style: TextStyle(fontSize: 12, color: colors.ink3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Overlap extends StatelessWidget {
  final String code;
  final int groupCount;
  final GuideOfflineCatalog catalog;

  const _Overlap({
    required this.code,
    required this.groupCount,
    required this.catalog,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final one = guideOfflineMatch(catalog, {code});
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(36, 8, 20, 10),
        child: Text(
          S.of(context).guide_offline_overlap(
                getFilterDistributionValue(context, code),
                _count(context, one),
                _count(context, groupCount),
                _size(context, one),
              ),
          style: TextStyle(fontSize: 13, height: 1.4, color: colors.ink2),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final GuideOfflineView view;
  final GuideOfflinePick pick;
  final int added;
  final int haveCount;
  final bool busy;
  final VoidCallback onPressed;

  const _Bar({
    required this.view,
    required this.pick,
    required this.added,
    required this.haveCount,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final ready = pick.chosen && added > 0 && !busy;
    final title = pick.chosen
        ? _label(context, guideOfflineLabel(pick.asCodes))
        : strings.guide_offline_choose;
    final String meta;
    if (!pick.chosen) {
      meta = strings.guide_offline_choose_note;
    } else if (added <= 0) {
      meta = strings.guide_offline_already;
    } else if (!view.canDownload) {
      meta = strings.guide_offline_add_guide(
        _count(context, added),
        _size(context, added),
      );
    } else if (haveCount > 0) {
      meta = strings.guide_offline_add_kept(
        _count(context, added),
        _size(context, added),
        _size(context, haveCount),
      );
    } else {
      meta = strings.guide_offline_add(
        _count(context, added),
        _size(context, added),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: colors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            if (!busy) ...[
              const SizedBox(width: 12),
              Opacity(
                opacity: ready ? 1 : 0.45,
                child: TextButton(
                  key: guideOfflineDownloadKey,
                  onPressed: ready ? onPressed : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: colors.mossFill,
                    disabledBackgroundColor: colors.mossFill,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    view.canDownload
                        ? strings.guide_offline_download
                        : strings.guide_person_field_guide,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final bool on;
  final bool mid;

  const _Box({required this.on, this.mid = false});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final filled = on;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? colors.mossFill : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: filled || mid ? colors.moss : colors.ink3,
          width: 1.5,
        ),
      ),
      child: SizedBox(
        width: 22,
        height: 22,
        child: filled
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : mid
                ? Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.moss,
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: const SizedBox(width: 10, height: 2),
                    ),
                  )
                : null,
      ),
    );
  }
}
