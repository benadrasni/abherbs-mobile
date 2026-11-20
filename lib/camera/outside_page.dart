import 'dart:io';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A name Plant.id returned that the book has not written yet.
class GuideOutsidePage extends StatefulWidget {
  final GuideCameraOutcome outcome;
  final String? photoPath;
  final DateTime when;
  final String place;

  /// From the photo's EXIF GPS. 0 and 0 means no place.
  final double latitude;
  final double longitude;
  final Future<String?> Function(GuideCameraDraft draft)? onSave;
  final Future<void> Function(String id)? onConfirm;
  final Future<void> Function(String id)? onDelete;
  final Future<void> Function(String id, String from, String to)? onRetarget;
  final void Function(String name)? onOpenSpecies;
  final VoidCallback? onSearch;

  /// Set when Seen opens a find that is already written. The page does not
  /// save it again.
  final String? observationId;

  /// A confirmed find keeps Delete and It’s another one, and hides Keep.
  final bool confirmed;

  const GuideOutsidePage({
    super.key,
    required this.outcome,
    required this.when,
    required this.place,
    this.photoPath,
    this.latitude = 0,
    this.longitude = 0,
    this.onSave,
    this.onConfirm,
    this.onDelete,
    this.onRetarget,
    this.onOpenSpecies,
    this.onSearch,
    this.observationId,
    this.confirmed = false,
  });

  @override
  State<GuideOutsidePage> createState() => _GuideOutsidePageState();
}

class _GuideOutsidePageState extends State<GuideOutsidePage> {
  String? _id;
  late final Future<void> _saved;
  bool _busy = false;

  GuideCameraHit? get _leading => widget.outcome.leading;

  String get _plant {
    final latin = _leading?.latin.trim() ?? '';
    if (latin.isNotEmpty) return latin;
    return _leading?.path ?? '';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.observationId?.trim() ?? '';
    if (existing.isNotEmpty) {
      _id = existing;
      _saved = Future<void>.value();
      return;
    }
    _saved = _save();
  }

  Future<void> _save() async {
    final save = widget.onSave;
    if (save == null) return;
    final leading = _leading;
    final id = await save(GuideCameraDraft(
      plant: _plant,
      when: widget.when,
      shotPath: widget.photoPath,
      latitude: widget.latitude,
      longitude: widget.longitude,
      candidates: guideCameraCandidateMaps([
        if (leading != null) leading,
        ...widget.outcome.candidates,
      ]),
    ));
    if (!mounted) return;
    setState(() => _id = id);
    if (id != null) GuideTabs.refreshSeen?.call();
  }

  Future<void> _keep() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _saved;
      final id = _id;
      if (id != null) await widget.onConfirm?.call(id);
      if (!mounted) return;
      final month = DateFormat.MMMM(
        Localizations.localeOf(context).toString(),
      ).format(widget.when);
      Navigator.pop(
        context,
        GuideOutsideResult.seen(S.of(context).guide_outside_confirmed(month)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _saved;
      final id = _id;
      if (id != null) await widget.onDelete?.call(id);
      if (!mounted) return;
      GuideTabs.refreshSeen?.call();
      Navigator.pop(
        context,
        GuideOutsideResult.seen(S.of(context).guide_outside_deleted),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _another() async {
    final chosen = await showGuideOtherNames(
      context: context,
      candidates: widget.outcome.candidates,
      onSearch: widget.onSearch,
    );
    if (chosen == null || !mounted) return;
    final name = guideCameraSpeciesName(chosen);
    if (name == null) return;
    setState(() => _busy = true);
    try {
      await _saved;
      final id = _id;
      if (id != null) {
        await widget.onRetarget?.call(id, _plant, name);
      }
      if (!mounted) return;
      GuideTabs.refreshSeen?.call();
      Navigator.pop(
        context,
        GuideOutsideResult.species(name, S.of(context).guide_outside_changed),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      child: Builder(
        builder: (context) => _page(context),
      ),
    );
  }

  Widget _page(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final leading = _leading;
    final time = guidePhotoMoment(context, widget.when);
    final window = GuideWindow.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final shot = _Shot(
      path: widget.photoPath,
      place: widget.place,
      whenLabel: guidePhotoDay(
        context,
        widget.when,
        todayLabel: strings.guide_outside_just_now,
      ),
      expand: window.wide,
      onClose: () async {
        try {
          await _saved;
        } catch (_) {}
        if (!context.mounted) return;
        Navigator.pop(
          context,
          const GuideOutsideResult.find(),
        );
      },
    );
    final text = <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GuideConfidenceMark(probability: leading?.probability),
                const SizedBox(height: 6),
                Text(
                  leading?.latin ?? '',
                  style: TextStyle(
                    fontFamily: GuideType.serif,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    fontSize: 30,
                    height: 1.1,
                    color: colors.ink,
                  ),
                ),
                if (leading?.vernacular != null &&
                    leading!.vernacular!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    leading.vernacular!.trim(),
                    style: TextStyle(fontSize: 15, color: colors.ink3),
                  ),
                ],
                if (_family(leading, colors) != null) ...[
                  const SizedBox(height: 8),
                  _family(leading, colors)!,
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.paper2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  strings.guide_camera_outside,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: colors.ink2,
                  ),
                ),
              ),
            ),
          ),
          ..._candidates(colors, strings),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.madder, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.confirmed
                          ? strings.guide_camera_confirmed_line(time)
                          : strings.guide_outside_saved,
                      style: TextStyle(
                        color: colors.madder,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.guide_outside_saved_detail(time, widget.place),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.ink3,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!widget.confirmed)
                          _Action(
                            key: const Key('guide-outside-keep'),
                            label: strings.guide_outside_keep,
                            filled: true,
                            onPressed: _busy ? null : _keep,
                          ),
                        _Action(
                          key: const Key('guide-outside-another'),
                          label: strings.guide_outside_another,
                          onPressed: _busy ? null : _another,
                        ),
                        _Action(
                          key: const Key('guide-outside-delete'),
                          label: strings.guide_outside_delete,
                          foreground: colors.madder,
                          onPressed: _busy ? null : _delete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    ];
    return Scaffold(
      key: const Key('guide-outside-page'),
      backgroundColor: colors.paper,
      body: guideWithRail(
        context,
        child: window.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 105, child: shot),
                  Expanded(
                    flex: 95,
                    child: ListView(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      children: text,
                    ),
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsets.only(bottom: bottomInset),
                children: [shot, ...text],
              ),
      ),
    );
  }

  List<Widget> _candidates(GuideColors colors, S strings) {
    final hits = widget.outcome.candidates;
    if (hits.isEmpty) return const [];
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 10),
      child: Text(
        strings.guide_camera_in_book,
        style: GuideType.section(colors),
      ),
    );
    final portraitGrid =
        GuideWindow.of(context).tablet && !GuideWindow.of(context).wide;
    if (!portraitGrid) {
      return [
        header,
        for (final hit in hits)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
            child: _Candidate(hit: hit, onOpen: widget.onOpenSpecies),
          ),
      ];
    }
    return [
      header,
      for (var i = 0; i < hits.length; i += 2)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Candidate(hit: hits[i], onOpen: widget.onOpenSpecies),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < hits.length
                    ? _Candidate(
                        hit: hits[i + 1],
                        onOpen: widget.onOpenSpecies,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ];
  }

  Widget? _family(GuideCameraHit? hit, GuideColors colors) {
    final latin = hit?.familyLatin?.trim() ?? '';
    final label = hit?.familyLabel?.trim() ?? '';
    if (latin.isEmpty && label.isEmpty) return null;
    return Text.rich(TextSpan(
      style: TextStyle(fontSize: 14, height: 1.4, color: colors.ink2),
      children: [
        if (label.isNotEmpty) TextSpan(text: label),
        if (label.isNotEmpty && latin.isNotEmpty) const TextSpan(text: ' · '),
        if (latin.isNotEmpty)
          TextSpan(
            text: latin,
            style: const TextStyle(
              fontFamily: GuideType.serif,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    ));
  }
}

/// A shutter path is an absolute file. A Seen photo is a path under the
/// app documents directory, or a catalog storage path.
Widget _shotPhoto(String? path, double width, double height) {
  if (path == null || path.isEmpty) return const SizedBox.expand();
  final direct = File(path);
  if (direct.existsSync()) {
    return Image.file(direct, fit: BoxFit.cover, width: width, height: height);
  }
  if (path.startsWith('/')) return const SizedBox.expand();
  return getImage(
    path,
    const SizedBox.expand(),
    width: width,
    height: height,
    fit: BoxFit.cover,
  );
}

class _Shot extends StatelessWidget {
  final String? path;
  final String place;
  final String whenLabel;
  final bool expand;
  final VoidCallback onClose;

  const _Shot({
    required this.path,
    required this.place,
    required this.whenLabel,
    required this.expand,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final top = MediaQuery.paddingOf(context).top;
    // Wide photo fills the scaffold. Phone photo is a band at the top.
    final pillBottom =
        10 + (expand ? MediaQuery.paddingOf(context).bottom : 0.0);
    final height = expand
        ? null
        : (GuideWindow.of(context).tablet ? 420.0 : 300.0);
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF333333)),
        LayoutBuilder(
          builder: (context, constraints) {
            return _shotPhoto(
              path,
              constraints.maxWidth,
              constraints.maxHeight,
            );
          },
        ),
          PositionedDirectional(
            top: top + 10,
            start: 12,
            child: Material(
              color: colors.wash,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                key: const Key('guide-outside-close'),
                tooltip: strings.guide_camera_close,
                onPressed: onClose,
                icon: Icon(Icons.close, color: colors.ink, size: 20),
              ),
            ),
          ),
          PositionedDirectional(
            start: 12,
            bottom: pillBottom,
            child: Row(
              children: [
                _MetaPill(label: whenLabel),
                const SizedBox(width: 6),
                _MetaPill(
                  label: place,
                  icon: Icons.place_outlined,
                ),
              ],
            ),
          ),
      ],
    );
    if (expand) return stack;
    return SizedBox(height: height, child: stack);
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MetaPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.wash,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.ink),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Candidate extends StatelessWidget {
  final GuideCameraHit hit;
  final void Function(String name)? onOpen;
  final String? actionLabel;

  const _Candidate({
    required this.hit,
    required this.onOpen,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final species = guideCameraSpeciesName(hit);
    final vernacular = hit.vernacular?.trim() ?? '';
    final title = vernacular.isNotEmpty ? vernacular : hit.latin;
    final showLatin = title.toLowerCase() != hit.latin.toLowerCase();
    return Material(
      color: colors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            species == null || onOpen == null ? null : () => onOpen!(species),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _Thumb(path: hit.photoPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GuideConfidenceMark(probability: hit.probability),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: GuideType.serif,
                        fontWeight: FontWeight.w500,
                        fontSize: 17,
                        color: colors.ink,
                      ),
                    ),
                    if (showLatin)
                      Text(
                        hit.latin,
                        style: TextStyle(
                          fontFamily: GuideType.serif,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                          color: colors.ink3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                actionLabel ?? strings.guide_camera_full_page,
                style: TextStyle(
                  color: colors.moss,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? path;

  const _Thumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final photo = path;
    if (photo == null || photo.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: GuideColors.of(context).photoWell,
          child: const SizedBox(width: 64, height: 64),
        ),
      );
    }
    return GuidePhoto(path: photo, width: 64, height: 64, radius: 10);
  }
}

class _Action extends StatelessWidget {
  final String label;
  final bool filled;
  final Color? foreground;
  final VoidCallback? onPressed;

  const _Action({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        backgroundColor: filled ? colors.mossFill : colors.cream,
        foregroundColor: filled ? Colors.white : (foreground ?? colors.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: filled ? BorderSide.none : BorderSide(color: colors.rule),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

/// Three bars and a word: likely, possible, or uncertain.
class GuideConfidenceMark extends StatelessWidget {
  final double? probability;

  const GuideConfidenceMark({super.key, required this.probability});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final confidence = guideCameraConfidence(probability);
    final Color color;
    final Color bar;
    final String label;
    final int filled;
    switch (confidence) {
      case GuideCameraConfidence.likely:
        color = colors.moss;
        bar = colors.mossFill;
        label = strings.guide_camera_likely;
        filled = 3;
      case GuideCameraConfidence.possible:
        color = colors.gold;
        bar = colors.gold;
        label = strings.guide_camera_possible;
        filled = 2;
      case GuideCameraConfidence.uncertain:
        color = colors.ink3;
        bar = colors.ink3;
        label = strings.guide_camera_uncertain;
        filled = 1;
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 6,
              height: 12,
              decoration: BoxDecoration(
                color: i < filled ? bar : colors.rule,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plant.id’s other names for this photo. Returns the chosen catalog species.
Future<GuideCameraHit?> showGuideOtherNames({
  required BuildContext context,
  required List<GuideCameraHit> candidates,
  VoidCallback? onSearch,
}) {
  return showModalBottomSheet<GuideCameraHit>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) {
      return GuideTheme(
        child: Builder(
          builder: (context) {
            final colors = GuideColors.of(context);
            final strings = S.of(context);
            final tablet = GuideWindow.of(context).tablet;
            return guideSheetAlign(
              context,
              Material(
              color: colors.paper,
              borderRadius: tablet
                  ? BorderRadius.circular(22)
                  : const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!tablet)
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.rule,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const SizedBox(width: 36, height: 4),
                          ),
                        ),
                      if (!tablet) const SizedBox(height: 12),
                      Text(
                        strings.guide_outside_which,
                        style: TextStyle(
                          fontFamily: GuideType.serif,
                          fontWeight: FontWeight.w500,
                          fontSize: 23,
                          height: 1.12,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.guide_outside_which_body,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: colors.ink2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final hit in candidates)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _Candidate(
                            hit: hit,
                            actionLabel: strings.guide_outside_choose,
                            onOpen: (name) => Navigator.pop(context, hit),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          key: const Key('guide-outside-search'),
                          onPressed: () {
                            Navigator.pop(context);
                            onSearch?.call();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: colors.ink,
                            backgroundColor: colors.cream,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                              side: BorderSide(color: colors.rule),
                            ),
                          ),
                          child: Text(strings.guide_outside_search),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        ),
      );
    },
  );
}
