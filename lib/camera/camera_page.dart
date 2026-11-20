import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:camera/camera.dart';
import 'package:abherbs_flutter/key/filter_utils.dart';
import 'package:abherbs_flutter/field_guide/field_guide_page.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_photo_file.dart';
import 'package:abherbs_flutter/data/guide_photo_pick.dart';
import 'package:abherbs_flutter/data/guide_location.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/species/guide_species.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_window.dart';
import 'package:abherbs_flutter/camera/outside_page.dart';
import 'package:abherbs_flutter/key/results_page.dart';
import 'package:abherbs_flutter/search/search_page.dart';
import 'package:abherbs_flutter/person/sign_in_page.dart';
import 'package:abherbs_flutter/species/species_page.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/keys.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/purchase/rewarded_ad.dart';
import 'package:abherbs_flutter/camera/plant_id_search.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

const _well = Color(0xFF0D0C0A);
const _scrim = Color(0x66000000);

enum _Sheet { limit, notPlant }

/// The field-guide camera. Location is asked once. A name in the book opens
/// that species page. A genus or family opens that list. A name outside the
/// book opens Outside the book.
class GuideCameraPage extends StatefulWidget {
  final GuideAllowance? allowance;
  final GuideCameraPlace? place;

  /// Place pill on Outside the book. When set, prefs are not read.
  final String? placeName;
  final Future<GuideCameraPlace> Function()? onAllow;
  final Future<GuideCameraPlace> Function()? onDecline;
  final Future<String?> Function(GuideCameraSource source)? pickPhoto;
  final Future<GuideCameraOutcome> Function(String path)? identify;

  /// When set, this reads the date of a roll photo. Production leaves it
  /// empty and reads the date from the photo.
  final Future<DateTime?> Function(String path)? photoTakenAt;

  /// When set, this reads the EXIF GPS of a roll photo.
  final Future<GuidePhotoPosition?> Function(String path)? photoPosition;

  /// When set, this reads the phone's position for a shutter photo.
  final Future<GuidePhotoPosition?> Function()? phonePosition;
  final Future<void> Function()? onWatchAd;
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onFieldGuide;
  final void Function(String name)? onOpenSpecies;
  final void Function(String path)? onOpenList;
  final VoidCallback? onKey;
  final VoidCallback? onClose;

  /// When set, this stands in for the live camera. Production leaves it
  /// empty and opens the device camera.
  final WidgetBuilder? livePreview;

  const GuideCameraPage({
    super.key,
    this.allowance,
    this.place,
    this.placeName,
    this.onAllow,
    this.onDecline,
    this.pickPhoto,
    this.identify,
    this.photoTakenAt,
    this.photoPosition,
    this.phonePosition,
    this.onWatchAd,
    this.onSignIn,
    this.onFieldGuide,
    this.onOpenSpecies,
    this.onOpenList,
    this.onKey,
    this.onClose,
    this.livePreview,
  });

  @override
  State<GuideCameraPage> createState() => _GuideCameraPageState();
}

class _GuideCameraPageState extends State<GuideCameraPage>
    with WidgetsBindingObserver {
  GuideAllowance? _liveAllowance;
  bool _guestFree = false;
  GuideCameraPlace? _place;
  bool _busy = false;
  bool _naming = false;
  String? _shotPath;

  /// EXIF date of a photo chosen from the roll. A shutter photo leaves this
  /// empty and the find uses the current time.
  DateTime? _shotWhen;

  /// EXIF GPS of the photo. A shutter photo without GPS falls back to the
  /// phone's position.
  GuidePhotoPosition? _shotPosition;
  _Sheet? _sheet;
  bool _notPlantCounted = false;
  RewardedAd? _rewardedAd;
  int _adAttempts = 0;
  CameraController? _camera;
  int _previewEpoch = 0;
  bool _previewStarting = false;
  bool _adLoading = false;

  GuideAllowance get _allowance =>
      widget.allowance ?? _liveAllowance ?? const GuideAllowance.guest();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _place = widget.place;
    if (widget.allowance == null) {
      _guestFree = guideGuestFreeRemembered();
    }
    _readAllowance();
    guideMonthCount.addListener(_onMonth);
    Purchases.namesRevision.addListener(_onNames);
    if (widget.allowance == null) unawaited(_loadMonth());
    if (widget.place == null) unawaited(_loadPlace());
    _ensureAd();
    unawaited(_startPreview());
  }

  @override
  void dispose() {
    // A review left on screen when the route goes away. A capture still in
    // flight deletes the file itself once it notices.
    if (!_busy && !_naming) _releaseShot();
    guideMonthCount.removeListener(_onMonth);
    Purchases.namesRevision.removeListener(_onNames);
    WidgetsBinding.instance.removeObserver(this);
    _previewEpoch++;
    _camera?.dispose();
    _camera = null;
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.livePreview != null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _previewEpoch++;
      final camera = _camera;
      if (camera == null || !camera.value.isInitialized) return;
      unawaited(_stopPreview());
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        !_previewStarting &&
        !_naming &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_startPreview());
    }
  }

  Future<void> _startPreview() async {
    if (widget.livePreview != null || _previewStarting) return;
    _previewStarting = true;
    final epoch = ++_previewEpoch;
    try {
      final previous = _camera;
      _camera = null;
      if (previous != null) await previous.dispose();
      if (!mounted || epoch != _previewEpoch) return;
      final cameras = await availableCameras();
      if (!mounted || epoch != _previewEpoch || cameras.isEmpty) return;
      var selected = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selected = camera;
          break;
        }
      }
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || epoch != _previewEpoch) {
        await controller.dispose();
        return;
      }
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (error) {
        debugPrint('guide camera orientation: $error');
      }
      if (!mounted || epoch != _previewEpoch) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (error) {
      debugPrint('guide camera preview: $error');
    } finally {
      _previewStarting = false;
    }
  }

  Future<void> _stopPreview() async {
    _previewEpoch++;
    final camera = _camera;
    _camera = null;
    if (mounted && camera != null) setState(() {});
    await camera?.dispose();
  }

  Future<void> _resumePreview() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      await _startPreview();
      return;
    }
    if (!camera.value.isPreviewPaused) return;
    try {
      await camera.resumePreview();
    } catch (error) {
      debugPrint('guide camera preview: $error');
      await _startPreview();
    }
  }

  void _releaseShot() {
    final path = _shotPath;
    if (path == null) return;
    _shotPath = null;
    unawaited(deleteDiscardedShot(path));
  }

  void _clearShot() {
    _releaseShot();
    setState(() {
      _naming = false;
      _sheet = null;
      _shotPath = null;
      _shotWhen = null;
      _shotPosition = null;
    });
    unawaited(_resumePreview());
  }

  void _onMonth() {
    if (!mounted || widget.allowance != null) return;
    _readAllowance();
    setState(() {});
  }

  void _onNames() {
    if (!mounted || widget.allowance != null) return;
    _readAllowance();
    setState(() {});
  }

  Future<void> _loadMonth() async {
    final count = await loadGuideMonthCount();
    if (!mounted || widget.allowance != null) return;
    if (guideMonthCount.value != count) guideMonthCount.value = count;
  }

  void _readAllowance() {
    if (widget.allowance != null) return;
    _liveAllowance = guideCameraLiveAllowance(guestFree: _guestFree);
    _ensureAd();
    if (_liveAllowance!.kind == GuideAllowanceKind.guest) {
      unawaited(_readGuestFree());
    }
  }

  /// A guest who signs in on this screen was not on the monthly allowance
  /// when the camera opened, so the ad has to load then.
  void _ensureAd() {
    if (widget.onWatchAd != null || _rewardedAd != null || _adLoading) return;
    final kind = _allowance.kind;
    if (kind == GuideAllowanceKind.credits ||
        kind == GuideAllowanceKind.month) {
      _loadAd();
    }
  }

  Future<void> _readGuestFree() async {
    final free = await guideGuestHasFreeName();
    if (!mounted || widget.allowance != null) return;
    setState(() {
      _guestFree = free;
      _liveAllowance = guideCameraLiveAllowance(guestFree: free);
    });
  }

  Future<void> _loadPlace() async {
    try {
      final place = await loadGuideCameraPlace();
      if (!mounted || widget.place != null) return;
      setState(() => _place = place);
    } catch (error) {
      debugPrint('guide camera place: $error');
    }
  }

  void _loadAd() {
    if (!mounted ||
        widget.onWatchAd != null ||
        _rewardedAd != null ||
        _adLoading) {
      return;
    }
    _adLoading = true;
    RewardedAd.load(
      adUnitId: getRewardAdUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _adLoading = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          _rewardedAd = ad;
          _adAttempts = 0;
        },
        onAdFailedToLoad: (error) {
          debugPrint('guide camera ad: $error');
          _adLoading = false;
          _rewardedAd = null;
          _adAttempts += 1;
          if (mounted && _adAttempts <= 3) _loadAd();
        },
      ),
    );
  }

  Future<void> _showRewardedAd() async {
    final ad = _rewardedAd;
    if (ad == null) {
      _adAttempts = 0;
      _loadAd();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).snack_loading_ad)),
      );
      return;
    }
    final done = Completer<void>();
    var earned = false;
    var dismissed = false;
    final before = guideMonthCount.value.adGrants;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        dismissed = true;
        if (_rewardedAd == ad) _rewardedAd = null;
        if (mounted) _loadAd();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (_rewardedAd == ad) _rewardedAd = null;
        if (mounted) _loadAd();
        if (!done.isCompleted) done.complete();
      },
    );
    _rewardedAd = null;
    try {
      await tieRewardedAd(ad);
      await ad.show(
        onUserEarnedReward: (ad, rewardItem) {
          earned = true;
        },
      );
    } catch (error) {
      debugPrint('guide camera ad show: $error');
      ad.dispose();
      if (mounted) _loadAd();
      return;
    }
    await done.future;
    if (dismissed) unawaited(GuideAnalytics.adReward(earned: earned));
    if (earned) await waitForNameGrant(before);
  }

  void _close() {
    _releaseShot();
    final action = widget.onClose;
    if (action != null) {
      action();
      return;
    }
    Navigator.maybePop(context);
  }

  void _key() {
    _releaseShot();
    final action = widget.onKey;
    if (action != null) {
      action();
      return;
    }
    leaveGuideCameraForFind(context);
  }

  Future<void> _signIn() async {
    final action = widget.onSignIn ?? () => openGuideSignIn(context);
    await action();
    if (!mounted) return;
    _readAllowance();
    setState(() {});
  }

  Future<void> _fieldGuide() async {
    final action = widget.onFieldGuide ?? () => openGuideFieldGuide(context);
    await action();
    if (!mounted) return;
    _readAllowance();
    setState(() {
      if (guideCameraCanCapture(_allowance)) _sheet = null;
    });
  }

  Future<void> _watchAd() async {
    final action = widget.onWatchAd ?? _showRewardedAd;
    await action();
    if (!mounted) return;
    _readAllowance();
    setState(() {
      if (guideCameraCanCapture(_allowance)) _sheet = null;
    });
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final action = widget.onAllow ??
          () => allowGuideCameraLocation(
                locate: locateGuideRegion,
                loadPrefs: loadGuideResultPrefs,
                savePrefs: saveGuideResultPrefs,
                saveAllowed: (allowed) async {
                  await Prefs.setBool(keyGuideLocationAllowed, allowed);
                },
              );
      final place = await action();
      if (!mounted) return;
      setState(() => _place = place);
    } catch (error) {
      debugPrint('guide camera location: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_location_unknown)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final action = widget.onDecline ??
          () => declineGuideCameraLocation(
                loadPrefs: loadGuideResultPrefs,
                savePrefs: saveGuideResultPrefs,
                saveAllowed: (allowed) async {
                  await Prefs.setBool(keyGuideLocationAllowed, allowed);
                },
              );
      final place = await action();
      if (!mounted) return;
      setState(() => _place = place);
    } catch (error) {
      debugPrint('guide camera location: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickDefault(GuideCameraSource source) async {
    final maxWidth = MediaQuery.sizeOf(context).width;
    if (source == GuideCameraSource.camera) {
      final shot = await _takePreviewPicture();
      if (shot != null) return shot;
    }
    if (source == GuideCameraSource.gallery) {
      final access = await Permission.accessMediaLocation.status;
      if (!access.isGranted) {
        await Permission.accessMediaLocation.request();
      }
    }
    if (source == GuideCameraSource.gallery) {
      return pickGuideDevicePhoto(maxWidth: maxWidth);
    }
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: maxWidth,
    );
    if (image == null) return null;
    return image.path;
  }

  Future<GuidePhotoPosition?> _phonePosition() async {
    final position = await locateGuidePhone();
    if (position == null) return null;
    return guidePhotoPosition(position.latitude, position.longitude);
  }

  Future<String?> _takePreviewPicture() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isTakingPicture) {
      return null;
    }
    try {
      final shot = await camera.takePicture();
      return shot.path;
    } catch (error) {
      debugPrint('guide camera shutter: $error');
      return null;
    }
  }

  Future<GuideCameraOutcome> _identifyDefault(String path) async {
    final identification = await identifyPlantPhoto(
      image: File(path),
      languageCode: plantIdLanguageTag(Localizations.localeOf(context)),
      maxWidth: MediaQuery.sizeOf(context).width,
      onCreditsChanged: () {
        if (!mounted) return;
        _readAllowance();
        setState(() {});
      },
    );
    if (mounted &&
        Auth.appUser == null &&
        (identification.guestFreeUsed ||
            identification.refusal == PhotoRefusal.signIn)) {
      guideMarkGuestFreeUsed();
      setState(() {
        _guestFree = false;
        _liveAllowance = guideCameraLiveAllowance();
      });
    }
    if (identification.failed) throw StateError('identifyPlant failed');
    switch (identification.refusal) {
      case PhotoRefusal.signIn:
        return const GuideCameraOutcome.refused(GuideCameraOutcomeKind.signIn);
      case PhotoRefusal.noCredits:
      case PhotoRefusal.noNames:
        return const GuideCameraOutcome.refused(GuideCameraOutcomeKind.limit);
      case PhotoRefusal.cooldown:
        return const GuideCameraOutcome.refused(GuideCameraOutcomeKind.tooSoon);
      case PhotoRefusal.repeatPhoto:
        return const GuideCameraOutcome.refused(
            GuideCameraOutcomeKind.samePhoto);
      case PhotoRefusal.dailyCeiling:
        return const GuideCameraOutcome.refused(
            GuideCameraOutcomeKind.pausedToday);
      case null:
        break;
    }
    if (identification.results.isEmpty && identification.charged) {
      return const GuideCameraOutcome.notPlant(counted: true);
    }
    final hits = <GuideCameraHit>[];
    for (final result in identification.results) {
      hits.add(await _cameraHit(result));
    }
    return guideCameraOutcome(hits);
  }

  Future<GuideCameraHit> _cameraHit(SearchResult result) async {
    final latin = result.labelLatin ?? '';
    final family = guideCameraFamilyLatin(result.plantDetails);
    final species = guideCameraSpeciesName(GuideCameraHit(
      latin: latin,
      path: result.path,
    ));
    String? familyLabel;
    String? photo;
    if (mounted && family != null) {
      familyLabel = await _familyVernacular(family);
    }
    if (mounted && species != null) {
      photo = await _catalogPhoto(species);
    }
    return GuideCameraHit(
      latin: latin,
      vernacular: _vernacular(result),
      probability: result.confidence,
      path: result.path,
      familyLatin: family,
      familyLabel: familyLabel,
      photoPath: photo,
    );
  }

  Future<String?> _familyVernacular(String family) async {
    try {
      final lang = getLanguageCode(
        Localizations.localeOf(context).languageCode,
      );
      final event =
          await translationsTaxonomyReference.child(lang).child(family).once();
      return guideTaxonVernacular(event.snapshot.value, family);
    } catch (error) {
      debugPrint('guide camera family $family: $error');
      return null;
    }
  }

  Future<String?> _catalogPhoto(String name) async {
    try {
      final event = await plantsReference.child(name).child('photoUrls').once();
      return guideStoragePhoto(_firstText(event.snapshot.value));
    } catch (error) {
      debugPrint('guide camera photo $name: $error');
      return null;
    }
  }

  /// A catalog species opened from Outside the book stays above that page.
  /// Restarting the preview here would run it under the page.
  void _openCatalogSpecies(String name) {
    final action = widget.onOpenSpecies;
    if (action != null) {
      action(name);
      return;
    }
    unawaited(openGuidePlant(
      context,
      name,
      source: GuidePlantSource.outside,
    ));
  }

  Future<String> _placeLabel() async {
    final given = widget.placeName;
    if (given != null && given.isNotEmpty) return given;
    if (!mounted) return '';
    final none = S.of(context).guide_outside_no_place;
    if (widget.place != null) return none;
    try {
      return await guideCameraPlaceName(
        loadPrefs: loadGuideResultPrefs,
        loadAllowed: () => Prefs.getBoolF(keyGuideLocationAllowed, false),
        regionName: (id) {
          if (!mounted) return '';
          return getFilterDistributionValue(context, id);
        },
        noPlace: none,
      );
    } catch (error) {
      debugPrint('guide camera place name: $error');
      return none;
    }
  }

  String _outsidePlant(GuideCameraOutcome outcome) {
    final latin = outcome.leading?.latin.trim() ?? '';
    if (latin.isNotEmpty) return latin;
    return outcome.leading?.path ?? '';
  }

  Future<void> _pushOutside(GuideCameraOutcome outcome) async {
    final shot = _shotPath;
    final when = _shotWhen ?? DateTime.now();
    final position = _shotPosition;
    final place = await _placeLabel();
    if (!mounted) return;
    final plant = _outsidePlant(outcome);
    final result = await Navigator.push<GuideOutsideResult>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: guideOutsideRouteName),
        builder: (context) => GuideOutsidePage(
          outcome: outcome,
          photoPath: shot,
          when: when,
          place: place,
          latitude: position?.latitude ?? 0,
          longitude: position?.longitude ?? 0,
          onSave: saveGuideCameraFind,
          onConfirm: (id) => setGuideCameraConfirmed(
            id: id,
            plant: plant,
            confirmed: true,
          ),
          onDelete: (id) => deleteGuideCameraFind(id: id, plant: plant),
          onRetarget: (id, from, to) => retargetGuideCameraFind(
            id: id,
            from: from,
            to: to,
          ),
          onOpenSpecies: _openCatalogSpecies,
          onSearch: _openSearch,
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _finishOutside(result);
  }

  Future<void> _finishOutside(GuideOutsideResult result) async {
    final message = result.message;
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
    if (!mounted) return;
    if (result.find) {
      leaveGuideCameraForFind(context);
      return;
    }
    if (result.seen) {
      Navigator.popUntil(context, (route) => route.isFirst);
      GuideTabs.showSeen?.call();
      GuideTabs.refreshSeen?.call();
      return;
    }
    final species = result.openSpecies;
    if (species == null) return;
    final open = widget.onOpenSpecies;
    if (open != null) {
      open(species);
      return;
    }
    await openGuidePlant(
      context,
      species,
      source: GuidePlantSource.outside,
    );
  }

  Future<void> _pushSpecies(
    String name,
    List<GuideCameraHit> lookalikes, {
    double? probability,
  }) async {
    final shot = _shotPath;
    final when = _shotWhen ?? DateTime.now();
    final position = _shotPosition;
    final place = await _placeLabel();
    final id = await saveGuideCameraFind(GuideCameraDraft(
      plant: name,
      when: when,
      shotPath: shot,
      latitude: position?.latitude ?? 0,
      longitude: position?.longitude ?? 0,
      candidates: guideCameraCandidateMaps([
        GuideCameraHit(
          latin: name,
          path: name,
          probability: probability,
        ),
        ...lookalikes,
      ]),
    ));
    if (!mounted) return;
    await openGuidePlant(
      context,
      name,
      source: GuidePlantSource.photo,
      pending: GuideCameraPending(
        plant: name,
        when: when,
        place: place,
        photoPath: shot,
        observationId: id,
        others: lookalikes,
      ),
      onConfirmPending: id == null
          ? null
          : () => setGuideCameraConfirmed(
                id: id,
                plant: name,
                confirmed: true,
              ),
      onUndoPending: id == null
          ? null
          : () => setGuideCameraConfirmed(
                id: id,
                plant: name,
                confirmed: false,
              ),
      onRetargetPending: id == null
          ? null
          : (to) => retargetGuideCameraFind(id: id, from: name, to: to),
      onSearchBook: _openSearch,
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: guideSearchRouteName),
        builder: (context) => GuideSearchPage(
          onOpenPlant: (context, name) => openGuidePlant(
            context,
            name,
            source: GuidePlantSource.search,
          ),
          onOpenTaxon: (context, path) {
            openGuideTaxonList(
              context,
              listPath: path,
              backLabel: S.of(context).guide_back_search,
              onOpenPlant: (context, name) => openGuidePlant(
                context,
                name,
                source: GuidePlantSource.list,
              ),
              onTryPhoto: (context) async {
                Navigator.of(context).popUntil(
                  (route) =>
                      route.settings.name == guideCameraRouteName ||
                      route.isFirst,
                );
              },
            );
          },
          onOpenCamera: (context) => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _openList(String path) {
    final action = widget.onOpenList;
    if (action != null) {
      action(path);
      _endNaming();
      return Future<void>.value();
    }
    return _openThenPreview(() {
      return openGuideTaxonList(
        context,
        listPath: path,
        backLabel: S.of(context).guide_back,
        onOpenPlant: (context, name) => openGuidePlant(
          context,
          name,
          source: GuidePlantSource.photo,
        ),
        onTryPhoto: (listContext) async {
          Navigator.of(listContext).popUntil(
            (route) =>
                route.settings.name == guideCameraRouteName || route.isFirst,
          );
        },
      );
    });
  }

  void _refused(String message) {
    _clearShot();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _endNaming() {
    if (!mounted || !_naming) return;
    setState(() => _naming = false);
  }

  Future<void> _openThenPreview(Future<void> Function() push) async {
    await _stopPreview();
    await push();
    // The find, when there is one, already has its own copy. The cache file
    // still has the original GPS.
    final shot = _shotPath;
    _shotPath = null;
    if (!mounted) {
      if (shot != null) unawaited(deleteDiscardedShot(shot));
      return;
    }
    setState(() {
      _naming = false;
      _shotWhen = null;
      _shotPosition = null;
    });
    if (shot != null) unawaited(deleteDiscardedShot(shot));
    await _startPreview();
  }

  Future<void> _capture(GuideCameraSource source) async {
    if (_busy || _naming) return;
    if (!guideCameraCanCapture(_allowance)) {
      if (_allowance.kind == GuideAllowanceKind.guest) {
        await _signIn();
      } else if (mounted) {
        setState(() => _sheet = _Sheet.limit);
      }
      return;
    }
    setState(() => _busy = true);
    String? path;
    var named = false;
    try {
      final pick = widget.pickPhoto ?? _pickDefault;
      path = await pick(source);
      if (!mounted || path == null) return;
      final previous = _shotPath;
      if (previous != null && previous != path) {
        unawaited(deleteDiscardedShot(previous));
      }
      setState(() {
        _naming = true;
        _shotPath = path;
        _shotWhen = null;
        _shotPosition = null;
        _sheet = null;
      });
      final phone = source == GuideCameraSource.camera &&
              _place != GuideCameraPlace.declined
          ? (widget.phonePosition ?? _phonePosition)()
          : null;
      if (source == GuideCameraSource.gallery) {
        final read = widget.photoTakenAt ?? guideCameraPhotoTakenAt;
        _shotWhen = await read(path);
        if (!mounted) return;
      }
      final locate = widget.photoPosition ?? guideCameraPhotoPosition;
      _shotPosition = await locate(path);
      if (!mounted) return;
      final identify = widget.identify ?? _identifyDefault;
      final outcome = await identify(path);
      named = true;
      unawaited(GuideAnalytics.searchPhoto(
        source: source == GuideCameraSource.camera ? 'camera' : 'gallery',
        outcome: guideCameraAnalyticsOutcome(outcome.kind),
        counted:
            outcome.kind == GuideCameraOutcomeKind.notPlant && outcome.counted,
      ));
      if (!mounted) return;
      if (_shotPosition == null && phone != null) {
        _shotPosition = await phone;
        if (!mounted) return;
      }
      // The naming cover stays up until the find is saved and the next page
      // is open, so Close cannot drop a name that was already spent.
      switch (outcome.kind) {
        case GuideCameraOutcomeKind.species:
          final name = outcome.speciesName;
          final open = widget.onOpenSpecies;
          if (name == null) {
            _endNaming();
          } else if (open != null) {
            open(name);
            _endNaming();
          } else {
            await _openThenPreview(
              () => _pushSpecies(
                name,
                outcome.candidates,
                probability: outcome.leadProbability,
              ),
            );
          }
        case GuideCameraOutcomeKind.list:
          final list = outcome.listPath;
          if (list == null) {
            _endNaming();
          } else {
            await _openList(list);
          }
        case GuideCameraOutcomeKind.outside:
          await _openThenPreview(() => _pushOutside(outcome));
        case GuideCameraOutcomeKind.notPlant:
          if (!mounted) return;
          setState(() {
            _naming = false;
            _notPlantCounted = outcome.counted;
            _sheet = _Sheet.notPlant;
          });
        case GuideCameraOutcomeKind.limit:
          if (!mounted) return;
          setState(() {
            _naming = false;
            _sheet = _Sheet.limit;
          });
        case GuideCameraOutcomeKind.signIn:
          _clearShot();
          await _signIn();
        case GuideCameraOutcomeKind.tooSoon:
          _refused(S.of(context).guide_camera_too_soon);
        case GuideCameraOutcomeKind.samePhoto:
          _refused(S.of(context).guide_camera_same_photo);
        case GuideCameraOutcomeKind.pausedToday:
          _refused(S.of(context).guide_camera_paused_today);
      }
    } catch (error) {
      debugPrint('guide camera: $error');
      if (!named && path != null) {
        unawaited(GuideAnalytics.searchPhoto(
          source: source == GuideCameraSource.camera ? 'camera' : 'gallery',
          outcome: 'error',
        ));
      }
      if (!mounted) return;
      // The still stays in front of the preview unless it is dropped here.
      _clearShot();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).guide_camera_failed)),
      );
    } finally {
      if (!mounted && path != null) {
        if (_shotPath == path) _shotPath = null;
        unawaited(deleteDiscardedShot(path));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final asking = _place == GuideCameraPlace.ask;
    return GuideTheme(
      navigationColor: (_) => _well,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _well,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _well,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _View(
                path: _shotPath,
                camera: _camera,
                livePreview: widget.livePreview,
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x88000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0xBB000000),
                      ],
                      stops: [0, 0.22, 0.64, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = GuideWindow.of(context).wide;
                    final frameLeft = wide ? constraints.maxWidth * 0.10 : 44.0;
                    final frameRight = wide ? 150.0 : 44.0;
                    final frameTop = wide
                        ? constraints.maxHeight * 0.12
                        : (constraints.maxHeight * 0.22).clamp(72.0, 230.0);
                    final frameHeight = wide
                        ? constraints.maxHeight * 0.72
                        : math.min(300.0, constraints.maxHeight * 0.36);
                    final controls = _Controls(
                      column: wide,
                      shutterLabel: strings.guide_camera_shutter,
                      rollLabel: strings.guide_camera_roll,
                      keyLabel: strings.guide_camera_key,
                      onShutter: () => _capture(GuideCameraSource.camera),
                      onRoll: () => _capture(GuideCameraSource.gallery),
                      onKey: _key,
                    );
                    return Stack(
                      children: [
                        Positioned(
                          left: frameLeft,
                          right: frameRight,
                          top: frameTop,
                          height: frameHeight,
                          child: const IgnorePointer(
                            child: CustomPaint(
                              painter: _CornerPainter(),
                              child: SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned(
                          left: wide ? frameLeft : 24,
                          right: wide ? frameRight : 24,
                          top: wide ? null : frameTop + frameHeight + 16,
                          bottom: wide ? 12 : null,
                          child: Text(
                            strings.guide_camera_tip,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 16,
                          right: wide ? 130 : 16,
                          child: _TopBar(
                            label: _meterLabel(strings),
                            meter: guideCameraMeter(_allowance),
                            closeLabel: strings.guide_camera_close,
                            onClose: _close,
                          ),
                        ),
                        if (asking)
                          Positioned(
                            top: 62,
                            left: 14,
                            right: wide ? 140 : 14,
                            child: _AskCard(
                              onAllow: _busy ? null : _allow,
                              onDecline: _busy ? null : _decline,
                            ),
                          ),
                        if (wide)
                          Positioned(
                            top: 64,
                            bottom: 18,
                            right: 18,
                            width: 112,
                            child: controls,
                          )
                        else
                          Positioned(
                            left: 28,
                            right: 28,
                            bottom: 18,
                            child: controls,
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_naming) _Naming(label: strings.guide_camera_naming),
              if (_sheet != null)
                _SheetLayer(
                  onDismiss: _clearShot,
                  child: _sheet == _Sheet.limit
                      ? _LimitSheet(
                          allowance: _allowance,
                          onWatchAd:
                              guideCameraOffersAd(_allowance) ? _watchAd : null,
                          onFieldGuide: _fieldGuide,
                          onKey: _key,
                        )
                      : _NotPlantSheet(
                          allowance: _allowance,
                          counted: _notPlantCounted,
                          onTryAgain: _clearShot,
                          onKey: _key,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _meterLabel(S strings) {
    switch (guideCameraMeter(_allowance).kind) {
      case GuideCameraMeterKind.fieldGuide:
        return strings.guide_camera_field_guide;
      case GuideCameraMeterKind.unlimited:
        return strings.guide_meter_unlimited;
      case GuideCameraMeterKind.signIn:
        return strings.guide_meter_sign_in;
      case GuideCameraMeterKind.namesLeft:
        return strings.guide_meter_left(guideCameraMeter(_allowance).namesLeft);
    }
  }
}

String? _firstText(dynamic raw) {
  if (raw is List) {
    for (final item in raw) {
      if (item != null && item.toString().isNotEmpty) return item.toString();
    }
  } else if (raw is Map) {
    final keys = raw.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      final item = raw[key];
      if (item != null && item.toString().isNotEmpty) return item.toString();
    }
  }
  return null;
}

String? _vernacular(SearchResult result) {
  final language = result.labelInLanguage?.trim() ?? '';
  if (language.isNotEmpty) return language;
  final common = result.commonName?.trim() ?? '';
  if (common.isNotEmpty) return common;
  return null;
}

class GuideCameraDot extends StatelessWidget {
  final bool filled;
  final Color color;

  const GuideCameraDot({
    super.key,
    required this.filled,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}

class _View extends StatelessWidget {
  final String? path;
  final CameraController? camera;
  final WidgetBuilder? livePreview;

  const _View({
    required this.path,
    required this.camera,
    required this.livePreview,
  });

  @override
  Widget build(BuildContext context) {
    final shot = path;
    if (shot != null && File(shot).existsSync()) {
      return Image(
        image: FileImage(File(shot)),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _live(context),
      );
    }
    return _live(context);
  }

  Widget _live(BuildContext context) {
    final camera = this.camera;
    if (camera != null &&
        camera.value.isInitialized &&
        camera.value.aspectRatio > 0) {
      return _LivePreview(controller: camera);
    }
    final fallback = livePreview;
    if (fallback != null) return fallback(context);
    return const SizedBox.expand();
  }
}

class _LivePreview extends StatelessWidget {
  final CameraController controller;

  const _LivePreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String label;
  final GuideCameraMeter meter;
  final String closeLabel;
  final VoidCallback onClose;

  const _TopBar({
    required this.label,
    required this.meter,
    required this.closeLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassButton(
          key: const Key('guide-camera-close'),
          label: closeLabel,
          onPressed: onClose,
          child: const Icon(Icons.close, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: DecoratedBox(
              key: const Key('guide-camera-meter'),
              decoration: BoxDecoration(
                color: _scrim,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (meter.dotCount > 0) ...[
                      for (var i = 0; i < meter.dotCount; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        GuideCameraDot(filled: i < meter.filledDots),
                      ],
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _AskCard extends StatelessWidget {
  final VoidCallback? onAllow;
  final VoidCallback? onDecline;

  const _AskCard({required this.onAllow, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Material(
      key: const Key('guide-camera-ask'),
      color: colors.paper,
      elevation: 8,
      shadowColor: const Color(0x66000000),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.guide_camera_where,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.guide_camera_where_body,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.ink2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Pill(
                  key: const Key('guide-camera-allow'),
                  label: strings.guide_camera_allow,
                  filled: true,
                  onPressed: onAllow,
                ),
                const SizedBox(width: 8),
                _Pill(
                  key: const Key('guide-camera-not-now'),
                  label: strings.guide_camera_not_now,
                  filled: false,
                  onPressed: onDecline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool column;
  final String shutterLabel;
  final String rollLabel;
  final String keyLabel;
  final VoidCallback onShutter;
  final VoidCallback onRoll;
  final VoidCallback onKey;

  const _Controls({
    this.column = false,
    required this.shutterLabel,
    required this.rollLabel,
    required this.keyLabel,
    required this.onShutter,
    required this.onRoll,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final roll = _GlassButton(
      key: const Key('guide-camera-roll'),
      label: rollLabel,
      onPressed: onRoll,
      radius: 10,
      child: const Icon(Icons.photo_outlined, color: Colors.white, size: 22),
    );
    final shutter = Semantics(
      button: true,
      label: shutterLabel,
      child: GestureDetector(
        key: const Key('guide-camera-shutter'),
        onTap: onShutter,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
    final keyButton = _GlassButton(
      key: const Key('guide-camera-key'),
      label: keyLabel,
      onPressed: onKey,
      child: const CustomPaint(
        size: Size(22, 22),
        painter: _KeyPainter(),
      ),
    );
    if (column) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          roll,
          const SizedBox(height: 22),
          shutter,
          const SizedBox(height: 22),
          keyButton,
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [roll, shutter, keyButton],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Widget child;
  final double radius;

  const _GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.radius = 19,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: _scrim,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 48, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _Naming extends StatelessWidget {
  final String label;

  const _Naming({required this.label});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: ColoredBox(
          color: const Color(0x99000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                    backgroundColor: Color(0x44FFFFFF),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetLayer extends StatelessWidget {
  final VoidCallback onDismiss;
  final Widget child;

  const _SheetLayer({required this.onDismiss, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final tablet = GuideWindow.of(context).tablet;
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight =
        tablet ? (height * 0.88 < 680 ? height * 0.88 : 680.0) : height * 0.86;
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x6B1A1612)),
          ),
          Align(
            alignment: tablet ? Alignment.center : Alignment.bottomCenter,
            child: Padding(
              padding: tablet ? const EdgeInsets.all(32) : EdgeInsets.zero,
              child: Material(
                color: colors.paper,
                borderRadius: tablet
                    ? BorderRadius.circular(22)
                    : const BorderRadius.vertical(top: Radius.circular(22)),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: tablet ? 520 : double.infinity,
                    maxHeight: maxHeight,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitSheet extends StatelessWidget {
  final GuideAllowance allowance;
  final VoidCallback? onWatchAd;
  final VoidCallback onFieldGuide;
  final VoidCallback onKey;

  const _LimitSheet({
    required this.allowance,
    required this.onWatchAd,
    required this.onFieldGuide,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final exhausted = guideCameraNamesExhausted(allowance);
    final meter = guideCameraMeter(allowance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Grab(),
        if (meter.dotCount > 0) ...[
          Row(
            children: [
              for (var i = 0; i < meter.dotCount; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                GuideCameraDot(
                  filled: i < meter.filledDots,
                  color: colors.moss,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          exhausted
              ? strings.guide_camera_limit_all_title
              : strings.guide_camera_limit_title,
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
          exhausted
              ? strings.guide_camera_limit_all_body
              : strings.guide_camera_limit_body,
          style: TextStyle(fontSize: 15, height: 1.4, color: colors.ink2),
        ),
        const SizedBox(height: 14),
        if (onWatchAd != null)
          _Choice(
            title: strings.guide_camera_watch_ad,
            note: strings.guide_camera_watch_ad_note,
            icon: Icons.smart_display_outlined,
            iconColor: colors.ink,
            iconGround: colors.paper2,
            onPressed: onWatchAd,
          ),
        _Choice(
          title: strings.guide_camera_field_guide_row,
          note: strings.guide_camera_field_guide_note,
          icon: Icons.eco_outlined,
          iconColor: Colors.white,
          iconGround: colors.mossFill,
          border: colors.moss,
          onPressed: onFieldGuide,
        ),
        _Choice(
          title: strings.guide_camera_key_row,
          note: strings.guide_camera_key_note,
          icon: Icons.apps_outlined,
          iconColor: colors.madder,
          iconGround: colors.paper2,
          onPressed: onKey,
        ),
      ],
    );
  }
}

class _NotPlantSheet extends StatelessWidget {
  final GuideAllowance allowance;
  final bool counted;
  final VoidCallback onTryAgain;
  final VoidCallback onKey;

  const _NotPlantSheet({
    required this.allowance,
    required this.counted,
    required this.onTryAgain,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final meter = guideCameraMeter(allowance);
    final left = meter.kind == GuideCameraMeterKind.namesLeft;
    final kept = counted
        ? strings.guide_camera_not_plant_counted(meter.namesLeft)
        : left
            ? strings.guide_camera_not_plant_left(meter.namesLeft)
            : strings.guide_camera_not_plant_kept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Grab(),
        Text(
          strings.guide_camera_not_plant,
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
          strings.guide_camera_not_plant_body,
          style: TextStyle(fontSize: 15, height: 1.4, color: colors.ink2),
        ),
        const SizedBox(height: 8),
        Text(
          kept,
          style: TextStyle(fontSize: 15, height: 1.4, color: colors.ink2),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _Pill(
            label: strings.guide_camera_try_again,
            filled: true,
            wide: true,
            onPressed: onTryAgain,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onKey,
            child: Text(
              strings.guide_camera_key,
              style: TextStyle(
                color: colors.moss,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String title;
  final String note;
  final IconData icon;
  final Color iconColor;
  final Color iconGround;
  final Color? border;
  final VoidCallback? onPressed;

  const _Choice({
    required this.title,
    required this.note,
    required this.icon,
    required this.iconColor,
    required this.iconGround,
    required this.onPressed,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: border ?? colors.rule, width: border == null ? 1 : 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: iconGround,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
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

class _Grab extends StatelessWidget {
  const _Grab();

  @override
  Widget build(BuildContext context) {
    if (GuideWindow.of(context).tablet) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GuideColors.of(context).rule,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: 36, height: 4),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool filled;
  final bool wide;
  final VoidCallback? onPressed;

  const _Pill({
    super.key,
    required this.label,
    required this.filled,
    required this.onPressed,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size(wide ? double.infinity : 0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        backgroundColor: filled ? colors.mossFill : colors.cream,
        foregroundColor: filled ? Colors.white : colors.ink,
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

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 34.0;
    const radius = 10.0;
    final w = size.width;
    final h = size.height;
    canvas.drawPath(_corner(0, 0, 1, 1, arm, radius), paint);
    canvas.drawPath(_corner(w, 0, -1, 1, arm, radius), paint);
    canvas.drawPath(_corner(0, h, 1, -1, arm, radius), paint);
    canvas.drawPath(_corner(w, h, -1, -1, arm, radius), paint);
  }

  Path _corner(
    double x,
    double y,
    double dx,
    double dy,
    double arm,
    double radius,
  ) {
    return Path()
      ..moveTo(x, y + dy * arm)
      ..lineTo(x, y + dy * radius)
      ..arcToPoint(
        Offset(x + dx * radius, y),
        radius: Radius.circular(radius),
        clockwise: dx == dy,
      )
      ..lineTo(x + dx * arm, y);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KeyPainter extends CustomPainter {
  const _KeyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.12, paint);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (var i = 0; i < 4; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(0, -size.width * 0.2)
          ..quadraticBezierTo(
            size.width * 0.28,
            -size.width * 0.36,
            0,
            -size.width * 0.48,
          )
          ..quadraticBezierTo(
            -size.width * 0.28,
            -size.width * 0.36,
            0,
            -size.width * 0.2,
          ),
        paint,
      );
      canvas.rotate(math.pi / 2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
