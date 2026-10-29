import 'dart:math' as math;

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_fold.dart';
import 'package:abherbs_flutter/shell/guide_window.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

export 'package:abherbs_flutter/shell/guide_fold.dart';
export 'package:abherbs_flutter/shell/guide_window.dart';

class GuideTitleBar extends StatelessWidget {
  final Widget title;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onAction;
  final bool showAction;
  final String? leadingLabel;
  final IconData? leadingIcon;
  final VoidCallback? onLeading;

  const GuideTitleBar({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.icon,
    required this.onAction,
    this.showAction = true,
    this.leadingLabel,
    this.leadingIcon,
    this.onLeading,
  });

  @override
  Widget build(BuildContext context) {
    final leading = onLeading;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 12),
      child: Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          if (leading != null && leadingIcon != null) ...[
            _TitleAction(
              label: leadingLabel ?? '',
              icon: leadingIcon!,
              onPressed: leading,
            ),
            const SizedBox(width: 8),
          ],
          if (showAction)
            _TitleAction(
              label: actionLabel,
              icon: icon,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

class _TitleAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _TitleAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: colors.cream,
        shape: CircleBorder(
          side: BorderSide(color: colors.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: colors.ink),
          ),
        ),
      ),
    );
  }
}

class GuideWordmark extends StatelessWidget {
  const GuideWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Text.rich(
      TextSpan(
        style: GuideType.wordmark(colors),
        children: [
          TextSpan(text: S.of(context).guide_brand_lead),
          TextSpan(
            text: S.of(context).guide_brand_name,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              color: colors.madder,
            ),
          ),
        ],
      ),
    );
  }
}

class GuideSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const GuideSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 12, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: GuideType.section(colors))),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: colors.moss,
                textStyle: const TextStyle(
                  fontFamily: GuideType.sans,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class GuidePhoto extends StatelessWidget {
  final String? path;

  /// Book photo used when [path] is not a file on this phone.
  final String? cover;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;
  final Color? background;

  const GuidePhoto({
    super.key,
    required this.path,
    this.cover,
    required this.width,
    required this.height,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: background ?? GuideColors.of(context).paper2,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: path == null && (cover == null || cover!.isEmpty)
            ? placeholder
            : getImage(
                path ?? cover!,
                placeholder,
                cover: path == null ? null : cover,
                width: width,
                height: height,
                fit: fit,
              ),
      ),
    );
  }
}

String guideListTitle(BuildContext context, GuideListCover cover) {
  if (cover.isFavorite) return S.of(context).guide_favorite_flowers;
  return cover.isNew ? S.of(context).guide_new_in_book : cover.title;
}

/// "1 plant", "2 plants", and the matching form in each language.
String guidePlantPhrase(BuildContext context, int count) {
  final formatted = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toString(),
  ).format(count);
  return S.of(context).guide_plants(count).replaceFirst('$count', formatted);
}

String guideListSubtitle(BuildContext context, GuideListCover cover) {
  if (cover.isNew) {
    final latest = cover.latest;
    if (latest == null) return '';
    return S.of(context).guide_latest(
          MaterialLocalizations.of(context).formatMediumDate(latest),
        );
  }
  if (cover.year != null) {
    return S.of(context).guide_years(cover.count, cover.year!);
  }
  return guidePlantPhrase(context, cover.count);
}

/// Book cards name the whole span. Find covers keep the newest year only.
String guideBookListSubtitle(BuildContext context, GuideListCover cover) {
  if (cover.isNew) {
    final latest = cover.latest;
    if (latest == null) return guidePlantPhrase(context, cover.count);
    return S.of(context).guide_new_span(
          guidePlantPhrase(context, cover.count),
          MaterialLocalizations.of(context).formatMediumDate(latest),
        );
  }
  final from = cover.yearFrom;
  final to = cover.year;
  if (from != null && to != null && from != to) {
    return S.of(context).guide_year_span(cover.count, from, to);
  }
  return guideListSubtitle(context, cover);
}

String guideWhen(BuildContext context, DateTime when) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatMediumDate(when);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when));
  return '$date, $time';
}

bool _sameDay(DateTime when, DateTime now) {
  return when.year == now.year &&
      when.month == now.month &&
      when.day == now.day;
}

/// [todayLabel] on the same calendar day. The date otherwise.
String guidePhotoDay(
  BuildContext context,
  DateTime when, {
  DateTime? now,
  required String todayLabel,
}) {
  if (_sameDay(when, now ?? DateTime.now())) return todayLabel;
  return MaterialLocalizations.of(context).formatShortDate(when);
}

/// Clock time on the same calendar day. Date and clock time otherwise.
String guidePhotoMoment(BuildContext context, DateTime when, {DateTime? now}) {
  final localizations = MaterialLocalizations.of(context);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when));
  if (_sameDay(when, now ?? DateTime.now())) return time;
  return '${localizations.formatShortDate(when)}, $time';
}

/// A vernacular name, or the Latin name when [label] is missing.
bool guideNameIsVernacular(String? label) => label != null && label.isNotEmpty;

TextStyle guideNameStyle(
  GuideColors colors, {
  required bool named,
  double size = 13,
}) {
  if (named) {
    return TextStyle(
      fontFamily: GuideType.sans,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.2,
      color: colors.ink,
    );
  }
  return GuideType.latin(colors).copyWith(fontSize: size, height: 1.2);
}

class GuideName extends StatelessWidget {
  final String? label;
  final String latinName;
  final double size;
  final int maxLines;

  const GuideName({
    super.key,
    required this.label,
    required this.latinName,
    this.size = 13,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final named = guideNameIsVernacular(label);
    return Text(
      named ? label! : latinName,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: guideNameStyle(
        GuideColors.of(context),
        named: named,
        size: size,
      ),
    );
  }
}

class GuideKeyScaffold extends StatelessWidget {
  final Widget child;

  /// Habitat and petal keep the Find, Book, and Seen bar, with the banner
  /// pinned above it. The result list does not.
  final bool withTabs;

  const GuideKeyScaffold({
    super.key,
    required this.child,
    this.withTabs = false,
  });

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      navigationColor: (colors) => withTabs ? colors.cream : colors.paper,
      child: guideChromeFrame(
        context,
        index: 0,
        tabs: withTabs,
        showAd: withTabs,
        onSelect: (index) => leaveGuideKeyForTab(context, index),
        child: child,
      ),
    );
  }
}

/// Landscape sidebar plus the page. Phone and iPad portrait return [child].
Widget guideWithRail(
  BuildContext context, {
  required Widget child,
  bool personOn = false,
  bool showAd = false,
  ValueChanged<int>? onSelect,
}) {
  if (!GuideWindow.of(context).wide) return child;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GuideSideRail(
        personOn: personOn,
        onSelect: onSelect ?? (index) => guideRailSelect(context, index),
        onPerson: () => guideRailPerson(context),
      ),
      Expanded(
        child: Column(
          children: [
            Expanded(child: child),
            if (showAd) const AppBannerAd(pinned: true),
          ],
        ),
      ),
    ],
  );
}

/// Phone tabs stay on the bottom. A wide window uses the leading rail.
///
/// iPhone Duo draws the status bar down one side, and Find, Book, and Seen
/// sit in that column, under the clock. The content column drops that side's
/// inset so a nested [SafeArea] does not pad it a second time. There is no
/// leading rail on that path: the side column is the only tab control.
Widget guideChromeFrame(
  BuildContext context, {
  required Widget child,
  required int index,
  required ValueChanged<int> onSelect,
  bool tabs = true,
  bool showAd = false,
  bool personOn = false,
}) {
  final wide = GuideWindow.of(context).wide;
  final chrome = GuideChrome.of(context);
  final crease = GuideFold.verticalCrease(context);
  if (crease != null && tabs && !wide) {
    // The hinge crosses the middle of a full-width bar, so Find and Book
    // stay on the left page and Seen stays on the right.
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: guideWithRail(
                context,
                personOn: personOn,
                showAd: false,
                onSelect: onSelect,
                child: child,
              ),
            ),
          ),
          if (showAd) const AppBannerAd(pinned: true),
          _GuideFoldTabs(
            index: index,
            personOn: personOn,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
  if (chrome.vertical) {
    if (!tabs) {
      return Scaffold(body: SafeArea(child: child));
    }
    final media = MediaQuery.of(context);
    final padding = chrome.onRight
        ? media.padding.copyWith(right: 0)
        : media.padding.copyWith(left: 0);
    final viewPadding = chrome.onRight
        ? media.viewPadding.copyWith(right: 0)
        : media.viewPadding.copyWith(left: 0);
    final content = MediaQuery(
      data: media.copyWith(padding: padding, viewPadding: viewPadding),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: child),
            if (showAd) const AppBannerAd(pinned: true),
          ],
        ),
      ),
    );
    final column = _GuideSideTabs(
      index: index,
      personOn: personOn,
      side: chrome.side,
      onRight: chrome.onRight,
      onSelect: onSelect,
    );
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: chrome.onRight
            ? [Expanded(child: content), column]
            : [column, Expanded(child: content)],
      ),
    );
  }
  return Scaffold(
    body: SafeArea(
      // Phone tabs pad the navigation-bar inset. A wide screen, and a page
      // without tabs, pads it here so the banner stays above the bar.
      bottom: wide || !tabs,
      child: guideWithRail(
        context,
        personOn: personOn,
        showAd: wide && showAd,
        onSelect: onSelect,
        child: child,
      ),
    ),
    bottomNavigationBar: wide || !tabs
        ? null
        : GuideBottomBar(
            index: index,
            personOn: personOn,
            showAd: showAd,
            onSelect: onSelect,
          ),
  );
}

/// Centers a bottom sheet as a card on a tablet. The phone sheet is unchanged.
Widget guideSheetAlign(BuildContext context, Widget sheet) {
  if (!GuideWindow.of(context).tablet) return sheet;
  return LayoutBuilder(
    builder: (context, constraints) {
      final spare = constraints.maxWidth - 64;
      final card = spare < 520 ? spare : 520.0;
      final limit = constraints.maxHeight * 0.88;
      final maxHeight = !constraints.maxHeight.isFinite
          ? 680.0
          : (limit < 680 ? limit : 680.0);
      return Center(
        child: SizedBox(
          width: card < 1 ? constraints.maxWidth : card,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: sheet,
          ),
        ),
      );
    },
  );
}

/// The visible word stays [label]. Screen readers also hear which tab this
/// is, so Book is not the same description as the Book heading.
String _tabSpoken(
  BuildContext context,
  String label,
  int index,
  int count, {
  int unconfirmed = 0,
}) {
  final place = MaterialLocalizations.of(context).tabLabel(
    tabIndex: index + 1,
    tabCount: count,
  );
  if (unconfirmed <= 0) return '$label, $place';
  final badge = unconfirmed > 99 ? '99+' : '$unconfirmed';
  return '$label, $place, $badge';
}

/// One tab in the semantics tree. The painted label stays the short word.
class _TabSemantics extends StatelessWidget {
  final String spoken;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  const _TabSemantics({
    required this.spoken,
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: spoken,
      excludeSemantics: true,
      onTap: onPressed,
      child: child,
    );
  }
}

/// Find, Book, and Seen. [showAd] pins the free-account banner above the tabs.
///
/// [personOn] is Account. None of these three icons is that page, so none
/// is selected.
class GuideBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final bool showAd;
  final bool personOn;

  const GuideBottomBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.showAd = false,
    this.personOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAd) const AppBannerAd(pinned: true),
        GuideTabBar(
          index: index,
          personOn: personOn,
          onSelect: onSelect,
        ),
      ],
    );
  }
}

const guideUnconfirmedBadgeKey = Key('guide-seen-unconfirmed');

/// The open tab’s pill. Same mark as the mushroom bar: a stadium behind
/// the icon, 64 wide when the column allows it.
const guideTabIndicatorKey = Key('guide-tab-indicator');

/// Light cream and [GuideColors.paper2] are a visible step apart. Dark
/// [GuideColors.paper2] sits on dark cream, so the stadium uses the photo
/// well, which is that same step on the dark bar.
Color _tabPill(GuideColors colors) {
  return colors.isDark ? colors.photoWell : colors.paper2;
}

/// A tab icon is selected only on the page it opens. Account is not one
/// of these pages.
bool _tabOn(int tab, int index, bool personOn) => !personOn && tab == index;

/// Find, Book, and Seen in equal thirds. Book is the center of the bar.
class _GuideFoldTabs extends StatelessWidget {
  final int index;
  final bool personOn;
  final ValueChanged<int> onSelect;

  const _GuideFoldTabs({
    required this.index,
    required this.onSelect,
    this.personOn = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rule = BorderSide(color: colors.rule);
    return ColoredBox(
      color: colors.cream,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 60,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final fold = GuideFold.verticalCrease(context, minPage: 80);
              final placed =
                  fold == null ? null : GuideFold.tabCenters(width: width);
              if (fold == null || placed == null || !width.isFinite) {
                return DecoratedBox(
                  decoration: BoxDecoration(border: Border(top: rule)),
                  child: GuideTabBar(
                    index: index,
                    personOn: personOn,
                    onSelect: onSelect,
                    framed: false,
                  ),
                );
              }
              final mirror = Directionality.of(context) != TextDirection.ltr;
              final List<double> centers;
              final List<int> indexes;
              if (mirror) {
                centers = [for (final center in placed) width - center]..sort();
                indexes = const [2, 1, 0];
              } else {
                centers = placed;
                indexes = const [0, 1, 2];
              }
              final creaseLeft = fold.leading;
              final creaseRight = fold.leading + fold.span;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: creaseLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: rule)),
                    ),
                  ),
                  Positioned(
                    left: creaseRight,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: rule)),
                    ),
                  ),
                  for (var slot = 0; slot < 3; slot++)
                    _foldTabSlot(
                      context,
                      width: width,
                      centers: centers,
                      indexes: indexes,
                      slot: slot,
                      creaseLeft: creaseLeft,
                      creaseRight: creaseRight,
                      selected: index,
                      personOn: personOn,
                      onSelect: onSelect,
                      colors: colors,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One tab. The glyph stays on [centers]. A tab that is off the crease
/// stops at the hinge. The middle tab is the center, so its target crosses it.
Widget _foldTabSlot(
  BuildContext context, {
  required double width,
  required List<double> centers,
  required List<int> indexes,
  required int slot,
  required double creaseLeft,
  required double creaseRight,
  required int selected,
  required bool personOn,
  required ValueChanged<int> onSelect,
  required GuideColors colors,
}) {
  final center = centers[slot];
  var left = slot == 0 ? 0.0 : (centers[slot - 1] + center) / 2;
  var right = slot == 2 ? width : (center + centers[slot + 1]) / 2;
  if (center <= creaseLeft) {
    if (right > creaseLeft) right = creaseLeft;
  } else if (center >= creaseRight && left < creaseRight) {
    left = creaseRight;
  }
  final span = right - left;
  if (span <= 0) return const SizedBox.shrink();
  final room = math.min(center - left, right - center);
  final visual = room <= 0 ? span : math.min(span, room * 2);
  // Alignment moves the child by a fraction of the spare space, not of the
  // slot. Dividing by the slot width leaves the glyph short of [center].
  final spare = (span - visual) / 2;
  final align = Alignment(
    spare <= 0 ? 0 : ((center - (left + span / 2)) / spare).clamp(-1.0, 1.0),
    0,
  );
  final tab = indexes[slot];
  final strings = S.of(context);
  final items = [
    (strings.guide_tab_find, Icons.center_focus_weak),
    (strings.guide_tab_book, Icons.menu_book_outlined),
    (strings.guide_tab_seen, Icons.article_outlined),
  ];
  return Positioned(
    left: left,
    width: span,
    top: 0,
    bottom: 0,
    child: ValueListenableBuilder<int>(
      valueListenable: GuideTabs.unconfirmed,
      builder: (context, unconfirmed, _) {
        final on = _tabOn(tab, selected, personOn);
        final ink = on ? colors.moss : colors.ink3;
        return _TabSemantics(
          spoken: _tabSpoken(
            context,
            items[tab].$1,
            tab,
            items.length,
            unconfirmed: tab == 2 ? unconfirmed : 0,
          ),
          selected: on,
          onPressed: () => onSelect(tab),
          child: InkWell(
            onTap: () => onSelect(tab),
            excludeFromSemantics: true,
            child: Align(
              alignment: align,
              child: SizedBox(
                width: visual,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TabIcon(
                      icon: items[tab].$2,
                      color: ink,
                      selected: on,
                      unconfirmed: tab == 2 ? unconfirmed : 0,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[tab].$1,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: ink,
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
}

class GuideTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<int> indexes;
  final bool framed;
  final bool personOn;

  const GuideTabBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.indexes = const [0, 1, 2],
    this.framed = true,
    this.personOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GuideTabs.unconfirmed,
      builder: (context, unconfirmed, _) {
        final colors = GuideColors.of(context);
        final bottom = MediaQuery.paddingOf(context).bottom;
        final items = [
          (S.of(context).guide_tab_find, Icons.center_focus_weak),
          (S.of(context).guide_tab_book, Icons.menu_book_outlined),
          (S.of(context).guide_tab_seen, Icons.article_outlined),
        ];
        final row = SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final i in indexes)
                Expanded(
                  child: _TabSemantics(
                    spoken: _tabSpoken(
                      context,
                      items[i].$1,
                      i,
                      items.length,
                      unconfirmed: i == 2 ? unconfirmed : 0,
                    ),
                    selected: _tabOn(i, index, personOn),
                    onPressed: () => onSelect(i),
                    child: InkWell(
                      onTap: () => onSelect(i),
                      excludeFromSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TabIcon(
                            icon: items[i].$2,
                            color: _tabOn(i, index, personOn)
                                ? colors.moss
                                : colors.ink3,
                            selected: _tabOn(i, index, personOn),
                            unconfirmed: i == 2 ? unconfirmed : 0,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            items[i].$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _tabOn(i, index, personOn)
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _tabOn(i, index, personOn)
                                  ? colors.moss
                                  : colors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
        if (!framed) return row;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.cream,
            border: Border(top: BorderSide(color: colors.rule)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: row,
          ),
        );
      },
    );
  }
}

/// Find, Book, and Seen in the Duo status column. Bottom-aligned so the
/// clock and the Dynamic Island keep the top of that column.
class _GuideSideTabs extends StatelessWidget {
  final int index;
  final bool personOn;
  final double side;
  final bool onRight;
  final ValueChanged<int> onSelect;

  const _GuideSideTabs({
    required this.index,
    required this.side,
    required this.onRight,
    required this.onSelect,
    this.personOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GuideTabs.unconfirmed,
      builder: (context, unconfirmed, _) {
        final colors = GuideColors.of(context);
        final bottom = MediaQuery.paddingOf(context).bottom;
        final items = [
          (S.of(context).guide_tab_find, Icons.center_focus_weak),
          (S.of(context).guide_tab_book, Icons.menu_book_outlined),
          (S.of(context).guide_tab_seen, Icons.article_outlined),
        ];
        final rule = BorderSide(color: colors.rule);
        return DecoratedBox(
          key: const Key('guide-side-tabs'),
          decoration: BoxDecoration(
            color: colors.cream,
            border: Border(
              left: onRight ? rule : BorderSide.none,
              right: onRight ? BorderSide.none : rule,
            ),
          ),
          child: SizedBox(
            width: side,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _TabSemantics(
                        spoken: _tabSpoken(
                          context,
                          items[i].$1,
                          i,
                          items.length,
                          unconfirmed: i == 2 ? unconfirmed : 0,
                        ),
                        selected: _tabOn(i, index, personOn),
                        onPressed: () => onSelect(i),
                        child: InkWell(
                          onTap: () => onSelect(i),
                          excludeFromSemantics: true,
                          child: SizedBox(
                            height: 72,
                            width: double.infinity,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _TabIcon(
                                    icon: items[i].$2,
                                    color: _tabOn(i, index, personOn)
                                        ? colors.moss
                                        : colors.ink3,
                                    selected: _tabOn(i, index, personOn),
                                    unconfirmed: i == 2 ? unconfirmed : 0,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    items[i].$1,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.15,
                                      fontWeight: _tabOn(i, index, personOn)
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: _tabOn(i, index, personOn)
                                          ? colors.moss
                                          : colors.ink3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  final int unconfirmed;

  const _TabIcon({
    required this.icon,
    required this.color,
    required this.unconfirmed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: 24, color: color);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 64, maxHeight: 32),
      child: SizedBox(
        width: double.infinity,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  key: guideTabIndicatorKey,
                  decoration: BoxDecoration(
                    color: _tabPill(GuideColors.of(context)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  glyph,
                  if (unconfirmed > 0)
                    PositionedDirectional(
                      top: 1,
                      end: -8,
                      child: _UnconfirmedBadge(count: unconfirmed),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnconfirmedBadge extends StatelessWidget {
  final int count;

  const _UnconfirmedBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return DecoratedBox(
      key: guideUnconfirmedBadgeKey,
      decoration: BoxDecoration(
        color: GuideColors.of(context).madderFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

/// Find, Book, and Seen down the side, with Person at the bottom.
class GuideSideRail extends StatelessWidget {
  final bool personOn;
  final ValueChanged<int> onSelect;
  final VoidCallback onPerson;

  const GuideSideRail({
    super.key,
    required this.personOn,
    required this.onSelect,
    required this.onPerson,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final items = [
      (0, strings.guide_tab_find, Icons.center_focus_weak),
      (1, strings.guide_tab_book, Icons.menu_book_outlined),
      (2, strings.guide_tab_seen, Icons.article_outlined),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cream,
        border: BorderDirectional(end: BorderSide(color: colors.rule)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: 104,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ValueListenableBuilder<int>(
              valueListenable: GuideTabs.unconfirmed,
              builder: (context, unconfirmed, _) {
                return Column(
                  children: [
                    for (final item in items)
                      _RailButton(
                        label: item.$2,
                        icon: item.$3,
                        selected: _tabOn(item.$1, GuideTabs.index, personOn),
                        unconfirmed: item.$1 == 2 ? unconfirmed : 0,
                        tabIndex: item.$1,
                        tabCount: items.length,
                        onPressed: () => onSelect(item.$1),
                      ),
                    const Spacer(),
                    _RailButton(
                      label: strings.guide_offline_back,
                      icon: Icons.person_outline,
                      selected: personOn,
                      onPressed: onPerson,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final int unconfirmed;
  final int? tabIndex;
  final int tabCount;
  final VoidCallback onPressed;

  const _RailButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.unconfirmed = 0,
    this.tabIndex,
    this.tabCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final color = selected ? colors.moss : colors.ink3;
    final button = InkWell(
      onTap: onPressed,
      excludeFromSemantics: tabIndex != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            _TabIcon(
              icon: icon,
              color: color,
              selected: selected,
              unconfirmed: unconfirmed,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
    final index = tabIndex;
    if (index == null) return button;
    return _TabSemantics(
      spoken: _tabSpoken(
        context,
        label,
        index,
        tabCount,
        unconfirmed: unconfirmed,
      ),
      selected: selected,
      onPressed: onPressed,
      child: button,
    );
  }
}

class GuideBackButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const GuideBackButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: onPressed ?? () => Navigator.maybePop(context),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(color: colors.moss, size: 20),
                  child: BackButtonIcon(),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.moss,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
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

class GuideKeyStepper extends StatelessWidget {
  final int filled;

  const GuideKeyStepper({super.key, required this.filled});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i < filled ? colors.madderFill : colors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(height: 3),
            ),
          ),
        ],
      ],
    );
  }
}

class GuideFilterPill extends StatelessWidget {
  final Widget? leading;
  final String label;
  final VoidCallback onPressed;

  const GuideFilterPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Material(
      color: colors.mossFill,
      borderRadius: BorderRadius.circular(15),
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
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.close, size: 14, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void guideNoFlowers(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(S.of(context).snack_no_flowers)),
  );
}

class GuideViewSwitch extends StatelessWidget {
  final String photos;
  final String plates;
  final bool platesOn;
  final VoidCallback onPhotos;
  final VoidCallback onPlates;

  const GuideViewSwitch({
    super.key,
    required this.photos,
    required this.plates,
    required this.platesOn,
    required this.onPhotos,
    required this.onPlates,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colors.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, photos, !platesOn, onPhotos),
          _segment(context, plates, platesOn, onPlates),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onPressed,
  ) {
    final colors = GuideColors.of(context);
    return Material(
      color: on ? colors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: SizedBox(
            height: 28,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: on ? colors.onInk : colors.ink3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
