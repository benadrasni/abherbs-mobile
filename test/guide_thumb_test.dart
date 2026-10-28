import 'dart:io';

import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const placeholder = Key('thumb-placeholder');

  tearDown(() {
    debugResolveThumb = null;
  });

  testWidgets('a loaded thumbnail stays up when its parent rebuilds',
      (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('guide-thumb'),
    );
    final photo = File('${dir!.path}/photo.png');
    await tester.runAsync(
      () => photo.writeAsBytes(img.encodePng(img.Image(width: 2, height: 2))),
    );
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    debugResolveThumb = (url, cover) async => photo;
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            builds++;
            return Column(
              children: [
                getImage(
                  'observations/photo.webp',
                  const ColoredBox(
                    key: placeholder,
                    color: Color(0xFFE7E0D4),
                  ),
                  cover: 'photos/cover.webp',
                  width: 118,
                  height: 118,
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('rebuild'),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(find.byKey(placeholder), findsOneWidget);

    await tester.pump();
    expect(find.byKey(placeholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    final shown = tester.widget<Image>(find.byType(Image));
    final provider = shown.image as FileImage;
    expect(provider.file.path, photo.path);

    await tester.tap(find.text('rebuild'));
    await tester.pump();

    expect(builds, greaterThan(1));
    expect(find.byKey(placeholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    final again = tester.widget<Image>(find.byType(Image)).image as FileImage;
    expect(again.file.path, photo.path);
  });

  testWidgets('a new fallback cover does not blank a photo already showing',
      (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('guide-thumb'),
    );
    final photo = File('${dir!.path}/photo.png');
    await tester.runAsync(
      () => photo.writeAsBytes(img.encodePng(img.Image(width: 2, height: 2))),
    );
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    debugResolveThumb = (url, cover) async => photo;

    Widget page(String? cover) {
      return MaterialApp(
        home: getImage(
          'observations/photo.webp',
          const ColoredBox(
            key: placeholder,
            color: Color(0xFFE7E0D4),
          ),
          cover: cover,
          width: 118,
          height: 118,
        ),
      );
    }

    await tester.pumpWidget(page(null));
    await tester.pump();
    expect(find.byKey(placeholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(page('photos/cover.webp'));

    // The new lookup is still running. The photo that was already up stays.
    expect(find.byKey(placeholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
