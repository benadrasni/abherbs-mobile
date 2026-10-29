import 'dart:async';
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

  testWidgets('a reused thumbnail drops the previous plant while the next loads',
      (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('guide-thumb'),
    );
    final first = File('${dir!.path}/first.png');
    final second = File('${dir.path}/second.png');
    await tester.runAsync(() async {
      final png = img.encodePng(img.Image(width: 2, height: 2));
      await first.writeAsBytes(png);
      await second.writeAsBytes(png);
    });
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    final pending = Completer<File?>();
    debugResolveThumb = (url, cover) {
      if (url.endsWith('second.webp')) return pending.future;
      return Future<File?>.value(first);
    };

    Widget page(String url) {
      return MaterialApp(
        home: getImage(
          url,
          const ColoredBox(
            key: placeholder,
            color: Color(0xFFE7E0D4),
          ),
          width: 118,
          height: 118,
        ),
      );
    }

    await tester.pumpWidget(page('observations/first.webp'));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as FileImage).file.path,
      first.path,
    );

    // Seen lately reuses the row, and the book toggles photo and plate.
    // The previous plant must not stay up while the new file loads.
    await tester.pumpWidget(page('observations/second.webp'));
    expect(find.byKey(placeholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    pending.complete(second);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(placeholder), findsNothing);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as FileImage).file.path,
      second.path,
    );
  });

  testWidgets('a photo saved after the first miss is shown on the next build',
      (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('guide-thumb'),
    );
    final photo = File('${dir!.path}/later.png');
    await tester.runAsync(
      () => photo.writeAsBytes(img.encodePng(img.Image(width: 2, height: 2))),
    );
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    File? saved;
    var lookups = 0;
    debugResolveThumb = (url, cover) async {
      lookups++;
      return saved;
    };

    Widget page() {
      return MaterialApp(
        home: getImage(
          'observations/photo.webp',
          const ColoredBox(
            key: placeholder,
            color: Color(0xFFE7E0D4),
          ),
          width: 118,
          height: 118,
        ),
      );
    }

    await tester.pumpWidget(page());
    await tester.pump();
    expect(lookups, 1);
    expect(_fileImage(tester), isNull);

    saved = photo;
    await tester.pumpWidget(page());
    await tester.pump();
    expect(lookups, 2);
    expect(_fileImage(tester)?.file.path, photo.path);
  });
}

FileImage? _fileImage(WidgetTester tester) {
  for (final image in tester.widgetList<Image>(find.byType(Image))) {
    final provider = image.image;
    if (provider is FileImage) return provider;
  }
  return null;
}
