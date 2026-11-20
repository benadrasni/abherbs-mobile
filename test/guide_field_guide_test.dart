import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/field_guide/field_guide_page.dart';
import 'package:abherbs_flutter/field_guide/guide_field_guide.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

void main() {
  tearDown(() {
    Purchases.purchases = {};
    Purchases.clearAccountProducts();
    Purchases.hasOldVersion = false;
    Purchases.namesReady = false;
  });

  test('dismissing the store sheet is not a failed purchase', () {
    final canceled = PurchaseDetails(
      productID: fieldGuideYearly,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'test',
      ),
      transactionDate: '0',
      status: PurchaseStatus.canceled,
    );
    expect(storePurchaseCanceled(canceled), isTrue);
    expect(storePurchaseCanceled(_purchase(fieldGuideYearly)), isFalse);
  });

  test('yearly is the offer to show, and a free phase is the one to buy', () {
    final choice = guideFieldGuideOfferChoice(const [
      (price: r'$0.00', rawPrice: 0),
      (price: r'$19.99', rawPrice: 19.99),
    ]);
    expect(choice?.buyIndex, 0);
    expect(choice?.displayPrice, r'$19.99');

    final paidOnly = guideFieldGuideOfferChoice(const [
      (price: r'$2.99', rawPrice: 2.99),
    ]);
    expect(paidOnly?.buyIndex, 0);
    expect(paidOnly?.displayPrice, r'$2.99');
    expect(guideFieldGuideOfferChoice(const []), isNull);
  });

  test('a photo-storage plan counts, and the other period is the replacement',
      () {
    final catalog = guideFieldGuideCatalog(
      storeAvailable: true,
      yearlyPrice: r'$19.99',
      monthlyPrice: r'$2.99',
      owned: {subscriptionYearly},
    );
    expect(catalog.photoStorage, isTrue);
    expect(catalog.coveredByOlderPlan, isTrue);
    expect(catalog.initialPlan, GuideFieldGuidePlan.yearly);

    final monthly = guideFieldGuideCatalog(
      storeAvailable: true,
      yearlyPrice: null,
      monthlyPrice: r'$2.99',
      owned: {fieldGuideMonthly},
    );
    expect(monthly.monthly.owned, isTrue);
    expect(monthly.initialPlan, GuideFieldGuidePlan.monthly);
    expect(
      guideFieldGuideReplaces(
        GuideFieldGuidePlan.yearly,
        {fieldGuideMonthly, subscriptionYearly},
      ),
      fieldGuideMonthly,
    );
    expect(
      guideFieldGuideReplaces(GuideFieldGuidePlan.yearly, {subscriptionYearly}),
      isNull,
    );
  });

  test('monthly on this phone can change to yearly, and other plans cannot',
      () {
    GuideFieldGuideAccess access({
      required Set<String> owned,
      bool monthlyOnThisStore = false,
      bool fromAccountOnly = false,
      String? yearlyPrice = r'$19.99',
    }) {
      return guideFieldGuideAccess(
        catalog: guideFieldGuideCatalog(
          storeAvailable: true,
          yearlyPrice: yearlyPrice,
          monthlyPrice: r'$2.99',
          owned: owned,
        ),
        monthlyOnThisStore: monthlyOnThisStore,
        fromAccountOnly: fromAccountOnly,
      );
    }

    final upgrade = access(
      owned: {fieldGuideMonthly},
      monthlyOnThisStore: true,
    );
    expect(upgrade.upgrade, isTrue);
    expect(upgrade.locked, isFalse);

    final yearly = access(owned: {fieldGuideYearly}, monthlyOnThisStore: true);
    expect(yearly.upgrade, isFalse);
    expect(yearly.locked, isTrue);

    final photos = access(owned: {subscriptionMonthly});
    expect(photos.upgrade, isFalse);
    expect(photos.locked, isTrue);

    final account = access(
      owned: {fieldGuideMonthly},
      fromAccountOnly: true,
    );
    expect(account.upgrade, isFalse);
    expect(account.locked, isTrue);

    final noPrice = access(
      owned: {fieldGuideMonthly},
      monthlyOnThisStore: true,
      yearlyPrice: null,
    );
    expect(noPrice.upgrade, isFalse);
    expect(noPrice.locked, isTrue);

    final waiting = guideFieldGuideAccess(
      catalog: guideFieldGuideCatalog(
        storeAvailable: false,
        yearlyPrice: null,
        monthlyPrice: null,
        owned: {fieldGuideMonthly},
      ),
      monthlyOnThisStore: true,
      fromAccountOnly: false,
      awaitingStore: true,
    );
    expect(waiting.upgrade, isTrue);
    expect(waiting.locked, isFalse);

    final deadStore = guideFieldGuideAccess(
      catalog: guideFieldGuideCatalog(
        storeAvailable: false,
        yearlyPrice: null,
        monthlyPrice: null,
        owned: {fieldGuideMonthly},
      ),
      monthlyOnThisStore: true,
      fromAccountOnly: false,
    );
    expect(deadStore.upgrade, isFalse);
    expect(deadStore.locked, isTrue);

    final free = access(owned: const {});
    expect(free.upgrade, isFalse);
    expect(free.locked, isFalse);
  });

  test('the paid price stays on the row when a trial phase is present', () {
    final loaded = guideFieldGuideFromStore(
      storeAvailable: true,
      owned: const {},
      products: [
        _product(fieldGuideYearly, r'$0.00', 0),
        _product(fieldGuideYearly, r'$19.99', 19.99),
        _product(fieldGuideMonthly, r'$2.99', 2.99),
      ],
    );
    expect(loaded.catalog.yearly.price, r'$19.99');
    expect(loaded.catalog.yearly.trial, isTrue);
    expect(loaded.catalog.monthly.price, r'$2.99');
    expect(loaded.catalog.monthly.trial, isFalse);
    expect(loaded.products[fieldGuideYearly]?.rawPrice, 0);
    expect(loaded.products[fieldGuideMonthly]?.rawPrice, 2.99);
  });

  test('a Play trial phase keeps the later paid price on the row', () {
    final loaded = guideFieldGuideFromStore(
      storeAvailable: true,
      owned: const {},
      products: [
        _playOffer(
          id: fieldGuideYearly,
          token: 'yearly-trial',
          phases: const [
            (price: 'Free', micros: 0, period: 'P7D'),
            (price: r'$19.99', micros: 19990000, period: 'P1Y'),
          ],
        ),
        _playOffer(
          id: fieldGuideMonthly,
          token: 'monthly',
          phases: const [
            (price: r'$2.99', micros: 2990000, period: 'P1M'),
          ],
        ),
      ],
    );
    expect(loaded.catalog.yearly.price, r'$19.99');
    expect(loaded.catalog.yearly.trial, isTrue);
    expect(loaded.catalog.yearly.period, 'P1Y');
    expect(loaded.products[fieldGuideYearly]?.price, 'Free');
    expect(loaded.catalog.monthly.price, r'$2.99');
    expect(loaded.catalog.monthly.trial, isFalse);
    expect(loaded.catalog.monthly.period, 'P1M');
  });

  test('Field Guide plans hide ads, and the old paid app is not Field Guide',
      () {
    Purchases.hasOldVersion = true;
    expect(Purchases.hasFieldGuide(), isFalse);
    expect(Purchases.syncsSeenPhotos(), isTrue);
    expect(Purchases.isOffline(), isTrue);
    expect(Purchases.showsAds(), isFalse);

    Purchases.hasOldVersion = false;
    Purchases.purchases = {productOffline: _purchase(productOffline)};
    expect(Purchases.owns(productOffline), isFalse);
    expect(Purchases.isOffline(), isFalse);

    Purchases.purchases = {};
    Purchases.replaceAccountProducts({productPhotoSearch});
    expect(Purchases.syncsSeenPhotos(), isFalse);
    expect(Purchases.isOffline(), isFalse);

    Purchases.replaceAccountProducts({productOffline});
    expect(Purchases.syncsSeenPhotos(), isFalse);
    expect(Purchases.isOffline(), isTrue);

    Purchases.replaceAccountProducts({productObservations});
    Purchases.finishNames();
    expect(Purchases.syncsSeenPhotos(), isTrue);
    expect(Purchases.hasFieldGuide(), isFalse);
    expect(Purchases.isOffline(), isFalse);
    expect(Purchases.showsAds(), isTrue);
    expect(Purchases.namesUnlimited, isFalse);

    Purchases.clearAccountProducts();
    expect(Purchases.syncsSeenPhotos(), isFalse);
    expect(Purchases.isOffline(), isFalse);

    Purchases.replaceAccountProducts({fieldGuideMonthly});
    expect(Purchases.hasFieldGuide(), isTrue);
    expect(Purchases.showsAds(), isFalse);

    Purchases.replaceAccountProducts({subscriptionMonthly});
    expect(Purchases.hasFieldGuide(), isTrue);

    Purchases.clearAccountProducts();
    expect(Purchases.showsAds(), isTrue);
  });

  testWidgets('yearly is selected and the store price starts that plan',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GuideFieldGuidePlan? bought;
    var restored = 0;
    await tester.pumpWidget(_app(_page(
      catalog: _priced(),
      onBuy: (plan) async {
        bought = plan;
        return true;
      },
      onRestore: () async => restored++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Field Guide'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Unlimited names from photos'), findsOneWidget);
    expect(find.text(r'$19.99'), findsOneWidget);
    expect(find.text(r'$2.99'), findsOneWidget);
    expect(find.text(r'7 days free, then $19.99 a year'), findsOneWidget);
    expect(find.text(r'7 days free, then $2.99 a month'), findsOneWidget);
    expect(
      find.text(
        r'Free for 7 days. The trial ends after 7 days, then $19.99 is charged every year. Cancel in Google Play before the trial ends and you will not be charged.',
      ),
      findsOneWidget,
    );
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.text('Manage or cancel in Google Play'), findsOneWidget);

    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pump();
    expect(bought, GuideFieldGuidePlan.yearly);

    await tester.tap(find.text('Monthly'));
    await tester.pump();
    expect(
      find.text(
        r'Free for 7 days. The trial ends after 7 days, then $2.99 is charged every month. Cancel in Google Play before the trial ends and you will not be charged.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pump();
    expect(bought, GuideFieldGuidePlan.monthly);

    await tester.tap(find.byKey(guideFieldGuideRestoreKey));
    await tester.pump();
    expect(restored, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an owned yearly plan is only a summary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var bought = 0;
    var restored = 0;
    await tester.pumpWidget(_app(_page(
      catalog: guideFieldGuideCatalog(
        storeAvailable: true,
        yearlyPrice: r'$19.99',
        monthlyPrice: r'$2.99',
        owned: {fieldGuideYearly},
      ),
      onBuy: (_) async {
        bought++;
        return true;
      },
      onRestore: () async => restored++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('You already have Field Guide.'), findsOneWidget);
    expect(find.text('Subscribed'), findsWidgets);
    expect(find.text('Subscribe'), findsNothing);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    await tester.tap(find.text('Monthly'));
    await tester.pump();
    expect(find.text('Change'), findsNothing);
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.tap(find.byKey(guideFieldGuideRestoreKey));
    await tester.pump();
    expect(bought, 0);
    expect(restored, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly on this phone can change to yearly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Purchases.purchases[fieldGuideMonthly] = _purchase(fieldGuideMonthly);
    GuideFieldGuidePlan? bought;
    await tester.pumpWidget(_app(_page(
      catalog: guideFieldGuideCatalog(
        storeAvailable: true,
        yearlyPrice: r'$19.99',
        monthlyPrice: r'$2.99',
        owned: {fieldGuideMonthly},
      ),
      onBuy: (plan) async {
        bought = plan;
        return true;
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    expect(find.text('You already have Field Guide.'), findsNothing);
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pump();
    expect(bought, GuideFieldGuidePlan.yearly);

    await tester.tap(find.text('Monthly'));
    await tester.pump();
    expect(find.text('Subscribed'), findsOneWidget);
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pump();
    expect(bought, GuideFieldGuidePlan.yearly);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a photo-storage plan is Field Guide already', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_page(
      catalog: guideFieldGuideCatalog(
        storeAvailable: true,
        yearlyPrice: r'$19.99',
        monthlyPrice: r'$2.99',
        owned: {subscriptionMonthly},
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('You already have Field Guide.'), findsOneWidget);
    expect(
      find.text('Your photo-storage plan counts as Field Guide.'),
      findsOneWidget,
    );
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Subscribed'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.tap(find.text('Yearly'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing store price does not start a purchase',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var bought = 0;
    await tester.pumpWidget(_app(_page(
      catalog: guideFieldGuideCatalog(
        storeAvailable: false,
        yearlyPrice: null,
        monthlyPrice: null,
        owned: const {},
      ),
      onBuy: (_) async {
        bought++;
        return true;
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('Store price'), findsNWidgets(2));
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pump();
    expect(bought, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page opens while the store is still answering',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gate = Completer<GuideFieldGuideLoaded>();
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete(GuideFieldGuideLoaded(catalog: _priced()));
      }
    });
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      load: () => gate.future,
      storeTimeout: const Duration(seconds: 30),
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pump();

    expect(find.text('Field Guide'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    gate.complete(GuideFieldGuideLoaded(catalog: _priced()));
    await tester.pump();
    expect(find.text(r'$19.99'), findsOneWidget);
    expect(find.text(r'$2.99'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a monthly plan stays open while the yearly price is still coming',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Purchases.purchases[fieldGuideMonthly] = _purchase(fieldGuideMonthly);
    Purchases.replaceAccountProducts({fieldGuideMonthly});
    final gate = Completer<GuideFieldGuideLoaded>();
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete(GuideFieldGuideLoaded(
          catalog: guideFieldGuideCatalog(
            storeAvailable: true,
            yearlyPrice: r'$19.99',
            monthlyPrice: r'$2.99',
            owned: {fieldGuideMonthly},
          ),
        ));
      }
    });
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      load: () => gate.future,
      storeTimeout: const Duration(seconds: 30),
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pump();

    expect(find.text('You already have Field Guide.'), findsNothing);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsNothing,
    );

    gate.complete(GuideFieldGuideLoaded(
      catalog: guideFieldGuideCatalog(
        storeAvailable: true,
        yearlyPrice: r'$19.99',
        monthlyPrice: r'$2.99',
        owned: {fieldGuideMonthly},
      ),
    ));
    await tester.pump();
    expect(find.text(r'$19.99'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a store that fails after the wait can be tried again',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    final gates = <Completer<GuideFieldGuideLoaded>>[];
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      load: () {
        calls++;
        final gate = Completer<GuideFieldGuideLoaded>();
        gates.add(gate);
        return gate.future;
      },
      storeTimeout: const Duration(milliseconds: 20),
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Field Guide'), findsOneWidget);

    gates.single.completeError(StateError('store'));
    await tester.pump();
    expect(find.text('Couldn’t load your account'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsNothing,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(calls, 2);
    gates.last.complete(GuideFieldGuideLoaded(catalog: _priced()));
    await tester.pump();
    expect(find.text(r'$19.99'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a store that never answers leaves the plans without a price',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      load: () => Completer<GuideFieldGuideLoaded>().future,
      storeTimeout: const Duration(milliseconds: 20),
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pump();
    expect(find.text('Field Guide'), findsOneWidget);
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Field Guide'), findsOneWidget);
    expect(find.text('Store price'), findsNWidgets(2));
    expect(
      find.text('The store doesn’t have these plans yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode keeps the page on the dark paper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_page(
      catalog: _priced(),
      appearance: GuideAppearance.dark,
    )));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Field Guide')))
          .scaffoldBackgroundColor,
      GuideColors.dark.paper,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a signed-out tap on Start or Restore asks for sign-in before buying',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var signedIn = false;
    var signInCalls = 0;
    var buyCalls = 0;
    var restoreCalls = 0;

    await tester.pumpWidget(_app(GuideFieldGuidePage(
      key: const ValueKey('cancel'),
      load: () async => GuideFieldGuideLoaded(catalog: _priced()),
      signedIn: () => signedIn,
      signIn: (_) async {
        signInCalls++;
      },
      buy: (_) async {
        buyCalls++;
        return true;
      },
      restore: () async {
        restoreCalls++;
      },
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pumpAndSettle();

    // Canceled sign-in does not start a purchase or restore.
    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pumpAndSettle();
    expect(signInCalls, 1);
    expect(buyCalls, 0);

    await tester.tap(find.byKey(guideFieldGuideRestoreKey));
    await tester.pumpAndSettle();
    expect(signInCalls, 2);
    expect(restoreCalls, 0);

    // Completing sign-in proceeds to purchase when the account does not own it.
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      key: const ValueKey('proceed'),
      load: () async => GuideFieldGuideLoaded(catalog: _priced()),
      signedIn: () => signedIn,
      signIn: (_) async {
        signInCalls++;
        signedIn = true;
      },
      buy: (_) async {
        buyCalls++;
        return true;
      },
      restore: () async {
        restoreCalls++;
      },
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pumpAndSettle();
    expect(signInCalls, 3);
    expect(buyCalls, 1);

    // Signing in to an account that already owns Field Guide skips buying.
    signedIn = false;
    await tester.pumpWidget(_app(GuideFieldGuidePage(
      key: const ValueKey('alreadyOwned'),
      load: () async => GuideFieldGuideLoaded(catalog: _priced()),
      signedIn: () => signedIn,
      signIn: (_) async {
        signInCalls++;
        signedIn = true;
        Purchases.replaceAccountProducts({fieldGuideYearly});
      },
      buy: (_) async {
        buyCalls++;
        return true;
      },
      plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guideFieldGuideStartKey));
    await tester.pumpAndSettle();
    expect(signInCalls, 4);
    expect(buyCalls, 1);
  });
}

GuideFieldGuideCatalog _priced() {
  return guideFieldGuideCatalog(
    storeAvailable: true,
    yearlyPrice: r'$19.99',
    monthlyPrice: r'$2.99',
    owned: const {},
  );
}

Widget _page({
  required GuideFieldGuideCatalog catalog,
  Future<bool> Function(GuideFieldGuidePlan plan)? onBuy,
  Future<void> Function()? onRestore,
  GuideAppearance? appearance,
}) {
  return GuideFieldGuidePage(
    appearance: appearance,
    load: () async => GuideFieldGuideLoaded(catalog: catalog),
    buy: onBuy ?? (_) async => false,
    restore: onRestore ?? () async {},
    plate: (_) => const ColoredBox(color: Color(0xFFEFE6D3)),
  );
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: home,
  );
}

ProductDetails _playOffer({
  required String id,
  required String token,
  required List<({String price, int micros, String period})> phases,
}) {
  return GooglePlayProductDetails.fromProductDetails(
    ProductDetailsWrapper(
      description: '',
      name: id,
      productId: id,
      productType: ProductType.subs,
      title: id,
      subscriptionOfferDetails: [
        SubscriptionOfferDetailsWrapper(
          basePlanId: id,
          offerId: token,
          offerTags: const [],
          offerIdToken: token,
          pricingPhases: [
            for (final phase in phases)
              PricingPhaseWrapper(
                billingCycleCount: phase.micros == 0 ? 1 : 0,
                billingPeriod: phase.period,
                formattedPrice: phase.price,
                priceAmountMicros: phase.micros,
                priceCurrencyCode: 'USD',
                recurrenceMode: phase.micros == 0
                    ? RecurrenceMode.finiteRecurring
                    : RecurrenceMode.infiniteRecurring,
              ),
          ],
        ),
      ],
    ),
  ).single;
}

ProductDetails _product(String id, String price, double raw) {
  return ProductDetails(
    id: id,
    title: id,
    description: '',
    price: price,
    rawPrice: raw,
    currencyCode: 'USD',
  );
}

PurchaseDetails _purchase(String id) {
  return PurchaseDetails(
    productID: id,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'test',
    ),
    transactionDate: '0',
    status: PurchaseStatus.purchased,
  );
}
