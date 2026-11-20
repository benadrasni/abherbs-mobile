import 'dart:async';
import 'dart:io';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_favorites.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/species/schema_page.dart';
import 'package:abherbs_flutter/camera/outside_page.dart';
import 'package:abherbs_flutter/person/sign_in_page.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/species/fullscreen.dart';
import 'package:abherbs_flutter/data/guide_photo_pick.dart';
import 'package:abherbs_flutter/data/guide_photo_file.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/shell/review_prompt.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_picker/country_picker.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

typedef GuideImageBuilder = Widget Function(
  String path,
  BoxFit fit,
  double width,
  double height,
);

typedef GuideVideoBuilder = Widget Function(GuideVideo video);

Widget guideSpeciesImage(
  String path,
  BoxFit fit,
  double width,
  double height,
) {
  return Builder(
    builder: (context) => getImage(
      path,
      ColoredBox(color: GuideColors.of(context).paper2),
      width: width,
      height: height,
      fit: fit,
    ),
  );
}

/// The guide species page. A one-plant notification uses this route.
MaterialPageRoute<void> guideSpeciesRoute(
  String name, {
  GuideCameraPending? pending,
  bool named = false,
  Future<void> Function()? onConfirmPending,
  Future<void> Function()? onUndoPending,
  Future<void> Function(String name)? onRetargetPending,
  VoidCallback? onSearchBook,
}) {
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: guideSpeciesRouteName),
    builder: (context) => GuideSpeciesPage(
      name: name,
      pending: pending,
      named: named,
      load: (languageCode) => loadGuideSpecies(name, languageCode),
      onShowSeen: GuideTabs.showSeen,
      onConfirmPending: onConfirmPending,
      onUndoPending: onUndoPending,
      onRetargetPending: onRetargetPending,
      onSearchBook: onSearchBook,
    ),
  );
}

/// A notification for one plant. An empty name opens nothing.
MaterialPageRoute<void>? guideNotificationPlantRoute(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return guideSpeciesRoute(trimmed);
}

Future<void> openGuidePlant(
  BuildContext context,
  String name, {
  String source = '',
  GuideCameraPending? pending,
  Future<void> Function()? onConfirmPending,
  Future<void> Function()? onUndoPending,
  Future<void> Function(String name)? onRetargetPending,
  VoidCallback? onSearchBook,
}) {
  unawaited(GuideAnalytics.plant(name, source: source));
  return Navigator.push(
    context,
    guideSpeciesRoute(
      name,
      pending: pending,
      named: source == GuidePlantSource.photo ||
          source == GuidePlantSource.outside,
      onConfirmPending: onConfirmPending,
      onUndoPending: onUndoPending,
      onRetargetPending: onRetargetPending,
      onSearchBook: onSearchBook,
    ),
  );
}

class GuideSpeciesPage extends StatefulWidget {
  final String name;
  final GuideSpecies? initial;
  final Future<GuideSpecies?> Function(String languageCode) load;
  final Future<void> Function(GuideSeenDraft draft)? saveSeen;
  final Future<GuideSeenPhoto?> Function(String plant)? pickPhoto;

  /// Replaces the notebook check in tests. True is a signed-in account or
  /// the anonymous guest. False opens sign-in and does not create a guest.
  /// Favorites use this hook when a test sets it, and [Auth.appUser] otherwise.
  final bool Function()? isSignedIn;
  final Future<void> Function(BuildContext context)? onSignIn;

  /// Replaces the favorites read in tests. The id is the catalog plant id.
  final bool Function(String plantId)? favoriteOf;

  /// Replaces [setGuideFavorite] in tests.
  final Future<void> Function(String plantId, bool on)? onFavorite;
  final VoidCallback? onShowSeen;
  final GuideImageBuilder? imageBuilder;
  final GuideVideoBuilder? videoBuilder;
  final int? month;
  final GuideCameraPending? pending;

  /// A photo or an outside-the-book name just opened this page.
  final bool named;
  final Future<void> Function()? onConfirmPending;
  final Future<void> Function()? onUndoPending;
  final Future<void> Function(String name)? onRetargetPending;
  final VoidCallback? onSearchBook;

  const GuideSpeciesPage({
    super.key,
    required this.name,
    required this.load,
    this.initial,
    this.saveSeen,
    this.pickPhoto,
    this.isSignedIn,
    this.onSignIn,
    this.favoriteOf,
    this.onFavorite,
    this.onShowSeen,
    this.imageBuilder,
    this.videoBuilder,
    this.month,
    this.pending,
    this.named = false,
    this.onConfirmPending,
    this.onUndoPending,
    this.onRetargetPending,
    this.onSearchBook,
  });

  @override
  State<GuideSpeciesPage> createState() => _GuideSpeciesPageState();
}

class _GuideSpeciesPageState extends State<GuideSpeciesPage> {
  final Map<String, GlobalKey> _sectionKeys = {};
  GuideSpecies? _species;
  GuideSpeciesSeen? _seen;
  bool _started = false;
  bool _loading = true;
  bool _missing = false;
  bool _failed = false;
  bool _saving = false;
  bool _kept = false;
  bool _pendingBusy = false;
  bool _favoriteBusy = false;
  bool? _favoriteOn;
  bool _namedNoted = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    Purchases.namesRevision.addListener(_onPlan);
    if (widget.favoriteOf == null) {
      guideFavoriteIds.addListener(_onFavoriteIds);
    }
  }

  @override
  void dispose() {
    Purchases.namesRevision.removeListener(_onPlan);
    if (widget.favoriteOf == null) {
      guideFavoriteIds.removeListener(_onFavoriteIds);
    }
    super.dispose();
  }

  void _onFavoriteIds() {
    if (!mounted) return;
    final id = _species?.id;
    setState(() {
      _favoriteOn = id == null ? null : guideFavoriteIds.value.contains(id);
    });
  }

  void _onPlan() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final initial = widget.initial;
    if (initial != null) {
      _species = initial;
      _seen = initial.seen;
      _loading = false;
      _bindKeys(initial);
      _noteNamed();
      return;
    }
    _load();
  }

  int get _month => widget.month ?? DateTime.now().month;

  /// The page is still the one on screen. A plant pushed on top, or a page
  /// the person already left, is not a place for the sheet.
  bool _reviewStillHere() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return route?.isCurrent ?? false;
  }

  /// A named photo stays on this page. The sheet waits out the pause, and
  /// only if the page is still the one on screen.
  void _noteNamed() {
    if (_namedNoted || _species == null) return;
    if (!widget.named && widget.pending == null) return;
    _namedNoted = true;
    unawaited(ReviewPrompt.note(stillHere: _reviewStillHere));
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    final languageCode = Localizations.localeOf(context).languageCode;
    try {
      final species = await widget.load(languageCode);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _species = species;
        _seen = species?.seen;
        _missing = species == null;
        _failed = false;
        _loading = false;
        if (species != null) _bindKeys(species);
      });
      _noteNamed();
    } catch (error) {
      debugPrint('guide species ${widget.name}: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _missing = false;
      _loading = true;
    });
    _load();
  }

  void _bindKeys(GuideSpecies species) {
    final ids = [
      for (final section in species.sections) section.id,
      'taxonomy',
      'distribution',
      'sightings',
    ];
    for (final id in ids) {
      _sectionKeys.putIfAbsent(id, GlobalKey.new);
    }
  }

  void _jump(String id) {
    final target = _sectionKeys[id]?.currentContext;
    if (target == null) return;
    final position = Scrollable.of(target).position;
    // Phone pills pin below the status bar. Land the section under that cover.
    // Tablet pills scroll away, so keep a little air at the top.
    final cover = GuideWindow.of(context).tablet
        ? 0.0
        : MediaQuery.paddingOf(context).top + _galleryPillHeight + 24;
    final alignment = cover == 0
        ? 0.16
        : ((cover + 16) / position.viewportDimension).clamp(0.0, 0.5);
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: alignment,
    );
  }

  bool _hasNotebook() {
    final check = widget.isSignedIn;
    if (check != null) return check();
    return guideNotebookUser() != null;
  }

  Future<void> _addSeen() async {
    if (_saving) return;
    if (!_hasNotebook()) {
      if (widget.isSignedIn == null) await Auth.startGuest();
      if (!mounted) return;
      if (!_hasNotebook()) {
        final signIn = widget.onSignIn ?? _openSignIn;
        await signIn(context);
        if (!mounted || !_hasNotebook()) return;
      }
    }
    if (!mounted) return;
    await _addPhoto();
  }

  Future<void> _addPhoto() async {
    setState(() => _saving = true);
    try {
      final pick = widget.pickPhoto ?? pickGuideSeenPhoto;
      final photo = await pick(widget.name);
      if (!mounted || photo == null || photo.relativePath.isEmpty) return;
      await _commit(photo, alreadySaving: true);
    } catch (error) {
      debugPrint('guide add seen ${widget.name}: $error');
      _showFailure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commit(
    GuideSeenPhoto photo, {
    bool alreadySaving = false,
  }) async {
    if (photo.relativePath.isEmpty) return;
    if (!alreadySaving) setState(() => _saving = true);
    final draft = GuideSeenDraft(
      plant: _species?.name ?? widget.name,
      when: photo.when,
      latitude: photo.latitude,
      longitude: photo.longitude,
      photoPath: photo.relativePath,
      fromPhoto: photo.fromPhoto,
    );
    try {
      final save = widget.saveSeen ?? saveGuideSeen;
      await save(draft);
      unawaited(GuideAnalytics.seenSave(
        source: draft.fromPhoto ? 'photo' : 'manual',
        shared: false,
      ));
      if (!mounted) return;
      setState(() => _seen = guideSeenAfterAdd(_seen, draft));
      GuideTabs.refreshSeen?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          draft.fromPhoto
              ? S.of(context).guide_added_seen_photo
              : S.of(context).guide_added_seen,
        ),
      ));
      unawaited(ReviewPrompt.note(stillHere: _reviewStillHere));
    } catch (error) {
      debugPrint('guide save seen ${widget.name}: $error');
      _showFailure();
    } finally {
      if (mounted && !alreadySaving) setState(() => _saving = false);
    }
  }

  void _showFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).guide_seen_failed)),
    );
  }

  void _showSeen() {
    final show = widget.onShowSeen;
    if (show == null) return;
    Navigator.popUntil(context, (route) => route.isFirst);
    show();
  }

  Future<void> _keepPending() async {
    if (_pendingBusy || _kept || widget.pending == null) return;
    setState(() => _pendingBusy = true);
    try {
      await widget.onConfirmPending?.call();
      if (!mounted) return;
      setState(() => _kept = true);
      GuideTabs.refreshSeen?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_camera_confirmed)),
      );
    } catch (error) {
      debugPrint('guide species keep: $error');
      _showFailure();
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Future<void> _undoPending() async {
    if (_pendingBusy || !_kept) return;
    setState(() => _pendingBusy = true);
    try {
      await widget.onUndoPending?.call();
      if (!mounted) return;
      setState(() => _kept = false);
      GuideTabs.refreshSeen?.call();
    } catch (error) {
      debugPrint('guide species undo: $error');
      _showFailure();
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Future<void> _notThis() async {
    final pending = widget.pending;
    if (_pendingBusy || pending == null || _kept) return;
    final chosen = await showGuideOtherNames(
      context: context,
      candidates: pending.others,
      onSearch: widget.onSearchBook,
    );
    if (!mounted || chosen == null) return;
    final name = guideCameraSpeciesName(chosen);
    if (name == null) return;
    setState(() => _pendingBusy = true);
    try {
      await widget.onRetargetPending?.call(name);
      if (!mounted) return;
      unawaited(GuideAnalytics.plant(
        name,
        source: GuidePlantSource.photo,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_outside_changed)),
      );
      final showSeen = widget.onShowSeen;
      final imageBuilder = widget.imageBuilder;
      final videoBuilder = widget.videoBuilder;
      final month = widget.month;
      final signedIn = widget.isSignedIn;
      final signIn = widget.onSignIn;
      final favoriteOf = widget.favoriteOf;
      final onFavorite = widget.onFavorite;
      final saveSeen = widget.saveSeen;
      final pickPhoto = widget.pickPhoto;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: guideSpeciesRouteName),
          builder: (context) => GuideSpeciesPage(
            name: name,
            load: (languageCode) => loadGuideSpecies(name, languageCode),
            onShowSeen: showSeen,
            imageBuilder: imageBuilder,
            videoBuilder: videoBuilder,
            month: month,
            isSignedIn: signedIn,
            onSignIn: signIn,
            favoriteOf: favoriteOf,
            onFavorite: onFavorite,
            saveSeen: saveSeen,
            pickPhoto: pickPhoto,
          ),
        ),
      );
    } catch (error) {
      debugPrint('guide species retarget: $error');
      _showFailure();
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  bool _canFavorite(GuideSpecies species) {
    final id = species.id;
    return id != null && id.isNotEmpty;
  }

  bool _favoriteMarked(String? id) {
    if (id == null || id.isEmpty) return false;
    final chosen = _favoriteOn;
    if (chosen != null) return chosen;
    final of = widget.favoriteOf;
    if (of != null) return of(id);
    return guideFavoriteIds.value.contains(id);
  }

  bool _accountSignedIn() {
    final check = widget.isSignedIn;
    if (check != null) return check();
    return Auth.appUser != null;
  }

  Future<void> _toggleFavorite(GuideSpecies species) async {
    final id = species.id;
    if (id == null || id.isEmpty || _favoriteBusy) return;
    if (!_accountSignedIn()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_favorite_account)),
      );
      final open = widget.onSignIn ?? _openSignIn;
      await open(context);
      if (!mounted || !_accountSignedIn()) return;
      await _writeFavorite(id, true);
      return;
    }
    await _writeFavorite(id, !_favoriteMarked(id));
  }

  Future<void> _writeFavorite(String id, bool on) async {
    setState(() {
      _favoriteBusy = true;
      _favoriteOn = on;
    });
    try {
      final write = widget.onFavorite ?? setGuideFavorite;
      await write(id, on);
      unawaited(GuideAnalytics.favorite(on: on));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            on
                ? S.of(context).guide_favorite_added
                : S.of(context).guide_favorite_removed,
          ),
        ),
      );
    } catch (error) {
      debugPrint('guide favorite $id: $error');
      if (mounted) setState(() => _favoriteOn = null);
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _share(GuideSpecies species) async {
    final title = species.hasVernacular ? species.label!.trim() : species.name;
    await SharePlus.instance.share(ShareParams(
      text: webPlantUrl(
        species.name,
        Localizations.localeOf(context).languageCode,
      ),
      subject: title,
    ));
  }

  void _openPhoto(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenPage(path),
        settings: const RouteSettings(name: 'FullScreen'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      child: Scaffold(
        body: guideWithRail(
          context,
          // The photo still runs under a top status bar. A side column, as on
          // iPhone Duo, keeps the plate and the text off the clock.
          child: SafeArea(
            top: false,
            bottom: false,
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final colors = GuideColors.of(context);
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.moss,
          ),
        ),
      );
    }
    if (_failed || _missing) {
      final strings = S.of(context);
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GuideBackButton(label: strings.guide_back),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _missing
                          ? strings.guide_species_missing
                          : strings.guide_species_failed,
                      style: TextStyle(color: colors.ink2),
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _retry,
                        child: Text(strings.guide_results_retry),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    final page = _content(context, _species!);
    final pending = widget.pending;
    if (pending == null) return page;
    return Column(
      children: [
        Expanded(child: page),
        _PendingBar(
          pending: pending,
          species: _species!,
          kept: _kept,
          onKeep: _pendingBusy ? null : _keepPending,
          onNotIt: _pendingBusy ? null : _notThis,
          onUndo: _pendingBusy ? null : _undoPending,
        ),
      ],
    );
  }

  Widget _content(BuildContext context, GuideSpecies species) {
    final strings = S.of(context);
    final colors = GuideColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final notes = species.sectionById('trivia');
    final uses = species.sectionById('herbalism');
    final chips = <({String id, String label})>[
      if (notes != null) (id: 'trivia', label: strings.guide_notes),
      for (final section in species.sections)
        if (section.id != 'trivia' && section.id != 'herbalism')
          (id: section.id, label: _sectionTitle(strings, section.id)),
      if (uses != null) (id: 'herbalism', label: strings.plant_herbalism),
      (id: 'taxonomy', label: strings.guide_taxonomy),
      (id: 'distribution', label: strings.guide_distribution),
      (id: 'sightings', label: strings.guide_sightings),
    ];
    final range = guideFloweringRange(
      species.floweringFrom,
      species.floweringTo,
      (month) => DateFormat.MMMM(locale).format(DateTime(2000, month)),
    );
    final window = GuideWindow.of(context);
    final size = MediaQuery.sizeOf(context);
    // Open iPhone Duo landscape is a tablet at about 951 points, short of
    // the 1000-point wide bar. The photo and the article still sit side by
    // side, the same split a wide iPad uses.
    final sideBySide =
        window.wide || (window.tablet && size.width > size.height);
    final galleryHeight = sideBySide ? 440.0 : (window.tablet ? 460.0 : 420.0);
    final head = <Widget>[
      _Gallery(
        species: species,
        image: _image,
        height: galleryHeight,
        onBack: () => Navigator.maybePop(context),
        onShare: widget.pending == null || _kept ? () => _share(species) : null,
        favorite: _favoriteMarked(species.id),
        onFavorite:
            _canFavorite(species) ? () => _toggleFavorite(species) : null,
        onOpen: _openPhoto,
        videoBuilder: widget.videoBuilder,
      ),
      _NameBlock(species: species),
      if (widget.pending == null && _seen != null)
        _SeenByYou(
          seen: _seen!,
          locale: locale,
          onPressed: _showSeen,
          image: _image,
        ),
      if (widget.pending == null)
        _AddSeenButton(saving: _saving, onPressed: _addSeen),
      _Facts(
        species: species,
        range: range,
        month: _month,
        locale: locale,
      ),
    ];
    final sections = <Widget>[
      if (species.description != null)
        SliverToBoxAdapter(child: _Lead(text: species.description!)),
      if (notes != null)
        SliverToBoxAdapter(
          child: _Aside(
            key: _sectionKeys['trivia'],
            boxKey: const Key('guide-aside-trivia'),
            title: strings.guide_notes,
            text: notes.text,
            accent: colors.gold,
            top: 14,
          ),
        ),
      for (final section in species.sections)
        if (section.id != 'trivia' && section.id != 'herbalism')
          SliverToBoxAdapter(
            child: _Section(
              key: _sectionKeys[section.id],
              title: _sectionTitle(strings, section.id),
              text: section.text,
              warn: section.id == 'toxicity',
              onOpen: section.id == 'flower' || section.id == 'inflorescence'
                  ? () => _openSchema(context, species, section.id)
                  : null,
              linkKey: section.id == 'flower'
                  ? guideSchemaFlowerKey
                  : section.id == 'inflorescence'
                      ? guideSchemaInflorescenceKey
                      : null,
            ),
          ),
      if (uses != null)
        SliverToBoxAdapter(
          child: _Aside(
            key: _sectionKeys['herbalism'],
            boxKey: const Key('guide-aside-herbalism'),
            title: strings.plant_herbalism,
            text: uses.text,
            disclaimer: strings.plant_herbalism_disclaimer,
            accent: colors.moss,
            top: 16,
          ),
        ),
      if (Purchases.showsAds()) const SliverToBoxAdapter(child: AppBannerAd()),
      SliverToBoxAdapter(
        child: _Taxonomy(
          key: _sectionKeys['taxonomy'],
          ranks: species.ranks,
        ),
      ),
      SliverToBoxAdapter(
        child: _Distribution(
          key: _sectionKeys['distribution'],
          path: species.mapPath,
        ),
      ),
      SliverToBoxAdapter(
        child: _Sightings(
          key: _sectionKeys['sightings'],
          sightings: species.sightings,
          locale: locale,
          image: _image,
          onOpen: _openPhoto,
        ),
      ),
      if (species.sources.isNotEmpty)
        SliverToBoxAdapter(child: _Sources(links: species.sources)),
      SliverToBoxAdapter(
        child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
      ),
    ];
    final jumps = SliverToBoxAdapter(
      child: _JumpWrap(chips: chips, onJump: _jump),
    );
    final crease = GuideFold.verticalCrease(context);
    if (crease != null) {
      // The crease is the gutter. The name stays on the photo's page, and
      // the article starts on the other page.
      return GuideFoldSplit(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        unsplit: const SizedBox.shrink(),
        leading: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          children: head,
        ),
        trailing: CustomScrollView(
          key: const Key('guide-species-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
              ),
              sliver: jumps,
            ),
            ...sections,
          ],
        ),
      );
    }
    if (sideBySide) {
      // The photo column still runs under the status bar. The right column
      // opens with the jump pills, so they take the same top inset the phone
      // cover uses, above the 12-point pad inside _JumpWrap.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 42,
            child: ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              children: head,
            ),
          ),
          Expanded(
            flex: 58,
            child: CustomScrollView(
              key: const Key('guide-species-scroll'),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top,
                  ),
                  sliver: jumps,
                ),
                ...sections,
              ],
            ),
          ),
        ],
      );
    }
    if (window.tablet) {
      return CustomScrollView(
        key: const Key('guide-species-scroll'),
        slivers: [
          for (final child in head) SliverToBoxAdapter(child: child),
          jumps,
          ...sections,
        ],
      );
    }
    // The photo still runs under the status bar. A pinned sliver would stick
    // at y = 0, which is underneath the clock.
    return _StatusBarJumpScroll(
      chips: chips,
      onJump: _jump,
      leading: head,
      trailing: sections,
    );
  }

  Widget _image(String path, BoxFit fit, double width, double height) {
    final build = widget.imageBuilder ?? guideSpeciesImage;
    return build(path, fit, width, height);
  }
}

Future<void> _openSignIn(BuildContext context) {
  return openGuideSignIn(context);
}

void _openSchema(BuildContext context, GuideSpecies species, String id) {
  final back = species.hasVernacular ? species.label!.trim() : species.name;
  final flower = id == 'flower';
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: RouteSettings(
        name: flower ? guideFlowerSchemaRouteName : guideInflorescenceRouteName,
      ),
      builder: (context) => flower
          ? GuideFlowerSchemaPage(backLabel: back)
          : GuideInflorescencePage(
              backLabel: back,
              types: species.inflorescenceTypes,
            ),
    ),
  );
}

String _sectionTitle(S strings, String id) {
  switch (id) {
    case 'flower':
      return strings.plant_flower;
    case 'inflorescence':
      return strings.plant_inflorescence;
    case 'fruit':
      return strings.plant_fruit;
    case 'leaf':
      return strings.plant_leaf;
    case 'stem':
      return strings.plant_stem;
    case 'habitat':
      return strings.plant_habitat;
    case 'toxicity':
      return strings.plant_toxicity;
    case 'herbalism':
      return strings.plant_herbalism;
    case 'trivia':
      return strings.guide_notes;
    default:
      return id;
  }
}

Future<GuideSeenPhoto?> pickGuideSeenPhoto(String plant) async {
  final user = await guideNotebookUserReady();
  if (user == null) return null;
  final access = await Permission.accessMediaLocation.status;
  if (!access.isGranted) {
    await Permission.accessMediaLocation.request();
  }
  final path = await pickGuideDevicePhoto(maxWidth: imageSizeScaleDown);
  if (path == null) return null;
  final bytes = await File(path).readAsBytes();
  final exifData = await readExifFromBytes(bytes);
  final dateTag =
      exifData['EXIF DateTimeOriginal'] ?? exifData['Image DateTime'];
  final latitude = getLatitudeFromExif(
    exifData['GPS GPSLatitudeRef'],
    exifData['GPS GPSLatitude'],
  );
  final longitude = getLongitudeFromExif(
    exifData['GPS GPSLongitudeRef'],
    exifData['GPS GPSLongitude'],
  );
  final names = plant.toLowerCase().split(' ');
  var prefix = 'unknown_';
  if (names.length > 1 && names[0].isNotEmpty && names[1].isNotEmpty) {
    prefix = '${names[0][0]}${names[1][0]}_';
  }
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  final suffix = dot > slash ? path.substring(dot) : defaultPhotoExtension;
  final filename = '$prefix${DateTime.now().millisecondsSinceEpoch}$suffix';
  final dir = '$storageObservations${user.uid}/${plant.replaceAll(' ', '_')}';
  final root = (await getApplicationDocumentsDirectory()).path;
  await Directory('$root/$dir').create(recursive: true);
  await copyGuidePhotoWithoutGps(path, '$root/$dir/$filename');
  return GuideSeenPhoto(
    relativePath: '$dir/$filename',
    when: getDateTimeFromExif(dateTag),
    latitude: latitude,
    longitude: longitude,
    fromPhoto: dateTag != null || latitude != 0 || longitude != 0,
  );
}

class _Gallery extends StatefulWidget {
  final GuideSpecies species;
  final GuideImageBuilder image;
  final double height;
  final VoidCallback onBack;
  final VoidCallback? onShare;
  final bool favorite;
  final VoidCallback? onFavorite;
  final ValueChanged<String> onOpen;
  final GuideVideoBuilder? videoBuilder;

  const _Gallery({
    required this.species,
    required this.image,
    required this.height,
    required this.onBack,
    required this.onShare,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    required this.videoBuilder,
  });

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final PageController _page = PageController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final species = widget.species;
    final slides = <_Slide>[
      for (final path in species.photoPaths) _Slide.photo(path),
      if (species.platePath != null) _Slide.plate(species.platePath!),
      for (final video in species.videos) _Slide.video(video),
    ];
    if (slides.isEmpty) slides.add(const _Slide.photo(null));
    final plateIndex =
        species.platePath == null ? -1 : species.photoPaths.length;
    final videoIndex = species.videos.isEmpty
        ? -1
        : species.photoPaths.length + (species.platePath == null ? 0 : 1);
    final top = MediaQuery.paddingOf(context).top + 10;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView(
            controller: _page,
            children: [
              for (final (index, slide) in slides.indexed)
                slide.video == null
                    ? GestureDetector(
                        onTap: slide.path == null
                            ? null
                            : () => widget.onOpen(slide.path!),
                        child: ColoredBox(
                          color:
                              slide.plate ? colors.plateWell : colors.photoWell,
                          child: slide.path == null
                              ? const SizedBox.expand()
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final title = species.hasVernacular
                                        ? species.label!.trim()
                                        : species.name;
                                    return Semantics(
                                      container: true,
                                      image: true,
                                      // Photos are "<title>, Tab n of m" and
                                      // are counted only among photographs.
                                      // The plate is not one of those, so the
                                      // slide is "<title>, Plate". The pill
                                      // stays "Plate".
                                      label: slide.plate
                                          ? '$title, ${strings.guide_plate}'
                                          : _indexedName(
                                              context,
                                              title,
                                              index,
                                              species.photoPaths.length,
                                            ),
                                      child: ExcludeSemantics(
                                        child: widget.image(
                                          slide.path!,
                                          slide.plate
                                              ? BoxFit.contain
                                              : BoxFit.cover,
                                          constraints.maxWidth,
                                          widget.height,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      )
                    : ColoredBox(
                        color: colors.photoWell,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              bottom: _galleryPillInset +
                                  _galleryPillHeight +
                                  _galleryVideoGap,
                            ),
                            child: widget.videoBuilder?.call(slide.video!) ??
                                _YoutubePlantVideo(
                                  key: ValueKey(
                                    'guide-video-${slide.video!.id}',
                                  ),
                                  video: slide.video!,
                                ),
                          ),
                        ),
                      ),
            ],
          ),
          PositionedDirectional(
            top: top,
            start: 12,
            end: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _OverlayButton(
                  label: strings.guide_back,
                  onPressed: widget.onBack,
                  icon: const BackButtonIcon(),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onFavorite != null)
                      _OverlayButton(
                        label: widget.favorite
                            ? strings.guide_favorite_remove
                            : strings.guide_favorite_add,
                        onPressed: widget.onFavorite!,
                        icon: Icon(
                          widget.favorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 20,
                          color: widget.favorite ? colors.madder : null,
                        ),
                      ),
                    if (widget.onFavorite != null && widget.onShare != null)
                      const SizedBox(width: 8),
                    if (widget.onShare != null)
                      _OverlayButton(
                        label: strings.guide_share,
                        onPressed: widget.onShare!,
                        icon: const Icon(Icons.ios_share, size: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PositionedDirectional(
            start: 12,
            bottom: _galleryPillInset,
            child: Row(
              children: [
                for (final pill in _galleryPills(
                  species: species,
                  strings: strings,
                  plateIndex: plateIndex,
                  videoIndex: videoIndex,
                  go: _go,
                ))
                  pill,
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _go(int index) {
    if (!_page.hasClients) return;
    _page.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }
}

const double _galleryPillInset = 12;
const double _galleryPillHeight = 48;
const double _galleryButtonExtent = 48;
const double _galleryVideoGap = 8;

class _Slide {
  final String? path;
  final bool plate;
  final GuideVideo? video;

  const _Slide.photo(this.path)
      : plate = false,
        video = null;

  const _Slide.plate(this.path)
      : plate = true,
        video = null;

  const _Slide.video(this.video)
      : path = null,
        plate = false;
}

List<Widget> _galleryPills({
  required GuideSpecies species,
  required S strings,
  required int plateIndex,
  required int videoIndex,
  required void Function(int index) go,
}) {
  final pills = <Widget>[];
  void add(Widget pill) {
    if (pills.isNotEmpty) pills.add(const SizedBox(width: 6));
    pills.add(pill);
  }

  if (species.photoPaths.isNotEmpty) {
    add(_Pill(
      label: species.photoPaths.length == 1
          ? strings.guide_photo_one
          : strings.guide_photo_count(species.photoPaths.length),
      filled: false,
      onPressed: () => go(0),
    ));
  }
  if (plateIndex >= 0) {
    add(_Pill(
      label: strings.guide_plate,
      filled: false,
      onPressed: () => go(plateIndex),
    ));
  }
  if (videoIndex >= 0) {
    add(_Pill(
      key: const Key('guide-video-pill'),
      label: strings.guide_video,
      filled: false,
      onPressed: () => go(videoIndex),
    ));
  }
  return pills;
}

class _OverlayButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Widget icon;

  const _OverlayButton({
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: colors.wash,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _galleryButtonExtent,
            height: _galleryButtonExtent,
            child: IconTheme(
              data: IconThemeData(color: colors.ink, size: 20),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _YoutubePlantVideo extends StatefulWidget {
  final GuideVideo video;

  const _YoutubePlantVideo({super.key, required this.video});

  @override
  State<_YoutubePlantVideo> createState() => _YoutubePlantVideoState();
}

class _YoutubePlantVideoState extends State<_YoutubePlantVideo> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.video.id,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_controller.close().catchError((Object error) {
      debugPrint('guide video: $error');
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(
      controller: _controller,
      aspectRatio: 16 / 9,
      autoFullScreen: false,
      enableFullScreenOnVerticalDrag: false,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}

class _NameBlock extends StatelessWidget {
  final GuideSpecies species;

  const _NameBlock({required this.species});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final named = species.hasVernacular;
    final title = named ? species.label!.trim() : species.name;
    final ranks = guideOrderFamilyLine(
      orderLabel: species.orderLabel,
      orderLatin: species.orderLatin,
      familyLabel: species.familyLabel,
      familyLatin: species.familyLatin,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ranks.isNotEmpty) ...[
            Text(
              ranks,
              key: const Key('guide-order-family'),
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: colors.ink2,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            style: named
                ? TextStyle(
                    fontFamily: GuideType.serif,
                    fontWeight: FontWeight.w500,
                    fontSize: 34,
                    letterSpacing: -0.85,
                    height: 1.05,
                    color: colors.ink,
                  )
                : GuideType.latin(colors).copyWith(fontSize: 34, height: 1.05),
          ),
          if (named) ...[
            const SizedBox(height: 6),
            Text.rich(TextSpan(
              style: GuideType.latin(colors).copyWith(fontSize: 18),
              children: [
                TextSpan(text: species.name),
                if (species.author != null)
                  TextSpan(
                    text: ' ${species.author}',
                    style: TextStyle(
                      fontFamily: GuideType.sans,
                      fontStyle: FontStyle.normal,
                      fontSize: 14,
                      color: colors.ink3,
                    ),
                  ),
              ],
            )),
          ] else if (species.author != null) ...[
            const SizedBox(height: 6),
            Text(
              species.author!,
              style: TextStyle(fontSize: 14, color: colors.ink3),
            ),
          ],
          if (species.names.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              S.of(context).guide_also(species.names.join(', ')),
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.ink2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingBar extends StatelessWidget {
  final GuideCameraPending pending;
  final GuideSpecies species;
  final bool kept;
  final VoidCallback? onKeep;
  final VoidCallback? onNotIt;
  final VoidCallback? onUndo;

  const _PendingBar({
    required this.pending,
    required this.species,
    required this.kept,
    required this.onKeep,
    required this.onNotIt,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final time = guidePhotoMoment(context, pending.when);
    final name = species.hasVernacular ? species.label!.trim() : species.name;
    final file = pending.photoPath;
    final hasFile = file != null && file.isNotEmpty && File(file).existsSync();
    final ground = kept ? colors.mossFill : colors.ink;
    final foreground = kept ? Colors.white : colors.onInk;
    return ColoredBox(
      color: ground,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          14 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: hasFile
                    ? Image.file(File(file), fit: BoxFit.cover)
                    : const ColoredBox(color: Color(0xFF555555)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kept
                        ? strings.guide_camera_in_seen_as(name)
                        : strings.guide_camera_your_photo,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    kept
                        ? strings.guide_camera_confirmed_line(time)
                        : strings.guide_camera_pending_line(
                            time, pending.place),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (kept)
              _PendingButton(
                label: strings.guide_camera_undo,
                onPressed: onUndo,
                foreground: foreground,
                border: foreground.withValues(alpha: 0.4),
              )
            else ...[
              _PendingButton(
                label: strings.guide_camera_its_this,
                onPressed: onKeep,
                background: colors.madderFill,
                foreground: Colors.white,
              ),
              const SizedBox(width: 6),
              _PendingButton(
                label: strings.guide_camera_not_it,
                onPressed: onNotIt,
                foreground: foreground,
                border: foreground.withValues(alpha: 0.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? background;
  final Color foreground;
  final Color? border;

  const _PendingButton({
    required this.label,
    required this.onPressed,
    required this.foreground,
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: background,
        foregroundColor: foreground,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: border == null ? BorderSide.none : BorderSide(color: border!),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

/// Month and day. A find from another year also shows the year.
String guideSeenDate(DateTime when, String locale, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final format = when.year == today.year
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  return format.format(when);
}

class _SeenByYou extends StatelessWidget {
  final GuideSpeciesSeen seen;
  final String locale;
  final VoidCallback onPressed;
  final GuideImageBuilder image;

  const _SeenByYou({
    required this.seen,
    required this.locale,
    required this.onPressed,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final last = seen.last;
    final when = last == null ? '' : guideSeenDate(last, locale);
    final detail = last == null
        ? ''
        : seen.count == 1
            ? strings.guide_seen_once(when)
            : strings.guide_seen_times(seen.count, when);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
      child: Material(
        color: colors.cream,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.rule),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: seen.photoPath == null
                        ? ColoredBox(color: colors.paper2)
                        : image(seen.photoPath!, BoxFit.cover, 36, 36),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.guide_seen_by_you,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          color: colors.moss,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            color: colors.ink,
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

class _AddSeenButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onPressed;

  const _AddSeenButton({required this.saving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 0),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: saving ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.ink,
              side: BorderSide(color: colors.rule),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontFamily: GuideType.sans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text('+ ${strings.guide_add_seen}'),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              strings.guide_add_seen_hint,
              style: TextStyle(fontSize: 13, color: colors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  final GuideSpecies species;
  final String range;
  final int month;
  final String locale;

  const _Facts({
    required this.species,
    required this.range,
    required this.month,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final height = guideHeightText(species.heightFrom, species.heightTo);
    final toxicity = guideCap(guideToxicityClassLabel(
      toxicityClass: species.toxicityClass,
      poisonous: strings.toxicity1,
      slight: strings.toxicity2,
      none: strings.guide_toxicity_none,
    ));
    final warn = species.toxicityClass == 1 || species.toxicityClass == 2;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.rule,
          border: Border.symmetric(
            horizontal: BorderSide(color: colors.rule),
          ),
        ),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: _Fact(
                      label: strings.guide_height,
                      value: height.isEmpty ? '—' : height,
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    flex: 3,
                    child: _Fact(
                      label: strings.plant_toxicity,
                      value: toxicity,
                      valueColor: warn ? colors.madder : null,
                      valueKey: const Key('guide-toxicity-value'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            ColoredBox(
              color: colors.paper,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 20, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      range.isEmpty
                          ? strings.plant_flower
                          : strings.guide_flowers(range),
                      style: GuideType.eyebrow(colors),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var m = 1; m <= 12; m++) ...[
                          if (m > 1) const SizedBox(width: 3),
                          Expanded(
                              child: _MonthCell(
                            month: m,
                            on: guideInFlower(
                              species.floweringFrom,
                              species.floweringTo,
                              m,
                            ),
                            now: m == month,
                            letter: DateFormat('MMMMM', locale)
                                .format(DateTime(2000, m)),
                          )),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Key? valueKey;

  const _Fact({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ColoredBox(
      color: colors.paper,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GuideType.eyebrow(colors)),
            const SizedBox(height: 2),
            Text(
              value,
              key: valueKey,
              style: TextStyle(
                fontFamily: GuideType.serif,
                fontWeight: FontWeight.w500,
                fontSize: 18,
                color: valueColor ?? colors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final int month;
  final bool on;
  final bool now;
  final String letter;

  const _MonthCell({
    required this.month,
    required this.on,
    required this.now,
    required this.letter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Container(
      key: ValueKey('guide-month-$month'),
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? colors.mossFill : colors.paper2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: now ? colors.madder : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 10,
          color: on ? Colors.white : colors.ink3,
        ),
      ),
    );
  }
}

/// The painted [label] stays. Screen readers also hear the place, so a jump
/// chip is not the same name as its heading, gallery photos are not the same
/// name, and two photos from one month are not the same name.
String _indexedName(
  BuildContext context,
  String label,
  int index,
  int count,
) {
  final place = MaterialLocalizations.of(context).tabLabel(
    tabIndex: index + 1,
    tabCount: count,
  );
  if (label.isEmpty) return place;
  return '$label, $place';
}

class _JumpWrap extends StatelessWidget {
  final List<({String id, String label})> chips;
  final ValueChanged<String> onJump;

  const _JumpWrap({required this.chips, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ColoredBox(
      color: colors.paper,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Wrap(
            key: const Key('guide-species-jumps'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < chips.length; i++)
                _Pill(
                  key: Key('guide-jump-${chips[i].id}'),
                  label: chips[i].label,
                  spoken: _indexedName(
                    context,
                    chips[i].label,
                    i,
                    chips.length,
                  ),
                  filled: true,
                  onPressed: () => onJump(chips[i].id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JumpBar extends StatelessWidget {
  final List<({String id, String label})> chips;
  final ValueChanged<String> onJump;
  final ScrollController controller;

  const _JumpBar({
    super.key,
    required this.chips,
    required this.onJump,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ColoredBox(
      color: colors.paper,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _Pill(
                  label: chips[i].label,
                  spoken: _indexedName(
                    context,
                    chips[i].label,
                    i,
                    chips.length,
                  ),
                  filled: true,
                  onPressed: () => onJump(chips[i].id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone jump pills. They scroll with the page until they meet the status
/// bar, then a paper cover holds them just below the clock.
class _StatusBarJumpScroll extends StatefulWidget {
  final List<({String id, String label})> chips;
  final ValueChanged<String> onJump;
  final List<Widget> leading;
  final List<Widget> trailing;

  const _StatusBarJumpScroll({
    required this.chips,
    required this.onJump,
    required this.leading,
    required this.trailing,
  });

  @override
  State<_StatusBarJumpScroll> createState() => _StatusBarJumpScrollState();
}

class _StatusBarJumpScrollState extends State<_StatusBarJumpScroll> {
  final GlobalKey _jumpKey = GlobalKey();
  final ScrollController _page = ScrollController();
  final ScrollController _flowChips = ScrollController();
  final ScrollController _pinnedChips = ScrollController();
  bool _cover = false;
  bool _syncScheduled = false;
  double _chipPixels = 0;
  double? _pinAt;
  double _measuredInset = 0;

  @override
  void initState() {
    super.initState();
    _page.addListener(_scheduleSync);
    _flowChips.addListener(_rememberFlow);
    _pinnedChips.addListener(_rememberPinned);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _StatusBarJumpScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSync();
  }

  @override
  void dispose() {
    _page.removeListener(_scheduleSync);
    _flowChips.removeListener(_rememberFlow);
    _pinnedChips.removeListener(_rememberPinned);
    _page.dispose();
    _flowChips.dispose();
    _pinnedChips.dispose();
    super.dispose();
  }

  void _rememberFlow() {
    if (!_cover && _flowChips.hasClients) _chipPixels = _flowChips.offset;
  }

  void _rememberPinned() {
    if (_cover && _pinnedChips.hasClients) _chipPixels = _pinnedChips.offset;
  }

  // Measure after layout. A scroll listener runs before the pills move, so
  // reading them there mixes the new offset with the old position.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncCover();
    });
  }

  void _syncCover() {
    if (!mounted || !_page.hasClients) return;
    final topInset = MediaQuery.paddingOf(context).top;
    if (_pinAt != null && _measuredInset != topInset) {
      _pinAt = _pinAt! + _measuredInset - topInset;
    }
    _measuredInset = topInset;
    final box = _jumpKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      _pinAt = _page.offset + top - topInset;
    }
    final pinAt = _pinAt;
    if (pinAt == null) return;
    final cover = _page.offset >= pinAt - 0.5;
    if (cover == _cover) return;
    setState(() => _cover = cover);
    _restore(cover ? _pinnedChips : _flowChips);
  }

  void _restore(ScrollController controller, {int tries = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final max = controller.position.maxScrollExtent;
      if (max <= 0 && _chipPixels > 0 && tries < 2) {
        _restore(controller, tries: tries + 1);
        return;
      }
      final target = _chipPixels.clamp(0.0, max);
      if ((controller.offset - target).abs() >= 0.5) {
        controller.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final colors = GuideColors.of(context);
    return Stack(
      children: [
        CustomScrollView(
          key: const Key('guide-species-scroll'),
          controller: _page,
          slivers: [
            for (final child in widget.leading)
              SliverToBoxAdapter(child: child),
            SliverToBoxAdapter(
              child: ExcludeSemantics(
                excluding: _cover,
                child: _JumpBar(
                  key: _jumpKey,
                  chips: widget.chips,
                  onJump: widget.onJump,
                  controller: _flowChips,
                ),
              ),
            ),
            ...widget.trailing,
          ],
        ),
        if (_cover)
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: ColoredBox(
              key: const Key('guide-species-jump-cover'),
              color: colors.paper,
              child: Padding(
                padding: EdgeInsets.only(top: topInset),
                child: _JumpBar(
                  chips: widget.chips,
                  onJump: widget.onJump,
                  controller: _pinnedChips,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String? spoken;
  final bool filled;
  final VoidCallback onPressed;

  const _Pill({
    super.key,
    required this.label,
    this.spoken,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final radius = BorderRadius.circular(_galleryPillHeight / 2);
    final chip = Material(
      color: filled ? colors.cream : colors.wash,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        excludeFromSemantics: spoken != null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: filled ? Border.all(color: colors.rule) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: _galleryPillHeight,
              // widthFactor keeps the chip as wide as its label. A plain
              // center alignment expands to the wrap's max width, which
              // stacks every tablet jump chip as a full-width bar.
              child: Align(
                alignment: Alignment.center,
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final name = spoken;
    if (name == null) return chip;
    return Semantics(
      container: true,
      button: true,
      label: name,
      excludeSemantics: true,
      onTap: onPressed,
      child: chip,
    );
  }
}

class _Lead extends StatelessWidget {
  final String text;

  const _Lead({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
      child: _RichPlantText(
        text: text,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: colors.ink2,
        ),
      ),
    );
  }
}

class _Aside extends StatelessWidget {
  final String title;
  final String text;
  final String? disclaimer;
  final Color accent;
  final double top;
  final Key? boxKey;

  const _Aside({
    super.key,
    required this.title,
    required this.text,
    required this.accent,
    required this.top,
    this.disclaimer,
    this.boxKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final rule = BorderSide(color: colors.rule);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, top, 20, 2),
      child: DecoratedBox(
        key: boxKey,
        decoration: BoxDecoration(
          color: colors.cream,
          border: BorderDirectional(
            top: rule,
            end: rule,
            bottom: rule,
            start: BorderSide(color: accent, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: GuideType.sans,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (disclaimer != null) ...[
                const SizedBox(height: 6),
                Text(
                  disclaimer!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: colors.ink3,
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 6),
              _RichPlantText(
                text: text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: colors.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String text;
  final bool warn;
  final VoidCallback? onOpen;
  final Key? linkKey;

  const _Section({
    super.key,
    required this.title,
    required this.text,
    required this.warn,
    this.onOpen,
    this.linkKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final body = _RichPlantText(
      text: text,
      style: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: colors.body,
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onOpen != null)
            GuideSchemaLink(
              key: linkKey,
              label: title,
              onPressed: onOpen!,
            )
          else
            Text(
              title,
              style: TextStyle(
                fontFamily: GuideType.serif,
                fontWeight: FontWeight.w500,
                fontSize: 19,
                color: colors.ink,
              ),
            ),
          const SizedBox(height: 6),
          if (warn)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.madder, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: body,
              ),
            )
          else
            body,
        ],
      ),
    );
  }
}

class _RichPlantText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _RichPlantText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(
      style: style,
      children: [
        for (final run in guideTextRuns(text))
          TextSpan(
            text: run.text,
            style:
                run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
      ],
    ));
  }
}

class _Taxonomy extends StatelessWidget {
  final List<GuideSpeciesRank> ranks;

  const _Taxonomy({super.key, required this.ranks});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(title: strings.guide_taxonomy, note: strings.guide_apg),
          const SizedBox(height: 6),
          for (final rank in ranks)
            Text.rich(TextSpan(
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: colors.ink,
              ),
              children: [
                TextSpan(
                  text: getTaxonLabel(context, rank.rank),
                  style: TextStyle(color: colors.ink3),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: rank.latin,
                  style: GuideType.latin(colors).copyWith(fontSize: 14),
                ),
                if (rank.vernacular != null && rank.vernacular!.isNotEmpty)
                  TextSpan(text: ' · ${rank.vernacular}'),
              ],
            )),
        ],
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  final String? path;

  const _Distribution({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(
            title: strings.guide_distribution,
            note: strings.guide_distribution_legend,
          ),
          if (path != null) ...[
            const SizedBox(height: 8),
            _MapImage(path: path!),
          ],
        ],
      ),
    );
  }
}

class _MapImage extends StatefulWidget {
  final String path;

  const _MapImage({required this.path});

  @override
  State<_MapImage> createState() => _MapImageState();
}

class _MapImageState extends State<_MapImage> {
  bool _failed = false;
  late Future<File?> _localFile;

  @override
  void initState() {
    super.initState();
    _localFile = Offline.getLocalFile(widget.path);
  }

  @override
  void didUpdateWidget(covariant _MapImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _failed = false;
      _localFile = Offline.getLocalFile(widget.path);
    }
  }

  Widget _labeledMap(Widget image) {
    return Semantics(
      container: true,
      image: true,
      label: S.of(context).guide_distribution,
      child: ExcludeSemantics(child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    if (_failed) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: AspectRatio(
          aspectRatio: 2,
          child: FutureBuilder<File?>(
            future: _localFile,
            builder: (context, snapshot) {
              final file = snapshot.data;
              if (file != null) {
                return _labeledMap(
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fail(),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const ColoredBox(color: Colors.white);
              }
              return _labeledMap(
                CachedNetworkImage(
                  imageUrl: storageEndpoint + widget.path,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const ColoredBox(color: Colors.white),
                  errorWidget: (_, __, ___) => _fail(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failed) setState(() => _failed = true);
    });
    return const SizedBox.shrink();
  }
}

class _Sightings extends StatelessWidget {
  final List<GuideSighting> sightings;
  final String locale;
  final GuideImageBuilder image;
  final ValueChanged<String> onOpen;

  const _Sightings({
    super.key,
    required this.sightings,
    required this.locale,
    required this.image,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final shown = sightings.take(9).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(
            title: strings.guide_sightings,
            note: shown.isEmpty
                ? null
                : strings.guide_sightings_count(sightings.length),
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Text(
              strings.guide_sightings_empty,
              style: TextStyle(fontSize: 13, color: colors.ink3),
            )
          else ...[
            GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final sighting = shown[index];
                final when = sighting.when;
                final caption =
                    when == null ? null : DateFormat.yMMMM(locale).format(when);
                final country = _sightingCountryName(context, sighting.country);
                return Semantics(
                  container: true,
                  button: true,
                  image: true,
                  label: _indexedName(
                    context,
                    _sightingSpoken(caption, country),
                    index,
                    shown.length,
                  ),
                  excludeSemantics: true,
                  onTap: () => onOpen(sighting.photoPath),
                  child: GestureDetector(
                    onTap: () => onOpen(sighting.photoPath),
                    excludeFromSemantics: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          image(sighting.photoPath, BoxFit.cover, 120, 120),
                          if (country != null)
                            PositionedDirectional(
                              top: 4,
                              start: 4,
                              end: 4,
                              child: Align(
                                alignment: AlignmentDirectional.topEnd,
                                child: _SightingChip(country),
                              ),
                            ),
                          if (caption != null)
                            PositionedDirectional(
                              start: 4,
                              bottom: 4,
                              end: 4,
                              child: Align(
                                alignment: AlignmentDirectional.bottomStart,
                                child: _SightingChip(caption),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              strings.guide_sightings_hint,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.ink3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Date stays on the bottom badge. Country is named with it for the
/// screen reader, since that badge sits in the opposite corner.
String _sightingSpoken(String? when, String? where) {
  final parts = <String>[
    if (when != null && when.isNotEmpty) when,
    if (where != null && where.isNotEmpty) where,
  ];
  if (parts.isEmpty) return '';
  return parts.join(' · ');
}

String? _sightingCountryName(BuildContext context, String? code) {
  if (code == null || code.isEmpty) return null;
  final country = Country.tryParse(code.toUpperCase());
  if (country == null) return code.toUpperCase();
  final translated = country.getTranslatedName(context)?.trim();
  if (translated != null && translated.isNotEmpty) return translated;
  final name = country.name.trim();
  if (name.isNotEmpty) return name;
  return code.toUpperCase();
}

class _SightingChip extends StatelessWidget {
  final String text;

  const _SightingChip(this.text);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GuideColors.of(context).wash,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

const int _collapsedSourceCount = 4;
const int _sourceColumns = 4;
const double _sourceGap = 8;
const double _sourceTapExtent = 48;

class _SourceLook {
  final String image;
  final String label;
  final bool plain;

  const _SourceLook(this.image, this.label, {this.plain = false});
}

_SourceLook _sourceLook(String url) {
  const plain = 'res/images/internet.png';
  var image = plain;
  var label = guideSourceHost(url);
  if (url.contains('wikipedia')) {
    image = 'res/images/wikipedia.png';
    label = 'wikipedia';
  } else if (url.contains('commons.wikimedia.org')) {
    image = 'res/images/commons.png';
    label = 'commons';
  } else if (url.contains('wikidata.org')) {
    image = 'res/images/wikidata.png';
    label = 'wikidata';
  } else if (url.contains('species.wikimedia.org')) {
    image = 'res/images/species.png';
    label = 'species';
  } else if (url.contains('luontoportti.com')) {
    image = 'res/images/luontoportti.png';
    label = 'luontoportti.com';
  } else if (url.contains('botany.cz')) {
    image = 'res/images/botany.png';
    label = 'botany.cz';
  } else if (url.contains('floranordica.org')) {
    image = 'res/images/floranordica.png';
    label = 'floranordica.org';
  } else if (url.contains('efloras.org')) {
    image = 'res/images/eflora.png';
    label = 'efloras.org';
  } else if (url.contains('berkeley.edu')) {
    image = 'res/images/berkeley.png';
    label = 'berkeley.edu';
  } else if (url.contains('hortipedia.com')) {
    image = 'res/images/hortipedia.png';
    label = 'hortipedia.com';
  } else if (url.contains('plants.usda.gov')) {
    image = 'res/images/usda.png';
    label = 'plants.usda.gov';
  } else if (url.contains('forestryimages.org')) {
    image = 'res/images/usfs.png';
    label = 'forestryimages.org';
  } else if (url.contains('tela-botanica.org')) {
    image = 'res/images/tela_botanica.png';
    label = 'tela-botanica.org';
  } else if (url.contains('infoflora.ch')) {
    image = 'res/images/infoflora.png';
    label = 'infoflora.ch';
  } else if (url.contains('pladias.cz')) {
    image = 'res/images/pladias.png';
    label = 'pladias.cz';
  } else if (url.contains('nativeplanttrust.org')) {
    image = 'res/images/gobotany.png';
    label = 'gobotany';
  } else if (url.contains('bsbi.org')) {
    image = 'res/images/bsbi.png';
    label = 'bsbi.org';
  } else if (url.contains('burkeherbarium.org') ||
      url.contains('burke.washington.edu')) {
    image = 'res/images/burke.png';
    label = 'burke';
  }
  return _SourceLook(image, label, plain: image == plain);
}

class _Sources extends StatefulWidget {
  final List<GuideSourceLink> links;

  const _Sources({required this.links});

  @override
  State<_Sources> createState() => _SourcesState();
}

class _SourcesState extends State<_Sources> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final links = widget.links;
    final hidden = links.length - _collapsedSourceCount;
    final shown = _expanded || hidden <= 0
        ? links
        : links.take(_collapsedSourceCount).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.of(context).plant_sources,
            style: TextStyle(
              fontFamily: GuideType.serif,
              fontWeight: FontWeight.w500,
              fontSize: 19,
              height: 1,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: _sourceGap),
          _SourceGrid(links: shown),
          if (hidden > 0) ...[
            const SizedBox(height: _sourceGap),
            Align(
              alignment: Alignment.center,
              child: _SourceMore(
                expanded: _expanded,
                hidden: hidden,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceGrid extends StatelessWidget {
  final List<GuideSourceLink> links;

  const _SourceGrid({required this.links});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / _sourceColumns;
        final rows = <Widget>[];
        for (var i = 0; i < links.length; i += _sourceColumns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: _sourceGap));
          final slice = links.skip(i).take(_sourceColumns).toList();
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final link in slice)
                SizedBox(width: width, child: _SourceButton(link: link)),
              for (var pad = slice.length; pad < _sourceColumns; pad++)
                SizedBox(width: width),
            ],
          ));
        }
        return Column(children: rows);
      },
    );
  }
}

class _SourceButton extends StatelessWidget {
  final GuideSourceLink link;

  const _SourceButton({required this.link});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final look = _sourceLook(link.url);
    return Semantics(
      button: true,
      link: true,
      label: look.label,
      child: InkWell(
        key: ValueKey(link.url),
        onTap: () => launchURL(link.url),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                look.image,
                width: 50,
                height: 50,
                color: look.plain ? colors.ink : null,
                colorBlendMode: look.plain ? BlendMode.srcIn : null,
              ),
              Text(
                look.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  color: colors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceMore extends StatelessWidget {
  final bool expanded;
  final int hidden;
  final VoidCallback onTap;

  const _SourceMore({
    required this.expanded,
    required this.hidden,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return InkWell(
      key: const Key('guide-sources-more'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _sourceTapExtent,
          minHeight: _sourceTapExtent,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: colors.moss,
                ),
                if (!expanded)
                  Text(
                    '+$hidden',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.moss,
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

class _Heading extends StatelessWidget {
  final String title;
  final String? note;

  const _Heading({required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Text.rich(TextSpan(
      style: TextStyle(
        fontFamily: GuideType.serif,
        fontWeight: FontWeight.w500,
        fontSize: 19,
        color: colors.ink,
      ),
      children: [
        TextSpan(text: title),
        if (note != null)
          TextSpan(
            text: '  $note',
            style: TextStyle(
              fontFamily: GuideType.sans,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.ink3,
            ),
          ),
      ],
    ));
  }
}
