import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/key/habitat_glyphs.dart';
import 'package:flutter/material.dart';

String guideHabitatName(S strings, String id) {
  switch (id) {
    case '4':
      return strings.guide_habitat_forest;
    case '1':
      return strings.guide_habitat_meadow;
    case '7':
      return strings.guide_habitat_dry;
    case '8':
      return strings.guide_habitat_fields;
    case '3':
      return strings.guide_habitat_water;
    case '9':
      return strings.guide_habitat_heath;
    case '5':
      return strings.guide_habitat_rock;
    case '10':
      return strings.guide_habitat_coast;
    default:
      return '';
  }
}

String guideHabitatExamples(S strings, String id) {
  switch (id) {
    case '4':
      return strings.guide_habitat_forest_examples;
    case '1':
      return strings.guide_habitat_meadow_examples;
    case '7':
      return strings.guide_habitat_dry_examples;
    case '8':
      return strings.guide_habitat_fields_examples;
    case '3':
      return strings.guide_habitat_water_examples;
    case '9':
      return strings.guide_habitat_heath_examples;
    case '5':
      return strings.guide_habitat_rock_examples;
    case '10':
      return strings.guide_habitat_coast_examples;
    default:
      return '';
  }
}

class GuideHabitatPage extends StatefulWidget {
  final String colorId;
  final GuideHabitatCounts? counts;
  final Future<GuideHabitatCounts> Function(String colorId) loadCounts;
  final void Function(String? habitatId) onContinue;

  const GuideHabitatPage({
    super.key,
    required this.colorId,
    required this.onContinue,
    this.counts,
    this.loadCounts = loadHabitatCounts,
  });

  @override
  State<GuideHabitatPage> createState() => _GuideHabitatPageState();
}

class _GuideHabitatPageState extends State<GuideHabitatPage> {
  GuideHabitatCounts? _counts;
  bool _failed = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _counts = widget.counts;
    if (_counts == null) _load();
  }

  @override
  void didUpdateWidget(GuideHabitatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.counts != oldWidget.counts) {
      _counts = widget.counts;
      _failed = false;
    }
    if (widget.colorId != oldWidget.colorId && widget.counts == null) {
      _counts = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    final colorId = widget.colorId;
    try {
      final counts = await widget.loadCounts(colorId);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _counts = counts;
        _failed = false;
      });
    } catch (error) {
      debugPrint('guide habitat: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() => _failed = true);
    }
  }

  void _pick(String id) {
    final counts = _counts;
    if (counts == null && !_failed) return;
    final remaining = counts?.byHabitat[id];
    if (remaining != null && remaining <= 0) {
      guideNoFlowers(context);
      return;
    }
    widget.onContinue(id);
  }

  void _skip() {
    final counts = _counts;
    if (counts == null && !_failed) return;
    if (counts != null && counts.total <= 0) {
      guideNoFlowers(context);
      return;
    }
    widget.onContinue(null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final colorName = getFilterColorValue(context, widget.colorId);
    return GuideKeyScaffold(
      withTabs: true,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          GuideBackButton(label: guideCap(strings.filter_color)),
          if (colorName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  GuideFilterPill(
                    label: guideCap(colorName),
                    leading: _ColorDot(colorId: widget.colorId),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GuideFoldLeading(
                  originX: 20,
                  child: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.guide_key_step_habitat.toUpperCase(),
                        style: GuideType.eyebrow(colors),
                      ),
                      const SizedBox(height: 8),
                      const GuideKeyStepper(filled: 2),
                      const SizedBox(height: 12),
                      Text(
                        strings.guide_habitat_question,
                        style: GuideType.question(colors),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ..._habitatTiles(),
                const SizedBox(height: 14),
                GuideFoldLeading(
                  originX: 20,
                  child: (context) => SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.moss,
                        textStyle: const TextStyle(
                          fontFamily: GuideType.sans,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(
                        _skipLabel(strings, colorName),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _habitatTiles() {
    final perRow = GuideFold.across(
      context,
      GuideWindow.of(context).columns(phone: 2, tablet: 4, wide: 4),
    );
    final tiles = <Widget>[];
    for (var i = 0; i < guideHabitatIds.length; i += perRow) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 8));
      final end = i + perRow > guideHabitatIds.length
          ? guideHabitatIds.length
          : i + perRow;
      tiles.add(
        _HabitatRow(
          ids: guideHabitatIds.sublist(i, end),
          columns: perRow,
          counts: _counts,
          onPick: _pick,
        ),
      );
    }
    return tiles;
  }

  String _skipLabel(S strings, String colorName) {
    final total = _counts?.total;
    if (colorName.isEmpty) {
      if (total == null) return strings.guide_habitat_skip_any;
      return strings.guide_habitat_skip_any_count(total);
    }
    if (total == null) return strings.guide_habitat_skip(colorName);
    return strings.guide_habitat_skip_count(total, colorName);
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

class _HabitatRow extends StatelessWidget {
  final List<String> ids;
  final int columns;
  final GuideHabitatCounts? counts;
  final ValueChanged<String> onPick;

  const _HabitatRow({
    required this.ids,
    required this.columns,
    required this.counts,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GuideFoldRow(
      columns: columns,
      gap: 8,
      originX: 20,
      stretch: true,
      children: [for (final id in ids) _tile(context, id)],
    );
  }

  Widget _tile(BuildContext context, String id) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final name = guideCap(guideHabitatName(strings, id));
    final examples = guideHabitatExamples(strings, id);
    final remaining = counts?.byHabitat[id];
    return Material(
      color: colors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onPick(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GuideHabitatGlyph(id: id),
                  const Spacer(),
                  Text(
                    remaining == null ? ' ' : '$remaining',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.2,
                ),
              ),
              Text(
                examples,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
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
