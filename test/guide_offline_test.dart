import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/offline/guide_media.dart';
import 'package:abherbs_flutter/offline/guide_offline.dart';
import 'package:abherbs_flutter/offline/offline_page.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const europe = ['10', '11', '12', '13', '14'];

  GuideOfflineCatalog catalog() {
    return const GuideOfflineCatalog([
      {'11'},
      {'11', '75'},
      {'75'},
      {'90'},
    ]);
  }

  test('a stored pack keeps Book available offline', () {
    expect(
      guidePackOnPhone(packs: '', classic: false, done: ''),
      isFalse,
    );
    expect(
      guidePackOnPhone(packs: '77', classic: false, done: ''),
      isTrue,
    );
    expect(
      guidePackOnPhone(packs: '', classic: true, done: ''),
      isTrue,
    );
    expect(
      guidePackOnPhone(packs: '', classic: false, done: '3,6'),
      isTrue,
    );
  });

  test('a plant counts once, and Antarctic is not a pack', () {
    final plants = catalog();
    expect(plants.total, 4);
    expect(guideOfflineMatch(plants, null), 4);
    expect(guideOfflineMatch(plants, {'11'}), 2);
    expect(guideOfflineMatch(plants, {'75'}), 2);
    expect(guideOfflineMatch(plants, {'11', '75'}), 3);
    expect(guideOfflineMatch(plants, {'90'}), 1);
    expect(guideOfflineMatch(plants, guideOfflinePackCodes), 3);
    expect(guideOfflinePackCodes.contains('90'), isFalse);
    expect(guideOfflinePackCodes.contains('91'), isFalse);
    expect(
      guideOfflineGroups.any((group) => group.codes.contains('90')),
      isFalse,
    );
    expect(guideOfflineUnion(null, {'11'}), isNull);
    expect(guideOfflineUnion({'11'}, null), isNull);
    expect(guideOfflineUnion({'11'}, {'75'}), {'11', '75'});
  });

  test('picture sizes round the way the page prints them', () {
    final middle = GuideOfflineSize.of(1105);
    expect(middle.gigabytes, isFalse);
    expect(middle.amount, '730');
    final book = GuideOfflineSize.of(1433);
    expect(book.gigabytes, isFalse);
    expect(book.amount, '950');
    expect(book.barMb, 950);
  });

  test('overlap names the region that holds most of a continent', () {
    const heavy = GuideOfflineCatalog([
      {'11'},
      {'11'},
      {'11'},
      {'11'},
      {'12'},
    ]);
    expect(guideOfflineOverlap(heavy, europe), '11');
    const split = GuideOfflineCatalog([
      {'11'},
      {'11'},
      {'12'},
      {'12'},
    ]);
    expect(guideOfflineOverlap(split, europe), isNull);
  });

  test('choosing while everything is on drops to that group or region', () {
    const pick = GuideOfflinePick();
    final all = pick.toggleEverything();
    expect(all.everything, isTrue);
    final group = all.toggleGroup(europe);
    expect(group.everything, isFalse);
    expect(group.regions, europe.toSet());
    final region = all.toggleRegion('11');
    expect(region.everything, isFalse);
    expect(region.regions, {'11'});
    expect(guideOfflineLabel(null).everything, isTrue);
    expect(guideOfflineLabel({'11'}).regionId, '11');
    expect(guideOfflineLabel(europe.toSet()).groupId, '1');
  });

  test('catalog ids stay numeric when the header node is a map', () {
    final plants = readGuideOfflineCatalog({
      '10': {
        'name': 'Ten',
        'filterDistribution': [10],
      },
      '2': {
        'name': 'Two',
        'filterDistribution': [11],
      },
      'skip': {'name': 'No id'},
    });
    expect(plants.ids, [2, 10]);
    expect(plants.idAt(0), 2);
    expect(plants.plants.first, {'11'});
  });

  test('a region downloads only plants that are not stored yet', () {
    final plan = guideOfflinePlan(
      catalog: catalog(),
      requestCodes: {'11'},
      storedCodes: <String>{},
      done: {0},
    );
    expect(plan.pending, [1]);
    expect(plan.alreadyDone, 1);
    expect(plan.total, 2);

    final overlap = guideOfflinePlan(
      catalog: catalog(),
      requestCodes: {'75'},
      storedCodes: {'11'},
      done: const {},
    );
    expect(overlap.pending, [2]);
    expect(overlap.total, 1);

    final book = guideOfflinePlan(
      catalog: catalog(),
      requestCodes: null,
      storedCodes: {'11'},
      done: const {},
    );
    expect(book.pending, [2, 3]);
    expect(book.total, 2);
  });

  test('a stored pack keeps an explicit region list', () {
    expect(
      guideOfflineStoredFrom('', classic: true).everything,
      isTrue,
    );
    expect(
      guideOfflineStoredFrom('11', classic: true).regions,
      {'11'},
    );
    expect(
      guideOfflineStore(
        const GuideOfflineStored(regions: {'11'}),
        const GuideOfflineRequest(
          everything: false,
          regions: {'75'},
          added: 1,
          title: 'Eastern Canada',
        ),
      ).regions,
      {'11', '75'},
    );
  });

  test('the stamp hash is md5 of the file bytes', () {
    expect(
      guideMediaHash('abc'.codeUnits),
      '900150983cd24fb0d6963f7d28e17f72',
    );
  });

  test('a change list keeps the latest stamp for plants in the pack', () {
    const plate = GuideMediaFile(url: 'a/plate.webp', bytes: 100, hash: 'p0');
    const plateNext =
        GuideMediaFile(url: 'a/plate.webp', bytes: 180, hash: 'p1');
    const photo = GuideMediaFile(url: 'a/ac1.webp', bytes: 50, hash: 'a');
    const addedPhoto = GuideMediaFile(url: 'a/ac2.webp', bytes: 70, hash: 'b');
    const gone = GuideMediaFile(url: 'a/old.webp', bytes: 10, hash: 'z');
    final log = readGuideChangeLog({
      'count': 4,
      'list': {
        '0': {
          'id': 0,
          'kind': 'pictures',
          'stamp': {
            'photos': [photo.toJson(), gone.toJson()],
            'plate': plate.toJson(),
          },
        },
        '1': {
          'id': 0,
          'kind': 'pictures',
          'stamp': {
            'photos': [photo.toJson(), addedPhoto.toJson()],
            'plate': plateNext.toJson(),
          },
        },
        '2': {
          'id': 2,
          'kind': 'added',
          'stamp': {'plate': plate.toJson()},
        },
        '3': {
          'id': 3,
          'kind': 'added',
          'stamp': {'plate': plate.toJson()},
        },
      },
    });
    final update = guideOfflineUpdate(
      log: log,
      mark: 0,
      catalog: catalog(),
      storedCodes: {'11'},
      stamps: {
        0: const GuideMediaStamp(photos: [photo, gone], plate: plate),
      },
    );
    expect(update.plants.map((plant) => plant.id), [0]);
    expect(update.plants.single.download.map((file) => file.url), [
      'a/ac2.webp',
      'a/plate.webp',
    ]);
    expect(update.plants.single.remove, ['a/old.webp']);
    expect(update.plants.single.bytes, 250);
    expect(update.resumeMark, 4);

    final book = guideOfflineUpdate(
      log: log,
      mark: 0,
      catalog: catalog(),
      storedCodes: null,
      stamps: const {},
    );
    expect(book.plants.map((plant) => plant.id), [0, 2, 3]);
    expect(book.plants.first.added, isTrue);
    expect(book.plants.first.bytes, 50 + 70 + 180);
  });

  test('a plant outside the pack is not part of the update', () {
    const plate = GuideMediaFile(url: 'a/plate.webp', bytes: 100, hash: 'p');
    final log = GuideChangeLog(
      count: 2,
      changes: [
        GuideCatalogChange(
          index: 0,
          plantId: 2,
          kind: 'added',
          stamp: const GuideMediaStamp(plate: plate),
        ),
        GuideCatalogChange(
          index: 1,
          plantId: 0,
          kind: 'pictures',
          stamp: const GuideMediaStamp(plate: plate),
        ),
      ],
    );
    final update = guideOfflineUpdate(
      log: log,
      mark: 0,
      catalog: catalog(),
      storedCodes: {'11'},
      stamps: {
        0: const GuideMediaStamp(plate: plate),
      },
    );
    expect(update.hasWork, isFalse);
    expect(update.resumeMark, 2);

    final left = guideOfflineUpdate(
      log: GuideChangeLog(
        count: 1,
        changes: [
          GuideCatalogChange(
            index: 0,
            plantId: 0,
            kind: 'pictures',
            stamp: const GuideMediaStamp(
              plate:
                  GuideMediaFile(url: 'a/plate.webp', bytes: 100, hash: 'new'),
            ),
          ),
        ],
      ),
      mark: 0,
      catalog: catalog(),
      storedCodes: {'75'},
      stamps: {
        0: const GuideMediaStamp(plate: plate),
      },
    );
    expect(left.hasWork, isFalse);
    expect(left.resumeMark, 1);

    final blocked = guideOfflineUpdate(
      log: GuideChangeLog(
        count: 1,
        changes: [
          GuideCatalogChange(
            index: 0,
            plantId: 99,
            kind: 'added',
            stamp: const GuideMediaStamp(plate: plate),
          ),
        ],
      ),
      mark: 0,
      catalog: catalog(),
      storedCodes: {'11'},
      stamps: const {},
    );
    expect(blocked.hasWork, isFalse);
    expect(blocked.resumeMark, 0);
  });

  test('on this phone leaves out plants the update still has to fetch', () {
    final plants = catalog();
    expect(guideOfflinePresent(plants, null, {0}), 3);
    expect(guideOfflinePresent(plants, {'11'}, {0}), 1);
    expect(guideOfflinePresent(plants, {'75'}, {0}), 2);
    expect(guideOfflinePresent(plants, null, const {}), 4);

    const stored = GuideOfflineStored.everything();
    expect(guideOfflineRegionOnPhone(stored, '11', plants, {0}), isFalse);
    expect(guideOfflineRegionOnPhone(stored, '75', plants, {0}), isTrue);
    expect(
      guideOfflineRegionOnPhone(stored, '11', plants, const {}),
      isTrue,
    );

    const overlap = GuideOfflineCatalog([
      {'11', '75'},
      {'11', '75'},
    ]);
    const europeOnly = GuideOfflineStored(regions: {'11'});
    expect(
      guideOfflineRegionOnPhone(europeOnly, '75', overlap, const {}),
      isTrue,
    );
    expect(
      guideOfflineRegionOnPhone(europeOnly, '75', overlap, {0}),
      isFalse,
    );

    const plate = GuideMediaFile(url: 'a/plate.webp', bytes: 100, hash: 'p');
    final picture = GuideOfflineUpdate(
      mark: 0,
      resumeMark: 1,
      plants: [
        GuideMediaJob(
          id: 0,
          added: false,
          stamp: const GuideMediaStamp(plate: plate),
          download: const [plate],
          remove: const [],
        ),
      ],
    );
    expect(guideOfflineMissingIds(picture), isEmpty);
    final fresh = GuideOfflineUpdate(
      mark: 0,
      resumeMark: 1,
      plants: [
        GuideMediaJob(
          id: 0,
          added: true,
          stamp: const GuideMediaStamp(plate: plate),
          download: const [plate],
          remove: const [],
        ),
      ],
    );
    expect(guideOfflineMissingIds(fresh), {0});
  });

  test('update sizes keep a small plate visible', () {
    expect(GuideOfflineBytes.of(0).amount, '0');
    expect(GuideOfflineBytes.of(200000).amount, '0.2');
    expect(GuideOfflineBytes.of(2000000).amount, '2');
    expect(GuideOfflineBytes.of(15000000).amount, '15');
    expect(GuideOfflineBytes.of(1500000000).gigabytes, isTrue);
  });

  test('an update starts on wi-fi and not on mobile data', () async {
    const plate = GuideMediaFile(url: 'a/plate.webp', bytes: 100, hash: 'p1');
    final update = GuideOfflineUpdate(
      mark: 0,
      resumeMark: 1,
      plants: [
        GuideMediaJob(
          id: 0,
          added: false,
          stamp: const GuideMediaStamp(plate: plate),
          download: const [plate],
          remove: const [],
        ),
      ],
    );
    var ran = false;
    final wifi = await startGuideOfflineUpdate(
      update: update,
      onProgress: (_, __) {},
      onFinished: () {},
      onFailed: () {},
      connectivity: () async => [ConnectivityResult.wifi],
      run: () => ran = true,
    );
    expect(wifi, GuideOfflineStart.started);
    expect(ran, isTrue);
    ran = false;
    final mobile = await startGuideOfflineUpdate(
      update: update,
      onProgress: (_, __) {},
      onFinished: () {},
      onFailed: () {},
      connectivity: () async => [ConnectivityResult.mobile],
      run: () => ran = true,
    );
    expect(mobile, GuideOfflineStart.needsWifi);
    expect(ran, isFalse);
  });

  test('the picture list is the unsuffixed plate, photos, and the map', () {
    expect(
      offlinePictureUrls(
        photos: ['a/ac1.webp', 'a/ac2.webp'],
        illustrationUrl: 'a/Acer_campestre.webp',
        headerUrl: 'a/ac1.webp',
      ),
      [
        'a/ac1.webp',
        'a/ac2.webp',
        'a/Acer_campestre.webp',
        'a/Acer_campestre_distribution.webp',
      ],
    );
    final sized = offlinePictureUrls(
      photos: ['a/ac1.webp'],
      illustrationUrl: 'a/Acer_campestre@1600.webp',
      headerUrl: 'a/other.webp',
    );
    expect(sized, isNot(contains('a/Acer_campestre@400.webp')));
    expect(sized, contains('a/Acer_campestre@1600.webp'));
    expect(sized, contains('a/other.webp'));
  });

  test('a region starts a pack for those plants on wi-fi', () async {
    GuideOfflineJobPlan? plan;
    final result = await startGuideOfflineDownload(
      request: const GuideOfflineRequest(
        everything: false,
        regions: {'11'},
        added: 2,
        title: 'Middle Europe',
      ),
      catalog: catalog(),
      stored: const GuideOfflineStored(),
      done: {0},
      onProgress: (_, __) {},
      onFinished: () {},
      onFailed: () {},
      connectivity: () async => [ConnectivityResult.wifi],
      run: (value) => plan = value,
    );
    expect(result, GuideOfflineStart.started);
    expect(plan, isNotNull);
    expect(plan!.codes, {'11'});
    expect(plan!.pending, [1]);
    expect(plan!.alreadyDone, 1);
    expect(plan!.total, 2);
  });

  test('pause drops that download, and the next one is a new job', () {
    final first = Offline.claimDownload();
    expect(Offline.ownsDownload(first), isTrue);
    Offline.pauseDownload();
    expect(Offline.ownsDownload(first), isFalse);
    expect(Offline.downloadPaused, isTrue);
    var plants = 0;
    var finished = 0;
    var failed = 0;
    Offline.downloadPack(
      plantIds: const [1],
      alreadyDone: 0,
      total: 1,
      generation: first,
      onPlant: (_, __) => plants++,
      onFinish: () => finished++,
      onFail: () => failed++,
    );
    expect(plants, 0);
    expect(finished, 0);
    expect(failed, 0);
    final second = Offline.claimDownload();
    expect(second, isNot(first));
    expect(Offline.ownsDownload(first), isFalse);
    expect(Offline.ownsDownload(second), isTrue);
    expect(Offline.downloadPaused, isFalse);
    Offline.pauseDownload();
    Offline.downloadPaused = false;
  });

  test('mobile data does not start a pack', () async {
    var ran = false;
    final result = await startGuideOfflineDownload(
      request: const GuideOfflineRequest(
        everything: false,
        regions: {'11'},
        added: 2,
        title: 'Middle Europe',
      ),
      catalog: catalog(),
      stored: const GuideOfflineStored(),
      done: const {},
      onProgress: (_, __) {},
      onFinished: () {},
      onFailed: () {},
      connectivity: () async => [ConnectivityResult.mobile],
      run: (_) => ran = true,
    );
    expect(result, GuideOfflineStart.needsWifi);
    expect(ran, isFalse);
  });

  testWidgets('the page lists Everything and Europe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(),
      onDownload: (_) async {},
    )));

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Everything'), findsWidgets);
    expect(find.text('Europe'), findsOneWidget);
    expect(find.text('4 plants'), findsOneWidget);
    expect(find.text('2 plants'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a group checkbox downloads that continent', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GuideOfflineRequest? request;
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(),
      onDownload: (value) async => request = value,
    )));

    await tester.tap(find.byKey(guideOfflineGroupKey('1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(guideOfflineDownloadKey));
    await tester.tap(find.byKey(guideOfflineDownloadKey));
    await tester.pump();

    expect(request, isNotNull);
    expect(request!.everything, isFalse);
    expect(request!.regions, europe.toSet());
    expect(request!.added, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without Field Guide the button opens Field Guide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    GuideOfflineRequest? request;
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(canDownload: false),
      onFieldGuide: () async => opened++,
      onDownload: (value) async => request = value,
    )));

    await tester.tap(find.byKey(guideOfflineEverythingKey));
    await tester.pump();
    await tester.ensureVisible(find.byKey(guideOfflineDownloadKey));
    expect(
      find.descendant(
        of: find.byKey(guideOfflineDownloadKey),
        matching: find.text('Field Guide'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(guideOfflineDownloadKey));
    await tester.pump();
    expect(opened, 1);
    expect(request, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buying Field Guide on this screen unlocks Download',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() {
      Purchases.purchases.clear();
      Purchases.clearAccountProducts();
    });
    Purchases.purchases.clear();
    Purchases.clearAccountProducts();
    GuideOfflineRequest? request;
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(canDownload: false),
      onFieldGuide: () async {
        Purchases.replaceAccountProducts({fieldGuideYearly});
      },
      onDownload: (value) async => request = value,
    )));

    await tester.tap(find.byKey(guideOfflineEverythingKey));
    await tester.pump();
    await tester.ensureVisible(find.byKey(guideOfflineDownloadKey));
    await tester.tap(find.byKey(guideOfflineDownloadKey));
    await tester.pump();

    expect(request, isNull);
    expect(
      find.descendant(
        of: find.byKey(guideOfflineDownloadKey),
        matching: find.text('Download'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a running job shows pause and hides Download', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var paused = 0;
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(),
      job: const GuideOfflineJob(
        title: 'Europe',
        plants: 2,
        doneMb: 12,
        totalMb: 40,
      ),
      onPause: () async => paused++,
    )));

    expect(find.text('Downloading Europe'), findsOneWidget);
    expect(find.text('12 MB of about 40 MB · 2 plants'), findsOneWidget);
    expect(find.byKey(guideOfflineDownloadKey), findsNothing);
    await tester.tap(find.byKey(guideOfflinePauseKey));
    await tester.pump();
    expect(paused, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone region is offered when it is not stored yet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GuideOfflineRequest? request;
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(phoneRegionId: '11'),
      onDownload: (value) async => request = value,
    )));

    expect(find.text('WHERE THIS PHONE IS'), findsOneWidget);
    expect(find.byKey(guideOfflinePhoneKey), findsOneWidget);
    await tester.tap(find.byKey(guideOfflinePhoneKey));
    await tester.pump();
    await tester.ensureVisible(find.byKey(guideOfflineDownloadKey));
    await tester.tap(find.byKey(guideOfflineDownloadKey));
    await tester.pump();

    expect(request, isNotNull);
    expect(request!.everything, isFalse);
    expect(request!.regions, {'11'});
    expect(request!.added, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing plant is not the whole book on this phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const plate =
        GuideMediaFile(url: 'a/plate.webp', bytes: 2000000, hash: 'p');
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(
        stored: const GuideOfflineStored.everything(),
        update: GuideOfflineUpdate(
          mark: 0,
          resumeMark: 1,
          plants: [
            GuideMediaJob(
              id: 0,
              added: true,
              stamp: const GuideMediaStamp(plate: plate),
              download: const [plate],
              remove: const [],
            ),
          ],
        ),
      ),
    )));

    expect(find.text('Everything · 3 plants · about 0 MB'), findsOneWidget);
    expect(find.text('4 plants'), findsNothing);
    expect(find.text('On this phone'), findsOneWidget);
    await tester.tap(find.byKey(guideOfflineEverythingKey));
    await tester.pump();
    expect(find.text('Already on this phone'), findsNothing);
    expect(find.text('1 plant · about 2 MB'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picture change still counts the plant as on this phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const plate =
        GuideMediaFile(url: 'a/plate.webp', bytes: 2000000, hash: 'p');
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(
        stored: const GuideOfflineStored.everything(),
        update: GuideOfflineUpdate(
          mark: 0,
          resumeMark: 1,
          plants: [
            GuideMediaJob(
              id: 0,
              added: false,
              stamp: const GuideMediaStamp(plate: plate),
              download: const [plate],
              remove: const [],
            ),
          ],
        ),
      ),
    )));

    expect(find.text('Everything · 4 plants · about 0 MB'), findsOneWidget);
    expect(find.text('On this phone'), findsNWidgets(2));
    expect(find.text('1 plant · about 2 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a region with a missing plant does not say it is on this phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const plate =
        GuideMediaFile(url: 'a/plate.webp', bytes: 2000000, hash: 'p');
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(
        stored: const GuideOfflineStored(regions: {'11'}),
        update: GuideOfflineUpdate(
          mark: 0,
          resumeMark: 1,
          plants: [
            GuideMediaJob(
              id: 0,
              added: true,
              stamp: const GuideMediaStamp(plate: plate),
              download: const [plate],
              remove: const [],
            ),
          ],
        ),
      ),
    )));

    expect(find.text('Middle Europe · 1 plant · about 0 MB'), findsOneWidget);
    await tester.tap(find.text('Europe'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(guideOfflineRegionKey('11')),
        matching: find.text('On this phone'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an update sits under what is stored', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var updates = 0;
    const plate =
        GuideMediaFile(url: 'a/plate.webp', bytes: 2000000, hash: 'p');
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(
        stored: const GuideOfflineStored(regions: {'11'}),
        update: GuideOfflineUpdate(
          mark: 0,
          resumeMark: 1,
          plants: [
            GuideMediaJob(
              id: 0,
              added: false,
              stamp: GuideMediaStamp(plate: plate),
              download: [plate],
              remove: [],
            ),
          ],
        ),
      ),
      onUpdate: () async => updates++,
    )));

    expect(find.text('1 plant · about 2 MB'), findsOneWidget);
    await tester.tap(find.byKey(guideOfflineUpdateKey));
    await tester.pump();
    expect(updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without Field Guide the update opens Field Guide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    var updates = 0;
    const plate =
        GuideMediaFile(url: 'a/plate.webp', bytes: 2000000, hash: 'p');
    await tester.pumpWidget(_app(GuideOfflinePage(
      view: _view(
        canDownload: false,
        stored: const GuideOfflineStored(regions: {'11'}),
        update: GuideOfflineUpdate(
          mark: 0,
          resumeMark: 1,
          plants: [
            GuideMediaJob(
              id: 0,
              added: false,
              stamp: GuideMediaStamp(plate: plate),
              download: [plate],
              remove: [],
            ),
          ],
        ),
      ),
      onFieldGuide: () async => opened++,
      onUpdate: () async => updates++,
    )));

    expect(find.text('1 plant · about 2 MB'), findsOneWidget);
    await tester.tap(find.byKey(guideOfflineUpdateKey));
    await tester.pump();
    expect(opened, 1);
    expect(updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('person shows the same update size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Text(
        guideOfflineMenuText(
          context,
          const GuideOfflineHold(
            canDownload: true,
            everything: false,
            storedPlants: 1105,
            totalPlants: 1433,
            regionIds: ['11'],
            updateBytes: 2000000,
            updatePlants: 1,
          ),
        ),
      ),
    )));
    expect(
      find.text('Middle Europe · about 730 MB · Update about 2 MB'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

GuideOfflineView _view({
  bool canDownload = true,
  String? phoneRegionId,
  GuideOfflineStored stored = const GuideOfflineStored(),
  GuideOfflineUpdate update = GuideOfflineUpdate.empty,
}) {
  return GuideOfflineView(
    catalog: const GuideOfflineCatalog([
      {'11'},
      {'11', '75'},
      {'75'},
      {'90'},
    ]),
    canDownload: canDownload,
    stored: stored,
    phoneRegionId: phoneRegionId,
    update: update,
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
