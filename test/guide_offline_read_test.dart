import 'dart:async';
import 'dart:io';

import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a dead read uses the pack and says it came from the phone', () async {
    var pack = 0;
    final value = await guideReadOrPack(
      () async => 'server',
      () async {
        pack++;
        return 'pack';
      },
      phoneOnly: false,
      wait: const Duration(milliseconds: 200),
    );
    expect(value.value, 'server');
    expect(value.fromPhone, isFalse);
    expect(pack, 0);

    final fellBack = await guideReadOrPack(
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return 'server';
      },
      () async => 'pack',
      phoneOnly: false,
      wait: const Duration(milliseconds: 10),
      label: 'guide test',
    );
    expect(fellBack.value, 'pack');
    expect(fellBack.fromPhone, isTrue);

    final offline = await guideReadOrPack(
      () async => 'server',
      () async => 'phone',
      phoneOnly: true,
      label: 'guide test',
    );
    expect(offline.value, 'phone');
    expect(offline.fromPhone, isTrue);
  });

  test('a missing pack throws instead of an empty read', () async {
    await expectLater(
      guideReadOrPack<Object?>(
        () async => throw StateError('down'),
        () async => throw StateError('no pack'),
        phoneOnly: false,
        wait: const Duration(milliseconds: 20),
        label: 'guide test',
      ),
      throwsA(
        isA<StateError>()
            .having((error) => error.message, 'message', 'no pack'),
      ),
    );
  });

  test('a failed bloom read is not cached', () async {
    final cache = GuideBloomCache();
    var reads = 0;
    Future<Map<String, GuideHeaderBloom>> load() async {
      reads++;
      if (reads == 1) throw StateError('down');
      return {'1': const GuideHeaderBloom('Bellis perennis', 5, 9)};
    }

    await expectLater(cache.read(load), throwsA(isA<StateError>()));
    expect(cache.stored, isNull);
    final blooms = await cache.read(load);
    expect(blooms['1']!.name, 'Bellis perennis');
    expect(await cache.read(load), blooms);
    expect(reads, 2);
  });

  test('an empty header snapshot is a failed bloom read', () {
    final empty = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'plants_headers_v3 is empty',
      ),
    );
    expect(() => guideBloomsFromSnapshot(null), empty);
    expect(() => guideBloomsFromSnapshot('late'), empty);
    expect(() => guideBloomsFromSnapshot(<String, dynamic>{}), empty);

    final blooms = guideBloomsFromSnapshot({
      '1': {
        'name': 'Bellis perennis',
        'floweringFrom': 5,
        'floweringTo': 9,
      },
    });
    expect(blooms['1']!.name, 'Bellis perennis');
  });

  test('a non-map label snapshot is not cached', () async {
    expect(() => guideLabelsFromSnapshot(null), throwsStateError);
    expect(() => guideLabelsFromSnapshot('late'), throwsStateError);

    final cache = GuideLabelCache();
    var reads = 0;
    Future<Map<String, String>> read(String language) async {
      reads++;
      if (reads == 1) return guideLabelsFromSnapshot(null);
      return guideLabelsFromSnapshot({
        'Bellis perennis': {firebaseAttributeLabel: 'de-name'},
      });
    }

    await expectLater(cache.labels('de', read), throwsA(isA<StateError>()));
    expect(
      await cache.labels('de', read),
      {'Bellis perennis': 'de-name'},
    );
    expect(reads, 2);
  });

  test('a call site cannot pass get() as its pack', () {
    const passedAsPack = '''
guideReadOrPack(
  () async => (await ref.once()).snapshot.value,
  () async => (await ref.get()).value,
);
''';
    expect(packArguments(passedAsPack).single, contains('.get('));

    final packs = [
      for (final file in Directory('lib/data').listSync().whereType<File>())
        if (file.path.endsWith('.dart'))
          ...packArguments(file.readAsStringSync()),
    ];
    expect(packs, isNotEmpty);
    for (final pack in packs) {
      expect(pack.contains('.get('), isFalse, reason: pack);
      expect(pack.contains('.once('), isFalse, reason: pack);
    }
  });

  test('overlapping de, en, and de share one de load', () async {
    final cache = GuideLabelCache();
    final gates = <String, Completer<Map<String, String>>>{};
    var reads = 0;
    Future<Map<String, String>> read(String language) {
      reads++;
      final gate = Completer<Map<String, String>>();
      gates[language] = gate;
      return gate.future;
    }

    final german = cache.labels('de', read);
    final english = cache.labels('en', read);
    final germanAgain = cache.labels('de', read);
    expect(reads, 2);
    expect(identical(german, germanAgain), isTrue);

    gates['en']!.complete({'Bellis perennis': 'en-name'});
    expect(await english, {'Bellis perennis': 'en-name'});
    expect(await cache.labels('en', read), {'Bellis perennis': 'en-name'});
    expect(reads, 2);

    gates['de']!.complete({'Bellis perennis': 'de-name'});
    expect(await german, {'Bellis perennis': 'de-name'});
    expect(await germanAgain, {'Bellis perennis': 'de-name'});
    expect(await cache.labels('en', read), {'Bellis perennis': 'en-name'});
    expect(await cache.labels('de', read), {'Bellis perennis': 'de-name'});
    expect(reads, 2);
  });

  test('a failed label load is not stored', () async {
    final cache = GuideLabelCache();
    var reads = 0;
    Future<Map<String, String>> read(String language) async {
      reads++;
      if (reads == 1) throw StateError('down');
      return {'Bellis perennis': 'de-name'};
    }

    await expectLater(
      cache.labels('de', read),
      throwsA(isA<StateError>()),
    );
    expect(await cache.labels('de', read), {'Bellis perennis': 'de-name'});
    expect(reads, 2);
  });
}

/// Second positional argument of each [guideReadOrPack] call.
List<String> packArguments(String source) {
  final packs = <String>[];
  const name = 'guideReadOrPack';
  var i = 0;
  while (true) {
    final at = source.indexOf(name, i);
    if (at < 0) break;
    var j = at + name.length;
    if (j < source.length && source[j] == '<') {
      j = _skipNest(source, j, '<', '>');
    }
    j = _skipSpace(source, j);
    if (j >= source.length || source[j] != '(') {
      i = at + name.length;
      continue;
    }
    final args = _splitArgs(source, j);
    i = j + 1;
    if (args.isEmpty || args.first.trimLeft().startsWith('Future')) continue;
    if (args.length < 2) continue;
    packs.add(args[1].trim());
  }
  return packs;
}

int _skipSpace(String source, int j) {
  while (j < source.length &&
      (source[j] == ' ' ||
          source[j] == '\n' ||
          source[j] == '\r' ||
          source[j] == '\t')) {
    j++;
  }
  return j;
}

int _skipNest(String source, int open, String left, String right) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == left) depth++;
    if (char == right) {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return source.length;
}

List<String> _splitArgs(String source, int openParen) {
  final args = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var quote = '';
  for (var i = openParen; i < source.length; i++) {
    final char = source[i];
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == r'\' && i + 1 < source.length) {
        buffer.write(source[i + 1]);
        i++;
        continue;
      }
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      if (depth > 1) buffer.write(char);
      continue;
    }
    if (char == ')' || char == ']' || char == '}') {
      if (char == ')' && depth == 1) {
        args.add(buffer.toString());
        return args;
      }
      depth--;
      buffer.write(char);
      continue;
    }
    if (char == ',' && depth == 1) {
      args.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  return args;
}
