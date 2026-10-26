import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/camera/camera_page.dart';
import 'package:abherbs_flutter/field_guide/field_guide_page.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_location.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/key/habitat_page.dart';
import 'package:abherbs_flutter/person/language_page.dart';
import 'package:abherbs_flutter/book/list_page.dart';
import 'package:abherbs_flutter/offline/guide_offline.dart';
import 'package:abherbs_flutter/offline/offline_page.dart';
import 'package:abherbs_flutter/person/person_page.dart';
import 'package:abherbs_flutter/seen/guide_seen.dart';
import 'package:abherbs_flutter/seen/stats_page.dart';
import 'package:abherbs_flutter/key/petal_page.dart';
import 'package:abherbs_flutter/key/results_page.dart';
import 'package:abherbs_flutter/search/search_page.dart';
import 'package:abherbs_flutter/person/sign_in_page.dart';
import 'package:abherbs_flutter/species/species_page.dart';
import 'package:abherbs_flutter/main.dart';
import 'package:abherbs_flutter/person/setting_utils.dart';
import 'package:abherbs_flutter/person/account_deletion.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/shell/dialogs.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
export 'package:abherbs_flutter/field_guide/field_guide_page.dart'
    show openGuideFieldGuide;
export 'package:abherbs_flutter/species/species_page.dart' show openGuidePlant;

void openGuideSearch(
  BuildContext context, {
  bool fromBook = false,
  VoidCallback? onShowFind,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => GuideSearchPage(
        fromBook: fromBook,
        onShowFind: onShowFind,
        onOpenPlant: (context, name) => openGuidePlant(
          context,
          name,
          source: GuidePlantSource.search,
        ),
        onOpenTaxon: (context, path) => openGuideTaxon(
          context,
          path,
          backLabel: S.of(context).guide_back_search,
        ),
        onOpenCamera: openGuideCamera,
      ),
      settings: const RouteSettings(name: guideSearchRouteName),
    ),
  );
}

void openGuideTaxon(
  BuildContext context,
  String listPath, {
  String? title,
  String? backLabel,
}) {
  openGuideTaxonList(
    context,
    listPath: listPath,
    title: title,
    backLabel: backLabel ?? S.of(context).guide_back,
    onOpenPlant: (context, name) => openGuidePlant(
      context,
      name,
      source: GuidePlantSource.list,
    ),
    onTryPhoto: openGuideCamera,
  );
}

RouteSettings _customListSettings(String listId) {
  final id = guideAnalyticsListId(listId);
  return RouteSettings(
    name: guideCustomRouteName,
    arguments: id.isEmpty ? null : id,
  );
}

void _openListedPlant(BuildContext context, String name, String source) {
  openGuidePlant(context, name, source: source);
}

void openGuideAccount(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guidePersonRouteName),
      builder: (context) => GuidePersonPage(
        onSignIn: openGuideSignIn,
        onSignOut: guideSignOut,
        onDeleteAccount: guideDeleteAccount,
        onRestore: guideRestorePurchases,
        onLanguage: openGuideLanguage,
        onFieldGuide: openGuideFieldGuide,
        onOffline: openGuideOffline,
        onStatistics: (context) =>
            openGuideStatistics(context, fromPerson: true),
      ),
    ),
  );
}

Future<void> guideSignOut(BuildContext context) {
  return Auth.signOut();
}

Future<void> guideDeleteAccount(BuildContext context) async {
  final result = await confirmAndDeleteAccount(context);
  if (!context.mounted) {
    return;
  }
  showDeleteAccountResult(context, result);
  if (result == DeleteAccountResult.success) {
    Navigator.of(context).pop();
  }
}

Future<void> guideRestorePurchases(BuildContext context) async {
  final store = InAppPurchase.instance;
  final available = await store.isAvailable();
  if (!context.mounted) return;
  if (!available) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).product_purchase_failed)),
    );
    return;
  }
  await store.restorePurchases();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(S.of(context).guide_person_restoring)),
  );
}

Future<void> openGuideLanguage(BuildContext context) async {
  final saved = await preferredLanguageTag();
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideLanguageRouteName),
      builder: (context) => GuideLanguagePage(
        selectedKey:
            saved.isEmpty ? '' : (languageListKey(languages, saved) ?? saved),
        // The phone's language, not the language currently on screen.
        phoneName: guideLanguageName(languages, '', getDeviceLocale()),
        options: guideLanguageOptions(languages),
        onChoose: _storeGuideLanguage,
      ),
    ),
  );
  if (!context.mounted) return;
  final language = await preferredLanguageTag();
  if (!context.mounted) return;
  App.setLocale(context, language);
  if (language == saved) return;
  unawaited(GuideAnalytics.language(language));
}

Future<void> _storeGuideLanguage(String key) async {
  if (key.isEmpty) {
    await Prefs.remove(keyPreferredLanguage);
    return;
  }
  await Prefs.setString(keyPreferredLanguage, key);
}

Future<void> openGuideStatistics(
  BuildContext context, {
  List<GuideSeenFind>? finds,
  bool sightings = false,
  String? backLabel,
  bool fromPerson = false,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      settings: const RouteSettings(name: guideStatsRouteName),
      builder: (context) => GuideStatsPage(
        finds: finds,
        sightings: sightings,
        fromPerson: fromPerson,
        backLabel: backLabel ?? S.of(context).guide_back,
      ),
    ),
  );
}

Future<void> openGuideOffline(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      settings: const RouteSettings(name: guideOfflineRouteName),
      builder: (context) => GuideOfflinePage(
        onFieldGuide: () => openGuideFieldGuide(context),
      ),
    ),
  );
}

void openGuideColor(BuildContext context, String colorId) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideHabitatRouteName),
      builder: (context) => GuideHabitatPage(
        colorId: colorId,
        onContinue: (habitatId) => openGuidePetals(
          context,
          colorId: colorId,
          habitatId: habitatId,
        ),
      ),
    ),
  );
}

void openGuidePetals(
  BuildContext context, {
  required String colorId,
  String? habitatId,
}) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guidePetalRouteName),
      builder: (context) => GuidePetalPage(
        colorId: colorId,
        habitatId: habitatId,
        onContinue: (petalId) => openGuideResults(
          context,
          colorId: colorId,
          habitatId: habitatId,
          petalId: petalId ?? '',
        ),
      ),
    ),
  );
}

void openGuideResults(
  BuildContext context, {
  required String colorId,
  String? habitatId,
  required String petalId,
}) {
  final language = Localizations.localeOf(context).languageCode;
  // Skip, back, skip would otherwise push a second list. The upper page's
  // Petals control would then return to the old list. One results route
  // stays above the petal step.
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideResultsRouteName),
      builder: (context) => GuideResultsPage(
        colorId: colorId,
        habitatId: habitatId,
        petalId: petalId,
        loadResults: (regionId) => loadGuideResults(
          colorId: colorId,
          habitatId: habitatId,
          petalId: petalId,
          regionId: regionId,
          languageCode: language,
        ),
        loadPrefs: loadGuideResultPrefs,
        savePrefs: saveGuideResultPrefs,
        loadSeen: loadGuideSeenNames,
        loadRegionCounts: () => loadGuideRegionCounts(
          colorId: colorId,
          habitatId: habitatId,
          petalId: petalId,
        ),
        locate: locateGuideRegion,
        onOpenPlant: (context, name) => _openListedPlant(
          context,
          name,
          GuidePlantSource.key,
        ),
        onTryPhoto: openGuideCamera,
      ),
    ),
    (route) => route.settings.name != guideResultsRouteName,
  );
}

/// A list notification opens the field-guide list for that database path.
MaterialPageRoute<dynamic> guideNotificationListRoute(
  String path, {
  String? title,
}) {
  var value = path.trim();
  if (value.startsWith('/')) value = value.substring(1);
  final given = title?.trim() ?? '';
  final parts = value.split('/').where((part) => part.isNotEmpty).toList();
  final fallback = parts.isEmpty ? '' : parts.last;
  return MaterialPageRoute<dynamic>(
    settings: _customListSettings(value),
    builder: (context) {
      final language = Localizations.localeOf(context).languageCode;
      return GuideResultsPage(
        colorId: '',
        habitatId: null,
        petalId: '',
        listTitle: given.isEmpty ? fallback : given,
        listBackLabel: S.of(context).guide_back,
        loadResults: (_) =>
            loadGuideListedPlants(rootReference.child(value), language),
        loadPrefs: () async => const GuideResultPrefs(),
        savePrefs: (_) async {},
        loadSeen: loadGuideSeenNames,
        loadRegionCounts: () async => const {},
        locate: () async => null,
        onOpenPlant: (context, name) => _openListedPlant(
          context,
          name,
          GuidePlantSource.notification,
        ),
        onTryPhoto: openGuideCamera,
      );
    },
  );
}

/// The connectivity read. Tests set this so a tap does not ask the device.
@visibleForTesting
Future<List<ConnectivityResult>> Function()? debugGuideConnectivity;

/// A stored pack. Tests set this so a tap does not read the phone's prefs.
@visibleForTesting
Future<bool> Function()? debugGuidePackOnPhone;

/// True when the phone has a connection. With none, shows the same dialog
/// as Name it from a photo and returns false.
Future<bool> guideReachable(BuildContext context) async {
  final read = debugGuideConnectivity ?? Connectivity().checkConnectivity;
  final result = await read();
  if (!context.mounted) return false;
  if (result.contains(ConnectivityResult.none)) {
    infoDialog(
      context,
      S.of(context).no_connection_title,
      S.of(context).no_connection_content,
    );
    return false;
  }
  return true;
}

Future<bool> _packOnPhone() async {
  final read = debugGuidePackOnPhone;
  if (read != null) return read();
  try {
    return guidePackOnPhone(
      packs: await Prefs.getStringF(keyGuideOfflinePacks, ''),
      classic: await Prefs.getBoolF(keyOffline, false),
      done: await Prefs.getStringF(keyGuideOfflineDone, ''),
    );
  } catch (error) {
    debugPrint('guide pack: $error');
    return false;
  }
}

/// Book and its lists. A pack already on the phone opens with no connection.
/// Otherwise the same dialog as Name it from a photo.
Future<bool> guideBookAvailable(BuildContext context) async {
  if (await _packOnPhone()) return true;
  return guideReachable(context);
}

Future<void> openGuideList(
  BuildContext context,
  GuideListCover cover, {
  String? backLabel,
}) async {
  if (!await guideBookAvailable(context)) return;
  if (!context.mounted) return;
  final back = backLabel ?? S.of(context).guide_back;
  final language = Localizations.localeOf(context).languageCode;
  final source =
      cover.isFavorite ? GuidePlantSource.favorite : GuidePlantSource.list;
  final listId = cover.isFavorite
      ? 'favorites'
      : cover.isNew
          ? 'new'
          : cover.path.path;
  switch (guideCustomLayout(cover)) {
    case GuideCustomLayout.fresh:
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: _customListSettings(listId),
          builder: (context) => GuideNewPage(
            backLabel: back,
            loadDays: () => loadGuideNewDays(language),
            loadSeen: loadGuideSeenNames,
            onOpenPlant: (context, name) =>
                _openListedPlant(context, name, source),
          ),
        ),
      );
    case GuideCustomLayout.years:
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: _customListSettings(listId),
          builder: (context) => GuideYearPage(
            title: cover.title,
            backLabel: back,
            loadList: () => loadGuideYearList(cover.path, language),
            loadSeen: loadGuideSeenNames,
            onOpenPlant: (context, name) =>
                _openListedPlant(context, name, source),
            onOpenGenus: (context, path, genus) => openGuideTaxon(
              context,
              path,
              title: genus,
            ),
          ),
        ),
      );
    case GuideCustomLayout.grid:
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: _customListSettings(listId),
          builder: (context) => GuideResultsPage(
            colorId: '',
            habitatId: null,
            petalId: '',
            listTitle: guideListTitle(context, cover),
            listEmpty:
                cover.isFavorite ? S.of(context).guide_favorite_empty : null,
            listBackLabel: back,
            loadResults: (_) => loadGuideListedPlants(cover.path, language),
            loadPrefs: () async => const GuideResultPrefs(),
            savePrefs: (_) async {},
            loadSeen: loadGuideSeenNames,
            loadRegionCounts: () async => const {},
            locate: () async => null,
            onOpenPlant: (context, name) =>
                _openListedPlant(context, name, source),
            onTryPhoto: openGuideCamera,
          ),
        ),
      );
  }
}

Future<void> openGuideCamera(BuildContext context) async {
  if (!await guideReachable(context)) return;
  if (!context.mounted) return;
  _pushCamera(context);
}

void _pushCamera(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideCameraRouteName),
      builder: (context) => const GuideCameraPage(),
    ),
  );
}
