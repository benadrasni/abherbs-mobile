import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/key/results_page.dart';
import 'package:abherbs_flutter/shell/app_banner_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stored vernacular replaces the Latin name on a key result', () {
    final plant = GuideKeyPlant(
      id: '9',
      name: 'Cuscuta gronovii',
      colors: const {'1'},
      habitats: const {'1'},
      petals: const {'2'},
      regions: const {'77'},
      photoPath: 'photos/Cuscuta_gronovii/a.webp',
      floweringFrom: 6,
      floweringTo: 9,
      cultivated: false,
    );
    final labeled = plant.toResult(
      label: guideResultLabel(
        plant.name,
        stored: const {'Cuscuta gronovii': 'common dodder'},
      ),
    );
    expect(labeled.shownName, 'common dodder');

    final cached = plant.toResult(
      label: guideResultLabel(
        plant.name,
        stored: const {},
        cached: 'common dodder',
      ),
    );
    expect(cached.shownName, 'common dodder');

    final latin = plant.toResult(
      label: guideResultLabel(plant.name, stored: const {}),
    );
    expect(latin.shownName, 'Cuscuta gronovii');
  });

  test('orders plants in flower first, then by name', () {
    final list = arrangeGuideResults(
      [
        _plant('1', 'Bellis perennis', label: 'Daisy', from: 3, to: 10),
        _plant('2', 'Achillea millefolium', label: 'Yarrow', from: 6, to: 9),
        _plant('3', 'Galanthus nivalis', label: 'Snowdrop', from: 1, to: 3),
        _plant('4', 'Rosa canina', label: 'Églantine', from: 5, to: 7),
        _plant('5', 'Tulipa gesneriana',
            label: 'Tulip', from: 4, to: 5, cultivated: true),
      ],
      month: 7,
      wildOnly: false,
    );

    expect(list.inFlowerCount, 3);
    expect(
      list.plants.map((plant) => plant.shownName).toList(),
      ['Daisy', 'Églantine', 'Yarrow', 'Snowdrop', 'Tulip'],
    );
  });

  test('a genus counts species in flower and species already seen', () {
    final blooms = readGuideHeaderBlooms({
      '69': {
        'name': 'Bellis perennis',
        'floweringFrom': 3,
        'floweringTo': 10,
      },
      '70': {
        'name': 'Bellis sylvestris',
        'floweringFrom': 1,
        'floweringTo': 3,
      },
      '71': 'skip',
    });
    expect(blooms['69']?.name, 'Bellis perennis');
    expect(blooms.containsKey('71'), isFalse);

    final note = countGuideGenusNote(
      plantIds: ['69', '70', '71'],
      blooms: blooms,
      seen: {'Bellis perennis'},
      month: 10,
    );
    expect(note.inFlower, 1);
    expect(note.seen, 1);
    expect(note.isEmpty, isFalse);

    final quiet = countGuideGenusNote(
      plantIds: ['70'],
      blooms: blooms,
      seen: {},
      month: 10,
    );
    expect(quiet.isEmpty, isTrue);
  });

  test('headers answer the key when the count index is missing', () {
    final plants = readGuideKeyPlants({
      '2': {
        'name': 'Rudbeckia hirta',
        'url': 'Asterales/Asteraceae/Rudbeckia_hirta/rh1.webp',
        'filterColor': [2],
        'filterHabitat': {'0': 1, '1': 8},
        'filterPetal': [3],
        'filterDistribution': [75, 84],
        'floweringFrom': 5,
        'floweringTo': 9,
      },
      '10': {
        'name': 'Lupinus texensis',
        'filterColor': [4, 2],
        'filterHabitat': [1],
        'filterPetal': [2],
        'filterDistribution': [84],
        'floweringFrom': 3,
        'floweringTo': 5,
      },
      '11': {
        'name': 'Tulipa gesneriana',
        'filterColor': [3],
        'filterPetal': [1],
        'cultivated': true,
        'floweringFrom': 4,
        'floweringTo': 5,
      },
      '12': 'skip',
    });

    expect(plants.map((plant) => plant.name), [
      'Rudbeckia hirta',
      'Lupinus texensis',
      'Tulipa gesneriana',
    ]);
    expect(
      plants.first.photoPath,
      'photos/Asterales/Asteraceae/Rudbeckia_hirta/rh1.webp',
    );
    expect(guideKeyCount(plants, colorId: '2'), 2);
    expect(guideKeyCount(plants, colorId: '2', habitatId: '1'), 2);
    expect(guideKeyCount(plants, colorId: '2', habitatId: '8'), 1);
    expect(guideKeyCount(plants, colorId: '2', habitatId: '4'), 0);
    expect(guideKeyCount(plants, colorId: '3'), 1);
    expect(guideKeyCount(plants, colorId: '3', habitatId: '1'), 0);
    expect(
      guideKeyCount(plants, colorId: '2', habitatId: '1', petalId: '2'),
      1,
    );
    expect(
      guideKeyMatches(
        plants,
        colorId: '2',
        habitatId: '1',
        petalId: '3',
        regionId: '84',
      ).map((plant) => plant.id),
      ['2'],
    );
    expect(
      guideKeyMatches(plants, colorId: '4', regionId: '84')
          .map((plant) => plant.name),
      ['Lupinus texensis'],
    );
  });

  test('wild only hides cultivated plants', () {
    final list = arrangeGuideResults(
      [
        _plant('1', 'Bellis perennis', label: 'Daisy', from: 3, to: 10),
        _plant('2', 'Tulipa gesneriana',
            label: 'Tulip', from: 4, to: 5, cultivated: true),
      ],
      month: 7,
      wildOnly: true,
    );
    expect(list.plants.map((plant) => plant.name), ['Bellis perennis']);
  });

  test('a season that wraps the year is in flower', () {
    expect(guideInFlower(11, 2, 1), isTrue);
    expect(guideInFlower(11, 2, 12), isTrue);
    expect(guideInFlower(11, 2, 6), isFalse);
    expect(guideInFlower(0, 5, 3), isFalse);
  });

  test('the banner follows the sixth plant', () {
    final plants = [
      for (var i = 0; i < 7; i++) _plant('$i', 'Plant $i', from: 1, to: 12),
    ];
    final slots = guideResultSlots(
      arrangeGuideResults(plants, month: 7, wildOnly: false),
      showAd: true,
    );
    expect(slots[0], isA<GuideMonthSlot>());
    expect(slots[7], isA<GuideAdSlot>());
    expect((slots[8] as GuidePlantSlot).plant.name, 'Plant 6');
    expect(slots.whereType<GuideAdSlot>(), hasLength(1));
    expect(
      guideResultSlots(
        arrangeGuideResults(plants, month: 7, wildOnly: false),
        showAd: false,
      ).whereType<GuideAdSlot>(),
      isEmpty,
    );
  });

  test('a four-column grid puts the banner after the third row', () {
    final plants = [
      for (var i = 0; i < 16; i++)
        _plant('$i', 'Plant ${i.toString().padLeft(2, '0')}', from: 1, to: 12),
    ];
    final slots = guideResultSlots(
      arrangeGuideResults(plants, month: 7, wildOnly: false),
      showAd: true,
      columns: 4,
    );
    expect(slots[0], isA<GuideMonthSlot>());
    expect(slots[13], isA<GuideAdSlot>());
    expect((slots[14] as GuidePlantSlot).plant.name, 'Plant 12');
    expect(slots.whereType<GuideAdSlot>(), hasLength(1));
  });

  test('a short in-flower row counts toward the banner', () {
    final plants = [
      for (var i = 0; i < 6; i++) _plant('n$i', 'Now $i', from: 10, to: 10),
      for (var i = 0; i < 8; i++) _plant('l$i', 'Later $i', from: 4, to: 5),
    ];
    final slots = guideResultSlots(
      arrangeGuideResults(plants, month: 10, wildOnly: false),
      showAd: true,
      columns: 4,
    );
    expect(slots[7], isA<GuideMonthSlot>());
    expect((slots[7] as GuideMonthSlot).inFlower, isFalse);
    expect(slots[12], isA<GuideAdSlot>());
    expect((slots[11] as GuidePlantSlot).plant.name, 'Later 3');
    expect(slots.whereType<GuideAdSlot>(), hasLength(1));
  });

  test('a list shorter than three rows keeps the banner at the end', () {
    final plants = [
      for (var i = 0; i < 8; i++) _plant('n$i', 'Now $i', from: 10, to: 10),
      for (var i = 0; i < 2; i++) _plant('l$i', 'Later $i', from: 4, to: 5),
    ];
    final slots = guideResultSlots(
      arrangeGuideResults(plants, month: 10, wildOnly: false),
      showAd: true,
      columns: 4,
    );
    expect(slots.whereType<GuideAdSlot>(), hasLength(1));
    expect(slots.last, isA<GuideAdSlot>());
    expect((slots[slots.length - 2] as GuidePlantSlot).plant.name, 'Later 1');
  });

  test('an empty flowering month still carries the view switch', () {
    final slots = guideResultSlots(
      arrangeGuideResults(
        [_plant('1', 'Galanthus nivalis', from: 1, to: 2)],
        month: 7,
        wildOnly: false,
      ),
      showAd: true,
    );
    expect(slots, hasLength(3));
    expect(slots.last, isA<GuideAdSlot>());
    final month = slots.first as GuideMonthSlot;
    expect(month.inFlower, isTrue);
    expect(month.count, 0);
    expect(month.controls, isTrue);
    expect(slots.whereType<GuideMonthSlot>(), hasLength(1));
  });

  test('the filter key keeps an empty region slot', () {
    expect(
      guideFilterKey(colorId: '1', habitatId: '1', petalId: '3'),
      '1_1_3_',
    );
    expect(
      guideFilterKey(
        colorId: '1',
        habitatId: '1',
        petalId: '3',
        regionId: '11',
      ),
      '1_1_3_11',
    );
  });

  test('a place maps to one floristic region', () {
    expect(
      guideRegionForPlace(
        countryCode: 'US',
        adminArea: 'California',
        latitude: 37.77,
        longitude: -122.42,
      ),
      '76',
    );
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'CA'), '76');
    expect(
      guideRegionForPlace(countryCode: 'US', adminArea: 'Washington'),
      '73',
    );
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Colorado'), '73');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Illinois'), '74');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'New York'), '75');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Texas'), '77');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Georgia'), '78');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Alaska'), '70');
    expect(guideRegionForPlace(countryCode: 'US', adminArea: 'Hawaii'), '63');
    expect(guideRegionForPlace(countryCode: 'US'), isNull);
    expect(
      guideRegionForPlace(countryCode: 'CA', adminArea: 'Ontario'),
      '72',
    );
    expect(
      guideRegionForPlace(countryCode: 'CA', adminArea: 'British Columbia'),
      '71',
    );
    expect(guideRegionForPlace(countryCode: 'CA', adminArea: 'Yukon'), '70');
    expect(guideRegionForPlace(countryCode: 'CA', adminArea: 'Québec'), '72');
    expect(guideRegionForPlace(countryCode: 'CA'), isNull);
    expect(guideRegionForPlace(countryCode: 'DE'), '11');
    expect(guideRegionForPlace(countryCode: 'UK'), '10');
    expect(
      guideRegionForPlace(countryCode: 'RU', latitude: 55.7, longitude: 37.6),
      '14',
    );
    expect(
      guideRegionForPlace(countryCode: 'RU', latitude: 55, longitude: 82.9),
      '30',
    );
    expect(
      guideRegionForPlace(countryCode: 'RU', latitude: 62, longitude: 129.7),
      '30',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'RU',
        latitude: 43.1,
        longitude: 131.9,
      ),
      '31',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'RU',
        latitude: 59.6,
        longitude: 150.8,
      ),
      '31',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'RU',
        latitude: 56.8,
        longitude: 60.6,
      ),
      '30',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'RU',
        latitude: 54.7,
        longitude: 20.5,
      ),
      '14',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'RU',
        latitude: 43.6,
        longitude: 39.7,
      ),
      '33',
    );
    expect(guideRegionForPlace(countryCode: 'RU'), isNull);
    expect(
      guideRegionForPlace(
        countryCode: 'UA',
        latitude: 45.3,
        longitude: 34.1,
      ),
      '14',
    );
    expect(
      guideRegionForPlace(countryCode: 'TR', latitude: 41, longitude: 28.9),
      '13',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'TR',
        latitude: 39.9,
        longitude: 32.8,
      ),
      '34',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'ES',
        latitude: 28.1,
        longitude: -15.4,
      ),
      '21',
    );
    expect(
      guideRegionForPlace(countryCode: 'ES', latitude: 40.4, longitude: -3.7),
      '12',
    );
    expect(guideRegionForPlace(countryCode: 'ES'), '12');
    expect(
      guideRegionForPlace(
        countryCode: 'PT',
        latitude: 37.7,
        longitude: -25.7,
      ),
      '21',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'PT',
        latitude: 32.65,
        longitude: -16.9,
      ),
      '21',
    );
    expect(
      guideRegionForPlace(countryCode: 'PT', latitude: 38.7, longitude: -9.1),
      '12',
    );
    expect(
      guideRegionForPlace(countryCode: 'EG', latitude: 27.9, longitude: 34.3),
      '34',
    );
    expect(
      guideRegionForPlace(countryCode: 'EG', latitude: 30, longitude: 31.2),
      '20',
    );
    expect(
      guideRegionForPlace(countryCode: 'IN', latitude: 11.6, longitude: 92.7),
      '41',
    );
    expect(
      guideRegionForPlace(
        countryCode: 'ID',
        latitude: -2.5,
        longitude: 140.7,
      ),
      '43',
    );
  });

  testWidgets('lists this month first and keeps the trail', (tester) async {
    String? opened;
    var photo = false;
    await _pump(
      tester,
      _page(
        plants: _sample,
        seen: const {'Bellis perennis'},
        onOpenPlant: (_, name) => opened = name,
        onTryPhoto: (_) async => photo = true,
      ),
    );

    expect(find.text('Petals'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Meadow'), findsOneWidget);
    expect(find.text('More than 5 petals'), findsOneWidget);
    expect(
      find.text('4 plants · you’ve seen 1', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('IN FLOWER NOW · 2'), findsOneWidget);
    expect(find.text('OTHER MONTHS · 2'), findsOneWidget);
    expect(find.text('Daisy'), findsOneWidget);
    expect(find.text('Yarrow'), findsOneWidget);
    expect(find.text('Snowdrop'), findsOneWidget);
    expect(find.text('Tulip'), findsOneWidget);
    expect(find.text('✓ Seen'), findsOneWidget);
    expect(find.text('Any region'), findsOneWidget);
    expect(find.text('Wild and garden'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Daisy')).dy,
      lessThan(tester.getTopLeft(find.text('Snowdrop')).dy),
    );

    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio,
      1,
    );
    await tester.tap(find.text('Plates'));
    await tester.pump();
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio,
      closeTo(2 / 3, 0.01),
    );

    await tester.tap(find.text('Daisy'));
    expect(opened, 'Bellis perennis');

    await tester.tap(find.text('Try a photo'));
    expect(photo, isTrue);

    await tester.tap(find.text('Wild and garden'));
    await tester.pump();
    expect(find.text('Wild only'), findsOneWidget);
    expect(find.text('Tulip'), findsNothing);
    expect(
      find.text('3 plants · you’ve seen 1', findRichText: true),
      findsOneWidget,
    );
  });

  test('reads the Latin name from a family or genus path', () {
    expect(
      guideListLatin('APG IV_v3/Eukaryota/Plantae/Asteraceae/list'),
      'Asteraceae',
    );
    expect(guideListLatin('/Bellis/list'), 'Bellis');
    expect(guideListLatin(''), '');
  });

  testWidgets('landscape tablet puts four results on a row', (tester) async {
    final plants = [
      for (var i = 0; i < 4; i++)
        _plant('$i', 'Species $i', label: 'Flower $i', from: 6, to: 8),
    ];

    Future<void> expectColumns(Size size, int across) async {
      await _pump(tester, _page(plants: plants), size: size);
      final first = tester.getTopLeft(find.text('Flower 0'));
      final lastInRow = tester.getTopLeft(find.text('Flower ${across - 1}'));
      expect((first.dy - lastInRow.dy).abs(), lessThan(2));
      expect(lastInRow.dx, greaterThan(first.dx + 80));
      if (across >= 4) return;
      final wrapped = tester.getTopLeft(find.text('Flower $across'));
      expect(wrapped.dy, greaterThan(first.dy + 40));
      expect((wrapped.dx - first.dx).abs(), lessThan(2));
    }

    await expectColumns(const Size(951, 669), 4);
    await expectColumns(const Size(1194, 834), 4);
    await expectColumns(const Size(669, 951), 3);
    await expectColumns(const Size(390, 1600), 2);
  });

  testWidgets('a family list uses the result grid without the key chips',
      (tester) async {
    await _pump(
      tester,
      _app(
        GuideResultsPage(
          colorId: '',
          habitatId: null,
          petalId: '',
          listTitle: 'Daisy family',
          listBackLabel: 'Book',
          listLatin: 'Asteraceae',
          initialPlants: _sample,
          initialPrefs: const GuideResultPrefs(),
          initialSeen: const {'Bellis perennis'},
          loadResults: (_) async => _sample,
          loadPrefs: () async => const GuideResultPrefs(),
          savePrefs: (_) async {},
          loadSeen: () async => const {},
          loadRegionCounts: () async => const {},
          locate: () async => null,
          onOpenPlant: (_, __) {},
          onTryPhoto: (_) async {},
        ),
      ),
    );

    expect(find.text('Daisy family'), findsOneWidget);
    expect(find.text('Asteraceae'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Daisy'), findsOneWidget);
    expect(find.text('✓ Seen'), findsWidgets);
    expect(find.text('Any region'), findsNothing);
    expect(find.text('Wild and garden'), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.byType(AppBannerAd), findsNothing);
    expect(
      tester.getTopLeft(find.text('Daisy')).dy,
      lessThan(tester.getTopLeft(find.text('Snowdrop')).dy),
    );
  });

  testWidgets('a long family list stays free of the result banner',
      (tester) async {
    final plants = [
      for (var i = 0; i < 7; i++)
        _plant('$i', 'Species $i', label: 'Flower $i', from: 6, to: 8),
    ];
    await _pump(
      tester,
      _app(
        GuideResultsPage(
          colorId: '',
          habitatId: null,
          petalId: '',
          listTitle: 'Daisy family',
          listBackLabel: 'Book',
          showAd: true,
          adBuilder: (_) => const Text('banner'),
          initialPlants: plants,
          initialPrefs: const GuideResultPrefs(),
          loadResults: (_) async => plants,
          loadPrefs: () async => const GuideResultPrefs(),
          savePrefs: (_) async {},
          loadSeen: () async => const {},
          loadRegionCounts: () async => const {},
          locate: () async => null,
          onOpenPlant: (_, __) {},
          onTryPhoto: (_) async {},
        ),
      ),
    );
    expect(find.text('Flower 0'), findsOneWidget);
    expect(find.text('banner'), findsNothing);
  });

  testWidgets('a region chip reloads that floristic list', (tester) async {
    String? asked;
    final regions = <String?, List<GuideResultPlant>>{
      null: _sample,
      '11': [_sample.first],
    };
    await _pump(
      tester,
      _page(
        plants: _sample,
        counts: const {'': 4, '11': 1},
        loadResults: (regionId) async {
          asked = regionId;
          return regions[regionId] ?? const [];
        },
      ),
    );

    await tester.tap(find.text('Any region'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you looking?'), findsOneWidget);
    expect(
      find.text(
        'Narrows 4 plants to those native or naturalized there.',
      ),
      findsOneWidget,
    );
    expect(find.text('Middle Europe'), findsOneWidget);

    await tester.tap(find.text('All regions…'));
    await tester.pumpAndSettle();
    expect(find.text('EUROPE'), findsOneWidget);
    expect(find.text('Northern Africa'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ANTARCTIC'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('ANTARCTIC'), findsOneWidget);
    expect(find.text('Antarctic Continent'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Middle Europe'),
      -400,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('Middle Europe'));
    await tester.pumpAndSettle();
    expect(asked, '11');
    expect(find.text('Where are you looking?'), findsNothing);
    expect(find.text('Middle Europe'), findsOneWidget);
    expect(find.text('Daisy'), findsOneWidget);
    expect(find.text('Yarrow'), findsNothing);
    expect(
      find.text('1 plant in Middle Europe', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('phone location sets the region', (tester) async {
    String? asked;
    await _pump(
      tester,
      _page(
        plants: _sample,
        locate: () async => '11',
        loadResults: (regionId) async {
          asked = regionId;
          return regionId == '11' ? [_sample.first] : _sample;
        },
      ),
    );

    await tester.tap(find.text('Any region'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this phone’s location'));
    await tester.pumpAndSettle();
    expect(asked, '11');
    expect(find.text('Middle Europe'), findsOneWidget);
    expect(find.byIcon(Icons.place), findsOneWidget);
  });

  testWidgets('a refused location stays on the sheet and opens Settings',
      (tester) async {
    var settings = 0;
    await _pump(
      tester,
      _page(
        plants: _sample,
        locate: () async => throw const GuideLocationRefused(),
        openLocationSettings: () async => settings++,
      ),
    );
    await tester.tap(find.text('Any region'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this phone’s location'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you looking?'), findsOneWidget);
    expect(
      find.text('Location was refused. Change it in Settings.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use this phone’s location'));
    await tester.pumpAndSettle();
    expect(settings, 1);
  });

  testWidgets('an unknown place leaves the region sheet open', (tester) async {
    await _pump(tester, _page(plants: _sample, locate: () async => null));
    await tester.tap(find.text('Any region'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this phone’s location'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you looking?'), findsOneWidget);
    expect(
      find.text('Couldn’t match this place to a floristic region.'),
      findsOneWidget,
    );
    expect(find.text('Any region'), findsNWidgets(2));
  });

  testWidgets('the free-account banner follows the sixth plant',
      (tester) async {
    final plants = [
      for (var i = 0; i < 6; i++)
        _plant('$i', 'Species $i', label: 'Flower $i', from: 6, to: 8),
    ];
    await _pump(
      tester,
      _page(
        plants: plants,
        showAd: true,
        adBuilder: (_) => const Text('banner'),
      ),
    );
    expect(find.text('banner'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Flower 5')).dy,
      lessThan(tester.getTopLeft(find.text('banner')).dy),
    );
  });

  testWidgets('a failed load can be tried again', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      _page(
        plants: null,
        loadResults: (_) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return _sample;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load these plants'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Daisy'), findsOneWidget);
  });

  testWidgets('the trail returns to the earlier steps', (tester) async {
    await _pump(tester, _stack());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to petals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to results'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More than 5 petals'));
    await tester.pumpAndSettle();
    expect(find.text('4 plants', findRichText: true), findsNothing);
    expect(find.text('to results'), findsOneWidget);

    await tester.tap(find.text('to results'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meadow'));
    await tester.pumpAndSettle();
    expect(find.text('to results'), findsNothing);
    expect(find.text('to petals'), findsOneWidget);

    await tester.tap(find.text('to petals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to results'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();
    expect(find.text('to petals'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a skipped petal count leaves that pill off', (tester) async {
    await _pump(tester, _app(_results(petalId: '')));

    expect(find.text('Petals'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Meadow'), findsOneWidget);
    expect(find.text('More than 5 petals'), findsNothing);
    expect(find.text(' petals'), findsNothing);
  });
}

const _sample = [
  GuideResultPlant(
    id: '69',
    name: 'Bellis perennis',
    label: 'Daisy',
    photoPath: null,
    platePath: null,
    floweringFrom: 3,
    floweringTo: 10,
    cultivated: false,
  ),
  GuideResultPlant(
    id: '2',
    name: 'Achillea millefolium',
    label: 'Yarrow',
    photoPath: null,
    platePath: null,
    floweringFrom: 6,
    floweringTo: 9,
    cultivated: false,
  ),
  GuideResultPlant(
    id: '3',
    name: 'Galanthus nivalis',
    label: 'Snowdrop',
    photoPath: null,
    platePath: null,
    floweringFrom: 1,
    floweringTo: 3,
    cultivated: false,
  ),
  GuideResultPlant(
    id: '4',
    name: 'Tulipa gesneriana',
    label: 'Tulip',
    photoPath: null,
    platePath: null,
    floweringFrom: 4,
    floweringTo: 5,
    cultivated: true,
  ),
];

GuideResultPlant _plant(
  String id,
  String name, {
  String? label,
  int from = 1,
  int to = 12,
  bool cultivated = false,
}) {
  return GuideResultPlant(
    id: id,
    name: name,
    label: label,
    photoPath: null,
    platePath: null,
    floweringFrom: from,
    floweringTo: to,
    cultivated: cultivated,
  );
}

Widget _page({
  List<GuideResultPlant>? plants = _sample,
  Set<String> seen = const {},
  Map<String, int> counts = const {'': 4},
  bool showAd = false,
  WidgetBuilder? adBuilder,
  Future<List<GuideResultPlant>> Function(String? regionId)? loadResults,
  Future<String?> Function()? locate,
  Future<void> Function()? openLocationSettings,
  void Function(BuildContext context, String name)? onOpenPlant,
  Future<void> Function(BuildContext context)? onTryPhoto,
}) {
  return _app(
    _results(
      plants: plants,
      seen: seen,
      counts: counts,
      showAd: showAd,
      adBuilder: adBuilder,
      loadResults: loadResults,
      locate: locate,
      openLocationSettings: openLocationSettings,
      onOpenPlant: onOpenPlant,
      onTryPhoto: onTryPhoto,
    ),
  );
}

Widget _results({
  List<GuideResultPlant>? plants = _sample,
  Set<String> seen = const {},
  Map<String, int> counts = const {'': 4},
  String petalId = '3',
  bool showAd = false,
  WidgetBuilder? adBuilder,
  Future<List<GuideResultPlant>> Function(String? regionId)? loadResults,
  Future<String?> Function()? locate,
  Future<void> Function()? openLocationSettings,
  void Function(BuildContext context, String name)? onOpenPlant,
  Future<void> Function(BuildContext context)? onTryPhoto,
}) {
  return GuideResultsPage(
    colorId: '1',
    habitatId: '1',
    petalId: petalId,
    month: 7,
    showAd: showAd,
    adBuilder: adBuilder,
    initialPlants: plants,
    initialPrefs: plants == null ? null : const GuideResultPrefs(),
    initialSeen: seen,
    initialRegionCounts: counts,
    loadResults: loadResults ?? (_) async => plants ?? const [],
    loadPrefs: () async => const GuideResultPrefs(),
    savePrefs: (_) async {},
    loadSeen: () async => seen,
    loadRegionCounts: () async => counts,
    locate: locate ?? () async => null,
    openLocationSettings: openLocationSettings ?? () async {},
    onOpenPlant: onOpenPlant ?? (_, __) {},
    onTryPhoto: onTryPhoto ?? (_) async {},
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
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        settings:
                            const RouteSettings(name: guidePetalRouteName),
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  settings: const RouteSettings(
                                    name: guideResultsRouteName,
                                  ),
                                  builder: (context) => _results(),
                                ),
                              );
                            },
                            child: const Text('to results'),
                          ),
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

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(390, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await tester.pump();
}
