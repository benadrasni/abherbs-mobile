import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/shell/guide_actions.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/search/guide_search.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const guideBookFamiliesKey = Key('guide-book-families');
const guideBookGeneraKey = Key('guide-book-genera');
const guideBookListsKey = Key('guide-book-lists');

class BookPage extends StatefulWidget {
  final List<GuideListCover>? lists;

  /// The list read threw. [lists] stays null; an empty list is a real answer.
  final bool listsFailed;
  final VoidCallback? onRetryLists;

  /// Signed-in favorites. Shown on Lists only when [GuideListCover.count]
  /// is at least one. Find does not receive this cover.
  final GuideListCover? favorites;
  final GuideBookSegment segment;
  final ValueChanged<GuideBookSegment> onSegment;
  final VoidCallback onOpenFind;
  final Future<GuideBookTaxa> Function(String languageCode) loadTaxa;
  final Future<Map<String, GuideGenusNote>> Function(
      List<GuideSearchTaxon> genera) loadGenusNotes;
  final void Function(BuildContext context, String listPath)? onOpenTaxon;
  final void Function(BuildContext context, GuideListCover cover)? onOpenList;
  final VoidCallback? onSearch;

  const BookPage({
    super.key,
    required this.lists,
    this.listsFailed = false,
    this.onRetryLists,
    this.favorites,
    required this.segment,
    required this.onSegment,
    required this.onOpenFind,
    this.loadTaxa = loadGuideBookTaxa,
    this.loadGenusNotes = loadGuideGenusNotes,
    this.onOpenTaxon,
    this.onOpenList,
    this.onSearch,
  });

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  final ScrollController _scroll = ScrollController();
  String? _languageCode;
  GuideBookTaxa? _taxa;
  Map<String, GuideGenusNote> _genusNotes = {};
  bool _error = false;
  int _ticket = 0;
  int _noteTicket = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = Localizations.localeOf(context).languageCode;
    if (_languageCode == code) return;
    _languageCode = code;
    _taxa = null;
    _genusNotes = {};
    _error = false;
    _load();
  }

  @override
  void didUpdateWidget(BookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment == widget.segment) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (widget.segment == GuideBookSegment.genera) _loadNotes();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final code = _languageCode;
    if (code == null) return;
    final ticket = ++_ticket;
    try {
      final taxa = await widget.loadTaxa(code);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _taxa = taxa;
        _error = false;
      });
      _loadNotes();
    } catch (error) {
      debugPrint('guide book: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() => _error = true);
    }
  }

  void _retry() {
    setState(() {
      _error = false;
      _taxa = null;
      _genusNotes = {};
    });
    _load();
  }

  Future<void> _loadNotes() async {
    final genera = _taxa?.genera;
    if (genera == null) return;
    final ticket = ++_noteTicket;
    try {
      final notes = await widget.loadGenusNotes(genera);
      if (!mounted || ticket != _noteTicket) return;
      setState(() => _genusNotes = notes);
    } catch (error) {
      debugPrint('guide genus notes: $error');
    }
  }

  String? _genusNote(GuideSearchTaxon taxon) {
    if (widget.segment != GuideBookSegment.genera) return null;
    return guideGenusNoteText(S.of(context), _genusNotes[taxon.latinName]);
  }

  void _search() {
    final search = widget.onSearch;
    if (search != null) {
      search();
      return;
    }
    openGuideSearch(context, fromBook: true, onShowFind: widget.onOpenFind);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final counts = _counts(context);
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: GuideTitleBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).guide_tab_book,
                  style: GuideType.wordmark(colors),
                ),
                if (counts != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    counts,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ],
            ),
            actionLabel: S.of(context).guide_search,
            icon: Icons.search,
            onAction: _search,
          ),
        ),
        SliverToBoxAdapter(
          child: _Segments(
            segment: widget.segment,
            onChanged: widget.onSegment,
          ),
        ),
        _body(),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  String? _counts(BuildContext context) {
    final taxa = _taxa;
    if (taxa == null) return null;
    final format = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    return S.of(context).guide_book_counts(
          guidePlantPhrase(context, taxa.plants),
          format.format(taxa.families.length),
        );
  }

  void _openTaxon(BuildContext context, GuideSearchTaxon taxon) {
    final custom = widget.onOpenTaxon;
    if (custom != null) {
      custom(context, taxon.listPath);
      return;
    }
    openGuideTaxon(
      context,
      taxon.listPath,
      title: _taxonHeading(taxon),
      backLabel: S.of(context).guide_tab_book,
    );
  }

  Widget _body() {
    switch (widget.segment) {
      case GuideBookSegment.families:
      case GuideBookSegment.genera:
        if (_error) return _message(_retry);
        final taxa = _taxa;
        if (taxa == null) return _waiting();
        final rows = widget.segment == GuideBookSegment.families
            ? taxa.families
            : taxa.genera;
        return _taxonSliver(rows);
      case GuideBookSegment.lists:
        final lists = widget.lists;
        if (lists == null) {
          if (widget.listsFailed) {
            return _message(widget.onRetryLists ?? () {});
          }
          return _waiting();
        }
        final picked = widget.favorites;
        final leading = picked != null && picked.isFavorite && picked.count > 0
            ? picked
            : null;
        final ordered = [
          for (final cover in lists)
            if (!cover.isFavorite) cover,
        ]..sort(compareGuideLists);
        final slivers = <Widget>[
          if (leading != null)
            SliverPadding(
              padding: const EdgeInsets.only(top: 6),
              sliver: SliverToBoxAdapter(
                child: _listCard(context, leading),
              ),
            ),
          if (ordered.isNotEmpty)
            _listSliver(ordered, top: leading != null ? 0 : 6),
        ];
        if (slivers.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        if (slivers.length == 1) return slivers.single;
        return SliverMainAxisGroup(slivers: slivers);
    }
  }

  Widget _listSliver(List<GuideListCover> ordered, {required double top}) {
    final columns =
        GuideWindow.of(context).columns(phone: 1, tablet: 2, wide: 3);
    if (columns == 1) {
      return SliverPadding(
        padding: EdgeInsets.only(top: top),
        sliver: SliverList.builder(
          itemCount: ordered.length,
          itemBuilder: (context, index) => _listCard(context, ordered[index]),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(10, top, 10, 0),
      sliver: _chunkedSliver(
        count: ordered.length,
        columns: columns,
        item: (context, index) => _listCard(
          context,
          ordered[index],
          padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 12),
        ),
      ),
    );
  }

  Widget _taxonSliver(List<GuideSearchTaxon> rows) {
    final columns =
        GuideWindow.of(context).columns(phone: 1, tablet: 2, wide: 3);
    if (columns == 1) {
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final taxon = rows[index];
          return _TaxonRow(
            taxon: taxon,
            note: _genusNote(taxon),
            onTap: () => _openTaxon(context, taxon),
          );
        },
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      sliver: _chunkedSliver(
        count: rows.length,
        columns: columns,
        item: (context, index) {
          final taxon = rows[index];
          return _TaxonRow(
            taxon: taxon,
            note: _genusNote(taxon),
            onTap: () => _openTaxon(context, taxon),
            padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 10, 9),
          );
        },
      ),
    );
  }

  Widget _chunkedSliver({
    required int count,
    required int columns,
    required Widget Function(BuildContext context, int index) item,
  }) {
    final rows = (count / columns).ceil();
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, row) {
        final start = row * columns;
        Widget cell(int column) {
          final index = start + column;
          if (index >= count) return const SizedBox.shrink();
          return item(context, index);
        }

        final equal = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++)
              Expanded(child: cell(column)),
          ],
        );
        // The sliver is inset by 10, so the crease is measured from there.
        if (columns != 2) return equal;
        return GuideFoldSplit(
          originX: 10,
          crossAxisAlignment: CrossAxisAlignment.start,
          unsplit: equal,
          leading: cell(0),
          trailing: cell(1),
        );
      },
    );
  }

  Widget _listCard(
    BuildContext context,
    GuideListCover cover, {
    EdgeInsetsGeometry padding =
        const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
  }) {
    return _ListCard(
      cover: cover,
      padding: padding,
      onTap: () {
        final open = widget.onOpenList;
        if (open != null) {
          open(context, cover);
          return;
        }
        openGuideList(
          context,
          cover,
          backLabel: S.of(context).guide_tab_book,
        );
      },
    );
  }

  Widget _waiting() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _message(VoidCallback onRetry) {
    final colors = GuideColors.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: colors.ink2),
          child: Text(
            S.of(context).no_connection_content,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final GuideBookSegment segment;
  final ValueChanged<GuideBookSegment> onChanged;

  const _Segments({required this.segment, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final items = [
      (
        GuideBookSegment.families,
        S.of(context).guide_search_families,
        guideBookFamiliesKey,
      ),
      (
        GuideBookSegment.genera,
        S.of(context).guide_search_genera,
        guideBookGeneraKey,
      ),
      (
        GuideBookSegment.lists,
        S.of(context).guide_book_lists,
        guideBookListsKey,
      ),
    ];
    Widget bar(List<int> slots) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.rule),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Row(
            children: [
              for (final slot in slots)
                Expanded(
                  child: _Segment(
                    label: items[slot].$2,
                    selected: segment == items[slot].$1,
                    buttonKey: items[slot].$3,
                    onTap: () => onChanged(items[slot].$1),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GuideFoldSplit(
        crossAxisAlignment: CrossAxisAlignment.center,
        unsplit: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: bar(const [0, 1, 2]),
        ),
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, end: 6),
          child: bar(const [0, 1]),
        ),
        trailing: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, end: 20),
          child: bar(const [2]),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final Key buttonKey;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.buttonKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Material(
      key: buttonKey,
      color: selected ? colors.ink : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? colors.onInk : colors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line under a genus: in flower this month, and how many you’ve seen.
String? guideGenusNoteText(S strings, GuideGenusNote? note) {
  if (note == null || note.isEmpty) return null;
  final parts = <String>[
    if (note.inFlower > 0) strings.guide_in_flower_now(note.inFlower),
    if (note.seen > 0) strings.guide_you_have_seen(note.seen),
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String _taxonHeading(GuideSearchTaxon taxon) {
  final raw = guideTaxonTitle(taxon);
  final vernacular = raw == taxon.latinName ? null : raw;
  final distinct = vernacular != null &&
      foldSearch(vernacular) != foldSearch(taxon.latinName);
  return distinct ? vernacular : taxon.latinName;
}

class _TaxonRow extends StatelessWidget {
  final GuideSearchTaxon taxon;
  final String? note;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  const _TaxonRow({
    required this.taxon,
    required this.note,
    required this.onTap,
    this.padding = const EdgeInsetsDirectional.fromSTEB(20, 9, 20, 9),
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final title = _taxonHeading(taxon);
    final distinct = title != taxon.latinName;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            _Plate(
              path: guideFamilyIllustration(taxon.illustrationFamily),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: distinct
                        ? const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.2,
                          )
                        : GuideType.latin(colors).copyWith(
                            fontSize: 16,
                            height: 1.2,
                          ),
                  ),
                  if (distinct)
                    Text(
                      taxon.latinName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GuideType.latin(colors).copyWith(
                        fontSize: 13,
                        height: 1.2,
                        color: colors.ink3,
                      ),
                    ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${taxon.count}',
              style: TextStyle(fontSize: 12, color: colors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  final String? path;

  const _Plate({required this.path});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      child: GuidePhoto(
        path: path,
        width: 44,
        height: 44,
        radius: 8,
        fit: BoxFit.contain,
        background: colors.cream,
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final GuideListCover cover;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  const _ListCard({
    required this.cover,
    required this.onTap,
    this.padding = const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final favorite = cover.isFavorite;
    final photos = cover.thumbs.isNotEmpty
        ? cover.thumbs.take(4).toList()
        : (cover.photoPath == null ? const <String>[] : [cover.photoPath!]);
    return Padding(
      padding: padding,
      child: Material(
        color: colors.cream,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: cover.isNew ? colors.gold : colors.rule,
            width: cover.isNew ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photos.isNotEmpty) ...[
                  _Thumbs(
                    photos: photos,
                    slots: favorite ? photos.length.clamp(1, 4) : 4,
                  ),
                  const SizedBox(height: 10),
                ],
                Text.rich(
                  TextSpan(
                    children: [
                      if (favorite)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: Icon(
                              Icons.favorite,
                              size: 16,
                              color: colors.madder,
                            ),
                          ),
                        ),
                      TextSpan(
                        text: guideListTitle(context, cover),
                        style: const TextStyle(
                          fontFamily: GuideType.serif,
                          fontWeight: FontWeight.w500,
                          fontSize: 18,
                          height: 1.15,
                        ),
                      ),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.bottom,
                        child: SizedBox(width: 6),
                      ),
                      TextSpan(
                        text: guideBookListSubtitle(context, cover),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
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

class _Thumbs extends StatelessWidget {
  final List<String> photos;
  final int slots;

  const _Thumbs({required this.photos, this.slots = 4});

  @override
  Widget build(BuildContext context) {
    final count = slots < 1 ? 1 : slots;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: i < photos.length
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final side = constraints.maxWidth;
                        return GuidePhoto(
                          path: photos[i],
                          width: side,
                          height: side,
                          radius: 8,
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}
