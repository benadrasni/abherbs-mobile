import 'package:abherbs_flutter/data/utils.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

enum GuideFieldGuidePlan { yearly, monthly }

/// Oxeye daisy plate on the Field Guide page.
const guideFieldGuidePlatePath =
    'photos/Asterales/Asteraceae/Leucanthemum_vulgare/Leucanthemum_vulgare@1600.webp';

String guideFieldGuideProductId(GuideFieldGuidePlan plan) {
  return plan == GuideFieldGuidePlan.yearly
      ? fieldGuideYearly
      : fieldGuideMonthly;
}

class GuideFieldGuideOffer {
  final GuideFieldGuidePlan plan;
  final String productId;
  final String? price;
  final bool owned;

  /// A free phase followed by a paid phase. The row price is the paid phase.
  final bool trial;

  /// ISO billing period of the paid phase, such as `P1Y` or `P1M`.
  final String? period;

  const GuideFieldGuideOffer({
    required this.plan,
    required this.productId,
    required this.price,
    required this.owned,
    this.trial = true,
    this.period,
  });
}

class GuideFieldGuideCatalog {
  final GuideFieldGuideOffer yearly;
  final GuideFieldGuideOffer monthly;
  final bool storeAvailable;

  /// An active photo-storage plan. It already is Field Guide.
  final bool photoStorage;
  final String? error;

  const GuideFieldGuideCatalog({
    required this.yearly,
    required this.monthly,
    required this.storeAvailable,
    required this.photoStorage,
    this.error,
  });

  bool get coveredByOlderPlan =>
      photoStorage && !yearly.owned && !monthly.owned;

  GuideFieldGuidePlan get initialPlan {
    if (monthly.owned && !yearly.owned) return GuideFieldGuidePlan.monthly;
    return GuideFieldGuidePlan.yearly;
  }

  GuideFieldGuideOffer offer(GuideFieldGuidePlan plan) {
    return plan == GuideFieldGuidePlan.yearly ? yearly : monthly;
  }

  GuideFieldGuideCatalog withOwnership(Set<String> owned) {
    return guideFieldGuideCatalog(
      storeAvailable: storeAvailable,
      yearlyPrice: yearly.price,
      monthlyPrice: monthly.price,
      owned: owned,
      error: error,
      yearlyTrial: yearly.trial,
      monthlyTrial: monthly.trial,
      yearlyPeriod: yearly.period,
      monthlyPeriod: monthly.period,
    );
  }
}

class GuideFieldGuideLoaded {
  final GuideFieldGuideCatalog catalog;
  final Map<String, ProductDetails> products;

  const GuideFieldGuideLoaded({
    required this.catalog,
    this.products = const {},
  });
}

GuideFieldGuideCatalog guideFieldGuideCatalog({
  required bool storeAvailable,
  required String? yearlyPrice,
  required String? monthlyPrice,
  required Set<String> owned,
  String? error,
  bool yearlyTrial = true,
  bool monthlyTrial = true,
  String? yearlyPeriod,
  String? monthlyPeriod,
}) {
  return GuideFieldGuideCatalog(
    yearly: GuideFieldGuideOffer(
      plan: GuideFieldGuidePlan.yearly,
      productId: fieldGuideYearly,
      price: _price(yearlyPrice),
      owned: owned.contains(fieldGuideYearly),
      trial: yearlyTrial,
      period: yearlyPeriod,
    ),
    monthly: GuideFieldGuideOffer(
      plan: GuideFieldGuidePlan.monthly,
      productId: fieldGuideMonthly,
      price: _price(monthlyPrice),
      owned: owned.contains(fieldGuideMonthly),
      trial: monthlyTrial,
      period: monthlyPeriod,
    ),
    storeAvailable: storeAvailable,
    photoStorage: owned.contains(subscriptionMonthly) ||
        owned.contains(subscriptionYearly),
    error: error,
  );
}

String? _price(String? price) {
  final trimmed = price?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class GuideFieldGuideChoice {
  final int buyIndex;
  final String displayPrice;

  const GuideFieldGuideChoice({
    required this.buyIndex,
    required this.displayPrice,
  });
}

/// Store rows for one product id.
///
/// A free introductory phase is the one to buy when a paid phase is also
/// present. The price on the row is the paid phase.
GuideFieldGuideChoice? guideFieldGuideOfferChoice(
  List<({String price, double rawPrice})> offers,
) {
  if (offers.isEmpty) return null;
  var paid = -1;
  var free = -1;
  for (var i = 0; i < offers.length; i++) {
    final raw = offers[i].rawPrice;
    if (raw > 0) {
      if (paid < 0 || raw > offers[paid].rawPrice) paid = i;
    } else if (free < 0 && offers[i].price.trim().isNotEmpty) {
      free = i;
    }
  }
  if (paid < 0 && free < 0) return null;
  if (paid < 0) {
    return GuideFieldGuideChoice(
      buyIndex: free,
      displayPrice: offers[free].price,
    );
  }
  return GuideFieldGuideChoice(
    buyIndex: free >= 0 ? free : paid,
    displayPrice: offers[paid].price,
  );
}

/// Whether this phone may replace monthly with yearly, or the screen is only
/// a summary. A plan that arrived from the account cannot be changed here.
class GuideFieldGuideAccess {
  final bool upgrade;
  final bool locked;

  const GuideFieldGuideAccess({required this.upgrade, required this.locked});
}

GuideFieldGuideAccess guideFieldGuideAccess({
  required GuideFieldGuideCatalog catalog,
  required bool monthlyOnThisStore,
  required bool fromAccountOnly,

  /// The catalog drawn before the store answers. A catalog the store has
  /// returned, including a dead store, is not this.
  bool awaitingStore = false,
}) {
  final monthlyHere = monthlyOnThisStore &&
      !fromAccountOnly &&
      catalog.monthly.owned &&
      !catalog.yearly.owned &&
      !catalog.coveredByOlderPlan;
  final upgrade = monthlyHere &&
      (catalog.yearly.price != null ||
          (awaitingStore && !catalog.storeAvailable));
  final hasPlan = catalog.monthly.owned ||
      catalog.yearly.owned ||
      catalog.coveredByOlderPlan ||
      fromAccountOnly;
  return GuideFieldGuideAccess(upgrade: upgrade, locked: hasPlan && !upgrade);
}

/// The other Field Guide product, when that product is already owned.
/// Photo-storage plans are a separate subscription and are not replaced.
String? guideFieldGuideReplaces(
  GuideFieldGuidePlan buying,
  Set<String> owned,
) {
  final other = buying == GuideFieldGuidePlan.yearly
      ? fieldGuideMonthly
      : fieldGuideYearly;
  return owned.contains(other) ? other : null;
}

GuideFieldGuideLoaded guideFieldGuideFromStore({
  required bool storeAvailable,
  required List<ProductDetails> products,
  required Set<String> owned,
  String? error,
}) {
  final yearly = _picked(products, fieldGuideYearly, yearly: true);
  final monthly = _picked(products, fieldGuideMonthly, yearly: false);
  return GuideFieldGuideLoaded(
    catalog: guideFieldGuideCatalog(
      storeAvailable: storeAvailable,
      yearlyPrice: yearly?.displayPrice,
      monthlyPrice: monthly?.displayPrice,
      owned: owned,
      error: error,
      yearlyTrial: yearly?.trial ?? false,
      monthlyTrial: monthly?.trial ?? false,
      yearlyPeriod: yearly?.period,
      monthlyPeriod: monthly?.period,
    ),
    products: {
      if (yearly != null) fieldGuideYearly: yearly.product,
      if (monthly != null) fieldGuideMonthly: monthly.product,
    },
  );
}

class GuideFieldGuideCandidate {
  final String recurringPrice;
  final double recurringRaw;
  final String? period;
  final bool trial;

  const GuideFieldGuideCandidate({
    required this.recurringPrice,
    required this.recurringRaw,
    required this.trial,
    this.period,
  });
}

class GuideFieldGuidePick {
  final int index;
  final String price;
  final bool trial;
  final String? period;

  const GuideFieldGuidePick({
    required this.index,
    required this.price,
    required this.trial,
    this.period,
  });
}

/// Buys a free trial on the yearly or monthly period when the store offers one.
/// The price is the paid phase. A same-priced plan on the other period is left.
GuideFieldGuidePick? guideFieldGuidePick(
  List<GuideFieldGuideCandidate> items, {
  required bool yearly,
}) {
  if (items.isEmpty) return null;
  final preferred = yearly ? 'P1Y' : 'P1M';
  final matched = [
    for (var i = 0; i < items.length; i++)
      if (items[i].period == preferred) i,
  ];
  final pool =
      matched.isEmpty ? [for (var i = 0; i < items.length; i++) i] : matched;
  int? trialIndex;
  int? paidIndex;
  var paidRaw = -1.0;
  for (final i in pool) {
    final item = items[i];
    if (item.trial && trialIndex == null) trialIndex = i;
    if (item.recurringRaw > paidRaw) {
      paidIndex = i;
      paidRaw = item.recurringRaw;
    }
  }
  final buy = trialIndex ?? paidIndex;
  if (buy == null) return null;
  final chosen = items[buy];
  final price = chosen.recurringRaw > 0 || paidIndex == null
      ? chosen.recurringPrice
      : items[paidIndex].recurringPrice;
  return GuideFieldGuidePick(
    index: buy,
    price: price,
    trial: chosen.trial,
    period:
        chosen.period ?? (paidIndex == null ? null : items[paidIndex].period),
  );
}

({
  ProductDetails product,
  String displayPrice,
  bool trial,
  String? period,
})? _picked(List<ProductDetails> products, String id, {required bool yearly}) {
  final matches = products.where((product) => product.id == id).toList();
  final pick = guideFieldGuidePick(
    [for (final product in matches) _candidate(product)],
    yearly: yearly,
  );
  if (pick == null) return null;
  return (
    product: matches[pick.index],
    displayPrice: pick.price,
    trial: pick.trial,
    period: pick.period,
  );
}

/// Play's product price is the first phase. A free trial makes that price
/// zero, so the row uses the later paid phase instead.
GuideFieldGuideCandidate _candidate(ProductDetails product) {
  if (product is GooglePlayProductDetails) {
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index != null && offers != null && index < offers.length) {
      final phases = offers[index].pricingPhases;
      var trial = false;
      PricingPhaseWrapper? paid;
      for (final phase in phases) {
        if (phase.priceAmountMicros <= 0) {
          trial = true;
        } else {
          paid = phase;
        }
      }
      if (paid != null) {
        return GuideFieldGuideCandidate(
          recurringPrice: paid.formattedPrice,
          recurringRaw: paid.priceAmountMicros / 1000000,
          period: paid.billingPeriod,
          trial: trial,
        );
      }
    }
  }
  final free = product.rawPrice == 0 && product.price.trim().isNotEmpty;
  return GuideFieldGuideCandidate(
    recurringPrice: product.price,
    recurringRaw: product.rawPrice,
    trial: free,
  );
}
