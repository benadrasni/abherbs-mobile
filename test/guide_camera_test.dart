import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/camera/camera_page.dart';
import 'package:abherbs_flutter/camera/guide_camera.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/camera/plant_id_search.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/camera/outside_page.dart';
import 'package:abherbs_flutter/key/results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a Plant.id tag uses the catalog language', () {
    expect(catalogLanguageCode('en-US'), 'en');
    expect(catalogLanguageCode('sk_SK'), 'sk');
    expect(catalogLanguageCode('nb-NO'), 'no');
    expect(catalogLanguageCode('zh-TW'), 'zh');
    expect(catalogLanguageCode('pt-BR'), 'pt');
    expect(catalogLanguageCode('pt'), 'pt');
  });

  test('location is asked once, then remembered', () async {
    expect(
      guideCameraPlace(
        locationRefused: false,
        fromLocation: false,
        locationAllowed: false,
      ),
      GuideCameraPlace.ask,
    );
    expect(
      guideCameraPlace(
        locationRefused: true,
        fromLocation: true,
        locationAllowed: true,
      ),
      GuideCameraPlace.declined,
    );
    expect(
      guideCameraPlace(
        locationRefused: false,
        fromLocation: true,
        locationAllowed: false,
      ),
      GuideCameraPlace.allowed,
    );
    expect(
      guideCameraPlace(
        locationRefused: false,
        fromLocation: false,
        locationAllowed: true,
      ),
      GuideCameraPlace.allowed,
    );

    var stored = const GuideResultPrefs(regionId: '11', wildOnly: true);
    bool? allowed;
    final placed = await allowGuideCameraLocation(
      locate: () async => '13',
      loadPrefs: () async => stored,
      savePrefs: (prefs) async => stored = prefs,
      saveAllowed: (value) async => allowed = value,
    );
    expect(placed, GuideCameraPlace.allowed);
    expect(stored.regionId, '13');
    expect(stored.fromLocation, isTrue);
    expect(stored.locationRefused, isFalse);
    expect(stored.wildOnly, isTrue);
    expect(allowed, isTrue);

    stored = const GuideResultPrefs(regionId: '11', fromLocation: true);
    allowed = null;
    final unmatched = await allowGuideCameraLocation(
      locate: () async => '',
      loadPrefs: () async => stored,
      savePrefs: (prefs) async => stored = prefs,
      saveAllowed: (value) async => allowed = value,
    );
    expect(unmatched, GuideCameraPlace.allowed);
    expect(stored.regionId, '11');
    expect(stored.fromLocation, isTrue);
    expect(stored.locationRefused, isFalse);
    expect(allowed, isTrue);

    stored = const GuideResultPrefs(regionId: '11', wildOnly: true);
    allowed = null;
    final refused = await allowGuideCameraLocation(
      locate: () async => throw const GuideLocationRefused(),
      loadPrefs: () async => stored,
      savePrefs: (prefs) async => stored = prefs,
      saveAllowed: (value) async => allowed = value,
    );
    expect(refused, GuideCameraPlace.declined);
    expect(stored.regionId, '11');
    expect(stored.locationRefused, isTrue);
    expect(stored.wildOnly, isTrue);
    expect(allowed, isFalse);

    expect(
      () => allowGuideCameraLocation(
        locate: () async => throw StateError('gps'),
        loadPrefs: () async => stored,
        savePrefs: (prefs) async => stored = prefs,
        saveAllowed: (value) async => allowed = value,
      ),
      throwsStateError,
    );

    stored = const GuideResultPrefs(regionId: '11', wildOnly: true);
    allowed = true;
    final declined = await declineGuideCameraLocation(
      loadPrefs: () async => stored,
      savePrefs: (prefs) async => stored = prefs,
      saveAllowed: (value) async => allowed = value,
    );
    expect(declined, GuideCameraPlace.declined);
    expect(stored.regionId, '11');
    expect(stored.locationRefused, isTrue);
    expect(stored.wildOnly, isTrue);
    expect(allowed, isFalse);
  });

  test('the meter follows the live allowance', () {
    final fieldGuide = guideCameraMeter(
      const GuideAllowance.unlimited(
        fieldGuide: true,
        unlimitedNames: true,
        noAds: true,
        seenSynced: true,
      ),
    );
    expect(fieldGuide.kind, GuideCameraMeterKind.fieldGuide);
    expect(fieldGuide.dotCount, 0);

    final photoSearch = guideCameraMeter(
      const GuideAllowance.unlimited(
        fieldGuide: false,
        unlimitedNames: true,
        noAds: false,
        seenSynced: false,
      ),
    );
    expect(photoSearch.kind, GuideCameraMeterKind.unlimited);
    expect(photoSearch.dotCount, 0);

    expect(
      guideCameraMeter(const GuideAllowance.guest()).kind,
      GuideCameraMeterKind.signIn,
    );

    final credits = guideCameraMeter(GuideAllowance.credits(3));
    expect(credits.dotCount, 5);
    expect(credits.filledDots, 3);
    expect(credits.namesLeft, 3);
    expect(guideCameraMeter(GuideAllowance.credits(9)).filledDots, 5);

    final month = guideCameraMeter(
      GuideAllowance.month(used: 2, fromAds: 0, now: DateTime(2026, 9)),
    );
    expect(month.filledDots, 3);
    expect(month.namesLeft, 3);

    expect(guideCameraCanCapture(GuideAllowance.credits(1)), isTrue);
    expect(guideCameraCanCapture(GuideAllowance.credits(0)), isFalse);
    expect(guideCameraCanCapture(const GuideAllowance.guest()), isFalse);
    expect(
      guideCameraCanCapture(
        GuideAllowance.month(used: 4, fromAds: 0, now: DateTime(2026, 9)),
      ),
      isTrue,
    );
    expect(
      guideCameraCanCapture(
        GuideAllowance.month(used: 5, fromAds: 0, now: DateTime(2026, 9)),
      ),
      isFalse,
    );

    expect(guideCameraOffersAd(GuideAllowance.credits(0)), isTrue);
    expect(guideCameraOffersAd(GuideAllowance.credits(2)), isFalse);
    expect(guideCameraOffersAd(const GuideAllowance.guest()), isFalse);
    expect(
      guideCameraCanCapture(
        GuideAllowance.month(used: 5, fromAds: 1, now: DateTime(2026, 9)),
      ),
      isTrue,
    );
    expect(
      guideCameraMeter(
        GuideAllowance.month(used: 5, fromAds: 1, now: DateTime(2026, 9)),
      ).namesLeft,
      1,
    );
    expect(
      guideCameraOffersAd(
        GuideAllowance.month(used: 5, fromAds: 1, now: DateTime(2026, 9)),
      ),
      isFalse,
    );
    expect(
      guideCameraOffersAd(
        GuideAllowance.month(used: 9, fromAds: 4, now: DateTime(2026, 9)),
      ),
      isTrue,
    );
    expect(
      guideCameraOffersAd(
        GuideAllowance.month(used: 5, fromAds: 5, now: DateTime(2026, 9)),
      ),
      isFalse,
    );
    expect(
      guideCameraNamesExhausted(
        GuideAllowance.month(used: 10, fromAds: 5, now: DateTime(2026, 9)),
      ),
      isTrue,
    );
    expect(
      guideCameraNamesExhausted(
        GuideAllowance.month(used: 5, fromAds: 5, now: DateTime(2026, 9)),
      ),
      isFalse,
    );
    expect(
      guideCameraNamesExhausted(
        GuideAllowance.month(used: 5, fromAds: 4, now: DateTime(2026, 9)),
      ),
      isFalse,
    );
  });

  test('a photo opens a species, a list, or Outside the book', () {
    expect(guideCameraConfidence(0.5), GuideCameraConfidence.likely);
    expect(guideCameraConfidence(0.49), GuideCameraConfidence.possible);
    expect(guideCameraConfidence(0.2), GuideCameraConfidence.possible);
    expect(guideCameraConfidence(0.19), GuideCameraConfidence.uncertain);
    expect(guideCameraConfidence(null), GuideCameraConfidence.uncertain);

    expect(guideCameraOutcome(const []).kind, GuideCameraOutcomeKind.notPlant);
    expect(
      guideCameraOutcome(const [
        GuideCameraHit(latin: '  '),
        GuideCameraHit(latin: '', path: ''),
      ]).kind,
      GuideCameraOutcomeKind.notPlant,
    );
    expect(
      guideCameraOutcome(const [
        GuideCameraHit(latin: 'Cystinarius', probability: 0.08),
      ], isPlant: false)
          .kind,
      GuideCameraOutcomeKind.notPlant,
    );

    final species = guideCameraOutcome(const [
      GuideCameraHit(latin: '', path: 'Bellis perennis'),
      GuideCameraHit(latin: 'Other', path: 'Other'),
    ]);
    expect(species.kind, GuideCameraOutcomeKind.species);
    expect(species.speciesName, 'Bellis perennis');
    expect(species.candidates.map((hit) => hit.path), ['Other']);

    final list = guideCameraOutcome(const [
      GuideCameraHit(latin: 'Bellis', path: 'Asteraceae/Bellis/'),
    ]);
    expect(list.kind, GuideCameraOutcomeKind.list);
    expect(list.listPath, 'Asteraceae/Bellis/');

    final outside = guideCameraOutcome(const [
      GuideCameraHit(latin: 'Rare plant', probability: 0.8),
      GuideCameraHit(latin: 'Bellis perennis', path: 'Bellis perennis'),
      GuideCameraHit(latin: 'Leucanthemum', path: 'Asteraceae/Leucanthemum/'),
      GuideCameraHit(
          latin: 'Matricaria chamomilla', path: 'Matricaria chamomilla'),
      GuideCameraHit(latin: 'Tanacetum vulgare', path: 'Tanacetum vulgare'),
    ]);
    expect(outside.kind, GuideCameraOutcomeKind.outside);
    expect(outside.leading?.latin, 'Rare plant');
    expect(
      outside.candidates.map(guideCameraSpeciesName),
      ['Bellis perennis', 'Matricaria chamomilla'],
    );
  });

  test('family, place, and observation keys stay plain', () async {
    expect(
      guideCameraFamilyLatin({
        'taxonomy': {'family': ' Asteraceae '},
      }),
      'Asteraceae',
    );
    expect(guideCameraFamilyLatin({'taxonomy': {}}), isNull);
    expect(guideCameraFamilyLatin(null), isNull);

    expect(guideObservationPlantKey('Bellis perennis'), 'Bellis perennis');
    expect(guideObservationPlantKey('A/B.C#D\$E[F]'), 'A_B_C_D_E_F_');
    expect(guideObservationPlantKey('   '), '_');

    expect(
      await guideCameraPlaceName(
        loadPrefs: () async => const GuideResultPrefs(
          regionId: '11',
          fromLocation: true,
        ),
        loadAllowed: () async => false,
        regionName: (id) => id == '11' ? 'Middle Europe' : '',
        noPlace: 'No place',
      ),
      'Middle Europe',
    );
    expect(
      await guideCameraPlaceName(
        loadPrefs: () async => const GuideResultPrefs(),
        loadAllowed: () async => false,
        regionName: (_) => 'Middle Europe',
        noPlace: 'No place',
      ),
      'No place',
    );
  });

  testWidgets('the viewfinder is dark and has no tab bar', (tester) async {
    await _show(
      tester,
      _page(
        allowance: const GuideAllowance.unlimited(
          fieldGuide: true,
          unlimitedNames: true,
          noAds: true,
          seenSynced: true,
        ),
      ),
    );

    expect(find.text('Flower and a leaf, in focus'), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-preview')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('guide-camera-preview'))),
      const Size(390, 844),
    );
    expect(find.text('Field Guide · unlimited'), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-close')), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-shutter')), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-roll')), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-key')), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-ask')), findsNothing);
    expect(find.byType(GuideCameraDot), findsNothing);
    expect(find.text('Find'), findsNothing);
    expect(find.text('Book'), findsNothing);
    expect(find.text('Seen'), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF0D0C0A),
    );

    final shutter =
        tester.getSize(find.byKey(const Key('guide-camera-shutter')));
    expect(shutter, const Size(76, 76));
    expect(
      tester.getSize(find.byKey(const Key('guide-camera-close'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(find.byKey(const Key('guide-camera-roll'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(find.byKey(const Key('guide-camera-key'))),
      const Size(48, 48),
    );
  });

  testWidgets('credits show five dots and the names still left',
      (tester) async {
    await _show(tester, _page(allowance: GuideAllowance.credits(3)));

    expect(find.text('3 names left'), findsOneWidget);
    final dots = tester.widgetList<GuideCameraDot>(find.byType(GuideCameraDot));
    expect(dots.length, 5);
    expect(dots.where((dot) => dot.filled).length, 3);
  });

  testWidgets('a guest is asked to sign in instead of taking a photo',
      (tester) async {
    var signedIn = 0;
    var picks = 0;
    await _show(
      tester,
      _page(
        onSignIn: () async => signedIn += 1,
        pickPhoto: (_) async {
          picks += 1;
          return '/tmp/shot.jpg';
        },
      ),
    );

    expect(find.text('Sign in to name a photo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(signedIn, 1);
    expect(picks, 0);
    expect(find.text('Naming…'), findsNothing);
  });

  testWidgets('location is offered once, then Allow hides it', (tester) async {
    var calls = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(2),
        place: GuideCameraPlace.ask,
        onAllow: () async {
          calls += 1;
          return GuideCameraPlace.allowed;
        },
      ),
    );

    expect(find.text('Add where you took it?'), findsOneWidget);
    expect(find.byKey(const Key('guide-camera-allow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-camera-allow')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(const Key('guide-camera-ask')), findsNothing);
  });

  testWidgets('Not now hides the location question', (tester) async {
    var calls = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(2),
        place: GuideCameraPlace.ask,
        onDecline: () async {
          calls += 1;
          return GuideCameraPlace.declined;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-not-now')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(const Key('guide-camera-ask')), findsNothing);
  });

  testWidgets('a location failure keeps the question', (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(2),
        place: GuideCameraPlace.ask,
        onAllow: () async => throw StateError('gps'),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-allow')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Couldn’t match this place to a floristic region.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('guide-camera-ask')), findsOneWidget);
  });

  testWidgets('no credits opens the limit sheet, including a rewarded ad',
      (tester) async {
    var ads = 0;
    var fieldGuide = 0;
    var keyed = 0;
    var picks = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(0),
        pickPhoto: (_) async {
          picks += 1;
          return '/tmp/shot.jpg';
        },
        onWatchAd: () async => ads += 1,
        onFieldGuide: () async => fieldGuide += 1,
        onKey: () => keyed += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(picks, 0);
    expect(find.text('No names left'), findsOneWidget);
    expect(find.text('You can still get a name today.'), findsOneWidget);
    expect(find.text('Watch a short ad'), findsOneWidget);
    expect(find.text('Field Guide · 7 days free'), findsOneWidget);
    expect(find.text('Key it out'), findsOneWidget);

    await tester.tap(find.text('Watch a short ad'));
    await tester.pumpAndSettle();
    expect(ads, 1);
    expect(find.text('No names left'), findsOneWidget);

    await tester.tap(find.text('Field Guide · 7 days free'));
    await tester.pumpAndSettle();
    expect(fieldGuide, 1);

    await tester.tap(find.text('Key it out'));
    await tester.pumpAndSettle();
    expect(keyed, 1);
  });

  testWidgets('a used-up month has no ad', (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.month(
          used: 10,
          fromAds: 5,
          now: DateTime(2026, 9),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(find.text('All ten names are used this month'), findsOneWidget);
    expect(
      find.text('Names come back next month. The key and the book stay open.'),
      findsOneWidget,
    );
    expect(find.text('Watch a short ad'), findsNothing);
    expect(find.text('Field Guide · 7 days free'), findsOneWidget);
    expect(find.text('Key it out'), findsOneWidget);
  });

  testWidgets('the shutter names a catalog species', (tester) async {
    final gate = Completer<GuideCameraOutcome>();
    GuideCameraSource? source;
    String? opened;
    var picks = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (value) async {
          picks += 1;
          source = value;
          return '/tmp/shot.jpg';
        },
        identify: (_) => gate.future,
        onOpenSpecies: (name) => opened = name,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pump();
    await tester.tap(find.text('Naming…'));
    await tester.pump();

    expect(find.text('Naming…'), findsOneWidget);
    expect(source, GuideCameraSource.camera);
    expect(picks, 1);

    gate.complete(const GuideCameraOutcome.species('Bellis perennis'));
    await tester.pumpAndSettle();

    expect(opened, 'Bellis perennis');
    expect(find.text('Naming…'), findsNothing);
  });

  test('a photo date is the EXIF clock, or nothing', () async {
    expect(
      guideCameraExifDate('2024:06:12 14:31:05'),
      DateTime(2024, 6, 12, 14, 31, 5),
    );
    expect(guideCameraExifDate('2024:06:12 14:31:05.12'),
        DateTime(2024, 6, 12, 14, 31, 5));
    expect(guideCameraExifDate(null), isNull);
    expect(guideCameraExifDate('not a date'), isNull);
    expect(guideCameraExifDate('2024:06:12'), isNull);

    final dir = await Directory.systemTemp.createTemp('wtf-photo-date');
    addTearDown(() => dir.delete(recursive: true));
    final dated = File('${dir.path}/dated.jpg');
    await dated.writeAsBytes(base64Decode(_datedJpeg));
    expect(
      await guideCameraPhotoTakenAt(dated.path),
      DateTime(2024, 6, 12, 14, 31, 5),
    );
    final plain = File('${dir.path}/plain.jpg');
    await plain.writeAsBytes(base64Decode(_plainJpeg));
    expect(await guideCameraPhotoTakenAt(plain.path), isNull);
    expect(await guideCameraPhotoTakenAt('${dir.path}/missing.jpg'), isNull);
  });

  test('a photo position is its EXIF GPS, or nothing', () async {
    expect(
        guidePhotoPosition(48.15, 17.11), (latitude: 48.15, longitude: 17.11));
    expect(
        guidePhotoPosition(-33.9, -70.6), (latitude: -33.9, longitude: -70.6));
    expect(guidePhotoPosition(0, 0), isNull);
    expect(guidePhotoPosition(double.nan, 17.11), isNull);
    expect(guidePhotoPosition(91, 17.11), isNull);
    expect(guidePhotoPosition(48.15, 181), isNull);

    final dir = await Directory.systemTemp.createTemp('wtf-photo-position');
    addTearDown(() => dir.delete(recursive: true));
    final dated = File('${dir.path}/dated.jpg');
    await dated.writeAsBytes(base64Decode(_datedJpeg));
    expect(await guideCameraPhotoPosition(dated.path), isNull);
    expect(await guideCameraPhotoPosition('${dir.path}/missing.jpg'), isNull);
  });

  testWidgets('naming a photo from the roll uses the photo date',
      (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (source) async {
          expect(source, GuideCameraSource.gallery);
          return '/tmp/roll.jpg';
        },
        photoTakenAt: (_) async => DateTime(2024, 6, 12, 14, 31, 5),
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.8),
          [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-roll')));
    await tester.pumpAndSettle();

    expect(find.text('Jun 12, 2024'), findsOneWidget);
    expect(find.textContaining('Jun 12, 2024, 2:31 PM'), findsOneWidget);
    expect(find.text('Just now'), findsNothing);
  });

  testWidgets('a shutter photo uses the current time', (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        photoTakenAt: (_) async => DateTime(2024, 6, 12, 14, 31, 5),
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.8),
          [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(find.text('Just now'), findsOneWidget);
    expect(find.text('Jun 12, 2024'), findsNothing);
  });

  group('the place saved with a photo', () {
    const photoGps = (latitude: 48.15, longitude: 17.11);
    const phoneGps = (latitude: 50.08, longitude: 14.42);

    Future<GuideOutsidePage> nameIt(
      WidgetTester tester, {
      required Key button,
      GuideCameraPlace place = GuideCameraPlace.allowed,
      GuidePhotoPosition? fromPhoto,
      void Function()? onPhone,
    }) async {
      await _show(
        tester,
        _page(
          allowance: GuideAllowance.credits(3),
          place: place,
          pickPhoto: (_) async => '/tmp/shot.jpg',
          photoTakenAt: (_) async => null,
          photoPosition: (_) async => fromPhoto,
          phonePosition: () async {
            onPhone?.call();
            return phoneGps;
          },
          identify: (_) async => const GuideCameraOutcome.outside(
            GuideCameraHit(latin: 'Rare plant', probability: 0.8),
            [],
          ),
        ),
      );
      await tester.tap(find.byKey(button));
      await tester.pumpAndSettle();
      return tester.widget<GuideOutsidePage>(find.byType(GuideOutsidePage));
    }

    testWidgets('a shutter photo without GPS uses the phone', (tester) async {
      final page = await nameIt(
        tester,
        button: const Key('guide-camera-shutter'),
      );
      expect(page.latitude, phoneGps.latitude);
      expect(page.longitude, phoneGps.longitude);
    });

    testWidgets('a shutter photo with GPS keeps its own', (tester) async {
      final page = await nameIt(
        tester,
        button: const Key('guide-camera-shutter'),
        fromPhoto: photoGps,
      );
      expect(page.latitude, photoGps.latitude);
      expect(page.longitude, photoGps.longitude);
    });

    testWidgets('a declined place never reads the phone', (tester) async {
      var asked = 0;
      final page = await nameIt(
        tester,
        button: const Key('guide-camera-shutter'),
        place: GuideCameraPlace.declined,
        onPhone: () => asked++,
      );
      expect(asked, 0);
      expect(page.latitude, 0);
      expect(page.longitude, 0);
    });

    testWidgets('a roll photo never uses the phone', (tester) async {
      var asked = 0;
      final page = await nameIt(
        tester,
        button: const Key('guide-camera-roll'),
        onPhone: () => asked++,
      );
      expect(asked, 0);
      expect(page.latitude, 0);
      expect(page.longitude, 0);
    });
  });

  testWidgets('a roll photo with no date uses the current time',
      (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/roll.jpg',
        photoTakenAt: (_) async => null,
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.8),
          [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-roll')));
    await tester.pumpAndSettle();

    expect(find.text('Just now'), findsOneWidget);
  });

  testWidgets('the photo roll opens a family list', (tester) async {
    String? opened;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (source) async {
          expect(source, GuideCameraSource.gallery);
          return '/tmp/roll.jpg';
        },
        photoTakenAt: (_) async => null,
        identify: (_) async =>
            const GuideCameraOutcome.list('Asteraceae/Bellis/'),
        onOpenList: (path) => opened = path,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-roll')));
    await tester.pumpAndSettle();

    expect(opened, 'Asteraceae/Bellis/');
  });

  testWidgets('a genus or family result opens the guide list', (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/roll.jpg',
        photoTakenAt: (_) async => null,
        identify: (_) async =>
            const GuideCameraOutcome.list('Asteraceae/Bellis/'),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-roll')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GuideResultsPage), findsOneWidget);
    expect(find.text('Bellis'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('Bellis')));
    expect(route?.settings.name, guideListRouteName);
  });

  testWidgets('a plant outside the book opens its page', (tester) async {
    String? opened;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(
            latin: 'Rare plant',
            vernacular: 'rare daisy',
            probability: 0.8,
          ),
          [
            GuideCameraHit(
              latin: 'Bellis perennis',
              vernacular: 'daisy',
              probability: 0.4,
              path: 'Bellis perennis',
            ),
          ],
        ),
        onOpenSpecies: (name) => opened = name,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide-outside-page')), findsOneWidget);
    expect(find.text('Rare plant'), findsOneWidget);
    expect(find.text('rare daisy'), findsOneWidget);
    expect(find.text('LIKELY'), findsOneWidget);
    expect(
      find.text(
        'We can name this one, but its page isn’t written yet. '
        'It’s in your Seen notebook either way.',
      ),
      findsOneWidget,
    );
    expect(find.text('In the book, and close'), findsOneWidget);
    expect(find.text('daisy'), findsOneWidget);
    expect(find.text('POSSIBLE'), findsOneWidget);
    expect(find.text('No place'), findsWidgets);
    expect(find.text('Saved to Seen · unconfirmed'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Full page ›'), 200);
    await tester.tap(find.text('Full page ›'));
    await tester.pumpAndSettle();
    expect(opened, 'Bellis perennis');
  });

  testWidgets('an empty result says it is not a plant', (tester) async {
    var keyed = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.notPlant(),
        onKey: () => keyed += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(find.text('That doesn’t look like a plant'), findsOneWidget);
    expect(
      find.text('This photo didn’t count. 3 names left.'),
      findsOneWidget,
    );
    expect(find.text('Naming…'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('That doesn’t look like a plant'), findsNothing);

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Key it out instead'));
    await tester.pumpAndSettle();
    expect(keyed, 1);
  });

  testWidgets('a failed name shows the error and leaves the viewfinder',
      (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => throw StateError('down'),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Couldn’t name this photo. Try again.'), findsOneWidget);
    expect(find.text('Naming…'), findsNothing);
    expect(find.text('Flower and a leaf, in focus'), findsOneWidget);
  });

  testWidgets('a discarded shot deletes the cache file that still has gps',
      (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('guide-discard-shot'),
    ))!;
    addTearDown(() => root.deleteSync(recursive: true));
    final cache = Directory('${root.path}/guide-pick')..createSync();
    final shot = File('${cache.path}/shot.jpg');
    final kept = File('${root.path}/kept.jpg')..writeAsBytesSync([5, 6]);

    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => shot.path,
        identify: (_) async => const GuideCameraOutcome.notPlant(),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('That doesn’t look like a plant'), findsOneWidget);

    // Written after the sheet is up. Building a frame of this file would
    // decode it and stall the test; discard unlinks it before the next frame.
    shot.writeAsBytesSync([1, 2, 3, 4]);
    expect(shot.existsSync(), isTrue);

    await tester.tap(find.text('Try again'));
    expect(shot.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
    await tester.pump();
  });

  testWidgets('a cancelled photo does not start naming', (tester) async {
    var identified = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => null,
        identify: (_) async {
          identified += 1;
          return const GuideCameraOutcome.notPlant();
        },
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();

    expect(identified, 0);
    expect(find.text('Naming…'), findsNothing);
  });

  test('a guest has one free name until it is used', () {
    const free = GuideAllowance.guest(free: true);
    expect(guideCameraCanCapture(free), isTrue);
    expect(guideCameraMeter(free).kind, GuideCameraMeterKind.namesLeft);
    expect(guideCameraMeter(free).namesLeft, 1);
    expect(guideCameraOffersAd(free), isFalse);

    const used = GuideAllowance.guest();
    expect(guideCameraCanCapture(used), isFalse);
    expect(guideCameraMeter(used).kind, GuideCameraMeterKind.signIn);

    final live = guideLiveAllowance(
      signedIn: false,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: false,
      guestFree: true,
      now: DateTime(2026, 9, 30),
    );
    expect(live.kind, GuideAllowanceKind.guest);
    expect(live.namesLeft, 1);
  });

  test('a reinstall does not keep the previous phone unlimited', () {
    Purchases.namesReady = false;
    Purchases.hasOldVersion = true;
    expect(Purchases.namesUnlimited, isFalse);
    expect(Purchases.namesFieldGuide, isFalse);
    Purchases.holdNamesFor('account');
    expect(Purchases.namesReady, isFalse);
    Purchases.finishNames();
    expect(Purchases.namesUnlimited, isTrue);
    Purchases.holdNamesFor('account');
    expect(Purchases.namesReady, isTrue);
    Purchases.hasOldVersion = false;
    Purchases.holdNamesFor(null);
    Purchases.namesReady = false;
  });

  test('switching accounts drops the previous products before names are ready',
      () {
    Purchases.holdNamesFor(null);
    Purchases.replaceAccountProducts({fieldGuideYearly});
    Purchases.finishNames();
    expect(Purchases.owns(fieldGuideYearly), isTrue);
    expect(Purchases.namesFieldGuide, isTrue);

    expect(Purchases.holdNamesFor('other-account'), isTrue);
    expect(Purchases.namesReady, isFalse);
    expect(Purchases.accountProducts, isEmpty);
    expect(Purchases.owns(fieldGuideYearly), isFalse);
    expect(Purchases.namesFieldGuide, isFalse);

    Purchases.replaceAccountProducts({fieldGuideMonthly});
    Purchases.finishNames();
    expect(Purchases.namesFieldGuide, isTrue);
    expect(Purchases.holdNamesFor('other-account'), isFalse);
    expect(Purchases.namesReady, isTrue);
    expect(Purchases.owns(fieldGuideMonthly), isTrue);

    Purchases.holdNamesFor(null);
    Purchases.clearAccountProducts();
    Purchases.namesReady = false;
  });

  testWidgets('a guest names one photo, then the server asks for sign-in',
      (tester) async {
    var signIns = 0;
    var opened = '';
    var calls = 0;
    await _show(
      tester,
      _page(
        allowance: const GuideAllowance.guest(free: true),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async {
          calls += 1;
          return calls == 1
              ? const GuideCameraOutcome.species('Bellis perennis')
              : const GuideCameraOutcome.refused(GuideCameraOutcomeKind.signIn);
        },
        onOpenSpecies: (name) => opened = name,
        onSignIn: () async => signIns += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    expect(opened, 'Bellis perennis');
    expect(signIns, 0);

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    expect(signIns, 1);
    expect(find.text('That doesn’t look like a plant'), findsNothing);
  });

  testWidgets('a server refusal for no names opens the limit sheet',
      (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(1),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async =>
            const GuideCameraOutcome.refused(GuideCameraOutcomeKind.limit),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    expect(find.text('No names left'), findsOneWidget);
  });

  testWidgets('too soon, the same photo, and a paused day say so and clear',
      (tester) async {
    final answers = [
      GuideCameraOutcomeKind.tooSoon,
      GuideCameraOutcomeKind.samePhoto,
      GuideCameraOutcomeKind.pausedToday,
    ];
    var index = 0;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => GuideCameraOutcome.refused(answers[index++]),
      ),
    );

    for (final text in [
      'Wait a moment, then take the next photo.',
      'This photo was already checked. Take a new one closer to the plant.',
      'Photo names are paused for today. The key still works.',
    ]) {
      await tester.tap(find.byKey(const Key('guide-camera-shutter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(text), findsOneWidget);
      expect(find.text('Naming…'), findsNothing);
      expect(find.text('Flower and a leaf, in focus'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(GuideCameraPage)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a not-a-plant photo past the free ones says it counted',
      (tester) async {
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(2),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.notPlant(counted: true),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    expect(find.text('That doesn’t look like a plant'), findsOneWidget);
    expect(
      find.text(
        'Several photos this month weren’t plants, so this one counted. '
        '2 names left.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('close leaves and the key returns to Find', (tester) async {
    var closed = 0;
    var tab = -1;
    final previous = GuideTabs.show;
    GuideTabs.show = (index) => tab = index;
    addTearDown(() => GuideTabs.show = previous);

    await _show(
      tester,
      Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideHabitatRouteName),
                    builder: (_) => const Text('habitat'),
                  ),
                );
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideSearchRouteName),
                    builder: (_) => const Text('search'),
                  ),
                );
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideCameraRouteName),
                    builder: (_) => _page(
                      allowance: GuideAllowance.credits(2),
                      onClose: () => closed += 1,
                    ),
                  ),
                );
              },
              child: const Text('Find'),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-camera-close')));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('Flower and a leaf, in focus'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-camera-key')));
    await tester.pumpAndSettle();

    expect(tab, 0);
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('habitat'), findsNothing);
    expect(find.text('search'), findsNothing);
    expect(find.text('Flower and a leaf, in focus'), findsNothing);
  });

  testWidgets('Outside the book shows the family and can search the book',
      (tester) async {
    var searched = 0;
    String? saved;
    GuideCameraDraft? draft;
    await _show(
      tester,
      Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideOutsideRouteName),
                    builder: (_) => GuideOutsidePage(
                      outcome: const GuideCameraOutcome.outside(
                        GuideCameraHit(
                          latin: 'Tanacetum corymbosum',
                          probability: 0.8,
                          familyLatin: 'Asteraceae',
                          familyLabel: 'daisy family',
                        ),
                        [
                          GuideCameraHit(
                            latin: 'Leucanthemum vulgare',
                            vernacular: 'oxeye daisy',
                            probability: 0.4,
                            path: 'Leucanthemum vulgare',
                          ),
                        ],
                      ),
                      when: DateTime(2026, 9, 30, 14, 31),
                      place: 'Middle Europe',
                      latitude: 48.15,
                      longitude: 17.11,
                      onSave: (value) async {
                        saved = value.plant;
                        draft = value;
                        return 'obs-1';
                      },
                      onSearch: () => searched += 1,
                    ),
                  ),
                );
              },
              child: const Text('open outside'),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('open outside'));
    await tester.pumpAndSettle();

    expect(find.text('Tanacetum corymbosum'), findsOneWidget);
    expect(find.text('daisy family · Asteraceae'), findsOneWidget);
    expect(find.text('Sep 30, 2026'), findsOneWidget);
    expect(find.textContaining('Sep 30, 2026, 2:31 PM'), findsOneWidget);
    expect(find.text('Middle Europe'), findsWidgets);
    expect(find.text('Saved to Seen · unconfirmed'), findsOneWidget);
    expect(find.textContaining('Photo,'), findsOneWidget);
    expect(saved, 'Tanacetum corymbosum');
    expect(draft?.latitude, 48.15);
    expect(draft?.longitude, 17.11);

    await tester.scrollUntilVisible(
      find.byKey(const Key('guide-outside-another')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-outside-another')));
    await tester.pumpAndSettle();
    expect(find.text('Which one is it?'), findsOneWidget);
    expect(
      find.text('Plant.id’s other candidates for this photo.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('guide-outside-search')));
    await tester.pumpAndSettle();
    expect(searched, 1);
    expect(find.text('Which one is it?'), findsNothing);
    expect(find.byKey(const Key('guide-outside-page')), findsOneWidget);
  });

  testWidgets('keeping an outside name opens Seen', (tester) async {
    var seen = 0;
    final previousShow = GuideTabs.showSeen;
    final previousRefresh = GuideTabs.refreshSeen;
    GuideTabs.showSeen = () => seen += 1;
    GuideTabs.refreshSeen = () {};
    addTearDown(() {
      GuideTabs.showSeen = previousShow;
      GuideTabs.refreshSeen = previousRefresh;
    });

    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.8),
          [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guide-outside-keep')));
    await tester.tap(find.byKey(const Key('guide-outside-keep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final month = DateFormat.MMMM('en').format(DateTime.now());
    expect(find.text('Confirmed. In Seen for $month.'), findsOneWidget);
    expect(seen, 1);
    _clearSnack(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-outside-page')), findsNothing);
  });

  testWidgets('deleting an outside name opens Seen', (tester) async {
    var seen = 0;
    final previousShow = GuideTabs.showSeen;
    GuideTabs.showSeen = () => seen += 1;
    addTearDown(() => GuideTabs.showSeen = previousShow);

    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.6),
          [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guide-outside-delete')));
    await tester.tap(find.byKey(const Key('guide-outside-delete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Deleted from Seen.'), findsOneWidget);
    expect(seen, 1);
    _clearSnack(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('choosing another candidate confirms that species',
      (tester) async {
    String? opened;
    await _show(
      tester,
      _page(
        allowance: GuideAllowance.credits(3),
        pickPhoto: (_) async => '/tmp/shot.jpg',
        identify: (_) async => const GuideCameraOutcome.outside(
          GuideCameraHit(latin: 'Rare plant', probability: 0.8),
          [
            GuideCameraHit(
              latin: 'Bellis perennis',
              vernacular: 'daisy',
              probability: 0.4,
              path: 'Bellis perennis',
            ),
          ],
        ),
        onOpenSpecies: (name) => opened = name,
      ),
    );

    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('guide-outside-another')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-outside-another')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, 'Bellis perennis');
    expect(find.text('Changed and confirmed.'), findsOneWidget);
    _clearSnack(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-outside-page')), findsNothing);
  });

  testWidgets('closing Outside the book returns to Find', (tester) async {
    var tab = -1;
    final previous = GuideTabs.show;
    GuideTabs.show = (index) => tab = index;
    addTearDown(() => GuideTabs.show = previous);

    await _show(
      tester,
      Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideHabitatRouteName),
                    builder: (_) => const Text('habitat'),
                  ),
                );
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideSearchRouteName),
                    builder: (_) => const Text('search'),
                  ),
                );
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: guideCameraRouteName),
                    builder: (_) => _page(
                      allowance: GuideAllowance.credits(2),
                      pickPhoto: (_) async => '/tmp/shot.jpg',
                      identify: (_) async => const GuideCameraOutcome.outside(
                        GuideCameraHit(latin: 'Rare plant', probability: 0.8),
                        [],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Find'),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-camera-shutter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-outside-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-outside-close')));
    await tester.pumpAndSettle();

    expect(tab, 0);
    expect(find.text('Find'), findsOneWidget);
    expect(find.byKey(const Key('guide-outside-page')), findsNothing);
    expect(find.text('Flower and a leaf, in focus'), findsNothing);
    expect(find.text('habitat'), findsNothing);
    expect(find.text('search'), findsNothing);
  });
}

void _clearSnack(WidgetTester tester) {
  final pages = find.byType(GuideCameraPage);
  if (pages.evaluate().isEmpty) return;
  ScaffoldMessenger.of(tester.element(pages.first)).removeCurrentSnackBar();
}

GuideCameraPage _page({
  GuideAllowance allowance = const GuideAllowance.guest(),
  GuideCameraPlace place = GuideCameraPlace.allowed,
  Future<GuideCameraPlace> Function()? onAllow,
  Future<GuideCameraPlace> Function()? onDecline,
  Future<String?> Function(GuideCameraSource source)? pickPhoto,
  Future<GuideCameraOutcome> Function(String path)? identify,
  Future<DateTime?> Function(String path)? photoTakenAt,
  Future<GuidePhotoPosition?> Function(String path)? photoPosition,
  Future<GuidePhotoPosition?> Function()? phonePosition,
  Future<void> Function()? onWatchAd,
  Future<void> Function()? onSignIn,
  Future<void> Function()? onFieldGuide,
  void Function(String name)? onOpenSpecies,
  void Function(String path)? onOpenList,
  VoidCallback? onKey,
  VoidCallback? onClose,
  WidgetBuilder livePreview = _standInPreview,
}) {
  return GuideCameraPage(
    allowance: allowance,
    place: place,
    onAllow: onAllow,
    onDecline: onDecline,
    pickPhoto: pickPhoto,
    identify: identify,
    photoTakenAt: photoTakenAt,
    photoPosition: photoPosition ?? (_) async => null,
    phonePosition: phonePosition ?? () async => null,
    onWatchAd: onWatchAd ?? () async {},
    onSignIn: onSignIn,
    onFieldGuide: onFieldGuide,
    onOpenSpecies: onOpenSpecies,
    onOpenList: onOpenList,
    onKey: onKey,
    onClose: onClose,
    livePreview: livePreview,
  );
}

const _datedJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/4QBoRXhpZgAATU0AKgAAAAgAAgEyAAIAAAAUAAAAJodpAAQAAAABAAAAOgAAAAAyMDI0OjA2OjEyIDE0OjMxOjA1AAABkAMAAgAAABQAAABMAAAAADIwMjQ6MDY6MTIgMTQ6MzE6MDUA/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3KSwwMTQ0NB8nOT04MjwuMzQy/9sAQwEJCQkMCwwYDQ0YMiEcITIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy/8AAEQgAEAAQAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8A56iiivNPkD//2Q==';

const _plainJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAQABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDxOiiigD//2Q==';

Widget _standInPreview(BuildContext context) {
  return const ColoredBox(
    key: Key('guide-camera-preview'),
    color: Color(0xFF123456),
  );
}

Future<void> _show(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}
