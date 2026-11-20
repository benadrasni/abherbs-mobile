import 'dart:async';
import 'dart:io';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/field_guide/guide_field_guide.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/person/sign_in_page.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/purchase/store_account.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

const guideFieldGuideStartKey = Key('guideFieldGuideStart');
const guideFieldGuideManageKey = Key('guideFieldGuideManage');
const guideFieldGuideRestoreKey = Key('guideFieldGuideRestore');
const guideFieldGuideYearlyKey = Key('guideFieldGuideYearly');
const guideFieldGuideMonthlyKey = Key('guideFieldGuideMonthly');

/// How long the plans wait for Play or the App Store before they open
/// without a price. A later answer still fills the rows in.
const guideFieldGuideStoreTimeout = Duration(seconds: 12);

/// Field Guide: yearly and monthly, with the store price on each row.
/// A monthly plan bought on this phone can change to yearly. Any other
/// active plan leaves the rows, the button, and Restore in place and off.
class GuideFieldGuidePage extends StatefulWidget {
  final Future<GuideFieldGuideLoaded> Function()? load;
  final Future<bool> Function(GuideFieldGuidePlan plan)? buy;
  final Future<void> Function()? restore;
  final bool Function()? signedIn;
  final Future<void> Function(BuildContext context)? signIn;
  final WidgetBuilder? plate;
  final GuideAppearance? appearance;
  final Duration storeTimeout;

  const GuideFieldGuidePage({
    super.key,
    this.load,
    this.buy,
    this.restore,
    this.signedIn,
    this.signIn,
    this.plate,
    this.appearance,
    this.storeTimeout = guideFieldGuideStoreTimeout,
  });

  @override
  State<GuideFieldGuidePage> createState() => _GuideFieldGuidePageState();
}

class _GuideFieldGuidePageState extends State<GuideFieldGuidePage> {
  GuideFieldGuideLoaded? _loaded;
  GuideFieldGuidePlan _plan = GuideFieldGuidePlan.yearly;
  bool _planChosen = false;
  bool _awaitingPrices = true;
  bool _failed = false;
  bool _busy = false;
  bool _viewed = false;
  String? _error;
  int _ticket = 0;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  @override
  void initState() {
    super.initState();
    Purchases.namesRevision.addListener(_onPlan);
    if (widget.load == null) {
      _purchaseSub = InAppPurchase.instance.purchaseStream.listen(
        _onStore,
        onError: (Object error) => debugPrint('guide field guide: $error'),
      );
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    Purchases.namesRevision.removeListener(_onPlan);
    _purchaseSub?.cancel();
    super.dispose();
  }

  /// A plan bought on the other phone arrives after this page has drawn.
  void _onPlan() {
    if (!mounted) return;
    _applyOwned();
    setState(() {});
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    final future = (widget.load ?? loadGuideFieldGuide)();
    try {
      final loaded = await future.timeout(widget.storeTimeout);
      _show(ticket, loaded);
    } on TimeoutException {
      debugPrint('guide field guide: store timed out');
      if (!mounted || ticket != _ticket) return;
      setState(() => _awaitingPrices = false);
      unawaited(_showWhenReady(ticket, future));
    } catch (error) {
      debugPrint('guide field guide: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _failed = true;
        _awaitingPrices = false;
      });
    }
  }

  /// Play can answer after the plans have already opened.
  Future<void> _showWhenReady(
    int ticket,
    Future<GuideFieldGuideLoaded> future,
  ) async {
    try {
      _show(ticket, await future);
    } catch (error) {
      debugPrint('guide field guide: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _failed = true;
        _awaitingPrices = false;
      });
    }
  }

  void _show(int ticket, GuideFieldGuideLoaded loaded) {
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _loaded = loaded;
      _failed = false;
      _awaitingPrices = false;
      if (!_planChosen) _plan = _openingPlan(loaded.catalog);
    });
    if (_viewed) return;
    _viewed = true;
    unawaited(GuideAnalytics.viewItem([
      loaded.catalog.yearly.productId,
      loaded.catalog.monthly.productId,
    ]));
  }

  void _onStore(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      final id = purchase.productID;
      final fieldGuide = id == fieldGuideMonthly || id == fieldGuideYearly;
      if (!fieldGuide || purchase.status != PurchaseStatus.error) continue;
      if (storePurchaseCanceled(purchase)) continue;
      if (!mounted) return;
      setState(() {
        _error = S.of(context).product_subscribe_failed;
        _busy = false;
      });
    }
  }

  void _applyOwned() {
    final loaded = _loaded;
    if (loaded == null) return;
    _loaded = GuideFieldGuideLoaded(
      catalog: loaded.catalog.withOwnership(guideOwnedProductIds()),
      products: loaded.products,
    );
  }

  GuideFieldGuideAccess _access(GuideFieldGuideCatalog catalog) {
    return guideFieldGuideAccess(
      catalog: catalog,
      monthlyOnThisStore: Purchases.purchases.containsKey(fieldGuideMonthly),
      fromAccountOnly: Purchases.fieldGuideFromAccountOnly,
      awaitingStore: _loaded == null,
    );
  }

  GuideFieldGuidePlan _openingPlan(GuideFieldGuideCatalog catalog) {
    if (_access(catalog).upgrade) return GuideFieldGuidePlan.yearly;
    return catalog.initialPlan;
  }

  bool _isSignedIn() {
    final check = widget.signedIn;
    if (check != null) return check();
    if (widget.buy != null || widget.restore != null) return true;
    return Auth.appUser != null;
  }

  Future<bool> _ensureSignedIn() async {
    if (_isSignedIn()) return true;
    await (widget.signIn ?? openGuideSignIn)(context);
    if (!mounted) return false;
    _applyOwned();
    setState(() {});
    return _isSignedIn();
  }

  Future<void> _start() async {
    final loaded = _loaded;
    if (loaded == null || _busy) return;
    final access = _access(loaded.catalog);
    final offer = loaded.catalog.offer(_plan);
    if (access.locked || offer.owned || offer.price == null) return;
    if (!access.upgrade &&
        (loaded.catalog.coveredByOlderPlan ||
            Purchases.fieldGuideFromAccountOnly)) {
      return;
    }
    if (!await _ensureSignedIn()) return;
    final current = _loaded;
    if (current == null || !mounted) return;
    final nextAccess = _access(current.catalog);
    final nextOffer = current.catalog.offer(_plan);
    if (nextAccess.locked || nextOffer.owned || nextOffer.price == null) return;
    if (!nextAccess.upgrade &&
        (current.catalog.coveredByOlderPlan ||
            Purchases.fieldGuideFromAccountOnly)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final buy = widget.buy ?? _buySelected;
      final started = await buy(_plan);
      if (!started && mounted) {
        setState(() => _error = S.of(context).product_subscribe_failed);
      }
    } catch (error) {
      debugPrint('guide field guide: $error');
      if (mounted) {
        setState(() => _error = S.of(context).product_subscribe_failed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _buySelected(GuideFieldGuidePlan plan) {
    final product = _loaded?.products[guideFieldGuideProductId(plan)];
    if (product == null) return Future<bool>.value(false);
    final replaceId = guideFieldGuideReplaces(
      plan,
      Purchases.purchases.keys.toSet(),
    );
    return buyGuideFieldGuide(
      product: product,
      replaces: replaceId == null ? null : Purchases.purchases[replaceId],
    );
  }

  Future<void> _restore() async {
    if (!await _ensureSignedIn()) return;
    final custom = widget.restore;
    if (custom != null) {
      await custom();
      return;
    }
    final store = InAppPurchase.instance;
    final available = await store.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() => _error = S.of(context).product_purchase_failed);
      return;
    }
    setState(() => _error = null);
    await store.restorePurchases();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).guide_person_restoring)),
    );
  }

  void _choose(GuideFieldGuidePlan plan) {
    setState(() {
      _plan = plan;
      _planChosen = true;
      _error = null;
    });
  }

  String _planNote(
    S strings,
    GuideFieldGuideOffer offer, {
    required bool locked,
  }) {
    if (locked) return offer.owned ? strings.product_subscribed : '';
    final price = offer.price;
    if (price == null) return '';
    final yearly = _billedYearly(offer);
    if (!offer.trial) {
      return yearly
          ? strings.guide_field_guide_every_year(price)
          : strings.guide_field_guide_every_month(price);
    }
    return yearly
        ? strings.guide_field_guide_then_yearly(price)
        : strings.guide_field_guide_then_monthly(price);
  }

  String _terms(S strings, GuideFieldGuideOffer offer, {required bool ios}) {
    final price = offer.price;
    if (price == null) return '';
    final where = ios
        ? strings.guide_field_guide_cancel_ios
        : strings.guide_field_guide_cancel_android;
    final yearly = _billedYearly(offer);
    if (!offer.trial) {
      final period = yearly
          ? strings.guide_field_guide_every_year(price)
          : strings.guide_field_guide_every_month(price);
      final renewal = ios
          ? strings.guide_field_guide_disclaimer_ios
          : strings.guide_field_guide_disclaimer_android;
      return '$period $renewal';
    }
    return yearly
        ? strings.guide_field_guide_trial_yearly(price, where)
        : strings.guide_field_guide_trial_monthly(price, where);
  }

  bool _billedYearly(GuideFieldGuideOffer offer) {
    if (offer.period == 'P1Y') return true;
    if (offer.period == 'P1M') return false;
    return offer.plan == GuideFieldGuidePlan.yearly;
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      appearance: widget.appearance,
      navigationColor: (colors) => colors.paper,
      child: Builder(
        builder: (context) {
          final colors = GuideColors.of(context);
          return Scaffold(
            backgroundColor: colors.paper,
            body: guideWithRail(
              context,
              personOn: true,
              child: SafeArea(
                bottom: false,
                child: GuideReadable(
                  maxWidth: 880,
                  child: _body(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  GuideFieldGuideCatalog _catalog() {
    return _loaded?.catalog ??
        guideFieldGuideCatalog(
          storeAvailable: false,
          yearlyPrice: null,
          monthlyPrice: null,
          owned: guideOwnedProductIds(),
        );
  }

  Widget _body(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    if (_failed && _loaded == null) {
      return Column(
        children: [
          const Spacer(),
          Text(
            strings.guide_person_failed,
            style: TextStyle(color: colors.ink2),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _failed = false;
                _awaitingPrices = true;
              });
              unawaited(_load());
            },
            child: Text(strings.guide_results_retry),
          ),
          const Spacer(),
        ],
      );
    }
    return _content(
      context,
      _catalog(),
      pricesPending: _awaitingPrices && _loaded == null,
    );
  }

  Widget _content(
    BuildContext context,
    GuideFieldGuideCatalog catalog, {
    required bool pricesPending,
  }) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    final selected = catalog.offer(_plan);
    final owned = selected.owned;
    final access = _access(catalog);
    final canBuy = !access.locked &&
        !owned &&
        selected.price != null &&
        !_busy &&
        (access.upgrade ||
            (!catalog.coveredByOlderPlan &&
                !Purchases.fieldGuideFromAccountOnly));
    final ios = Platform.isIOS;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 250,
                child: _Hero(plate: widget.plate),
              ),
              PositionedDirectional(
                top: 10,
                start: 12,
                child: _BackButton(label: strings.guide_back),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(
            strings.guide_person_field_guide,
            style: TextStyle(
              fontFamily: GuideType.serif,
              fontWeight: FontWeight.w500,
              fontSize: 34,
              letterSpacing: -0.68,
              height: 1.05,
              color: colors.ink,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            strings.guide_field_guide_sub,
            style: TextStyle(color: colors.ink2, fontSize: 16, height: 1.45),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Column(
                  title: strings.guide_field_guide_free,
                  titleColor: colors.ink3,
                  lines: [
                    strings.guide_field_guide_free_search,
                    strings.guide_field_guide_free_key,
                    strings.guide_field_guide_free_species,
                    strings.guide_field_guide_free_seen,
                    strings.guide_field_guide_free_names,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Column(
                  title: strings.guide_field_guide_adds,
                  titleColor: colors.moss,
                  border: colors.moss,
                  lines: [
                    strings.guide_field_guide_add_names,
                    strings.guide_field_guide_add_ads,
                    strings.guide_field_guide_add_seen,
                    strings.guide_field_guide_add_offline,
                  ],
                ),
              ),
            ],
          ),
        ),
        if (access.locked) _Included(photoStorage: catalog.photoStorage),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            children: [
              _Plan(
                planKey: guideFieldGuideYearlyKey,
                title: strings.guide_field_guide_yearly,
                note: _planNote(
                  strings,
                  catalog.yearly,
                  locked: access.locked,
                ),
                price: catalog.yearly.price ??
                    strings.guide_field_guide_store_price,
                pricePending: pricesPending && catalog.yearly.price == null,
                selected: _plan == GuideFieldGuidePlan.yearly,
                onPressed: access.locked
                    ? null
                    : () => _choose(GuideFieldGuidePlan.yearly),
              ),
              const SizedBox(height: 8),
              _Plan(
                planKey: guideFieldGuideMonthlyKey,
                title: strings.guide_field_guide_monthly,
                note: _planNote(
                  strings,
                  catalog.monthly,
                  locked: access.locked,
                ),
                price: catalog.monthly.price ??
                    strings.guide_field_guide_store_price,
                pricePending: pricesPending && catalog.monthly.price == null,
                selected: _plan == GuideFieldGuidePlan.monthly,
                onPressed: access.locked
                    ? null
                    : () => _choose(GuideFieldGuidePlan.monthly),
              ),
            ],
          ),
        ),
        if (!access.locked && selected.price == null && !pricesPending)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              strings.guide_field_guide_unavailable,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.ink3, fontSize: 13, height: 1.4),
            ),
          ),
        if (!access.locked && selected.price != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(
              _terms(strings, selected, ios: ios),
              style: TextStyle(color: colors.ink, fontSize: 15, height: 1.45),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _StartButton(
            label: access.locked || owned
                ? strings.product_subscribed
                : (access.upgrade ||
                        catalog.yearly.owned ||
                        catalog.monthly.owned)
                    ? strings.product_change
                    : strings.guide_field_guide_start,
            spinning: _busy,
            onPressed: canBuy ? () => unawaited(_start()) : null,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.madder, fontSize: 13, height: 1.4),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: _TextButton(
            buttonKey: guideFieldGuideManageKey,
            label: strings.guide_field_guide_manage(
              ios
                  ? strings.guide_field_guide_cancel_ios
                  : strings.guide_field_guide_cancel_android,
            ),
            onPressed: openGuideSubscriptionManage,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: _TextButton(
            buttonKey: guideFieldGuideRestoreKey,
            label: strings.guide_person_restore,
            onPressed: access.locked ? null : () => unawaited(_restore()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            strings.guide_field_guide_note,
            style: TextStyle(color: colors.ink3, fontSize: 12, height: 1.45),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              _Link(
                label: strings.terms_of_use,
                onPressed: () => launchURL(termsOfUseUrl),
              ),
              _Link(
                label: strings.privacy_policy,
                onPressed: () => launchURL(privacyPolicyUrl),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Product ids the server has checked onto the signed-in account.
Set<String> guideOwnedProductIds() {
  return Set<String>.of(Purchases.accountProducts);
}

Future<GuideFieldGuideLoaded> loadGuideFieldGuide() async {
  final store = InAppPurchase.instance;
  final owned = guideOwnedProductIds();
  final available = await store.isAvailable();
  if (!available) {
    return guideFieldGuideFromStore(
      storeAvailable: false,
      products: const [],
      owned: owned,
    );
  }
  final response = await store.queryProductDetails({
    fieldGuideMonthly,
    fieldGuideYearly,
  });
  return guideFieldGuideFromStore(
    storeAvailable: true,
    products: response.productDetails,
    owned: owned,
    error: response.error?.message,
  );
}

const _playSubscriptions =
    'https://play.google.com/store/account/subscriptions?package=sk.ab.herbs';
const _appleSubscriptions = 'https://apps.apple.com/account/subscriptions';

/// Opens the store page where a trial or subscription is canceled.
void openGuideSubscriptionManage() {
  launchURL(Platform.isIOS ? _appleSubscriptions : _playSubscriptions);
}

Future<bool> buyGuideFieldGuide({
  required ProductDetails product,
  PurchaseDetails? replaces,
}) {
  final account = storeApplicationUserName();
  final PurchaseParam param;
  if (Platform.isAndroid && replaces is GooglePlayPurchaseDetails) {
    param = GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: account,
      changeSubscriptionParam: ChangeSubscriptionParam(
        oldPurchaseDetails: replaces,
        replacementMode: ReplacementMode.withTimeProration,
      ),
    );
  } else {
    param = PurchaseParam(
      productDetails: product,
      applicationUserName: account,
    );
  }
  return InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
}

Future<void> openGuideFieldGuide(BuildContext context) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideFieldGuideRouteName),
      builder: (context) => const GuideFieldGuidePage(),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({this.plate});

  final WidgetBuilder? plate;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.plateWell),
          plate?.call(context) ?? const _Plate(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.paper.withValues(alpha: 0),
                  colors.paper.withValues(alpha: 0),
                  colors.paper,
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate();

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: GuideColors.of(context).plateWell);
    return FutureBuilder<File?>(
      future: Offline.getLocalFile(guideFieldGuidePlatePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return placeholder;
        }
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4),
            errorBuilder: (context, error, stackTrace) => placeholder,
          );
        }
        return CachedNetworkImage(
          imageUrl: storageEndpoint + guideFieldGuidePlatePath,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.4),
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
        );
      },
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.cream,
          shape: CircleBorder(side: BorderSide(color: colors.rule)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.maybePop(context),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 38,
              height: 38,
              child: IconTheme(
                data: IconThemeData(color: colors.ink, size: 20),
                child: const BackButtonIcon(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.titleColor,
    required this.lines,
    this.border,
  });

  final String title;
  final Color titleColor;
  final List<String> lines;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: border ?? colors.rule, width: border == null ? 1 : 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: titleColor,
                fontSize: 12,
                letterSpacing: 0.96,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  line,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.planKey,
    required this.title,
    required this.note,
    required this.price,
    this.pricePending = false,
    required this.selected,
    required this.onPressed,
  });

  final Key planKey;
  final String title;
  final String note;
  final String price;
  final bool pricePending;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final enabled = onPressed != null;
    return Material(
      key: planKey,
      color: colors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? colors.moss : colors.rule,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.moss : colors.ink3,
                    width: selected ? 6 : 1.5,
                  ),
                ),
                child: const SizedBox(width: 20, height: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? colors.ink : colors.ink3,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    if (note.isNotEmpty)
                      Text(
                        note,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              pricePending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.moss,
                      ),
                    )
                  : Text(
                      price,
                      style: TextStyle(
                        color: enabled ? colors.ink : colors.ink3,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included({required this.photoStorage});

  final bool photoStorage;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.moss, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.guide_field_guide_included,
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
              if (photoStorage) ...[
                const SizedBox(height: 4),
                Text(
                  strings.guide_field_guide_included_photos,
                  style: TextStyle(
                    color: colors.ink3,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.onPressed,
    required this.spinning,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final enabled = onPressed != null;
    return Material(
      key: guideFieldGuideStartKey,
      color: enabled || spinning ? colors.mossFill : colors.paper2,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: spinning ? null : onPressed,
        child: SizedBox(
          height: 44,
          child: Center(
            child: spinning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: enabled ? Colors.white : colors.ink3,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Material(
      key: buttonKey,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: onPressed == null ? colors.ink3 : colors.moss,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: GuideColors.of(context).moss,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
