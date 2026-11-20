import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/search/guide_search.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter/material.dart';

class GuideSearchPage extends StatefulWidget {
  final bool fromBook;
  final VoidCallback? onShowFind;
  final void Function(BuildContext context, String latinName) onOpenPlant;
  final void Function(BuildContext context, String listPath) onOpenTaxon;
  final void Function(BuildContext context) onOpenCamera;
  final Future<GuideSearchIndex> Function(String languageCode) loadIndex;
  final Future<GuidePlantCard> Function(String languageCode, int id) loadCard;

  const GuideSearchPage({
    super.key,
    this.fromBook = false,
    this.onShowFind,
    required this.onOpenPlant,
    required this.onOpenTaxon,
    required this.onOpenCamera,
    this.loadIndex = loadGuideSearchIndex,
    this.loadCard = loadGuidePlantCard,
  });

  @override
  State<GuideSearchPage> createState() => _GuideSearchPageState();
}

class _GuideSearchPageState extends State<GuideSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String? _languageCode;
  String _query = '';
  GuideSearchIndex? _index;
  bool _indexError = false;
  int _indexTicket = 0;
  final Map<String, GuidePlantCard> _cards = {};
  final Set<String> _loadingCards = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = Localizations.localeOf(context).languageCode;
    if (_languageCode == code) return;
    _languageCode = code;
    _index = peekGuideSearchIndex(code);
    _indexError = false;
    _cards.clear();
    _loadingCards.clear();
    if (_index == null) {
      _loadIndex();
    } else {
      _resolveCards();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() => _query = _controller.text);
    _resolveCards();
  }

  Future<void> _loadIndex() async {
    final code = _languageCode;
    if (code == null) return;
    final ticket = ++_indexTicket;
    try {
      final index = await widget.loadIndex(code);
      if (!mounted || ticket != _indexTicket) return;
      setState(() {
        _index = index;
        _indexError = false;
      });
      _resolveCards();
    } catch (error) {
      debugPrint('guide search: $error');
      if (!mounted || ticket != _indexTicket) return;
      setState(() => _indexError = true);
    }
  }

  void _resolveCards() {
    final index = _index;
    final lang = _languageCode;
    if (index == null || lang == null) return;
    final results = queryGuideSearch(index, _query);
    for (final plant in results.plants) {
      final key = '${getLanguageCode(lang)}/${plant.id}';
      if (_cards.containsKey(key) || !_loadingCards.add(key)) continue;
      widget.loadCard(lang, plant.id).then((card) {
        _loadingCards.remove(key);
        if (!mounted) return;
        setState(() => _cards[key] = card);
      }, onError: (Object error) {
        _loadingCards.remove(key);
        debugPrint('guide search card ${plant.id}: $error');
      });
    }
  }

  GuidePlantCard? _cardFor(GuideSearchPlant plant) {
    final lang = _languageCode;
    if (lang == null) return null;
    return _cards['${getLanguageCode(lang)}/${plant.id}'];
  }

  String? _label(GuideSearchPlant plant) {
    final fetched = _cardFor(plant)?.label;
    if (fetched != null && fetched.isNotEmpty) return fetched;
    final key = plant.labelKey;
    if (key == null || key.isEmpty) return null;
    return key;
  }

  void _logOpenedSearch() {
    final index = _index;
    if (index == null) return;
    final results = queryGuideSearch(index, _query);
    unawaited(GuideAnalytics.search(
      term: _query,
      resultCount: results.plants.length +
          results.genera.length +
          results.families.length,
    ));
  }

  String _latin(GuideSearchPlant plant) {
    final name = _cardFor(plant)?.latinName;
    if (name != null && name.isNotEmpty) return name;
    return displayLatin(plant.latinKey);
  }

  Future<void> _openPlant(GuideSearchPlant plant) async {
    final lang = _languageCode;
    if (lang == null) return;
    final key = '${getLanguageCode(lang)}/${plant.id}';
    GuidePlantCard? card = _cards[key];
    if (card == null) {
      try {
        card = await widget.loadCard(lang, plant.id);
      } catch (error) {
        debugPrint('guide search card ${plant.id}: $error');
      }
    }
    if (!mounted) return;
    _logOpenedSearch();
    final name = card?.latinName;
    widget.onOpenPlant(
      context,
      name != null && name.isNotEmpty ? name : displayLatin(plant.latinKey),
    );
  }

  void _keyOut() {
    final showFind = widget.onShowFind;
    Navigator.maybePop(context);
    showFind?.call();
  }

  @override
  Widget build(BuildContext context) {
    final backLabel = widget.fromBook
        ? S.of(context).guide_tab_book
        : S.of(context).guide_tab_find;
    return GuideTheme(
      child: Scaffold(
        body: guideWithRail(
          context,
          child: SafeArea(
            child: GuideReadable(
              child: Column(
                children: [
                  GuideBackButton(label: backLabel),
                  _QueryField(controller: _controller),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_indexError) {
      return _IndexError(onRetry: _loadIndex);
    }
    final index = _index;
    if (index == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (foldSearch(_query).isEmpty) return const SizedBox.shrink();
    final results = queryGuideSearch(index, _query);
    if (results.isEmpty) {
      return _Empty(
        onPhoto: () => widget.onOpenCamera(context),
        onKey: _keyOut,
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        if (results.plants.isNotEmpty) ...[
          _SectionLabel(S.of(context).guide_search_plants),
          for (final plant in results.plants)
            _ResultRow(
              title: _label(plant),
              latin: _latin(plant),
              photoPath: _cardFor(plant)?.photoPath,
              plate: false,
              onTap: () => _openPlant(plant),
            ),
        ],
        if (results.genera.isNotEmpty) ...[
          _SectionLabel(S.of(context).guide_search_genera),
          for (final taxon in results.genera) _taxonRow(taxon),
        ],
        if (results.families.isNotEmpty) ...[
          _SectionLabel(S.of(context).guide_search_families),
          for (final taxon in results.families) _taxonRow(taxon),
        ],
      ],
    );
  }

  Widget _taxonRow(GuideSearchTaxon taxon) {
    final raw = taxon.vernaculars.isEmpty ? '' : taxon.vernaculars.first.trim();
    final same =
        raw.isNotEmpty && foldSearch(raw) == foldSearch(taxon.latinName);
    final vernacular = raw.isEmpty || same ? null : raw;
    return _ResultRow(
      title: vernacular ?? taxon.latinName,
      latin: vernacular == null ? null : taxon.latinName,
      photoPath: taxon.illustrationFamily.isEmpty
          ? null
          : storageFamilies + taxon.illustrationFamily + defaultExtension,
      plate: true,
      count: taxon.count,
      onTap: () {
        _logOpenedSearch();
        widget.onOpenTaxon(context, taxon.listPath);
      },
    );
  }
}

class _QueryField extends StatelessWidget {
  final TextEditingController controller;

  const _QueryField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.moss, width: 1.5),
        ),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search, size: 20, color: colors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  cursorColor: colors.moss,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(fontSize: 16, color: colors.ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: S.of(context).guide_search_hint,
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: colors.ink3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 2),
      child: Text(title.toUpperCase(), style: GuideType.eyebrow(colors)),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String? title;
  final String? latin;
  final String? photoPath;
  final bool plate;
  final int? count;
  final VoidCallback onTap;

  const _ResultRow({
    required this.title,
    required this.latin,
    required this.photoPath,
    required this.plate,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final named = title != null && title!.isNotEmpty;
    final showLatin = latin != null && latin!.isNotEmpty && latin != title;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 9, 20, 9),
        child: Row(
          children: [
            _Thumb(path: photoPath, plate: plate),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (named)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  if (showLatin)
                    Text(
                      latin!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GuideType.latin(colors).copyWith(
                        fontSize: named ? 13 : 16,
                        height: 1.2,
                        color: named ? colors.ink3 : colors.ink,
                      ),
                    ),
                ],
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(fontSize: 12, color: colors.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? path;
  final bool plate;

  const _Thumb({required this.path, required this.plate});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final photo = GuidePhoto(
      path: path,
      width: 44,
      height: 44,
      radius: 8,
      fit: plate ? BoxFit.contain : BoxFit.cover,
      background: plate ? colors.cream : colors.paper2,
    );
    if (!plate) return photo;
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      child: photo,
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onPhoto;
  final VoidCallback onKey;

  const _Empty({required this.onPhoto, required this.onKey});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final photo = S.of(context).guide_search_try_photo;
    final key = S.of(context).guide_search_key;
    final sentence = S.of(context).guide_search_empty(photo, key);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.paper2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colors.ink2,
            ),
            children: _spans(sentence, photo, key),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(String sentence, String photo, String key) {
    final spans = <InlineSpan>[];
    var rest = sentence;
    while (rest.isNotEmpty) {
      final photoAt = rest.indexOf(photo);
      final keyAt = rest.indexOf(key);
      final photoFirst = photoAt >= 0 && (keyAt < 0 || photoAt <= keyAt);
      final at = photoFirst ? photoAt : keyAt;
      if (at < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      final token = photoFirst ? photo : key;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _Link(
            text: token,
            onTap: photoFirst ? onPhoto : onKey,
          ),
        ),
      );
      rest = rest.substring(at + token.length);
    }
    return spans;
  }
}

class _Link extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _Link({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: colors.moss,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }
}

class _IndexError extends StatelessWidget {
  final VoidCallback onRetry;

  const _IndexError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: colors.ink2),
          child: Text(
            S.of(context).no_connection_content,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }
}
