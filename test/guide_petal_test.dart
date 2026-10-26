import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/key/petal_glyphs.dart';
import 'package:abherbs_flutter/key/petal_page.dart';
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
  });

  testWidgets('draws the four petal choices', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final id in guidePetalIds) GuidePetalGlyph(id: id),
          ],
        ),
      ),
    );
    expect(find.byType(GuidePetalGlyph), findsNWidgets(4));
  });

  testWidgets('shows the remaining plants for this color and place',
      (tester) async {
    String? picked;
    await _pump(
      tester,
      _page(
        habitatId: '1',
        onContinue: (id) => picked = id,
      ),
    );

    expect(find.text('KEY IT OUT · 3 OF 3'), findsOneWidget);
    expect(find.text('How many petals?'), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
    expect(find.byType(AppBannerAd), findsOneWidget);
    expect(
      find.text(
        'Two-lipped or one-sided flowers are zygomorphic, whatever the count.',
      ),
      findsOneWidget,
    );
    expect(find.text('Habitat'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Meadow'), findsOneWidget);
    expect(find.text('4 or less'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('More than 5'), findsOneWidget);
    expect(find.text('Zygomorphic'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(
      find.text('Not sure? Show all 239 white, meadow plants'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('41')).dy,
      lessThan(tester.getTopLeft(find.text('4 or less')).dy),
    );
    expect(
      tester.getTopRight(find.text('41')).dx,
      greaterThan(tester.getTopRight(find.text('4 or less')).dx),
    );
    final glyph = tester.getCenter(find.byType(GuidePetalGlyph).first);
    final tile = tester.getRect(
      find
          .ancestor(
            of: find.byType(GuidePetalGlyph).first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(glyph.dx, closeTo(tile.center.dx, 1));

    await tester.tap(find.text('More than 5'));
    await tester.pump();
    expect(picked, '3');
  });

  testWidgets('a skipped place keeps only the color', (tester) async {
    await _pump(tester, _page(habitatId: null));
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Meadow'), findsNothing);
    expect(find.text('141'), findsOneWidget);
    expect(
      find.text('Not sure? Show all 416 white plants'),
      findsOneWidget,
    );
  });

  testWidgets('not sure lists every plant in this color and place',
      (tester) async {
    String? picked = 'unset';
    await _pump(
      tester,
      _page(onContinue: (id) => picked = id),
    );

    await tester.ensureVisible(
      find.text('Not sure? Show all 239 white, meadow plants'),
    );
    await tester.tap(find.text('Not sure? Show all 239 white, meadow plants'));
    await tester.pump();
    expect(picked, isNull);
  });

  testWidgets('an empty filter stays on the petal step', (tester) async {
    String? picked = 'unset';
    await _pump(
      tester,
      _page(
        counts: const {'1': 0, '2': 0, '3': 0, '4': 0},
        onContinue: (id) => picked = id,
      ),
    );

    await tester.ensureVisible(
      find.text('Not sure? Show all 0 white, meadow plants'),
    );
    await tester.tap(find.text('Not sure? Show all 0 white, meadow plants'));
    await tester.pump();
    expect(
      find.text('There are no flowers matching criteria.'),
      findsOneWidget,
    );
    expect(picked, 'unset');
  });

  testWidgets('waits for the counts before skipping petals', (tester) async {
    var picked = false;
    final pending = Completer<Map<String, int>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(_withPlace);
    });
    await _pump(
      tester,
      _page(
        counts: null,
        loadCounts: (_, __) => pending.future,
        onContinue: (_) => picked = true,
      ),
    );

    await tester.ensureVisible(
      find.text('Not sure? Show all white, meadow plants'),
    );
    await tester.tap(find.text('Not sure? Show all white, meadow plants'));
    await tester.pump();
    expect(picked, isFalse);
  });

  testWidgets('an empty petal choice stays here', (tester) async {
    String? picked;
    await _pump(
      tester,
      _page(
        counts: const {'1': 0, '2': 9, '3': 4, '4': 1},
        onContinue: (id) => picked = id,
      ),
    );
    await tester.tap(find.text('4 or less'));
    await tester.pump();
    expect(
        find.text('There are no flowers matching criteria.'), findsOneWidget);
    expect(picked, isNull);
  });

  testWidgets('the color returns to Find and the place returns here',
      (tester) async {
    await _pump(tester, _stack());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to petals'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meadow'));
    await tester.pumpAndSettle();
    expect(find.text('How many petals?'), findsNothing);
    expect(find.text('to petals'), findsOneWidget);

    await tester.tap(find.text('to petals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();
    expect(find.text('to petals'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

const _withPlace = {'1': 41, '2': 89, '3': 50, '4': 59};
const _skipped = {'1': 125, '2': 80, '3': 141, '4': 70};

Widget _page({
  String? habitatId = '1',
  Map<String, int>? counts,
  Future<Map<String, int>> Function(String colorId, String? habitatId)?
      loadCounts,
  void Function(String? petalId)? onContinue,
}) {
  return _app(
    GuidePetalPage(
      colorId: '1',
      habitatId: habitatId,
      counts: counts ??
          (loadCounts == null
              ? (habitatId == null ? _skipped : _withPlace)
              : null),
      loadCounts: loadCounts ?? ((_, __) async => _withPlace),
      onContinue: onContinue,
    ),
  );
}

Widget _stack() {
  return _app(
    Builder(
      builder: (context) => TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: guideHabitatRouteName),
              builder: (habitatContext) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.push(
                      habitatContext,
                      MaterialPageRoute<void>(
                        settings:
                            const RouteSettings(name: guidePetalRouteName),
                        builder: (context) => GuidePetalPage(
                          colorId: '1',
                          habitatId: '1',
                          counts: _withPlace,
                        ),
                      ),
                    );
                  },
                  child: const Text('to petals'),
                ),
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
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await tester.pump();
}
