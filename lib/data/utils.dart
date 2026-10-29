import 'dart:async';
import 'dart:io';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:exif/exif.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String productNoAdsAndroid = "no_ads";
const String productNoAdsIOS = "NoAds";
const String productOffline = "offline";
const String productObservations = "observations";
const String productPhotoSearch = "search_by_photo";
const String subscriptionMonthly = "store_photos_monthly";
const String subscriptionYearly = "store_photos_yearly";
const String fieldGuideMonthly = "field_guide_monthly";
const String fieldGuideYearly = "field_guide_yearly";

const String keyLanguageAndCountry = "language_country";
const String keyPreferredLanguage = "pref_language";
const String keyMyRegion = "my_region";
const String keyGuideRegion = "guide_region";
const String keyGuideRegionFromLocation = "guide_region_from_location";
const String keyGuideWildOnly = "guide_wild_only";
const String keyGuideSeenHideShared = "guide_seen_hide_shared";
const String keyGuideLocationRefused = "guide_location_refused";
const String keyGuideLocationAllowed = "guide_location_allowed";
const String keyGuideTheme = "guide_theme";
const String keyVersionBlockFloor = "version_block_floor";
const String keyVersionBannerDismissed = "version_banner_dismissed";
const String keyGuideOfflinePacks = "guide_offline_packs";
const String keyGuideOfflineTotal = "guide_offline_total";
const String keyGuideOfflineStoredPlants = "guide_offline_stored_plants";
const String keyGuideOfflineDone = "guide_offline_done";
const String keyGuideOfflineChange = "guide_offline_change";
const String keyOffline = "offline";
const String keyOfflinePlant = "offline_plant";
const String keyOfflineFamily = "offline_family";
const String keyOfflineDB = "offline_db";
const String keyPurchases = "purchases";
const String keyToken = "token";
const String keyOldVersion = "old_version";
const String keyGuestCreated = "guest_created";
const String keyGuestFreeUsed = "guest_free_used";
const String keyGuideMonthCount = "guide_month_count";

const String playStore = "market://details?id=sk.ab.herbs";
const String appStoreListing = "https://apps.apple.com/app/id1449982118";

const String languageLatin = "la";
const String languageEnglish = "en";
const String languageSlovak = "sk";
const String languageGerman = "de";
const String languageFrench = "fr";
const String languageCzech = "cs";
const String languagePolish = "pl";
const String languageRussian = "ru";
const String languageSpanish = "es";
const String languagePortuguese = "pt";
const String languageJapanese = "ja";
const String languageItalian = "it";
const String languageDutch = "nl";
const String languageUkrainian = "uk";
const String languageHungarian = "hu";
const String languageDanish = "da";
const String languageSwedish = "sv";
const String languageNorwegian = "no";
const String languageFinnish = "fi";
const String languageEstonian = "et";
const String languageLatvian = "lv";
const String languageLithuanian = "lt";
const String languageCroatian = "hr";
const String languageSlovenian = "sl";
const String languageSerbian = "sr";
const String languageBulgarian = "bg";
const String languageRomanian = "ro";
const String languageHindi = "hi";
const String languageKorean = "ko";
const String languageChinese = "zh";
const String languagePersian = "fa";
const String languageHebrew = "he";
const String languageArabic = "ar";
const String languageIndonesian = "id";
const String languageTurkish = "tr";

const String webUrl = "https://whatsthatflower.com/";

/// Website path prefixes (English is unprefixed). Keep in sync with web/src/lib.js INDEXED_LANGS.
const List<String> webPathLanguages = [
  languageSlovak,
  languageGerman,
  languageFrench,
  languageCzech,
  languagePolish,
  languageRussian,
  languageSpanish,
  languagePortuguese,
  languageJapanese,
  languageItalian,
  languageDutch,
  languageUkrainian,
  languageHungarian,
  languageDanish,
  languageSwedish,
  languageNorwegian,
  languageFinnish,
  languageEstonian,
  languageLatvian,
  languageLithuanian,
  languageCroatian,
  languageSlovenian,
  languageSerbian,
  languageBulgarian,
  languageRomanian,
  languageHindi,
  languageKorean,
  languageChinese,
  languagePersian,
  languageHebrew,
  languageArabic,
  languageIndonesian,
  languageTurkish,
];
const String termsOfUseUrl =
    "https://storage.googleapis.com/abherbs-resources/misc/TermsOfServiceofWhatsthatflower.htm";
const String privacyPolicyUrl =
    "https://storage.googleapis.com/abherbs-resources/misc/PrivacyPolicyofWhatsthatflower.htm";
const String storageBucket = "gs://abherbs-resources";
const String storageEndpoint =
    "https://storage.googleapis.com/abherbs-resources/";
const String storageFamilies = "families/";
const String storagePhotos = "photos/";
const String storageObservations = "observations/";

/// Owner-only copies of Seen photos. Shared Sightings stay under
/// [storageObservations].
const String storagePrivate = "private/";
const String defaultExtension = ".webp";
const String defaultPhotoExtension = ".jpg";
const double imageSizeScaleDown = 2048;

const int firebaseCacheSize = 1024 * 1024 * 20;
const String firebaseCountsV3 = 'counts_4_v3';
const String firebaseListsV3 = 'lists_4_v3';
const String firebasePlants = 'plants_v2';
const String firebaseSearch = 'search_v3';
const String firebaseAPGIV = 'APG IV_v3';
const String firebaseListsCustom = 'lists_custom';
const String firebaseAttributeSourceUrl = 'sourceUrl';

/// Custom-list `list/{id}` values of 1900–2100 are designation years
/// (Blume / Baum / Orchidee des Jahres). Presence-only lists still use `1`.
/// Old clients ignore the number and only read the plant-id keys.
const int customListYearMin = 1900;
const int customListYearMax = 2100;

int? customListYear(dynamic value) {
  int? n;
  if (value is int) {
    n = value;
  } else if (value is num) {
    n = value.toInt();
  }
  if (n == null || n < customListYearMin || n > customListYearMax) {
    return null;
  }
  return n;
}

/// A state name, not a year and not the membership value `1`.
bool customListStateName(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  return RegExp(r'[A-Za-z]').hasMatch(text);
}

/// State names stored on one plant. One state is a string. Several states
/// are a map whose keys are the state names.
List<String> customListStates(dynamic value) {
  if (value is String) {
    final text = value.trim();
    if (!customListStateName(text)) return const [];
    return [text];
  }
  if (value is Map) {
    final names = <String>[];
    value.forEach((key, child) {
      if (child == null || child == false) return;
      final name = key.toString().trim();
      if (customListStateName(name)) names.add(name);
    });
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }
  return const [];
}

const String firebasePlantHeaders = 'plants_headers';
const String firebasePlantHeadersV3 = 'plants_headers_v3';
const String firebaseTranslations = 'translations';
const String firebaseTranslationsTaxonomy = 'translations_taxonomy';
const String firebasePlantsToUpdate = "plants_to_update";
const String firebaseCatalogChanges = "catalog_changes";
const String firebaseFamiliesToUpdate = "families_to_update";
const String firebaseVersions = "versions";
const String firebaseUsers = "users";
const String firebaseSynonyms = "synonyms";
const String firebaseUsersPhotoSearch = "users_photo_search";
const String firebasePhotoQuota = "photo_quota";
const String firebaseAttributeAnonymousFreeUsed = "anonymousFreeUsed";
const String firebaseSearchPhoto = 'search_photo';
const String firebaseObservationsPublic = "observations/public";
const String firebaseObservationsPrivate = "observations/by users";
const String firebaseObservationsLogs = "observations/logs";
const String firebaseCreditsLogs = "credits";
const String firebaseObservationsByDate = "by date";
const String firebaseObservationsByPlant = "by plant";
const String firebaseObservationsStats = "stats";

const String firebaseRootTaxon = 'Eukaryota';
const String firebaseAPGType = "type";
const String firebaseAttributeFreebase = "freebase";
const String firebaseAttributeList = "list";

/// Genus-only rows on a custom list. A sibling of [firebaseAttributeList].
/// The store app never reads it. Keys inside `list` stay numeric plant ids.
const String firebaseAttributeGenera = "genera";
const String firebaseAttributeCount = "count";
const String firebaseAttributeIOS = "ios";
const String firebaseAttributeAndroid = "android";
const String firebaseAttributeLastUpdate = "db_update";
const String firebaseAttributeName = "name";
const String firebaseAttributeUrl = "url";
const String firebaseAttributeLabel = "label";
const String firebaseAttributeOrder = "order";
const String firebaseAttributeOldVersion = "old version";
const String firebaseAttributeToken = "token";
const String firebaseAttributePurchases = "purchases";
const String firebaseAttributeCredits = "credits";
const String firebaseAttributeFavorite = "favorites";
const String firebaseAttributeEntity = "m";
const String firebaseAttributeAnonymous = "anonymous";
const String firebaseAttributeIsLabel = "is_label";

const String firebaseValueReview = "review";
const String firebaseValuePublic = "public";
const String firebaseValueRejection = "rejected";

const String notificationAttributeAction = "action";
const String notificationAttributeActionList = "list";
const String notificationAttributeActionBrowse = "browse";
const String notificationAttributeActionPlant = "plant";
const String notificationAttributePath = "path";
const String notificationAttributeUri = "uri";
const String notificationAttributeName = "name";

const String remoteMinAndroidBuild = "min_android_build";
const String remoteMinIosBuild = "min_ios_build";

final DatabaseReference rootReference = FirebaseDatabase.instance.ref();
final DatabaseReference countsV3Reference =
    rootReference.child(firebaseCountsV3);
final DatabaseReference listsV3Reference = rootReference.child(firebaseListsV3);
final DatabaseReference headersV3Reference =
    rootReference.child(firebasePlantHeadersV3);
final DatabaseReference listsReference =
    rootReference.child(firebasePlantHeaders);
final DatabaseReference listsCustomReference =
    rootReference.child(firebaseListsCustom);
final DatabaseReference translationsReference =
    rootReference.child(firebaseTranslations);
final DatabaseReference translationsTaxonomyReference =
    rootReference.child(firebaseTranslationsTaxonomy);
final DatabaseReference plantsReference = rootReference.child(firebasePlants);
final DatabaseReference searchReference = rootReference.child(firebaseSearch);
final DatabaseReference apgIVReference = rootReference.child(firebaseAPGIV);
final DatabaseReference publicObservationsReference =
    rootReference.child(firebaseObservationsPublic);
final DatabaseReference privateObservationsReference =
    rootReference.child(firebaseObservationsPrivate);
final DatabaseReference logsObservationsReference =
    rootReference.child(firebaseObservationsLogs);
final DatabaseReference logsCreditsReference =
    rootReference.child(firebaseCreditsLogs);
final DatabaseReference usersReference = rootReference.child(firebaseUsers);

Map<String, String> translationCache = {};

bool get isInDebugMode {
  bool inDebugMode = false;
  assert(inDebugMode = true);
  return inDebugMode;
}

/// DNS / offline / TLS failures while loading a photo. Not an app bug.
bool isTransientNetworkError(Object error) {
  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is TlsException ||
      error is TimeoutException) {
    return true;
  }
  final type = error.runtimeType.toString();
  if (type.contains('ClientException') ||
      type.contains('SocketException') ||
      type.contains('HttpException') ||
      type.contains('HandshakeException')) {
    return true;
  }
  final text = error.toString();
  return text.contains('Failed host lookup') ||
      text.contains('No address associated with hostname') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection refused') ||
      text.contains('Connection reset') ||
      text.contains('Connection closed') ||
      text.contains('Connection timed out') ||
      text.contains('Software caused connection abort') ||
      text.contains('ClientException');
}

/// EventChannel `cancel` after the engine/plugin is already gone (screen pop, process death).
bool isIgnorablePluginTeardown(Object error) {
  final text = error.toString();
  return text.contains('MissingPluginException') &&
      text.contains('method cancel');
}

bool isIgnorableNonFatalError(Object error) {
  return isTransientNetworkError(error) || isIgnorablePluginTeardown(error);
}

bool isIgnorableFlutterError(FlutterErrorDetails details) {
  if (details.library == 'image resource service') {
    return true;
  }
  return isIgnorableNonFatalError(details.exception);
}

void launchURL(String path) async {
  try {
    final url = Uri.parse(path);
    if (!await launchUrl(url)) {
      debugPrint('Could not launch $url');
    }
  } catch (error) {
    debugPrint('Could not launch $path: $error');
  }
}

double getLatitudeFromExif(IfdTag? latitudeRef, IfdTag? latitude) {
  if (latitude != null) {
    double latDegrees = latitude.values.toList()[0].numerator /
        latitude.values.toList()[0].denominator;
    double latMinutes = latitude.values.toList()[1].numerator /
        latitude.values.toList()[1].denominator;
    double latSeconds = latitude.values.toList()[2].numerator /
        latitude.values.toList()[2].denominator;

    int northSouth = latitudeRef.toString() == 'N' ? 1 : -1;
    return northSouth * (latDegrees + latMinutes / 60 + latSeconds / 60 / 60);
  } else {
    return 0.0;
  }
}

double getLongitudeFromExif(IfdTag? longitudeRef, IfdTag? longitude) {
  if (longitude != null) {
    double longDegrees = longitude.values.toList()[0].numerator /
        longitude.values.toList()[0].denominator;
    double longMinutes = longitude.values.toList()[1].numerator /
        longitude.values.toList()[1].denominator;
    double longSeconds = longitude.values.toList()[2].numerator /
        longitude.values.toList()[2].denominator;

    int eastWest = longitudeRef.toString() == 'E' ? 1 : -1;
    return eastWest * (longDegrees + longMinutes / 60 + longSeconds / 60 / 60);
  } else {
    return 0.0;
  }
}

DateTime getDateTimeFromExif(IfdTag? dateTime) {
  if (dateTime != null) {
    var dateParts = dateTime.toString().split(' ');
    var datePart = dateParts[0].split(':');
    var timePart = dateParts[1].split(':');
    return DateTime(
        int.parse(datePart[0]),
        int.parse(datePart[1]),
        int.parse(datePart[2]),
        int.parse(timePart[0]),
        int.parse(timePart[1]),
        int.parse(timePart[2]));
  } else {
    return DateTime.now();
  }
}

/// Reads a missing local Seen photo from the owner's private Storage
/// prefix. The field guide sets this. Left unset, [getImage] uses the
/// public URL, which is how Sightings already load.
typedef GuidePrivatePhotoFetch = Future<File?> Function(String path);

GuidePrivatePhotoFetch? guidePrivatePhotoFetch;

/// Uploads Seen photos for a Field Guide account. The old observation editor
/// calls this without importing the guide library.
typedef GuidePrivatePhotoSync = Future<void> Function({String? onlyId});

GuidePrivatePhotoSync? guideSyncPrivatePhotos;

typedef GuidePrivatePhotoDelete = Future<void> Function(Iterable<String> paths);

GuidePrivatePhotoDelete? guideDeletePrivatePhotos;

void Function(String id)? guideSkipPrivatePhoto;

Future<File?> _localImage(String url) async {
  final local = await Offline.getLocalFile(url);
  if (local != null) return local;
  final fetch = guidePrivatePhotoFetch;
  if (fetch == null) return null;
  try {
    return await fetch(url);
  } catch (error) {
    debugPrint('private photo $url: $error');
    return null;
  }
}

/// Replaces the disk lookup in tests. Production leaves this null.
@visibleForTesting
Future<File?> Function(String url, String? cover)? debugResolveThumb;

/// The file for a thumbnail. A photo already on the phone wins. When that
/// file is missing, [cover] is the book photo from an offline pack.
Future<File?> _thumbFile(String url, String? cover) async {
  final own = await Offline.getLocalFile(url);
  if (own != null) return own;
  if (cover != null && cover.isNotEmpty && cover != url) {
    final book = await Offline.getLocalFile(cover);
    if (book != null) return book;
  }
  return _localImage(url);
}

Widget getImage(String url, Widget placeholder,
    {String? cover,
    double width = 50.0,
    double height = 50.0,
    BoxFit fit = BoxFit.contain}) {
  return _ResolvedThumb(
    url: url,
    cover: cover,
    placeholder: placeholder,
    width: width,
    height: height,
    fit: fit,
  );
}

/// Keeps the disk lookup alive across rebuilds.
///
/// A future created in [build] shows the placeholder again on every parent
/// rebuild. Find paints several times as it opens (lists, the account, a
/// second read of Seen lately), and each pass flashed thumbnails that were
/// already on screen.
class _ResolvedThumb extends StatefulWidget {
  final String url;
  final String? cover;
  final Widget placeholder;
  final double width;
  final double height;
  final BoxFit fit;

  const _ResolvedThumb({
    required this.url,
    required this.cover,
    required this.placeholder,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  State<_ResolvedThumb> createState() => _ResolvedThumbState();
}

class _ResolvedThumbState extends State<_ResolvedThumb> {
  File? _file;
  var _ready = false;
  var _token = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ResolvedThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cover != widget.cover) {
      _resolve();
    }
  }

  void _resolve() {
    final url = widget.url;
    final cover = widget.cover;
    final token = ++_token;
    // A photo already on screen stays there. Blanking here is the flash:
    // the next finds read often carries the same file with a new cover.
    unawaited(_load(url, cover, token));
  }

  Future<void> _load(String url, String? cover, int token) async {
    File? file;
    try {
      final resolve = debugResolveThumb ?? _thumbFile;
      file = await resolve(url, cover);
    } catch (error) {
      debugPrint('thumb $url: $error');
    }
    if (!mounted || token != _token) return;
    setState(() {
      _file = file;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return widget.placeholder;
    final file = _file;
    if (file != null) {
      return Image.file(
        file,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _broken(context),
      );
    }
    return CachedNetworkImage(
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: (context, url) => widget.placeholder,
      errorWidget: (context, url, error) => _broken(context),
      imageUrl: storageEndpoint + widget.url,
    );
  }

  Widget _broken(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      child: Icon(
        Icons.error,
        color: Theme.of(context).secondaryHeaderColor,
        size: 80.0,
      ),
    );
  }
}

String getTaxonLabel(BuildContext context, String taxon) {
  switch (taxon) {
    case 'Superregnum':
      return S.of(context).taxonomy_superregnum;
    case 'Regnum':
      return S.of(context).taxonomy_regnum;
    case 'Cladus':
      return S.of(context).taxonomy_cladus;
    case 'Ordo':
      return S.of(context).taxonomy_ordo;
    case 'Familia':
      return S.of(context).taxonomy_familia;
    case 'Subfamilia':
      return S.of(context).taxonomy_subfamilia;
    case 'Tribus':
      return S.of(context).taxonomy_tribus;
    case 'Subtribus':
      return S.of(context).taxonomy_subtribus;
    case 'Genus':
      return S.of(context).taxonomy_genus;
    case 'Subgenus':
      return S.of(context).taxonomy_subgenus;
    case 'Supersectio':
      return S.of(context).taxonomy_supersectio;
    case 'Sectio':
      return S.of(context).taxonomy_sectio;
    case 'Subsectio':
      return S.of(context).taxonomy_subsectio;
    case 'Serie':
      return S.of(context).taxonomy_serie;
    case 'Subserie':
      return S.of(context).taxonomy_subserie;
    default:
      return S.of(context).taxonomy_unknown;
  }
}

String getLanguageCode(String code) {
  return code == 'nb' ? 'no' : code;
}

/// Encyclopedia URL for [path] in [languageCode]. Indexed languages use /de/…;
/// English is unprefixed; other UI languages keep ?lang=. Keep in sync with
/// web/src/lib.js INDEXED_LANGS.
String webPageUrl(String path, String languageCode) {
  final lang = getLanguageCode(languageCode);
  var pathname = path.startsWith('/') ? path : '/$path';
  if (pathname.length > 1 && pathname.endsWith('/')) {
    pathname = pathname.substring(0, pathname.length - 1);
  }
  String body;
  if (webPathLanguages.contains(lang)) {
    body = pathname == '/' ? '/$lang' : '/$lang$pathname';
  } else {
    body = pathname;
  }
  if (!body.endsWith('/')) {
    body = '$body/';
  }
  final origin = webUrl.substring(0, webUrl.length - 1);
  if (lang != languageEnglish && !webPathLanguages.contains(lang)) {
    return '$origin$body?lang=$lang';
  }
  return '$origin$body';
}

String webPlantUrl(String latinName, String languageCode) {
  return webPageUrl('plant/${Uri.encodeComponent(latinName)}', languageCode);
}
