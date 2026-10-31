import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/l10n/app_locale.dart';
import 'package:abherbs_flutter/person/setting_utils.dart';
import 'package:abherbs_flutter/shell/guide_actions.dart';
import 'package:abherbs_flutter/shell/guide_links.dart';
import 'package:abherbs_flutter/shell/guide_fold.dart';
import 'package:abherbs_flutter/shell/guide_shell.dart';
import 'package:abherbs_flutter/book/list_page.dart';
import 'package:abherbs_flutter/species/species_page.dart';
import 'package:abherbs_flutter/purchase/owned_purchases.dart';
import 'package:abherbs_flutter/purchase/store_proof.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/shell/ad_consent.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:abherbs_flutter/shell/meta_ads.dart';
import 'package:abherbs_flutter/shell/app_version.dart';
import 'package:abherbs_flutter/shell/app_version_check.dart';
import 'package:abherbs_flutter/shell/settings_remote.dart';
import 'package:abherbs_flutter/shell/version_gate.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/shell/dialogs.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/shell/safe_focus_traversal.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:app_links/app_links.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'firebase_options.dart';

void _iapError() {
  Fluttertoast.showToast(
      msg: 'IAP not prepared. Check if Platform service is available.',
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 5,
      backgroundColor: Colors.redAccent);
}

Future<void> initializeFlutterFire() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    providerAndroid: isInDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: isInDebugMode
        ? const AppleDebugProvider()
        : const AppleDeviceCheckProvider(),
  );
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  FirebaseDatabase.instance.setPersistenceCacheSizeBytes(firebaseCacheSize);

  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!isInDebugMode);

  await RemoteConfiguration.setupRemoteConfig();

  FlutterError.onError = (details) {
    if (isIgnorableFlutterError(details)) {
      return;
    }
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (isIgnorableNonFatalError(error)) {
      return true;
    }
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

String? notificationTitle(RemoteMessage message) {
  return message.notification?.title ?? message.data['title'];
}

String? notificationBody(RemoteMessage message) {
  return message.notification?.body ?? message.data['body'];
}

Locale getDeviceLocale() {
  // device locale could be "en", "en_US" or "en_US.UTF-8"
  List<String> localeHelper = Platform.localeName.split(".")[0].split("_");
  if (localeHelper.length > 1) {
    return Locale(localeHelper[0], localeHelper[1]);
  } else {
    return Locale(localeHelper[0]);
  }
}

Future<Locale> initializeLocale() async {
  final language = await preferredLanguageTag();
  final languageCountry = language.split('_');
  if (languageCountry.length < 2) {
    return getDeviceLocale();
  }
  return Locale(languageCountry[0], languageCountry[1]);
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isAndroid) {
      // Keeps Flutter's system-ui plugin in edge-to-edge so a later overlay
      // update does not clear the window insets on Android 10–14.
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    runApp(const _Startup());
  }, (error, stackTrace) {
    if (isIgnorableNonFatalError(error)) {
      return;
    }
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
  });
}

/// The system launch screen already shows the plate. This keeps that plate
/// on screen, then fades it away once the app is ready.
class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup>
    with SingleTickerProviderStateMixin {
  static const _cream = Color(0xFFDED6B8);
  static const _plate = AssetImage('res/images/splash_plate.jpg');

  late final AnimationController _cover;
  late final CurvedAnimation _coverOpacity;
  Locale? _locale;
  var _coverOn = true;

  @override
  void initState() {
    super.initState();
    _cover = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 800),
    );
    _coverOpacity = CurvedAnimation(parent: _cover, curve: Curves.easeOut);
    _open();
  }

  Future<void> _open() async {
    try {
      await initializeFlutterFire();
      await GuideAnalytics.start();
      WakelockPlus.enable();
      await Prefs.init();
      await applyRememberedVersionBlock();
      unawaited(Auth.startGuest());
      final umpFailed = await gatherAdConsent();
      final tracking =
          await AppTrackingTransparency.requestTrackingAuthorization();
      await setMetaAdvertiserTracking(tracking == TrackingStatus.authorized);
      await applyAnalyticsConsent(
        umpFailed: umpFailed,
        trackingAuthorized:
            !Platform.isIOS || tracking == TrackingStatus.authorized,
      );
      await MobileAds.instance.initialize();
      final locale = await initializeLocale();
      if (!mounted) return;
      setState(() => _locale = locale);
      await _cover.reverse();
      if (!mounted) return;
      setState(() => _coverOn = false);
    } catch (error, stackTrace) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _coverOpacity.dispose();
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          if (_locale != null) App(_locale!),
          if (_coverOn)
            Positioned.fill(
              child: FadeTransition(
                opacity: _coverOpacity,
                child: const ColoredBox(
                  color: _cream,
                  child: Image(image: _plate, fit: BoxFit.contain),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class App extends StatefulWidget {
  final Locale locale;

  App(this.locale);

  static void setLocale(BuildContext context, String language) async {
    _AppState state = context.findAncestorStateOfType<_AppState>()!;
    state.changeLanguage(language);
  }

  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final FirebaseAnalytics _firebaseAnalytics = FirebaseAnalytics.instance;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  StreamSubscription<Uri>? _sharedLinks;
  String? _pendingSharedPlant;
  String? _openedSharedLink;
  DateTime? _openedSharedAt;
  int _sharedLinkFrames = 0;
  late Locale _locale;
  String? _currentTopic;

  void _subscribeToLanguageTopic(String languageCode) {
    final topic = 'notifications-$languageCode';
    FirebaseMessaging.instance.subscribeToTopic(topic).then((_) {
      _currentTopic = topic;
    }).catchError((error) {});
  }

  void _unsubscribeFromTopic(String topic) {
    FirebaseMessaging.instance
        .unsubscribeFromTopic(topic)
        .then((_) {})
        .catchError((error) {});
  }

  changeLanguage(String language) {
    if (language.isEmpty) {
      setState(() {
        translationCache = {};
        _locale = getDeviceLocale();
      });
    } else {
      var languageCountry = language.split('_');
      setState(() {
        translationCache = {};
        _locale = Locale(languageCountry[0], languageCountry[1]);
      });
    }

    if (_currentTopic != null) {
      _unsubscribeFromTopic(_currentTopic!);
    }

    _subscribeToLanguageTopic(_locale.languageCode);
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      final id = purchase.productID;
      if (id.isEmpty) continue;
      final owned = purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (purchase.status == PurchaseStatus.error &&
          !storePurchaseCanceled(purchase)) {
        unawaited(GuideAnalytics.purchaseFailed(
          productId: id,
          reason: 'store',
        ));
      }
      if (owned) unawaited(_confirmPurchase(purchase));
      // Finish here, not on the sales page. A purchase that arrives after
      // that page has closed still has to be acknowledged.
      if (purchase.pendingCompletePurchase) {
        unawaited(_completePurchase(purchase));
      }
    }
  }

  Future<void> _confirmPurchase(PurchaseDetails purchase) async {
    final outcome = await submitStorePurchase(purchase);
    final id = purchase.productID;
    final confirmed = outcome.result == StoreProofResult.accepted &&
        outcome.products[id] == true;
    if (confirmed) {
      Purchases.purchases[id] = purchase;
      Purchases.namesRevision.value++;
      unawaited(rememberStorePurchases([id]));
      if (purchase.status == PurchaseStatus.purchased) {
        unawaited(GuideAnalytics.purchase(id));
      }
      if (mounted) setState(() {});
      return;
    }
    // Deferred stays quiet, and so does a restore. Launch, Person, and
    // Field Guide send receipts the server may already have refused.
    // The toast is for a purchase just made.
    if (purchase.status != PurchaseStatus.purchased ||
        outcome.result == StoreProofResult.deferred ||
        !mounted) {
      return;
    }
    unawaited(GuideAnalytics.purchaseFailed(
      productId: id,
      reason: 'rejected',
    ));
    Fluttertoast.showToast(
      msg: S.of(context).product_purchase_failed,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 5,
    );
  }

  Future<void> _completePurchase(PurchaseDetails purchase) async {
    try {
      await _inAppPurchase.completePurchase(purchase);
    } catch (error) {
      debugPrint('purchase finish: $error');
    }
  }

  Future<dynamic> handleMessage(RemoteMessage message) {
    if (message.data.isNotEmpty) {
      final raw = message.data[notificationAttributeAction];
      final action = raw is String ? raw : '';
      if (action.isNotEmpty && _navigatorKey.currentContext != null) {
        switch (action) {
          case notificationAttributeActionList:
            String path = message.data[notificationAttributePath];
            final openNew = notificationPathOpensNewInBook(path);
            return notificationPopup(
              _navigatorKey.currentContext!,
              notificationTitle(message),
              notificationBody(message),
            ).then((open) {
              _logNotification(notificationAttributeActionList, open);
              final context = _navigatorKey.currentContext;
              if (open && context != null) {
                Navigator.push(
                  context,
                  openNew
                      ? guideNewInBookRoute()
                      : guideNotificationListRoute(
                          path,
                          title: notificationTitle(message),
                        ),
                );
              }
            });
          case notificationAttributeActionPlant:
            return notificationPopup(
              _navigatorKey.currentContext!,
              notificationTitle(message),
              notificationBody(message),
            ).then((open) {
              final name = message.data[notificationAttributeName]?.toString();
              _logNotification(
                notificationAttributeActionPlant,
                open,
                plant: name,
              );
              final context = _navigatorKey.currentContext;
              final route = guideNotificationPlantRoute(name);
              if (open && context != null && route != null) {
                Navigator.push(context, route);
              }
            });
          case notificationAttributeActionBrowse:
            String uri = message.data[notificationAttributeUri];
            return notificationPopup(
              _navigatorKey.currentContext!,
              notificationTitle(message),
              notificationBody(message),
            ).then((open) {
              _logNotification(notificationAttributeActionBrowse, open);
              if (open && uri.isNotEmpty) {
                launchURL(uri);
              }
            });
        }
      }
    }
    return Future.value(null);
  }

  void _persistFcmToken(String? token) {
    if (token == null || token.isEmpty) {
      return;
    }
    Prefs.setString(keyToken, token);
    if (Auth.appUser != null) {
      usersReference
          .child(Auth.appUser!.uid)
          .child(firebaseAttributeToken)
          .set(token);
    }
  }

  void _firebaseCloudMessagingListeners() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.instance.getToken().then((token) {
      _persistFcmToken(token);
    }).onError((error, stackTrace) => null);
    FirebaseMessaging.instance.onTokenRefresh.listen(_persistFcmToken);

    FirebaseMessaging.instance.getInitialMessage().then((value) async {
      if (value != null) {
        await _openFromNotification(value);
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      handleMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _openFromNotification(message);
    });
  }

  void _logNotification(String action, bool accepted, {String? plant}) {
    unawaited(GuideAnalytics.notificationOpen(
      action: action,
      accepted: accepted,
    ));
    if (!accepted || action != notificationAttributeActionPlant) return;
    final name = plant?.trim() ?? '';
    if (name.isEmpty) return;
    unawaited(GuideAnalytics.plant(
      name,
      source: GuidePlantSource.notification,
    ));
  }

  Future<void> _openFromNotification(RemoteMessage message) async {
    if (message.data.isEmpty || _navigatorKey.currentContext == null) {
      return;
    }
    final raw = message.data[notificationAttributeAction];
    final action = raw is String ? raw : '';
    if (action.isNotEmpty) {
      _logNotification(
        action,
        true,
        plant: message.data[notificationAttributeName]?.toString(),
      );
    }
    MaterialPageRoute<dynamic>? redirect = await findRedirectF(message.data);
    if (redirect != null && _navigatorKey.currentContext != null) {
      Navigator.push(_navigatorKey.currentContext!, redirect);
    }
  }

  Future<MaterialPageRoute<dynamic>>? findRedirectF(
      Map<String, dynamic> notificationData) {
    if (notificationData.isEmpty) {
      return null;
    } else {
      final raw = notificationData[notificationAttributeAction];
      final action = raw is String ? raw : '';
      if (action.isEmpty) {
        return null;
      } else {
        switch (action) {
          case notificationAttributeActionBrowse:
            String uri = notificationData[notificationAttributeUri];
            if (uri.isNotEmpty) {
              launchURL(uri);
              return null;
            }
            return null;
          case notificationAttributeActionList:
            String path = notificationData[notificationAttributePath];
            if (path.isNotEmpty && notificationPathOpensNewInBook(path)) {
              return Future<MaterialPageRoute<dynamic>>.value(
                  guideNewInBookRoute());
            }
            if (path.isNotEmpty) {
              return Future<MaterialPageRoute<dynamic>>.value(
                guideNotificationListRoute(
                  path,
                  title: notificationData['title']?.toString(),
                ),
              );
            }
            return null;
          case notificationAttributeActionPlant:
            final route = guideNotificationPlantRoute(
              notificationData[notificationAttributeName]?.toString(),
            );
            if (route == null) return null;
            return Future<MaterialPageRoute<dynamic>>.value(route);
          default:
            return null;
        }
      }
    }
  }

  Locale localeResolution(
      Locale savedLocale, Iterable<Locale> supportedLocales) {
    final resultLocale = resolveAppLocale(savedLocale, supportedLocales);
    Prefs.setStringList(keyLanguageAndCountry, [
      resultLocale.languageCode,
      resultLocale.countryCode ?? '',
    ]);
    return resultLocale;
  }

  Future<void> initStoreInfo() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      _iapError();
    } else {
      unawaited(_inAppPurchase.restorePurchases().catchError((Object error) {
        debugPrint('restore: $error');
      }));
    }
    if (mounted) setState(() {});
    Purchases.hasOldVersion = Prefs.getBool(keyOldVersion, false);
    Auth.setUser();
    Offline.initialize();
  }

  @override
  void initState() {
    super.initState();

    _firebaseCloudMessagingListeners();
    final Stream<List<PurchaseDetails>> purchaseUpdated =
        _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      unawaited(GuideAnalytics.purchaseFailed(reason: 'stream'));
      if (mounted) {
        Fluttertoast.showToast(
            msg: S.of(context).product_purchase_failed,
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 5);
      }
    });
    initStoreInfo();

    _locale = widget.locale;
    _subscribeToLanguageTopic(_locale.languageCode);
    _listenForSharedLinks();
  }

  /// A shared encyclopedia URL opens that species. Cold start is the initial
  /// link. A link opened while the guide is already running arrives on the
  /// stream. The same URL twice in a moment is one open.
  void _listenForSharedLinks() {
    final links = AppLinks();
    _sharedLinks = links.uriLinkStream.listen(
      _onSharedLink,
      onError: (Object error) {
        debugPrint('guide link: $error');
      },
    );
    unawaited(_openInitialSharedLink(links));
  }

  Future<void> _openInitialSharedLink(AppLinks links) async {
    try {
      final uri = await links.getInitialLink();
      if (uri != null) _onSharedLink(uri);
    } catch (error) {
      debugPrint('guide link: $error');
    }
  }

  void _onSharedLink(Uri uri) {
    final name = plantNameFromSharedUrl(uri);
    if (name == null) return;
    final key = uri.toString();
    final now = DateTime.now();
    if (_openedSharedLink == key &&
        _openedSharedAt != null &&
        now.difference(_openedSharedAt!) < const Duration(seconds: 2)) {
      return;
    }
    _openedSharedLink = key;
    _openedSharedAt = now;
    final context = _navigatorKey.currentContext;
    if (!mounted || context == null) {
      _pendingSharedPlant = name;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openPendingSharedPlant();
      });
      return;
    }
    _openSharedPlant(context, name);
  }

  void _openPendingSharedPlant() {
    final name = _pendingSharedPlant;
    final context = _navigatorKey.currentContext;
    if (name == null) return;
    if (context == null) {
      if (_sharedLinkFrames >= 8) return;
      _sharedLinkFrames++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openPendingSharedPlant();
      });
      return;
    }
    _pendingSharedPlant = null;
    _sharedLinkFrames = 0;
    _openSharedPlant(context, name);
  }

  void _openSharedPlant(BuildContext context, String name) {
    unawaited(openGuidePlant(context, name, source: GuidePlantSource.link));
  }

  @override
  void dispose() {
    Prefs.dispose();
    _subscription.cancel();
    _sharedLinks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      locale: localeResolution(_locale, S.delegate.supportedLocales),
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? child) {
        return GuideFoldHost(
          child: FocusTraversalGroup(
            policy: safeReadingOrderTraversalPolicy,
            child: ListenableBuilder(
              listenable: VersionGateController.instance,
              builder: (context, navigator) {
                final blocked = VersionGateController.instance.prompt ==
                    VersionPrompt.block;
                return Stack(
                  children: [
                    IgnorePointer(
                      ignoring: blocked,
                      child: ExcludeFocus(
                        excluding: blocked,
                        child: ExcludeSemantics(
                          excluding: blocked,
                          child: navigator ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    if (blocked)
                      Positioned.fill(
                        child: VersionRequiredPage(
                          onUpdate: () => openAppUpdate(requiredUpdate: true),
                        ),
                      ),
                  ],
                );
              },
              child: child,
            ),
          ),
        );
      },
      localizationsDelegates: [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        CountryLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      initialRoute: '/guide',
      navigatorObservers: [
        FirebaseAnalyticsObserver(
          analytics: _firebaseAnalytics,
          nameExtractor: (RouteSettings settings) => guideAnalyticsScreenName(
            settings.name,
            settings.arguments,
            customName: guideCustomRouteName,
          ),
        ),
      ],
      routes: {
        '/guide': (context) => const GuideShell(),
      },
    );
  }
}
