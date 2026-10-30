import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const headers = 'plants_headers_v3';

  setUp(resetGuideSyncForTest);

  test('a kept path uses the listener and its child stays a server read', () {
    final generation = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, generation, applied: true);

    expect(guidePathKeptSynced(headers), isTrue);
    expect(guidePathKeptSynced('/$headers'), isTrue);
    expect(guidePathKeptSynced('$headers/12'), isFalse);

    final release = guideSyncBegin('/$headers', false);
    guideSyncFinish(headers, false, release, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('an older keep does not undo a newer release', () {
    final older = guideSyncBegin(headers, true);
    final newer = guideSyncBegin(headers, false);
    guideSyncFinish(headers, true, older, applied: true);
    expect(guidePathKeptSynced(headers), isTrue);

    guideSyncFinish(headers, false, newer, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('a late older keep does not put a released path back', () {
    final older = guideSyncBegin(headers, true);
    final newer = guideSyncBegin(headers, false);
    guideSyncFinish(headers, false, newer, applied: true);
    guideSyncFinish(headers, true, older, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('an older release does not undo a newer keep', () {
    final older = guideSyncBegin(headers, false);
    final newer = guideSyncBegin(headers, true);
    guideSyncFinish(headers, false, older, applied: true);
    guideSyncFinish(headers, true, newer, applied: true);
    expect(guidePathKeptSynced(headers), isTrue);
  });

  test('a failed keep drops the mark and a failed release leaves it', () {
    final failed = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, failed, applied: false);
    expect(guidePathKeptSynced(headers), isFalse);

    final kept = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, kept, applied: true);
    final release = guideSyncBegin(headers, false);
    guideSyncFinish(headers, false, release, applied: false);
    expect(guidePathKeptSynced(headers), isTrue);
  });
}
