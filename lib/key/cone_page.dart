import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/key/conifer.dart';
import 'package:abherbs_flutter/key/habitat_page.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:flutter/material.dart';

class GuideConePage extends StatefulWidget {
  final String leafId;
  final String? habitatId;
  final GuideConeCounts? counts;
  final Future<GuideConeCounts> Function(String leafId, String? habitatId)
      loadCounts;
  final void Function(String? coneId)? onContinue;

  const GuideConePage({
    super.key,
    required this.leafId,
    required this.habitatId,
    this.counts,
    this.loadCounts = loadConeCounts,
    this.onContinue,
  });

  @override
  State<GuideConePage> createState() => _GuideConePageState();
}

class _GuideConePageState extends State<GuideConePage> {
  GuideConeCounts? _counts;
  bool _failed = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _counts = widget.counts;
    if (_counts == null) _load();
  }

  @override
  void didUpdateWidget(GuideConePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.counts != oldWidget.counts) {
      _counts = widget.counts;
      _failed = false;
    }
    if ((widget.leafId != oldWidget.leafId ||
            widget.habitatId != oldWidget.habitatId) &&
        widget.counts == null) {
      _counts = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    try {
      final counts = await widget.loadCounts(widget.leafId, widget.habitatId);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _counts = counts;
        _failed = false;
      });
    } catch (error) {
      debugPrint('guide cones: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() => _failed = true);
    }
  }

  void _pick(String id) {
    final counts = _counts;
    if (counts == null && !_failed) return;
    final remaining = counts?.byCone[id];
    if (remaining != null && remaining <= 0) {
      guideNoConifers(context);
      return;
    }
    widget.onContinue?.call(id);
  }

  void _skip() {
    final counts = _counts;
    if (counts == null && !_failed) return;
    if (counts != null && counts.total <= 0) {
      guideNoConifers(context);
      return;
    }
    widget.onContinue?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final leafName = guideCap(guideLeafName(strings, widget.leafId));
    final habitatId = widget.habitatId;
    final habitatValue =
        habitatId == null ? '' : guideHabitatName(strings, habitatId);
    final habitatName = habitatValue.isEmpty ? '' : guideCap(habitatValue);
    return GuideKeyScaffold(
      withTabs: true,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          GuideBackButton(label: guideCap(strings.filter_habitat)),
          if (leafName.isNotEmpty || habitatName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (leafName.isNotEmpty)
                    GuideFilterPill(
                      label: leafName,
                      leading: GuideLeafGlyph(id: widget.leafId, size: 16),
                      onPressed: () => popGuideKeyToFind(context),
                    ),
                  if (habitatName.isNotEmpty)
                    GuideFilterPill(
                      label: habitatName,
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
                Text(
                  strings.guide_key_step_petal.toUpperCase(),
                  style: GuideType.eyebrow(colors),
                ),
                const SizedBox(height: 8),
                const GuideKeyStepper(filled: 3),
                const SizedBox(height: 12),
                Text(
                  strings.guide_cone_question,
                  style: GuideType.question(colors),
                ),
                const SizedBox(height: 6),
                Text(
                  strings.guide_cone_hint,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.ink3,
                  ),
                ),
                const SizedBox(height: 14),
                for (final id in guideConeIds) ...[
                  _ConeTile(
                    id: id,
                    count: _counts?.byCone[id],
                    onPick: () => _pick(id),
                  ),
                  if (id != guideConeIds.last) const SizedBox(height: 8),
                ],
                const SizedBox(height: 14),
                SizedBox(
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
                      _skipLabel(strings),
                      textAlign: TextAlign.center,
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

  String _skipLabel(S strings) {
    final total = _counts?.total;
    if (total == null) return strings.guide_cone_skip;
    return strings.guide_cone_skip_count(total);
  }
}

class _ConeTile extends StatelessWidget {
  final String id;
  final int? count;
  final VoidCallback onPick;

  const _ConeTile({
    required this.id,
    required this.count,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final empty = count == 0;
    return Opacity(
      opacity: empty ? 0.38 : 1,
      child: Material(
        color: colors.cream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.rule),
            ),
            child: Row(
              children: [
                const SizedBox(width: 4),
                GuideConeGlyph(id: id, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guideCap(guideConeName(strings, id)),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        guideConeExample(strings, id),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: colors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 12, color: colors.ink3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
