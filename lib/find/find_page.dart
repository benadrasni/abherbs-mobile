import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/shell/guide_actions.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:flutter/material.dart';

class FindPage extends StatelessWidget {
  final Map<String, int>? colorCounts;
  final List<GuideListCover>? lists;

  /// The list read threw. [lists] stays null; an empty list is a real answer.
  final bool listsFailed;
  final VoidCallback? onRetryLists;

  /// Signed-in favorites. Shown first in the list strip only when
  /// [GuideListCover.count] is at least one. New in the book stays second.
  final GuideListCover? favorites;
  final List<GuideFind>? finds;
  final GuideAllowance allowance;
  final VoidCallback onOpenBook;
  final VoidCallback onOpenSeen;

  const FindPage({
    super.key,
    required this.colorCounts,
    required this.lists,
    this.listsFailed = false,
    this.onRetryLists,
    this.favorites,
    required this.finds,
    this.allowance = const GuideAllowance.guest(),
    required this.onOpenBook,
    required this.onOpenSeen,
  });

  @override
  Widget build(BuildContext context) {
    final window = GuideWindow.of(context);
    final crease = GuideFold.verticalCrease(context);
    final recent = (finds ?? const <GuideFind>[]).take(5).toList();
    final flowerLists = _findLists(lists, favorites);
    final strings = S.of(context);
    final seen = recent.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GuideSectionHeader(
                title: strings.guide_seen_lately,
                action: strings.guide_all_finds,
                onAction: onOpenSeen,
              ),
              _FindStrip(finds: recent, onOpenSeen: onOpenSeen),
            ],
          );
    final flowerListsView = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GuideSectionHeader(
          title: strings.custom_lists,
          action: strings.guide_all_lists,
          onAction: onOpenBook,
        ),
        if (flowerLists == null && listsFailed)
          _ListRetry(onPressed: onRetryLists)
        else if (flowerLists == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (flowerLists.isNotEmpty)
          _ListStrip(lists: flowerLists),
      ],
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        GuideTitleBar(
          title: const GuideWordmark(),
          actionLabel: strings.guide_account,
          icon: Icons.person_outline,
          showAction: !window.wide,
          onAction: () => openGuideAccount(context),
        ),
        if (crease != null)
          GuideFoldSplit(
            crossAxisAlignment: CrossAxisAlignment.start,
            unsplit: const SizedBox.shrink(),
            leading: Column(
              children: [
                const _SearchButton(),
                _CameraCard(allowance: allowance),
              ],
            ),
            trailing: _KeyCard(colorCounts: colorCounts),
          )
        else if (window.tablet)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const _SearchButton(),
                    _CameraCard(allowance: allowance),
                  ],
                ),
              ),
              Expanded(child: _KeyCard(colorCounts: colorCounts)),
            ],
          )
        else ...[
          const _SearchButton(),
          _CameraCard(allowance: allowance),
          _KeyCard(colorCounts: colorCounts),
        ],
        if (window.wide && seen != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 85, child: seen),
              Expanded(flex: 115, child: flowerListsView),
            ],
          )
        else ...[
          if (seen != null) seen,
          flowerListsView,
        ],
      ],
    );
  }
}

class _ListRetry extends StatelessWidget {
  final VoidCallback? onPressed;

  const _ListRetry({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: colors.ink2),
        child: Text(
          S.of(context).no_connection_content,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton();

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
      child: Material(
        color: colors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openGuideSearch(context),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search, size: 20, color: colors.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    S.of(context).guide_search,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: colors.ink3),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  final GuideAllowance allowance;

  const _CameraCard({required this.allowance});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
      child: Material(
        color: colors.mossFill,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openGuideCamera(context),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context).guide_camera_title,
                        style: TextStyle(
                          fontFamily: GuideType.serif,
                          fontWeight: FontWeight.w500,
                          fontSize: 21,
                          height: 1.1,
                          color: colors.onMoss,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        S.of(context).guide_camera_body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: colors.onMoss.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Meter(allowance: allowance),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.onMoss,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: Icon(Icons.photo_camera_outlined,
                        color: colors.mossFill, size: 28),
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

class _Meter extends StatelessWidget {
  final GuideAllowance allowance;

  const _Meter({required this.allowance});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final style = TextStyle(
      fontSize: 12,
      height: 1.2,
      color: colors.onMoss.withValues(alpha: 0.9),
    );
    final meter = guideCameraMeter(allowance);
    switch (meter.kind) {
      case GuideCameraMeterKind.fieldGuide:
        return Text(S.of(context).guide_meter_field_guide, style: style);
      case GuideCameraMeterKind.unlimited:
        return Text(S.of(context).guide_meter_unlimited, style: style);
      case GuideCameraMeterKind.signIn:
        return Text(S.of(context).guide_meter_sign_in, style: style);
      case GuideCameraMeterKind.namesLeft:
        return Row(
          children: [
            for (var i = 0; i < meter.dotCount; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _Dot(filled: i < meter.filledDots),
            ],
            if (meter.dotCount > 0) const SizedBox(width: 8),
            Flexible(
              child: Text(
                S.of(context).guide_meter_left(meter.namesLeft),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
    }
  }
}

class _Dot extends StatelessWidget {
  final bool filled;

  const _Dot({required this.filled});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colors.onMoss : Colors.transparent,
        border: Border.all(color: colors.onMoss, width: 1.5),
      ),
    );
  }
}

/// The step label and "always free" sit at opposite ends. On a narrow
/// phone the pair can be wider than the card, so the longer label
/// ellipsizes instead of overflowing the row.
class _KeyStepLine extends StatelessWidget {
  final String step;
  final String free;

  const _KeyStepLine({required this.step, required this.free});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final stepStyle = GuideType.eyebrow(colors);
    final freeStyle = stepStyle.copyWith(color: colors.moss);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final stepWidth = _oneLineWidth(context, step, stepStyle);
        final freeWidth = _oneLineWidth(context, free, freeStyle);
        if (!maxWidth.isFinite || stepWidth + freeWidth <= maxWidth) {
          return Row(
            children: [
              Text(step, maxLines: 1, style: stepStyle),
              const Spacer(),
              Text(free, maxLines: 1, style: freeStyle),
            ],
          );
        }
        const gap = 8.0;
        final room = (maxWidth - gap).clamp(0.0, maxWidth);
        // Keep the shorter label whole and give the leftover to the longer one.
        final stepSlot = stepWidth >= freeWidth
            ? (room - freeWidth).clamp(0.0, room)
            : stepWidth.clamp(0.0, room);
        final freeSlot = (room - stepSlot).clamp(0.0, room);
        return Row(
          children: [
            SizedBox(
              width: stepSlot,
              child: Text(
                step,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: stepStyle,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: freeSlot,
              child: Text(
                free,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: freeStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

double _oneLineWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _KeyCard extends StatelessWidget {
  final Map<String, int>? colorCounts;

  const _KeyCard({required this.colorCounts});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final s = S.of(context);
    final swatches = [
      ('1', s.color_white),
      ('2', s.color_yellow),
      ('3', s.color_red),
      ('4', s.color_blue),
      ('5', s.color_green),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyStepLine(
            step: s.guide_key_step.toUpperCase(),
            free: s.guide_always_free.toUpperCase(),
          ),
          const SizedBox(height: 8),
          const GuideKeyStepper(filled: 1),
          const SizedBox(height: 12),
          Text(s.guide_color_question, style: GuideType.question(colors)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final swatch in swatches)
                Expanded(
                  child: _Swatch(
                    id: swatch.$1,
                    label: guideCap(swatch.$2),
                    color: guideSwatchColor(swatch.$1),
                    count: colorCounts == null ? null : colorCounts![swatch.$1],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String id;
  final String label;
  final Color color;
  final int? count;

  const _Swatch({
    required this.id,
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    // White is nearly the paper color, so this disk is true white with a
    // pencil ring instead of the faint hairline used on the other colors.
    final white = id == '1';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openGuideColor(context, id),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: white ? const Color(0xFFFFFFFF) : color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: white
                              ? colors.ink3.withValues(alpha: 0.55)
                              : const Color(0x1F000000),
                          width: white ? 1.5 : 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.15),
                    ),
                  ],
                ),
              ),
              if (count != null)
                PositionedDirectional(
                  top: 4,
                  end: 6,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.ink3,
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

/// Madder pill on an unconfirmed photo in Seen lately. Mockup `.find-card .u`.
const guideFindToConfirmKey = Key('guide-find-to-confirm');

const _findNameGap = 6.0;
const _findDateGap = 2.0;

TextStyle _findDateStyle(GuideColors colors) {
  return TextStyle(fontSize: 11, color: colors.ink3);
}

/// Tallest phone card: photo, a name of up to two lines, and the date.
///
/// [Text] applies bold text and the platform line-height override on top of
/// the style. The painter has to do the same, or the strip is short on the
/// phone that sets them.
double _phoneFindStripHeight(
  BuildContext context,
  List<GuideFind> finds,
  double width,
) {
  final colors = GuideColors.of(context);
  var tallest = 0.0;
  for (final find in finds) {
    final named = guideNameIsVernacular(find.label);
    final name = _textBlockHeight(
      context,
      text: named ? find.label! : find.name,
      style: guideNameStyle(colors, named: named),
      width: width,
      maxLines: 2,
    );
    final date = _textBlockHeight(
      context,
      text: guideWhen(context, find.when),
      style: _findDateStyle(colors),
      width: width,
      maxLines: 1,
    );
    // The photo is square, the same edge as the text width.
    final height = width + _findNameGap + name + _findDateGap + date;
    if (height > tallest) tallest = height;
  }
  // Each text line can round up to the next physical pixel inside the column.
  final slack = 2 / MediaQuery.devicePixelRatioOf(context);
  return tallest + slack;
}

double _textBlockHeight(
  BuildContext context, {
  required String text,
  required TextStyle style,
  required double width,
  required int maxLines,
}) {
  final defaults = DefaultTextStyle.of(context);
  var effective = style.inherit ? defaults.style.merge(style) : style;
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final lineHeight = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (lineHeight != null || letterSpacing != null || wordSpacing != null) {
    effective = effective.merge(
      TextStyle(
        height: lineHeight,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
      ),
    );
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textAlign: defaults.textAlign ?? TextAlign.start,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
    ellipsis: '\u2026',
    locale: Localizations.maybeLocaleOf(context),
    textWidthBasis: defaults.textWidthBasis,
    textHeightBehavior: defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

class _FindStrip extends StatelessWidget {
  final List<GuideFind> finds;
  final VoidCallback onOpenSeen;

  const _FindStrip({required this.finds, required this.onOpenSeen});

  @override
  Widget build(BuildContext context) {
    final window = GuideWindow.of(context);
    if (!window.tablet) {
      // A horizontal list needs a finite height. A wrapped name is a couple
      // of pixels taller on some densities than on others, so a constant
      // clips the date (Pixel 10 Pro, 2px) while the same card fits on a
      // Pixel 9a. Measure the cards instead.
      const edge = 118.0;
      return SizedBox(
        height: _phoneFindStripHeight(context, finds, edge),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: finds.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _card(context, finds[index], edge),
        ),
      );
    }
    final columns = window.wide ? 3 : 5;
    return _GuideGrid(
      columns: columns,
      count: finds.length,
      item: (index) => _card(context, finds[index], null),
    );
  }

  Widget _card(BuildContext context, GuideFind find, double? edge) {
    final colors = GuideColors.of(context);
    final photo = edge == null
        ? AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GuidePhoto(
                  path: find.photoPath,
                  cover: find.coverPath,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
          )
        : GuidePhoto(
            path: find.photoPath,
            cover: find.coverPath,
            width: edge,
            height: edge,
          );
    final card = InkWell(
      onTap: () {
        // A name still waiting opens Seen, where it can be confirmed.
        if (!find.confirmed) {
          onOpenSeen();
          return;
        }
        openGuidePlant(
          context,
          find.name,
          source: GuidePlantSource.seen,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              photo,
              if (!find.confirmed)
                const PositionedDirectional(
                  start: 6,
                  top: 6,
                  child: _ToConfirmBadge(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GuideName(label: find.label, latinName: find.name),
          const SizedBox(height: 2),
          Text(
            guideWhen(context, find.when),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _findDateStyle(colors),
          ),
        ],
      ),
    );
    if (edge == null) return card;
    return SizedBox(width: edge, child: card);
  }
}

class _GuideGrid extends StatelessWidget {
  final int columns;
  final int count;
  final Widget Function(int index) item;

  const _GuideGrid({
    required this.columns,
    required this.count,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final fold = GuideFold.verticalCrease(context);
    var across = columns;
    if (fold != null && across.isOdd && across > 1) across -= 1;
    if (fold == null || across < 2) {
      return _rows(
        across,
        count,
        item,
        const EdgeInsets.symmetric(horizontal: 20),
      );
    }
    final half = across ~/ 2;
    List<int> side(bool leading) => [
          for (var i = 0; i < count; i++)
            if (leading ? i % across < half : i % across >= half) i,
        ];
    Widget page(List<int> indexes, EdgeInsetsGeometry padding) {
      return _rows(
        half,
        indexes.length,
        (local) => item(indexes[local]),
        padding,
      );
    }

    return GuideFoldSplit(
      crossAxisAlignment: CrossAxisAlignment.start,
      unsplit: _rows(
        across,
        count,
        item,
        const EdgeInsets.symmetric(horizontal: 20),
      ),
      leading: page(
        side(true),
        const EdgeInsetsDirectional.only(start: 20, end: 6),
      ),
      trailing: page(
        side(false),
        const EdgeInsetsDirectional.only(start: 6, end: 20),
      ),
    );
  }
}

Widget _rows(
  int columns,
  int count,
  Widget Function(int index) item,
  EdgeInsetsGeometry padding,
) {
  final rows = count == 0 ? 0 : (count / columns).ceil();
  return Padding(
    padding: padding,
    child: Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 12),
                Expanded(
                  child: row * columns + column < count
                      ? item(row * columns + column)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

class _ToConfirmBadge extends StatelessWidget {
  const _ToConfirmBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: guideFindToConfirmKey,
      decoration: BoxDecoration(
        color: GuideColors.of(context).madderFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          S.of(context).guide_find_to_confirm,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Editorial lists, with favorites first when at least one plant is marked.
List<GuideListCover>? _findLists(
  List<GuideListCover>? lists,
  GuideListCover? favorites,
) {
  if (lists == null) return null;
  final leading =
      favorites != null && favorites.isFavorite && favorites.count > 0
          ? favorites
          : null;
  return [
    for (final cover in lists)
      if (!cover.isFavorite) cover,
    if (leading != null) leading,
  ]..sort(compareGuideLists);
}

class _ListStrip extends StatelessWidget {
  final List<GuideListCover> lists;

  const _ListStrip({required this.lists});

  @override
  Widget build(BuildContext context) {
    final window = GuideWindow.of(context);
    if (!window.tablet) {
      return SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: lists.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _card(context, lists[index], 150),
        ),
      );
    }
    final columns = window.columns(phone: 1, tablet: 4, wide: 3);
    return _GuideGrid(
      columns: columns,
      count: lists.length,
      item: (index) => _card(context, lists[index], null),
    );
  }

  Widget _card(BuildContext context, GuideListCover cover, double? edge) {
    final colors = GuideColors.of(context);
    final title = guideListTitle(context, cover);
    final coverBox = edge == null
        ? AspectRatio(
            aspectRatio: 16 / 10,
            child: _cover(context, cover, title, null),
          )
        : _cover(context, cover, title, edge);
    final card = InkWell(
      onTap: () => openGuideList(
        context,
        cover,
        backLabel: S.of(context).guide_tab_find,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          coverBox,
          const SizedBox(height: 5),
          Text(
            guideListSubtitle(context, cover),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.25, color: colors.ink3),
          ),
        ],
      ),
    );
    if (edge == null) return card;
    return SizedBox(width: edge, child: card);
  }

  Widget _cover(
    BuildContext context,
    GuideListCover cover,
    String title,
    double? width,
  ) {
    final colors = GuideColors.of(context);
    Widget photo(double w, double h) => GuidePhoto(
          path: cover.photoPath,
          width: w,
          height: h,
          radius: 0,
        );
    final art = width == null
        ? LayoutBuilder(
            builder: (context, constraints) => photo(
              constraints.maxWidth,
              constraints.maxHeight,
            ),
          )
        : photo(width, 96);
    final frame = Stack(
      fit: StackFit.expand,
      children: [
        art,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x99000000)],
              stops: [0.45, 1],
            ),
          ),
        ),
        PositionedDirectional(
          start: 9,
          end: 9,
          bottom: 7,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: GuideType.serif,
              fontWeight: FontWeight.w500,
              fontSize: 15,
              height: 1.1,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: cover.isNew ? Border.all(color: colors.gold, width: 2) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: width == null
            ? frame
            : SizedBox(width: width, height: 96, child: frame),
      ),
    );
  }
}
