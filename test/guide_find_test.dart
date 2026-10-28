import 'dart:ui' show Tristate;

import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/find/find_page.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/species/species_page.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    Purchases.hasOldVersion = false;
    Purchases.purchases = {};
    Purchases.clearAccountProducts();
    GuideTabs.unconfirmed.value = 0;
  });

  tearDown(() {
    Purchases.hasOldVersion = false;
    Purchases.purchases = {};
    Purchases.clearAccountProducts();
  });

  test('the cover is the newest year in the list', () {
    expect(readGuideList(null).count, 0);
    expect(readGuideList('meadow').count, 0);

    final plain = readGuideList([null, '69', null]);
    expect(plain.count, 1);
    expect(plain.coverId, '1');
    expect(plain.year, isNull);

    final ordered = readGuideList({'10': 1, '2': 1});
    expect(ordered.coverId, '2');
    expect(ordered.year, isNull);

    final years = readGuideList({'5': 1, '9': 2024, '3': 2019});
    expect(years.count, 3);
    expect(years.coverId, '9');
    expect(years.year, 2024);

    final tied = readGuideList({'1': 2020, '2': 2020});
    expect(tied.coverId, '1');
    expect(tied.year, 2020);

    final edge = readGuideList({'1': 1899, '2': 2100, '4': 2101, '8': '2024'});
    expect(edge.count, 4);
    expect(edge.coverId, '2');
    expect(edge.year, 2100);

    final words = readGuideList({'b': 1, 'a': 2020.0, 'm': null});
    expect(words.count, 2);
    expect(words.coverId, 'a');
    expect(words.year, 2020);

    expect(plain.thumbIds, ['1']);
    expect(plain.yearFrom, isNull);
    expect(ordered.thumbIds, ['2', '10']);
    expect(years.thumbIds, ['9', '3']);
    expect(years.yearFrom, 2019);
    expect(tied.thumbIds, ['1', '2']);
    expect(tied.yearFrom, 2020);
    expect(edge.thumbIds, ['2']);
    expect(edge.yearFrom, 2100);
    expect(words.thumbIds, ['a']);
    expect(words.yearFrom, 2020);

    final states = readGuideList({
      '9': 'California',
      '2': {'Connecticut': 1, 'Pennsylvania': 1},
      '4': 'Alabama',
      '8': '2024',
    });
    expect(states.labeled, isTrue);
    expect(states.year, isNull);
    expect(states.count, 4);
    expect(states.coverId, '4');
    expect(states.thumbIds, ['4', '9', '2']);
    expect(
      readGuideStateIds({
        '9': 'California',
        '2': {'Pennsylvania': 1, 'Connecticut': 1},
        '4': 'Alabama',
      }).map((row) => '${row.state}:${row.id}'),
      ['Alabama:4', 'California:9', 'Connecticut:2', 'Pennsylvania:2'],
    );

    final withGenera = readGuideList(
      {
        '4': 'Alabama',
        '9': 'California',
      },
      genera: {
        'Viola': 'Illinois',
        'Rosa': {'New York': 1, 'Oklahoma': 1},
        '12': 'Wisconsin',
      },
    );
    expect(withGenera.labeled, isTrue);
    expect(withGenera.count, 5);
    expect(withGenera.coverId, '4');
    expect(withGenera.coverGenus, isNull);

    final genusFirst = readGuideList(
      {'3': 'Wyoming'},
      genera: {'Viola': 'Alabama'},
    );
    expect(genusFirst.labeled, isTrue);
    expect(genusFirst.count, 2);
    expect(genusFirst.coverId, isNull);
    expect(genusFirst.coverGenus, 'Viola');

    final membership = readGuideList(
      {'1': 1, '2': 1},
      genera: {'Rosa': 'New York'},
    );
    expect(membership.labeled, isFalse);
    expect(membership.count, 3);
    expect(membership.coverId, '1');
    expect(membership.coverGenus, isNull);

    final newerGenus = readGuideList(
      {'1': 2020},
      genera: {'Quercus': 2024},
    );
    expect(newerGenus.count, 2);
    expect(newerGenus.year, 2024);
    expect(newerGenus.coverId, isNull);
    expect(newerGenus.coverGenus, 'Quercus');
    expect(guideGenusSampleId('Viola', const ['635', '1090']), '1090');
    expect(guideGenusSampleId('Yucca', const []), isNull);
    expect(guideGenusSampleId('Quercus', const ['4', '8']), '4');

    expect(
      readGuideTimeline(
        {'4': 'Alabama', '9': 'California'},
        {
          'Viola': 'Illinois',
          'Rosa': {'Oklahoma': 1, 'New York': 1},
        },
      ).map((row) => '${row.state}:${row.id ?? row.genus}'),
      [
        'Alabama:4',
        'California:9',
        'Illinois:Viola',
        'New York:Rosa',
        'Oklahoma:Rosa',
      ],
    );

    final span = readGuideList({
      '1': 2018,
      '2': 2020,
      '3': 2019,
      '4': 2022,
      '5': 2021,
      '6': 2017,
    });
    expect(span.coverId, '4');
    expect(span.year, 2022);
    expect(span.yearFrom, 2017);
    expect(span.thumbIds, ['4', '5', '2', '3']);
  });

  test('new lists come first, then sourced, then a parameter, then titles', () {
    final covers = [
      _cover(title: 'meadows', count: 3),
      _cover(title: 'Alpine', count: 6, year: 2024),
      _cover(title: 'zzzz', count: 2, isNew: true),
      _cover(title: 'beeches', count: 2, year: 2020),
      _cover(title: 'Baum des Jahres', count: 4, hasSource: true, year: 2024),
      _cover(title: 'California', count: 5, parameter: 'California'),
    ];
    covers.sort(compareGuideLists);
    expect(
      covers.map((cover) => cover.title),
      [
        'zzzz',
        'Baum des Jahres',
        'Alpine',
        'beeches',
        'California',
        'meadows',
      ],
    );
    expect(guideListRank(covers.first), 0);
    expect(guideListRank(covers[1]), 1);
    expect(guideListRank(covers[2]), 2);
    expect(guideListRank(covers.last), 3);
  });

  test('two parameter lists sort by the parameter, not the title', () {
    final covers = [
      _cover(title: 'Aaa Wyoming', count: 2, parameter: 'Wyoming'),
      _cover(title: 'Zzz Alabama', count: 3, parameter: 'Alabama'),
      _cover(title: 'Middle', count: 4, year: 2024),
      _cover(title: 'Vegetables', count: 9),
    ];
    covers.sort(compareGuideLists);
    expect(
      covers.map((cover) => cover.title),
      ['Zzz Alabama', 'Middle', 'Aaa Wyoming', 'Vegetables'],
    );
  });

  test('New in the book stays first among the other lists', () {
    final covers = [
      _cover(title: 'Vegetables', count: 9),
      _cover(title: 'zzzz', count: 2, isNew: true),
      _cover(title: 'Spices', count: 8),
      _cover(
        title: 'Fleurs « canadensis »',
        count: 11,
        parameter: 'canadensis',
      ),
    ];
    covers.sort(compareGuideLists);
    expect(covers.first.isNew, isTrue);
    expect(
      covers.map((cover) => cover.title),
      ['zzzz', 'Fleurs « canadensis »', 'Spices', 'Vegetables'],
    );
  });

  test('Favorite flowers sorts ahead of New in the book', () {
    final covers = [
      _cover(title: 'Vegetables', count: 9),
      _cover(title: '', count: 2, isFavorite: true),
      _cover(title: 'zzzz', count: 2, isNew: true),
      _cover(title: 'Spices', count: 8, hasSource: true),
    ];
    covers.sort(compareGuideLists);
    expect(covers.first.isFavorite, isTrue);
    expect(covers[1].isNew, isTrue);
    expect(guideListRank(covers.first), -1);
    expect(guideListRank(covers[1]), 0);
  });

  test('a find keeps its own time and first photo', () {
    final when = guideFindWhen({
      observationDate: {observationTime: 1500.9},
    });
    expect(when, DateTime.fromMillisecondsSinceEpoch(1500));
    expect(guideFindWhen({}), DateTime.fromMillisecondsSinceEpoch(0));
    expect(
      guideFindWhen({
        observationDate: {observationTime: 'soon'}
      }),
      DateTime.fromMillisecondsSinceEpoch(0),
    );

    expect(guideFirstText([null, '', 'a.jpg', 'b.jpg']), 'a.jpg');
    expect(guideFirstText({'2': 'b.jpg', '10': 'c.jpg', '1': ''}), 'c.jpg');
    expect(guideFirstText(null), isNull);
  });

  test('a missing confirmed flag counts as confirmed', () {
    expect(guideFindConfirmed({}), isTrue);
    expect(guideFindConfirmed({observationConfirmed: true}), isTrue);
    expect(guideFindConfirmed({observationConfirmed: false}), isFalse);
    expect(guideFindConfirmed({observationConfirmed: 'false'}), isTrue);
  });

  testWidgets('pins the banner above Find and Book, and leaves Seen clear',
      (tester) async {
    Purchases.hasOldVersion = true;
    var index = 0;
    Widget bar() {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: GuideBottomBar(
            index: index,
            showAd: index == 0 || index == 1,
            onSelect: (next) => index = next,
          ),
        ),
      );
    }

    await tester.pumpWidget(bar());
    expect(find.byType(AppBannerAd), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);

    index = 1;
    await tester.pumpWidget(bar());
    expect(find.byType(AppBannerAd), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);

    index = 2;
    await tester.pumpWidget(bar());
    expect(find.byType(AppBannerAd), findsNothing);
    expect(find.text('Seen'), findsOneWidget);
  });

  testWidgets('shows the key, the first five finds, and the list covers',
      (tester) async {
    Purchases.hasOldVersion = true;
    var seen = 0;
    var book = 0;
    final when = DateTime(2026, 9, 29, 15, 4);
    final latest = DateTime(2026, 9, 1);
    final finds = [
      GuideFind(
        name: 'Bellis perennis',
        label: 'oxeye',
        when: when,
        photoPath: null,
      ),
      for (var n = 2; n <= 6; n++)
        GuideFind(
          name: 'Find $n',
          label: null,
          when: when,
          photoPath: null,
        ),
    ];

    await _pump(
      tester,
      _page(
        colorCounts: const {'1': 12, '2': 0, '4': 7},
        finds: finds,
        allowance: const GuideAllowance.unlimited(
          fieldGuide: false,
          unlimitedNames: true,
          noAds: true,
          seenSynced: false,
        ),
        lists: [
          _cover(title: 'Alpine flowers', count: 6, year: 2024),
          _cover(title: 'Meadows', count: 11),
          _cover(title: '', count: 2, isNew: true, latest: latest),
        ],
        onOpenSeen: () => seen++,
        onOpenBook: () => book++,
      ),
    );

    expect(find.byType(AppBannerAd), findsNothing);
    expect(find.text('What’s that flower?'), findsOneWidget);
    expect(find.text('Search plants, families, genera'), findsOneWidget);
    expect(find.text('Name it from a photo'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('KEY IT OUT · 1 OF 3'), findsOneWidget);
    expect(find.text('ALWAYS FREE'), findsOneWidget);
    expect(find.text('What color is the flower?'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Red, pink'), findsOneWidget);
    expect(find.text('Blue, purple'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    final count = tester.getRect(find.text('12'));
    final label = tester.getRect(find.text('White'));
    expect(count.top, lessThan(label.top));
    expect(count.center.dx, greaterThan(label.center.dx));
    expect(find.text('null'), findsNothing);

    expect(find.text('oxeye'), findsOneWidget);
    expect(find.text('To confirm'), findsNothing);
    expect(find.text('Bellis perennis'), findsNothing);
    expect(find.text('Find 5', skipOffstage: false), findsOneWidget);
    expect(find.text('Find 6', skipOffstage: false), findsNothing);
    final context = tester.element(find.text('Seen lately'));
    expect(
      find.text(guideWhen(context, when), skipOffstage: false),
      findsNWidgets(5),
    );

    expect(find.text('New in the book'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New in the book')).dx,
      lessThan(tester.getTopLeft(find.text('Alpine flowers')).dx),
    );
    final date = MaterialLocalizations.of(context).formatMediumDate(latest);
    expect(find.text('Latest $date'), findsOneWidget);
    expect(find.text('6 years · 2024'), findsOneWidget);
    expect(find.text('11 plants'), findsOneWidget);
    expect(_goldBorders, findsOneWidget);

    await tester.tap(find.text('All finds'));
    await tester.tap(find.text('All lists'));
    await tester.pump();
    expect(seen, 1);
    expect(book, 1);
  });

  testWidgets('Favorite flowers leads Find, and New in the book stays second',
      (tester) async {
    final favorites = _cover(title: '', count: 2, isFavorite: true);
    final lists = [
      _cover(title: 'Alpine flowers', count: 6, year: 2024),
      _cover(title: 'Dropped', count: 3, isFavorite: true),
      _cover(title: '', count: 2, isNew: true, latest: DateTime(2026, 9, 1)),
    ];

    await _pump(tester, _page(lists: lists, favorites: favorites));

    expect(find.text('Favorite flowers'), findsOneWidget);
    expect(find.text('2 plants'), findsOneWidget);
    expect(find.text('Dropped'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Favorite flowers')).dx,
      lessThan(tester.getTopLeft(find.text('New in the book')).dx),
    );
    expect(
      tester.getTopLeft(find.text('New in the book')).dx,
      lessThan(tester.getTopLeft(find.text('Alpine flowers')).dx),
    );
    expect(_goldBorders, findsOneWidget);

    await _pump(
      tester,
      _page(
        lists: lists,
        favorites: _cover(title: '', count: 0, isFavorite: true),
      ),
    );
    expect(find.text('Favorite flowers'), findsNothing);
    expect(find.text('Dropped'), findsNothing);
    expect(
      tester.getTopLeft(find.text('New in the book')).dx,
      lessThan(tester.getTopLeft(find.text('Alpine flowers')).dx),
    );

    await _pump(tester, _page(lists: null, favorites: favorites));
    expect(find.text('Favorite flowers'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a failed list load can be tried again', (tester) async {
    var tries = 0;
    await _pump(
      tester,
      _page(
        lists: null,
        listsFailed: true,
        onRetryLists: () => tries++,
      ),
    );

    expect(
      find.text("This feature doesn't work without Internet connection."),
      findsOneWidget,
    );
    expect(find.text('Lists of flowers'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(
      find.text("This feature doesn't work without Internet connection."),
    );
    expect(tries, 1);
  });

  testWidgets('hides finds and covers that are not ready', (tester) async {
    Purchases.hasOldVersion = true;
    await _pump(tester, _page(finds: null, lists: null));
    expect(find.text('Seen lately'), findsNothing);
    expect(find.text('Lists of flowers'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(tester, _page(finds: const [], lists: const []));
    expect(find.text('Seen lately'), findsNothing);
    expect(find.text('All lists'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('Remove ads and Field Guide hide banners', () {
    Purchases.hasOldVersion = false;
    Purchases.clearAccountProducts();
    expect(Purchases.showsAds(), isTrue);

    Purchases.replaceAccountProducts({_noAds().productID});
    expect(Purchases.showsAds(), isFalse);

    Purchases.clearAccountProducts();
    Purchases.hasOldVersion = true;
    expect(Purchases.showsAds(), isFalse);

    Purchases.hasOldVersion = false;
    expect(Purchases.showsAds(), isTrue);
  });

  testWidgets('a no-ads purchase leaves Find without a banner', (tester) async {
    Purchases.hasOldVersion = false;
    Purchases.replaceAccountProducts({_noAds().productID});
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: GuideBottomBar(
          index: 0,
          showAd: Purchases.showsAds(),
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byType(AppBannerAd), findsNothing);
    expect(find.text('Find'), findsOneWidget);
  });

  testWidgets('selects the icon for the open tab', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_tabs(index: 1));

    expect(
      tester.widget<Text>(find.text('Book')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Book')).style?.color,
      GuideColors.light.moss,
    );
    expect(
      tester.widget<Text>(find.text('Find')).style?.fontWeight,
      FontWeight.w400,
    );
    expect(
      tester.widget<Text>(find.text('Seen')).style?.fontWeight,
      FontWeight.w400,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Book, Tab 2 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Find, Tab 1 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Seen, Tab 3 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );

    final pill = tester.getRect(find.byKey(guideTabIndicatorKey));
    final book = tester.getRect(find.byIcon(Icons.menu_book_outlined));
    expect(pill.width, 64);
    expect(pill.height, 32);
    expect(pill.contains(book.center), isTrue);
    expect(find.byKey(guideTabIndicatorKey), findsOneWidget);
    final paint = tester.widget<DecoratedBox>(find.byKey(guideTabIndicatorKey));
    expect(
      (paint.decoration as BoxDecoration).color,
      GuideColors.light.paper2,
    );
    expect(
      (paint.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(16),
    );

    await tester.pumpWidget(_tabs(index: 0, personOn: true));
    expect(find.byKey(guideTabIndicatorKey), findsNothing);
    handle.dispose();
  });

  testWidgets('shows the unconfirmed count on the Seen icon', (tester) async {
    GuideTabs.unconfirmed.value = 3;
    await tester.pumpWidget(_tabs());
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(guideUnconfirmedBadgeKey), findsOneWidget);

    final icon = tester.getRect(find.byIcon(Icons.article_outlined));
    final badge = tester.getRect(find.byKey(guideUnconfirmedBadgeKey));
    final bar = tester.getRect(find.byType(GuideTabBar));
    expect(badge.top, closeTo(icon.top + 1, 0.5));
    expect(badge.center.dy, lessThan(icon.center.dy));
    expect(badge.center.dx, greaterThan(icon.center.dx));
    expect(badge.top, greaterThanOrEqualTo(bar.top));
    expect(badge.right, lessThanOrEqualTo(bar.right));

    final paint = tester.widget<DecoratedBox>(
      find.byKey(guideUnconfirmedBadgeKey),
    );
    expect(
      (paint.decoration as BoxDecoration).color,
      GuideColors.light.madderFill,
    );

    GuideTabs.unconfirmed.value = 120;
    await tester.pump();
    expect(find.text('99+'), findsOneWidget);

    GuideTabs.unconfirmed.value = 0;
    await tester.pump();
    expect(find.byKey(guideUnconfirmedBadgeKey), findsNothing);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
  });

  testWidgets('a tab name includes its place for screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_tabs());

    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
    expect(find.bySemanticsLabel('Find, Tab 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Book, Tab 2 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Seen, Tab 3 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Book'), findsNothing);
    expect(find.bySemanticsLabel('Seen'), findsNothing);

    GuideTabs.unconfirmed.value = 3;
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Seen, Tab 3 of 3, 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Seen, Tab 3 of 3'), findsNothing);

    GuideTabs.unconfirmed.value = 120;
    await tester.pump();
    expect(find.text('99+'), findsOneWidget);
    expect(find.bySemanticsLabel('Seen, Tab 3 of 3, 99+'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the side rail names tabs the same way', (tester) async {
    final handle = tester.ensureSemantics();
    GuideTabs.unconfirmed.value = 4;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Scaffold(
        body: GuideSideRail(
          personOn: false,
          onSelect: (_) {},
          onPerson: () {},
        ),
      ),
    ));

    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
    expect(find.bySemanticsLabel('Find, Tab 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Book, Tab 2 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Seen, Tab 3 of 3, 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Person'), findsOneWidget);
    expect(find.bySemanticsLabel('Book'), findsNothing);
    handle.dispose();
  });

  testWidgets('a wrapped Latin name fits the Seen-lately strip',
      (tester) async {
    final when = DateTime(2026, 10, 7, 14, 15);
    final finds = [
      GuideFind(
        name: 'Heterotheca subaxillaris',
        label: null,
        when: when,
        photoPath: null,
      ),
      GuideFind(
        name: 'Bidens aristosa',
        label: null,
        when: when,
        photoPath: null,
      ),
    ];

    Future<void> pump({double textScale = 1}) {
      return _pumpPhone(
        tester,
        _page(
          finds: finds,
          lists: const [],
          locale: const Locale('ja'),
          textScale: textScale,
        ),
      );
    }

    await pump();
    expect(tester.takeException(), isNull);
    // Heterotheca subaxillaris wraps inside the 118-wide card. One line is
    // about 16px; a wrapped name is the case that overflowed.
    expect(
      tester.getSize(find.text('Heterotheca subaxillaris')).height,
      greaterThan(24),
    );
    _expectDateInsideStrip(tester, when);

    await pump(textScale: 1.5);
    expect(tester.takeException(), isNull);
    _expectDateInsideStrip(tester, when);
    expect(_findStripHeight(tester), greaterThan(180));
  });

  testWidgets('an unconfirmed find wears To confirm and opens Seen',
      (tester) async {
    Purchases.hasOldVersion = true;
    var seen = 0;
    final when = DateTime(2026, 9, 29, 15, 4);
    await _pump(
      tester,
      _page(
        finds: [
          GuideFind(
            name: 'Bellis perennis',
            label: 'oxeye',
            when: when,
            photoPath: null,
            confirmed: false,
          ),
          GuideFind(
            name: 'Leucanthemum vulgare',
            label: 'daisy',
            when: when,
            photoPath: null,
          ),
        ],
        lists: const [],
        onOpenSeen: () => seen++,
      ),
    );

    expect(find.text('To confirm'), findsOneWidget);
    final photo = tester.getRect(find.byType(GuidePhoto).first);
    final badge = tester.getRect(find.byKey(guideFindToConfirmKey));
    expect(badge.top, closeTo(photo.top + 6, 0.5));
    expect(badge.left, closeTo(photo.left + 6, 0.5));
    final paint = tester.widget<DecoratedBox>(
      find.byKey(guideFindToConfirmKey),
    );
    expect(
      (paint.decoration as BoxDecoration).color,
      GuideColors.light.madderFill,
    );

    await tester.tap(find.text('To confirm'));
    await tester.pump();
    expect(seen, 1);
    expect(find.byType(GuideSpeciesPage), findsNothing);

    await tester.tap(find.text('daisy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(seen, 1);
    expect(
      tester
          .widget<GuideSpeciesPage>(
            find.byType(GuideSpeciesPage, skipOffstage: false),
          )
          .name,
      'Leucanthemum vulgare',
    );
  });

  testWidgets('a Field Guide shows Field Guide - unlimited on the photo card',
      (tester) async {
    await _pump(
      tester,
      _page(
        finds: const [],
        lists: const [],
        allowance: const GuideAllowance.unlimited(
          fieldGuide: true,
          unlimitedNames: true,
          noAds: true,
          seenSynced: true,
        ),
      ),
    );
    expect(find.text('Field Guide - unlimited'), findsOneWidget);
    expect(find.text('Unlimited'), findsNothing);
  });

  testWidgets('asks a signed-out reader to sign in', (tester) async {
    Purchases.replaceAccountProducts({_noAds().productID});
    await _pump(tester, _page(finds: const [], lists: const []));
    expect(find.text('Sign in to name a photo'), findsOneWidget);
    expect(find.text('Unlimited'), findsNothing);
  });

  testWidgets('a first open has one free photo name', (tester) async {
    await _pump(
      tester,
      _page(
        finds: const [],
        lists: const [],
        allowance: const GuideAllowance.guest(free: true),
      ),
    );
    expect(find.text('1 name left'), findsOneWidget);
    expect(find.text('Sign in to name a photo'), findsNothing);
  });

  testWidgets('a signed-in month shows the names still left', (tester) async {
    await _pump(
      tester,
      _page(
        finds: const [],
        lists: const [],
        allowance: GuideAllowance.month(
          used: 2,
          fromAds: 0,
          now: DateTime(2026, 9, 30),
        ),
      ),
    );
    expect(find.text('3 names left'), findsOneWidget);
    expect(find.text('Sign in to name a photo'), findsNothing);
  });
}

Widget _tabs({int index = 0, bool personOn = false}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: GuideBottomBar(
        index: index,
        personOn: personOn,
        onSelect: (_) {},
      ),
    ),
  );
}

GuideListCover _cover({
  required String title,
  required int count,
  bool isNew = false,
  bool hasSource = false,
  bool isFavorite = false,
  String parameter = '',
  int? year,
  DateTime? latest,
}) {
  return GuideListCover(
    title: title,
    photoPath: null,
    path: FirebaseDatabase.instance.ref('lists'),
    isNew: isNew,
    count: count,
    year: year,
    latest: latest,
    hasSource: hasSource,
    parameter: parameter,
    isFavorite: isFavorite,
  );
}

final _goldBorders = find.byWidgetPredicate((widget) {
  if (widget is! DecoratedBox) return false;
  final decoration = widget.decoration;
  if (decoration is! BoxDecoration) return false;
  final border = decoration.border;
  return border is Border &&
      border.top.color == GuidePalette.gold &&
      border.top.width == 2;
});

PurchaseDetails _noAds() {
  return PurchaseDetails(
    productID: productNoAdsIOS,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'test',
    ),
    transactionDate: '0',
    status: PurchaseStatus.purchased,
  );
}

Widget _page({
  Map<String, int>? colorCounts = const {},
  List<GuideFind>? finds = const [],
  List<GuideListCover>? lists = const [],
  bool listsFailed = false,
  VoidCallback? onRetryLists,
  GuideListCover? favorites,
  GuideAllowance allowance = const GuideAllowance.guest(),
  VoidCallback? onOpenBook,
  VoidCallback? onOpenSeen,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) {
  return MaterialApp(
    locale: locale,
    builder: textScale == 1
        ? null
        : (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            );
          },
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: Scaffold(
      body: FindPage(
        colorCounts: colorCounts,
        lists: lists,
        listsFailed: listsFailed,
        onRetryLists: onRetryLists,
        favorites: favorites,
        finds: finds,
        allowance: allowance,
        onOpenBook: onOpenBook ?? () {},
        onOpenSeen: onOpenSeen ?? () {},
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await tester.pump();
}

/// Pixel 10 Pro: 1080×2410 at 420 dpi. The Seen-lately strip overflowed here.
Future<void> _pumpPhone(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1080, 2410);
  tester.view.devicePixelRatio = 420 / 160;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await tester.pump();
}

double _findStripHeight(WidgetTester tester) {
  return tester.getSize(_findStrip).height;
}

void _expectDateInsideStrip(WidgetTester tester, DateTime when) {
  final context = tester.element(find.text('Heterotheca subaxillaris'));
  final date = tester.getRect(find.text(guideWhen(context, when)).first);
  final strip = tester.getRect(_findStrip);
  expect(date.top, greaterThanOrEqualTo(strip.top));
  expect(date.bottom, lessThanOrEqualTo(strip.bottom + 0.1));
}

final _findStrip = find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);
