import 'dart:async';

import 'package:abherbs_flutter/book/book_page.dart';
import 'package:abherbs_flutter/find/find_page.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_favorites.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/seen/guide_private_photos.dart';
import 'package:abherbs_flutter/seen/guide_seen.dart';
import 'package:abherbs_flutter/seen/guide_seen_store.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/shell/guide_actions.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/shell/app_version.dart';
import 'package:abherbs_flutter/shell/app_version_check.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/shell/version_gate.dart';
import 'package:abherbs_flutter/seen/seen_page.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class GuideShell extends StatefulWidget {
  const GuideShell({super.key});

  @override
  State<GuideShell> createState() => _GuideShellState();
}

class _GuideShellState extends State<GuideShell> with WidgetsBindingObserver {
  final Set<int> _opened = {0};
  int _index = 0;
  String? _languageCode;
  int _listTicket = 0;
  int _favoriteTicket = 0;
  GuideListCover? _favorites;
  int _findTicket = 0;
  int _unconfirmedTicket = 0;
  String? _seenUid;
  bool _unconfirmedLoaded = false;
  Object? _seenValue;
  bool _seenReady = false;
  final Map<String, GuideSeenFind> _seenFaces = {};
  String? _decoratedStamp;
  int _decorateGen = 0;
  bool _decorateActive = false;
  bool _decorateQueued = false;
  Map<String, int>? _colorCounts;
  int? _catalogCount;
  List<GuideListCover>? _lists;

  /// The list read threw. Distinct from an empty catalog, which is [_lists]
  /// set to an empty list.
  bool _listsFailed = false;

  /// The new-plants query threw. The language lists stay on screen, and this
  /// stays set until a later read of `lists_custom/new` finishes.
  bool _freshFailed = false;
  int _freshTicket = 0;

  /// Bumped when the person picks another tab while a connection check for
  /// Book is still running, so that check cannot open Book afterwards.
  int _tabTicket = 0;
  GuideBookSegment _bookSegment = GuideBookSegment.families;
  List<GuideFind>? _finds;
  List<GuideSeenFind>? _notebook;
  int _accountTicket = 0;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DatabaseEvent>? _quotaSub;
  StreamSubscription<DatabaseEvent>? _seenRemote;
  String? _seenWatchUid;
  VersionPrompt _versionPrompt = VersionPrompt.none;
  int? _storeBuild;
  int _dismissedStore = 0;
  bool _versionBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    guidePrivatePhotoFetch = fetchGuidePrivatePhoto;
    guideSyncPrivatePhotos = syncGuidePrivatePhotos;
    guideDeletePrivatePhotos = deleteGuidePrivatePhotos;
    guideSkipPrivatePhoto = skipGuidePrivatePhoto;
    GuideAppearanceController.instance.apply(storedGuideAppearance());
    guideGuestFreeRemaining.value = guideGuestFreeRemembered();
    guideGuestFreeRemaining.addListener(_onGuestFree);
    Purchases.namesRevision.addListener(_onNames);
    unawaited(guideGuestHasFreeName());
    unawaited(GuideAnalytics.screen(guideAnalyticsTabFind));
    _authSub = Auth.subscribe((user) {
      unawaited(_onAccount(user));
    });
    guideMonthCount.addListener(_onMonth);
    guideFavoriteIds.addListener(_onFavoriteIds);
    _watchQuota();
    _watchSeenRemote();
    _loadColors();
    unawaited(_checkVersion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = Localizations.localeOf(context).languageCode;
    if (_languageCode == code) return;
    _languageCode = code;
    unawaited(GuideAnalytics.setLanguage(code));
    _loadLists();
    unawaited(_refreshFavoriteCover());
    _loadFinds();
    if (_opened.contains(2)) {
      _clearSeenLabels();
      _showSeen(forceDecorate: true);
    } else {
      _loadUnconfirmed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GuideTabs.show = null;
    GuideTabs.showSeen = null;
    GuideTabs.refreshSeen = null;
    GuideTabs.openPerson = null;
    GuideTabs.unconfirmed.value = 0;
    guideGuestFreeRemaining.removeListener(_onGuestFree);
    Purchases.namesRevision.removeListener(_onNames);
    guideMonthCount.removeListener(_onMonth);
    guideFavoriteIds.removeListener(_onFavoriteIds);
    watchGuideFavorites(null);
    _authSub?.cancel();
    _quotaSub?.cancel();
    _seenRemote?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(syncGuidePrivatePhotos());
    unawaited(_checkVersion());
    // A long suspend keeps the strip that was on screen. Ask again so a
    // find deleted on another device does not stay under Seen lately.
    _loadFinds();
    // A timed-out read leaves _lists null. Ask again; that is not an empty
    // catalog, and the first attempt often loses the startup connection.
    // A finished language list can still be missing New in the book when
    // only that query threw.
    if (_lists == null) {
      _loadLists();
    } else if (_freshFailed) {
      unawaited(_retryFresh());
    }
  }

  /// A failed fetch keeps a remembered floor closed. The shell only shows
  /// the soft banner. The hard page is drawn over the navigator.
  Future<void> _checkVersion() async {
    if (_versionBusy) return;
    _versionBusy = true;
    try {
      final build = await readAppBuildNumber();
      if (!mounted) return;
      final fresh = decideVersion(await readFreshVersionFacts(build));
      await persistVersionDecision(fresh);
      VersionGateController.instance.apply(
        fresh.prompt == VersionPrompt.block
            ? VersionPrompt.block
            : VersionPrompt.none,
      );
      if (!mounted) return;
      var prompt = fresh.prompt == VersionPrompt.block
          ? VersionPrompt.none
          : fresh.prompt;
      final store = fresh.storeBuild;
      if (prompt == VersionPrompt.banner &&
          store != null &&
          store == _dismissedStore) {
        prompt = VersionPrompt.none;
      }
      setState(() {
        _versionPrompt = prompt;
        _storeBuild = store;
      });
    } catch (error) {
      debugPrint('version check: $error');
    } finally {
      _versionBusy = false;
    }
  }

  void _dismissVersionBanner() {
    final store = _storeBuild;
    if (store != null) {
      _dismissedStore = store;
      unawaited(Prefs.setInt(keyVersionBannerDismissed, store));
    }
    setState(() => _versionPrompt = VersionPrompt.none);
  }

  /// Keeps the signed-in notebook synced. The snapshot is already the
  /// server copy, so Seen paints from it instead of downloading the list
  /// again. Each event also reloads Seen lately. Vernaculars and Share
  /// are filled in after that.
  void _watchSeenRemote() {
    final uid = guideNotebookUser()?.uid;
    if (uid == _seenWatchUid && _seenRemote != null) return;
    _seenRemote?.cancel();
    _seenRemote = null;
    _seenWatchUid = uid;
    if (uid == null) return;
    _seenRemote = privateObservationsReference
        .child(uid)
        .child(firebaseObservationsByDate)
        .child(firebaseAttributeList)
        .onValue
        .listen((event) => _onSeenRemote(event, uid), onError: (Object error) {
      debugPrint('guide seen: $error');
      if (!mounted || _seenReady || !_opened.contains(2)) return;
      setState(() => _notebook = []);
      GuideTabs.unconfirmed.value = 0;
    });
  }

  void _onSeenRemote(DatabaseEvent event, String uid) {
    guidePrivatePhotosChanged();
    _seenValue = event.snapshot.value;
    _seenReady = true;
    _seenUid = guideNotebookUser()?.uid;
    unawaited(fillGuideSeenCountries(_seenValue, uid));
    _unconfirmedLoaded = true;
    // The first event can be the on-disk copy. [loadRecentFinds] waits
    // for the server, so the strip does not keep a deleted find.
    _loadFinds();
    if (!_opened.contains(2)) {
      GuideTabs.unconfirmed.value =
          guideUnconfirmedTotal(guideSeenRows(_seenValue));
      return;
    }
    _showSeen();
  }

  void _go(int index) {
    if (index == 1 && _index != 1) {
      final ticket = ++_tabTicket;
      unawaited(_openBook(ticket));
      return;
    }
    _tabTicket++;
    _enter(index);
  }

  /// Book and its lists open from a pack already on the phone. With no pack
  /// and no connection, the same dialog as Name it from a photo stays here.
  Future<void> _openBook(int ticket) async {
    if (!mounted) return;
    if (!await guideBookAvailable(context)) return;
    if (!mounted || ticket != _tabTicket) return;
    _enter(1);
  }

  void _enter(int index) {
    if (_index != index) {
      unawaited(GuideAnalytics.screen(guideAnalyticsTab(index)));
    }
    GuideTabs.index = index;
    List<GuideSeenFind>? primed;
    if (index == 2) {
      _loadFinds();
      final uid = guideNotebookUser()?.uid;
      if (uid == null) {
        primed = [];
      } else if (_seenReady) {
        final rows = guideSeenRows(_seenValue);
        primed = [
          for (final row in rows) guideSeenCarryFace(row, _seenFaces[row.id]),
        ];
        _rememberSeenFaces(primed);
        GuideTabs.unconfirmed.value = guideUnconfirmedTotal(rows);
      }
    }
    setState(() {
      _opened.add(index);
      _index = index;
      if (primed != null) _notebook = primed;
    });
    if (index == 2 && _seenReady) _scheduleDecorate(force: true);
  }

  /// Find’s All lists opens Book on the lists of flowers.
  void _openLists() {
    final ticket = ++_tabTicket;
    unawaited(_openListsWhenOnline(ticket));
  }

  Future<void> _openListsWhenOnline(int ticket) async {
    if (!mounted) return;
    if (!await guideBookAvailable(context)) return;
    if (!mounted || ticket != _tabTicket) return;
    if (_index != 1) unawaited(GuideAnalytics.screen(guideAnalyticsTabBook));
    GuideTabs.index = 1;
    setState(() {
      _bookSegment = GuideBookSegment.lists;
      _opened.add(1);
      _index = 1;
    });
  }

  void _onGuestFree() {
    if (mounted) setState(() {});
  }

  void _onMonth() {
    if (mounted) setState(() {});
  }

  void _onNames() {
    if (!mounted) return;
    setState(() {});
    if (Purchases.namesReady && Purchases.syncsSeenPhotos()) {
      unawaited(syncGuidePrivatePhotos());
    }
  }

  /// Sign-in finishes after Find has drawn. The name meter follows the
  /// account record at once. The find list reloads after that. Seen paints
  /// from the notebook listener.
  Future<void> _onAccount(User? user) async {
    final ticket = ++_accountTicket;
    _watchQuota();
    watchGuideFavorites(user);
    unawaited(_refreshFavoriteCover());
    _watchSeenRemote();
    _resetSeenForUser();
    if (user == null) guideMonthCount.value = GuideMonthCount.empty;
    if (_opened.contains(2)) {
      _showSeen();
    } else {
      unawaited(_loadUnconfirmed());
    }
    if (mounted) setState(() {});
    final finds = _loadFinds();
    if (user != null) {
      try {
        await Auth.setUser();
      } catch (error) {
        debugPrint('guide account: $error');
      }
    }
    if (!mounted || ticket != _accountTicket) return;
    setState(() {});
    await finds;
    if (!mounted || ticket != _accountTicket) return;
    await guideGuestHasFreeName();
    if (!mounted || ticket != _accountTicket) return;
    if (user != null) {
      unawaited(syncGuidePrivatePhotos());
      final count = await loadGuideMonthCount();
      if (!mounted || ticket != _accountTicket) return;
      if (guideMonthCount.value != count) guideMonthCount.value = count;
    }
    setState(() {});
  }

  /// The last finished quota read for the signed-in account. Another
  /// account, or no stored line, clears the meter so the previous account
  /// does not stay on screen.
  void _recallMonthCount() {
    final uid = Auth.appUser?.uid;
    if (uid == null || !Prefs.ready()) {
      guideMonthCount.value = GuideMonthCount.empty;
      return;
    }
    final next = guideMonthCountForAccount(
      uid: uid,
      stored: Prefs.getString(keyGuideMonthCount, ''),
      now: DateTime.now(),
    );
    if (guideMonthCount.value != next) guideMonthCount.value = next;
  }

  void _watchQuota() {
    _quotaSub?.cancel();
    _quotaSub = null;
    final uid = Auth.appUser?.uid;
    if (uid == null) {
      guideMonthCount.value = GuideMonthCount.empty;
      return;
    }
    _recallMonthCount();
    _quotaSub =
        rootReference.child(firebasePhotoQuota).child(uid).onValue.listen(
      (event) {
        if (Auth.appUser?.uid != uid) return;
        final raw = event.snapshot.value;
        final next = guideMonthCountArrived(raw, DateTime.now());
        // Null, or anything that is not a map, did not arrive. The stored
        // line recalled for this account stays.
        if (next == null || guideMonthCount.value == next) return;
        guideMonthCount.value = next;
        unawaited(guideRememberMonthCount(uid, next));
      },
      onError: (Object error) => debugPrint('guide month: $error'),
    );
  }

  Future<void> _loadColors() async {
    try {
      final counts = await loadColorCounts();
      if (!mounted) return;
      setState(() {
        _colorCounts = counts.byColor;
        _catalogCount = counts.total;
      });
    } catch (error) {
      debugPrint('guide colors: $error');
    }
  }

  void _onFavoriteIds() {
    unawaited(_refreshFavoriteCover());
  }

  Future<void> _refreshFavoriteCover() async {
    final code = _languageCode;
    if (code == null) return;
    final ticket = ++_favoriteTicket;
    if (Auth.appUser == null || guideFavoriteIds.value.isEmpty) {
      if (!mounted || ticket != _favoriteTicket) return;
      if (_favorites != null) setState(() => _favorites = null);
      return;
    }
    try {
      final cover = await loadGuideFavoriteCover(code);
      if (!mounted || ticket != _favoriteTicket) return;
      setState(() => _favorites = cover);
    } catch (error) {
      debugPrint('guide favorites: $error');
      if (!mounted || ticket != _favoriteTicket) return;
      if (_favorites != null) setState(() => _favorites = null);
    }
  }

  Future<void> _loadLists() async {
    final code = _languageCode;
    if (code == null) return;
    final ticket = ++_listTicket;
    ++_freshTicket;
    if (_listsFailed) {
      setState(() => _listsFailed = false);
    }
    try {
      final read = await loadGuideLists(code);
      if (!mounted || ticket != _listTicket) return;
      setState(() {
        _lists = read.covers;
        _listsFailed = false;
        _freshFailed = read.freshFailed;
      });
      if (read.freshFailed) unawaited(_retryFresh());
    } catch (error) {
      debugPrint('guide lists: $error');
      if (!mounted || ticket != _listTicket) return;
      // Keep a list already on screen. Only a finished read may be empty.
      setState(() {
        if (_lists == null) _listsFailed = true;
      });
    }
  }

  /// One more read of New in the book. A miss stays flagged for the next
  /// resume. An empty catalog clears the flag.
  Future<void> _retryFresh() async {
    if (!_freshFailed) return;
    final ticket = ++_freshTicket;
    final listTicket = _listTicket;
    try {
      final cover = await loadGuideFreshCover();
      if (!mounted || ticket != _freshTicket || listTicket != _listTicket) {
        return;
      }
      setState(() {
        _freshFailed = false;
        final lists = _lists;
        if (lists == null) return;
        _lists = guideListsWithFresh(lists, cover);
      });
    } catch (error) {
      debugPrint('guide lists new: $error');
    }
  }

  Future<void> _loadFinds() async {
    final code = _languageCode;
    if (code == null) return;
    final ticket = ++_findTicket;
    try {
      final finds = await loadRecentFinds(code, limit: 40);
      if (!mounted || ticket != _findTicket) return;
      setState(() => _finds = finds);
    } catch (error) {
      debugPrint('guide finds: $error');
      if (!mounted || ticket != _findTicket) return;
      setState(() => _finds = []);
    }
  }

  void _resetSeenForUser() {
    final uid = guideNotebookUser()?.uid;
    if (uid == _seenUid) return;
    _seenUid = uid;
    _unconfirmedLoaded = false;
    _seenReady = false;
    _seenValue = null;
    _seenFaces.clear();
    _decoratedStamp = null;
    _decorateQueued = false;
    ++_decorateGen;
    ++_unconfirmedTicket;
    GuideTabs.unconfirmed.value = 0;
    if (_notebook == null) return;
    _notebook = null;
    if (mounted) setState(() {});
  }

  Future<void> _loadUnconfirmed() async {
    if (_notebook != null || _unconfirmedLoaded || _seenReady) return;
    final uid = guideNotebookUser()?.uid;
    _seenUid = uid;
    final ticket = ++_unconfirmedTicket;
    try {
      final count = await loadGuideUnconfirmedCount();
      if (!mounted || ticket != _unconfirmedTicket || _notebook != null) {
        return;
      }
      if (_seenReady || guideNotebookUser()?.uid != uid) return;
      _unconfirmedLoaded = true;
      GuideTabs.unconfirmed.value = count;
    } catch (error) {
      debugPrint('guide unconfirmed: $error');
    }
  }

  void _clearSeenLabels() {
    final next = <String, GuideSeenFind>{};
    _seenFaces.forEach((id, face) {
      next[id] = face.catalogKnown
          ? face.withCatalog(
              label: null,
              inBook: face.inBook,
              photoAttached: face.photoAttached,
            )
          : face;
    });
    _seenFaces
      ..clear()
      ..addAll(next);
    _decoratedStamp = null;
  }

  void _rememberSeenFaces(List<GuideSeenFind> rows) {
    final ids = <String>{};
    for (final row in rows) {
      ids.add(row.id);
      _seenFaces[row.id] = row;
    }
    _seenFaces.removeWhere((id, _) => !ids.contains(id));
  }

  void _publishSeen(List<GuideSeenFind> rows) {
    final shown = [
      for (final row in rows) guideSeenCarryFace(row, _seenFaces[row.id]),
    ];
    _rememberSeenFaces(shown);
    GuideTabs.unconfirmed.value = guideUnconfirmedTotal(rows);
    if (!mounted) {
      _notebook = shown;
      return;
    }
    setState(() => _notebook = shown);
  }

  /// Draws the notebook already in hand. [forceDecorate] checks photo files
  /// again, which a tab open needs and a repeat listener event does not.
  void _showSeen({bool forceDecorate = false}) {
    final uid = guideNotebookUser()?.uid;
    if (uid == null) {
      _seenReady = false;
      _seenValue = null;
      _seenFaces.clear();
      _decoratedStamp = null;
      GuideTabs.unconfirmed.value = 0;
      if (!mounted) {
        _notebook = [];
        return;
      }
      setState(() => _notebook = []);
      return;
    }
    if (!_seenReady) return;
    _publishSeen(guideSeenRows(_seenValue));
    _scheduleDecorate(force: forceDecorate);
  }

  void _scheduleDecorate({bool force = false}) {
    final code = _languageCode;
    if (code == null || !_seenReady || !_opened.contains(2)) return;
    final stamp = '$code\u0000${guideSeenDecorateStamp(_seenValue)}';
    if (!force && stamp == _decoratedStamp) return;
    if (_decorateActive) {
      _decorateQueued = true;
      return;
    }
    unawaited(_runDecorate());
  }

  Future<void> _runDecorate() async {
    _decorateActive = true;
    try {
      var spins = 0;
      do {
        _decorateQueued = false;
        final code = _languageCode;
        final uid = _seenUid;
        final value = _seenValue;
        if (code == null || !_seenReady) break;
        final stamp = '$code\u0000${guideSeenDecorateStamp(value)}';
        final gen = ++_decorateGen;
        try {
          final decorated = await decorateGuideSeen(
            guideSeenRows(value),
            code,
            clouds: guideSeenCloudFlags(value),
          );
          if (!mounted || gen != _decorateGen) continue;
          if (guideNotebookUser()?.uid != uid) continue;
          final latest = guideSeenRows(_seenValue);
          final doneStamp = '$code\u0000${guideSeenDecorateStamp(_seenValue)}';
          final pass = guideSeenPass(
            latest: latest,
            read: decorated,
            remembered: _seenFaces,
            stamp: stamp,
            doneStamp: doneStamp,
          );
          _rememberSeenFaces(pass.rows);
          _decoratedStamp = pass.stamp;
          setState(() => _notebook = pass.rows);
          GuideTabs.unconfirmed.value = guideUnconfirmedTotal(latest);
        } catch (error) {
          debugPrint('guide seen: $error');
          if (!mounted || gen != _decorateGen) continue;
          _decoratedStamp = null;
          if (_notebook == null) {
            setState(() => _notebook = []);
            GuideTabs.unconfirmed.value = 0;
          }
        }
        spins++;
      } while (_decorateQueued && spins < 3);
    } finally {
      _decorateActive = false;
      if (_decorateQueued && mounted && _opened.contains(2)) {
        _decorateQueued = false;
        unawaited(_runDecorate());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    GuideTabs.show = (index) {
      if (mounted) _go(index);
    };
    GuideTabs.showSeen = () {
      if (mounted) _go(2);
    };
    GuideTabs.refreshSeen = () {
      if (!mounted) return;
      _loadFinds();
      if (_opened.contains(2)) _showSeen();
    };
    GuideTabs.openPerson = openGuideAccount;
    GuideTabs.index = _index;
    final prompt = _versionPrompt;
    final showAd = (_index == 0 || _index == 1) && Purchases.showsAds();
    final pages = Column(
      children: [
        if (prompt == VersionPrompt.banner)
          VersionBanner(
            onUpdate: () => openAppUpdate(requiredUpdate: false),
            onDismiss: _dismissVersionBanner,
          ),
        Expanded(
          child: IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: [
              FindPage(
                colorCounts: _colorCounts,
                catalogCount: _catalogCount,
                lists: _lists,
                listsFailed: _listsFailed,
                onRetryLists: _loadLists,
                favorites: _favorites,
                finds: _finds,
                allowance: guideCameraLiveAllowance(
                  guestFree: guideGuestFreeRemaining.value,
                ),
                onOpenBook: _openLists,
                onOpenSeen: () => _go(2),
              ),
              _opened.contains(1)
                  ? BookPage(
                      lists: _lists,
                      listsFailed: _listsFailed,
                      onRetryLists: _loadLists,
                      favorites: _favorites,
                      segment: _bookSegment,
                      onSegment: (segment) {
                        if (_bookSegment == segment) return;
                        setState(() => _bookSegment = segment);
                      },
                      onOpenFind: () => _go(0),
                    )
                  : const SizedBox.shrink(),
              _opened.contains(2)
                  ? SeenPage(
                      finds: _notebook,
                      signedIn: Auth.appUser != null,
                      fieldGuide: Purchases.syncsSeenPhotos(),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
    return GuideTheme(
      navigationColor: (colors) => colors.cream,
      child: guideChromeFrame(
        context,
        index: _index,
        showAd: showAd,
        onSelect: _go,
        child: pages,
      ),
    );
  }
}
