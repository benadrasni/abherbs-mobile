import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/key/guide_path.dart';
import 'package:abherbs_flutter/key/habitat_glyphs.dart';
import 'package:abherbs_flutter/key/habitat_page.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Purchases.hasOldVersion = true;
    Purchases.purchases = {};
  });

  tearDown(() {
    Purchases.hasOldVersion = false;
    Purchases.purchases = {};
    GuideTabs.show = null;
  });

  test('the key keeps the eight v3 places in grid order', () {
    expect(guideHabitatIds, ['4', '1', '7', '8', '3', '9', '5', '10']);
    expect(guideFilterKey(colorId: '1'), '1___');
    expect(guideFilterKey(colorId: '1', habitatId: '4'), '1_4__');
    expect(guideFilterKey(colorId: '1', habitatId: '10'), '1_10__');
    expect(
      guideFilterKey(colorId: '1', habitatId: '1', petalId: '3'),
      '1_1_3_',
    );
    expect(guideFilterKey(colorId: '1', petalId: '3'), '1__3_');
  });

  test('habitat drawings follow the mockup paths', () {
    final wave = parseGuidePath(
      'M4 30c4-3 8 3 12 0s8 3 12 0 8 3 12 0',
    );
    final end = _end(wave);
    expect(end.dx, closeTo(40, 0.01));
    expect(end.dy, closeTo(30, 0.01));

    final step = parseGuidePath('M0 0l-6-10');
    expect(_end(step), const Offset(-6, -10));

    final tree = parseGuidePath('M14 6 6 20h5l-6 10h18l-6-10h5z');
    expect(tree.getBounds().width, greaterThan(10));
    expect(tree.getBounds().height, greaterThan(10));
  });

  testWidgets('draws a glyph for every place', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final id in guideHabitatIds) GuideHabitatGlyph(id: id),
          ],
        ),
      ),
    );
    expect(find.byType(GuideHabitatGlyph), findsNWidgets(8));
  });

  testWidgets('shows the eight places and the flowers still in the color',
      (tester) async {
    String? picked = 'unset';
    await _pump(
      tester,
      _page(
        onContinue: (id) => picked = id ?? 'skipped',
      ),
    );

    expect(find.text('KEY IT OUT · 2 OF 3'), findsOneWidget);
    expect(find.text('Where is it growing?'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('woods, edges, clearings'), findsOneWidget);
    expect(find.text('Meadow'), findsOneWidget);
    expect(find.text('pastures, hay meadows, lawns'), findsOneWidget);
    expect(find.text('Dry and sunny'), findsOneWidget);
    expect(find.text('Fields and roadsides'), findsOneWidget);
    expect(find.text('Water and wetland'), findsOneWidget);
    expect(find.text('Heath and bog'), findsOneWidget);
    expect(find.text('Rocks and mountains'), findsOneWidget);
    expect(find.text('cliffs, scree, walls, alpine'), findsOneWidget);
    expect(find.text('Coast'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(
      find.text('In a garden, or not sure? Show all 100 white plants'),
      findsOneWidget,
    );

    await tester.tap(find.text('Forest'));
    await tester.pump();
    expect(picked, '4');

    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pump();
    await tester.tap(
      find.text('In a garden, or not sure? Show all 100 white plants'),
    );
    await tester.pump();
    expect(picked, 'skipped');
  });

  testWidgets('a place with no flowers stays on this step', (tester) async {
    String? picked = 'unset';
    await _pump(
      tester,
      _page(
        counts: _counts(coast: 0),
        onContinue: (id) => picked = id ?? 'skipped',
      ),
    );

    await tester.ensureVisible(find.text('Coast'));
    await tester.tap(find.text('Coast'));
    await tester.pump();
    expect(
        find.text('There are no flowers matching criteria.'), findsOneWidget);
    expect(picked, 'unset');
  });

  testWidgets('waits for the counts before continuing', (tester) async {
    var picked = false;
    final pending = Completer<GuideHabitatCounts>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(_counts());
    });
    await _pump(
      tester,
      _page(
        counts: null,
        loadCounts: (_) => pending.future,
        onContinue: (_) => picked = true,
      ),
    );

    await tester.tap(find.text('Meadow'));
    await tester.pump();
    expect(picked, isFalse);
    expect(
      find.text('In a garden, or not sure? Show all white plants'),
      findsOneWidget,
    );
  });

  testWidgets('color and back return to the color step', (tester) async {
    await _pump(tester, _open());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    expect(find.text('Where is it growing?'), findsNothing);
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();
    expect(find.text('Where is it growing?'), findsNothing);
  });

  testWidgets('pins the banner above the Find tabs', (tester) async {
    var tab = -1;
    GuideTabs.show = (index) => tab = index;
    await _pump(tester, _named());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
    expect(find.byType(AppBannerAd), findsOneWidget);

    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(tab, 1);
    expect(find.text('Where is it growing?'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

GuideHabitatCounts _counts({int coast = 88}) {
  return GuideHabitatCounts(
    total: 100,
    byHabitat: {
      '4': 11,
      '1': 22,
      '7': 33,
      '8': 44,
      '3': 55,
      '9': 66,
      '5': 77,
      '10': coast,
    },
  );
}

Offset _end(Path path) {
  final metric = path.computeMetrics().last;
  return metric.getTangentForOffset(metric.length)!.position;
}

Widget _page({
  GuideHabitatCounts? counts = const GuideHabitatCounts(
    total: 100,
    byHabitat: {
      '4': 11,
      '1': 22,
      '7': 33,
      '8': 44,
      '3': 55,
      '9': 66,
      '5': 77,
      '10': 88,
    },
  ),
  Future<GuideHabitatCounts> Function(String colorId)? loadCounts,
  required void Function(String? habitatId) onContinue,
}) {
  return _app(
    GuideHabitatPage(
      colorId: '1',
      counts: counts,
      loadCounts: loadCounts ?? loadHabitatCounts,
      onContinue: onContinue,
    ),
  );
}

Widget _open() {
  return _named();
}

Widget _named() {
  return _app(
    Builder(
      builder: (context) => TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: guideHabitatRouteName),
              builder: (context) => GuideHabitatPage(
                colorId: '1',
                counts: _counts(),
                onContinue: (_) {},
              ),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
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

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await tester.pump();
}
